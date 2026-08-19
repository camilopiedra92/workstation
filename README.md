# workstation

[![CI](https://github.com/camilopiedra92/workstation/actions/workflows/ci.yml/badge.svg)](https://github.com/camilopiedra92/workstation/actions/workflows/ci.yml)

This machine's development environment, declared as code.

**A Globant-issued Windows 11 laptop whose development environment is Ubuntu on
WSL2.** Both halves are declared here, in one repository, with one set of
checks. The Windows layer is deliberately thin: everything in it exists to make
the WSL layer reachable, visible or typeable — the subsystem, a terminal, a
font, an editor — plus the tools needed to author this repo. No runtimes, no
repositories, no development on the host. Everything else is inside Ubuntu.

The macOS counterpart is the `dotfiles` repo, and nothing is shared with it at
the file level. What was taken from it is the discipline: the environment is a
repo rather than a memory, one manifest per manager with the boundary written
down, everything pinned with its reason and its expiry, one place for the
checks with three audiences, and identity and secrets outside the repo so the
repo can be public. Sharing a file instead would need a mechanism to keep two
repos in sync, and that mechanism is a third thing to maintain and the first
thing to rot.

## New machine

```powershell
# 1. PowerShell on Windows, from the repo root, once. Raises UAC:
.\windows\bootstrap.ps1
```

```bash
# 2. Inside Ubuntu, once:
git clone https://github.com/camilopiedra92/workstation ~/workstation
~/workstation/wsl/install.sh
```

Step 1 is `bootstrap.ps1` rather than `winget configure` typed directly, and the
difference is not convenience. The script passes
`--accept-configuration-agreements`, without which the command stops on a
confirmation prompt; it asserts winget is new enough to have `configure` at all,
turning "the command does nothing recognisable" into a sentence that says why;
and it checks `$LASTEXITCODE` after every winget call, which is the one thing
`$ErrorActionPreference = 'Stop'` does not do for you.

`winget configure` is idempotent by design, so re-running the script is safe.
`install.sh` is idempotent by test: `check.sh` runs `install.sh --links-only`
twice and asserts the second run changes nothing.

## Architecture

| Layer | Tool | What it manages |
|---|---|---|
| Windows host | WinGet Configuration | the subsystem, terminal, font, editor, and this repo's authoring tools (`windows/configuration.winget`) |
| System, inside Ubuntu | apt | compilers, libraries, the login shell (`wsl/apt-packages.txt`) |
| Runtimes and tools | mise | node, python, pnpm, and every CLI you type (`wsl/mise/config.toml`) |
| Python | uv | packages, venvs and projects, plus CLI tools (`wsl/uv-tools.txt`) |

Rule: **apt installs what the system needs, mise installs everything you use,
uv installs Python CLIs.**

That widens mise's domain compared with the Mac's rule, which is *"Homebrew
installs programs, mise installs runtimes"*. The naive translation — apt in
Homebrew's place — is wrong here, because apt carries stale versions of exactly
the tools in use (`eza`, `bat`, `fd`, `rg`, `delta`, `zoxide`) and does not
carry `starship` at all. The Mac's rule forbids a *runtime* coming from the
system package manager, and this respects that; what changes is that user tools
move to mise as well, which serves the pinning discipline better than apt does.
mise's `ubi` and `aqua` backends install at a fixed version with a checksum,
while apt gives whatever is in the archive that day and moves underneath you.

The test for the apt list: would this still need to exist if you never opened a
terminal? If yes, apt. If no, mise.

`check.sh` enforces the boundary rather than trusting it — a package declared on
both sides of it is a boundary that has already leaked.

## The measurement everything /mnt/c rests on

Measured on this machine on 2026-08-18, under Ubuntu 26.04 on WSL2, creating
2000 files:

| | |
|---|---|
| ext4 (`~`) | **0.065s** |
| `/mnt/c` | **7.554s** |

A factor of **116**. Public benchmarks report nine to twenty times, which is the
number this repo's design was originally argued from; the measured one is an
order of magnitude past it, on the hardware that matters.

That single number justifies what would otherwise look like taste:
repositories live at `~/Development` on ext4 and are never worked on through
`/mnt/c`; the terminal's `startingDirectory` is inverted (below) so no tab ever
opens on the Windows side by default; and the repositories that were already on
`C:\` were re-cloned into Ubuntu rather than reached across the boundary.

`/mnt/c` stays mounted, and disabling `automount` was considered and rejected.
The rule is that `/mnt/c` is never a *working* path, not that it is
unreachable — the migration went through it, and reaching a Windows file
occasionally is legitimate. Windows can still see the Linux side through
`\\wsl$\Ubuntu-26.04\home\...`; that path is for looking, not for working.

## Files

```
check.sh                      every check, run by you, the hook and CI
drift.sh                      what this machine has that nothing here declares
bump-tools.sh                 moves the pinned versions to their latest releases
.gitattributes                LF everywhere, whatever a clone has autocrlf set to
.editorconfig                 formatting, read by shfmt and by the editor
.taplo.toml                   which schema validates which TOML, for taplo and the editor
githooks/pre-commit           runs check.sh --strict before each commit
githooks/pre-push             refuses to rewrite or delete the default branch
schemas/                      vendored JSON schemas: mise, starship, Windows Terminal
docs/                         the design spec, and runbooks for the steps no script can perform
.github/workflows/ci.yml      the two jobs: content on Ubuntu, Windows-only questions on Windows
.github/tool-checksums.txt    pinned hashes for the tools CI installs
.github/dependabot.yml        renews the action SHAs those workflows pin

windows/configuration.winget  the host, declared. The Brewfile's counterpart
windows/bootstrap.ps1         the only imperative step
windows/terminal/settings.json   Windows Terminal, translated from the Mac's Ghostty config
windows/vscode/settings.json     host-side editor settings: what the local UI renders

wsl/install.sh                symlinks + full installation, run inside Ubuntu
wsl/apt-packages.txt          what the system needs
wsl/mise/config.toml          runtimes and user tools, pinned
wsl/uv-tools.txt              Python CLIs, each pinned to a reference
wsl/zsh/.zshenv               XDG paths and PATH; linked into both $HOME and ZDOTDIR
wsl/zsh/.zshrc                history, completion, fzf, aliases
wsl/zsh/.zsh_plugins.txt      plugins (antidote)
wsl/starship.toml             prompt
wsl/git/config                git config, without identity
wsl/git/ignore                global gitignore
wsl/vscode/settings.json      remote-side editor settings: what needs the toolchain
wsl/claude/settings.json      Claude Code settings, merged into ~/.claude rather than linked
wsl/claude/CLAUDE.md          what the agent should know about this environment
wsl/claude/statusline.sh      Claude Code statusline
wsl/claude/subagent-statusline.sh   per-agent telemetry in the agent panel
wsl/claude/statusline-demo.sh       renders both with sample cases
```

`$ZDOTDIR/.zsh_plugins.zsh` is **generated**, not versioned: antidote
regenerates it whenever `.zsh_plugins.txt` changes.

## Where things land

`install.sh` links from the repo into XDG paths, and copies or merges instead
wherever the program on the other end rewrites its own configuration:

| | |
|---|---|
| `~/.zshenv` | cannot be moved: zsh reads it before it can know about `ZDOTDIR` |
| `~/.config/zsh/` | `.zshenv` again — the same file, linked twice, see below — plus `.zshrc`, `.zsh_plugins.txt` and the generated `.zsh_plugins.zsh` |
| `~/.config/starship.toml`, `~/.config/mise/config.toml` | linked |
| `~/.config/git/` | `config`, `ignore`, and the unversioned `config.local` |
| `~/.local/state/zsh/history` | state the shell writes, not config you edit |
| `~/.claude/` | `statusline.sh`, `subagent-statusline.sh` and `CLAUDE.md` are linked; `settings.json` is **merged** with `jq`, because Claude Code rewrites it |
| `~/.vscode-server/data/Machine/settings.json` | **copied**, because VS Code Server rewrites it |
| `/etc/wsl.conf` | interop narrowed, see below |

`install.sh` also removes a leftover `~/.gitconfig` after linking the XDG path,
because git reads both and the legacy file wins — so leaving it behind means the
linked config is read and then overruled.

Windows Terminal's own `settings.json` is deployed by copying too, for the same
reason and proven the same way: the repo writes `"defaultProfile":
"Ubuntu-26.04"`, and after the first launch the deployed file said
`{ddad2f1c-79f7-5b21-a2c2-7560c6c23ae0}`. Terminal accepted the name and
rewrote the file with the GUID it generates for that distro. Anything that
rewrites its own configuration must never be symlinked.

## Why WSL2

The work on this machine is Node/TypeScript, git, markdown and Claude Code.
Across the projects present there was one `.ps1`, one `.sh`, one `.py` and one
`.ts`. Nothing touches a Windows API. The evidence, from primary sources:

- Microsoft's own Mac-to-Windows guide states: *"Using WSL provides the kind of
  environment most familiar to Mac users."* Its native-Unix story — Coreutils,
  `sudo`, `curl` — is framed as covering *"basic tasks"*.
- mise, which is the centre of this toolchain, documents native Windows as
  supported *"via the use of shims until someone adds PowerShell support"*, and
  has open reports of those shims polluting the WSL `PATH`.
- Nix, the ceiling for reproducibility, officially supports macOS and Linux
  only. On Windows it runs under WSL2. Choosing native Windows would close that
  door permanently.
- Anthropic documents WSL2 as the recommended WSL version for Claude Code.
- The filesystem measurement above.

Ghostty does not run on Windows and is not on its roadmap, so the terminal is
replaced rather than ported. It is the only piece of the macOS environment with
no equivalent path.

## Why there is no .zprofile

The Mac repo needs a long section here. This one does not, and the shortness is
the point.

On macOS, `/etc/zprofile` runs `/usr/libexec/path_helper` between `.zshenv` and
`.zprofile`, and path_helper does not append to `PATH` — it rebuilds it, so
everything `.zshenv` prepended lands behind `/usr/bin`. `.zprofile` exists there
to re-source `.zshenv` once path_helper is done.

Linux has no path_helper. The problem is gone, so the file is gone, and
`check.sh` asserts it stays gone. That the whole apparatus evaporated on
changing platform is the confirmation it was diagnosed correctly on the Mac: it
was a macOS problem, not a shell problem.

What does survive is the **double link of `.zshenv`**, because that is zsh
behaviour rather than macOS behaviour and applies identically here. zsh reads
`$HOME/.zshenv` when `ZDOTDIR` is unset in the environment and
`$ZDOTDIR/.zshenv` when it is already exported — one or the other, never both.
The second branch is every shell spawned from one this repo already configured:
a git hook, `zsh -c` from an editor. With only the `$HOME` copy linked those
read *neither* file and start with the bare system `PATH`, so a hook reports
`node: command not found` on a machine where the terminal beside it resolves
node fine. `typeset -U path` is what makes linking the same file into both
places safe rather than merely tolerable.

## Why interop is narrowed

`install.sh` writes `appendWindowsPath = false` into `/etc/wsl.conf`. That is
the only mechanism; `.zshenv` records the reasoning beside the `PATH` it builds
rather than duplicating it. The individual Windows commands this environment
actually calls are aliased in `.zshrc`.

The speed argument is real but secondary: interop puts roughly forty Windows
directories into every shell, and every command lookup walks them. **The
correctness argument is the one that decides it.** Every file under `/mnt/c` is
executable as far as Linux is concerned, and mise's Windows shims live there. A
shimmed tool found on that PATH runs a Windows script inside Linux — the same
tool name, a different program, no error.

Note also what this does **not** do. Narrowing PATH interop does not make
`/mnt/c` unreadable, and nothing about it stops a process from opening a file
there by path. That is precisely why the Claude Code deny list carries the host
paths it does.

## The Claude Code settings

`wsl/claude/settings.json` is strict JSON with no room for comments, so the
reasoning lives here. It is merged into `~/.claude/settings.json` with `jq`
rather than symlinked, because Claude Code rewrites that file on its own
(theme, `/config`) and a symlink would end up overwritten. The repo's values win
on conflict; anything the machine added that the repo does not mention is
preserved.

- **`forceLoginMethod` is `claudeai`, matching the account that pays for this.**
  This machine had `console`. It is not cosmetic in either direction: set to
  `console` it would refuse the login entirely on a new machine, and the wrong
  value in the other direction lets an accidental Console login bill per token
  instead of drawing on the subscription. Nothing surfaces this on a machine
  that is already signed in, which is what makes it worth writing down.
- **`effortLevel` is absent on purpose, and not set to `high` either.** The
  model's own default is already `high`, and writing that down would freeze it:
  a future model shipping a better default would be overridden by a line nobody
  revisits. Same argument as `node = "lts"` rather than a number. Escalate per
  session with `/effort`, which is also the only place `max` and `ultracode` are
  reachable — the settings file does not accept them. `check.sh` asserts the key
  stays absent, because an absence has nothing else to defend it.
- **`fallbackModel` matters because `model` is pinned.** With one model named
  and no chain, an overload is a stopped session rather than a slower one.
- **`autoUpdatesChannel` is `stable`**, roughly a week behind and skipping
  releases with major regressions. The machine had `latest`. Every other tool
  here is pinned and checksum-verified; following `latest` for the tool doing
  the work was the inconsistency.
- **`attribution` replaces `includeCoAuthoredBy`**, which the schema marks
  deprecated. Same intent, the key that still exists.
- **`enabledPlugins` lists only the ones that are on.** A `false` entry is a
  plugin someone tried and turned off, and reproducing it on a new machine would
  mean installing it in order to disable it.
- **`extraKnownMarketplaces` is not versioned at all.** Every enabled plugin
  comes from `claude-plugins-official`. The machine declared a `personal`
  marketplace pointing at a local directory, which could not transfer anyway.
- **`permissions` has split ownership.** The repo owns `deny`, which is the same
  everywhere. `allow` accumulates per project — domains, MCP tools — and stays
  out, which is why `deny` is an array the merge replaces whole while `allow` is
  never mentioned.
- **`additionalDirectories` grants `~/workstation` and nothing else**, so a
  session opened in a project can still read this repo without being handed the
  home directory.
- **`disableBypassPermissionsMode` is `disable`, set on purpose.** The
  documentation limits `bypassPermissions` to "isolated environments like
  containers or VMs where Claude Code can't cause damage", and this laptop is
  neither. The same page notes a user can set this in their own settings to lock
  themselves out of the mode, which is what this does.
- **Home rules carry a `~/` prefix and project rules do not**, which is the
  difference between a rule that works and one that reads as if it does. An
  unprefixed pattern in user settings anchors at the *current directory*, so
  `Read(**/.ssh/**)` only ever matched a `.ssh` folder inside whatever project
  was open.

### The Windows host paths, and why the Mac has none

The Mac's deny list was written for a machine with no Windows host beneath it.
Here, the host's credential stores are ordinary readable files from inside
Ubuntu, reachable at `/mnt/c/Users/...`, and narrowing interop does not change
that. So the list is extended with the host's copies of what the Linux side
already protects: SSH and AWS credentials, the Azure and gcloud directories,
`gh`'s hosts file, the npm configuration, Docker's config, Claude Code's own
credentials on the host, `.git-credentials`, and PowerShell's PSReadLine
history.

**Every one of those is written with a leading double slash**, as
`Read(//mnt/c/Users/...)`, and that is load-bearing rather than cosmetic. In a
permission rule a single leading slash is relative to the settings file's own
directory, so `Read(/mnt/c/...)` resolves under `~/.claude/` and matches nothing
that exists. These rules shipped with one slash. They were inert for as long as
they existed, and the check written to police them compared the settings file
against templates carrying the identical mistake -- so it reported the host as
covered throughout.

What found it was Task 12 Step 5, which is the only step in this repo that tests
a rule by trying to violate it. A probe file placed inside a denied directory was
read without complaint; the same read was refused the moment the rule was
rewritten with two slashes. That is the fourth defect in this repo to live in a
check rather than in the configuration it judges, and the first one that had a
credential behind it.

Two of those deserve their reasoning stated, because neither is derivable from
the Mac's list:

- **Claude Code's own credentials on the host.** The agent running in WSL would
  otherwise be able to read the credentials of the installation it is replacing.
- **PSReadLine's `ConsoleHost_history.txt`.** It routinely holds pasted tokens,
  connection strings and one-off secrets, and nothing ever prunes it. The Linux
  mirror — `~/.local/state/zsh/history` — is deliberately left readable, because
  `.zshrc` sets `HIST_IGNORE_SPACE`, so a leading space keeps a command out by
  choice, and an agent seeing recent commands is usually the point. PowerShell's
  history has neither the control nor the upside.

**One of these rules protects nothing today, and it is better to say so than to
let a reader count it as covered.** `gh` on this machine stores its token in the
Windows Credential Manager: `gh auth status` reports `keyring`, and no
`hosts.yml` exists anywhere under the user profile. The rule stays as defence
for the file-based fallback. Likewise `.ssh` and `.aws` do not exist on this
host at all, so those cover nothing yet either — correctly, as defence for
later. A rule that matches nothing and a rule that protects something look
identical in the file.

### Why the deny list is doubled

Every host path is listed twice: once with this machine's user name spelled out,
once with a `*` in its place.

> The glob is the rule; the literal is the guarantee. A deny list is the one kind
> of configuration where a pattern that silently fails to match is worse than no
> pattern at all — it reads as protection while providing none. That pattern is
> exercised on exactly one machine, by one person, who has no reason to test it.

`check.sh` builds its assertion list from a path template, so it checks both
forms of every category. It previously asserted only some globbed patterns,
which meant a check that claimed to cover the host covered a fraction of it and
would have stayed green while every literal was deleted.

### The statuslines

Reused from the Mac unchanged, which is one of the consequences of running
Claude Code inside WSL rather than on the host: `~/.claude` is a Linux path, so
these bash scripts have a shell, the deny paths are POSIX, and `CLAUDE.md`
describes the environment actually being edited. Run on the host reaching into
`\\wsl$\...`, all three break at once.

The main statusline is two lines: identity on top (model, path, branch, PR) in
powerline style, and gauges below (context, limits, cost) on a clean background,
so color keeps working as an alarm. `STYLE` and `LINES`, at the top of the
script, switch to `minimal` and to a single line. Both require a Nerd Font,
which `windows/terminal/settings.json` already sets.

To see them without restarting Claude, including the cases you cannot trigger at
will:

```bash
~/workstation/wsl/claude/statusline-demo.sh
```

### What a deny rule can and cannot reach

It covers Claude's own file tools and the shell commands Claude Code recognises
— `cat`, `head`, `sed` — and stops at anything that opens a file itself. A
one-line Python or Node script reads a denied path without touching any of it.

**The tool name in the rule is not a free label.** A file rule is matched
against `Read(...)` or `Edit(...)` and nothing else; `Edit(...)` is what the
engine consults for all three file-editing tools. `Write(//mnt/c/**)` and
`NotebookEdit(//mnt/c/**)` name real tools, read as protection, and are never
consulted — both shipped inert in the commit that added them, and `check.sh`
demanded them by name, because the check was built from the same wrong model as
the file it judges. Claude Code prints a warning about each at startup, which is
what surfaced it, hours later rather than months. That is the fifth defect here
to live in a check rather
than in the configuration it judges, and the second — after the single-slash
rules above — where the shape of the failure was a rule that could not fire.

## What did not port

Recorded rather than omitted, because a dropped setting that is written down is
information and one that is silently omitted is a hole.

| From the Mac | Why not here |
|---|---|
| `font-thicken` | a macOS antialiasing correction; the problem does not exist on Windows' rasteriser |
| `window-colorspace = display-p3` | no counterpart |
| `background-blur = macos-glass` | the nearest thing is `useAcrylic`, a different material rather than the same one renamed |
| `window-padding-color = extend` | no counterpart |
| `minimum-contrast` | no counterpart |
| `bin/dev-nuke.sh` | it resets Homebrew and macOS caches, neither of which exists here |
| `ohmyzsh/plugins/macos` (`ofd`, `pfd`, `cdf`) | Finder wrappers |
| the second Python (`3.13`) | the Mac carries it solely because gcloud ships no interpreter and gsutil refuses anything newer. There is no gcloud on this machine; copying it would be carrying a workaround for a problem this machine does not have |
| the whole cask layer, and `.zprofile` | above |
| `claude-hud` | the statuslines already fill that role, and two things installed for one role is the failure the one-font check exists to forbid |

## Checks

```bash
./check.sh
```

One script is the whole point. You run it by hand, `githooks/pre-commit` runs it
before every commit, and CI runs that same file rather than reimplementing
anything — checks written twice drift, and the moment CI and local disagree you
stop trusting both. To bypass the hook once: `git commit --no-verify`.

A check either runs (`ok` / `FAIL`) or is skipped because its tool is missing. A
skip is a hole in coverage, not a neutral third outcome, so both gates turn it
into a failure; `./check.sh --strict` reproduces that by hand, and CI turns it
on by itself because every CI system sets `CI`. Without it, a missing tool turns
into a green run that verified less than you think.

This repo spans two platforms and the checks mostly do not. Almost everything
here validates file content — YAML, JSON, TOML, shell — which needs the files
and not the operating system. The handful of questions that genuinely need
Windows (`winget configure validate`, and asserting the DSC resource names
resolve) live in the second CI job. Nothing goes to a runner that cannot answer
it honestly.

Configs are validated against schemas, not merely parsed. Parsing is the easy
half: a misspelled key is valid YAML, valid JSON and valid TOML, and the program
reading it usually drops the option and carries on. The Windows Terminal
settings are validated against Windows Terminal's published schema, and the TOML
files against vendored schemas through `.taplo.toml`, which the CLI reads and so
does the *Even Better TOML* editor extension where somebody has installed it —
so the check and the autocomplete cannot disagree about what a valid key is.

The schemas are **vendored** rather than fetched at check time. A gate must not
need the network: a check that goes red because DNS blinked is a check you learn
to ignore. Vendoring also puts a schema change in a diff somebody reads. The
cost is that a vendored copy goes stale, and stale has a specific shape — adopt
a key upstream added after the copy was taken, and the check calls your correct
config invalid. **Nothing here notices that** — see the exemptions below for
what it costs and why it was accepted.

### The checks were the most dangerous thing in this repo

Worth stating plainly, because it is the through-line of building it. The worst
defects found were not in the configuration. They were in the checks, and every
one of them was green:

- The `/mnt/c` check passed for two tasks **without reading a single line**. Git
  for Windows rewrites an argument that looks like an absolute Unix path before
  `git.exe` sees it, so the pattern with a leading slash matched nothing. The
  pattern now omits the slash, which matches the same lines on both platforms.
- The identity check guarded one file while the identity sat in another.
- The host-coverage check asserted a fraction of the categories it claimed to
  cover, in one of the two forms.
- Its replacement could silently degrade, because `str.format()` ignores an
  extra argument when the template has no placeholder rather than raising — so a
  template added without one would have produced two identical assertions and
  grown the count by two while verifying one string twice. It now fails loudly
  and names the offending template.

Every one was found by asking what the check actually inspects rather than
whether it passes. Break a check on purpose before trusting it; a rule nobody
has watched fail is a rule nobody should rely on.

Two more arrived later and they invert the shape: not green while inspecting
nothing, but red while explaining nothing. Both CI jobs had failed on every
run this repo ever had, for reasons that had nothing to do with the files CI
judges.

- **zsh was never on the CI runner**, and the workflow's own comment asserted
  it was. So `check.sh`'s zsh check failed under `--strict` every time — the
  design working exactly as intended, reporting a hole in coverage — and
  nothing downstream depended on the answer.
- **The Windows job discarded the answer it was given.** `winget show` piped
  its output to `Out-Null`, so when winget stopped to ask whether the msstore
  source agreements were accepted — on a runner, with no stdin to answer
  from — what reached the log was nine unresolvable package ids and no cause.
  `Microsoft.WindowsTerminal` was among them, which is the tell that the ids
  were never the problem. `bootstrap.ps1` had carried the fix for this exact
  class since the day it was written: `--accept-configuration-agreements`, one
  command over.

So the rule those first four produce needs its other half: **a check must
report what it saw, not only its verdict.** A red check that names no cause
costs the same investigation as no check at all, and buys a false sense that
something is being watched.

Which is the third finding, and it is not about a check but about what was
enforcing them: **nothing was.** *Changing something*, below, described a
default branch that takes no direct pushes; GitHub answered `404 Branch not
protected`, with no rulesets at all. Every commit on `main` went in directly,
CI ran afterwards, and it was red on all five. The paragraph describing the
protection was the only thing providing it — R36's shape one layer up, and
the reason the two failures above survived from the first commit: no merge
ever depended on them.

### When a check produces a false positive

The cleanest lesson of the build, and the one most likely to be repeated.

The identity check matched `name=$(basename "$d")` in a runbook — a genuine
false positive. An exclusion for `*.md` was added, on the reasoning that
markdown is prose. That exclusion then hid a real address in the plan document
for a round: the exact string a history rewrite had just been performed to
remove.

The fix was not a narrower exclusion. It was a better discriminator — require
whitespace before the `=`:

```
^[[:space:]]*(name|email)[[:space:]]+=
```

Shell assignment cannot have a space there; that is syntax, not convention. Git
config conventionally does. One character, and the exclusion became
**unnecessary rather than smaller**, so there is now no file this check cannot
see.

> When a check produces a false positive, the question is not "what do I
> exclude" but "what actually distinguishes the two cases". Excluding is always
> faster and always leaves a hole shaped exactly like the exclusion.

The same round found the other half of the pattern: an allowlist that is
unanchored on the left launders anything preceding it, so a line ending in the
allowed placeholder passes with a real address in front of it. Both the pattern
and its exception have to be anchored to mean what they read as.

## Encoding, and the boundary that produces it

This repo has hit a run of defects that look unrelated and share one root.
Listing them together is more useful than scattering them as comments, because
the next one will look like none of them individually and like all of them
collectively:

- **CRLF on commit.** Git for Windows ships `core.autocrlf=true`; a `.sh`
  reaching Ubuntu with CRLF fails at the shebang with `bad interpreter:
  /usr/bin/env bash^M`, naming neither the file nor the cause. Fixed by
  `.gitattributes` declaring `* text=auto eol=lf`, which takes the machine out
  of the answer entirely.
- **CRLF carried in by `cp`.** The same setting means a clone made on this host
  has CRLF in its working tree, so a naive `diff` against it reports every line
  as changed. Comparing content rather than line endings needs `tr -d '\r'`
  first.
- **cp1252 on read.** Python's `open()` uses the locale encoding. Bytes
  undefined in cp1252 raise — that is how this was found, on the vendored
  Windows Terminal schema — but *every other non-ASCII byte decodes silently
  into different characters*, which is worse, because a check comparing those
  reaches a confident wrong answer. Fixed by `PYTHONUTF8=1` plus an explicit
  `encoding='utf-8'` at each call site. Both, deliberately: the environment
  variable covers the call sites nobody has written yet, and the explicit
  argument survives a check being copied into a terminal to debug it.
- **UTF-16LE from `wsl.exe`.** `wsl --list` output is full of NUL bytes to a
  consumer expecting text, so a match against it silently never succeeds — which
  in a DSC `TestScript` means reinstalling the distro on every run while
  reporting success. Fixed by `WSL_UTF8=1`.
- **UTF-16LE from `winget.exe`.** Same shape, different binary.
- **`\n` becoming `\r\n` on write.** Windows-native Python in text mode
  translates newlines. Nothing shipped is affected because the checks only read,
  but anything that writes a file must open binary or pass `newline=''`.
- **An argument rewritten in transit.** Git for Windows converts what looks like
  an absolute Unix path into a Windows path before the program sees it. That is
  the vacuous `/mnt/c` check above, and it is the same species: a value changing
  meaning as it crosses.
- **`ln -s` silently copying.** Git Bash on this host has no symlink privilege,
  so `ln -s` produces a regular file with no error and `[ -L ]` is false; the
  same command inside Ubuntu produces a real symlink. If anyone ever ran
  `install.sh` from Git Bash, every link would become a copy and editing the repo
  would stop propagating to the live config — with everything appearing to work
  until a change had no effect.
- **A write that reported success without landing.** A `cp` did not take, and a
  `diff` run immediately afterwards reported no difference. Verifying a revert
  has to be a fresh read, or a re-run of the thing that failed — not a comparison
  made in the same breath as the write.

The generalisation is worth stating: **anything crossing the Windows/Linux
boundary carries an encoding, a translation or a privilege until something pins
it.** This many is not bad luck; it is a property of the architecture, and the
next one is already out there.

## Decisions that look odd without their reasoning

- **`startingDirectory` lives in `profiles.defaults`, and is overridden back to
  `%USERPROFILE%` on the PowerShell profile.** It reads backwards. Windows
  Terminal generates the WSL profile itself and derives its GUID from the distro
  name, so there is no stable id to hang a per-profile setting on — a
  hand-written GUID points at nothing, or creates a duplicate profile beside the
  real one with the settings applied to the decoy. Unset, the documented default
  is `%USERPROFILE%`, which is `/mnt/c` from inside Ubuntu: not an occasional
  mistake but the default in every new tab, at the cost measured above.
  PowerShell's GUID is a fixed built-in constant, so the override goes there.
  Confirmed working: `pwd` in a fresh tab returns `/home/camilo`. `check.sh`
  asserts the setting exists, points at the WSL side, and names the same distro
  that `configuration.winget` installs.
- **Ubuntu is installed by a DSC `Script` resource, not a package id.**
  `Canonical.Ubuntu.2604` does not exist in winget; the newest there is 24.04.
  Downgrading would have traded two years of support for the convenience of
  using one tool for everything. `Script` is an inbox DSC resource Microsoft
  documents alongside `Environment`, `Registry` and `Service`, so this is DSC's
  own answer for a state no packaged resource covers, and `TestScript` keeps it
  idempotent.
- **`gh` comes from mise, not apt.** git's credential helper invokes it, so a
  missing `gh` is not a missing convenience — it is every push failing with an
  opaque credential error naming neither cause. From mise because apt's `gh`
  trails upstream, and this is the one tool whose auth flow moves with the
  service it talks to.
- **`git` is not declared on the host.** All git work happens in WSL, where
  `gh auth setup-git` provides credentials, mirroring the Mac exactly. A
  host-side credential-manager bridge is the documented alternative and is
  rejected: it creates a cross-boundary dependency to solve a problem that does
  not exist once nothing on the host uses git. Not declared is not the same as
  removed — Git for Windows and a host `gh` were both here before this repo
  existed, and `drift.sh` reports them as installed-and-undeclared, which is the
  correct verdict.
- **`core.fsmonitor` is absent, and the absence is a pending measurement rather
  than an oversight.** On macOS it is backed by FSEvents, where the Mac repo
  measured a real difference. Here it would be git's own daemon watching a
  virtualised ext4 volume under WSL2 — a different mechanism at a different
  cost, and nothing about the Mac's number transfers. The measurement procedure
  is written down in `docs/runbook-tasks-10-11-build-and-migrate.md`; a setting
  that buys nothing is not neutral, it is a claim nobody checked.

## What applying this to a real machine taught

Both of these were invisible until the manifest met the host, and both are
counter-intuitive enough to be re-broken by a well-meaning edit.

**`Ensure: Present` is not a version claim.** The first apply reported `Unit
successfully applied` over a Windows Terminal six minor versions behind, because
any installed version satisfies `Present`. *Unpinned* and *unasserted* are
different states, and the manifest wants the first: the packages that are
deliberately not pinned carry `useLatest: true`, which makes `Test` consult
whether an update is available and makes `Set` perform it. Do not remove it as
redundant on the belief that these applications update themselves out of band —
on this machine one of them demonstrably did not, and the manifest reported
success while delivering a build from years earlier.

**`$ErrorActionPreference = 'Stop'` does not catch a native executable's exit
code.** `bootstrap.ps1` called a winget setting that had become obsolete, winget
rejected it and printed a wall of usage text, and the script carried on
reporting success. Every winget invocation now checks `$LASTEXITCODE` through a
helper. Anyone reading PowerShell with a `Stop` preference at the top will
assume that case is handled; it is not.

One winget call is deliberately not wrapped in an output-capturing helper:
`winget configure` itself, because capturing would buffer the live progress and
the UAC prompt the bootstrap depends on. The exit-code check runs immediately
after it instead.

## Exemptions to the rules stated here

An unstated exception to a stated rule reads as an oversight, and someone
eventually "fixes" it. Each of these is a real, defensible gap:

- **`windows/vscode/settings.json` is not schema-validated**, while every other
  config key here is checked against its published schema. VS Code generates its
  settings schema per install from the extensions present, so there is no static
  authoritative document to vendor. The gap is unavoidable rather than an
  oversight. If VS Code ever publishes a static schema, it gets vendored under
  `schemas/` and validated like the rest.
- **The vendored schemas under `schemas/` have no staleness check.** Nothing
  compares them against upstream and nothing notices when a published schema
  moves. What that looks like when it happens: a key upstream has added is
  rejected here with a message about an unknown property, which is a confusing
  way to learn that a schema is old — the config is right and the check is
  wrong, and the message says the opposite. Re-vendoring is therefore a manual
  act, done when a key this repo wants to use is refused. Automating it would
  mean a network call from a script that is otherwise entirely local, which is
  the reason it has not been done rather than an oversight. That leaves the
  schemas the one pin here whose renewal depends on somebody noticing, which is
  worth saying out loud precisely because everything else was built not to.
- **No VS Code extension is declared anywhere here**, and two of the sentences
  above quietly depend on one. `.editorconfig` reaches the editor through the
  EditorConfig extension, and `.taplo.toml` reaches it through *Even Better
  TOML*; both are installed by hand today. The Mac repo's Brewfile carries its
  extension list and this repo has no equivalent manifest yet, which makes this
  the one place where "the environment is a repo, not a memory" does not hold.
  Neither gap reaches the gates — shfmt and taplo read those files directly, so
  the hook and CI are unaffected either way, and the exposure is that a fresh
  machine's editor silently formats to its own defaults until somebody notices.
- **Some authoring dependencies on the Windows host are undeclared, on
  purpose.** `configuration.winget` declares shellcheck, shfmt and taplo,
  because their whole justification is that the host and CI reach the same
  verdict on the same file, so they are pinned to the versions CI installs. It
  deliberately does **not** declare pyyaml and jsonschema (installed with pip) or
  jq (installed with winget): those are transitional, needed only while this repo
  was authored on the host, and are declared permanently where they belong — as
  `python3-yaml` and `python3-jsonschema` in `wsl/apt-packages.txt`, and as `jq`
  in `wsl/mise/config.toml`. `configuration.winget` declares the machine's steady
  state, and a transitional dependency written there would outlive its reason and
  be believed by whoever reads it next. The consequence is that `drift.sh` names
  the host's Python and its jq as installed-but-undeclared, which is understood
  rather than investigated. The pip packages it does not name at all: that
  section compares winget ids, so nothing here sees a pip install on the host in
  either direction.

## Finding drift

```bash
./drift.sh
```

Asking whether everything declared is installed is the easy direction, and a
subset always answers yes. The gap it leaves is everything installed and never
written down, which is the direction drift actually grows in. `drift.sh` reports
**both** directions, separately, because they mean different things and get
fixed differently: declared but not present is a broken machine, and present but
not declared is an undocumented one.

One section per manifest:

| | compared against |
|---|---|
| `wsl/apt-packages.txt` | `apt-mark showmanual` — what was asked for, not the dependency tree apt pulled in behind it |
| `wsl/mise/config.toml` | `mise ls --current`, by name and then by version |
| `wsl/uv-tools.txt` | `uv tool list`, by name, and the pinned reference against each tool's receipt under `uv tool dir` |
| `windows/configuration.winget` | `winget list` on the host, reached through `cmd.exe` by absolute path |

Two of those are more than a name comparison, for reasons worth knowing. The
mise section checks the resolved version too, because a tool installed at a
different version than its pin is drift that a name-only comparison reports as
agreement — allowing for the two pin styles in that file, since a major-only pin
resolving to a full version is correct rather than drift. It also compares what
mise says it was *asked* for against what this repo declares, which is how a
different config layer winning over this one becomes visible. The uv section
compares the **reference**, not the version, because `uv tool list` reports the
resolved package version while `uv-tools.txt` pins a git tag; those never match,
so the pin is checked against what uv recorded in the tool's receipt.

The Windows section is the one that will report the most, and on this machine
that is the right answer rather than noise: Git for Windows, GitHub CLI, Docker
Desktop, Node and Python all predate this repo. Each is either adopted into
`configuration.winget` or consciously left as known drift. What must not happen
is nobody looking — and the fix for a noisy first run is never an allow-list,
because a list this has been taught to stop reporting is a list that has stopped
working.

It is not part of `check.sh` and CI never runs it, on purpose. Every check in
there has to mean the same thing on a runner as on this laptop; this one cannot,
because a runner arrives with its own preinstalled packages, so "installed but
undeclared" is always true there and never interesting. Wiring it into CI would
either break the build forever on packages nobody put there, or get "fixed" with
a CI-only skip — a check that skips itself on the one machine that would
otherwise run it automatically.

What it does **not** do, so nobody counts it as covered: it makes no network
call. It does not ask whether a pinned version has been superseded, whether
anything installed has left support, or whether the vendored schemas still match
what upstream publishes. Every comparison it makes is between a file in this
repo and the machine it is run on.

## Updating the pins

```bash
./bump-tools.sh
```

The versions in `wsl/mise/config.toml` and the tool pins CI installs are exact,
and exact pins go stale. This makes the chore a command rather than a memory.
Hand-maintained pins are how `eza = "0.24.7"` — a version that was never
released, whose tag returns 404 — reached this repo in the first place, and it
would have failed on the user's machine partway through the build.

Two families of pin, one script, because leaving them apart is how they drift.
A CI tool's version appears in `ci.yml`, again in the step that asserts what is
installed, as a hash in `.github/tool-checksums.txt`, and — for the tools the
host also runs — as a `version` in `configuration.winget`. Those move together
or CI and the host stop agreeing on what a clean file looks like. The mise pins
have no checksum, so that half is simpler: read the current release, rewrite the
pin, leave the reasoning comment alone.

The pinned action SHAs are the exception, and they are renewed rather than
bumped by hand. Pinning an action to a commit stops a moved tag from silently
changing what runs in CI, and the cost is that a pinned SHA never picks up a
security fix on its own. `.github/dependabot.yml` is what closes that: it opens
a pull request when a pinned action moves, and updates the trailing version
comment with it.

Neither of those is auto-merged. Hashes and SHAs from upstream at a given moment
are exactly what a checksum file exists not to take on trust. CI proves the new
versions install and everything still passes; you decide they should be trusted.

That is worth generalising, because it was measured across the whole plan:
**every value copied from a source was correct; every value written from memory
was suspect, and several were wrong.** Every mise tool pin, a package id that
does not exist in winget, a terminal profile GUID, and a path form that mixed
two documented syntaxes. Anything stated as fact without a source is a claim, not a
fact, until something checks it.

## Changing something

The default branch does not take direct pushes, and that is now a GitHub
ruleset rather than a sentence in this file: a pull request is required,
`ubuntu-checks` and `windows-checks` must both pass, and force-pushes and
deletion are refused. Nobody bypasses it, this repo's owner included. Getting
around it means disabling it, which is deliberate and leaves a record — the
same standard `githooks/pre-push` sets for a rewrite, and the whole difference
between a rule and an intention.

This paragraph said all of it before any of it was true. Five commits reached
`main` directly, each running CI *after* the commit was already in — which is
the failure the sentence claims to prevent — and CI was red on every one.
Everything goes through a pull request that CI has to pass first.

```bash
git switch -c what-youre-doing
# ...edit, commit (the hook runs check.sh --strict)...
git push -u origin HEAD
gh pr create --fill
gh pr merge --auto --squash
```

`githooks/pre-push` refuses any push that would rewrite or delete the default
branch, detected not by looking for a flag — git does not tell the hook which
flags were used — but by what a force push actually is: a push whose remote tip
is not an ancestor of what is being sent. It is defence in depth and says so: it
only covers clones that have it installed, and `--no-verify` walks past it. A
deliberate rewrite is still possible, it just has to be deliberate.

## Daily use

```bash
sudo apt update && sudo apt upgrade   # the system layer
mise upgrade                          # runtimes and tools
antidote update                       # zsh plugins
```

Pin versions in a project (creates `mise.toml`, version it with the repo):

```bash
mise use node@24 python@3.13
```

## Expiry dates

Written down so they are not discovered by accident.

| When | What |
|---|---|
| 2026-10-28 | Node 26 becomes Active LTS. Change `node = "26"` back to `"lts"`, which restores the tracking. |
| October 2026 | Python 3.15 ships. The pin moves once the C-extension packages that matter publish wheels for it. |
| When gcloud arrives | Add the second Python back, with the gsutil reasoning next to it. |
| When Ghostty ships Windows | Re-evaluate the terminal. Not on its roadmap today. |
| 2031 | Ubuntu 26.04 leaves support. |
| No expiry | The font pin moves when a glyph problem makes it move. The vendored schemas move when a key this repo wants appears upstream. |
