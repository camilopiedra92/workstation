#!/usr/bin/env bash
# Rebuilds the development environment inside Ubuntu on WSL2.
#
# Usage:  git clone <repo> ~/workstation && ~/workstation/wsl/install.sh
#         ~/workstation/wsl/install.sh --links-only
#
# The Windows host is not this script's business: it is declared in
# windows/configuration.winget and applied with `winget configure` before this
# runs. This script assumes Ubuntu exists and configures what is inside it.
#
# --links-only exists for check.sh. The full script installs packages, downloads
# runtimes and edits /etc/wsl.conf and the login shell -- none of which belongs
# in a check that the pre-commit hook runs on every commit, and none of which a
# temporary HOME can sandbox, because sudo does not care about $HOME.
#
# What the check actually asserts is that link() is idempotent, which is the
# half that respects $HOME. This flag makes the code match the claim instead of
# doing far more and verifying far less: it runs only the symlinks and the git
# identity file, and skips apt, mise, uv, the Claude Code settings merge (it
# needs jq, which comes from mise), antidote, chsh, /etc/wsl.conf and
# core.hooksPath -- everything with a sudo, a network fetch, or a real-system
# side effect.
set -euo pipefail

LINKS_ONLY=0
case "${1:-}" in
  "") ;;
  --links-only) LINKS_ONLY=1 ;;
  *)
    echo "usage: $0 [--links-only]" >&2
    exit 2
    ;;
esac

WSL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }

if [ "$LINKS_ONLY" -eq 0 ]; then
  # --- 1. WSL interop, narrowed -----------------------------------------------
  # Windows PATH interop puts roughly forty Windows directories into every
  # shell. It is a correctness problem before it is a speed one: every file
  # under /mnt/c is executable as far as Linux is concerned, and mise's Windows
  # shims live there, so a shimmed tool found on that PATH runs a Windows
  # script inside Linux. The Windows commands this environment actually calls
  # are aliased individually in .zshrc.
  log "Narrowing WSL interop"
  # Anchored to an *uncommented* assignment: a bare `grep -q appendWindowsPath`
  # also matches `# appendWindowsPath = true` commented out by hand, and would
  # then report the step already done while interop stayed wide -- exactly the
  # failure this step exists to prevent.
  if ! grep -qE '^[[:space:]]*appendWindowsPath' /etc/wsl.conf 2> /dev/null; then
    # Appends a second [interop] section if one already exists elsewhere in the
    # file. WSL tolerates duplicate sections in wsl.conf (last one wins) --
    # accepted here rather than parsed around, since a hand-edited wsl.conf is
    # rare enough that a merge is not worth the added fragility.
    sudo tee -a /etc/wsl.conf > /dev/null << 'EOF'

[interop]
appendWindowsPath = false
EOF
    echo "    /etc/wsl.conf updated -- takes effect after 'wsl --shutdown'"
  fi

  # --- 2. apt packages --------------------------------------------------------
  # Docker's packages are not in Ubuntu's archive, so its repository has to be
  # registered before the install below reads apt-packages.txt, which names
  # them. Order is the whole point of putting this here rather than in a later
  # step: get it wrong and the installer still works on a machine that already
  # has Docker, and fails on the clean one it exists to rebuild.
  #
  # Both files are vendored under wsl/apt/ rather than fetched. A key pulled
  # over the network at install time is trusted because it arrived, which is
  # the same reasoning ci.yml rejects for the binaries it checksums. Vendored,
  # the bytes apt trusts are in git, and any change to them is a diff somebody
  # reviews. Verified when it was added: fingerprint
  # 9DC858229FC7DD38854AE2D88D81803C0EBFCD88, uid "Docker Release (CE deb)".
  #
  # install(1) rather than cp+chmod: one call, permissions stated rather than
  # inherited from whatever umask this runs under, and re-running it changes
  # nothing observable.
  log "Registering the Docker apt repository"
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo install -m 0644 "$WSL_DIR/apt/docker.asc" /etc/apt/keyrings/docker.asc
  sudo install -m 0644 "$WSL_DIR/apt/docker.sources" /etc/apt/sources.list.d/docker.sources

  log "Installing apt packages"
  sudo apt-get update -qq
  # shellcheck disable=SC2046
  sudo apt-get install -y $(sed 's/#.*//' "$WSL_DIR/apt-packages.txt" | grep -v '^\s*$')

  # --- 3. mise -----------------------------------------------------------------
  # PATH is widened before the probe below, not after: mise installs into
  # $HOME/.local/bin, and probing command -v before that directory is on PATH
  # means a second run never finds an already-installed mise -- and re-runs
  # curl | sh over the network for a tool that is already there, which is
  # exactly the "second run changes something" the idempotency check exists to
  # catch.
  export PATH="$HOME/.local/bin:$PATH"
  if ! command -v mise > /dev/null 2>&1; then
    log "Installing mise"
    curl -fsSL https://mise.run | sh
  fi
fi

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
# The values below are placeholders, not this machine's identity: this script
# is itself tracked in the repo it writes them from, and a real name and
# address committed here would ship in every clone.
if [ ! -f "$XDG_CONFIG_HOME/git/config.local" ]; then
  log "Creating the git identity file -- EDIT IT before your first commit"
  cat > "$XDG_CONFIG_HOME/git/config.local" << 'EOF'
# Your git identity. This file is deliberately outside the repo so the repo can
# be public and each machine can carry its own name and address.
#
# git accepts any string here and will commit with these placeholders
# unmodified, so nothing stops you at commit time. .invalid is the TLD
# reserved for exactly this case, so a forgotten placeholder fails visibly if
# anything ever tries to mail this address, rather than reaching someone real.
[user]
	name = CHANGE ME
	email = change@me.invalid
EOF
  echo "    $XDG_CONFIG_HOME/git/config.local -- edit this before committing"
fi

if [ "$LINKS_ONLY" -eq 0 ]; then
  # --- 6. Hooks ----------------------------------------------------------------
  git -C "$(dirname "$WSL_DIR")" config core.hooksPath githooks

  # --- 7. Runtimes and tools ----------------------------------------------------
  log "Installing runtimes and tools with mise"
  mise install
  mise reshim

  # Everything mise manages lives behind shims, and the PATH line in step 3
  # only covers mise's own binary. Without this, the very next step -- which
  # installs Python CLIs with uv, and uv is one of the tools mise just
  # installed -- fails with `uv: command not found` and takes the whole script
  # down with it.
  #
  # wsl/zsh/.zshenv puts this on PATH for interactive shells. This script is
  # not one, so it has to do it for itself.
  export PATH="$XDG_DATA_HOME/mise/shims:$PATH"

  # --- 8. Python CLIs -----------------------------------------------------------
  # uv tool has no manifest of its own, which is why uv-tools.txt exists.
  log "Installing Python CLIs with uv"
  # Read from fd 3, not stdin: a command inside this loop that ever reads
  # stdin (uv tool install does not today) would otherwise consume the rest of
  # uv-tools.txt instead of whatever it meant to read.
  while read -r -u 3 line; do
    # Strip only a comment that begins a field -- preceded by whitespace or at
    # line start -- not a bare `#` fused onto a token. pip/uv VCS references
    # commonly carry #egg= or #subdirectory= fragments, and truncating at any
    # `#` would silently install a different, valid-looking ref instead of
    # failing loud.
    line=$(printf '%s' "$line" | sed -E 's/(^|[[:space:]])#.*$//')
    [ -z "${line// /}" ] && continue
    read -r name ref <<< "$line"
    if uv tool list 2> /dev/null | grep -q "^$name "; then
      echo "    $name already installed"
    else
      echo "    installing $name from $ref"
      uv tool install "$ref"
    fi
  done 3< "$WSL_DIR/uv-tools.txt"

  # --- 9. Claude Code settings ---------------------------------------------------
  # Merged with jq rather than linked, because Claude Code rewrites this file on
  # its own -- a symlink would be replaced by a regular file the first time the
  # theme changed. Same reasoning as the VS Code settings below.
  #
  # The repo's values win on conflict, and anything the machine has added that
  # the repo does not mention is preserved. jq comes from mise, which is why
  # this step lives after the shim export above rather than earlier.
  log "Merging Claude Code settings"
  mkdir -p "$HOME/.claude"
  if [ -f "$HOME/.claude/settings.json" ]; then
    # jq reading and writing the same path truncates it before it has read
    # anything, so the merged result is written to a temp file and moved in.
    #
    # This one is an `if` rather than `cmd && cmd` on purpose. set -e exempts a
    # failing command in an AND-list, which is right for the guards elsewhere in
    # this script and wrong here: a jq failure would skip the mv, leave the
    # settings unmerged, and let the script finish reporting success -- the
    # exact outcome this step exists to prevent.
    if ! jq -s '.[0] * .[1]' "$HOME/.claude/settings.json" "$WSL_DIR/claude/settings.json" \
      > "$HOME/.claude/settings.json.new"; then
      rm -f "$HOME/.claude/settings.json.new"
      echo "    jq could not merge $HOME/.claude/settings.json -- is it valid JSON?" >&2
      exit 1
    fi
    mv "$HOME/.claude/settings.json.new" "$HOME/.claude/settings.json"
  else
    cp "$WSL_DIR/claude/settings.json" "$HOME/.claude/settings.json"
  fi

  # --- 10. zsh plugins -----------------------------------------------------------
  # wsl/zsh/.zshrc sources antidote from exactly this path. The two files have
  # to agree and only these comments say so -- on the Mac a package manager
  # owned the location, here nothing does.
  if [ ! -d "$XDG_DATA_HOME/antidote" ]; then
    log "Installing antidote"
    git clone --depth=1 https://github.com/mattmc3/antidote.git "$XDG_DATA_HOME/antidote"
  fi

  # --- 11. Login shell -----------------------------------------------------------
  # Tests the account's actual shell in /etc/passwd rather than $SHELL: $SHELL
  # is assigned once at session start and does not update within a running
  # shell, so comparing against it would re-run chsh -- and re-prompt for sudo
  # -- on a second run in the same terminal, even after the change already
  # landed.
  #
  # ${USER:-$(id -un)} rather than a bare $USER: under set -u, USER is the one
  # variable bash does not assign for you when it is unset, unlike SHELL --
  # verified. An environment that never exported it (a cron job, some CI
  # shells) would otherwise abort the script on its very last step, naming a
  # variable rather than the missing export. id -un asks the account directly.
  target_user="${USER:-$(id -un)}"
  if [ "$(getent passwd "$target_user" | cut -d: -f7)" != "$(command -v zsh)" ]; then
    log "Setting zsh as the login shell"
    sudo chsh -s "$(command -v zsh)" "$target_user"
  fi

  # --- 12. VS Code remote settings -----------------------------------------------
  # Copied rather than linked: VS Code Server rewrites this file when settings
  # are changed through the UI, and a symlink would end up overwritten.
  if [ -d "$HOME/.vscode-server" ]; then
    log "Applying VS Code remote settings"
    mkdir -p "$HOME/.vscode-server/data/Machine"
    cp "$WSL_DIR/vscode/settings.json" "$HOME/.vscode-server/data/Machine/settings.json"
  else
    echo "    .vscode-server not present yet -- connect once from VS Code, then re-run"
  fi

  # --- 13. Docker daemon and group ----------------------------------------------
  # The packages install the daemon but leave it stopped and disabled. systemd
  # is enabled in /etc/wsl.conf by step 1, so enabling the unit is what makes
  # Docker survive a `wsl --shutdown` instead of needing a hand-started daemon
  # from a shell profile, which is the arrangement older WSL guides describe.
  log "Enabling the Docker daemon"
  sudo systemctl enable --now docker.service

  # Reassigned rather than reusing step 11's copy: a step that silently depends
  # on a variable set eighty lines earlier breaks the moment either one moves.
  target_user="${USER:-$(id -un)}"
  # id -nG reads the account database, not this shell's credentials, so the
  # guard is still correct on the run right after the group was added.
  #
  # Split to one group per line and matched whole-line, not `grep -qw docker`
  # against the space-separated list. `-w` treats a hyphen as a word boundary,
  # so membership of an unrelated `docker-users` group would satisfy it and the
  # real usermod would never run -- the same shape as the appendWindowsPath
  # guard in step 1, which had to be anchored for the same reason. Verified:
  # `echo "camilo docker-users" | grep -qw docker` matches, `grep -qx` does not.
  if ! id -nG "$target_user" | tr ' ' '\n' | grep -qx docker; then
    log "Adding $target_user to the docker group"
    # Root-equivalent by design: the socket lets any member mount the host
    # filesystem into a privileged container. Accepted on a disposable WSL box
    # and recorded in docs/decisions.md rather than left as an unstated risk.
    sudo usermod -aG docker "$target_user"
    echo "    docker group applies to new shells only -- Ubuntu 26.04 ships no newgrp or sg"
  fi

  log "Done. Open a new shell, or run: exec zsh"
else
  log "Done (links only). apt, mise, uv, antidote, chsh and system files were skipped."
fi
