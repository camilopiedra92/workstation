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

`install.sh` already linked `statusline.sh`, `subagent-statusline.sh` and
`CLAUDE.md` into `~/.claude/`. The settings file is **merged, not linked** —
Claude Code rewrites it on its own (theme, `/config`), and a symlink would be
overwritten. Same reason Windows Terminal's settings cannot be linked.

```bash
mkdir -p ~/.claude
if [ -f ~/.claude/settings.json ]; then
  jq -s '.[0] * .[1]' ~/.claude/settings.json ~/workstation/wsl/claude/settings.json \
    > /tmp/merged.json && mv /tmp/merged.json ~/.claude/settings.json
else
  cp ~/workstation/wsl/claude/settings.json ~/.claude/settings.json
fi
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

The deny rules covering the Windows host's credentials exist only in this repo —
the Mac has no host to protect against. They have never been exercised. Inside a
Claude session:

```
> read ~/.ssh/id_ed25519
> read /mnt/c/Users/camilo.piedrahita/.aws/credentials
> read /mnt/c/Users/camilo.piedrahita/AppData/Roaming/gh/hosts.yml
```

**All three must be refused.**

The first is the POSIX rule the Mac also has. The second and third are the ones
this repo added, and they are the ones with no prior evidence. If either is
allowed, the `/mnt/c` rules are not matching and Task 8 needs revisiting —
report it rather than working around it.

Note that `install.sh` disables Windows **PATH interop**, which is a different
thing from the mount. `/mnt/c` remains fully readable. That is precisely why
these rules exist.

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

> We are executing `docs/superpowers/plans/2026-08-18-workstation.md` with
> subagent-driven development. Tasks 1 through 12 are complete. The ledger is at
> `.superpowers/sdd/2026-08-18-workstation/progress.md` — read it before doing
> anything, especially the Rulings section, which records every decision made on
> my behalf and what each costs if wrong. Remaining: Task 13 (`drift.sh`),
> Task 14 (CI), Task 15 (README). Addenda for all three are already written in
> that same directory and override their briefs.

The ledger is the handoff. It survives this session ending, and it is the only
place the reasoning behind the odd-looking decisions is written down — why
`startingDirectory` sits in `profiles.defaults`, why Ubuntu is installed by a
DSC `Script` resource, why `useLatest` must not be deleted as redundant.

---

## If something goes wrong mid-migration

Nothing here is one-way. The host installation is intact until Step 8, and
Step 8 is a rename. To fall back: rename `settings.json.retired` back, and
continue on Windows while the WSL side is fixed.

The one thing worth not doing is running both installations against the same
repositories at once. They will not corrupt anything, but two agents editing the
same tree with different working directories is a confusing hour.
