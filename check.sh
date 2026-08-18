#!/usr/bin/env bash
# Every check this repo runs, in one place.
#
# You run it by hand, the pre-commit hook runs it, and CI runs it. That is the
# point: checks written twice drift, and the moment local and CI disagree you
# stop trusting either one.
#
# Usage:  ./check.sh [--strict]
#
# This repo spans two platforms, and the checks do not. Almost everything here
# validates file content -- YAML, JSON, TOML, shell -- which needs the files and
# not the operating system. The handful that genuinely need Windows live in a
# second CI job and are not run from here.
#
# A skipped check is a hole in coverage, not a neutral outcome: the tool was
# missing, nothing ran, and the run still ends green. Strict mode turns a skip
# into a failure, so coverage cannot shrink without the run going red. It is on
# automatically under CI and in the pre-commit hook, which is what makes CI's
# promise true by construction rather than by a list somebody remembers to
# update. Invoked by hand it is a report and not a gate, and there an amber skip
# is the useful answer.
#
# Every check here is a function invoked indirectly, by name, through check().
# The linter cannot see that, and would report all of them as unused code.
# shellcheck disable=SC2329,SC2317
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

# Every CI system sets CI, so the strict path needs no wiring in the workflow
# and cannot be forgotten there. --strict reproduces it locally, which is the
# only way to test this behaviour without pushing.
STRICT=0
[ -n "${CI:-}" ] && STRICT=1
case "${1:-}" in
  "") ;;
  --strict) STRICT=1 ;;
  *)
    echo "usage: $0 [--strict]" >&2
    exit 2
    ;;
esac

GREEN=$'\033[32m'
RED=$'\033[31m'
AMBER=$'\033[33m'
DIM=$'\033[90m'
OFF=$'\033[0m'

FAILED=0
SKIPPED=0

check() { # check <name> <command...>
  # Returns the wrapped command's exit status -- 0 on PASS, nonzero on FAIL --
  # so this is a real predicate, not always-0. That still does not make
  # `check X cmd || skip X reason` the right way to write a conditional check:
  # skip's job is "the tool to run this at all is missing," which check() has
  # no way to know just from what it wrapped failing. Conditional checks in
  # this file are written in the guard form instead --
  # `if have TOOL; then check ...; else skip ...; fi` -- see below.
  local name="$1"
  shift
  local out status
  out=$("$@" 2>&1)
  status=$?
  if [ "$status" -eq 0 ]; then
    printf '%sPASS%s %s\n' "$GREEN" "$OFF" "$name"
  else
    printf '%sFAIL%s %s\n' "$RED" "$OFF" "$name"
    [ -n "$out" ] && printf '%s%s%s\n' "$DIM" "$out" "$OFF"
    FAILED=1
  fi
  return "$status"
}

skip() { # skip <name> <reason>
  if [ "$STRICT" -eq 1 ]; then
    printf '%sFAIL%s %s (%s)\n' "$RED" "$OFF" "$1" "$2"
    FAILED=1
  else
    printf '%sSKIP%s %s (%s)\n' "$AMBER" "$OFF" "$1" "$2"
    SKIPPED=1
  fi
}

have() { command -v "$1" > /dev/null 2>&1; }

# --- No carriage returns in tracked files ------------------------------------
# .gitattributes should make this impossible, which is exactly why it is
# asserted. A rule nobody has watched fail is a rule nobody should rely on.
no_crlf() {
  local hits
  hits=$(git grep -lIP '\r' -- . || true)
  [ -z "$hits" ] || {
    echo "files containing CR: $hits"
    return 1
  }
}
check "no carriage returns in tracked files" no_crlf

# --- English only ------------------------------------------------------------
# The repo is English-only by policy (wsl/claude/CLAUDE.md). The pattern is
# written as escapes rather than literal accented characters so that this file
# does not itself violate the rule it enforces.
english_only() {
  local hits
  hits=$(git grep -nIP '[\x{00E1}\x{00E9}\x{00ED}\x{00F3}\x{00FA}\x{00F1}\x{00C1}\x{00C9}\x{00CD}\x{00D3}\x{00DA}\x{00D1}\x{00BF}\x{00A1}]' \
    -- . || true)
  [ -z "$hits" ] || {
    echo "$hits"
    return 1
  }
}
check "english only" english_only

# --- Shell -------------------------------------------------------------------
if have shellcheck; then
  check "shellcheck" shellcheck -x ./*.sh ./githooks/*
else
  skip "shellcheck" "not installed"
fi

if have shfmt; then
  check "shfmt" shfmt -d ./*.sh ./githooks/*
else
  skip "shfmt" "not installed"
fi

syntax_bash() { for f in ./*.sh ./githooks/*; do bash -n "$f" || return 1; done; }
check "bash syntax" syntax_bash

# --- Windows layer -----------------------------------------------------------
# The manifest is YAML, and YAML parses on any platform. Whether the package ids
# inside it resolve is a different question, and one only a Windows machine with
# winget can answer -- so it lives in the second CI job, not here. See practice
# #8: out of a runner goes what that runner cannot answer honestly.
have_pyyaml() { python3 -c "import yaml" > /dev/null 2>&1; }

if have python3 && have_pyyaml; then
  check "winget manifest is valid yaml" python3 -c "
import sys, yaml
yaml.safe_load(open('windows/configuration.winget'))
"
else
  skip "winget manifest is valid yaml" "python3/pyyaml not installed"
fi

# The host layer declares three named groups: the substrate (WSL2 + Ubuntu), the
# environment (terminal, font, editor, PowerToys), and the authoring tools this
# repo's own checks need. Anything outside those three is the boundary leaking,
# and a leak nobody notices is a leak that grows.
#
# The Script resource that installs Ubuntu is asserted separately: without it,
# the distro could be deleted from the manifest, or its version silently
# edited, and every check above would still pass -- the substrate is the one
# thing here whose absence nothing else would notice.
host_layer_stays_thin() {
  python3 - << 'PY'
import sys, yaml

GROUPS = {
    'substrate': {'Microsoft.WSL'},
    'environment': {'Microsoft.WindowsTerminal', 'DEVCOM.JetBrainsMonoNerdFont',
                     'Microsoft.VisualStudioCode', 'Microsoft.PowerToys'},
    'authoring': {'koalaman.shellcheck', 'mvdan.shfmt', 'tamasfe.taplo'},
}
allowed = set().union(*GROUPS.values())

doc = yaml.safe_load(open('windows/configuration.winget'))
resources = doc['properties']['resources']

declared = {
    r['settings']['id']
    for r in resources
    if r['resource'].endswith('/WinGetPackage')
}
extra = declared - allowed
if extra:
    print('host layer declares packages outside the three known groups: %s' % ', '.join(sorted(extra)))
    print('the known groups, so the fix is one line:')
    for name, ids in GROUPS.items():
        print('  %s: %s' % (name, ', '.join(sorted(ids))))
    print('If this is deliberate, widen the appropriate group above and say why in the manifest.')
    sys.exit(1)

ubuntu = [r for r in resources if r.get('id') == 'ubuntu' and r['resource'] == 'PSDscResources/Script']
if not ubuntu:
    print('no PSDscResources/Script resource with id "ubuntu" found -- the substrate can silently vanish')
    sys.exit(1)
set_script = ubuntu[0].get('settings', {}).get('SetScript', '')
if 'Ubuntu-26.04' not in set_script:
    print('the ubuntu Script resource does not install Ubuntu-26.04 -- found:\n%s' % set_script)
    sys.exit(1)
PY
}
if have python3 && have_pyyaml; then
  check "the host layer stays thin" host_layer_stays_thin
else
  skip "the host layer stays thin" "python3/pyyaml not installed"
fi

# --- Summary -----------------------------------------------------------------
echo
if [ "$FAILED" -ne 0 ]; then
  printf '%sSome checks failed.%s\n' "$RED" "$OFF"
  exit 1
fi
if [ "$SKIPPED" -ne 0 ]; then
  printf '%sAll checks passed, some skipped.%s\n' "$AMBER" "$OFF"
  exit 0
fi
printf '%sAll checks passed.%s\n' "$GREEN" "$OFF"
