# Workstation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn this Windows 11 laptop into a declared, reproducible development environment — a thin WinGet DSC layer on the host and Ubuntu 26.04 LTS under WSL2 where the work happens — carrying seventeen practices from the macOS `dotfiles` repo without sharing a file with it.

**Architecture:** Two strata in one repository. `windows/` declares only what makes the WSL layer reachable, visible or typeable: the subsystem, a terminal, a font, an editor. `wsl/` declares the actual environment: apt for the system, mise for runtimes and tools, uv for Python CLIs, plus zsh, starship, git and Claude Code. One `check.sh` in bash validates both, run by you, by the pre-commit hook, and by CI.

**Tech Stack:** WinGet Configuration (DSC 0.2), PowerShell 5.1 (host bootstrap only), WSL2, Ubuntu 26.04 LTS, bash, zsh + antidote, starship, mise, uv, git, Claude Code.

**Spec:** `docs/superpowers/specs/2026-08-18-workstation-design.md`

## Global Constraints

- **Everything written into a file is in English.** Names, comments, commit messages, documentation, log strings, CLI output. Only conversation with the user is Spanish. A check enforces this.
- **Line endings are LF everywhere.** `.gitattributes` declares `* text=auto eol=lf`. No file exempted, `.ps1` included.
- **Nothing is `latest`.** Every tool, runtime and CI dependency is pinned, and every pin carries its reason and its expiry in a comment next to it.
- **A check that did not run is not a check that passed.** `check.sh` is amber-skip when run by hand and hard-fail under `--strict`, which is automatic when `CI` is set and in the pre-commit hook.
- **Secrets and identity never enter the repo.** Git identity lives in `~/.config/git/config.local`, outside the repo. The repo is public.
- **`/mnt/c` is never a working path.** No file in the repo may assume it. Repositories live on ext4 at `~/Development`.
- **Every config key is validated against its published schema**, vendored under `schemas/`. A key the schema does not know is a failure, not a warning.
- **Target versions:** Ubuntu 26.04 LTS, node 26 (reverts to `"lts"` on 2026-10-28), python 3.14, pnpm 11, WinGet Configuration schema 0.2, `configurationVersion: 0.2.0`.
- **Source repo for ported content:** `camilopiedra92/dotfiles` on GitHub. Clone it to a scratch path to copy from; never add it as a submodule, remote or dependency.

---

## Phase 0 — Foundation

### Task 1: Repo foundation and the check harness

Nothing on the machine changes in this task. It produces the gate that every later task passes through.

**Files:**
- Create: `check.sh`
- Create: `.editorconfig`
- Create: `.taplo.toml`
- Create: `githooks/pre-commit`
- Create: `githooks/pre-push`
- Modify: none (`.gitattributes` and `.gitignore` already exist)

**Interfaces:**
- Produces: `check()` and `skip()` shell functions, the `STRICT` variable, and the convention that every later task appends one `check "<name>" <function-or-command>` line to `check.sh`. Exit 0 = all passed; exit 1 = something failed, or something skipped while `STRICT=1`.

- [ ] **Step 1: Write `check.sh` with the harness and two real checks**

```bash
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
  *) echo "usage: $0 [--strict]" >&2; exit 2 ;;
esac

GREEN=$'\033[32m'
RED=$'\033[31m'
AMBER=$'\033[33m'
DIM=$'\033[90m'
OFF=$'\033[0m'

FAILED=0
SKIPPED=0

check() { # check <name> <command...>
  local name="$1"; shift
  local out
  if out=$("$@" 2>&1); then
    printf '%sPASS%s %s\n' "$GREEN" "$OFF" "$name"
  else
    printf '%sFAIL%s %s\n' "$RED" "$OFF" "$name"
    [ -n "$out" ] && printf '%s%s%s\n' "$DIM" "$out" "$OFF"
    FAILED=1
  fi
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
  [ -z "$hits" ] || { echo "files containing CR: $hits"; return 1; }
}
check "no carriage returns in tracked files" no_crlf

# --- English only ------------------------------------------------------------
# The repo is English-only by policy (wsl/claude/CLAUDE.md). The pattern is
# written as escapes rather than literal accented characters so that this file
# does not itself violate the rule it enforces.
english_only() {
  local hits
  hits=$(git grep -nIP '[\x{00E1}\x{00E9}\x{00ED}\x{00F3}\x{00FA}\x{00F1}\x{00C1}\x{00C9}\x{00CD}\x{00D3}\x{00DA}\x{00D1}\x{00BF}\x{00A1}]' \
    -- . ':!docs/superpowers/**' || true)
  [ -z "$hits" ] || { echo "$hits"; return 1; }
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
```

- [ ] **Step 2: Break the CRLF check on purpose, and watch it fail**

A check nobody has watched fail is a check nobody should rely on. This step is not optional.

```bash
cd ~/Development/workstation      # or the Windows path, if not yet migrated
printf 'a\r\nb\r\n' > /tmp/crlf-probe.txt
cp /tmp/crlf-probe.txt ./crlf-probe.txt
git add -f crlf-probe.txt
./check.sh
```

Expected: `FAIL no carriage returns in tracked files`, listing `crlf-probe.txt`, and exit 1.

Then undo, and confirm it goes green again:

```bash
git rm -f --cached crlf-probe.txt && rm -f crlf-probe.txt
./check.sh
```

Expected: `PASS no carriage returns in tracked files`.

- [ ] **Step 3: Prove strict mode changes the verdict**

```bash
./check.sh                # shellcheck absent -> SKIP, exit 0
echo "exit=$?"
./check.sh --strict       # same tree, same absent tool -> FAIL, exit 1
echo "exit=$?"
```

Expected: first run ends `All checks passed, some skipped.` with `exit=0`; second ends `Some checks failed.` with `exit=1`. Same tree, same missing tool, opposite verdicts. If both runs agree, strict mode is not wired and the hook below is worthless.

- [ ] **Step 4: Write `githooks/pre-commit`**

```bash
#!/usr/bin/env bash
# Runs the repo's checks before every commit.
#
# Lives in githooks/ rather than .git/hooks/ because the latter is not
# versioned: a hook nobody else receives is a hook that only protects the
# machine it was written on. install.sh points core.hooksPath here.
#
# Escape hatch:  git commit --no-verify
set -uo pipefail

repo=$(git rev-parse --show-toplevel)

# --strict, because this is a gate and not a report. A hook that exits 0 having
# linted nothing says "this commit passed" when what happened is that nothing
# checked it -- and the commit lands either way. It also makes the hook agree
# with the gate that judges it afterwards: CI turns strict on by itself, so
# without this the local run is the more permissive of the two and waves through
# exactly what CI will reject.
if ! "$repo/check.sh" --strict; then
  echo "Commit aborted. Fix the above, or bypass with: git commit --no-verify" >&2
  exit 1
fi
```

- [ ] **Step 5: Write `githooks/pre-push`**

Copy verbatim from the `dotfiles` repo at `githooks/pre-push`. It is platform-independent: it refuses to delete or force-push the default branch by comparing ancestry rather than by looking for a flag git never passes to hooks. Its header comment already states plainly that it is defence in depth and that the real defence is a server-side ruleset.

- [ ] **Step 6: Write `.editorconfig`**

Copy from `dotfiles` at `.editorconfig`, then add one section, because this repo has PowerShell and the Mac repo does not:

```ini
[*.ps1]
indent_style = space
indent_size = 4
end_of_line = lf
```

- [ ] **Step 7: Write `.taplo.toml`**

Copy from `dotfiles` at `.taplo.toml`, changing the schema paths from `mise/config.toml` to `wsl/mise/config.toml` and from `starship.toml` to `wsl/starship.toml`.

- [ ] **Step 8: Wire the hooks and verify the gate fires**

```bash
git config core.hooksPath githooks
chmod +x check.sh githooks/pre-commit githooks/pre-push
git update-index --chmod=+x check.sh githooks/pre-commit githooks/pre-push
```

Then prove the hook is a gate, not decoration:

```bash
printf 'echo "unquoted $var"\n' >> check.sh   # introduces a shellcheck finding
git add check.sh && git commit -m "probe"
```

Expected: the commit is **refused**, with `FAIL shellcheck` (or `FAIL shellcheck (not installed)` if shellcheck is absent — either way, refused). Revert the probe line before continuing.

- [ ] **Step 9: Commit**

```bash
git add check.sh .editorconfig .taplo.toml githooks/
git commit -m "Add the check harness and the git hooks that gate on it

check.sh is the only place checks are written. It is a report when you run it
and a gate under --strict, which CI sets by itself and the pre-commit hook
passes explicitly. Measured: with shellcheck absent, the plain run ends
'All checks passed, some skipped' at exit 0 and the strict run ends
'Some checks failed' at exit 1. Same tree, same missing tool, opposite verdicts."
```

---

## Phase 1 — The Windows layer

### Task 2: Declare the host and make it appliable

**Files:**
- Create: `windows/configuration.winget`
- Create: `windows/bootstrap.ps1`
- Modify: `check.sh` (append the YAML checks)

**Interfaces:**
- Produces: a `winget configure`-appliable manifest that installs WSL2, Ubuntu 26.04 LTS, Windows Terminal, VS Code with Remote-WSL, JetBrainsMono Nerd Font and PowerToys. Task 6 applies it. Task 3 depends on the font and the terminal being declared here, and the one-nerd-font check in Task 3 parses this file.

**Naming note, and a correction to the spec.** Microsoft's documented convention is the `.winget` extension with the default at `./.config/configuration.winget`. This repo takes the extension — which is what carries the schema association and the tooling recognition — and declines the directory, because `.config/` at the repo root would put the Windows layer outside the two-strata structure that the rest of the repo is organised by. Record the deviation in the file header. The spec says `configuration.dsc.yaml`; `configuration.winget` supersedes it, and the spec should be amended in Task 18.

- [ ] **Step 1: Write `windows/configuration.winget`**

```yaml
# yaml-language-server: $schema=https://aka.ms/configuration-dsc-schema/0.2
#
# The Windows host, declared. This file is the counterpart of the Mac repo's
# Brewfile and it is not a compromise: WinGet Configuration is declarative,
# idempotent, official, and applied with one command.
#
# It declares four kinds of thing and nothing else: the subsystem, a terminal, a
# font, an editor. Everything here exists to make the WSL layer reachable,
# visible or typeable. The moment something that is not one of those four wants
# to be installed on the host, that is the signal the boundary is being crossed
# for a bad reason.
#
# Naming: Microsoft's convention is ./.config/configuration.winget. The
# extension is kept, because that is what carries the schema association. The
# directory is not, because .config/ at the repo root would place the Windows
# layer outside the two-strata structure this repo is organised by.
#
# Apply:     winget configure .\windows\configuration.winget
# Validate:  winget configure validate .\windows\configuration.winget
#
# git is deliberately absent. All git work happens in WSL, where
# `gh auth setup-git` provides credentials, mirroring the Mac exactly. A
# host-side credential-manager bridge is the documented alternative and is
# rejected: it creates a cross-boundary dependency to solve a problem that does
# not exist once nothing on the host uses git.
properties:
  assertions:
    # WSL2 and the modern winget both require Windows 10 1809+; this machine is
    # Windows 11 build 26200. The floor is asserted rather than assumed so that
    # applying this on a different machine fails at the precondition instead of
    # halfway through an install.
    - resource: Microsoft.Windows.Developer/OsVersion
      directives:
        description: Require Windows 10 21H2 or newer
        allowPrerelease: true
      settings:
        MinVersion: '10.0.22000'

  resources:
    # ---- The substrate ----
    # Ubuntu 26.04 LTS: released April 2026, supported to 2031. The alternative,
    # 24.04, runs out in 2029. Unlike Node, Ubuntu LTS has no parity trap to
    # sidestep -- every LTS gets the same five years -- so the newest one simply
    # is the right one, with no date to revisit.
    - resource: Microsoft.WinGet.DSC/WinGetPackage
      id: ubuntu
      directives:
        description: Install Ubuntu 26.04 LTS on WSL2
        securityContext: elevated
      settings:
        id: Canonical.Ubuntu.2604
        source: winget

    # ---- The terminal ----
    # Replaces Ghostty, which does not run on Windows and is not on its roadmap.
    # The machine currently has 1.18.10301, several versions behind.
    - resource: Microsoft.WinGet.DSC/WinGetPackage
      id: terminal
      directives:
        description: Install Windows Terminal
        securityContext: elevated
      settings:
        id: Microsoft.WindowsTerminal
        source: winget

    # ---- The font ----
    # Exactly one Nerd Font, and check.sh asserts that it is exactly one. Two
    # installed is not better than one: when something falls back, or a family
    # name is misspelled, a second Nerd Font lets it resolve to the wrong one and
    # still work, with glyphs that look subtly different and no way to tell why.
    - resource: Microsoft.WinGet.DSC/WinGetPackage
      id: font
      directives:
        description: Install JetBrainsMono Nerd Font
        securityContext: elevated
      settings:
        id: DEVCOM.JetBrainsMonoNerdFont
        source: winget

    # ---- The editor ----
    # Installed on the host and used against WSL through Remote-WSL. That is the
    # supported model, and it is why settings.json splits in two: host-side
    # rendering here, toolchain-side settings in wsl/vscode/settings.json.
    - resource: Microsoft.WinGet.DSC/WinGetPackage
      id: vscode
      directives:
        description: Install Visual Studio Code
        securityContext: elevated
      settings:
        id: Microsoft.VisualStudioCode
        source: winget

    # ---- Mac muscle memory ----
    # PowerToys is here for Keyboard Manager specifically, which Microsoft's own
    # Mac-to-Windows guide recommends for remapping Command-key habits.
    - resource: Microsoft.WinGet.DSC/WinGetPackage
      id: powertoys
      directives:
        description: Install PowerToys
        securityContext: elevated
      settings:
        id: Microsoft.PowerToys
        source: winget

  configurationVersion: 0.2.0
```

- [ ] **Step 2: Verify every package id resolves before trusting the file**

Package ids are the one thing here that cannot be validated by a schema. Prove each one:

```bash
for id in Canonical.Ubuntu.2604 Microsoft.WindowsTerminal DEVCOM.JetBrainsMonoNerdFont \
          Microsoft.VisualStudioCode Microsoft.PowerToys; do
  printf '%-40s ' "$id"
  winget.exe show --id "$id" --exact > /dev/null 2>&1 && echo OK || echo "NOT FOUND"
done
```

Expected: `OK` for all five. Any `NOT FOUND` is a real finding — resolve it with `winget.exe search <name>` and correct the manifest. Do not proceed with a guessed id.

- [ ] **Step 3: Validate the manifest against the DSC schema**

```bash
winget.exe configure validate .\\windows\\configuration.winget
```

Expected: validation succeeds with no errors.

- [ ] **Step 4: Write `windows/bootstrap.ps1`**

```powershell
# The one imperative step in this repo.
#
# Everything it can hand to a declarative tool, it hands over: the whole host
# layer is configuration.winget, and this script's job is to get winget to a
# state where it can apply it, then get out of the way.
#
# Usage (PowerShell, from the repo root):
#   .\windows\bootstrap.ps1
#
# Re-running is safe. winget configure is idempotent by design: it applies only
# what is not already in the desired state.

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $PSScriptRoot 'configuration.winget'

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Blue }

# winget configure landed in v1.6.2631. Asserting the floor turns "the command
# does nothing recognisable" into a sentence that says why.
Write-Step 'Checking winget version'
$wingetVersion = (winget --version).TrimStart('v')
$required = [version]'1.6.2631'
if ([version]($wingetVersion -split '-')[0] -lt $required) {
    throw "winget $wingetVersion is older than $required, which is where 'winget configure' was added. Update from the Microsoft Store (App Installer)."
}
Write-Host "    winget $wingetVersion"

# Enabling configuration is a one-time, per-machine acknowledgement. It is
# separate from applying anything, and asking for it here rather than letting
# the apply fail is the difference between a prompt and an error.
Write-Step 'Enabling winget configuration'
winget settings --enable Configuration

Write-Step 'Applying the host configuration'
winget configure $manifest --accept-configuration-agreements

Write-Step 'Host layer applied.'
Write-Host ''
Write-Host 'Next, inside Ubuntu:' -ForegroundColor Yellow
Write-Host '  git clone https://github.com/camilopiedra92/workstation ~/workstation'
Write-Host '  ~/workstation/wsl/install.sh'
```

- [ ] **Step 5: Append the manifest checks to `check.sh`**

Insert before the `# --- Summary ---` block:

```bash
# --- Windows layer -----------------------------------------------------------
# The manifest is YAML, and YAML parses on any platform. Whether the package ids
# inside it resolve is a different question, and one only a Windows machine with
# winget can answer -- so it lives in the second CI job, not here. See practice
# #8: out of a runner goes what that runner cannot answer honestly.
if have python3; then
  check "winget manifest is valid yaml" python3 -c "
import sys, yaml
yaml.safe_load(open('windows/configuration.winget'))
" 2> /dev/null || skip "winget manifest is valid yaml" "pyyaml not installed"
else
  skip "winget manifest is valid yaml" "python3 not installed"
fi

# The host layer declares four kinds of thing: the subsystem, a terminal, a font,
# an editor -- plus PowerToys for Mac keyboard habits. Anything else is the
# boundary leaking, and a leak nobody notices is a leak that grows.
host_layer_stays_thin() {
  python3 - << 'PY'
import sys, yaml
allowed = {
    'Canonical.Ubuntu.2604', 'Microsoft.WindowsTerminal',
    'DEVCOM.JetBrainsMonoNerdFont', 'Microsoft.VisualStudioCode',
    'Microsoft.PowerToys',
}
doc = yaml.safe_load(open('windows/configuration.winget'))
declared = {
    r['settings']['id']
    for r in doc['properties']['resources']
    if r['resource'].endswith('/WinGetPackage')
}
extra = declared - allowed
if extra:
    print('host layer declares packages outside the allowed set: %s' % ', '.join(sorted(extra)))
    print('If this is deliberate, widen the set here and say why in the manifest.')
    sys.exit(1)
PY
}
if have python3; then
  check "the host layer stays thin" host_layer_stays_thin
else
  skip "the host layer stays thin" "python3 not installed"
fi
```

- [ ] **Step 6: Run the checks**

```bash
./check.sh
```

Expected: `PASS winget manifest is valid yaml`, `PASS the host layer stays thin`, everything else still passing or amber-skipping.

- [ ] **Step 7: Commit**

```bash
git add windows/ check.sh
git commit -m "Declare the Windows host layer

configuration.winget installs the subsystem, a terminal, a font and an editor,
and nothing else. A check asserts that set stays closed, because the boundary
leaking is the failure mode this layer has.

Naming follows Microsoft's .winget extension but not the ./.config/ directory:
the extension carries the schema association, the directory would place the
Windows layer outside the two strata this repo is organised by."
```

---

### Task 3: Declare the visual environment, coherently

Ghostty's config translated to Windows Terminal, VS Code's host-side settings, and the check that asserts the font is the same in all three plus the manifest.

**Files:**
- Create: `windows/terminal/settings.json`
- Create: `windows/vscode/settings.json`
- Create: `schemas/windows-terminal.json`
- Modify: `check.sh`

**Interfaces:**
- Consumes: `windows/configuration.winget` from Task 2 — the one-nerd-font check parses its `DEVCOM.JetBrainsMonoNerdFont` entry.
- Produces: the declaration sites the font check reads — Windows Terminal `profiles.defaults.font.face`, VS Code `editor.fontFamily`, VS Code `terminal.integrated.fontFamily`.

- [ ] **Step 1: Vendor the Windows Terminal schema**

```bash
mkdir -p schemas
curl -fsSL https://aka.ms/terminal-profiles-schema -o schemas/windows-terminal.json
python3 -c "import json; json.load(open('schemas/windows-terminal.json')); print('valid json')"
```

Expected: `valid json`. Vendoring rather than fetching at check time is the same reasoning as `tool-checksums.txt`: a schema fetched at validation time can change under you, and a check whose rules move is a check you stop trusting.

- [ ] **Step 2: Confirm which Ghostty settings have a counterpart, before writing any**

Do not write a key and hope. For each candidate, grep the vendored schema:

```bash
for key in face size features cellHeight colorScheme opacity useAcrylic padding \
           cursorShape historySize copyOnSelect unfocusedAppearance; do
  printf '%-22s ' "$key"
  grep -q "\"$key\"" schemas/windows-terminal.json && echo present || echo ABSENT
done
```

Confirmed present in Microsoft's published docs already: `font.face`, `font.size`, `font.features` (OpenType tags as `"tag": integer`), `colorScheme`, `opacity` (integer 0–100), `useAcrylic`, `padding` (`"left, top, right, bottom"`), `cursorShape` (`"filledBox"` is the block), `unfocusedAppearance`.

Any key that comes back `ABSENT` does **not** get written speculatively. It goes in the file's "not ported" comment block with the reason. A dropped setting that is written down is information; one silently omitted is a hole.

- [ ] **Step 3: Write `windows/terminal/settings.json`**

Use `font.cellHeight` only if Step 2 reported it present; otherwise move the `adjust-cell-height = 12%` line into the not-ported block.

```jsonc
{
  "$schema": "https://aka.ms/terminal-profiles-schema",

  // Windows Terminal, translated from the Mac's ghostty/config.
  //
  // What did not port, recorded rather than omitted:
  //   font-thicken            a macOS antialiasing correction; the problem it
  //                           solves does not exist on Windows' rasteriser
  //   window-colorspace=p3    no counterpart
  //   background-blur=macos-glass  the nearest thing is useAcrylic, which is a
  //                           different material, not the same one renamed
  //   window-padding-color=extend  no counterpart
  //   minimum-contrast        no counterpart
  //
  // Every other key below was confirmed against schemas/windows-terminal.json
  // before being written. check.sh re-confirms it on every run.

  "defaultProfile": "{2c4de342-38b7-51cf-b940-2309a097f518}",
  "copyOnSelect": true,
  "copyFormatting": "none",

  "profiles": {
    "defaults": {
      "font": {
        // The same font as the Mac, and as VS Code below. check.sh asserts all
        // three agree and that exactly one Nerd Font is declared installed.
        "face": "JetBrainsMono Nerd Font",
        "size": 14,
        // JetBrains Mono ships no `liga`; its ligatures live in `calt`.
        // `zero` slashes the zero -- the single highest-value feature in a
        // terminal, where 0 and O collide constantly in paths and hashes.
        // `ss02` is the font's "Closed construction": narrower apertures on
        // a/c/e/s. A letterform preference, unrelated to ligatures.
        "features": { "calt": 1, "zero": 1, "ss02": 1 }
      },
      // Catppuccin Mocha, the same theme as the Mac's Ghostty.
      "colorScheme": "Catppuccin Mocha",
      // Ghostty: window-padding-x = 18, window-padding-y = 14.
      // Order here is left, top, right, bottom.
      "padding": "18, 14, 18, 14",
      // Ghostty: background-opacity = 0.90. This scale is 0-100.
      // Unblurred opacity requires Windows 11, which this machine is.
      "opacity": 90,
      "useAcrylic": true,
      "cursorShape": "filledBox",
      // Ghostty: scrollback-limit = 100000000 bytes. This is a line count, so
      // it is not the same number expressed differently -- it is a different
      // unit, chosen to be generous rather than converted.
      "historySize": 100000,
      // Ghostty: unfocused-split-opacity = 0.6. Windows Terminal applies this
      // per window rather than per split, which is the closest thing it has.
      "unfocusedAppearance": { "opacity": 70 }
    },
    "list": [
      {
        "guid": "{2c4de342-38b7-51cf-b940-2309a097f518}",
        "name": "Ubuntu 26.04 LTS",
        "source": "Windows.Terminal.Wsl",
        "hidden": false,
        // The work lives on ext4 and never on /mnt/c. Starting here rather than
        // in the Windows home directory is what makes that the path of least
        // resistance instead of a rule to remember.
        "startingDirectory": "//wsl$/Ubuntu-26.04/home/camilo"
      },
      { "guid": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}", "name": "Windows PowerShell", "hidden": false },
      { "guid": "{0caa0dad-35be-5f56-a8ff-afceeeaa6101}", "name": "Command Prompt", "hidden": true }
    ]
  },

  "schemes": [],

  "actions": [
    {
      // Shift+Enter inserts a line break instead of sending the message.
      // Essential for multi-line prompts in Claude Code, and the single
      // keybinding whose absence is noticed within a minute.
      "command": { "action": "sendInput", "input": "\n" },
      "keys": "shift+enter"
    }
  ]
}
```

- [ ] **Step 4: Add the Catppuccin Mocha scheme**

The `schemes` array above is empty and `colorScheme` names a scheme that does not exist yet — which Windows Terminal resolves by silently falling back to Campbell. Fetch the official scheme and paste it in:

```bash
curl -fsSL https://raw.githubusercontent.com/catppuccin/windows-terminal/main/mocha.json
```

Paste the returned object into the `schemes` array. Then confirm the name matches exactly what `colorScheme` asks for:

```bash
python3 - << 'PY'
import json, re
s = open('windows/terminal/settings.json').read()
s = re.sub(r'^\s*//.*$', '', s, flags=re.M)
d = json.loads(s)
names = [x['name'] for x in d['schemes']]
want = d['profiles']['defaults']['colorScheme']
print('schemes:', names, '| wanted:', want, '|', 'OK' if want in names else 'MISMATCH')
PY
```

Expected: `OK`. A `MISMATCH` here is exactly the silent-fallback failure this step exists to prevent.

- [ ] **Step 5: Write `windows/vscode/settings.json` (host side)**

```jsonc
{
  // VS Code, host side. This file holds what the local UI renders; anything
  // that needs the toolchain lives in wsl/vscode/settings.json and is applied
  // to the Remote-WSL machine scope. A setting on the wrong side of that line
  // silently does nothing, which is the failure mode this split prevents.

  // ---------- Font ----------
  // The same font and features as windows/terminal/settings.json, so a prompt
  // looks identical in either terminal. Left unset, VS Code falls back to
  // Consolas, and what breaks under it is `eza --icons`, which the ls/ll/la/lt
  // aliases all pass: its icons are Private Use Area codepoints only a Nerd Font
  // carries, so every line of a listing starts with an empty box. The starship
  // prompt survives -- it is built from standard Unicode arrows.
  "editor.fontFamily": "JetBrainsMono Nerd Font, Consolas, monospace",
  "editor.fontLigatures": "'calt', 'zero', 'ss02'",
  // Stated separately even though the terminal would inherit the line above:
  // this is the one that has to be a Nerd Font, and an inherited value is the
  // kind that gets broken by an unrelated edit.
  "terminal.integrated.fontFamily": "JetBrainsMono Nerd Font",

  // ---------- Appearance ----------
  "workbench.iconTheme": "material-icon-theme",
  "workbench.startupEditor": "none",
  "workbench.editor.empty.hint": "hidden",

  // ---------- Terminal ----------
  // The default profile is WSL, not PowerShell. Nothing on this machine is
  // developed against Windows, so a PowerShell prompt opening by default is an
  // invitation to work in the wrong place.
  "terminal.integrated.defaultProfile.windows": "Ubuntu-26.04",

  // ---------- Remote ----------
  // Extensions that must be installed inside WSL rather than on the host. VS
  // Code otherwise installs them locally, where they cannot see the toolchain.
  "remote.WSL.fileWatcher.polling": false,

  // ---------- Noise ----------
  "telemetry.telemetryLevel": "off",
  // Red Hat extensions ship their own telemetry on a separate switch that
  // telemetry.telemetryLevel does not reach. Set here so it is already off if
  // one is ever installed.
  "redhat.telemetry.enabled": false,
  "update.showReleaseNotes": false
}
```

- [ ] **Step 6: Append the schema and font-coherence checks to `check.sh`**

```bash
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
s = re.sub(r'^\s*//.*$', '', open('windows/terminal/settings.json').read(), flags=re.M)
s = re.sub(r',(\s*[}\]])', r'\1', s)
jsonschema.validate(json.loads(s), json.load(open('schemas/windows-terminal.json')))
PY
}
if have python3 && python3 -c "import jsonschema" 2> /dev/null; then
  check "windows terminal settings match the published schema" wt_schema
else
  skip "windows terminal settings match the published schema" "jsonschema not installed"
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
    s = open(path).read()
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
doc = yaml.safe_load(open('windows/configuration.winget'))
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
if have python3; then
  check "one nerd font, declared everywhere it renders" one_nerd_font
else
  skip "one nerd font, declared everywhere it renders" "python3 not installed"
fi
```

- [ ] **Step 7: Break the font check on purpose**

```bash
sed -i 's/"terminal.integrated.fontFamily": "JetBrainsMono Nerd Font"/"terminal.integrated.fontFamily": "Consolas"/' windows/vscode/settings.json
./check.sh
```

Expected: `FAIL one nerd font, declared everywhere it renders`, with
`terminal.integrated.fontFamily is 'Consolas', windows terminal uses 'JetBrainsMono Nerd Font'`.

Revert:

```bash
git checkout windows/vscode/settings.json
./check.sh
```

Expected: back to `PASS`.

- [ ] **Step 8: Commit**

```bash
git add windows/ schemas/ check.sh
git commit -m "Translate the terminal and declare the font once

Ghostty's config becomes Windows Terminal's, key by key, each one confirmed
against the vendored schema before being written. Five settings have no
counterpart and are recorded as not ported rather than omitted: a dropped
setting that is written down is information, one silently dropped is a hole.

The font is declared in three places and installed in a fourth, and a check
asserts all four agree and that exactly one Nerd Font is installed."
```

---

### Task 4: Apply the host layer

**The machine changes in this task.** Everything before it was files.

**Files:** none. This task runs what Tasks 2 and 3 declared.

- [ ] **Step 1: Record what the machine looks like first**

So that "it worked" is a comparison and not an impression:

```bash
wsl.exe -l -v 2>&1 | tr -d '\0'
winget.exe list --id Microsoft.WindowsTerminal --exact 2>&1 | tail -2
```

Expected before: only `docker-desktop`; Windows Terminal 1.18.10301.

- [ ] **Step 2: Apply**

In PowerShell, from the repo root. This prompts once for UAC.

```powershell
.\windows\bootstrap.ps1
```

- [ ] **Step 3: Verify each declared thing arrived**

```bash
wsl.exe -l -v 2>&1 | tr -d '\0'          # expect Ubuntu-26.04, VERSION 2
winget.exe list --id Microsoft.WindowsTerminal --exact 2>&1 | tail -2   # expect >= 1.22
winget.exe list --id DEVCOM.JetBrainsMonoNerdFont --exact 2>&1 | tail -2
winget.exe list --id Microsoft.PowerToys --exact 2>&1 | tail -2
```

If Ubuntu is listed at `VERSION 1`, stop and fix it before continuing — WSL1 has none of the filesystem performance this design depends on:

```powershell
wsl --set-version Ubuntu-26.04 2
wsl --set-default-version 2
```

- [ ] **Step 4: Create the Ubuntu user**

```powershell
wsl -d Ubuntu-26.04
```

First launch prompts for a UNIX username and password. Use `camilo`. The `startingDirectory` in `windows/terminal/settings.json` hardcodes `/home/camilo`; if a different name is chosen, that line must be corrected and committed in the same breath.

- [ ] **Step 5: Prove the filesystem claim rather than trusting it**

The whole "repos live on ext4" decision rests on this number. Measure it on this machine:

```bash
wsl.exe -d Ubuntu-26.04 -- bash -c '
  echo "--- ext4 ---"; cd ~ && time (mkdir -p bench && cd bench && for i in $(seq 1 2000); do echo x > f$i; done && rm -rf ~/bench)
  echo "--- /mnt/c ---"; cd /mnt/c/Users/camilo.piedrahita && time (mkdir -p bench && cd bench && for i in $(seq 1 2000); do echo x > f$i; done && rm -rf /mnt/c/Users/camilo.piedrahita/bench)
'
```

Record both numbers in the commit message. If ext4 is not dramatically faster, that is a finding worth stopping for, not a result to round past.

- [ ] **Step 6: Deploy the Terminal settings and confirm the font renders**

```bash
cp windows/terminal/settings.json \
  "/c/Users/camilo.piedrahita/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
```

Open Windows Terminal. Expected, by eye: it opens on Ubuntu 26.04, the Catppuccin Mocha palette, JetBrains Mono with a slashed zero, and `ls` glyphs that are icons rather than empty boxes. An empty box means the font did not resolve — check the family name against `font.face` exactly.

- [ ] **Step 7: Commit the measurement**

```bash
git commit --allow-empty -m "Apply the host layer

WSL2 with Ubuntu 26.04 LTS, Windows Terminal, JetBrainsMono Nerd Font, VS Code
and PowerToys, all from configuration.winget.

Measured on this machine, 2000 small file creations:
  ext4 (~):        <fill in from Step 5>
  /mnt/c:          <fill in from Step 5>
which is why ~/Development is the working path and /mnt/c is not."
```

---

## Phase 2 — The WSL layer

### Task 5: The manifests

**Files:**
- Create: `wsl/apt-packages.txt`
- Create: `wsl/mise/config.toml`
- Create: `wsl/uv-tools.txt`
- Create: `schemas/mise.json`
- Modify: `check.sh`

**Interfaces:**
- Produces: three manifests `wsl/install.sh` (Task 9) reads, and `drift.sh` (Task 12) compares the machine against.

**Boundary, restated for this platform.** The Mac's rule is *"Homebrew installs programs, mise installs runtimes. Never a runtime through Homebrew."* The naive translation puts apt in Homebrew's place and is wrong: apt carries stale versions of exactly the tools in use here, and `starship` is not in apt at all. The rule here:

> **apt installs what the system needs. mise installs everything you use — runtimes and tools alike. uv installs Python CLIs.**

This does not violate the Mac rule, which forbids a *runtime* from the system package manager. What changes is that mise's domain widens to user tools, and that serves the pinning discipline better than apt does: mise's `ubi` and `aqua` backends install at a pinned version with a checksum, while apt gives whatever is in the archive that day.

- [ ] **Step 1: Write `wsl/apt-packages.txt`**

```
# Packages apt installs, one per line. `#` starts a comment.
#
# This list is deliberately short, and the boundary is the reason. apt installs
# what the SYSTEM needs -- compilers, libraries, the shell itself, things other
# packages link against. Everything YOU use comes from mise, which pins with a
# checksum where apt gives you whatever is in the archive that day.
#
# Adding a tool here that mise could install is how the boundary starts leaking.
# The test: would this still need to exist if you never opened a terminal? If
# yes, apt. If no, mise.

# Build toolchain. mise compiles some tools from source and every one of them
# fails without this, with an error that names a missing header rather than a
# missing package.
build-essential
pkg-config
libssl-dev

# The shell. It is the login shell, so it must come from the system: a shell
# installed under a version manager cannot be listed in /etc/shells.
zsh

# Fetching and unpacking, which mise itself needs before it can install anything.
curl
ca-certificates
unzip

# git is here rather than from mise for the same reason as zsh: it is what the
# system's own tooling shells out to.
git
```

- [ ] **Step 2: Write `wsl/mise/config.toml`**

```toml
# Runtimes and tools, pinned.
#
# The boundary: apt installs what the system needs, mise installs everything you
# use. The Mac repo's rule -- never a runtime through the system package manager
# -- is preserved; what widens is mise's domain, to user tools as well. That
# serves the pinning discipline better than apt does, because the ubi and aqua
# backends install at a fixed version with a checksum while apt gives whatever is
# in the archive that day.

[tools]
# A major, not "lts", and that is a deliberate choice with an expiry date.
#
# 26 is Current today: it entered on 2026-04-21 and becomes Active LTS on
# 2026-10-28, supported until 2029-04-30. Asking for it by number is the only
# way to be on it before that date, since "lts" resolves to 24 until then.
#
# The two converge in October. Once 26 is the LTS, changing this back to "lts"
# is a no-op that restores the tracking -- the pin moves on its own again
# instead of freezing here until someone remembers to edit it. Do that then.
#
# What this is NOT is "latest". That would land on 27 next October, and
# odd-numbered majors never become LTS: they ship in October and are out of
# support roughly six months later.
node = "26"

# Python has no LTS and none of the reasoning above transfers. Every stable
# release gets the same five years, so the newest stable simply is the
# recommended one. 3.14 shipped 2025-10-07, supported to 2030-10-31.
#
# The minor is pinned rather than "latest" for the one reason that does apply:
# 3.15 arrives this October and the C-extension packages that matter take months
# to publish wheels for it.
#
# One version, not two. The Mac carries a second 3.13 solely because the gcloud
# CLI ships no interpreter and gsutil refuses anything above 3.13. There is no
# gcloud on this machine, so that entry is not carried. It comes back when
# gcloud does, with the same reasoning written next to it -- copying it now would
# be carrying a workaround for a problem this machine does not have.
python = "3.14"

# The package manager for new node projects. Here rather than in a global npm
# install because `npm i -g` writes into the node install directory down to the
# patch, so a patch bump moves that directory and the global vanishes without a
# word. mise owns this the way it owns the runtimes.
#
# pnpm rather than npm because npm's node_modules is flat: a package can require
# something it never declared, because a transitive dependency got hoisted next
# to it. pnpm's layout is symlinked, so a package resolves only what it declares.
#
# The major is the pin because the lockfile format travels with it.
pnpm = "11"

# ---- User tools ----
# Everything below would come from Homebrew on the Mac. Here they come from mise,
# for the reason in the header: pinned with a checksum rather than whatever apt
# has. The version is a floor written as an exact pin so a bump is a visible diff.
starship = "1.24.0"   # the prompt; not in apt at all
eza = "0.24.7"        # ls, with icons the Nerd Font carries
bat = "0.26.0"        # cat, with syntax highlighting
fd = "10.4.0"         # find, and what FZF_DEFAULT_COMMAND calls
ripgrep = "14.1.1"    # grep
fzf = "0.68.0"        # the fuzzy picker fzf-tab drives
zoxide = "0.9.9"      # cd, with frecency
jq = "1.8.1"          # what statusline.sh parses its payload with
delta = "0.19.0"      # git's pager
uv = "0.9.9"          # Python packages, venvs and the CLIs in uv-tools.txt
```

- [ ] **Step 3: Verify every pinned version actually exists**

A pin to a version that was never released fails at install time, far from here.

```bash
for t in starship eza bat fd ripgrep fzf zoxide jq delta uv; do
  want=$(grep -E "^$t = " wsl/mise/config.toml | sed 's/.*"\(.*\)".*/\1/')
  printf '%-10s %-10s ' "$t" "$want"
  mise ls-remote "$t" 2>/dev/null | grep -qx "$want" && echo OK || echo "NOT A RELEASED VERSION"
done
```

Run this after Task 10 installs mise if mise is not yet available. Any `NOT A RELEASED VERSION` is corrected to the newest release at the time of writing, never rounded to `latest`.

- [ ] **Step 4: Write `wsl/uv-tools.txt`**

```
# Command-line applications installed with `uv tool`, one per line.
#
# This is the third package manager here, and the only one that arrives without
# a manifest of its own. apt reads its list and mise reads mise/config.toml;
# `uv tool` keeps its state under `uv tool dir` and has nothing to read a list
# from, so a machine rebuilt from this repo would come up without these. This
# file is that list: install.sh applies it, drift.sh compares it against what the
# machine actually has.
#
# Two fields separated by whitespace: the package name, and the reference to
# install it from. The reference is not redundant with the name -- a bare name
# resolves to PyPI at whatever version is current, which is the pin thrown away.
# `#` starts a comment.

# Spec-Driven Development CLI, part of GitHub Spec Kit.
#
# Pinned to a release tag, which is the form upstream's README lists first and
# the only form where `specify self check` and `specify self upgrade` behave as
# documented: both detect how the CLI was installed and rewrite this same
# reference, so a pin here is a pin they know how to move. `uv tool upgrade`
# cannot move it -- a fixed rev gives it nothing to resolve -- and that is not a
# workaround to route around but the reason the self commands exist.
specify-cli  git+https://github.com/github/spec-kit.git@v0.16.4
```

- [ ] **Step 5: Vendor the mise schema and append the manifest checks**

```bash
curl -fsSL https://mise.jdx.dev/schema/mise.json -o schemas/mise.json
```

Then append to `check.sh` before the summary:

```bash
# --- WSL manifests -----------------------------------------------------------
if have taplo; then
  check "toml" taplo lint
  check "toml format" taplo fmt --check --diff
else
  skip "toml" "taplo not installed"
  skip "toml format" "taplo not installed"
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
      echo "no reference for $name"; bad=1
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
  [ -z "$dupes" ] || { echo "declared by both apt and mise: $dupes"; return 1; }
}
check "apt and mise do not claim the same package" no_manager_overlap
```

- [ ] **Step 6: Break the overlap check on purpose**

```bash
echo "jq" >> wsl/apt-packages.txt
./check.sh
```

Expected: `FAIL apt and mise do not claim the same package`, naming `jq`. Revert with `git checkout wsl/apt-packages.txt`.

- [ ] **Step 7: Commit**

```bash
git add wsl/ schemas/ check.sh
git commit -m "Declare the WSL manifests

The manager boundary is restated for this platform: apt installs what the system
needs, mise installs everything you use. That widens mise's domain to user tools
without breaking the Mac rule it comes from, and serves pinning better than apt
does -- ubi and aqua install a fixed version with a checksum, apt gives whatever
is in the archive that day.

python is single-valued here. The Mac carries a second 3.13 for gsutil under
gcloud; there is no gcloud on this machine, and copying the entry would be
carrying a workaround for a problem that does not exist here."
```

---

### Task 6: The shell

**Files:**
- Create: `wsl/zsh/.zshenv`, `wsl/zsh/.zshrc`, `wsl/zsh/.zsh_plugins.txt`
- Create: `wsl/starship.toml`
- Create: `schemas/starship.json`
- Modify: `check.sh`

**Interfaces:**
- Produces: `$ZDOTDIR` at `~/.config/zsh`, a `PATH` with mise shims first, and the starship prompt. Task 9's `install.sh` links these files.

**What dies here, and why that is a good sign.** The Mac's `.zprofile` disappears entirely — forty lines explaining `path_helper`, the measured table of PATH positions, the re-source. Linux has no `path_helper`. That the complexity evaporates on changing platform confirms it was diagnosed correctly: it was a macOS problem, not a shell problem.

What survives is the double link of `.zshenv`. That branch — `ZDOTDIR` exported or not — is zsh behaviour, not macOS behaviour, and applies identically here.

- [ ] **Step 1: Write `wsl/zsh/.zshenv`**

```bash
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
```

- [ ] **Step 2: Write `wsl/zsh/.zshrc`**

Copy from `dotfiles` at `zsh/.zshrc`, with exactly these changes:

1. Delete the two `HOMEBREW_*` exports — there is no Homebrew here.
2. Replace `alias update-all='brew upgrade && brew cleanup && mise upgrade && antidote update'` with:
   ```bash
   alias update-all='sudo apt update && sudo apt upgrade -y && mise upgrade && antidote update'
   ```
3. Replace `alias dotfiles='cd ~/dotfiles'` with `alias workstation='cd ~/workstation'`.
4. Delete `alias nuke='sudo dev-nuke'` — `bin/dev-nuke.sh` is not ported (it is Homebrew and macOS caches).
5. Add, after the aliases block:
   ```bash
   # Windows interop, deliberately narrow. These are the only Windows binaries
   # this environment calls, and naming them individually is what keeps
   # /mnt/c/... off PATH -- see the note in .zshenv about why that matters for
   # correctness and not only for speed.
   alias explorer='explorer.exe'
   alias clip='clip.exe'
   ```
6. Keep everything else — history options, completion styles, fzf-tab config, key bindings, the eza/bat aliases, `c` and `cc` for Claude Code.

- [ ] **Step 3: Write `wsl/zsh/.zsh_plugins.txt`**

Copy from `dotfiles` at `zsh/.zsh_plugins.txt` with one deletion and one comment correction:

- Delete the line `ohmyzsh/ohmyzsh path:plugins/macos` — `ofd`, `pfd`, `cdf` and `showfiles` are all macOS Finder commands.
- In the header's WATCH OUT paragraph, replace the list of Homebrew-provided completions with: *"check it does not duplicate something mise already provides — gh, mise, uv, bat, eza, fd, rg, zoxide and starship all ship their own completions."*

Keep the ordering comment verbatim. It is the load-bearing part of the file: completions → compinit → rest → syntax highlighting → history search.

- [ ] **Step 4: Copy `wsl/starship.toml`**

Copy from `dotfiles` at `starship.toml` **unchanged**. starship is cross-platform and this file has no macOS in it. This is the one file in the entire repo that transfers without a single byte changing, and that is worth stating in the commit message.

- [ ] **Step 5: Vendor the starship schema and append the checks**

```bash
curl -fsSL https://starship.rs/config-schema.json -o schemas/starship.json
```

```bash
# --- Shell -------------------------------------------------------------------
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

# Nothing in the repo may assume /mnt/c is a working path.
no_mnt_c() {
  local hits
  hits=$(git grep -nI '/mnt/c' -- . ':!docs/**' ':!check.sh' || true)
  [ -z "$hits" ] || { echo "$hits"; return 1; }
}
check "no file assumes /mnt/c" no_mnt_c
```

- [ ] **Step 6: Run the checks and commit**

```bash
./check.sh
git add wsl/ schemas/ check.sh
git commit -m "Port the shell, and delete what macOS made necessary

.zprofile does not come across. It existed to undo macOS path_helper, which
rebuilds PATH rather than appending to it; Linux has no path_helper, so the
forty lines explaining it are gone with the problem. A check asserts it stays
gone, because copying it back from the other repo is a one-keystroke mistake.

The double link of .zshenv does come across: that branch is zsh behaviour, not
macOS behaviour.

starship.toml transfers with not one byte changed -- the only file in this repo
of which that is true."
```

---

### Task 7: Git

**Files:**
- Create: `wsl/git/config`, `wsl/git/ignore`
- Modify: `check.sh`

**Interfaces:**
- Produces: `~/.config/git/config` and `~/.config/git/ignore` after `install.sh` links them. Identity is expected at `~/.config/git/config.local`, which the repo never contains.

- [ ] **Step 1: Write `wsl/git/config`**

Copy from `dotfiles` at `git/config` with these changes:

1. Both credential helper blocks change from `!/opt/homebrew/bin/gh auth git-credential` to `!/usr/bin/gh auth git-credential`. Confirm the path after Task 10 with `command -v gh` and correct it if it differs.
2. `core.fsmonitor` and `core.untrackedCache` are **removed for now**, with this comment in their place:

```
[core]
	# There is no excludesfile here on purpose. git's default is already
	# $XDG_CONFIG_HOME/git/ignore, which is exactly where this repo links its
	# global ignore. Naming it would only be necessary to point somewhere
	# non-standard -- and doing that silently disables the default path.
	#
	# fsmonitor and untrackedCache are NOT set here, and their absence is a
	# measurement and not an oversight. On macOS fsmonitor is backed by FSEvents,
	# where the Mac repo measured it as the difference between seconds and
	# milliseconds. Here it would be git's own daemon watching a virtualised ext4
	# volume under WSL2, which is a different mechanism with a different cost.
	# Step 3 of this task measures it on this machine. A setting that buys
	# nothing is not neutral: it is a claim nobody checked.
```

3. Everything else carries over unchanged — `init.defaultBranch`, `push.autoSetupRemote`, `push.followTags`, `pull.rebase`, `commit.verbose`, `rerere`, `fetch.prune`, `transfer.fsckObjects`, `rebase.autoSquash/autoStash/updateRefs`, `merge.conflictStyle = zdiff3`, `diff.algorithm = histogram`, `diff.colorMoved`, `diff.mnemonicPrefix`, `branch.sort`, `tag.sort`, `column.ui`, `help.autocorrect`, and the `[include] path = config.local` at the top.

- [ ] **Step 2: Write `wsl/git/ignore`**

Copy from `dotfiles` at `git/ignore`, then:

1. **Delete** the entire macOS block — `.DS_Store`, `.localized`, `__MACOSX/`, `.AppleDouble`, `.LSOverride`, `Icon[[:cntrl:]]`, `._*`, `.Spotlight-V100`, `.Trashes`, `.fseventsd`, `.TemporaryItems`, `.AppleDB`, `.AppleDesktop`, `Network Trash Folder`, `Temporary Items`, `.apdisk`.
2. **Add** at the top:

```
# Linux
.directory
.Trash-*
.nfs*
.fuse_hidden*

# Windows.
#
# No Windows process works in these repos -- they live on ext4 inside WSL and
# nothing on the host touches them. This block is here for the one path that
# still exists: browsing \\wsl$ in File Explorer, which writes these files into
# whatever directory it renders.
Thumbs.db
Thumbs.db:encryptable
ehthumbs.db
Desktop.ini
$RECYCLE.BIN/
*.lnk
```

3. Keep the editors block verbatim, including the un-ignore lines for `.vscode/settings.json`, `tasks.json`, `launch.json`, `extensions.json` and `*.code-snippets`, and its comment explaining why a blanket `.vscode/` is wrong.
4. Keep the JetBrains, swap-file, secrets and `**/.claude/settings.local.json` blocks verbatim.

- [ ] **Step 3: Measure `core.fsmonitor` before deciding**

Run after Task 11 has migrated a real repository. Do not decide from the Mac's numbers.

```bash
cd ~/Development/surge-pods
git config --local core.fsmonitor false
for i in 1 2 3; do /usr/bin/time -f '%e off' git status > /dev/null; done
git config --local core.fsmonitor true
git status > /dev/null   # warm the daemon
for i in 1 2 3; do /usr/bin/time -f '%e on ' git status > /dev/null; done
git config --local --unset core.fsmonitor
```

If `on` is meaningfully faster, add `fsmonitor = true` and `untrackedCache = true` to `wsl/git/config` with the measured numbers in the comment. If it is not, leave them out and record the numbers in the commit message. Either outcome is a result; only skipping the measurement is a failure.

- [ ] **Step 4: Append the git checks**

```bash
# --- Git ---------------------------------------------------------------------
check "gitconfig parses" git config --file wsl/git/config --list

# Identity must never be in the repo. This is the check that lets the repo be
# public: config.local is included by relative path and lives outside git.
no_identity_in_repo() {
  local hits
  hits=$(grep -nE '^\s*(name|email)\s*=' wsl/git/config || true)
  [ -z "$hits" ] || { echo "identity in the repo: $hits"; return 1; }
}
check "git identity is not in the repo" no_identity_in_repo

# The Mac's ignore file is macOS-specific and this one must not inherit it.
no_macos_in_ignore() {
  local hits
  hits=$(grep -nE 'DS_Store|AppleDouble|Spotlight-V100|__MACOSX' wsl/git/ignore || true)
  [ -z "$hits" ] || { echo "macOS entries in a Linux ignore file: $hits"; return 1; }
}
check "git/ignore carries no macOS entries" no_macos_in_ignore
```

- [ ] **Step 5: Break the identity check, then commit**

```bash
printf '\n[user]\n\tname = Probe\n' >> wsl/git/config
./check.sh    # expect FAIL git identity is not in the repo
git checkout wsl/git/config
./check.sh    # expect PASS

git add wsl/git check.sh
git commit -m "Port the git config, minus what was measured on the other machine

core.fsmonitor and untrackedCache are deliberately absent pending measurement on
this machine. On macOS they are backed by FSEvents; here it would be git's own
daemon over a virtualised ext4 volume, which is a different mechanism at a
different cost. Numbers go in the comment once taken.

The ignore file drops the macOS block entirely and gains a small Windows one --
not because anything on the host works in these repos, but because browsing
\\\\wsl\$ in Explorer writes Thumbs.db into whatever it renders."
```

---

### Task 8: Claude Code

**Files:**
- Create: `wsl/claude/settings.json`
- Create: `wsl/claude/CLAUDE.md`
- Create: `wsl/claude/statusline.sh`
- Create: `wsl/claude/subagent-statusline.sh`
- Create: `wsl/claude/statusline-demo.sh`
- Modify: `check.sh`

**Interfaces:**
- Produces: the settings `install.sh` merges into `~/.claude/settings.json` with `jq`, and the two statusline scripts it links to `~/.claude/`.

- [ ] **Step 1: Copy the three statusline scripts unchanged**

From `dotfiles`: `claude/statusline.sh`, `claude/subagent-statusline.sh`, `claude/statusline-demo.sh`. They are bash reading JSON on stdin and shelling out to `jq`, `git` and `date`. Nothing in them is macOS-specific.

One thing to verify rather than assume — the Mac's `statusline.sh` header notes it was written against bash 3.2 because that is what macOS ships. Ubuntu 26.04 ships bash 5.x. The scripts must still run:

```bash
bash --version | head -1
./wsl/claude/statusline-demo.sh > /dev/null && echo "demo renders"
```

- [ ] **Step 2: Write `wsl/claude/settings.json`**

Every value below differs from what this machine currently has, and each difference is a correction.

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "forceLoginMethod": "claudeai",
  "theme": "dark-ansi",
  "tui": "fullscreen",
  "language": "spanish",
  "outputStyle": "Explanatory",
  "model": "opus[1m]",
  "fallbackModel": ["opus", "sonnet"],
  "teammateMode": "auto",
  "alwaysThinkingEnabled": true,
  "spinnerTipsEnabled": false,
  "autoUpdatesChannel": "stable",
  "cleanupPeriodDays": 60,
  "inputNeededNotifEnabled": true,
  "agentPushNotifEnabled": true,
  "attribution": { "commit": "", "pr": "" },
  "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" },
  "enabledPlugins": {
    "claude-md-management@claude-plugins-official": true,
    "commit-commands@claude-plugins-official": true,
    "explanatory-output-style@claude-plugins-official": true,
    "security-guidance@claude-plugins-official": true,
    "superpowers@claude-plugins-official": true
  },
  "permissions": {
    "defaultMode": "auto",
    "disableBypassPermissionsMode": "disable",
    "additionalDirectories": ["~/workstation"],
    "deny": [
      "Read(~/.ssh/**)",
      "Read(~/.aws/**)",
      "Read(~/.config/gcloud/**)",
      "Read(~/.config/gh/hosts.yml)",
      "Read(~/.config/git/config.local)",
      "Read(~/.docker/config.json)",
      "Read(~/.npmrc)",
      "Read(~/.netrc)",
      "Read(/mnt/c/Users/*/.ssh/**)",
      "Read(/mnt/c/Users/*/.aws/**)",
      "Read(/mnt/c/Users/*/AppData/Roaming/gh/hosts.yml)",
      "Read(/mnt/c/Users/*/AppData/Roaming/npm/**)",
      "Read(/mnt/c/Users/*/.docker/config.json)",
      "Read(**/.env)",
      "Read(**/.env.*)",
      "Read(**/*.pem)",
      "Read(**/*.key)",
      "Read(**/*.p12)",
      "Read(**/*.pfx)",
      "Read(**/id_rsa*)",
      "Read(**/id_ed25519*)",
      "Read(**/.npmrc)",
      "Read(**/.netrc)",
      "Bash(rm -rf:*)",
      "Bash(git push --force:*)",
      "Bash(git push --force-with-lease:*)",
      "Bash(git push -f:*)",
      "Bash(git filter-branch:*)",
      "Bash(git filter-repo:*)",
      "Bash(git reset --hard:*)"
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 0,
    "refreshInterval": 60
  },
  "subagentStatusLine": {
    "type": "command",
    "command": "~/.claude/subagent-statusline.sh"
  }
}
```

The file is strict JSON with no room for comments, so the reasoning lives in `README.md` (Task 15). Carry over the Mac's explanations for `forceLoginMethod`, the absent `effortLevel`, `fallbackModel`, `autoUpdatesChannel`, `attribution`, `enabledPlugins`, the unversioned `extraKnownMarketplaces`, and the split ownership of `deny` versus `allow`. Add one paragraph this repo needs and the Mac does not: **the four `/mnt/c/Users/*` deny rules exist because the Windows host's credential stores are readable from inside WSL.** They do not exist on the Mac because there is no host to read.

- [ ] **Step 3: Write `wsl/claude/CLAUDE.md`**

Copy from `dotfiles` at `claude/CLAUDE.md` with these changes:

1. In `## Environment`, replace *"Claude Code and shell configuration live in `~/dotfiles` (versioned)"* with *"`~/workstation` (versioned)"*.
2. Replace the mise/uv sentence's Homebrew reference with the boundary as restated for this machine: *"runtimes and tools come from mise and never from apt; Python packages and virtualenvs from uv."*
3. Add this section:

```markdown
## The Windows boundary

This environment is Ubuntu under WSL2 on a Windows host. Two rules follow, and
both are about correctness rather than taste.

Never write to `/mnt/c`. Repositories and build output live on ext4 under
`~/Development`, where they are an order of magnitude faster. `/mnt/c` is
reachable, and being reachable is exactly what makes it a trap.

Never assume a Windows binary is on `PATH`. Windows interop is disabled in
`/etc/wsl.conf` deliberately: it puts the whole Windows `PATH` into every shell,
where every file is executable as far as Linux is concerned, so a Windows shim
found there executes a Windows script inside Linux. The Windows commands this
environment calls are aliased individually in `.zshrc`. If something needs one
that is not there, add the alias -- do not re-enable interop.

When something genuinely must cross the boundary, cross it explicitly and say
so in the commit message. A crossing nobody wrote down is the one that breaks on
the next machine.
```

4. Keep everything else verbatim — the language rule, "calibrate by size", "ask before introducing a new dependency", "judge against the authoritative source", "prove things rather than assert them", "break a check on purpose before trusting it", and "respect the toolchain each project already uses".

- [ ] **Step 4: Append the Claude checks**

Copy the four statusline checks from `dotfiles` `check.sh` — *demo renders*, *minimal payload still renders the model*, *invalid json produces no output*, *subagent rows are valid jsonl with the agent name* — changing paths from `claude/` to `wsl/claude/`. Then add:

```bash
check "claude settings" python3 -c "import json; json.load(open('wsl/claude/settings.json'))"

# The host's credential stores are readable from inside WSL. They are not on the
# Mac, because there is no host. Denying ~/.ssh while leaving the Windows one
# readable protects the key and hands over the one beside it.
deny_covers_the_host() {
  python3 - << 'PY'
import json, sys
deny = json.load(open('wsl/claude/settings.json'))['permissions']['deny']
need = ['/mnt/c/Users/*/.ssh/**', '/mnt/c/Users/*/.aws/**',
        '/mnt/c/Users/*/AppData/Roaming/gh/hosts.yml']
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
  python3 -c "
import json, sys
s = json.load(open('wsl/claude/settings.json'))
sys.exit(1 if 'effortLevel' in s else 0)
" || { echo "effortLevel is set; it freezes a default that improves on its own"; return 1; }
}
check "effortLevel is absent on purpose" no_effort_level
```

- [ ] **Step 5: Break the deny check, then commit**

```bash
python3 - << 'PY'
import json
p = 'wsl/claude/settings.json'
d = json.load(open(p))
d['permissions']['deny'] = [x for x in d['permissions']['deny'] if '/mnt/c' not in x]
json.dump(d, open(p, 'w'), indent=2)
PY
./check.sh    # expect FAIL the deny list covers the Windows host
git checkout wsl/claude/settings.json
./check.sh    # expect PASS

git add wsl/claude check.sh
git commit -m "Port Claude Code, with the deny list extended to the host

Six divergences on this machine are corrected: forceLoginMethod was console,
which bills per token instead of drawing on the subscription; permissions.deny
was absent entirely under defaultMode auto; there was no model or fallbackModel,
so an overload is a stopped session rather than a slower one; autoUpdatesChannel
was latest; effortLevel was written down, freezing a default that improves on its
own; and a marketplace pointed at a local directory that cannot transfer.

Four deny rules exist here that the Mac has no reason to carry: the Windows
host's .ssh, .aws, gh/hosts.yml and npm config are all readable from inside WSL.
Denying the Linux ones while leaving those open protects the key and hands over
the token beside it."
```

---

### Task 9: `install.sh`

**Files:**
- Create: `wsl/install.sh`
- Create: `wsl/vscode/settings.json`
- Modify: `check.sh`

**Interfaces:**
- Consumes: every manifest and config file from Tasks 5–8.
- Produces: a linked, installed environment. Running it twice must change nothing the second time, and a check asserts that.

- [ ] **Step 1: Write `wsl/vscode/settings.json` (remote side)**

Everything from the Mac's `vscode/settings.json` that needs the toolchain rather than the local UI. The host-side half already lives in `windows/vscode/settings.json` from Task 3.

```jsonc
{
  // VS Code, Remote-WSL machine scope. Applied to
  // ~/.vscode-server/data/Machine/settings.json.
  //
  // This half needs the toolchain: formatters, linters, the Python interpreter.
  // The half that needs the local renderer -- fonts, theme, window -- is in
  // windows/vscode/settings.json. A setting on the wrong side of that line
  // silently does nothing, which is the whole reason for the split.

  "editor.formatOnSave": true,
  "editor.bracketPairColorization.enabled": true,
  "editor.linkedEditing": true,
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  "files.trimFinalNewlines": true,

  // ---------- Python ----------
  // Ruff (by Astral, the uv people): linter and formatter in one binary.
  // Replaces black + isort + flake8 and is roughly 100x faster.
  "[python]": {
    "editor.defaultFormatter": "charliermarsh.ruff",
    "editor.codeActionsOnSave": {
      "source.fixAll.ruff": "explicit",
      "source.organizeImports.ruff": "explicit"
    }
  },
  // "standard" reports real type errors without the noise of "strict"
  "python.analysis.typeCheckingMode": "standard",
  "python.analysis.autoImportCompletions": true,
  // mise resolves the interpreter from each project's mise.toml
  "python.terminal.activateEnvironment": true,

  // ---------- JavaScript / TypeScript ----------
  "[javascript]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
  "[javascriptreact]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
  "[typescript]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
  "[typescriptreact]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
  "[json]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
  "[jsonc]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
  "[html]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
  "[css]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
  "[markdown]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
  "editor.codeActionsOnSave": { "source.fixAll.eslint": "explicit" },
  // Use the project's TypeScript, not the one VS Code ships: keeps the editor
  // and CI from reporting different errors.
  "typescript.enablePromptUseWorkspaceTsdk": true,
  "typescript.updateImportsOnFileMove.enabled": "always",
  "javascript.updateImportsOnFileMove.enabled": "always",

  // ---------- Terminal ----------
  // Inherits the shell PATH, so mise activates the right version per project.
  "terminal.integrated.inheritEnv": true,

  // ---------- Git ----------
  "git.autofetch": true,
  "git.confirmSync": false,
  // pull.rebase=true is already in ~/.config/git/config; this aligns the UI.
  "git.enableSmartCommit": true,

  // ---------- Noise ----------
  "errorLens.enabledDiagnosticLevels": ["error", "warning"],
  "files.exclude": {
    "**/.venv": true,
    "**/__pycache__": true,
    "**/.ruff_cache": true,
    "**/.mypy_cache": true,
    "**/node_modules": true
  },

  // ---------- Claude Code ----------
  // The panel, not the sidebar: it keeps the full editor width for code.
  "claudeCode.preferredLocation": "panel"
}
```

- [ ] **Step 2: Write `wsl/install.sh`**

```bash
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
	email = the personal address
EOF
  echo "    $XDG_CONFIG_HOME/git/config.local"
fi

# --- 6. Hooks -----------------------------------------------------------------
git -C "$(dirname "$WSL_DIR")" config core.hooksPath githooks

# --- 7. Runtimes and tools ----------------------------------------------------
log "Installing runtimes and tools with mise"
mise install
mise reshim

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
```

- [ ] **Step 3: Append the idempotency check**

Adapt the Mac's `install_is_idempotent` check from `dotfiles` `check.sh`. It runs `install.sh` against a temporary `HOME`, captures the result, runs it again, and asserts the second run reports no changes. Change every path from `install.sh` to `wsl/install.sh`.

- [ ] **Step 4: Commit**

```bash
git add wsl/ check.sh
git commit -m "Add install.sh and split the VS Code settings

VS Code's settings divide along the Remote-WSL boundary: what the local UI
renders stays on the host, what needs the toolchain goes to the machine scope
inside WSL. The Mac file mixes both because macOS has no boundary to respect;
here a setting on the wrong side silently does nothing.

install.sh narrows WSL interop as its first act, before installing anything.
That is a correctness fix and not a speed one: every file under /mnt/c is
executable as far as Linux is concerned, and mise's Windows shims live there."
```

---

## Phase 3 — Apply and migrate

### Task 10: Apply the WSL layer

**The machine changes in this task.**

- [ ] **Step 1: Clone and run**

```bash
wsl -d Ubuntu-26.04
git clone https://github.com/camilopiedra92/workstation ~/workstation
~/workstation/wsl/install.sh
```

- [ ] **Step 2: Cycle WSL so `/etc/wsl.conf` takes effect**

From PowerShell:

```powershell
wsl --shutdown
```

Then reopen the terminal and confirm interop is actually narrowed — this is the assertion that the file took, not a second mechanism:

```bash
echo "$PATH" | tr ':' '\n' | grep -c '/mnt/c' || echo "0 windows entries on PATH"
```

Expected: `0`. A non-zero count means `/etc/wsl.conf` did not apply and the shims hazard is still live.

- [ ] **Step 3: Verify each layer arrived**

```bash
echo "shell:    $SHELL"
echo "zdotdir:  $ZDOTDIR"
node --version        # expect v26.x
python --version      # expect 3.14.x
pnpm --version        # expect 11.x
starship --version
eza --version
which node | grep -q mise && echo "node comes from mise" || echo "WRONG: node is not from mise"
git config --get init.defaultBranch    # expect main
git config --get pull.rebase           # expect true
```

- [ ] **Step 4: Verify the pinned versions match the manifest**

```bash
cd ~/workstation
for t in starship eza bat fd ripgrep fzf zoxide jq delta uv; do
  want=$(grep -E "^$t = " wsl/mise/config.toml | sed 's/.*"\(.*\)".*/\1/')
  got=$(mise current "$t" 2>/dev/null)
  printf '%-10s want %-10s got %-10s %s\n' "$t" "$want" "$got" \
    "$([ "$want" = "$got" ] && echo OK || echo MISMATCH)"
done
```

Any `MISMATCH` is fixed before proceeding. A pin the machine does not honour is a pin that is not doing its job.

- [ ] **Step 5: Run the full check suite in its real home**

```bash
cd ~/workstation && ./check.sh --strict
```

Expected: everything `PASS`. This is the first run where nothing should skip, because the tools are now installed. Any remaining `FAIL (not installed)` names a tool the manifests forgot — add it to `wsl/mise/config.toml` and re-run.

- [ ] **Step 6: Commit any manifest corrections Step 5 forced**

---

### Task 11: Migrate the repositories to ext4

- [ ] **Step 1: Record what is on the Windows side, with its state**

Nothing is deleted before this list exists and every entry is accounted for.

```bash
for d in /mnt/c/Users/camilo.piedrahita/Development/*/; do
  name=$(basename "$d")
  printf '%-26s ' "$name"
  if [ -d "$d/.git" ]; then
    remote=$(git -C "$d" remote get-url origin 2>/dev/null || echo "NO REMOTE")
    dirty=$(git -C "$d" status --porcelain 2>/dev/null | wc -l)
    unpushed=$(git -C "$d" log --oneline @{u}.. 2>/dev/null | wc -l)
    printf 'remote=%-60s dirty=%s unpushed=%s\n' "$remote" "$dirty" "$unpushed"
  else
    printf 'NOT A GIT REPO -- must be copied, not re-cloned\n'
  fi
done
```

Known from the survey: `aipm`, `glow`, `surge-pods` and `vr` are git repos; `obsi`, `testaware` and `surge-pods-migration` are not.

- [ ] **Step 2: Push anything unpushed, from the Windows side, before moving**

Any repo showing `dirty>0` or `unpushed>0` in Step 1 is resolved first. A re-clone silently discards both.

- [ ] **Step 3: Re-clone the git repos onto ext4**

```bash
mkdir -p ~/Development && cd ~/Development
gh auth login          # once, if not already authenticated inside WSL
gh auth setup-git
for r in aipm glow surge-pods vr; do
  git clone "$(git -C /mnt/c/Users/camilo.piedrahita/Development/$r remote get-url origin)" "$r"
done
```

- [ ] **Step 4: Copy the non-git directories**

```bash
for d in obsi testaware surge-pods-migration; do
  cp -r "/mnt/c/Users/camilo.piedrahita/Development/$d" ~/Development/
done
```

- [ ] **Step 5: Copy the untracked files the re-clone did not bring**

`.remember/`, `.claude/settings.local.json`, `.env` files and `.mcp.json` are untracked by design and do not survive a clone.

```bash
for r in aipm glow surge-pods vr; do
  src="/mnt/c/Users/camilo.piedrahita/Development/$r"
  for extra in .remember .claude .mcp.json .env .env.local; do
    [ -e "$src/$extra" ] && cp -r "$src/$extra" ~/Development/$r/ && echo "$r: brought $extra"
  done
done
```

- [ ] **Step 6: Verify before deleting anything**

```bash
for r in aipm glow surge-pods vr; do
  printf '%-14s ' "$r"
  git -C ~/Development/$r log --oneline -1
done
ls ~/Development
```

Expected: seven entries, and each git repo at the same commit as its Windows counterpart. **The Windows copies are not deleted in this task.** They stay until the environment has been used for real. Deleting them is its own decision, taken later, deliberately.

- [ ] **Step 7: Measure a real repository, and settle `core.fsmonitor`**

Run Task 7 Step 3 now, against `~/Development/surge-pods`. Record the numbers, edit `wsl/git/config` accordingly, and commit with the measurement in the message.

---

### Task 12: Move Claude Code into WSL

**This task ends the current session.** Claude Code is running on the Windows host right now; after this it runs in Ubuntu. Read the whole task before starting any of it.

- [ ] **Step 1: Record the host installation, so nothing is lost silently**

```bash
cp /c/Users/camilo.piedrahita/.claude/settings.json /tmp/claude-host-settings.json
ls /c/Users/camilo.piedrahita/.claude/
cat /c/Users/camilo.piedrahita/.claude/settings.json | python3 -m json.tool | head -60
```

Note in particular: the plugin set, the `claude-hud` marketplace, and the `personal` marketplace pointing at a local directory — which the design records as unable to transfer.

- [ ] **Step 2: Install Claude Code inside Ubuntu**

```bash
wsl -d Ubuntu-26.04
node --version        # must be v26.x, from mise
curl -fsSL https://claude.ai/install.sh | bash
claude --version
```

- [ ] **Step 3: Apply the repo's settings**

`install.sh` already linked `statusline.sh`, `subagent-statusline.sh` and `CLAUDE.md` into `~/.claude/`. The settings file is merged rather than linked, because Claude Code rewrites it on its own (theme, `/config`) and a symlink would be overwritten:

```bash
mkdir -p ~/.claude
if [ -f ~/.claude/settings.json ]; then
  jq -s '.[0] * .[1]' ~/.claude/settings.json ~/workstation/wsl/claude/settings.json \
    > /tmp/merged.json && mv /tmp/merged.json ~/.claude/settings.json
else
  cp ~/workstation/wsl/claude/settings.json ~/.claude/settings.json
fi
python3 -c "import json; json.load(open('$HOME/.claude/settings.json')); print('valid')"
```

- [ ] **Step 4: Authenticate, and confirm which method took**

```bash
claude
```

At the login prompt, choose the Claude.ai subscription — not Console. `forceLoginMethod: "claudeai"` should make that the only offer. If a Console login is offered instead, stop: the setting did not apply, and proceeding bills per token instead of drawing on the subscription.

- [ ] **Step 5: Confirm the statusline and the deny list are live**

```bash
claude
```

Expected: the two-line statusline from `dotfiles` renders — identity above, gauges below. Then, inside the session, confirm the deny list is enforced:

```
> read ~/.ssh/id_ed25519
> read /mnt/c/Users/camilo.piedrahita/.aws/credentials
```

Both must be refused. The second is the one this repo added and the Mac has no reason to carry; if it is allowed, the `/mnt/c` deny rules are not being applied and Task 8 needs revisiting.

- [ ] **Step 6: Reinstall plugins**

`enabledPlugins` lists what should be on. Anything the host had that is not in that list was deliberately dropped — including `claude-hud`, which the statusline decision replaced.

- [ ] **Step 7: Retire the host installation**

Only after Steps 4–6 all pass. Do not uninstall; disable, and leave it recoverable:

```bash
mv /c/Users/camilo.piedrahita/.claude/settings.json \
   /c/Users/camilo.piedrahita/.claude/settings.json.retired
```

`drift.sh` will report the host installation as installed-and-undeclared, which is the correct verdict. Removing it is a separate decision.

---

## Phase 4 — The rest of the discipline

### Task 13: `drift.sh`

**Files:** Create `drift.sh`

Deliberately **not** part of `check.sh` and not run by CI. Every check in there has to mean the same thing on a runner as on this laptop, and this one cannot: a runner arrives with its own preinstalled packages, so "installed but undeclared" is always true there and never interesting.

- [ ] **Step 1: Write `drift.sh`**

It answers the question the manifests cannot: what does this machine have that nothing declares? Four comparisons, each printed in both directions:

1. **apt** — `apt-mark showmanual` against `wsl/apt-packages.txt`.
2. **mise** — `mise ls --current` against `wsl/mise/config.toml`, comparing versions and not only names.
3. **uv** — `uv tool list` against `wsl/uv-tools.txt`, comparing the installed reference against the declared one.
4. **Windows host** — `winget.exe list --source winget` against `windows/configuration.winget`. This is the direction that will report the most, and it is expected to: Git for Windows, GitHub CLI, Docker Desktop and Node were all installed before this repo existed. They are reported, not removed.

Model the output on the Mac's `drift.sh`: green for agreement, red for a gap, dim for the detail, and a non-zero exit if anything drifted.

- [ ] **Step 2: Run it and read the output as a to-do list**

```bash
./drift.sh
```

Expected on first run: several host-side entries. Each is either adopted into `windows/configuration.winget` or consciously left as known drift. Neither answer is wrong; only not looking is.

- [ ] **Step 3: Commit**

---

### Task 14: CI

**Files:** Create `.github/workflows/ci.yml`, `.github/tool-checksums.txt`, `.github/dependabot.yml`, `bump-tools.sh`

- [ ] **Step 1: Write the `ubuntu-latest` job**

It defines no checks of its own: it installs what the runner is missing at pinned, checksum-verified versions, then calls `./check.sh`. `CI` is set by the runner, so strict mode needs no wiring and cannot be forgotten.

Tools to install, each pinned and each with a SHA256 recorded in `.github/tool-checksums.txt`: `shellcheck` v0.11.0, `shfmt` v3.13.1, `actionlint` 1.7.12, `taplo` 0.10.0. Linux amd64 artifacts, not the macOS ones the other repo pins. Plus `zsh`, `python3`, `pyyaml` and `jsonschema` from the runner image.

Copy the workflow's structure from `dotfiles` `.github/workflows/ci.yml` — including `permissions: contents: read`, the `concurrency` block, the SHA-pinned `actions/checkout`, the `verify()` function that refuses to install a file it has no recorded hash for, and the "tools are the pinned versions" step.

- [ ] **Step 2: Write the `windows-latest` job**

It runs only what nothing else can answer:

```yaml
  windows-checks:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - name: Validate the WinGet configuration
        run: winget configure validate .\windows\configuration.winget
      - name: Every declared package id resolves
        shell: pwsh
        run: |
          $ids = @('Canonical.Ubuntu.2604','Microsoft.WindowsTerminal',
                   'DEVCOM.JetBrainsMonoNerdFont','Microsoft.VisualStudioCode',
                   'Microsoft.PowerToys')
          $bad = @()
          foreach ($id in $ids) {
            winget show --id $id --exact | Out-Null
            if ($LASTEXITCODE -ne 0) { $bad += $id }
          }
          if ($bad) { throw "unresolvable package ids: $($bad -join ', ')" }
```

This is the honest half of the split. A package id resolving is a claim only a machine with winget can settle, and it is the one thing in the Windows layer a schema cannot catch.

- [ ] **Step 3: Write `.github/tool-checksums.txt`**

Download each pinned artifact, run `sha256sum`, and record the hash with the exact filename CI will fetch. Carry over the Mac file's header explaining why the hashes live here rather than being fetched: *a checksum published beside the artifact proves nothing, because whoever could replace the binary could replace that file with it.*

- [ ] **Step 4: Write `bump-tools.sh` and `.github/dependabot.yml`**

`bump-tools.sh` moves the version pins in `ci.yml` to the latest upstream releases and refreshes the hashes in `tool-checksums.txt` in the same pass, so the two cannot drift apart. `dependabot.yml` watches `github-actions` so the SHA-pinned actions get bumped with a diff to review rather than by trust.

- [ ] **Step 5: Push and watch both jobs go green**

```bash
gh repo create camilopiedra92/workstation --public --source=. --push
gh run watch
```

- [ ] **Step 6: Break CI on purpose**

Push a branch with a deliberate shellcheck violation and confirm the ubuntu job fails; push one with a misspelled package id and confirm the windows job fails. A CI nobody has watched fail is a CI nobody should rely on. Delete the branches afterwards.

---

### Task 15: `README.md`

**Files:** Create `README.md`; Modify `docs/superpowers/specs/2026-08-18-workstation-design.md`

The README is where the reasoning that cannot live in a strict-JSON file goes. It is the largest single deliverable of this task and the one that decays fastest if deferred.

- [ ] **Step 1: Write the README**

Sections, modelled on the Mac repo's but answering this machine's questions:

- **What this is** — one screen. Two strata, one repo, one `check.sh`.
- **New machine** — the two bootstrap commands.
- **Architecture** — the layer table, and the manager boundary as restated: *apt installs what the system needs, mise installs everything you use, uv installs Python CLIs.* State plainly that this widens mise's domain versus the Mac's rule and why that serves pinning better.
- **Files** — the annotated tree.
- **Why WSL2** — the evidence, with the sources: Microsoft's Mac-to-Windows guide, mise's own "via the use of shims until someone adds PowerShell support", Nix's platform support, the ext4-versus-`/mnt/c` numbers **measured on this machine** in Task 4.
- **Why there is no `.zprofile`** — the counterpart to the Mac README's long note. Here the answer is short, and its shortness is the point.
- **Why interop is narrowed** — the correctness argument, not the speed one.
- **The Claude Code settings** — the per-key reasoning, since the file cannot hold comments. Every item the Mac README covers, plus the paragraph about the four `/mnt/c` deny rules and why the Mac has no reason to carry them.
- **What did not port** — the five Ghostty settings, `dev-nuke.sh`, the macOS zsh plugin, the second Python version. Each with its reason.
- **Expiry dates** — the table from the spec.

- [ ] **Step 2: Amend the spec where implementation corrected it**

Two known corrections:

1. `configuration.dsc.yaml` → `configuration.winget`, with the naming note from Task 2.
2. Whatever Task 7 Step 3 measured about `core.fsmonitor`, replacing the instruction to measure with the result.

Add any others the implementation surfaced. A spec that no longer describes what was built is worse than no spec.

- [ ] **Step 3: Final full run**

```bash
./check.sh --strict && ./drift.sh
gh run watch
```

- [ ] **Step 4: Commit**

```bash
git add README.md docs/
git commit -m "Document the reasoning, and correct the spec where building it taught us better

The settings file is strict JSON with no room for comments, so the reasoning for
every key lives here -- including the four /mnt/c deny rules, which exist because
the Windows host's credential stores are readable from inside WSL and which the
Mac has no host to need."
```

---

## Self-Review

**Spec coverage.** Every spec section maps to a task: the seventeen practices to Task 1 (harness), 13 (drift), 14 (CI); constraints to the Global Constraints block; the WSL2 decision to Tasks 4 and 10; Claude-in-WSL to Task 12; ext4 to Task 11; the VS Code split to Tasks 3 and 9; the manager boundary to Task 5; one `check.sh` to Task 1 and every task after it; the two CI jobs to Task 14; the Windows layer to Tasks 2–4; the WSL layer to Tasks 5–10; line endings to `.gitattributes`, already committed, with its check in Task 1; bootstrap to Tasks 2, 4 and 10; expiry dates to Task 15.

**Two spec deviations, both deliberate and both recorded in Task 15 Step 2:** the manifest is `configuration.winget`, not `configuration.dsc.yaml`, following Microsoft's documented extension; and `core.fsmonitor` is withheld pending measurement rather than ported on the Mac's evidence.

**Placeholders.** The only bracketed fill-ins are two measured numbers in Task 4 Step 7, which the step immediately above produces. Every other step carries its actual content or an exact source path to copy from.

**Naming consistency.** `check()`/`skip()`/`have()`/`STRICT` from Task 1 are used unchanged in Tasks 2, 3, 5, 6, 7, 8 and 9. The font family string `JetBrainsMono Nerd Font` is identical in `configuration.winget`, `terminal/settings.json` and both VS Code files, and the check in Task 3 compares exactly those. `~/workstation` is the clone path in `install.sh`, in `additionalDirectories`, in the `.zshrc` alias and in `CLAUDE.md`.

---

## Ordering constraints

These are the only places where task order is not free:

- Task 4 requires Tasks 2 and 3 — it applies what they declare.
- Task 10 requires Task 4 (Ubuntu must exist) and Tasks 5–9 (the files it applies).
- Task 11 requires Task 10 (`gh` and git must work inside WSL).
- Task 12 requires Task 10 (node from mise) and should follow Task 11, so the migrated repos are what the new session opens into.
- Task 7 Step 3 requires Task 11 — there is no real repository to measure before it.
- Task 14 Step 5 creates the GitHub remote; Task 10 Step 1 clones from it, so either create the remote earlier or clone from the local path and add the remote afterwards.

Everything else can be reordered.
