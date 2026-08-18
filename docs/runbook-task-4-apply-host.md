# Runbook — Task 4: apply the Windows host layer

**You run this one.** Everything up to here has been files; this is the first
step that changes the machine, and it needs a human because `winget configure`
raises a UAC prompt and Ubuntu's first launch asks for a username.

Expect 10–20 minutes, most of it downloads.

---

## Before you start

Open **PowerShell** (not Git Bash) in the repo:

```powershell
cd C:\Users\camilo.piedrahita\Development\workstation
```

### Record what the machine looks like now

So that "it worked" is a comparison and not an impression. Paste the output back
to me if anything surprises you.

```powershell
wsl -l -v
winget list --id Microsoft.WindowsTerminal --exact
```

Expected **before**: only `docker-desktop` listed; Windows Terminal at
`1.18.10301.0`.

---

## Step 1 — Apply

```powershell
.\windows\bootstrap.ps1
```

**One UAC prompt.** It appears once, at the start, because the manifest marks the
system-wide installs as needing elevation. The three authoring tools
(shellcheck, shfmt, taplo) are user-scope and are not part of that prompt.

What it installs: WSL2, Ubuntu 26.04 LTS, Windows Terminal, VS Code,
JetBrainsMono Nerd Font, PowerToys, and the three authoring tools.

**If it fails**, stop and send me the error. Two failures are plausible and I
want to see either verbatim:

- Anything naming `PSDscResources` or `Script` — that is the DSC resource that
  installs Ubuntu. I verified the resource exists in the module (`Script` at
  2.12.0.0, queried from the PowerShell Gallery), but `winget configure validate`
  cannot check resource names, so this is the first time it is exercised for real.
- Anything naming a package id — every id was verified to resolve, but a
  catalogue can move.

Re-running is safe. `winget configure` is idempotent by design: it applies only
what is not already in the desired state.

---

## Step 2 — Confirm each declared thing arrived

```powershell
wsl -l -v
winget list --id Microsoft.WindowsTerminal --exact
winget list --id DEVCOM.JetBrainsMonoNerdFont --exact
winget list --id Microsoft.PowerToys --exact
```

Expected: `Ubuntu-26.04` present at **VERSION 2**, Windows Terminal at 1.22 or
newer, font and PowerToys present.

**If Ubuntu shows VERSION 1, stop and fix it before going on.** WSL1 has none of
the filesystem performance this whole design rests on:

```powershell
wsl --set-default-version 2
wsl --set-version Ubuntu-26.04 2
```

---

## Step 3 — Create the Ubuntu user

```powershell
wsl -d Ubuntu-26.04
```

First launch asks for a UNIX username and password.

**Use `camilo`.** Not `camilo.piedrahita`, not anything else.

`windows/terminal/settings.json` hardcodes `/home/camilo` as the starting
directory. If you pick a different name, that line is wrong and every terminal
tab opens in a directory that does not exist — tell me and I will correct it in
the same breath rather than leaving it to be discovered later.

The password is for `sudo` inside Ubuntu. It is unrelated to your Windows or
Globant password, and nothing syncs them. Pick something you can type often.

Then leave the shell:

```bash
exit
```

---

## Step 4 — Measure the filesystem claim

This is the number the entire "repos live on ext4" decision rests on, and so far
it is a number from other people's benchmarks rather than from your machine.
It takes about a minute.

```powershell
wsl -d Ubuntu-26.04 -- bash -c 'echo "--- ext4 (home) ---"; cd ~ && time (mkdir -p bench && cd bench && for i in $(seq 1 2000); do echo x > f$i; done; cd ~ && rm -rf ~/bench); echo "--- /mnt/c ---"; cd /mnt/c/Users/camilo.piedrahita && time (mkdir -p bench && cd bench && for i in $(seq 1 2000); do echo x > f$i; done; cd /mnt/c/Users/camilo.piedrahita && rm -rf bench)'
```

**Send me both numbers.** They go into the commit message and the README, so the
claim in this repo is measured on this laptop rather than borrowed.

If ext4 is not dramatically faster, that is a finding worth stopping for — it
would mean something is wrong with the WSL2 setup, not that the design is wrong.

---

## Step 5 — Deploy the terminal settings

Back in **Git Bash**:

```bash
cd /c/Users/camilo.piedrahita/Development/workstation
cp windows/terminal/settings.json \
  "/c/Users/camilo.piedrahita/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
```

If that path does not exist, Windows Terminal has not been launched since it was
installed. Open it once, close it, and try again.

---

## Step 6 — Look at it

Open Windows Terminal. Four things to check by eye:

| | Expected | If wrong |
|---|---|---|
| Opens on | Ubuntu 26.04, not PowerShell | `defaultProfile` did not match the generated profile name — send me `wsl -l -q` output |
| Colours | Catppuccin Mocha — deep purple-grey background | the scheme name and the `colorScheme` value disagree |
| Zero | slashed (`0` with a line through it) | the font did not resolve; you are seeing Consolas |
| `ls` | icons before filenames, not empty boxes | same — the font did not resolve |

Then the one that matters most:

```bash
pwd
```

**Expected: `/home/camilo`.** If it says `/mnt/c/Users/camilo.piedrahita`, the
`startingDirectory` setting did not take, and every session would start on the
slow path. Tell me — that is a real failure, not a cosmetic one.

Finally, test the keybinding this whole translation exists for:

Type something, then press **Shift+Enter**. It should insert a line break rather
than submitting. That is the binding Claude Code needs for multi-line prompts,
and it was the piece the schema rejected in its original form.

---

## What you are NOT doing yet

Nothing is installed *inside* Ubuntu yet — no zsh, no mise, no starship, no
Claude Code. Ubuntu is a bare distro at this point. That is Task 10, after I
finish Tasks 5 through 9.

Your repositories are untouched, still under
`C:\Users\camilo.piedrahita\Development`. They move in Task 11, and nothing is
deleted from Windows even then.

---

## When you are done

Send me:

1. The `wsl -l -v` output from Step 2
2. Both numbers from Step 4
3. Whether the four visual checks and `pwd` came out as expected
4. Any error, verbatim

I will record the measurement in the repo and carry on with Tasks 5 through 9.
