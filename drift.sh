#!/usr/bin/env bash
# What this machine has that nothing here declares.
#
# check.sh asks: is everything declared actually present, and is the repo
# internally consistent? A subset of the machine always answers that yes --
# the tools this repo happened to install. The question that question cannot
# ask is the one that matters more over time: what is on this machine that no
# manifest names. That is the direction drift actually grows in, the same way
# the Mac repo's `brew bundle check` cannot answer it either, for the same
# reason -- it only ever confirms declared things are present.
#
# So this prints each of the four managers' agreement in both directions
# separately, because the two directions mean different things and get fixed
# differently:
#   declared but not present   -- a broken machine. Something did not install.
#   present but not declared   -- an undocumented one. It works today; nobody
#                                  wrote down why it is there.
#
# Usage (from inside Ubuntu, after wsl/install.sh has run):
#   ~/workstation/drift.sh
#
# Deliberately not in check.sh and not run by CI. Every check in check.sh has
# to mean the same thing on a CI runner as on this laptop -- that agreement is
# what makes its green tick worth trusting. This one cannot: a runner arrives
# with its own preinstalled packages, so "installed but undeclared" is always
# true there and never interesting. Wiring this into CI would either break the
# build forever on packages nobody put there, or get "fixed" by wrapping it in
# a CI-only skip -- which is a check that skips itself on the one machine that
# would otherwise run it automatically. This is a report a person reads by
# hand, not a gate.
#
# The Windows section below will report several packages on this machine that
# predate this repo -- Git for Windows, GitHub CLI, Docker Desktop, Node,
# Python. That is the correct answer on the first run, not noise to silence.
# Each one is either adopted into windows/configuration.winget or consciously
# left as known drift; what must not happen is nobody looking.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

# Neither mise nor uv is asked for --no-color by name -- that flag differs or
# does not exist across their versions. NO_COLOR is the convention both
# actually check, and a tool that has never heard of it simply ignores it.
export NO_COLOR=1

GREEN=$'\033[32m'
RED=$'\033[31m'
AMBER=$'\033[33m'
DIM=$'\033[90m'
OFF=$'\033[0m'

# Whether anything printed a GAP. Exit code, not a display concern: a report
# that always exits 0 cannot be composed into anything else later, even though
# nothing here treats a nonzero exit as a gate today.
DRIFTED=0

have() { command -v "$1" > /dev/null 2>&1; }

# Resolved by capability rather than by name, for the reason check.sh sets out
# at length: mise's python3 shim shadows the /usr/bin/python3 that apt installed
# python3-yaml against, so the bare name finds the one interpreter without it.
PYTHON=python3
if ! "$PYTHON" -c "import yaml" > /dev/null 2>&1; then
  if /usr/bin/python3 -c "import yaml" > /dev/null 2>&1; then
    PYTHON=/usr/bin/python3
  fi
fi

# printf '%s\n' "" still emits one blank line, which comm would then count as
# a real (empty-string) entry on both sides of every comparison. Guarding
# empty input here is what keeps an empty manifest from reading as agreement
# on a phantom item instead of agreement on nothing.
#
# A trailing \r is stripped for the same reason winget's own output is
# stripped below, but as a general backstop rather than only at that one
# call site: every list this function feeds into a comm comparison, and one
# stray \r on one line makes that line compare unequal to its otherwise
# identical counterpart with no visible sign why. A python3 that writes
# CRLF -- a Windows-native interpreter is the one that does, not the WSL
# one this runs under -- reproduces exactly that failure, and this is where
# it gets caught regardless of which producer it came from.
lines() { [ -n "$1" ] && printf '%s\n' "$1" | tr -d '\r'; }

# One direction of one comparison. PASS: nothing in $2, so this direction
# agrees. GAP: something does not, and each item gets its own indented line so
# the output reads as a list of things to decide about, one at a time, rather
# than prose to parse. Named GAP rather than FAIL -- check.sh's FAIL means an
# assertion this repo makes about itself did not hold; this means a true fact
# about the machine that nothing here asserted either way.
report_gap() { # report_gap <direction-label> <items, one per line>
  local label="$1" items="$2"
  if [ -z "$items" ]; then
    printf '%sPASS%s  %s: none\n' "$GREEN" "$OFF" "$label"
  else
    printf '%sGAP%s   %s:\n' "$RED" "$OFF" "$label"
    printf '%s\n' "$items" | sed "s/^/         ${DIM}/; s/\$/${OFF}/"
    DRIFTED=1
  fi
}

# A manager this section needs is not reachable from here at all -- not
# installed, or (for the fourth section) the Windows host could not be
# reached. This is not drift: it is missing coverage, and the two must not
# look the same. A silent skip would read as an all-clear it never earned, so
# this stays visible without turning the exit code red on its own.
skip_section() { printf '%sSKIP%s  %s\n' "$AMBER" "$OFF" "$1"; }

section() { printf '\n%s%s%s\n' "$DIM" "$1" "$OFF"; }

# mise's and winget's tables are both column-aligned with spaces, not
# tab-separated -- so a naive whitespace split breaks the moment any field (a
# package Name, say) contains one. Slicing every row at the header row's own
# column offsets survives that, and it is shared here rather than written
# twice because both tables have the same shape. A column is bounded by
# wherever the next header token starts, whether or not that next token was
# asked for -- otherwise the last requested column swallows every column
# after it that this function was not told to read. If the header text a
# caller asked for is not found as its own token -- a column renamed
# upstream, most likely -- this prints nothing and exits nonzero, and callers
# treat that as "cannot check" rather than trusting a guess.
#
# The script is passed with -c, not piped into `python3 -` on a heredoc: a
# heredoc there would redirect stdin to the script's own text, leaving
# nothing on stdin for the table this function is piped. -c keeps the two
# separate, the way the winget and mise calls below need them to be.
parse_table() { # parse_table <column-name>... < table-text
  local script
  script=$(
    cat << 'PY'
import re
import sys

cols = sys.argv[1:]
lines = [l.rstrip("\n") for l in sys.stdin]

header_idx = None
tokens = None
for i, line in enumerate(lines):
    found = [(m.start(), m.group()) for m in re.finditer(r"\S+", line)]
    names = {t for _, t in found}
    if all(c in names for c in cols):
        tokens = found
        header_idx = i
        break

if header_idx is None:
    sys.exit(1)

positions = sorted(start for start, _ in tokens)
starts = {name: start for start, name in tokens}


def end_of(start):
    later = [p for p in positions if p > start]
    return min(later) if later else None


bounds = {c: (starts[c], end_of(starts[c])) for c in cols}
for line in lines[header_idx + 1 :]:
    stripped = line.strip()
    if not stripped or set(stripped) <= {"-"}:
        continue
    row = {c: line[s:e].strip() for c, (s, e) in bounds.items()}
    print("\t".join(row.get(c, "") for c in cols))
PY
  )
  "$PYTHON" -c "$script" "$@"
}

# --- apt -----------------------------------------------------------------
# showmanual, not the full install list: comparing against everything
# installed would drown the output in dependencies apt pulled in on its own,
# which is not a decision anyone made and not this section's business.
section "apt"
if have apt-mark; then
  declared=$(sed 's/#.*//' wsl/apt-packages.txt | tr -d ' ' | grep -v '^$' | sort -u)
  installed=$(apt-mark showmanual | sort -u)
  report_gap "declared in wsl/apt-packages.txt but not manually installed" \
    "$(comm -23 <(lines "$declared") <(lines "$installed"))"
  report_gap "manually installed but not in wsl/apt-packages.txt" \
    "$(comm -13 <(lines "$declared") <(lines "$installed"))"
else
  skip_section "apt-mark not found -- this section only means something inside WSL"
fi

# --- mise ------------------------------------------------------------------
section "mise"
if have mise; then
  # wsl/mise/config.toml has exactly one section, [tools], so nothing here
  # needs to track leaving it again -- a second [section] header would need
  # this to stop, and none exists.
  declared=$(awk '
    /^\[/ { insec = ($0 == "[tools]"); next }
    insec && /^[a-z0-9_.-]+[[:space:]]*=[[:space:]]*"/ {
      tool = $0
      sub(/[[:space:]]*=.*/, "", tool)
      value = $0
      sub(/^[^"]*"/, "", value)
      sub(/".*/, "", value)
      print tool " " value
    }
  ' wsl/mise/config.toml)
  declared_names=$(lines "$declared" | awk '{print $1}' | sort -u)

  current=$(mise ls --current 2>&1)
  parsed=$(lines "$current" | parse_table Tool Version Requested)
  if [ -z "$parsed" ]; then
    skip_section "could not read mise's table -- 'mise ls --current' printed:"
    printf '%s%s%s\n' "$DIM" "$current" "$OFF"
  else
    installed_names=$(lines "$parsed" | awk -F'\t' '{print $1}' | sort -u)
    report_gap "declared in wsl/mise/config.toml but not active under mise" \
      "$(comm -23 <(lines "$declared_names") <(lines "$installed_names"))"
    report_gap "active under mise but not in wsl/mise/config.toml" \
      "$(comm -13 <(lines "$declared_names") <(lines "$installed_names"))"

    # Names agreeing is not enough -- a tool installed at a different version
    # than the pin is drift a name-only comparison would report as agreement.
    # Version cannot always be compared to the pin by simple equality: node's
    # major-only pin ("26") resolves to a full version ("26.3.1") in Version,
    # which is correct and not drift, exactly as wsl/mise/config.toml's own
    # comments describe the two pin styles it uses. What Version failing to
    # resolve at all looks like -- empty, or mise's own "missing" marker -- is
    # checked for every tool regardless of pin style; an exact three-part pin
    # (most of the user tools) is additionally checked for equality, since for
    # those Version disagreeing with the pin at all is exactly the drift this
    # section exists to catch. Requested disagreeing with what
    # wsl/mise/config.toml itself declares is a third, independent signal:
    # some other config layer is winning over this repo's.
    version_gaps=""
    while read -r name want; do
      [ -n "$name" ] || continue
      row=$(lines "$parsed" | awk -F'\t' -v n="$name" '$1 == n { print; exit }')
      [ -n "$row" ] || continue # already reported above as not active
      got=$(printf '%s' "$row" | awk -F'\t' '{print $2}')
      requested=$(printf '%s' "$row" | awk -F'\t' '{print $3}')
      if [ -z "$got" ] || [ "${got,,}" = "missing" ]; then
        version_gaps="${version_gaps}${name} is requested at ${want} but not installed"$'\n'
      elif [[ "$want" == *.*.* ]] && [ "$got" != "$want" ]; then
        version_gaps="${version_gaps}${name}: wsl/mise/config.toml pins ${want} exactly, mise has ${got} installed"$'\n'
      fi
      if [ -n "$requested" ] && [ "$requested" != "$want" ]; then
        version_gaps="${version_gaps}${name}: wsl/mise/config.toml pins ${want}, mise currently requests ${requested}"$'\n'
      fi
    done <<< "$declared"
    report_gap "declared pin does not match what mise actually resolved" "${version_gaps%$'\n'}"
  fi
else
  skip_section "mise not found -- this section only means something inside WSL"
fi

# --- uv ----------------------------------------------------------------------
section "uv"
if have uv; then
  declared=$(sed -E 's/#.*//; s/[[:space:]]+/ /g; s/^ //; s/ $//' wsl/uv-tools.txt | grep -v '^$')
  declared_names=$(lines "$declared" | awk '{print $1}' | sort -u)

  # Top-level lines only: `uv tool list` nests each tool's entry points under
  # it on their own indented lines, which are not tools and would otherwise
  # inflate this comparison with things that are not packages at all.
  installed_names=$(uv tool list 2> /dev/null | grep -vE '^[[:space:]-]' | awk '{print $1}' | sort -u)
  report_gap "declared in wsl/uv-tools.txt but not installed" \
    "$(comm -23 <(lines "$declared_names") <(lines "$installed_names"))"
  report_gap "installed with uv tool but not in wsl/uv-tools.txt" \
    "$(comm -13 <(lines "$declared_names") <(lines "$installed_names"))"

  # `uv tool list`'s version column is the resolved package version, not the
  # reference wsl/uv-tools.txt pins it by -- for specify-cli that reference is
  # a git tag, which is not a version number and would never match. The
  # reference uv actually installed from is recorded in each tool's receipt,
  # under `uv tool dir`; that is what the pin is checked against.
  tool_dir=$(uv tool dir 2> /dev/null)
  if [ -n "$tool_dir" ]; then
    ref_gaps=""
    while read -r name ref; do
      [ -n "$name" ] || continue
      receipt="$tool_dir/$name/uv-receipt.toml"
      [ -f "$receipt" ] || continue # already reported above as not installed
      grep -qF -- "$ref" "$receipt" ||
        ref_gaps="${ref_gaps}${name}: wsl/uv-tools.txt pins ${ref}, receipt does not mention it (${receipt})"$'\n'
    done <<< "$declared"
    report_gap "installed from a different reference than wsl/uv-tools.txt declares" "${ref_gaps%$'\n'}"
  else
    skip_section "cannot read installed references -- 'uv tool dir' did not resolve"
  fi
else
  skip_section "uv not found -- this section only means something inside WSL"
fi

# --- the Windows host --------------------------------------------------------
# This is the direction that will report the most, and on a machine that had
# Git for Windows, GitHub CLI, Docker Desktop, Node and Python before this
# repo existed, that is expected -- see the header. Do not turn that into an
# allow-list: a list this section has been taught to stop reporting is a list
# that has stopped working.
section "the Windows host"
resolve_winget() {
  # Meaningful only from inside WSL, alongside the Windows host it checks.
  grep -qi microsoft /proc/version 2> /dev/null || return 1
  [ -x /mnt/c/Windows/System32/cmd.exe ] || return 1
  return 0
}

if resolve_winget; then
  # wsl/install.sh turns off appendWindowsPath, so winget.exe is not on PATH
  # here and is not found by bare name -- see wsl/install.sh's interop step.
  # That narrows what WSL puts on $PATH; it does not disable running a
  # Windows binary by an absolute Windows path, which is what this uses.
  # cmd.exe is asked to find winget.exe by its own PATH rather than this
  # guessing the path directly: winget's real home is a per-user WindowsApps
  # alias directory, and asking Windows to resolve its own PATH is more
  # reliable than reconstructing that path from the WSL side.
  #
  # winget.exe's output carries NUL bytes when its stdout is not a real
  # console, which a pipe from WSL never is -- the same UTF-16LE shape that
  # bit windows/configuration.winget's own Script resource, and wsl.exe
  # before that. tr -d strips it back to text before anything reads it.
  raw=$(/mnt/c/Windows/System32/cmd.exe /c winget.exe list --source winget \
    --accept-source-agreements 2>&1 | tr -d '\0\r')

  parsed=$(lines "$raw" | parse_table Name Id Version)
  if [ -z "$parsed" ]; then
    skip_section "could not read winget's table -- 'winget.exe list' printed:"
    printf '%s%s%s\n' "$DIM" "$raw" "$OFF"
  else
    installed_ids=$(lines "$parsed" | awk -F'\t' '{print $2}' | grep -v '^$' | sort -u)

    declared_ids=$("$PYTHON" -c "
import yaml
doc = yaml.safe_load(open('windows/configuration.winget', encoding='utf-8'))
ids = sorted({
    r['settings']['id']
    for r in doc['properties']['resources']
    if 'id' in r.get('settings', {})
})
print('\n'.join(ids))
" 2> /dev/null)

    if [ -z "$declared_ids" ]; then
      skip_section "could not read windows/configuration.winget -- python3/pyyaml not available here"
    else
      report_gap "declared in windows/configuration.winget but not installed" \
        "$(comm -23 <(lines "$declared_ids") <(lines "$installed_ids"))"
      report_gap "installed on the host but not in windows/configuration.winget" \
        "$(comm -13 <(lines "$declared_ids") <(lines "$installed_ids"))"
    fi
  fi
else
  skip_section "cannot reach the Windows host from here -- this section only means something inside WSL"
fi

printf '\n'
if [ "$DRIFTED" -eq 1 ]; then
  printf '%sDrift found -- each GAP above is either adopted into its manifest or left as known drift.%s\n' "$RED" "$OFF"
else
  printf '%sNo drift found.%s\n' "$GREEN" "$OFF"
fi
exit "$DRIFTED"
