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

Remember what this is buying: **0.065s against 7.554s**, measured on this machine.

## Step 1 — Inventory what is on the Windows side, with its state

Nothing is deleted before this list exists and every entry is accounted for.

```bash
for d in /mnt/c/Users/camilo.piedrahita/Development/*/; do
  name=$(basename "$d")
  printf '%-26s ' "$name"
  if [ -d "$d/.git" ]; then
    remote=$(git -C "$d" remote get-url origin 2>/dev/null || echo "NO REMOTE")
    dirty=$(git -C "$d" status --porcelain 2>/dev/null | wc -l)
    unpushed=$(git -C "$d" log --oneline @{u}.. 2>/dev/null | wc -l)
    printf 'dirty=%-4s unpushed=%-4s %s\n' "$dirty" "$unpushed" "$remote"
  else
    printf 'NOT A GIT REPO -- must be copied, not re-cloned\n'
  fi
done
```

Known from the survey: `aipm`, `glow`, `surge-pods` and `vr` are git repos;
`obsi`, `testaware` and `surge-pods-migration` are not.

## Step 2 — Push anything unpushed, first

**Any repo showing `dirty>0` or `unpushed>0` must be resolved before it moves.**
A re-clone discards both, silently. This is the one genuinely destructive risk in
the whole plan, and this step is what removes it.

## Step 3 — Authenticate git inside Ubuntu

```bash
gh auth login
gh auth setup-git
```

This is a separate authentication from the one on Windows. That is deliberate —
`git/config` points its credential helper at `gh`, so if this step is skipped
every push fails with an opaque credential error that names neither cause.

## Step 4 — Re-clone the git repositories

```bash
mkdir -p ~/Development && cd ~/Development
for r in aipm glow surge-pods vr; do
  git clone "$(git -C /mnt/c/Users/camilo.piedrahita/Development/$r remote get-url origin)" "$r"
done
```

## Step 5 — Copy the directories that are not git repos

```bash
for d in obsi testaware surge-pods-migration; do
  cp -r "/mnt/c/Users/camilo.piedrahita/Development/$d" ~/Development/
done
```

## Step 6 — Bring the untracked files a clone cannot

`.remember/`, `.claude/settings.local.json`, `.env` files and `.mcp.json` are
untracked by design and do not survive a clone:

```bash
for r in aipm glow surge-pods vr; do
  src="/mnt/c/Users/camilo.piedrahita/Development/$r"
  for extra in .remember .claude .mcp.json .env .env.local; do
    [ -e "$src/$extra" ] && cp -r "$src/$extra" ~/Development/$r/ && echo "$r: brought $extra"
  done
done
```

## Step 7 — Verify before anything is deleted

```bash
for r in aipm glow surge-pods vr; do
  printf '%-16s ' "$r"
  git -C ~/Development/$r log --oneline -1
done
ls ~/Development
```

Expect seven entries, each git repo at the same commit as its Windows twin.

**The Windows copies stay.** They are not deleted in this task, or in any task.
Deleting them is its own decision, taken later, after you have used the new
environment for real work.

## Step 8 — Settle `core.fsmonitor` with a measurement

This is the deferred item from Task 7. The Mac's config enables `fsmonitor` and
`untrackedCache` on FSEvents evidence; here it would be git's own daemon over a
virtualised ext4 volume, which is a different mechanism at a different cost. We
did not port it on faith.

```bash
cd ~/Development/surge-pods
git config --local core.fsmonitor false
for i in 1 2 3; do /usr/bin/time -f '%e off' git status > /dev/null; done
git config --local core.fsmonitor true
git status > /dev/null            # warm the daemon
for i in 1 2 3; do /usr/bin/time -f '%e on ' git status > /dev/null; done
git config --local --unset core.fsmonitor
```

**Send me both sets of numbers.** If `on` is meaningfully faster, the setting
goes into `wsl/git/config` with the measurement in its comment. If it is not, it
stays out and the numbers go in the commit message.

Either outcome is a result. Only skipping the measurement is a failure — a
setting that buys nothing is not neutral, it is a claim nobody checked.

---

## When you are done

Send me:

1. Anything that failed in Task 10, verbatim
2. The Step 6 pin table if anything mismatched
3. Whether `check.sh --strict` came back fully green for the first time
4. The `fsmonitor` numbers

Then Task 12 moves Claude Code in, and that runbook is already written at
`docs/runbook-task-12-claude-into-wsl.md`.
