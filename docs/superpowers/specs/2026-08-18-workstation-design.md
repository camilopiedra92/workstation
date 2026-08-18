# Workstation — design

This machine's development environment, declared as code.

The machine is a Globant-issued Windows 11 laptop. The environment that runs on
it is Ubuntu under WSL2. Both halves are declared here, in one repository, with
one set of checks.

## Why this repo exists, and why it is not `dotfiles`

`dotfiles` is the macOS environment. It stays that way: macOS on Apple Silicon
only, Homebrew at `/opt/homebrew`, casks, Ghostty. Nothing here changes it and
nothing here is shared with it at the file level.

What is taken from it is the discipline, not the content. Seventeen practices
were extracted from that repo and every one of them applies here:

| # | Practice |
|---|---|
| 1 | The environment is a repo, not a memory. Rebuildable from zero with one command. |
| 2 | One manifest per manager, with the boundary written down. |
| 3 | No manager without a manifest. A manager that has nothing to read a list from gets one written for it. |
| 4 | Everything pinned, and every pin carries its reason and its expiry. |
| 5 | One place for the checks, three audiences: you, the hook, CI. |
| 6 | A check that did not run is not a check that passed. Strict mode in the gates. |
| 7 | Drift is measured in the direction it grows: what the machine has that the manifest does not declare. |
| 8 | Out of CI goes what CI cannot answer honestly. |
| 9 | Hooks are versioned, not left in `.git/hooks`. |
| 10 | A gate declares what it is. The pre-push hook says plainly it is defence in depth. |
| 11 | Supply chain verified: tools pinned and checksummed, with the hashes in this repo. |
| 12 | The reasoning lives next to the config, with measurements rather than assertions. |
| 13 | Standard paths, and the legacy ones deleted so they cannot win silently. |
| 14 | Identity and secrets outside the repo, so the repo can be public. |
| 15 | The agent deny-list is specific to this machine, not a generic list. |
| 16 | Split ownership in the agent config: the repo owns `deny`, the machine owns `allow`. |
| 17 | Coherence across different tools is forced and verified by a check. |

The starting point on this machine was zero of the seventeen. Measured before
any change: `git config --global --list` returned nothing at all — no identity,
no `init.defaultBranch`, no `pull.rebase`. Node was a global install under
`C:\Program Files\nodejs`. `python` resolved to the Microsoft Store alias at
`AppData\Local\Microsoft\WindowsApps\python`. `~/.claude/settings.json` carried
no `permissions.deny` while running `defaultMode: auto` with
`skipDangerousModePermissionPrompt: true`.

## Constraints, measured rather than assumed

Every one of these was verified on the machine before the design was fixed.

| | |
|---|---|
| Domain | `GLOBANT`, and the user is in the local Administrators group |
| ExecutionPolicy | `MachinePolicy` and `UserPolicy` both `Undefined` — no GPO lockdown |
| winget | v1.29.280, default sources, no corporate restriction |
| WSL | enabled, version 2 default; a `docker-desktop` distro already present |
| Proxy | none |
| PowerShell | 5.1 only; no pwsh 7 installed |
| Windows | 11 Enterprise, build 26200 |
| Windows Terminal | 1.18.10301 — several versions behind |
| VS Code | installed, user scope |

Nothing here forces a workaround. That is the reason this design does not
contain one.

## The decision that shapes everything: WSL2

The work on this machine is Node/TypeScript, git, markdown and Claude Code.
Across the seven projects present, there is one `.ps1` file, one `.sh`, one
`.py` and one `.ts`. Nothing touches a Windows API, and there is no .NET, no
C++, and no installer packaging.

The evidence, from primary sources:

- Microsoft's own Mac-to-Windows guide states: *"Using WSL provides the kind of
  environment most familiar to Mac users."* Its native Unix story — Coreutils,
  `sudo`, `curl` — is framed as covering *"basic tasks"*.
- mise, which is the centre of the toolchain, documents native Windows as
  supported *"via the use of shims until someone adds PowerShell support"*, and
  has open reports of those shims polluting the WSL `PATH`.
- Nix, the ceiling for reproducibility, officially supports only macOS and
  Linux. On Windows it runs under WSL2. Choosing native Windows would close that
  door permanently.
- WSL2's ext4 is 9–20x faster than `/mnt/c` for build artifacts, and I/O latency
  dropped roughly 40% over 2025.
- Anthropic documents WSL2 as the recommended WSL version for Claude Code.

Ghostty does not run on Windows and is not on its roadmap, so the terminal is
replaced rather than ported. That is the only piece of the macOS environment
with no equivalent path.

## Architecture: two strata

```
┌─ WINDOWS HOST ───────────────────────────── thin, declarative ─────┐
│  Declared by:  windows/configuration.dsc.yaml   (WinGet DSC)       │
│                                                                    │
│   · WSL2 + Ubuntu 26.04 LTS          the substrate                 │
│   · Windows Terminal                 replaces Ghostty              │
│   · VS Code + Remote-WSL             editor, runs on the host      │
│   · JetBrainsMono Nerd Font          the same font as on the Mac   │
│   · PowerToys                        Keyboard Manager, for Mac     │
│                                      muscle memory                 │
│                                                                    │
│  No runtimes. No repositories. No development happens here.        │
├─ WSL2 / UBUNTU 26.04 LTS ─────────────────── the real environment ─┤
│  Declared by:  wsl/                                                │
│                                                                    │
│   · apt-packages.txt      what the system needs                    │
│   · mise/config.toml      runtimes and user tools                  │
│   · uv-tools.txt          Python CLIs                              │
│   · zsh + antidote + starship.toml                                 │
│   · git/config + git/ignore + githooks/                            │
│   · claude/  settings.json, CLAUDE.md, both statuslines            │
│   · bin/                                                           │
│                                                                    │
│  Repositories live at ~/Development on ext4. Never /mnt/c.         │
└────────────────────────────────────────────────────────────────────┘
```

The Windows layer is deliberately thin. Everything in it exists to make the WSL
layer reachable, visible or typeable — a terminal, a font, an editor, the
subsystem itself. The moment something that is not one of those four things
wants to be installed on the host, that is the signal the boundary is being
crossed for a bad reason.

## Load-bearing decisions

### 1. Claude Code runs inside WSL, not on Windows

This is the decision with the most consequences and they all point the same way.
`~/.claude` becomes a Linux path, so `statusline.sh` and
`subagent-statusline.sh` — 467 lines already written, already designed, already
covered by four checks — are reused unchanged. The deny-list uses POSIX paths
identical to the Mac's. `CLAUDE.md` describes the environment the agent actually
works in.

Run on the host instead, reaching into `\\wsl$\...`, all three break: the bash
statuslines have no shell, the deny paths do not match, and `CLAUDE.md`
documents an environment that is not the one being edited.

The migration cost is real and belongs in the plan, not in a footnote: the
current Claude Code installation on the host, its `settings.json`, its plugin
set and its authenticated session all live on the Windows side today.

### 2. Repositories live on ext4, never on `/mnt/c`

The seven projects currently under `C:\Users\camilo.piedrahita\Development` are
re-cloned into `~/Development` inside Ubuntu. The 9–20x penalty on `/mnt/c` is
not a tuning detail; it is the single most common way a WSL setup is made to
feel slow and then blamed on WSL.

Windows can still reach them through `\\wsl$\Ubuntu-26.04\home\...` when
something genuinely needs to. That path is for looking, not for working.

### 3. VS Code installs on the host and edits in WSL

Remote-WSL is the supported model. The design consequence is that
`settings.json` splits in two, and the split is correct rather than a tax:

- **Host** (`windows/vscode/settings.json`) — font, theme, window, telemetry.
  Things the local UI renders.
- **Remote** (`wsl/vscode/settings.json`, applied to
  `~/.vscode-server/data/Machine/settings.json`) — formatters, linters, the
  Python interpreter, terminal profile. Things that need the toolchain.

The Mac file mixes both because on macOS there is no boundary to respect. Here
there is, and a setting placed on the wrong side silently does nothing.

### 4. The manager boundary, restated

The Mac rule is *"Homebrew installs programs, mise installs runtimes. Never a
runtime through Homebrew."* The naive translation is apt in Homebrew's place,
and it is wrong: apt carries stale versions of exactly the tools in use here —
`eza`, `bat`, `fd`, `rg`, `delta`, `zoxide` — and `starship` is not in apt at
all.

The rule for this machine:

> **apt installs what the system needs. mise installs everything you use —
> runtimes and tools alike. uv installs Python CLIs.**

This does not violate the Mac rule. That rule forbids a *runtime* coming from
the system package manager, and this respects it. What changes is that mise's
domain widens to user tools, and that serves practice #4 better than apt does:
mise's `ubi` and `aqua` backends install at a pinned version with a checksum,
while apt gives whatever is in the archive that day and moves underneath you.

### 5. One `check.sh`, in bash, inside WSL, validating both strata

The files under `windows/` are content — YAML, JSON, a schema. They are
validated as content, which needs the files and not the operating system. Where
something genuinely requires Windows, WSL invokes the host binary through
interop (`winget.exe`).

Practice #5 survives intact: one script, three audiences.

### 6. CI in two jobs, and the split is honest

`ubuntu-latest` runs the whole of `check.sh`, which is about 90% of the
coverage. `windows-latest` runs only what nothing else can answer:
`winget configure --validate` and the Windows Terminal schema.

This is not duplication — the two jobs ask different questions. It is practice
#8 applied in the other direction: nothing goes to a runner that cannot answer
it honestly.

## Layout

```
workstation/
├── README.md                       the reasoning, as in dotfiles
├── check.sh                        every check, one place
├── drift.sh                        what the machine has that nothing declares
├── bump-tools.sh                   moves the CI pins to their latest releases
├── .editorconfig
├── .taplo.toml
├── .gitignore
├── .github/
│   ├── workflows/ci.yml
│   ├── tool-checksums.txt
│   └── dependabot.yml
├── githooks/{pre-commit,pre-push}
├── schemas/                        vendored: mise, starship, windows-terminal
├── docs/superpowers/specs/
├── windows/
│   ├── configuration.dsc.yaml      the Brewfile's role
│   ├── bootstrap.ps1               the only imperative step
│   ├── terminal/settings.json      Windows Terminal
│   └── vscode/settings.json        host-side editor settings
└── wsl/
    ├── install.sh
    ├── apt-packages.txt
    ├── mise/config.toml
    ├── uv-tools.txt
    ├── zsh/{.zshenv,.zshrc,.zsh_plugins.txt}
    ├── starship.toml
    ├── git/{config,ignore}
    ├── vscode/settings.json        remote-side editor settings
    ├── claude/
    │   ├── settings.json
    │   ├── CLAUDE.md
    │   ├── statusline.sh
    │   ├── subagent-statusline.sh
    │   └── statusline-demo.sh
    └── bin/
```

## The Windows layer

### `configuration.dsc.yaml`

WinGet Configuration is the Brewfile's counterpart and it is not a compromise:
declarative YAML, idempotent, official, and applied with one command. It
declares WSL2, Ubuntu 26.04 LTS, Windows Terminal, VS Code with the Remote-WSL
extension, JetBrainsMono Nerd Font, and PowerToys.

`git` is deliberately **not declared** on the host. All git work happens in WSL,
and `gh auth setup-git` inside Ubuntu provides credentials there, mirroring the
Mac exactly. A host-side Git Credential Manager bridge is the documented
alternative; it is rejected here because it creates a cross-boundary dependency
to solve a problem that does not exist once nothing on the host uses git.

Not declared is not the same as removed. The machine already has Git for Windows
at `/mingw64/bin/git` and `gh` at `C:\Program Files\GitHub CLI`, installed
before this repo existed. `drift.sh` will report both as installed-and-undeclared,
which is the correct verdict and the point of practice #7: the manifest is the
claim, and anything outside it is visible rather than assumed. Removing them is a
separate decision, made once the WSL side is authenticated and proven, never as a
side effect of bootstrapping.

### Ubuntu 26.04 LTS, and why that number

26.04 released in April 2026 and is supported until 2031. The alternative,
24.04, is supported until 2029. This follows the same reasoning as `node = "26"`
in the Mac's mise config — take the newest long-term release deliberately, and
write down why — with one difference worth stating: Ubuntu LTS has no parity
trap to sidestep. Every LTS gets the same five years, so the newest one simply
is the right one, with no date to wait for and no note to revisit.

### `terminal/settings.json` — the Ghostty translation

| Ghostty | Windows Terminal |
|---|---|
| `font-family`, `font-size` | `font.face`, `font.size` |
| `font-feature = calt, zero, ss02` | `font.features`, same OpenType tags |
| `adjust-cell-height = 12%` | `font.cellHeight` |
| `theme = Catppuccin Mocha` | Catppuccin Mocha scheme |
| `window-padding-x/y = 18/14` | `padding` |
| `background-opacity = 0.90` + blur | `opacity` + acrylic |
| `scrollback-limit` | `historySize` |
| `copy-on-select` | `copyOnSelect` |
| `keybind = shift+enter=text:\n` | `sendInput: "\n"` |
| `global:cmd+grave=toggle_quick_terminal` | Quake mode, native |

Every key is validated against Windows Terminal's published JSON schema, which
is vendored under `schemas/` and enforced by `check.sh`. This replaces
`ghostty +validate-config`, which was the Mac repo's only check that validated
configuration rather than code — and the one whose absence let CI report success
while validating no Ghostty config at all.

Three settings do not port: `font-thicken` (a macOS antialiasing correction),
`window-colorspace = display-p3`, and `macos-glass` blur. They are recorded in
the file as explicitly not ported. A dropped setting that is written down is
information; one that is silently omitted is a hole.

## The WSL layer

### What dies, and why that is a good sign

The entire `.zprofile` apparatus disappears — forty lines explaining
`path_helper`, the measured table of PATH positions, the re-source. Linux has no
`path_helper`. That the complexity evaporates on changing platform confirms it
was diagnosed correctly: it was a macOS problem, not a shell problem.

What survives is the double link of `.zshenv`. That branch — `ZDOTDIR` exported
or not — is zsh behaviour, not macOS behaviour, and applies identically here.

Also gone: `ohmyzsh/plugins/macos` (`ofd`, `pfd`, `cdf`), `bin/dev-nuke.sh`
(Homebrew and macOS caches), and the entire cask layer.

### `mise/config.toml`

`node = "26"` carries over with its reasoning and its expiry unchanged: 26
becomes Active LTS on 2026-10-28, at which point the pin returns to `"lts"` and
starts tracking on its own again.

`python = ["3.14"]`, single-valued. The Mac carries a second 3.13 solely because
gcloud ships no interpreter and gsutil refuses anything above 3.13. There is no
gcloud on this machine, so that entry is not carried. It comes back only when
gcloud does, with the same reasoning written next to it. Copying it now would be
carrying a workaround for a problem this machine does not have.

`pnpm = "11"` carries over unchanged.

### `git/config` and `git/ignore`

`git/config` transfers nearly whole. Two changes.

The credential helper points at the Linux `gh` rather than
`/opt/homebrew/bin/gh`.

`core.fsmonitor` is not carried on faith. On macOS it is backed by FSEvents; on
Linux git's fsmonitor daemon uses a different mechanism, and under WSL2 it is
watching a virtualised ext4 volume. The instruction is to measure it the way the
Mac repo measured `path_helper`: time `git status` on the largest repo here with
`core.fsmonitor` on and off, and keep the setting only if the difference is real.
If it is not, the line is deleted — a setting that buys nothing is not neutral,
it is a claim nobody checked.

`git/ignore` drops the macOS block and gains a Linux one. A small Windows block
stays despite no Windows process working in these repos, because browsing
`\\wsl$` in Explorer can still deposit `Thumbs.db` and `desktop.ini`. The
editor, secret and `**/.claude/settings.local.json` sections carry over
unchanged.

## Claude Code

`settings.json` follows the Mac repo's model with every divergence found on this
machine corrected:

- `forceLoginMethod: "claudeai"` — the machine currently has `console`, which
  the Mac repo's README documents as letting an accidental Console login bill
  per token instead of drawing on the subscription.
- `permissions.deny` — currently absent entirely. Restored with POSIX paths, and
  extended with the Windows host paths reachable from WSL through
  `/mnt/c/Users/...`. Those do not exist on the Mac and do exist here:
  `.ssh`, `.aws`, and `gh/hosts.yml` on the host are readable from Ubuntu unless
  denied. This is practice #15 applied to a machine the Mac's list never
  described.
- `model` and `fallbackModel` — currently neither. With one model named and no
  chain, an overload is a stopped session rather than a slower one.
- `autoUpdatesChannel: "stable"` — currently `latest`.
- `effortLevel` absent — currently `high`, which freezes a default that improves
  on its own.
- `extraKnownMarketplaces` is not versioned. The machine currently declares a
  `personal` marketplace pointing at a local directory, which is exactly the case
  the Mac repo documents as unable to transfer.
- Statusline: `statusline.sh` and `subagent-statusline.sh` from the Mac repo,
  reused unchanged. `claude-hud` is removed. Two things installed for one role is
  the same failure practice #17 forbids for fonts.

`CLAUDE.md` transfers nearly whole — `~/Development` remains accurate inside
Ubuntu, the mise/uv rule holds, the Spanish-reply/English-files rule holds, and
so does *"prove things rather than assert them"*. One section is added: the
Windows/WSL boundary. Never write to `/mnt/c`. Never assume a Windows binary is
on `PATH`. When something must cross, cross it explicitly and say so.

## Line endings

Found by measurement while creating this repo, not anticipated. Git for Windows
ships `core.autocrlf=true` in its system gitconfig at
`C:/Program Files/Git/etc/gitconfig`, so the first commit here emitted
`LF will be replaced by CRLF the next time Git touches it`.

This repo is authored on Windows and consumed on Linux, which is the exact
direction that setting works against. `autocrlf` decides using a heuristic about
what counts as text, and a shell script cannot rely on "usually right": a `.sh`
reaching Ubuntu with CRLF fails at the shebang with
`bad interpreter: /usr/bin/env bash^M`, an error that names neither the file nor
the cause.

`.gitattributes` declares `* text=auto eol=lf`, which takes the machine out of
the answer entirely — the repo stores LF and checks out LF whatever any clone
has `autocrlf` set to. `.ps1` is covered by that rule rather than exempted:
both PowerShell 5.1 and 7 read LF scripts without complaint, and an exemption
would be the one file able to reintroduce CRLF.

This is practice #13 in a form the Mac repo never needed. There, every machine
that touches the files is a Unix one, so the question never arises.

## Checks

Carried unchanged: shellcheck, shfmt, bash syntax, zsh syntax, actionlint,
tracked scripts executable in git, installed tools match the ci.yml pins,
TOML lint and format, gitconfig parses, Claude settings parse, VS Code settings
parse as JSONC, `uv-tools.txt` declares a pinned reference per tool, English
only, install idempotency, and the four statusline checks (demo renders,
minimal payload still renders the model, invalid JSON produces no output,
subagent rows are valid JSONL).

Adapted: *"one nerd font, declared everywhere it renders"*. The four declaration
sites become Windows Terminal `font.face`, VS Code host `editor.fontFamily`, VS
Code host `terminal.integrated.fontFamily`, and the DSC manifest. The
justification is unchanged and still the strongest argument in the check —
*"two fonts installed is not better than one"*.

Replaced: `ghostty +validate-config` becomes Windows Terminal schema validation
plus `winget configure --validate`.

New, because the boundary is new:

- No file in the repo assumes `/mnt/c`.
- `configuration.dsc.yaml` and `apt-packages.txt` do not declare the same thing
  twice. A package installed on both sides of the boundary is a boundary that
  has already leaked.
- No tracked file contains a CR. `.gitattributes` should make this impossible,
  which is exactly why it is asserted: a rule nobody has watched fail is a rule
  nobody should rely on. Break it on purpose before trusting it.

## Bootstrap

Two steps, and only the first is imperative.

```powershell
# 1. PowerShell on Windows, once:
winget configure .\windows\configuration.dsc.yaml
```

```bash
# 2. Inside Ubuntu, once:
git clone https://github.com/camilopiedra92/workstation ~/workstation
~/workstation/wsl/install.sh
```

`winget configure` is idempotent by design. `install.sh` is idempotent by test —
`check.sh` runs it twice and asserts the second run changes nothing, which is
the check the Mac repo already has.

## Out of scope

- Any change to the `dotfiles` repo. It stays macOS-only.
- Sharing files between the two repos. The discipline is shared; the content is
  not. A shared file would need a mechanism to keep it in sync, and that
  mechanism is a third thing to maintain and the first thing to rot.
- Docker. It already runs on WSL2 through Docker Desktop and is not part of what
  this repo declares yet. It is added when there is a reason, not preemptively.
- Dev Drive. A ReFS volume optimised for build workloads is the native Windows
  answer to a problem ext4 already solves here.

## Expiry dates

Written down so they are not discovered by accident.

| When | What |
|---|---|
| 2026-10-28 | Node 26 becomes Active LTS. Change `node = "26"` back to `"lts"`. |
| When gcloud arrives | Add `python = ["3.14", "3.13"]` with the gsutil reasoning. |
| When Ghostty ships Windows | Re-evaluate the terminal. Not on its roadmap today. |
