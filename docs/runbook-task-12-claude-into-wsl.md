# Runbook — Task 12: move Claude Code into WSL

**This task ends the session that built this repo.** Claude Code currently runs
on the Windows host; after this it runs inside Ubuntu. Read the whole page before
starting any of it.

Nothing here is irreversible. The host installation is disabled, not removed,
and every step below is checked before the next one depends on it.

**Do Task 10 and Task 11 first.** This one needs node from mise, and it should
open into the repositories that Task 11 migrates — otherwise the first thing the
new session sees is an empty home directory.

---

## Why this move, in one paragraph

Running Claude Code inside WSL is what makes three things work that otherwise
break. `~/.claude` becomes a Linux path, so `statusline.sh` and
`subagent-statusline.sh` — 467 lines of bash already written and already covered
by four checks — are reused unchanged. The deny list uses POSIX paths identical
to the Mac's. And `CLAUDE.md` describes the environment the agent actually edits
in, rather than one it reaches into over a UNC path.

---

## Step 1 — Record the host installation before touching it

```bash
cp /c/Users/camilo.piedrahita/.claude/settings.json /c/Users/camilo.piedrahita/.claude/settings.json.pre-migration
ls /c/Users/camilo.piedrahita/.claude/
```

Note what is there. In particular the plugin set, the `claude-hud` marketplace,
and the `personal` marketplace pointing at a local directory — that last one
cannot transfer and is deliberately not carried over.

---

## Step 2 — Install Claude Code inside Ubuntu

```bash
wsl -d Ubuntu-26.04
node --version        # must be v26.x, and must come from mise
which node            # must contain /mise/
```

**If `node` is not from mise, stop.** Task 10 did not finish, and installing on
top of a system node is how you end up with two installations and no idea which
one is running.

```bash
curl -fsSL https://claude.ai/install.sh | bash
claude --version
```

---

## Step 3 — Apply the repo's settings

`install.sh` already did this. It links `statusline.sh`, `subagent-statusline.sh`
and `CLAUDE.md` into `~/.claude/`, and merges `settings.json` rather than linking
it -- Claude Code rewrites that file on its own (theme, `/config`), and a symlink
would be overwritten. Same reason Windows Terminal's settings cannot be linked.
This step is only a check that it landed:

```bash
python3 -c "import json; json.load(open('$HOME/.claude/settings.json')); print('valid json')"
```

---

## Step 4 — Authenticate, and check *which* method took

```bash
claude
```

At the login prompt, choose the **Claude.ai subscription**. `forceLoginMethod:
"claudeai"` should make that the only offer.

**If a Console login is offered instead, stop.** The setting did not apply, and
proceeding bills per token instead of drawing on the subscription. This machine
was set to `console` before this repo existed — that is one of the six
divergences Task 8 corrects, and it is the one with a bill attached.

---

## Step 5 — Prove the deny list actually denies

This is the step that matters most, and it cannot be checked any other way.

**It has already caught one live failure.** On 2026-08-18 every one of the twenty
host rules was inert: they were written `Read(/mnt/c/...)` with one leading
slash, which a permission rule reads as relative to the settings file's own
directory. They matched nothing, and `check.sh` reported the host as covered
throughout, because its expectations carried the same slash. See R36. The rules
now start with `//`. This step is what found that, and it is the only reason it
was ever found.

So run it as written, and read the refusals rather than counting them.

### Two ways this test lies to you

**The tool matters.** Ask an agent to "read" a path and it may reach for Bash —
and a `cat` is stopped by the auto mode classifier, not by these rules. That
refusal names the classifier, looks exactly like success, and proves nothing:
the classifier is a harness mechanism this repo does not declare, version or
control. Name the Read tool explicitly, and say not to use Bash.

**The target matters.** A path that looks like a credential can be refused by
that same classifier before any rule is consulted — sometimes before the request
even reaches the machine you are testing. So the decisive probe is a *harmless*
file inside a denied directory. It isolates the rule from everything else that
might refuse for its own reasons.

### The probe

```bash
u=/mnt/c/Users/camilo.piedrahita
[ -e "$u/.azure" ] && echo "STOP: .azure exists, pick another denied dir" || {
  mkdir -p "$u/.azure"
  echo "harmless probe" > "$u/.azure/probe.txt"
}
```

`Read(//mnt/c/Users/*/.azure/**)` covers it, in both the literal and the glob
form. Then, inside a Claude session:

```
Use the Read tool on /mnt/c/Users/camilo.piedrahita/.azure/probe.txt.
Answer only READ or DENIED plus the literal message. Do not use Bash.
```

**Expected:** `DENIED: File is in a directory that is denied by your permission
settings.`

Three outcomes and what each means:

| What comes back | What it means |
| --- | --- |
| DENIED, naming your permission settings | The rule fired. This is the pass. |
| DENIED, naming the auto mode classifier | Inconclusive. Something else refused; the rule was never consulted. |
| READ | The rule did not fire. Stop and fix it before anything else. |

### Then a second, unrelated rule

One rule firing could be one rule firing. Repeat against a different category —
a literal path rather than a glob:

```
Use the Read tool on /mnt/c/Users/camilo.piedrahita/.docker/config.json.
Answer only READ or DENIED plus the literal message. Do not use Bash.
```

### And one negative control

A test where everything is refused proves nothing either — the agent might be
refusing all of `/mnt/c` for an unrelated reason, and the deny rules could be
doing none of the work.

```
Use the Read tool on /mnt/c/Users/camilo.piedrahita/Development/workstation/README.md.
Answer only READ or DENIED plus the literal message. Do not use Bash.
```

**This one must succeed.** If it is also refused, the earlier refusals were not
the deny rules and the test told you nothing.

### Clean up

```bash
rm -rf /mnt/c/Users/camilo.piedrahita/.azure
```

### If a rule does not fire

Report it rather than working around it. A rule that does not fire is worse than
no rule: it reads as protection while providing none, and this is the only moment
anyone will ever check.

The first thing to check is the slash. The second is whether a Linux-side rule —
`Read(~/.config/git/config.local)` is a good one, the file exists and its contents
are dull — refuses correctly. If the `~/` rule fires and the `//mnt/c` one does
not, the permission engine is working and the fault is in the path. If neither
fires, the settings file is not being read at all.

Note that `install.sh` disables Windows **PATH interop**, which is a different
thing from the mount. `/mnt/c` remains fully readable. That is precisely why
these rules exist.

### What this step does not cover, and cannot

These twenty rules are `Read(...)` rules. The repo's only `Bash(...)` deny rules
guard destructive commands — `rm -rf`, force pushes, `filter-branch` — and none
of them protects a credential path. A `cat` of a host credential file is not
refused by anything in this repository.

That is not an oversight to fix by adding `Bash(cat //mnt/c/...)`: a command-string
rule is evaded by `head`, by `python -c`, by any of a hundred spellings, so such a
rule would add the appearance of coverage without the substance — the exact
failure this step exists to detect. What stops it today is the auto mode
classifier, which belongs to the harness rather than to this repo. Write that down
rather than papering over it: the deny list closes the Read path, and the Bash
path is closed by something this repo neither owns nor can promise.

---

## Step 6 — Confirm the statusline renders

```bash
claude
```

Expected: the two-line statusline from the Mac repo — identity above, gauges
below. If it renders as a raw error or an empty line, `jq` is missing or the
script is not executable; both are Task 10 problems, not Task 12 problems.

`claude-hud` is deliberately **not** installed. Two things occupying one role is
the same failure the one-Nerd-Font rule forbids.

---

## Step 7 — Reinstall plugins

`enabledPlugins` in the repo's settings lists what should be on. Anything the
host had that is not in that list was dropped on purpose.

---

## Step 8 — Retire the host installation

**Only after Steps 4, 5 and 6 all pass.** Do not uninstall — disable, and leave
it recoverable:

```bash
mv /c/Users/camilo.piedrahita/.claude/settings.json \
   /c/Users/camilo.piedrahita/.claude/settings.json.retired
```

`drift.sh` will report the host installation as installed-and-undeclared. That
is the correct verdict, not a problem to silence. Removing it is a separate
decision for a separate day.

---

## What to tell the next session

Start the new session inside Ubuntu, in `~/workstation`, and hand it this:

> This repository declares this machine. All fifteen tasks of
> `docs/superpowers/plans/2026-08-18-workstation.md` are complete and reviewed.
> Read `README.md` for how it works and `docs/decisions.md` for why — that second
> file records every decision taken on my behalf during the build and what each
> costs if it is wrong. Do not change anything that looks odd until you have read
> its entry there.

**`docs/decisions.md` is the handover**, and it is tracked, so it arrives with the
clone. That matters more than it sounds: the working record it was extracted from
lives under `.superpowers/`, which is git-ignored — so the document this page used
to point at would not have existed on the machine this page tells you to create.

It is the only place the reasoning behind the odd-looking decisions is written
down: why `startingDirectory` sits in `profiles.defaults` rather than on the
profile it configures, why Ubuntu is installed by a DSC `Script` resource instead
of a package id, and why `useLatest` must not be deleted as redundant — that last
one because the argument for leaving it out was sound, and the first real apply
disproved it.

---

## If something goes wrong mid-migration

Nothing here is one-way. The host installation is intact until Step 8, and
Step 8 is a rename. To fall back: rename `settings.json.retired` back, and
continue on Windows while the WSL side is fixed.

The one thing worth not doing is running both installations against the same
repositories at once. They will not corrupt anything, but two agents editing the
same tree with different working directories is a confusing hour.
