# Read by every zsh, including non-interactive ones: git hooks, `zsh -c` from an
# editor, anything spawned under a running session. That is what makes it the
# right place for PATH and the wrong place for anything interactive.
#
# This file is linked into TWO places by install.sh, to the same file, because
# zsh reads exactly one of them depending on how the shell started:
#
#   ZDOTDIR unset in the environment  ->  $HOME/.zshenv
#   ZDOTDIR already exported          ->  $ZDOTDIR/.zshenv
#
# It reads one or the other, never both. The second branch is every shell spawned
# from one this repo already configured. With only the $HOME copy linked, those
# read NEITHER file and start with the bare system PATH -- no mise shims, so a
# git hook reports `node: command not found` on a machine where the terminal
# beside it resolves node fine.
#
# Linking it twice is safe rather than merely tolerable: `typeset -U path` makes
# the file idempotent by construction, so a second read hoists entries that are
# already there instead of duplicating them.
#
# NOTE for anyone arriving from the Mac repo: there is no .zprofile here and
# that is not an omission. macOS runs /usr/libexec/path_helper between .zshenv
# and .zprofile, and path_helper REBUILDS PATH rather than appending to it, which
# is what that file existed to undo. Linux has no path_helper. The problem is
# gone, so the file is gone.

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

export ZDOTDIR="$XDG_CONFIG_HOME/zsh"

# Duplicates are removed on assignment, which is what makes this file safe to
# read twice.
typeset -U path PATH

path=(
  "$HOME/.local/bin"
  "$XDG_DATA_HOME/mise/shims"
  $path
)
export PATH

export EDITOR="code --wait"
export VISUAL="$EDITOR"

# Windows interop puts the entire Windows PATH into every WSL shell, which is
# roughly forty entries this environment never calls and which make every command
# lookup walk them. It is disabled in /etc/wsl.conf by install.sh; this is the
# assertion that it took, not a second mechanism.
#
# It also matters for correctness, not just speed: mise's Windows shims live on
# that PATH, every file under /mnt/c is executable as far as Linux is concerned,
# and a shimmed tool found there executes the Windows script inside Linux.
