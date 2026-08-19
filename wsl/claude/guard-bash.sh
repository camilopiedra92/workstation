#!/usr/bin/env bash
# PreToolUse hook for Claude Code's Bash tool -- the enforcement layer behind
# the "never" rules that name concrete commands.
#
# Claude runs this before every Bash tool call, passing the pending call as
# JSON on stdin. Exit 0 lets the command run; exit 2 blocks it and feeds
# stderr back to the model as the reason. A prompted rule is advisory and its
# compliance decays as a session grows; this does not, which is why the rules
# below live here and CLAUDE.md only points at them. See docs/decisions.md R43.
#
# What it blocks, and why:
#
#   pip install / python -m pip install    installs into the interpreter
#                                          itself; uv owns packages here
#   python -m venv                         uv venv owns virtualenvs here
#   npm install -g (and aliases)           writes into a directory named after
#                                          node's patch version; lost on bump
#   the common Bash shapes that write      /mnt/c is reachable and 9-20x
#   under /mnt/c                           slower; work lives on ext4
#
# Scope, stated honestly: Bash is an open-ended surface, so the /mnt/c rules
# here catch the common write shapes (redirects, tee, sed -i, dd, a /mnt/c
# destination argument), not every conceivable one. The complete guarantees
# are the Write/Edit/NotebookEdit deny rules in settings.json; this hook is
# the net for the tool those rules cannot see into. Executing a Windows
# binary by absolute path (drift.sh's cmd.exe crossing) is not a write and
# passes untouched.
#
# Exercised by check.sh: every rule is fed a command it must block and a
# lookalike it must allow, so a regex that drifts fails a check rather than
# silently over- or under-matching.

set -euo pipefail

cmd=$(jq -r '.tool_input.command // empty' 2> /dev/null) || exit 0
[ -n "$cmd" ] || exit 0

deny() {
  echo "guard-bash.sh blocked this command: $1" >&2
  exit 2
}

# One segment per simple command: split on control operators and newlines so
# `cd x && pip install y` cannot hide behind its prefix. Splitting on a bare
# `&` also splits `2>&1` into harmless fragments; every pattern below anchors
# on a command word, so the fragments match nothing.
segments=$(printf '%s\n' "$cmd" | sed -E 's/&&|\|\||[;|&]/\n/g')

while IFS= read -r seg; do
  # Strip what may legitimately precede the command word: whitespace,
  # environment assignments, sudo, `command`.
  seg=$(printf '%s' "$seg" | sed -E '
    s/^[[:space:]]+//
    s/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)+//
    s/^sudo[[:space:]]+(-[^[:space:]]+[[:space:]]+)*//
    s/^command[[:space:]]+//')

  if printf '%s' "$seg" | grep -Eq '^pip[0-9]*[[:space:]]+install([[:space:]]|$)'; then
    deny "pip installs into the interpreter itself. Use 'uv pip install' inside a venv, or 'uv tool install' for a CLI."
  fi

  if printf '%s' "$seg" | grep -Eq '^python[0-9.]*[[:space:]]+-m[[:space:]]+pip[[:space:]]+install([[:space:]]|$)'; then
    deny "python -m pip installs into the interpreter itself. Use 'uv pip install' inside a venv."
  fi

  if printf '%s' "$seg" | grep -Eq '^python[0-9.]*[[:space:]]+-m[[:space:]]+venv([[:space:]]|$)'; then
    deny "python -m venv builds on whichever interpreter answers. Use 'uv venv', which reads .python-version."
  fi

  if printf '%s' "$seg" | grep -Eq '^npm[[:space:]]+(i|in|ins|inst|insta|instal|install|isntall|add)([[:space:]]|$)' &&
    printf '%s' "$seg" | grep -Eq '(^|[[:space:]])(-g|--global|--location[= ]global)([[:space:]]|$)'; then
    deny "npm -g writes into a directory named after node's patch version and loses it on the next bump. Global CLIs come from mise or 'uv tool install'."
  fi

  # Writes under /mnt/c. Redirects are checked against the raw segment; the
  # rest anchor on the verb whose /mnt/c argument is necessarily a write
  # target -- cp/mv/rsync/install only when /mnt/c is the FINAL argument, so
  # copying FROM Windows stays a legitimate read crossing.
  if printf '%s' "$seg" | grep -Eq '>>?[[:space:]]*/mnt/c/'; then
    deny "this redirects output onto the Windows filesystem. Work lives on ext4; write there and cross explicitly if Windows truly needs the file."
  fi
  if printf '%s' "$seg" | grep -Eq '^tee[[:space:]]+(-[^[:space:]]+[[:space:]]+)*/mnt/c/'; then
    deny "tee writes onto the Windows filesystem. Work lives on ext4."
  fi
  if printf '%s' "$seg" | grep -Eq '^sed[[:space:]].*-i' &&
    printf '%s' "$seg" | grep -Eq '[[:space:]]/mnt/c/'; then
    deny "sed -i edits a file in place on the Windows filesystem. Work lives on ext4."
  fi
  if printf '%s' "$seg" | grep -Eq '^dd[[:space:]](.*[[:space:]])?of=/mnt/c/'; then
    deny "dd writes onto the Windows filesystem. Work lives on ext4."
  fi
  if printf '%s' "$seg" | grep -Eq '^(cp|mv|rsync|install)[[:space:]].*[[:space:]]/mnt/c/[^[:space:]]*[[:space:]]*$'; then
    deny "the destination is the Windows filesystem. Copying FROM it is a legitimate read crossing; copying TO it is not. Work lives on ext4."
  fi
  if printf '%s' "$seg" | grep -Eq '^(mkdir|touch|truncate|ln|chmod|chown|rm|rmdir|unlink)[[:space:]](.*[[:space:]])?/mnt/c/'; then
    deny "this modifies the Windows filesystem. Work lives on ext4."
  fi
done <<< "$segments"

exit 0
