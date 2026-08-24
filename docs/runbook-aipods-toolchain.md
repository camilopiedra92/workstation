# Runbook — install the AI Pods toolchain on WSL

Stepwise, the `coda` Agent Runtime, and the capability registry, on Ubuntu under
WSL2. Three steps here cannot be scripted — a Drive download behind a Google
session, an Azure device-code login, and an OAuth browser handoff — so this is a
runbook rather than an installer.

The vendor's own guide is written for macOS and for a machine whose shell reads
`~/.zshrc`. Neither is true here, and both failures are silent. Read the traps
at the bottom before starting if you are debugging rather than installing.

Verified end to end on 2026-08-24: `coda` 1.3.0, Stepwise 1.40.1,
registry 1.23.0.

---

## Why the vendor path does not work unchanged

Three reasons, each costing an afternoon if met blind.

**PATH lands in a dead file.** Both installers append their `export PATH` line to
`~/.zshrc`. `ZDOTDIR` points at `~/.config/zsh` on this machine, so zsh never
reads `~/.zshrc`. The binaries install correctly, `doctor` passes when run by
hand, and every new terminal reports `command not found`.

**The browser opener blocks forever.** The Stepwise installer probes
`command -v open` before `xdg-open`, a preference that makes sense on macOS.
Here it makes no difference: `/usr/bin/open` is a symlink through
`/etc/alternatives` to `xdg-open`, so both branches call the same script — and
that call was observed hanging for minutes, leaving the installer stuck after
printing the device code with no error. Preferring `xdg-open` is therefore not
the fix; not invoking an opener at all is.

**The device-code prompt needs a real terminal.** It reads from `/dev/tty`, so
it aborts under any redirected stdin.

---

## Prerequisites

```bash
for b in curl unzip git; do command -v "$b" || echo "MISSING: $b"; done
```

Nothing else. The `coda` installer ships a native binary — Node is not required,
and installing through `npm i -g @globant/coda` instead would tie the CLI to
whichever node version mise has active today.

---

## Step 1 — Install the Agent Runtime

```bash
curl -fsSL 'https://docs.globant.ai/en/filedownload?4622,12' -o /tmp/coda-install.sh
less /tmp/coda-install.sh          # read it before running it
bash /tmp/coda-install.sh
```

It writes to `~/.coda/bin/coda`, needs no sudo, and downloads anonymously from
the public npm registry.

**Check:**

```bash
~/.coda/bin/coda --version
```

---

## Step 2 — Claim the PATH where zsh will read it

Step 1 created a stray `~/.zshrc`. Delete it; the entry belongs in the versioned
`.zshenv`, which every zsh reads:

```bash
rm ~/.zshrc
grep -n 'coda/bin' wsl/zsh/.zshenv     # already claimed, alongside .stepwise/bin
```

**Check** — a non-interactive zsh reads `.zshenv` and nothing else, so this
proves the entry works rather than that some other file happens to compensate:

```bash
zsh -c 'command -v coda'
```

---

## Step 3 — Get the Stepwise installer out of Drive

The installer is not on a public URL. It lives in a Drive folder that needs a
signed-in Google session, and the folder holds **five files named `install.sh`**.
They are byte-identical — confirmed by sha256 — so any of them will do, but
confirm that rather than assume it if the folder has changed.

Drive refuses to virus-scan executables, so a direct download returns an
interstitial rather than the file. The real bytes need a second request carrying
the `confirm`, `uuid` and `at` fields that interstitial mints. Downloading it by
hand from the browser does this for you; automating it does not.

Folder: <https://drive.google.com/drive/folders/16A76iz_qH7IbAddZvhzgTC0MMe86BhKW>

**Check:** the file is ~17 KB and starts with `#!/bin/bash`.

---

## Step 4 — Run the installer in a real terminal

```bash
bash ~/Downloads/install.sh
```

It prints a device code, then waits. Open <https://microsoft.com/devicelogin>,
enter the code, and approve the consent screen for
*AzArtifacts - aipods-stepwise - delegated clients*. Approving that consent is
an identity decision — do it yourself, and read what it names before clicking.

The `open` hang from the top of this page will bite here. In an interactive
terminal you can Ctrl-C the opener and the installer continues, because the call
is guarded with `|| true`. For an unattended run, patch the two interactive
lines instead — the `read -r _dummy < /dev/tty` and the `open`/`xdg-open` block —
and keep the untouched original beside it so the diff stays visible.

Your account needs Reader or Contributor on the `stepwise-feed` Azure DevOps
Artifacts feed. If the browser login succeeds but the download fails, that is
the reason, and it is not a local problem.

**Check:**

```bash
rm ~/.zshrc                        # the installer recreates the stray file
zsh -c 'stepwise --version'
```

---

## Step 5 — Sync the capability registry

`stepwise registry sync` needs a TTY: without one it reports
*"interactive login is unavailable in this context"* and stops. It mints a
second, separate device code.

```bash
stepwise registry sync
```

Approve *AzArtifacts - aipods-agents-skills - delegated clients* — a different
consent from Step 4, for a different feed.

**Check:**

```bash
stepwise registry list | grep -coP '^\S+\s+[a-z0-9][a-z0-9-]+ \(v[0-9]'
```

That counts capability headings rather than output lines — 90 on registry
1.23.0. Do not treat the number as the check; treat "far more than six" as the
check. The Stepwise User Manual documents six capabilities, and the registry is
what the Playlist is actually composed from.

---

## Step 6 — Health check

```bash
stepwise doctor
```

Four checks must pass: binary, registry, config, executor CLI.

Note what is **not** in that list on 1.40.x: `CODA_SINGLE_AGENT_MAX_ITERATIONS`.
The handbook states across five pages that `doctor --fix` sets it to 300 and
that a lower value silently truncates agent sessions mid-run. The check was
removed; the failure mode was not. Inspect `~/.coda/.env` by hand if sessions
end early for no visible reason.

---

## Step 7 — Point `coda` at the right Glob.AI instance

`coda` asks for a region and offers *europe*, *us* and *others*. Neither of the
first two is the Globant client infrastructure — they are the public SaaS
tenants. Choose **others**, then enter the base URL exactly:

```
https://api.clients.globant.com
```

`coda` matches a typed URL against its preset table and reuses the preset when
it finds one; a trailing slash or a `console.` host misses, and you silently get
a `custom` profile with a different secrets variable and a different OAuth
client id.

| id | Prompt label | API base URL |
| --- | --- | --- |
| `clients` | (under "others") | `https://api.clients.globant.com` |
| `corp` | (under "others") | `https://api.os.corp.globant.com` |
| `saas-europe` | europe | `https://api.eu.glob.ai` |
| `saas-us` | us | `https://api.saia.ai/` |
| `beta` | (under "others") | `https://api.beta.saia.ai` |

OAuth stores its tokens in the OS keyring, so `~/.coda/.secrets` stays empty.
That is correct, not a failure.

**Check** — the profile resolved to the preset, not to `custom`:

```bash
python3 -c "import json,pathlib;d=json.loads((pathlib.Path.home()/'.coda/config.json').read_text());p=d['profiles'][d['activeProfile']];print(p['instance'], p['org']['name'], p['project']['name'])"
```

---

## Step 8 — Prove the whole chain

```bash
coda -p "Reply with exactly: PIPELINE OK"
```

A successful run also prints its cost. Expect roughly 16k tokens and $0.05 for a
three-word answer: that is the per-invocation context floor, and it is the
baseline every capability's token figure sits on top of.

---

## Traps, in one table

| Symptom | Cause | Fix |
| --- | --- | --- |
| `command not found` in new terminals, binary present | PATH written to `~/.zshrc`, which `ZDOTDIR` makes dead | Claim it in `wsl/zsh/.zshenv`; delete the stray file |
| Installer prints the device code then hangs | the `open`/`xdg-open` call never returns; both resolve to `xdg-open` here | Ctrl-C the opener, or drop the block entirely for unattended runs |
| Installer aborts immediately | `read < /dev/tty` with redirected stdin | Run it in a real terminal |
| Downloaded `install.sh` is 2.5 KB of HTML | Drive's virus-scan interstitial | Follow the confirm form, or download from the browser |
| `registry sync`: "interactive login is unavailable" | No TTY | Run it in a real terminal |
| Sessions end early with no error | `CODA_SINGLE_AGENT_MAX_ITERATIONS` below 300, no longer checked by `doctor` | Inspect `~/.coda/.env` |
| `coda` logs in but shows the wrong projects | Picked europe or us instead of others → clients | Re-run `coda --reconfigure` |

---

## What this runbook does not give you

A **dedicated Glob.AI project**. The Clients console has no way to create one —
projects are provisioned through a Jira request that names the client and the
project. Until it lands you are in a shared `Default` project whose token
consumption cannot be attributed to your pod, which is exactly what the AI Pods
Gate 3 forbids. Raise that request at the start of an engagement, not when you
reach the tooling gate.
