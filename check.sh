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

# Python's open() uses the locale's encoding unless told otherwise, and this repo
# is authored on Windows (cp1252) and runs in CI on Linux (UTF-8). That is the
# check.sh header's promise broken at the root: the same file, two verdicts.
#
# Two ways it breaks, and the quiet one is worse. A byte undefined in cp1252
# (0x81, 0x8d, 0x8f, 0x90, 0x9d) raises UnicodeDecodeError and takes the check
# down -- that is how this was found, on the vendored Windows Terminal schema at
# position 6105. Every other non-ASCII byte decodes silently into different
# characters, and a check that compares those reaches a confident wrong answer.
#
# PEP 540's UTF-8 mode fixes every call site at once, including the ones nobody
# has written yet. That is the point: an explicit encoding= on each open() is
# discipline, and discipline is what gets forgotten at the next call site.
export PYTHONUTF8=1

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
yaml.safe_load(open('windows/configuration.winget', encoding='utf-8'))
"
else
  skip "winget manifest is valid yaml" "python3/pyyaml not installed"
fi

# --- Python runs in UTF-8 mode --------------------------------------------
# Asserts the property, not the line: a check that grepped check.sh for the
# `export PYTHONUTF8=1` above would pass even if someone wrote it wrong or put
# it after a check that already needed it. This asks the interpreter itself.
utf8_mode() {
  python3 -c "import sys; sys.exit(0 if sys.flags.utf8_mode else 1)"
}
if have python3; then
  check "python runs in utf-8 mode" utf8_mode
else
  skip "python runs in utf-8 mode" "python3 not installed"
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

doc = yaml.safe_load(open('windows/configuration.winget', encoding='utf-8'))
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

# --- Windows Terminal --------------------------------------------------------
# Replaces the Mac repo's `ghostty +validate-config`, which was its only check
# that validated configuration rather than code -- and whose absence once let CI
# report success while validating no Ghostty config at all.
wt_schema() {
  python3 - << 'PY'
import json, re, sys
try:
    import jsonschema
except ImportError:
    print('jsonschema not installed'); sys.exit(2)
s = re.sub(r'^\s*//.*$', '', open('windows/terminal/settings.json', encoding='utf-8').read(), flags=re.M)
s = re.sub(r',(\s*[}\]])', r'\1', s)
jsonschema.validate(json.loads(s), json.load(open('schemas/windows-terminal.json', encoding='utf-8')))
PY
}
if have python3 && python3 -c "import jsonschema" 2> /dev/null; then
  check "windows terminal settings match the published schema" wt_schema
else
  skip "windows terminal settings match the published schema" "jsonschema not installed"
fi

# --- Every action id and keybinding id resolve to each other -----------------
# The schema (checked above) validates actions and keybindings independently --
# it has no way to know they are supposed to refer to each other, so it happily
# accepts a keybindings id with a typo, or an actions id nothing ever binds.
# Either one passes schema validation and does nothing on the machine, silently.
# Same argument as the font-coherence and startingDirectory checks below and
# above: two places naming the same thing agree because something makes them,
# not because whoever edits one remembers the other.
#
# Flagging an action with no keybinding is a rule about this file today, not
# a general one: every action here exists to be bound to a key, so an unbound
# one is a mistake. That stops being true the day an action is meant to be
# invoked only from the command palette and deliberately carries no
# keybinding -- whoever adds one should treat this check failing as a sign to
# widen it (e.g. an explicit allow-list of intentionally unbound ids), not as
# a rule to silence.
actions_and_keybindings_resolve() {
  python3 - << 'PY'
import json, re, sys

def jsonc(path):
    s = open(path, encoding='utf-8').read()
    s = re.sub(r'^\s*//.*$', '', s, flags=re.M)
    s = re.sub(r',(\s*[}\]])', r'\1', s)
    return json.loads(s)

wt = jsonc('windows/terminal/settings.json')
action_ids = {a['id'] for a in wt.get('actions', []) if 'id' in a}
keybinding_ids = {k['id'] for k in wt.get('keybindings', []) if 'id' in k}

problems = []
orphan_keybindings = keybinding_ids - action_ids
orphan_actions = action_ids - keybinding_ids
if orphan_keybindings:
    problems.append('keybindings reference an id no action defines: %s' % ', '.join(sorted(orphan_keybindings)))
if orphan_actions:
    problems.append('actions define an id no keybinding references: %s' % ', '.join(sorted(orphan_actions)))

for p in problems:
    print(p)
sys.exit(1 if problems else 0)
PY
}
if have python3; then
  check "every action id and keybinding id resolve to each other" actions_and_keybindings_resolve
else
  skip "every action id and keybinding id resolve to each other" "python3 not installed"
fi

# --- One Nerd Font, declared everywhere it renders ---------------------------
# Two fonts installed is not better than one. When something falls back, or a
# family name is misspelled, a second Nerd Font lets it resolve to the wrong one
# and still work -- with glyphs that look subtly different and no way to tell
# why. One font makes that failure immediate.
one_nerd_font() {
  python3 - << 'PY'
import json, re, sys, yaml

problems = []

def jsonc(path):
    s = open(path, encoding='utf-8').read()
    s = re.sub(r'^\s*//.*$', '', s, flags=re.M)
    s = re.sub(r',(\s*[}\]])', r'\1', s)
    return json.loads(s)

wt = jsonc('windows/terminal/settings.json')
term_font = wt.get('profiles', {}).get('defaults', {}).get('font', {}).get('face', '')
if not term_font:
    problems.append('windows terminal declares no profiles.defaults.font.face')
elif 'Nerd Font' not in term_font:
    problems.append('windows terminal font.face is not a Nerd Font: %r' % term_font)

v = jsonc('windows/vscode/settings.json')
# The editor may list fallbacks; only the first entry is the one that renders.
editor = (v.get('editor.fontFamily') or '').split(',')[0].strip()
integrated = (v.get('terminal.integrated.fontFamily') or '').strip()
for key, got in (('editor.fontFamily', editor),
                 ('terminal.integrated.fontFamily', integrated)):
    if not got:
        problems.append('windows/vscode/settings.json declares no %s' % key)
    elif term_font and got != term_font:
        problems.append('%s is %r, windows terminal uses %r' % (key, got, term_font))

# Exactly one, not at least one: see the note above this function.
doc = yaml.safe_load(open('windows/configuration.winget', encoding='utf-8'))
fonts = [r['settings']['id'] for r in doc['properties']['resources']
         if r['resource'].endswith('/WinGetPackage')
         and 'NerdFont' in r['settings']['id']]
if len(fonts) != 1:
    problems.append('the manifest declares %d Nerd Fonts, expected 1: %s'
                    % (len(fonts), ', '.join(fonts) or 'none'))

for p in problems:
    print(p)
sys.exit(1 if problems else 0)
PY
}
# Needs pyyaml as well as jsonschema's absence-tolerant cousin above needs
# jsonschema: the brief's own guard checked only for python3, which is the
# same gap Task 2 found and fixed for the manifest checks (check() has no way
# to tell "the tool is missing" from "the check failed" on its own -- that is
# what the guard form is for).
if have python3 && have_pyyaml; then
  check "one nerd font, declared everywhere it renders" one_nerd_font
else
  skip "one nerd font, declared everywhere it renders" "python3/pyyaml not installed"
fi

# --- The terminal opens on ext4, not /mnt/c ----------------------------------
# Addendum B3: neither check above would notice startingDirectory being
# deleted, misspelled, or pointed at /mnt/c. Point 3 -- the distro segment
# matching the distro configuration.winget installs -- is the valuable one,
# and it is the same argument as the one-nerd-font check above: two files
# naming the same thing must be made to agree by a check, not by whoever edits
# one of them remembering the other exists.
starting_directory_stays_on_wsl() {
  python3 - << 'PY'
import json, re, sys, yaml

problems = []

def jsonc(path):
    s = open(path, encoding='utf-8').read()
    s = re.sub(r'^\s*//.*$', '', s, flags=re.M)
    s = re.sub(r',(\s*[}\]])', r'\1', s)
    return json.loads(s)

wt = jsonc('windows/terminal/settings.json')
sd = wt.get('profiles', {}).get('defaults', {}).get('startingDirectory')

if not sd:
    problems.append('profiles.defaults.startingDirectory is missing')
else:
    low = sd.lower()
    if 'wsl$' not in low and 'wsl.localhost' not in low:
        problems.append('profiles.defaults.startingDirectory %r does not reference wsl$ or wsl.localhost' % sd)
    if re.match(r'^[a-zA-Z]:', sd) or 'userprofile' in low:
        problems.append('profiles.defaults.startingDirectory %r points at the Windows side (a C: path or %%USERPROFILE%%)' % sd)

    doc = yaml.safe_load(open('windows/configuration.winget', encoding='utf-8'))
    ubuntu = [r for r in doc['properties']['resources']
              if r.get('id') == 'ubuntu' and r['resource'] == 'PSDscResources/Script']
    set_script = ubuntu[0].get('settings', {}).get('SetScript', '') if ubuntu else ''
    m = re.search(r'-d\s+(\S+)', set_script)
    distro = m.group(1) if m else None
    if not distro:
        problems.append("could not find the distro name in configuration.winget's ubuntu SetScript")
    elif distro not in sd:
        problems.append('profiles.defaults.startingDirectory %r does not name the distro configuration.winget installs (%s)' % (sd, distro))

for p in problems:
    print(p)
sys.exit(1 if problems else 0)
PY
}
if have python3 && have_pyyaml; then
  check "the terminal opens on wsl, matching the distro configuration.winget installs" starting_directory_stays_on_wsl
else
  skip "the terminal opens on wsl, matching the distro configuration.winget installs" "python3/pyyaml not installed"
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
