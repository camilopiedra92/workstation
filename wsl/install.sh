#!/usr/bin/env bash
# Rebuilds the development environment inside Ubuntu on WSL2.
#
# Usage:  git clone <repo> ~/workstation && ~/workstation/wsl/install.sh
#
# The Windows host is not this script's business: it is declared in
# windows/configuration.winget and applied with `winget configure` before this
# runs. This script assumes Ubuntu exists and configures what is inside it.
set -euo pipefail

WSL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }

# --- 1. WSL interop, narrowed -------------------------------------------------
# Windows PATH interop puts roughly forty Windows directories into every shell.
# It is a correctness problem before it is a speed one: every file under /mnt/c
# is executable as far as Linux is concerned, and mise's Windows shims live
# there, so a shimmed tool found on that PATH runs a Windows script inside Linux.
# The Windows commands this environment actually calls are aliased individually
# in .zshrc.
log "Narrowing WSL interop"
if ! grep -q 'appendWindowsPath' /etc/wsl.conf 2> /dev/null; then
  sudo tee -a /etc/wsl.conf > /dev/null << 'EOF'

[interop]
appendWindowsPath = false
EOF
  echo "    /etc/wsl.conf updated -- takes effect after 'wsl --shutdown'"
fi

# --- 2. apt packages ----------------------------------------------------------
log "Installing apt packages"
sudo apt-get update -qq
# shellcheck disable=SC2046
sudo apt-get install -y $(sed 's/#.*//' "$WSL_DIR/apt-packages.txt" | grep -v '^\s*$')

# --- 3. mise ------------------------------------------------------------------
if ! command -v mise > /dev/null 2>&1; then
  log "Installing mise"
  curl -fsSL https://mise.run | sh
fi
export PATH="$HOME/.local/bin:$PATH"

# --- 4. Symlinks --------------------------------------------------------------
log "Linking configuration"
link() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  # If a real file already exists (not a symlink), back it up before replacing it
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    mv "$dest" "$dest.backup.$(date +%Y%m%d%H%M%S)"
    echo "    backed up: $dest"
  fi
  ln -sfn "$src" "$dest"
  echo "    $dest -> $src"
}

# .zshenv is linked twice, to the same file, because zsh reads exactly one of the
# two depending on how the shell started -- never both. See the file's own
# header. `typeset -U path` is what makes reading it twice safe.
link "$WSL_DIR/zsh/.zshenv" "$HOME/.zshenv"
link "$WSL_DIR/zsh/.zshenv" "$XDG_CONFIG_HOME/zsh/.zshenv"
link "$WSL_DIR/zsh/.zshrc" "$XDG_CONFIG_HOME/zsh/.zshrc"
link "$WSL_DIR/zsh/.zsh_plugins.txt" "$XDG_CONFIG_HOME/zsh/.zsh_plugins.txt"
link "$WSL_DIR/starship.toml" "$XDG_CONFIG_HOME/starship.toml"
link "$WSL_DIR/mise/config.toml" "$XDG_CONFIG_HOME/mise/config.toml"
link "$WSL_DIR/git/config" "$XDG_CONFIG_HOME/git/config"
link "$WSL_DIR/git/ignore" "$XDG_CONFIG_HOME/git/ignore"
link "$WSL_DIR/claude/statusline.sh" "$HOME/.claude/statusline.sh"
link "$WSL_DIR/claude/subagent-statusline.sh" "$HOME/.claude/subagent-statusline.sh"
link "$WSL_DIR/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"

# git reads ~/.gitconfig AND ~/.config/git/config, and the legacy file wins. A
# leftover there means the linked config is read and then overruled.
#
# This is a bare AND-list, not an `if`, and that is deliberate: under
# `set -euo pipefail` it still does not abort when the file is absent, because
# `set -e` only inspects the exit status of the last command in an AND-OR
# list, not any command that failed earlier in it. Tested, not assumed --
# leave this as an AND-list.
[ -e "$HOME/.gitconfig" ] && [ ! -L "$HOME/.gitconfig" ] && {
  mv "$HOME/.gitconfig" "$HOME/.gitconfig.backup.$(date +%Y%m%d%H%M%S)"
  echo "    removed legacy ~/.gitconfig (it would have overruled the linked one)"
}

mkdir -p "$XDG_STATE_HOME/zsh"

# --- 5. Git identity ----------------------------------------------------------
# Outside the repo, so the repo can be public and each machine uses its own.
if [ ! -f "$XDG_CONFIG_HOME/git/config.local" ]; then
  log "Creating git identity file (fill it in)"
  cat > "$XDG_CONFIG_HOME/git/config.local" << 'EOF'
[user]
	name = CHANGE ME
	email = change@me.invalid
EOF
  echo "    $XDG_CONFIG_HOME/git/config.local"
fi

# --- 6. Hooks -----------------------------------------------------------------
git -C "$(dirname "$WSL_DIR")" config core.hooksPath githooks

# --- 7. Runtimes and tools ----------------------------------------------------
log "Installing runtimes and tools with mise"
mise install
mise reshim

# Everything mise manages lives behind shims, and the PATH line in step 3 only
# covers mise's own binary. Without this, the very next step -- which installs
# Python CLIs with uv, and uv is one of the tools mise just installed -- fails
# with `uv: command not found` and takes the whole script down with it.
#
# wsl/zsh/.zshenv puts this on PATH for interactive shells. This script is not
# one, so it has to do it for itself.
export PATH="$XDG_DATA_HOME/mise/shims:$PATH"

# --- 8. Python CLIs -----------------------------------------------------------
# uv tool has no manifest of its own, which is why uv-tools.txt exists.
log "Installing Python CLIs with uv"
while read -r line; do
  line=${line%%#*}
  [ -z "${line// /}" ] && continue
  read -r name ref <<< "$line"
  if uv tool list 2> /dev/null | grep -q "^$name "; then
    echo "    $name already installed"
  else
    echo "    installing $name from $ref"
    uv tool install "$ref"
  fi
done < "$WSL_DIR/uv-tools.txt"

# --- 9. zsh plugins -----------------------------------------------------------
# wsl/zsh/.zshrc sources antidote from exactly this path. The two files have to
# agree and only these comments say so -- on the Mac a package manager owned
# the location, here nothing does.
if [ ! -d "$XDG_DATA_HOME/antidote" ]; then
  log "Installing antidote"
  git clone --depth=1 https://github.com/mattmc3/antidote.git "$XDG_DATA_HOME/antidote"
fi

# --- 10. Login shell ----------------------------------------------------------
if [ "$SHELL" != "$(command -v zsh)" ]; then
  log "Setting zsh as the login shell"
  sudo chsh -s "$(command -v zsh)" "$USER"
fi

# --- 11. VS Code remote settings ---------------------------------------------
# Copied rather than linked: VS Code Server rewrites this file when settings are
# changed through the UI, and a symlink would end up overwritten.
if [ -d "$HOME/.vscode-server" ]; then
  log "Applying VS Code remote settings"
  mkdir -p "$HOME/.vscode-server/data/Machine"
  cp "$WSL_DIR/vscode/settings.json" "$HOME/.vscode-server/data/Machine/settings.json"
else
  echo "    .vscode-server not present yet -- connect once from VS Code, then re-run"
fi

log "Done. Open a new shell, or run: exec zsh"
