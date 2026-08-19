# Decisions taken while building this

Thirty-two decisions were made on the owner's behalf during the build. Each is
recorded here with what it decided, why, and **what it costs if it is wrong** —
so any of them can be found, judged and reversed by someone who was not there.

This file exists because the working record that held them does not survive a
clone. It lived under `.superpowers/`, which is git-ignored, while the runbooks
tell the next session to read it after cloning the repository into Ubuntu — so
the handover document did not survive the migration it describes. That was found
by checking rather than by assuming, which is the same reason most of what
follows was found.

Read it when something here looks wrong. Several of these decisions look odd
without their reasoning, and a few were reversed once already by evidence from
the machine itself — `useLatest` is the clearest example: the argument for
leaving those packages unasserted was sound and the first real apply disproved
it.

The entries are in the order they were made. Numbering is the original.

---

Ruling R1: Tasks 4, 10, 11 and 12 are executed by the user, not by subagents — I hand them a verified runbook at the point each is reached, and I verify the result afterwards. Why: each contains a step no non-interactive process can complete — UAC elevation for `winget configure`, WSL first-launch UNIX user creation, `gh auth login`, and the Claude Code login prompt. Subagents execute the file-producing tasks: 1, 2, 3, 5, 6, 7, 8, 9, 13, 14, 15. Cost if wrong: none. A subagent dispatched at these tasks would block on a prompt it cannot answer and time out, losing its turn budget for nothing.

Ruling R2: Task 5 Step 3 and Task 7 Step 3 are deferred to the machine phase rather than dropped. The implementer records them as deferred in its report; I carry both into the runbook for Tasks 10 and 11. Why: both verify against a machine state that does not exist while the task runs — `mise ls-remote` needs mise, and the fsmonitor measurement needs a real migrated repository. Cost if wrong: an unverified version pin or an unmeasured setting ships. Both are caught downstream — Task 10 Step 4 compares every pin against what mise actually resolved, and Task 11 Step 7 is the measurement itself.

Ruling R3: the GitHub remote is created and pushed at the end of the file phase (after Task 9), not in Task 14 Step 5. Why: Task 10 clones the repo into Ubuntu and cannot clone from a remote that does not exist. Cost if wrong: the public repo exists earlier than planned, containing documentation, a check harness and config files. Nothing sensitive — identity and secrets are outside the repo by design, and a check asserts it.

Ruling R4: the windows CI job derives the package ids from configuration.winget instead of hardcoding them. Why: two lists of the same thing drift, and the direction they drift in is silent — a package added to the manifest stops being covered by CI with no error. This is the same argument the plan already makes for the manifests themselves. Cost if wrong: the CI job becomes slightly more complex than a literal array, in exchange for not being able to go stale.

Ruling R5: `windows/terminal/settings.json` does not hardcode a GUID for the WSL profile. Windows Terminal generates WSL profiles dynamically and derives their GUID from the distro name, so a hand-written one either points at nothing or creates a duplicate profile beside the real one. Instead: put every appearance setting in `profiles.defaults`, which applies to generated profiles too, and set `defaultProfile` to the profile name. Task 3 Step 2 confirms against the vendored schema that `defaultProfile` accepts a name; if it does not, the fallback is to leave `defaultProfile` unset and record the GUID after Task 4 installs Ubuntu. Cost if wrong: the terminal opens on PowerShell instead of Ubuntu until the GUID is filled in after Task 4 — cosmetic, and visible immediately.

Ruling R6: the `english_only` check does not exclude `docs/superpowers/**`. Why: the exclusion was in the plan text without a stated reason, and an unchecked region is exactly the silent hole practice #6 exists to prevent. Verified before ruling: `git grep` for Spanish accented characters over all tracked files returns nothing, so removing the exclusion does not fail the check today. Cost if wrong: a doc that legitimately needs an accented character (a quoted Spanish string) fails the check and needs an explicit narrow exception rather than a blanket one — which is the better failure.

Ruling R7: work happens on branch `workstation-setup`, not in a separate git worktree. Why: the plan's later phases clone this repo into WSL at a canonical path and apply it to the machine; a detached worktree adds a path indirection with no isolation benefit for a fresh repo whose only prior content is documentation. Cost if wrong: nothing — main stays untouched either way, and a worktree can still be created later if parallel work appears.

## Progress

Ruling R5 — resolved, no fallback needed. Microsoft Learn (Windows Terminal
startup settings) states for `defaultProfile`: **"Accepts: GUID or profile name
as a string"**. The same page lists `Windows.Terminal.Wsl` among
`disabledProfileSources`, confirming WSL profiles come from a dynamic generator
and that a hand-written GUID would create a duplicate profile beside the real
one rather than configuring it. Task 3 therefore: appearance settings go in
`profiles.defaults`, `defaultProfile` is the string `"Ubuntu-26.04"`, and no
WSL entry is written into `profiles.list`.
Source: https://learn.microsoft.com/en-us/windows/terminal/customize-settings/startup

Ruling R8: shellcheck, shfmt and taplo are installed on the Windows host now and
declared in windows/configuration.winget as a second, named group ("authoring
tools"), distinct from the four packages that make the WSL layer reachable.
Task 2's closed-set check widens to two named sets rather than one.

Why: Task 1 wires a pre-commit gate that runs check.sh --strict, but the tools it
needs do not arrive until Task 10 (via mise, inside Ubuntu, behind the
interactive Task 4). The eight tasks in between would each need --no-verify,
which is the gate deleting itself by attrition. The alternatives are worse:
relaxing the hook reintroduces "a skip reads as a pass", which Task 1 just
measured and the design forbids; leaving the tools undeclared manufactures
exactly the drift practice #7 exists to catch.

Evidence this is the right home: winget serves shellcheck 0.11.0 and shfmt
3.13.1 -- the exact versions the plan's CI pins -- and taplo 0.10.0, likewise.
The host and CI run the same binaries, which is the property the Mac repo's CI
comment argues for. All three installed at user scope with no elevation.

Cost if wrong: the host carries three CLI tools the WSL environment also has.
They are declared, so drift.sh reports them as present-and-declared rather than
as drift, and removing them later is a one-line manifest edit.

Ruling R9: implementers receive the tool PATH prefix as a dispatch instruction,
never as a line in a repo file. winget installed the three as portable packages
under %LOCALAPPDATA%\Microsoft\WinGet\Packages\<id>\ and modified the user PATH,
which shells started before the install do not see. Hardcoding those Windows
paths into check.sh or a hook would couple the repo to the host it is explicitly
designed to leave. Cost if wrong: an implementer that forgets the prefix hits a
refused commit with a legible reason, and retries.

Ruling R10: any file the plan describes as copied from dotfiles is copied with
`cp`, never retyped or reconstructed, and the implementer verifies with
`diff <(tr -d '\r' < SOURCE) DEST` and pastes that output into its report.
Intended edits are applied on top of the copy afterwards, as separate edits.

Why: Task 1 flattened four em dashes while reporting a byte-for-byte match --
a false claim that would have been trusted. The root cause is reconstruction
rather than copying: reading a file and writing it back through a tool that
normalises typography. Tasks 6, 7 and 8 copy far larger files from the same
source (.zshrc, git/config, git/ignore, three statusline scripts, ~900 lines
together). Silent character normalisation across those would be invisible in
review and unrecoverable without the source.

Note on the CRLF trap this exposed: the dotfiles clone sits in a scratch
directory cloned under Git for Windows with autocrlf=true, so its working tree
has CRLF. A naive `diff` against it reports every line as changed. The `tr -d
'\r'` in the verification command above is what makes the comparison mean
content rather than line endings. Implementers must be told this or they will
read a whole-file diff as catastrophic and start "fixing" it.

Ruling R11: the em dashes are restored rather than the repo standardising on
ASCII. Why: the value of a verbatim copy is that a later diff against the source
says whether the file has drifted from its origin. Silently normalising
characters destroys that property -- the same argument this repo makes
everywhere else against losing information quietly. Cost if wrong: newly
authored files in this repo use `--` while copied ones use em dashes, which is a
cosmetic inconsistency; the lost diffability would have been structural.

Ruling R12: configuration.winget declares WSL itself as `Microsoft.WSL`
(a WinGetPackage) and Ubuntu 26.04 LTS through a `PSDscResources/Script`
resource -- NOT as a WinGetPackage.

Why: winget's catalogue stops at `Canonical.Ubuntu.2404`. There is no
`Canonical.Ubuntu.2604`. Verified twice: `winget show --id Canonical.Ubuntu.2604
--exact` returns NOT FOUND, and `winget search Ubuntu` lists 18.04, 20.04, 22.04
and 24.04 and nothing newer. Ubuntu 26.04 is installable -- `wsl --list --online`
offers it as `Ubuntu-26.04` -- just not through winget. The plan asserted an id
that does not exist, and applying it would have failed at Task 4 with a
package-not-found error naming nothing useful.

The two ways out were: downgrade to 24.04, or install it the way Canonical
actually ships it. Downgrading contradicts a spec decision that was argued
explicitly -- 26.04 is supported to 2031, 24.04 to 2029 -- and would trade five
years of support for the convenience of using one tool for everything.

`Script` is an inbox DSC resource Microsoft documents alongside Environment,
Registry, Service and WindowsFeature, so this is not routing around DSC: it is
DSC's own answer for a state no packaged resource covers. Idempotence, the
property that actually matters, is preserved -- Test checks whether `wsl -l -q`
already lists the distro, Set runs the install.

Verified for this ruling: `Microsoft.WSL` exists in winget at 2.7.11;
`wsl --install` accepts `-d <DistroName>` and `--no-launch, -n`.

Cost if wrong: if the Script resource misbehaves under `winget configure`, the
fallback is one imperative line in bootstrap.ps1 beside the winget call. Still
one command for the user, and the distro stays named in a versioned file either
way. Task 2 must confirm the exact module/resource spelling with
`winget configure validate` before trusting it.

Also verified for Task 2, all OK: Microsoft.WindowsTerminal,
DEVCOM.JetBrainsMonoNerdFont, Microsoft.VisualStudioCode, Microsoft.PowerToys.

Consequence for Task 2's "host layer stays thin" check: it now guards three
named groups, not one flat set --
  substrate:   Microsoft.WSL          (+ Ubuntu 26.04 via the Script resource)
  environment: Microsoft.WindowsTerminal, DEVCOM.JetBrainsMonoNerdFont,
               Microsoft.VisualStudioCode, Microsoft.PowerToys
  authoring:   koalaman.shellcheck, mvdan.shfmt, tamasfe.taplo   (see R8)
The check must also assert the Script resource is present, or Ubuntu could
vanish from the manifest without any check noticing.

Ruling R13: windows/terminal/settings.json sets `startingDirectory` in
`profiles.defaults` to the WSL home, and overrides it back to `%USERPROFILE%` on
the Windows PowerShell profile.

Why: Microsoft's reference gives `startingDirectory` a default of
`"%USERPROFILE%"`. Unset, a WSL tab therefore opens in C:\Users\camilo.piedrahita
-- /mnt/c from inside Ubuntu, the path the spec measured at 9-20x worse and
declared must never be a working path. Unset does not make that an occasional
mistake; it makes it the default in every new tab, which is worse than a mistake
because nothing ever signals it.

It has to live in `defaults` rather than on the Ubuntu profile because R5 removed
the ability to name that profile: Windows Terminal generates it and derives its
GUID from the distro name, so there is no stable id to hang a per-profile setting
on. PowerShell's GUID is a fixed built-in constant and can be named safely, so
the override goes there. The file must explain the inversion or it reads as a
mistake.

The plan's value was also malformed: `//wsl$/Ubuntu-26.04/home/camilo` mixes the
two documented forms. settings.json takes `"\\wsl$\DISTRO\home\USER"`;
`//wsl.localhost/DISTRO/home/USER` is the Settings-UI form.

Cost if wrong: the terminal opens somewhere that does not exist and says so
immediately -- a loud, first-launch failure, not a silent one.

Ruling R14: Task 3 gains a check the plan does not contain -- that
`profiles.defaults.startingDirectory` exists, points at wsl$/wsl.localhost rather
than a C: path or %USERPROFILE%, and names the same distro that
windows/configuration.winget installs. Why: nothing else would notice this
setting being deleted or retargeted, and the distro name now appears in two files
that must agree. Same argument as the one-nerd-font check -- two files naming the
same thing agree because a check makes them, not because whoever edits one
remembers the other. Cost if wrong: one more check to keep green.

Also recorded for Task 3: `font.cellHeight` is NOT confirmed to exist. It did not
appear in the appearance reference. Step 2's schema grep decides it; if absent it
joins the not-ported block rather than being written on faith.

Ruling R15: pyyaml is installed with pip on the host as an explicitly
transitional dependency of the authoring phase, and declared permanently as
`python3-yaml` in wsl/apt-packages.txt (Task 5) -- which is where check.sh
actually runs from Task 10 onward. It is NOT added to configuration.winget.

Why not the manifest: that file declares the machine's steady state. A
transitional authoring dependency written there would outlive its reason and be
believed by whoever reads it next -- and declaring pyyaml without declaring the
Python it belongs to would be incoherent besides. The host's Python
(pythoncore 3.14, pre-existing and undeclared) is known drift like Git for
Windows, not something this repo adopts.

Why install it at all rather than skip: under --strict a skip is a failure, and
the pre-commit hook runs --strict. A skipped YAML check would refuse every commit
for the rest of the authoring phase -- the same trap R8 fixed for
shellcheck/shfmt/taplo. Verified: pip 26.0.1 is present and python3 is a real
pythoncore 3.14 install, not the Microsoft Store alias.

Cost if wrong: the host carries one undeclared pip package for the duration of
the authoring phase. Bounded, recorded here, and gone once the repo lives in WSL.

Ruling R16: check() is amended to return the wrapped command's status. No current
call site needs it. The reason is that a helper which always returns 0 while
looking like a predicate is a footgun -- impl-task2 walked into it and it cost a
round trip. With the fix, `check X cmd || skip ...` prints FAIL then SKIP, which
is visibly wrong; without it the skip silently never runs. Loud beats silent.
Cost if wrong: a function whose last statement is a failing check now returns
nonzero; no such call site exists, and check.sh does not use set -e.

Ruling R17: all ten tool version pins in Task 5 are replaced with versions read
from each project's GitHub releases on 2026-08-18, and the verification moves
from Task 10 to Task 5 itself.

Why: I wrote those ten numbers from memory when drafting the plan and not one of
them is correct. `eza = "0.24.7"` is the one that actually breaks -- the newest
eza release is 0.23.5 and the tag v0.24.7 returns 404. It was never published.
`mise install` would have failed during Task 10, which is a step the USER runs on
their own machine after the host layer is already applied.

R2 deferred this verification to Task 10 on the reasoning that it needed mise.
That reasoning was wrong: it needed the upstream release list, which
`gh api repos/<owner>/<repo>/releases/latest` returns from anywhere. The
deferral, not the pin, is what let a nonexistent version survive into a plan
that had already been reviewed and approved. R2 stands for the fsmonitor
measurement, which genuinely needs a migrated repository; it is withdrawn for
the version pins.

Verified 2026-08-18: starship 1.26.0, eza 0.23.5, bat 0.26.1, fd 10.4.2,
ripgrep 15.2.0, fzf 0.74.3, zoxide 0.10.0, jq 1.8.2, delta 0.19.2, uv 0.12.5.

Cost if wrong: a pin is a few patch versions behind on the day it lands. The
alternative -- what the plan actually had -- was an install that fails on the
user's machine naming a version that does not exist.

Consequence for Task 14: bump-tools.sh must cover these ten pins as well as the
CI tool pins. Ten hand-maintained exact pins is ten chances a year to repeat
exactly the mistake this ruling is fixing.

Ruling R18: pin `version` on the three authoring tools and the font. Do NOT pin
Windows Terminal, VS Code, PowerToys or WSL. Rewrite the header to state both the
five groups and this policy with its reasoning.

Verified `version` is a real setting by reading the resource definition, not the
docs: Microsoft.WinGet.DSC.psm1:467-477 declares Id (Key, Mandatory), Source
(Key), Version, Ensure.

Why pin the authoring tools: their whole justification is that host and CI reach
the same verdict on the same file. Unpinned, the sentence in their own
description is false the next time winget's package moves. Versions confirmed
from winget and all three match the CI pins exactly -- shellcheck 0.11.0,
shfmt 3.13.1, taplo 0.10.0.

Why pin the font (3.3.0): it does not self-update, and it is what renders the
terminal. A font version change moves glyph metrics -- something this repo
already cares enough about to give a dedicated coherence check.

Why NOT pin the four applications: Windows Terminal, VS Code, PowerToys and WSL
all update themselves out of band, through the Store and their own in-app
updaters. A `version` there would describe a state the machine contradicts within
days, so the manifest would document a fiction. And if the pin were honoured it
would hold back security updates on the two largest attack surfaces here -- a
browser-grade editor and a terminal. Current versions recorded for reference
only: Terminal 1.24.11911.0, VS Code 1.132.0, PowerToys 0.100.2, WSL 2.7.11.

Cost if wrong: two machines built from this manifest get different versions of
four self-updating apps -- which would have converged to the same current version
within a day anyway.

Ruling R19: wsl/zsh/.zshrc must change antidote's source path. The Mac file
hardcodes `/opt/homebrew/opt/antidote/share/antidote/antidote.zsh` at line 52,
and Task 6's brief lists six changes to make when copying -- none of which
touches it. Missed by my pre-flight scan, which marked the 6->9 pair clean.

What it costs: the shell still starts, but with zero plugins. No fzf-tab, no
autosuggestions, no syntax highlighting, no history-substring-search, plus error
lines at every startup. Half-broken and irritating to diagnose, because the
shell works well enough that nothing points at the cause.

Task 9 clones antidote to $XDG_DATA_HOME/antidote, and `antidote.zsh` sits at
that repo's root (verified: 80,676 bytes). So the line becomes
`source "${XDG_DATA_HOME:-$HOME/.local/share}/antidote/antidote.zsh"`.
Tasks 6 and 9 must agree on that path, and nothing currently makes them.

Ruling R20: `gh` is declared in wsl/mise/config.toml at 2.97.0. It is used in
four places across Tasks 7, 11 and 14 and declared in no manifest at all.
install.sh would finish clean and then Task 11 fails with `gh: command not
found`, while git's credential helper points at a binary that does not exist --
so every push fails with an opaque credential error naming neither cause.
From mise not apt: apt's gh trails upstream, and this is the one tool whose auth
flow moves with the service it talks to. Verified: cli/cli latest is v2.97.0.

Audit of every file Tasks 6-8 copy from dotfiles, for macOS-specific paths:
  zsh/.zshrc            3 hits -- 2 covered by the plan, 1 is R19
  zsh/.zsh_plugins.txt  2 hits -- both covered by the plan
  git/config            2 hits -- both covered by the plan
  starship.toml         CLEAN
  claude/statusline.sh, subagent-statusline.sh, statusline-demo.sh   CLEAN
  claude/CLAUDE.md      CLEAN
That confirms two things I asserted in the spec without checking: starship.toml
transfers with nothing changed, and the statusline scripts are portable.

Ruling R21: wsl/install.sh must add mise's shim directory to PATH immediately
after `mise install` / `mise reshim`, before the uv step.

Why: the script as planned adds only `$HOME/.local/bin` -- where mise's own
binary lands -- and never `~/.local/share/mise/shims`, where everything mise
MANAGES lands. Step 8 calls `uv tool install`, and uv is one of the tools mise
just installed. Traced: `uv tool list` fails with stderr suppressed, grep matches
nothing, the else branch runs `uv tool install`, uv is not found, and
`set -euo pipefail` aborts -- after every config file has been linked and before
any Python CLI is installed. The machine is left half configured and the error
names uv rather than the missing PATH entry.

This is the file the user runs on their own machine, so a reviewer would not have
caught it; the user would have, halfway through.

Verified rather than reasoned: mise's default shim directory is
~/.local/share/mise/shims, and `https://mise.run` returns 200.

Cost if wrong: one redundant PATH entry in a script that already sets PATH.

Also verified for Task 9, so nobody "hardens" a non-bug later: the AND-list
idiom `[ -e f ] && [ ! -L f ] && { ... }` does NOT abort under `set -euo
pipefail`. Tested directly -- the script continues. set -e ignores the failure of
any command in an AND-OR list other than the last. The addendum tells the
implementer to comment it as checked, because it reads like a bug and someone
will eventually "fix" it into an if-block.

And: step ordering confirmed correct -- the mise config is linked in step 4
before `mise install` runs in step 7, so mise reads the pinned versions rather
than installing nothing at all.

Ruling R22: check.sh exports PYTHONUTF8=1, every Python open() it contains also
passes encoding='utf-8', and a new check asserts sys.flags.utf8_mode rather than
grepping for the export line. Task 2's two existing call sites are retrofitted.

Why: impl-task3 found that `json.load(open('schemas/windows-terminal.json'))`
raises UnicodeDecodeError at byte 0x81, position 6105, because
locale.getpreferredencoding() is cp1252 on this host. I reproduced it, and
established the bug is narrower and nastier than "non-ASCII breaks it":

  - bytes undefined in cp1252 (0x81, 0x8d, 0x8f, 0x90, 0x9d) raise -- the crash
  - every OTHER non-ASCII byte decodes silently into different characters.
    Tested with an em dash: cp1252 reads its three UTF-8 bytes as three garbage
    characters, no error, and a check comparing those reaches a confident wrong
    answer.

The silent case is the worse one and per-call encoding= only covers call sites
someone remembers. PEP 540 UTF-8 mode covers the ones not yet written, which is
the failure mode that actually recurs. Both are applied: the env var is the
guarantee, the explicit encoding is what survives a snippet run outside
check.sh.

The check asserts the property (sys.flags.utf8_mode) rather than the presence of
the export line. A check that greps for a line passes when the line is written
wrongly.

This is the same species as Task 2's WSL_UTF8 issue: a tool whose text encoding
depends on which platform is running it, silently, unless pinned. Third
encoding-shaped defect in this repo. Worth watching for a fourth.

Cost if wrong: one env var and a redundant argument in a script that already
sets both.

Ruling R23: jsonschema approved on the pyyaml precedent -- pip on the host,
transitional, absent from configuration.winget, declared as python3-jsonschema in
Task 5's apt manifest (added to that addendum as C7).

Ruling R24: both Task 3 minors are routed to Task 15 (README) rather than a fix
round. Why: neither is a defect in what shipped -- both are missing *statements
of reasoning*, which is exactly what Task 15 exists to write, and the README is
where this repo already puts reasoning that cannot live in a strict-format file.
Opening a fix round to add two comments would cost a dispatch and a re-review to
land text that Task 15 has to write anyway. Cost if wrong: two explanations land
one task later than they could have.

Ruling R25: from now until Task 10, commits are made with --no-verify, and every
such commit message must state that the sole failure was `zsh syntax (zsh not
installed)`.

Why: the hook runs --strict, zsh does not exist on this Windows host, and there
is no zsh worth installing here -- Git for Windows ships no package manager and
winget has no usable zsh. Ubuntu has one declared in apt-packages.txt but nothing
is installed inside it until Task 10, and check.sh runs in Git Bash regardless.

This is the R8 trap again -- a gate defeated by attrition -- resolved differently
because the tool cannot be obtained. The mitigation is that the bypass must be
declared each time, so it stays auditable rather than becoming habitual, and the
window is bounded: Tasks 7, 8, 9 plus my own commits, after which the repo lives
in Ubuntu where zsh exists.

Cost if wrong: for three tasks, a real failure could hide behind a bypass that
was justified for a different reason. Mitigated by requiring the commit message
to name the single expected failure, so a second one is visible in review.

Ruling R26: both are fixed despite being Minor, because they are the class I
already ruled substantive in Task 2 -- a comment that states something false gets
corrected rather than left. I spent three rounds enforcing that there; applying a
looser standard here only because these are smaller would make the earlier rounds
arbitrary. Asked for the .zprofile mention to be rewritten as a named, deleted
mechanism rather than deleted outright, for the same reason the manifest names
its own disproven claim: someone arriving with the Mac's mental model should find
out why it does not apply, not find silence. Cost if wrong: one small round on
comments.

Ruling R27: jq 1.8.2 installed on the Windows host via winget, same precedent as
R8 (shellcheck/shfmt/taplo) and R15 (pyyaml) -- transitional authoring
dependency, NOT declared in configuration.winget, already declared permanently in
wsl/mise/config.toml.

Why: Task 8 ports the three statusline scripts and four checks that exercise
them -- demo renders, minimal payload still renders the model, invalid json
produces no output, subagent rows are valid jsonl. All four shell out to jq,
which was absent from both Git Bash and Ubuntu. Without it those four ship
unexercised, in the one task whose entire subject is the statusline.

winget serves jq 1.8.2, exactly what wsl/mise/config.toml pins. Host and declared
environment run the same binary, which is the same property that made R8 the
right call.

Also verified for Task 8: bash is 5.3.9 on BOTH Git Bash and Ubuntu 26.04. The
statusline scripts were written against macOS's bash 3.2, and the header's
reasoning about avoiding $(command) forks is weaker there but not wrong. No
version gap to worry about.

Ruling R28: Tasks 13, 14 and 15 are executed BEFORE handing the user Tasks 10-12,
reversing the plan's ordering.

Why: all three produce files and none needs a built machine to be written.
drift.sh compares against a real environment but writing it does not require one;
CI runs on GitHub's runners, not here; the README documents decisions already
made. The plan sequenced them last because drift.sh is only USEFUL after Task 10,
which conflated writing with exercising.

What it buys: the user receives a complete repository plus three runbooks in one
handoff, rather than being interrupted to run Tasks 10-12 and then waiting again.
And Task 12 ends this session -- so anything not done before it either happens in
a fresh session with no context, or is read out of the ledger by an agent that
was not here. Better to have three fewer tasks in that position.

Deferred verifications remain deferred and are already carried in the runbooks:
drift.sh's first real run is Task 10, and the fsmonitor measurement is Task 11
Step 8. Both are written as instructions the user executes, not as items the
implementer can fake.

Cost if wrong: drift.sh and CI are written against a machine state that has not
been observed. Both are checked by their own review, and both are cheap to
correct once the user's first run reports what actually happens.

Task 8 re-review: everything ADDRESSED. gcloud, the four new categories, the
widening (verified 18 generated against 18 in the file, 1:1 both directions), and
all 13 open() calls carrying encoding. No new breakage.

TWO findings, queued for a fix round once impl-task9 finishes -- both touch
check.sh and two implementers must not run at once.

G-A (Important): the widened check has a hole in its own construction.
`str.format()` silently ignores an argument when the template has no `{}`
placeholder -- it does not raise. So a tenth template added without one produces
two IDENTICAL need entries: the loop still appends twice, len(need) still grows
by two, nothing errors, and the check degrades to verifying one string twice
while believing it verified a literal and a glob. Not live today -- all nine
templates are well formed -- but it is the same species as the no_mnt_c
leading-slash bug: a check that passes while inspecting less than it claims. Fix
with an explicit guard in the loop that fails loudly on a template missing `{}`.

G-B (accepted, and it corrects me): add `.azure`, literal + globbed.

I had left it out on the stated bar "evidence, not plausibility -- no Linux
precedent and absent from this host". The reviewer points out I did not apply
that bar evenly: `.git-credentials` went in on category reasoning alone, with no
on-disk evidence and only an adjacent `~/.netrc` as precedent. Either that one
should not be there or .azure should. The asymmetry-of-cost argument that
justified gcloud applies identically: two lines now, against nobody ever
revisiting this list if `az login` is run on the Windows side later.

Recorded because it is a case of a reviewer catching the CONTROLLER applying a
rule inconsistently, which is harder to see than catching a defect in the work.
The bar itself was fine; my application of it was not.

Ruling R29: every commit's author and committer email rewritten from the
owner's personal address to their GitHub noreply form,
and the repo's local git config set to the same so future commits inherit it.
User approved ("do the most recommended world-class thing").

Why, and it was my error: I chose that email for every `-c user.email` in this
session without checking what the user actually uses. Their own public repo,
camilopiedra92/dotfiles, commits as
142334282+camilopiedra92@users.noreply.github.com -- the GitHub noreply form. So
they deliberately keep the real address off public repositories, and I had been
putting it into all 32 commits of a repo the plan says to create with
`gh repo create --public`.

Caught only because impl-task9 flagged that the plan document also carries the
identity, which made me look at where else it appears. The file-level leak the
reviewer found (Critical A) was real but secondary: commit metadata is visible on
every public repo regardless of file contents, so fixing install.sh alone would
have left the address exposed 32 times over.

Done safely: nothing was pushed, so this rewrote local history only. Verified
`git diff refs/original/... workstation-setup --stat` is empty -- the trees are
identical and only metadata moved. Originals remain at refs/original/, which git
does not push. Confirmed the only pushable refs are refs/heads/main and
refs/heads/workstation-setup and that both carry the noreply address exclusively.

Cost if wrong: the SHAs changed, so any note referring to a pre-rewrite commit id
is stale. Nothing external references them -- no remote exists yet.

Also corrected in this round: impl-task9 TESTED a claim I wrote into the fix
message -- that "git will refuse to commit until these are real values" -- with a
fresh git init and the placeholder strings, found git accepts any string, and
rewrote the comment to describe what actually guards a forgotten placeholder (the
reserved .invalid TLD). My assertion, their measurement. That is the standard
this repo asks for, applied to me.

Ruling R30: drift.sh's two legitimate /mnt/c references are handled by excluding
the PATH, not the FILE. `no_mnt_c` gains `grep -vE 'mnt/c/Windows/System32/'`.

The tension is real: drift.sh must reach winget.exe, install.sh removes the
Windows PATH from WSL on purpose, so the crossing goes through cmd.exe at its
absolute System32 path. Both hits are genuine code, not prose.

The implementer proposed a ':!drift.sh' exclusion, which is the third time that
shape has been proposed this session -- Task 6 for wsl/zsh/.zshenv, Task 8 for
CLAUDE.md, now this. Refused for the third time, and the reason sharpens each
time: drift.sh is the file MOST likely to grow a second, illegitimate /mnt/c
reference, because it is the only file that reaches across at all. Excluding it
wholesale blinds the check exactly where it is most needed.

The discriminator: /mnt/c/Windows/System32 is Windows' own system directory and
nobody's work will ever live there. Reaching a system binary by absolute path is
categorically different from treating /mnt/c as a working path. Scoped that way,
a later /mnt/c/Users/... in drift.sh still fires.

Same shape as the .md fix and the whitespace-before-= fix. Three times now the
answer has been to find what actually distinguishes the two cases rather than to
carve out the file that happens to contain one.

Two bugs the implementer found in its OWN testing, both worth recording:
  - a python heredoc that ate its own stdin, so every parse silently returned
    nothing. That is the same family as no_mnt_c and the manifest that installed
    nothing: passing while inspecting nothing. Found by testing the parser
    against real files rather than trusting it worked.
  - CRLF contamination from Windows-native python3 making identical strings
    compare unequal under `comm`. Seventh encoding-shaped hazard, first of that
    exact shape.
And it hit core.fileMode=false meaning `git add` does not pick up the executable
bit on Windows -- caught by the exec-bits check that shipped two tasks ago, which
is the check doing exactly what it was ported for.

Ruling R31: the .ps1 parse check leaves check.sh rather than PowerShell Core
entering the WSL manifest.

The implementer framed two options -- install the runtime, or exempt the check.
Neither. check.sh's contract is that its verdict means the same thing wherever it
runs, which is why --strict turns a skip into a failure. A check that
structurally cannot run on the target machine breaks that contract however it is
guarded; guarding it only makes the breakage quiet. The repo already states the
mirror for drift.sh -- out of CI goes what CI cannot answer honestly -- and the
inverse holds: out of check.sh goes what check.sh cannot answer everywhere.

Coverage moves rather than disappearing: the windows CI job already runs
PSScriptAnalyzer, which cannot analyse what it cannot parse. Cost, stated: a .ps1
syntax error is no longer caught on the authoring host before push. On a Windows
layer of two files that is worth check.sh's contract staying intact.

And it resolves the class-check's own cost. The implementer correctly identified
that its exclude-list -- for tools deliberately host-only -- was the real
maintenance burden. Those two entries were pwsh and powershell. With the check
gone, the list is empty, and every remaining have-guarded tool genuinely must be
declared for WSL.

Class-level check APPROVED on the implementer's specification: derive the tool
list from check.sh's own source rather than a second hand-maintained list, since
a parallel list is precisely the shape that went stale twice today. Build the
exclusion mechanism anyway, empty, with its purpose stated -- otherwise the first
genuinely host-only tool gets an ad-hoc workaround.
## After the build -- decisions taken while applying the repo to the machine

These were not made during the build. They were made in Tasks 10 and 11, against
a real Ubuntu, where the first thing a manifest meets is a machine that disagrees.
Every one of them corrects something the build got wrong and could not have
known -- which is the argument for running the machine phase against a written
plan rather than improvising it, and for writing down what the plan got wrong.

Ruling R32: check.sh and drift.sh resolve their Python interpreter by capability
-- the first `python3` that can import yaml -- rather than by the bare name.

Why: on the first `./check.sh --strict` ever run inside Ubuntu, five checks
reported `python3/pyyaml not installed` on a machine where every dependency was
present and correctly declared. `wsl/apt-packages.txt` had python3-yaml and
python3-jsonschema, dpkg confirmed both `ii`, and `/usr/bin/python3` imported
them. But mise puts its own python3 shim ahead of /usr/bin on PATH, so the bare
name resolved to mise's interpreter -- the one Python on the machine without
either library.

R15 and R23 approved those apt packages after confirming they "do not collide"
with mise's python. They do coexist. The failure mode runs the other way: the
shim shadows the interpreter the libraries were installed for. What was verified
was not what mattered, which is the same shape as every other defect this repo
found in its own checks -- the configuration was right and the check was wrong
about it.

Rejected -- hardcode /usr/bin/python3: correct in WSL and broken in CI, where
pyyaml arrives by pip onto setup-python's interpreter and /usr/bin/python3 is a
different one. A fix that trades a WSL failure for a CI failure is not a fix.

Rejected -- install pyyaml and jsonschema into mise's python: a fourth install
path, duplicating libraries apt already provides, and a second copy of each to
keep pinned. The machine does not need two of them; the script needs to find the
one that exists.

Cost if wrong: the resolver decides on yaml alone. A machine where yaml and
jsonschema lived on *different* interpreters would run the schema check against
the one without jsonschema and skip it, reporting a cause that is true as
written but points at the wrong interpreter. Both libraries arrive from one
manager in both environments -- apt in WSL, pip in CI -- so that machine does
not exist today, and the check still degrades to a skip rather than a false
pass.

Ruling R33: core.fsmonitor stays out of wsl/git/config. This closes the item R2
deferred from Task 7.

The measurement was taken as specified, on the migrated surge-pods: twenty
`git status` runs took 0.09 s with fsmonitor off and 0.09 s with it on -- 4.5 ms
each, on a 308-commit repository. But the number is not what decides it. `git
fsmonitor--daemon status` answers `fatal: fsmonitor--daemon not supported on this
platform`: Ubuntu's git 2.53 is not built with the daemon at all.

That makes the setting inert rather than slow, which is the worse of the two
failures. A config line that reads as an active optimisation and does nothing is
a claim the next reader has no reason to doubt and no way to test -- the exact
shape the Mac repo's entry does not have, because on FSEvents it genuinely works.

Cost if wrong: on a future Ubuntu whose git ships the daemon, this machine leaves
a real optimisation unused. That is cheap to reverse and the condition is one
command, so Step 8 of the runbook now names it: re-open only if
`git fsmonitor--daemon status` ever answers differently.

Ruling R34: the migration moves each repository by what it actually has, and the
inventory that decides this reports UNKNOWN rather than zero.

Task 11 as written sorted the seven directories into two categories fixed in
advance -- four git repos to re-clone, three non-repos to copy -- and its Step 1
printed an `unpushed=` column per repository. Run against the real machine, both
were wrong in the same direction.

Three of the four "git repos to re-clone" have no remote at all: aipm, glow and
vr, 175 commits between them, existing on one disk. `git clone "$(git remote
get-url origin)"` would have run `git clone ""`. And surge-pods, which does have
a remote, had two branches that the remote has never seen -- twelve commits --
so a clean re-clone of it would have dropped them silently.

The inventory did not merely fail to warn about any of this. It printed
`unpushed=0` for all three remote-less repositories, because `git log @{u}..`
fails when there is no upstream, prints nothing, and `wc -l` counts zero lines.
The most reassuring value in the column was the one that meant "this command
could not run". It also asked only the checked-out branch, which is why
surge-pods -- clean and pushed on main -- reported entirely green.

So: the category is derived per repository from the inventory, not fixed in
advance, and any branch whose upstream state cannot be computed prints UNKNOWN.
node_modules is excluded from every copy: 245 MB of the 447 MB, and installed by
Windows Node, so every native binding in it is a Windows binary.

Cost if wrong: the inventory is longer and prints a line per branch rather than
per repository. On seven repositories that is fifteen lines instead of seven, and
it is the only place in this repo where a check answers a question about work
that exists nowhere else.

Ruling R35: `gh auth setup-git` is reverted, not accommodated.

`~/.config/git/config` is a symlink into this repository, so that command writes
into a tracked file -- and it writes the absolute path of the gh binary it is
running from, which under mise carries the version: `.../installs/gh/2.97.0/...`.
The committed value is the bare `!gh auth git-credential`, with a comment
directly above it explaining that an absolute path here would go stale. gh
overwrote the value and left the comment.

Verified before reverting: with the bare name restored, `gh auth git-credential
get` returns the token. The credential lives in ~/.config/gh/hosts.yml and the
helper only has to be found on PATH, which mise's shim directory already
guarantees.

Cost if wrong: if some future caller invokes git with a PATH that lacks mise's
shims, the bare name will not resolve and that push fails. The absolute path
would survive that case -- and fail the far more likely one, the first gh version
bump, which bump-tools.sh performs on purpose. The runbook now checks for this
with `git status` immediately after the command that causes it.

Ruling R36: the twenty host deny rules are written with a leading double slash,
and the check that polices them asserts that form specifically.

They shipped with one slash, as `Read(/mnt/c/Users/...)`. In a Claude Code
permission rule a single leading slash is relative to the settings file's own
directory, so those rules resolved under `~/.claude/mnt/c/...` and could never
match anything. They were inert from the day they were written until Task 12
Step 5 tested one, and Step 5 is the only step in this repo that tests a rule by
attempting to violate it.

Proven rather than reasoned. A harmless probe file was placed inside a denied
directory and read with the Read tool: it came back clean, no denial. The
identical read was refused -- "File is in a directory that is denied by your
permission settings" -- the moment the same rule was rewritten with two slashes,
with nothing else changed. A second, unrelated rule behaved the same way, and a
Linux-side rule written with `~/` had been denying correctly all along, which is
what localised the fault to the path form rather than to the permission engine.

The check is the second half of this ruling and the more important half. `check.sh`
built its expectations from templates that carried the same single slash, so it
compared a broken file against a broken expectation and reported the host as
covered on every run since the rules existed. Both were corrected together, and
the `no file assumes /mnt/c` exclusion now excuses only the double-slash form --
so a regression to the inert spelling fails a second, independent check rather
than passing quietly. That was verified by feeding both spellings through the
filter and confirming only the inert one survives.

Two things this exposed about testing a deny rule, both now in the runbook:

The tool matters. Asked to "read" a path, the agent reached for Bash, and what
refused it was the auto mode classifier -- a harness mechanism this repo does not
declare, version or control. A refusal naming the classifier proves nothing about
these rules, and reads exactly like success. The test must name the Read tool.

The target matters. A credential-shaped path can be blocked by that same
classifier before any rule is consulted, so the decisive probe is a harmless file
placed inside a denied directory. It isolates the rule from everything else that
might refuse.

Cost if wrong: none identified. The double slash is what the permission syntax
specifies for a filesystem-root path, the `~/` rules are unaffected, and both
spellings were exercised against a live installation before this was written.

This is the fourth defect in this repo to live in a check rather than in the
configuration it judges, and the first with a credential behind it. The other
three cost a red build. This one had been publishing the appearance of protection
over a Windows host's SSH keys, cloud credentials, and Claude Code's own token.
