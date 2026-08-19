# Runbook — Tasks 10 and 11: build the environment, move the work in

**You run these.** They happen inside Ubuntu, back to back, in one sitting.
Task 10 builds the environment; Task 11 moves your repositories onto ext4.

Expect 20–40 minutes, most of it downloads. **Nothing is deleted from Windows**,
including in Task 11.

Do these only after I confirm Task 9 is complete — `wsl/install.sh` has to exist.

---

# Task 10 — build the environment

## Step 1 — Clone the repo into Ubuntu

```bash
wsl -d Ubuntu-26.04
git clone https://github.com/camilopiedra92/workstation ~/workstation
cd ~/workstation
```

If the remote does not exist yet, tell me — I create it before you get here, but
if something went wrong the fallback is to copy from
`/mnt/c/Users/camilo.piedrahita/Development/workstation` and add the remote
afterwards.

## Step 2 — Run it

```bash
~/workstation/wsl/install.sh
```

It will ask for your Ubuntu password once, for `sudo apt-get`.

**Re-running is safe.** A check asserts the second run changes nothing — if you
have to stop and restart, just run it again.

If it stops partway, send me the last twenty lines. The step that fails tells me
which manifest is wrong, and the machine is in a known partial state rather than
an unknown one.

## Step 3 — Cycle WSL so `/etc/wsl.conf` takes effect

From **PowerShell**:

```powershell
wsl --shutdown
```

Then reopen the terminal. This is not optional — `install.sh` writes
`/etc/wsl.conf` and WSL only reads it at boot.

## Step 3b — Set your git identity. Do this before you commit anything.

`install.sh` created `~/.config/git/config.local` with **placeholders**, because
this repository is public and a real name and address cannot live in it. Nothing
else will remind you.

```bash
cat ~/.config/git/config.local
```

It says `CHANGE ME` and `change@me.invalid`. Replace them with your own:

```bash
git config --file ~/.config/git/config.local user.name  "<your name>"
git config --file ~/.config/git/config.local user.email "<your address>"
```

**For the address, use your GitHub noreply form** — that is what your `dotfiles`
repo already commits with, and it keeps your real address off public
repositories. GitHub shows it under Settings → Emails, as
`<id>+<username>@users.noreply.github.com`.

This file lives outside the repo precisely so each machine can carry its own
values and the repository can stay public. That is also why this page does not
print them: a check refuses to let any identity into a tracked file, and it
refused this runbook when it did.

Then confirm git actually sees it:

```bash
git config --get user.name
git config --get user.email
```

**Both must print your values, not the placeholders.** If they print nothing,
`config.local` is not being included — check that `~/.config/git/config` exists
and is a symlink into the repo.

**Why this step is here rather than left to the message `install.sh` prints:**
git accepts any string as an identity. It will not refuse a commit authored by
`CHANGE ME <change@me.invalid>` — that was measured, not assumed. So a forgotten
placeholder is not caught at commit time; it is caught weeks later, in a log,
and the only fix is rewriting history.

---

## Step 4 — Confirm interop is actually narrowed

```bash
echo "$PATH" | tr ':' '\n' | grep -c '/mnt/c'
```

**Expected: `0`.**

A non-zero count means `/etc/wsl.conf` did not apply and the hazard is still
live. This is not about speed. Every file under `/mnt/c` is executable as far as
Linux is concerned, and mise's *Windows* shims live there — so a shimmed tool
found on that PATH would run a Windows script inside Linux.

## Step 5 — Confirm each layer arrived

```bash
echo "shell:   $SHELL"          # expect zsh
echo "zdotdir: $ZDOTDIR"        # expect ~/.config/zsh
node --version                  # expect v26.x
python --version                # expect 3.14.x
pnpm --version                  # expect 11.x
starship --version
which node | grep -q mise && echo "node comes from mise" || echo "WRONG: not from mise"
git config --get init.defaultBranch   # expect main
git config --get pull.rebase          # expect true
```

The `which node` line matters most. If node does not come from mise, the PATH
ordering in `.zshenv` is wrong and every project will silently use the wrong
runtime.

## Step 6 — Confirm the pins are honoured

A pin the machine ignores is a pin doing nothing:

```bash
cd ~/workstation
for t in starship eza bat fd ripgrep fzf zoxide jq delta uv gh; do
  want=$(grep -E "^$t = " wsl/mise/config.toml | sed 's/.*"\(.*\)".*/\1/')
  got=$(mise current "$t" 2>/dev/null)
  printf '%-10s want %-10s got %-10s %s\n' "$t" "$want" "$got" \
    "$([ "$want" = "$got" ] && echo OK || echo MISMATCH)"
done
```

Any `MISMATCH` — send it to me before continuing.

## Step 7 — Run the full check suite in its real home

```bash
cd ~/workstation && ./check.sh --strict
```

**This is the first run where nothing should skip.** Every tool now exists,
including zsh — which has been the one expected failure on Windows for three
tasks. If anything still reports `FAIL (not installed)`, it names a tool the
manifests forgot; send it to me.

**Two checks run here for the first time anywhere**, so read a failure from
either as "this ran for the first time", not as "the environment is broken":

- `install.sh --links-only is idempotent` — skipped on Windows because that
  filesystem has no symlinks. This machine does, so it finally executes.
- `zsh syntax` — skipped everywhere until zsh existed.

If either fails, send me the output rather than working around it. A first
execution failing is information; it is the reason the check was written.

Note that `githooks/pre-commit` runs `check.sh --strict` on **every** commit
here, so a failure in either of those blocks committing until it is fixed. That
is the gate working as designed, but it is worth knowing before it surprises you
mid-commit.

## Step 8 — Look at the prompt

Open a new tab. You should see the starship prompt: two lines, directory and git
branch above, `❯` below. Runtime versions appear only inside a project that uses
them.

Type `ls`. Icons, not empty boxes.

---

# Task 11 — move the work onto ext4

Remember what this is buying. Creating 2000 files: 0.065s on ext4 against 7.554s
on `/mnt/c`. And measured afterwards on a real repository, `git status`: 4.5 ms
on ext4 against 9.1 s on `/mnt/c` — though that second pair is not like for like,
because the Windows copy still had its `node_modules` and the ext4 clone did not.

**This task was run once, on 2026-08-18, and the steps below are what it turned
into — not what it started as.** Three of them were wrong in ways that would have
lost work. Each carries the correction and why, because the same mistakes are
available to anyone rebuilding this machine.

## Step 1 — Inventory what is on the Windows side, with its state

Nothing moves before this list exists and every entry is accounted for.

```bash
# Spelled out, not $USER: the WSL account is `camilo` and the Windows profile
# is `camilo.piedrahita`. With $USER the glob matches nothing and the inventory
# comes back empty -- which reads as "nothing to migrate" rather than as an error.
base=/mnt/c/Users/camilo.piedrahita/Development
for d in "$base"/*/; do
  name=$(basename "$d")
  if [ ! -d "$d/.git" ]; then
    printf '%-24s NOT A GIT REPO -- must be copied, not re-cloned\n' "$name"
    continue
  fi
  remote=$(git -C "$d" remote get-url origin 2> /dev/null) || remote=""
  printf '%-24s dirty=%-5s remote=%s\n' \
    "$name" "$(git -C "$d" status --porcelain | wc -l)" "${remote:-NONE}"
  git -C "$d" for-each-ref --format='%(refname:short) %(upstream:short)' refs/heads |
    while read -r branch up; do
      if [ -z "$up" ]; then
        printf '    %-28s NO UPSTREAM -- unpushed state UNKNOWN\n' "$branch"
      else
        printf '    %-28s %s commits not in %s\n' \
          "$branch" "$(git -C "$d" rev-list --count "$up..$branch")" "$up"
      fi
    done
done
```

**Why this replaced the original.** The first version of this step ran
`git log --oneline @{u}.. | wc -l` on each repository and printed the result as
`unpushed=`. For a branch with no upstream that command fails, prints nothing,
and `wc -l` counts zero lines — so the column read `unpushed=0` for three
repositories that had no remote at all. The reassuring number meant "could not
answer", and nothing on the line said so.

It also looked only at the checked-out branch. A repository whose `main` was
clean and pushed reported entirely green while two other branches held twelve
commits that existed on one disk. The version above asks every branch, and says
UNKNOWN where it cannot answer instead of guessing zero.

## Step 2 — Resolve everything the inventory could not vouch for

**Before anything is re-cloned:** every branch showing commits not in its
upstream, every branch marked UNKNOWN, and every repository whose remote is NONE.
A re-clone silently discards all three.

Push what should be pushed. What should not be pushed is fine to keep local —
but then that repository is copied, not re-cloned, and Step 4 decides that by
what the inventory said rather than by category.

## Step 3 — Authenticate git inside Ubuntu

```bash
gh auth login
gh auth setup-git
git -C ~/workstation status --porcelain
```

This is a separate authentication from the one on Windows. That is deliberate —
`git/config` points its credential helper at `gh`, so if this step is skipped
every push fails with an opaque credential error that names neither cause.

**The third line is not optional, and this is why.** `~/.config/git/config` is a
symlink into this repository, so `gh auth setup-git` writes into a tracked file —
and what it writes is the absolute path of the `gh` binary it happens to be
running from:

```
helper = !/home/you/.local/share/mise/installs/gh/2.97.0/.../gh auth git-credential
```

That path carries gh's version inside it. The first `bump-tools.sh` run that
moves gh deletes it, and every push afterwards fails with exactly the credential
error this step exists to prevent. The committed value is
`!gh auth git-credential` — the bare name, resolved through mise's shim
directory, which is already first on PATH. The comment above it in
`wsl/git/config` says precisely this, and `gh` overwrote it anyway.

So if that `status` prints `M wsl/git/config`, revert it and confirm the bare
name still authenticates:

```bash
git -C ~/workstation checkout -- wsl/git/config
printf 'protocol=https\nhost=github.com\n\n' | gh auth git-credential get
```

The token lives in `~/.config/gh/hosts.yml`, not in the path, so the bare name
resolves and returns the same token.

## Step 4 — Move each repository by what the inventory said

Two kinds, decided per repository rather than per category:

**Has a remote, and every branch is in it → re-clone.** Nothing is reconstructed
from the Windows copy, and the working tree arrives with LF endings.

```bash
mkdir -p ~/Development && cd ~/Development
git clone "$(git -C "$base/<repo>" remote get-url origin)" "<repo>"
```

**No remote, or any branch that lives nowhere else → copy, including `.git`.**
The original version of this step re-cloned four repositories from
`git remote get-url origin`; three of them had no remote, so it would have run
`git clone ""`. Their history exists in exactly one place, and only a copy of
`.git` preserves it.

```bash
tar -C "$base" --exclude=node_modules -cf - "<repo>" | tar -C ~/Development -xf -
```

**`--exclude=node_modules` matters twice.** It is the bulk of the bytes — 245 MB
of 447 MB here — and copying it over 9p is the slowest thing in this runbook. It
is also worthless: those trees were installed by Windows Node, so any native
binding inside them is a Windows binary. Reinstall with `pnpm install` instead.

If a re-cloned repository turns out to be missing a branch that only the Windows
copy has, fetch it straight from that copy — no remote and no network involved:

```bash
git -C ~/Development/<repo> fetch "$base/<repo>" 'refs/heads/<branch>:refs/heads/<branch>'
```

## Step 5 — Copy the directories that are not git repos

```bash
for d in <the ones the inventory marked NOT A GIT REPO>; do
  tar -C "$base" --exclude=node_modules -cf - "$d" | tar -C ~/Development -xf -
done
```

## Step 6 — Bring the local files a clone cannot

`.remember/`, `.env` files and parts of `.claude/` are local state no clone
reproduces. Copies made with `tar` already carry them; only re-cloned
repositories need this.

**Do not copy those directories wholesale, and this is the correction that
matters.** An earlier version of this step called `.claude/` and `.mcp.json`
untracked by design. In `surge-pods` they are not: 430 files under `.claude/`
are versioned, and so is `.mcp.json`. Copying the directory over a fresh clone
rewinds every one of them to whatever the Windows checkout held — here 72
commits and eight days stale, 77 of those files differing — and drags CRLF in
with them, because Git for Windows checked them out that way: 142 of the 401
versioned `.claude/` files on the Windows side have CRLF endings.

Step 7 cannot see any of that. `cp` does not move `HEAD`, so the verification
there reports MATCH — accurately, about the one thing a copy could not have
broken — while the working tree has just gone backwards. Only `git status` sees
it, which is why it is part of this step now.

So decide file by file, and ask the *destination*: the fresh clone is the
authority on what is versioned today, and the Windows copy's answer is 72
commits old.

```bash
for r in <the re-cloned ones>; do
  src="$base/$r"; dst=~/Development/$r
  for extra in .remember .claude .mcp.json .env .env.local; do
    [ -e "$src/$extra" ] || continue
    while IFS= read -r -d '' f; do
      # The clone already has the tracked copy, at the right commit and with LF
      # endings. Per file rather than per directory, because `.claude/` is
      # versioned and local-only at once -- skipping it whole would lose
      # settings.local.json and the caches under it.
      git -C "$dst" ls-files --error-unmatch "$f" > /dev/null 2>&1 && continue
      mkdir -p "$dst/$(dirname "$f")"
      cp "$src/$f" "$dst/$f" && echo "$r: brought $f"
    done < <(cd "$src" && find "$extra" -type f -print0)
  done
done
```

On `surge-pods` that skips 398 versioned files and still brings 65 local ones.

Then confirm nothing versioned moved:

```bash
for r in <the re-cloned ones>; do
  printf '%-16s %s tracked files modified\n' "$r" \
    "$(git -C ~/Development/$r status --porcelain --untracked-files=no | wc -l)"
done
```

**Every count must be zero.** A non-zero one means a tracked file was
overwritten anyway, and `git -C ~/Development/<repo> checkout -- .` puts it back.

What does get copied keeps the line endings it had on `/mnt/c` — 30 of those 65
on `surge-pods` are CRLF. Git ignores all of them, so `git status` stays quiet;
a parser will not, and a trailing `\r` on the last value of a `.env` is the
usual way that surfaces.

## Step 7 — Verify before anything is deleted

For every repository, compare the new HEAD against its Windows twin:

```bash
for r in <every git repo>; do
  w=$(git -C "$base/$r" rev-parse --short HEAD)
  l=$(git -C ~/Development/$r rev-parse --short HEAD)
  printf '%-16s windows=%s ext4=%s %s\n' "$r" "$w" "$l" \
    "$([ "$w" = "$l" ] && echo MATCH || echo DIFFERS)"
done
ls ~/Development
```

**DIFFERS is not automatically wrong, and this is the line that has to be read
rather than glanced at.** A re-clone can legitimately be *ahead*: here
`surge-pods` came back 72 commits and eight days newer than the Windows copy,
which had simply never been pulled. What makes that safe is not the count but the
ancestry — prove the old HEAD is contained in the new one:

```bash
git -C ~/Development/<repo> merge-base --is-ancestor \
  "$(git -C "$base/<repo>" rev-parse HEAD)" HEAD \
  && echo "windows HEAD is an ancestor -- nothing lost" \
  || echo "DIVERGED -- stop and resolve by hand"
```

A copied repository must be MATCH. Only a re-cloned one may differ, and only
forwards.

Expect the same number of entries in `~/Development` as the inventory listed.

**The Windows copies stay.** They are not deleted in this task, or in any task.
Deleting them is its own decision, taken later, after you have used the new
environment for real work.

## Step 8 — `core.fsmonitor` is settled. Do not measure it again.

This was the deferred item from Task 7, and it now has an answer, recorded as R33
in `docs/decisions.md`: **it stays out of `wsl/git/config`.**

```
$ git fsmonitor--daemon status
fatal: fsmonitor--daemon not supported on this platform
```

Ubuntu's git is not built with the daemon, so `core.fsmonitor = true` here is
neither faster nor slower — it is inert. And there was nothing to buy in any
case: twenty `git status` runs took 0.09 s with it off and 0.09 s with it on,
which is 4.5 ms each on a 308-commit repository.

Re-open this only if `git fsmonitor--daemon status` ever answers differently.

---

## What this run answered

Both tasks were executed on 2026-08-18. The four questions this section used to
ask are answered, and the answers are why several steps above now read
differently:

1. **Task 10 failures.** Five, all one cause: `check.sh` resolved `python3` to
   mise's shim, which has neither pyyaml nor jsonschema, while apt had installed
   both against `/usr/bin/python3`. Fixed by resolving the interpreter by
   capability — R32.
2. **The pin table.** Eleven of eleven honoured, no mismatch.
3. **`check.sh --strict`.** Green inside Ubuntu for the first time: 34 checks,
   nothing skipped. That includes the two that had never executed anywhere —
   `zsh syntax`, and `install.sh --links-only` idempotence — both passing on
   first run.
4. **`fsmonitor`.** Settled and closed: see Step 8 and R33.

What the migration itself cost, for anyone repeating it: nothing was lost, but
only because Step 1 was rewritten mid-run. As originally written it would have
re-cloned three repositories that have no remote, and discarded two branches
holding twelve commits that exist on no server. Both are R34.

Then Task 12 moves Claude Code in, and that runbook is already written at
`docs/runbook-task-12-claude-into-wsl.md`.
