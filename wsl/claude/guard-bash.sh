#!/usr/bin/env bash
# PreToolUse hook for Claude Code's Bash tool -- the enforcement layer behind
# the "never" rules that name concrete commands.
#
# Claude runs this before every Bash tool call, passing the pending call as
# JSON on stdin. Exit 0 lets the command run; exit 2 blocks it and feeds
# stderr back to the model as the reason. A prompted rule is advisory and its
# compliance decays as a session grows; this does not. The mechanism backs the
# prose rules in CLAUDE.md today; the prose contracts to a pointer in a
# follow-up change. See docs/decisions.md R43.
#
# What it blocks, and why:
#
#   pip install / python -m pip install    installs into the interpreter
#   without a venv activated in the        itself; uv owns packages here, and
#   same command                           an activation cannot outlive the
#                                          call (each Bash call is a fresh
#                                          shell), so same-command is the only
#                                          activation that counts
#   python -m venv                         uv venv owns virtualenvs here
#   npm install -g (and aliases)           writes into a directory named after
#                                          node's patch version; lost on bump
#   the common Bash shapes that write      /mnt/c is reachable and 9-20x
#   under /mnt/c                           slower; work lives on ext4
#
# Scope, stated honestly. Bash is an open-ended surface and this is a net for
# the habitual shapes, not a parser:
#   - heredoc bodies are skipped (they are data), so the command line that
#     opens a heredoc is still checked but its content never is;
#   - single- and double-quoted spans are removed before the command-shaped
#     rules run, so prose ABOUT pip/npm is not an install -- which also means
#     a deliberately quoted evasion (bash -c "pip install x") passes: the
#     guard is aimed at habit, not at adversaries;
#   - the /mnt/c rules keep quotes and tolerate them around paths, so the
#     quoted form of a Windows path (they contain spaces) is caught -- but
#     prose that quotes a /mnt/c redirect inside a string can still
#     false-positive, and `cd /mnt/c/... && echo hi > file` is out of scope;
#   - executing a Windows binary by absolute path (drift.sh's cmd.exe
#     crossing) is not a write and passes untouched.
# The complete guarantees are the Write/Edit/NotebookEdit deny rules in
# settings.json; this hook is the net for the tool those rules cannot see
# into.
#
# All matching is bash-native ([[ =~ ]] with patterns held in variables, the
# form that keeps bash from reinterpreting regex metacharacters): no
# per-pattern forks, so the cost stays flat as commands grow lines. Exercised
# by check.sh: every rule is fed commands it must block and lookalikes it
# must allow, so a regex that drifts fails a check rather than silently over-
# or under-matching.

set -euo pipefail

# Fail-open is right for a hook, but silent fail-open makes a dead guard
# indistinguishable from a clean one. Say so on the way out.
command -v jq > /dev/null 2>&1 || {
  echo "guard-bash.sh: jq not on PATH; guard did not run" >&2
  exit 0
}

cmd=$(jq -r '.tool_input.command // empty' 2> /dev/null) || exit 0
[ -n "$cmd" ] || exit 0

# Cheap pre-filter: nothing below can match a command that never mentions
# these substrings, and most commands do not.
case "$cmd" in
  *pip* | *npm* | *venv* | */mnt/c*) ;;
  *) exit 0 ;;
esac

deny() {
  echo "guard-bash.sh blocked this command: $1" >&2
  exit 2
}

# Drop heredoc bodies: everything between `<< TAG` and the line holding TAG is
# data, not commands. The line that opens the heredoc is kept, so a heredoc
# whose TARGET is /mnt/c is still caught by the redirect rule. `<<<` does not
# match the tag pattern and is untouched.
stripped=$(printf '%s\n' "$cmd" | awk '
  skip {
    line = $0
    sub(/^[[:space:]]+/, "", line)
    if (line == tag) skip = 0
    next
  }
  {
    if (match($0, /<<-?[[:space:]]*["'\'']?[A-Za-z_][A-Za-z0-9_]*/)) {
      tag = substr($0, RSTART, RLENGTH)
      sub(/^<<-?[[:space:]]*["'\'']?/, "", tag)
      skip = 1
    }
    print
  }
')

# One segment per simple command: split on control operators and newlines so
# `cd x && pip install y` cannot hide behind its prefix. Splitting on a bare
# `&` also splits `2>&1` into harmless fragments; every command-anchored
# pattern below matches nothing in them.
split_ops() {
  printf '%s\n' "$1" | sed -E 's/&&|\|\||[;|&]/\n/g'
}

# Strip what may legitimately precede the command word: whitespace,
# environment assignments, sudo, `command`. Sets CLEANED rather than printing:
# a $(subshell) per segment is exactly the fork cost this script avoids.
clean_prefixes() {
  local s=$1
  while :; do
    if [[ $s =~ ^[[:space:]]+ ]] ||
      [[ $s =~ ^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)+ ]] ||
      [[ $s =~ ^sudo[[:space:]]+(-[^[:space:]]+[[:space:]]+)* ]] ||
      [[ $s =~ ^command[[:space:]]+ ]]; then
      s=${s:${#BASH_REMATCH[0]}}
    else
      break
    fi
  done
  CLEANED=$s
}

# Patterns live in variables: bash's =~ treats an unquoted literal pattern as
# regex but reparses quotes and escapes in surprising ways (GNU regex reads
# \> as a word boundary, for one). A variable is passed through verbatim.
dq='"'
sq="'"
q="[$dq$sq]"

re_activate='^(source|\.)[[:space:]]+[^[:space:]]*activate'
re_pip='^pip[0-9]*[[:space:]]+install([[:space:]]|$)'
re_pymod_pip='^python[0-9.]*[[:space:]]+-m[[:space:]]+pip[[:space:]]+install([[:space:]]|$)'
re_pymod_venv='^python[0-9.]*[[:space:]]+-m[[:space:]]+venv([[:space:]]|$)'
re_npm_verb='^npm[[:space:]]+(i|in|ins|inst|insta|instal|install|isntall|add)([[:space:]]|$)'
re_npm_global='(^|[[:space:]])(-g|--global|--location[= ]global)([[:space:]]|$)'

re_redirect='>>?[[:space:]]*'$q'?/mnt/c/'
re_tee='^tee[[:space:]]+(-[^[:space:]]+[[:space:]]+)*'$q'?/mnt/c/'
re_sed_cmd='^sed([[:space:]]|$)'
re_sed_inplace='(^|[[:space:]])(--in-place|-[a-zA-Z]*i)'
re_mnt_arg='[[:space:]]'$q'?/mnt/c/'
re_dd='^dd[[:space:]](.*[[:space:]])?of='$q'?/mnt/c/'
re_dest_verb='^(cp|mv|rsync|install|ln)[[:space:]]'
re_dest_final='[[:space:]]('$dq'/mnt/c/[^'$dq']*'$dq'|'$sq'/mnt/c/[^'$sq']*'$sq'|/mnt/c/[^[:space:]]*)([[:space:]]+--?[A-Za-z][A-Za-z-]*)*[[:space:]]*$'
re_dest_flag='[[:space:]](-t[[:space:]]+|--target-directory=)'$q'?/mnt/c/'
re_modify='^(mkdir|touch|truncate|chmod|chown|rm|rmdir|unlink)[[:space:]](.*[[:space:]])?'$q'?/mnt/c/'

# ── Command-shaped rules, on text with quoted spans removed ─────────────────
# Quoted text is data: `gh pr create --body "... pip install ..."` is prose.
# Removal happens BEFORE the operator split, so an operator inside a string
# cannot open a fake segment.
noquotes=$(printf '%s\n' "$stripped" | sed -E "s/\"[^\"]*\"//g; s/'[^']*'//g")

venv_active=0
while IFS= read -r seg; do
  clean_prefixes "$seg"
  seg=$CLEANED

  # An activation earlier in the SAME command makes a later pip legitimate:
  # it installs into that venv, not into the interpreter. State cannot leak
  # in from a previous call, because every Bash tool call is a fresh shell.
  if [[ $seg =~ $re_activate ]]; then
    venv_active=1
  fi

  if [[ $venv_active -eq 0 && $seg =~ $re_pip ]]; then
    deny "pip without an activated venv installs into the interpreter itself. Use 'uv pip install', or activate the project's venv in this same command."
  fi
  if [[ $venv_active -eq 0 && $seg =~ $re_pymod_pip ]]; then
    deny "python -m pip without an activated venv installs into the interpreter itself. Use 'uv pip install', or activate the project's venv in this same command."
  fi
  if [[ $seg =~ $re_pymod_venv ]]; then
    deny "python -m venv builds on whichever interpreter answers. Use 'uv venv', which reads .python-version."
  fi
  if [[ $seg =~ $re_npm_verb && $seg =~ $re_npm_global ]]; then
    deny "npm -g writes into a directory named after node's patch version and loses it on the next bump. Global CLIs come from mise or 'uv tool install'."
  fi
done < <(split_ops "$noquotes")

# ── /mnt/c write rules, on the raw text ─────────────────────────────────────
# Quotes are kept and tolerated around the path here, because a quoted
# Windows path is the normal shape of a real write, not an evasion.
# cp/mv/rsync/install/ln block only when /mnt/c is the destination -- the
# final argument (trailing flags allowed; rsync idiom), an explicit
# -t/--target-directory, or dd's of= -- so copying and linking FROM Windows
# stays a legitimate read crossing.
while IFS= read -r seg; do
  clean_prefixes "$seg"
  seg=$CLEANED

  if [[ $seg =~ $re_redirect ]]; then
    deny "this redirects output onto the Windows filesystem. Work lives on ext4; write there and cross explicitly if Windows truly needs the file."
  fi
  if [[ $seg =~ $re_tee ]]; then
    deny "tee writes onto the Windows filesystem. Work lives on ext4."
  fi
  if [[ $seg =~ $re_sed_cmd && $seg =~ $re_sed_inplace && $seg =~ $re_mnt_arg ]]; then
    deny "sed -i edits a file in place on the Windows filesystem. Work lives on ext4."
  fi
  if [[ $seg =~ $re_dd ]]; then
    deny "dd writes onto the Windows filesystem. Work lives on ext4."
  fi
  if [[ $seg =~ $re_dest_verb ]] && { [[ $seg =~ $re_dest_final ]] || [[ $seg =~ $re_dest_flag ]]; }; then
    deny "the destination is the Windows filesystem. Copying or linking FROM it is a legitimate read crossing; writing TO it is not. Work lives on ext4."
  fi
  if [[ $seg =~ $re_modify ]]; then
    deny "this modifies the Windows filesystem. Work lives on ext4."
  fi
done < <(split_ops "$stripped")

exit 0
