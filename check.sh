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

# --- Which python3 -----------------------------------------------------------
# Resolved by capability, not by name. The YAML and JSON Schema checks below
# need pyyaml and jsonschema. In WSL those arrive from apt, as python3-yaml and
# python3-jsonschema, and apt installs them against /usr/bin/python3 -- but mise
# puts its own python3 shim ahead of that on PATH, and mise's interpreter has
# neither library. A bare `python3` therefore resolves to the one interpreter
# that cannot do the work, and five checks degrade to skip on a machine where
# every dependency is present and correctly declared.
#
# That was measured on this laptop, not predicted. R15 and R23 approved the apt
# packages after confirming they "do not collide" with mise's python; they do
# coexist, but the failure mode runs the other way -- the shim shadows the
# interpreter the libraries were installed for. The manifests were right and the
# checks were wrong about them, which is the same shape as every other defect
# this repo found in its own checks.
#
# So take the first python3 that can import yaml. On CI that is the one on PATH,
# where pyyaml arrives by pip; in WSL it is /usr/bin/python3. If neither can,
# this stays on PATH's python3 so the skips still name the interpreter a reader
# would go looking for.
PYTHON=python3
if ! "$PYTHON" -c "import yaml" > /dev/null 2>&1; then
  if /usr/bin/python3 -c "import yaml" > /dev/null 2>&1; then
    PYTHON=/usr/bin/python3
  fi
fi

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
# Every tracked .sh must be executable in the index, not merely on disk. git
# records the mode, and a script committed 100644 is "Permission denied" the
# first time anything execs it -- which for the statuslines is Claude Code, on
# the user's first session, with no error anyone sees. This check did not exist
# before wsl/claude/statusline.sh, subagent-statusline.sh and
# statusline-demo.sh reached the repo the same way -- ported now so it cannot
# happen a third time.
exec_bits() {
  local bad
  bad=$(git ls-files -s -- '*.sh' 'githooks/*' | awk '$1 != "100755" { print $4 }')
  [ -z "$bad" ] || {
    echo "tracked but not executable: $bad"
    return 1
  }
}
check "tracked scripts are executable in git" exec_bits

if have shellcheck; then
  check "shellcheck" shellcheck -x ./*.sh ./githooks/* ./wsl/claude/*.sh ./wsl/install.sh
else
  skip "shellcheck" "not installed"
fi

if have shfmt; then
  check "shfmt" shfmt -d ./*.sh ./githooks/* ./wsl/claude/*.sh ./wsl/install.sh
else
  skip "shfmt" "not installed"
fi

syntax_bash() {
  for f in ./*.sh ./githooks/* ./wsl/claude/*.sh ./wsl/install.sh; do bash -n "$f" || return 1; done
}
check "bash syntax" syntax_bash

# --- Windows layer -----------------------------------------------------------
# The manifest is YAML, and YAML parses on any platform. Whether the package ids
# inside it resolve is a different question, and one only a Windows machine with
# winget can answer -- so it lives in the second CI job, not here. See practice
# #8: out of a runner goes what that runner cannot answer honestly.
have_pyyaml() { "$PYTHON" -c "import yaml" > /dev/null 2>&1; }

if have "$PYTHON" && have_pyyaml; then
  check "winget manifest is valid yaml" "$PYTHON" -c "
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
  "$PYTHON" -c "import sys; sys.exit(0 if sys.flags.utf8_mode else 1)"
}
if have "$PYTHON"; then
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
  "$PYTHON" - << 'PY'
import sys, yaml

GROUPS = {
    'substrate': {'Microsoft.WSL'},
    'environment': {'Microsoft.WindowsTerminal', 'DEVCOM.JetBrainsMonoNerdFont',
                     'Microsoft.VisualStudioCode', 'Microsoft.PowerToys'},
    'authoring': {'rhysd.actionlint', 'koalaman.shellcheck', 'mvdan.shfmt', 'tamasfe.taplo'},
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
if have "$PYTHON" && have_pyyaml; then
  check "the host layer stays thin" host_layer_stays_thin
else
  skip "the host layer stays thin" "python3/pyyaml not installed"
fi

# --- Windows Terminal --------------------------------------------------------
# Replaces the Mac repo's `ghostty +validate-config`, which was its only check
# that validated configuration rather than code -- and whose absence once let CI
# report success while validating no Ghostty config at all.
wt_schema() {
  "$PYTHON" - << 'PY'
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
if have "$PYTHON" && "$PYTHON" -c "import jsonschema" 2> /dev/null; then
  check "windows terminal settings match the published schema" wt_schema
else
  skip "windows terminal settings match the published schema" "jsonschema not installed"
fi

# --- The scheme is readable where this environment actually paints -----------
# A colour scheme cannot be judged one colour at a time. What decides whether
# text is readable is the PAIR: this ink, on that background. The schema check
# above validates that every value is a colour; it has no opinion about whether
# any of them can be read.
#
# So this reads the pairs out of statusline.sh itself -- its `seg <bg> <accent>
# <ink>` calls are the exhaustive list of what the statusline paints -- maps the
# ANSI codes back through the scheme, and measures each one. Same argument as
# the one-nerd-font check: two files that have to agree, and nothing but a check
# to notice when they stop agreeing.
#
# 4.5:1 is WCAG AA for normal text. Terminal text is normal text.
scheme_contrast() {
  "$PYTHON" - << 'PYEOF'
import json, re, sys

STATUSLINE = 'wsl/claude/statusline.sh'

s = re.sub(r'^\s*//.*$', '', open('windows/terminal/settings.json', encoding='utf-8').read(), flags=re.M)
s = re.sub(r',(\s*[}\]])', r'\1', s)
wt = json.loads(s)
want = wt['profiles']['defaults']['colorScheme']
scheme = next((x for x in wt['schemes'] if x['name'] == want), None)
if scheme is None:
    print('profiles.defaults.colorScheme is %r, which no scheme defines' % want)
    sys.exit(1)

# ANSI code -> scheme key. 39 and 49 are "default foreground/background", which
# is what statusline.sh emits to step out of a colour without a full reset.
NAMES = ['black', 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'white']
CODE = {39: 'foreground', 49: 'background'}
for i, n in enumerate(NAMES):
    bright = 'bright' + n[0].upper() + n[1:]
    CODE[30 + i] = CODE[40 + i] = n
    CODE[90 + i] = CODE[100 + i] = bright


def lum(h):
    h = h.lstrip('#')

    def chan(v):
        v = int(v, 16) / 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * chan(h[0:2]) + 0.7152 * chan(h[2:4]) + 0.0722 * chan(h[4:6])


def ratio(a, b):
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


problems = []
src = open(STATUSLINE, encoding='utf-8').read()


def measure(what, fg_code, bg_code):
    fk, bk = CODE.get(fg_code), CODE.get(bg_code)
    if fk is None or bk is None:
        problems.append('%s uses an ANSI code with no scheme colour: %s on %s'
                        % (what, fg_code, bg_code))
        return
    r = ratio(scheme[fk], scheme[bk])
    if r < 4.5:
        problems.append('%s: %s %s on %s %s is %.2f:1, below WCAG AA 4.5:1'
                        % (what, fk, scheme[fk], bk, scheme[bk], r))


# Every segment the statusline paints, read from the source of truth.
segs = re.findall(r'seg (\d+) (\d+) (\d+)', src)
if not segs:
    problems.append('found no seg calls in %s -- has it been rewritten?' % STATUSLINE)
for bg, _accent, ink in segs:
    measure('statusline segment', int(ink), int(bg))

# The dimmed text: labels, separators, the second line's chrome. One slot, and
# the one most often read at a glance.
dim = re.search(r"DIM=\$'\\033\[(\d+)m'", src)
if dim:
    measure('statusline DIM', int(dim.group(1)), 49)
else:
    problems.append('could not find DIM in %s' % STATUSLINE)

# The scheme's own defaults, and text sitting on a selection.
if ratio(scheme['foreground'], scheme['background']) < 4.5:
    problems.append('foreground on background is %.2f:1, below 4.5:1'
                    % ratio(scheme['foreground'], scheme['background']))
if 'selectionBackground' in scheme:
    r = ratio(scheme['foreground'], scheme['selectionBackground'])
    if r < 4.5:
        problems.append('foreground on selectionBackground is %.2f:1, below 4.5:1' % r)

for p in problems:
    print(p)
sys.exit(1 if problems else 0)
PYEOF
}
if have "$PYTHON"; then
  check "the scheme is readable where this environment paints" scheme_contrast
else
  skip "the scheme is readable where this environment paints" "python3 not installed"
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
  "$PYTHON" - << 'PY'
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
if have "$PYTHON"; then
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
  "$PYTHON" - << 'PY'
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
if have "$PYTHON" && have_pyyaml; then
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
  "$PYTHON" - << 'PY'
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
if have "$PYTHON" && have_pyyaml; then
  check "the terminal opens on wsl, matching the distro configuration.winget installs" starting_directory_stays_on_wsl
else
  skip "the terminal opens on wsl, matching the distro configuration.winget installs" "python3/pyyaml not installed"
fi

# --- PowerShell ----------------------------------------------------------------
# windows/*.ps1 is not parsed here. It was, briefly: guarded by `have pwsh ||
# have powershell`, which is honest about the precondition but does not fix
# the real problem -- this script's whole contract is that its verdict means
# the same thing wherever it runs, which is why --strict turns a skip into a
# failure and why a check that did not run is not a check that passed. A
# check that structurally cannot run on the target machine (WSL has no
# PowerShell, and this repo is not putting one there just to lint two files)
# breaks that contract no matter how it is guarded; the guard only makes the
# breakage quiet. The mirror of this rule already exists for drift.sh: out of
# CI goes what CI cannot answer honestly. Out of check.sh goes what check.sh
# cannot answer everywhere.
#
# The coverage moved rather than disappeared: the windows CI job's
# PSScriptAnalyzer step is the only thing checking windows/*.ps1 now, and it
# is load-bearing there rather than belt-and-braces -- see that job for the
# other half of this reasoning. The cost, stated rather than hidden: a .ps1
# syntax error is no longer caught on the authoring host before push. On a
# repo whose Windows layer is two files, that is a cost worth paying to keep
# this file's verdict meaning one thing everywhere it runs.

# --- WSL manifests -----------------------------------------------------------
if have taplo; then
  check "toml" taplo lint
  check "toml format" taplo fmt --check --diff
else
  skip "toml" "taplo not installed"
  skip "toml format" "taplo not installed"
fi

# --- GitHub Actions workflows -------------------------------------------------
# .github/workflows/ci.yml is otherwise the one file in this repo nothing
# lints: it is YAML, so the schema and manifest checks above do not touch it,
# and it is not shell. actionlint is pinned, checksum-verified and version-
# asserted in ci.yml's own ubuntu job already -- installing it there had no
# second purpose until now. actionlint with no arguments finds the nearest
# .github/workflows directory on its own, confirmed against `actionlint
# --help` rather than assumed.
if have actionlint; then
  check "actionlint" actionlint
else
  skip "actionlint" "not installed"
fi

# Every tool in uv-tools.txt carries a reference, because a bare name resolves to
# whatever PyPI has today -- which is the pin thrown away, silently.
uv_tools_manifest() {
  local line name ref bad=0
  while read -r line; do
    line=${line%%#*}
    [ -z "${line// /}" ] && continue
    read -r name ref <<< "$line"
    if [ -z "$ref" ]; then
      echo "no reference for $name"
      bad=1
    fi
  done < wsl/uv-tools.txt
  return "$bad"
}
check "uv-tools.txt declares a pinned reference per tool" uv_tools_manifest

# apt and mise must not both claim the same package. A tool installed by two
# managers has two versions and one PATH, and which one wins is an accident.
no_manager_overlap() {
  local apt_list mise_list dupes
  apt_list=$(sed 's/#.*//' wsl/apt-packages.txt | tr -d ' ' | grep -v '^$' | sort)
  mise_list=$(sed 's/#.*//' wsl/mise/config.toml | grep -oE '^[a-z0-9_-]+ = ' | tr -d ' =' | sort)
  dupes=$(comm -12 <(echo "$apt_list") <(echo "$mise_list"))
  [ -z "$dupes" ] || {
    echo "declared by both apt and mise: $dupes"
    return 1
  }
}
check "apt and mise do not claim the same package" no_manager_overlap

# The linter versions are declared in three places: the WSL manifest, the Windows
# host manifest and the CI workflow. They must agree, or the same file gets three
# verdicts depending on where it was checked -- which is the one thing this repo's
# whole check discipline rests on not happening.
#
# Asserted rather than trusted to bump-tools.sh, because a hand edit never goes
# near the bumper, and because the bumper itself missed these for a while.
linter_versions_agree() {
  "$PYTHON" - << 'PY'
import re, sys

def mise(tool):
    for line in open('wsl/mise/config.toml', encoding='utf-8'):
        m = re.match(r'^%s = "([^"]+)"' % tool, line)
        if m:
            return m.group(1)

def winget(pkg):
    s = open('windows/configuration.winget', encoding='utf-8').read()
    m = re.search(r'id:\s*%s\s*\n\s*source:\s*winget\s*\n\s*version:\s*"?([^"\s]+)"?' % re.escape(pkg), s)
    if not m:
        m = re.search(r'version:\s*"?([^"\s]+)"?\s*\n\s*id:\s*%s' % re.escape(pkg), s)
    return m.group(1) if m else None

def ci(var):
    for line in open('.github/workflows/ci.yml', encoding='utf-8'):
        m = re.match(r'\s*%s:\s*v?([0-9.]+)' % var, line)
        if m:
            return m.group(1)

problems = []
for tool, pkg, var in (('shellcheck', 'koalaman.shellcheck', 'SHELLCHECK_VERSION'),
                       ('shfmt', 'mvdan.shfmt', 'SHFMT_VERSION'),
                       ('taplo', 'tamasfe.taplo', 'TAPLO_VERSION'),
                       ('actionlint', 'rhysd.actionlint', 'ACTIONLINT_VERSION')):
    got = {'mise': mise(tool), 'winget': winget(pkg), 'ci': ci(var)}
    if None in got.values():
        problems.append('%s: could not read a version from every file: %s' % (tool, got))
    elif len(set(got.values())) != 1:
        problems.append('%s disagrees across files: %s' % (tool, got))

for p in problems:
    print(p)
sys.exit(1 if problems else 0)
PY
}
if have "$PYTHON"; then
  check "the linter versions agree across all three manifests" linter_versions_agree
else
  skip "the linter versions agree across all three manifests" "python3 not installed"
fi

# actionlint reached this file the same way the PowerShell check almost
# stayed: a tool check.sh depends on, guarded by have() so its own absence is
# graceful, with nothing asserting that the WSL machine this hook actually
# runs on ever installs it. "Declared for CI" and "declared for the machine
# that runs the checks" are different claims, and nothing checked the second
# one -- twice, independently, before this existed.
#
# The tool list below is not a second hand-maintained list of names: that
# shape is exactly what went stale twice already (linter_versions_agree's own
# tuple list needed a fourth entry by hand; bump-tools.sh's old mirror list
# needed the same). It is read out of check.sh's own source instead, so a new
# have() guard is covered the moment it is written, not the moment someone
# remembers to also update a check about it.
guarded_tools_are_declared() {
  "$PYTHON" - << 'PY'
import re
import sys

# A tool have()-guarded here that is deliberately not meant to be declared
# for WSL. Empty today, on purpose, not because no such tool could ever
# exist: PowerShell was the one candidate, and the resolution there was to
# remove the check rather than exempt the tool, because check.sh's contract
# is that its verdict means the same thing wherever it runs -- a check that
# structurally cannot run in WSL does not belong in this file at all, guarded
# or not. A name only belongs here if a future have()-guarded check has some
# other legitimate reason to exist in check.sh without a WSL install path;
# state that reason next to the name when one is added, the same way this
# paragraph states why the list starts empty.
EXCLUDE = set()

text = open('check.sh', encoding='utf-8').read()
have_tools = set()
for line in text.splitlines():
    stripped = line.strip()
    if stripped.startswith('#'):
        continue
    for m in re.finditer(r'(?:^|[(&|]|\bif\s+|\belif\s+|\bwhile\s+)!?\s*have\s+([a-z][a-z0-9_.-]*)', stripped):
        have_tools.add(m.group(1))
have_tools -= EXCLUDE

apt_text = open('wsl/apt-packages.txt', encoding='utf-8').read()
mise_text = open('wsl/mise/config.toml', encoding='utf-8').read()

missing = []
for tool in sorted(have_tools):
    in_apt = re.search(r'^%s$' % re.escape(tool), apt_text, re.M) is not None
    in_mise = re.search(r'^%s = "' % re.escape(tool), mise_text, re.M) is not None
    if not (in_apt or in_mise):
        missing.append(tool)

if missing:
    print('have()-guarded in check.sh but declared in no WSL manifest: %s' % ', '.join(missing))
    sys.exit(1)
PY
}
if have "$PYTHON"; then
  check "every have()-guarded tool is declared for WSL" guarded_tools_are_declared
else
  skip "every have()-guarded tool is declared for WSL" "python3 not installed"
fi

# --- zsh and the prompt -------------------------------------------------------
syntax_zsh() {
  have zsh || return 0
  for f in wsl/zsh/.zshenv wsl/zsh/.zshrc; do zsh -n "$f" || return 1; done
}
if have zsh; then
  check "zsh syntax" syntax_zsh
else
  skip "zsh syntax" "zsh not installed"
fi

# The Mac's .zprofile does not belong here and its absence is deliberate. This
# asserts nobody reintroduces it by reflex when copying from the other repo.
no_zprofile() {
  [ ! -e wsl/zsh/.zprofile ] || {
    echo "wsl/zsh/.zprofile exists. It solved macOS path_helper, which Linux does not have."
    return 1
  }
}
check "no .zprofile (the macOS problem it solved does not exist here)" no_zprofile

# Nothing in the repo may assume /mnt/c is a working path. A comment that
# explains why it is kept off PATH is not an assumption -- it is the rule
# being documented -- so comment lines are filtered out rather than whole
# files excluded; excluding a file by name would make it permanently
# invisible to this check, including for a real assumption written into it
# later.
#
# The pattern deliberately omits the leading slash. Git for Windows rewrites
# an argument that looks like an absolute Unix path into a Windows path
# before git.exe sees it, so '/mnt/c' matches nothing here -- the check
# passed on every run while inspecting nothing, until a deliberate probe
# caught it. 'mnt/c' matches the same lines and is not rewritten, on either
# platform.
#
# Each exclusion below has its own reason. They are not interchangeable, and a
# new one needs its own justification rather than being added by analogy:
#   ':!*.md'          markdown is prose. This check guards config and code,
#                     where an assumption is executed rather than described.
#   ':!check.sh'      this file necessarily contains the pattern it searches for.
#   '"Read(//mnt/c'   a deny rule REFUSES the path rather than assuming it. Kept
#                     to that exact string so a permissive entry -- an
#                     additionalDirectories pointing at /mnt/c, say -- still
#                     fires in the same file.
#
#                     The double slash is required, and excusing only that form
#                     is deliberate. A deny rule written `Read(/mnt/c/...)` with
#                     one slash resolves relative to the settings directory and
#                     cannot fire, which is how twenty inert rules sat in this
#                     repo looking like protection (R36). Written this way, a
#                     regression to the single-slash form is not excused here and
#                     fails this check -- so the mistake now has two independent
#                     ways to be caught rather than none.
#   'mnt/c/Windows/System32/'  reaching a Windows system binary by absolute path
#                     is not the same as treating /mnt/c as a working path.
#                     drift.sh needs cmd.exe to reach winget.exe, because
#                     install.sh removes the Windows PATH from WSL on purpose.
#                     Scoped to System32 rather than to drift.sh: that file is
#                     the likeliest place a real /mnt/c assumption would appear,
#                     so it must stay visible to this check.
no_mnt_c() {
  local hits
  hits=$(git grep -nI 'mnt/c' -- . ':!*.md' ':!check.sh' |
    grep -vE '^[^:]+:[0-9]+:[[:space:]]*(#|//)' |
    grep -vE '"Read\(//mnt/c' |
    grep -vE 'mnt/c/Windows/System32/' || true)
  [ -z "$hits" ] || {
    echo "$hits"
    return 1
  }
}
check "no file assumes /mnt/c" no_mnt_c

# --- Git ---------------------------------------------------------------------
check "gitconfig parses" git config --file wsl/git/config --list

# Identity must never be in the repo. This is the check that lets the repo be
# public: config.local is included by relative path and lives outside git.
#
# Grepped across the whole tree, not just wsl/git/config: that file was never
# the only door into the repo, and it was the only one guarded. install.sh's
# own git-identity heredoc walked straight past a check that grepped one file
# and reported PASS. check.sh excludes itself because its own check function
# has to spell out what it is looking for.
#
# No file-type exclusion here, deliberately. An earlier version skipped *.md to
# avoid matching `name=$(basename ...)` in a runbook; that also hid a real
# address in the plan document for a round. Requiring whitespace before the `=`
# separates the two by syntax rather than by file type -- shell assignment cannot
# have a space there, git config conventionally does -- so there is no file this
# check cannot see.
#
# install.sh still writes lines shaped exactly like `name = ...` and
# `email = ...` -- that heredoc is the git-config skeleton config.local is
# supposed to look like, placeholders and all, and a check that flagged its own
# placeholders would fail forever, on every commit, for a file that is correct.
# The allowlist below is anchored to the whole `path:lineno:content` line, front
# and back: unanchored, `grep -v` only needs the line to END in a placeholder,
# so `email = real@person.com  # was: email = change@me.invalid` would launder
# straight through. Only wsl/install.sh's placeholders, verbatim and alone on
# the line, are let through; a real name or address anywhere else still fails.
no_identity_in_repo() {
  local hits
  hits=$(git grep -nE '^[[:space:]]*(name|email)[[:space:]]+=' -- . ':!check.sh' |
    grep -vE '^[^:]+:[0-9]+:[[:space:]]*(name|email)[[:space:]]+=[[:space:]]*(CHANGE ME|change@me\.invalid)$' || true)
  [ -z "$hits" ] || {
    echo "identity in the repo: $hits"
    return 1
  }
}
check "git identity is not in the repo" no_identity_in_repo

# The Mac's ignore file is macOS-specific and this one must not inherit it.
no_macos_in_ignore() {
  local hits
  hits=$(grep -nE 'DS_Store|AppleDouble|Spotlight-V100|__MACOSX' wsl/git/ignore || true)
  [ -z "$hits" ] || {
    echo "macOS entries in a Linux ignore file: $hits"
    return 1
  }
}
check "git/ignore carries no macOS entries" no_macos_in_ignore

# --- Claude Code -------------------------------------------------------------
check "claude settings" "$PYTHON" -c "import json; json.load(open('wsl/claude/settings.json', encoding='utf-8'))"

# The Windows host's credential stores are readable from inside WSL. They are
# not on the Mac, because there is no host. This asserts every category is
# denied in BOTH forms: the glob is the rule, the literal is the guarantee. A
# pattern that silently fails to match is worse than no pattern -- it reads as
# protection while providing none, and this list is exercised for the first
# time by a human, by hand, in Task 12.
deny_covers_the_host() {
  "$PYTHON" - << 'PY'
import json, sys
deny = json.load(open('wsl/claude/settings.json', encoding='utf-8'))['permissions']['deny']

# One template per category, both forms built from it, so a tenth category is
# one line and cannot arrive with only one of its two forms.
#
# The leading DOUBLE slash is the whole point of this check, and it is not a
# typo. In a permission rule a single leading slash is relative to the settings
# file's own directory, so `Read(/mnt/c/...)` resolves under ~/.claude/ and can
# never match anything. Two slashes mean the filesystem root. These rules shipped
# with one slash and were inert -- proven on 2026-08-18 by reading a probe file
# inside a supposedly denied directory, which succeeded, and denied immediately
# once the rule was rewritten with two. See R36.
#
# This check passed throughout, because it compared the settings file against
# templates carrying the same mistake. Asserting a rule is present is not
# asserting it can fire.
templates = [
    '//mnt/c/Users/{}/.ssh/**',
    '//mnt/c/Users/{}/.aws/**',
    '//mnt/c/Users/{}/.azure/**',
    '//mnt/c/Users/{}/.docker/config.json',
    '//mnt/c/Users/{}/.git-credentials',
    '//mnt/c/Users/{}/.claude/.credentials.json',
    '//mnt/c/Users/{}/AppData/Roaming/gh/hosts.yml',
    '//mnt/c/Users/{}/AppData/Roaming/npm/**',
    '//mnt/c/Users/{}/AppData/Roaming/gcloud/**',
    '//mnt/c/Users/{}/AppData/Roaming/Microsoft/Windows/PowerShell/PSReadLine/ConsoleHost_history.txt',
]
need = []
for p in templates:
    # The guard below is not defensive noise. str.format() ignores its argument
    # when there is no {} to fill, so a template written without one yields two
    # identical entries -- the loop still appends twice, the count still looks
    # right, and the check silently verifies one string twice while reporting
    # that it verified both forms. That is the same shape as a check that
    # passes while inspecting nothing.
    if '{}' not in p:
        print('template has no {} placeholder, so both forms would be identical: %s' % p)
        sys.exit(1)
    need.append(p.format('camilo.piedrahita'))
    need.append(p.format('*'))

missing = [n for n in need if 'Read(%s)' % n not in deny]
if missing:
    print('deny does not cover the Windows host: %s' % ', '.join(missing))
    sys.exit(1)
PY
}
check "the deny list covers the Windows host, not just Linux" deny_covers_the_host

# effortLevel absent on purpose: the model's own default is already high, and
# writing it down would freeze it -- a better default in a future model would be
# overridden by a line nobody revisits.
no_effort_level() {
  "$PYTHON" -c "
import json, sys
s = json.load(open('wsl/claude/settings.json', encoding='utf-8'))
sys.exit(1 if 'effortLevel' in s else 0)
" || {
    echo "effortLevel is set; it freezes a default that improves on its own"
    return 1
  }
}
check "effortLevel is absent on purpose" no_effort_level

# ── Statusline behaviour ─────────────────────────────────────────────────────
# These are pure functions from a JSON payload to a line of text, which makes
# them the one thing here that can be tested properly.
printf '\n%sStatusline%s\n' "$DIM" "$OFF"

check "demo renders" bash -c './wsl/claude/statusline-demo.sh > /dev/null'

# A freshly opened session has no context and no limits yet. Printing a broken
# line there is worse than printing a short one.
minimal_payload() {
  local out
  out=$(echo '{"model":{"display_name":"Opus 5"},"cwd":"/tmp"}' | ./wsl/claude/statusline.sh)
  case "$out" in
    *"Opus 5"*) return 0 ;;
    *)
      echo "model missing from a minimal payload: $out"
      return 1
      ;;
  esac
}
check "minimal payload still renders the model" minimal_payload

# Garbage in must mean nothing out, never a half-rendered line: Claude prints
# whatever we emit, junk included.
invalid_json_is_silent() {
  local out
  out=$(echo 'not json' | ./wsl/claude/statusline.sh)
  [ -z "$out" ] || {
    echo "emitted output for invalid JSON: $out"
    return 1
  }
}
check "invalid json produces no output" invalid_json_is_silent

subagent_rows() {
  local payload out
  payload='{"columns":80,"tasks":[
    {"id":"a","name":"brisk-otter","type":"local_agent","status":"running",
     "startTime":1,"model":"claude-opus-5","contextWindowSize":200000,
     "tokenCount":48000,"tokenSamples":[1,2,3]},
    {"id":"b","type":"local_bash","status":"running","startTime":1,"tokenCount":0}]}'
  out=$(echo "$payload" | ./wsl/claude/subagent-statusline.sh)

  [ "$(echo "$out" | wc -l | tr -d ' ')" = 2 ] || {
    echo "expected 2 rows, got: $out"
    return 1
  }
  echo "$out" | jq -e . > /dev/null || {
    echo "not valid JSONL: $out"
    return 1
  }
  echo "$out" | jq -e 'has("id") and has("content")' > /dev/null || return 1

  # The name is the only part of the row you can address an agent by, so its
  # absence is a regression worth failing on.
  echo "$out" | head -1 | jq -e '.content | contains("brisk-otter")' > /dev/null ||
    {
      echo "agent name missing from the row"
      return 1
    }

  # A task without a name must still render, not vanish.
  echo "$out" | tail -1 | jq -e '.content | length > 0' > /dev/null ||
    {
      echo "unnamed task rendered empty"
      return 1
    }
}
check "subagent rows are valid jsonl with the agent name" subagent_rows

# --- install.sh is idempotent -------------------------------------------------
# Adapted from the Mac's install_is_idempotent, with every path pointed at
# wsl/install.sh instead -- and run with --links-only, not the bare script.
#
# The full script installs apt packages, downloads pinned runtimes with mise,
# fetches Python CLIs with uv, clones antidote, edits /etc/wsl.conf and can
# change the login shell. None of that belongs in a check githooks/pre-commit
# runs on every commit, and a temporary HOME does not sandbox any of it --
# sudo does not care about $HOME, and apt and mise write outside it too.
# --links-only exists in wsl/install.sh for exactly this: it runs only the
# steps that do respect $HOME, the symlinks and the git identity file, so this
# check can call the real script instead of a paraphrase of it.
#
# What this asserts, precisely, because it is easy to overclaim: the second
# run backs up nothing, which is the signal that link() found every
# destination already correct. Idempotency of apt, mise, uv and antidote is
# NOT exercised here -- those steps never run under --links-only -- and stays
# deferred to a real run: see docs/runbook-tasks-10-11-build-and-migrate.md,
# which is where a human first sees the full script run twice.

# On this Windows host `ln -s` does not fail -- it silently copies the target
# instead of linking it, so the capability has to be probed rather than
# assumed from the presence of some other tool. `have apt-get && have sudo`
# used to stand in for "a real Ubuntu host," but --links-only needs neither of
# those: a Linux CI container without a sudo binary would skip this check, and
# CI forces --strict, turning a check that would have passed into a FAIL for a
# reason the guard's own text gets wrong.
have_symlinks() {
  local d probe
  d=$(mktemp -d) || return 1
  : > "$d/target"
  ln -s target "$d/link" 2> /dev/null
  [ -L "$d/link" ]
  probe=$?
  rm -rf "$d"
  return "$probe"
}

install_is_idempotent() {
  local tmphome first second status=0
  tmphome=$(mktemp -d)

  first=$(HOME="$tmphome" \
    XDG_CONFIG_HOME="$tmphome/.config" \
    XDG_DATA_HOME="$tmphome/.local/share" \
    XDG_STATE_HOME="$tmphome/.local/state" \
    ./wsl/install.sh --links-only 2>&1) || {
    echo "first run failed:"
    echo "$first"
    rm -rf "$tmphome"
    return 1
  }

  second=$(HOME="$tmphome" \
    XDG_CONFIG_HOME="$tmphome/.config" \
    XDG_DATA_HOME="$tmphome/.local/share" \
    XDG_STATE_HOME="$tmphome/.local/state" \
    ./wsl/install.sh --links-only 2>&1) || {
    echo "second run failed:"
    echo "$second"
    rm -rf "$tmphome"
    return 1
  }

  if echo "$second" | grep -q 'backed up:'; then
    echo "second run backed up a file -- linking is not idempotent"
    echo "$second"
    status=1
  fi

  rm -rf "$tmphome"
  return "$status"
}
if have_symlinks; then
  check "install.sh --links-only is idempotent" install_is_idempotent
else
  skip "install.sh --links-only is idempotent" "this filesystem does not support symlinks"
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
