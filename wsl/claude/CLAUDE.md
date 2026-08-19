# Global preferences

## Environment

`~/Development` is a container folder, not a project. Each subfolder is an
independent project with its own git, its own toolchain and its own
conventions. Do not assume something seen in one project applies to another,
and do not create loose files at the root of `~/Development`.

Claude Code and shell configuration live in `~/workstation` (versioned). Changes
to `~/.claude/*.sh` go there, not into stray copies.

Usual stack: Python, Node/TypeScript/JavaScript, React, shell and infra.

## The Windows boundary

This environment is Ubuntu under WSL2 on a Windows host. Two rules follow, and
both are about correctness rather than taste.

Never write to `/mnt/c`. Repositories and build output live on ext4 under
`~/Development`, where they are an order of magnitude faster. `/mnt/c` is
reachable, and being reachable is exactly what makes it a trap.

Never assume a Windows binary is on `PATH`. Windows PATH interop is off in
`/etc/wsl.conf` -- `appendWindowsPath = false`, and only that: interop itself
stays on, which is what lets `drift.sh` call `cmd.exe` and the `explorer`/`clip`
aliases work at all. With the Windows `PATH` on, every shell inherits it, and
every file under `/mnt/c` is executable as far as Linux is concerned, so a
Windows shim found there executes a Windows script inside Linux. The Windows
commands this environment calls are aliased individually in `.zshrc`. If
something needs one that is not there, add the alias -- do not put the Windows
`PATH` back.

When something genuinely must cross the boundary, cross it explicitly and say
so in the commit message. A crossing nobody wrote down is the one that breaks on
the next machine.

## Language

Reply to me in Spanish. That is the only thing in Spanish: everything you
write into a file goes in English — names, comments, commit messages, repo
documentation, log strings, test fixtures, CLI output. A repo may end up
public or shared.

## How to work

Calibrate by size. Make a small or mechanical change directly and tell me
afterwards. If it touches several files, changes an interface, or involves a
design decision with real alternatives, propose the approach before writing.

Ask before introducing a new dependency. I almost always prefer solving it
with what is already in the project or with the standard library.

Keep writes single-threaded, and fan out everything that is not a write.
One agent holds the plan and edits the files; every other contributes
intelligence, not actions. Parallel writers fail because an action carries
an implicit decision, and two agents deciding differently produce work
nobody can reconcile afterwards.

So a plan whose tasks form a serial chain over the same files runs inline.
Where a plan or a skill recommends splitting it across agents, read its own
gate before obeying its header — Superpowers' `subagent-driven-development`
asks whether the tasks are mostly independent and sends tightly-coupled work
elsewhere itself. Deciding which shape I have is the whole judgement.

Calibrate the ceremony to the blast radius, not to the length of the task
list. A rename, a config line, a comment: do it, and let the suite verify.
Ordinary work inside one module: tests where there is real logic (see Code
below), written inline, one review before the merge. Something irreversible
or facing outward — a write to a live system, a security boundary, a
migration, a published contract: spec, plan, a failing test before every
behaviour, a review at each milestone rather than at the end. Uniform
ceremony is not safety; it buys latency, latency grows the batch, and the
batch is where the risk actually lives.

Architecture and the data model are their own category, because what can be
wrong there is the decision rather than the code, and no amount of testing
tells me a schema was the wrong schema. Three things follow.

**Review the decision before the code exists.** Write the choice down first
— context, the alternatives actually weighed, the decision, what it costs —
one page, in source control beside the code. Reviewing the implementation of
a wrong model does not save it. This is also the one place where spawning
several independent attempts and comparing them earns its cost: design is
where diversity of approach pays, and nothing is being written yet, so there
is no writer to keep single.

**Make the rule enforceable instead of remembered.** A boundary defended by
review is defended until someone is tired. Write the check — a test that
fails when a layer imports what it must not, when the only module allowed to
read the environment stops being the only one. Governance by rule beats
governance by inspection, and it is usually an afternoon's work.

**For anything holding data, reversibility is the design property.** Expand,
migrate, contract: add the new shape beside the old, move, then remove —
each step backwards-compatible and separately revertible. Never one
destructive step. Rehearse the rollback, not just the migration: the
migration runs once, the rollback is the one needed on the bad day.
Ceremony belongs on doors that only open one way, and a schema with data in
it is the clearest one there is.

The tiers do not change by domain. What changes is the material a check can
be made of, and that is worth settling before starting.

Backend is the easy case: correctness is input, output and state, so a test
can assert nearly all of it, and test-first pays in full. Frontend is not —
a test can assert that a button with the right accessible name exists and
cannot tell me it looks right. So the suite there leans on integration over
unit tests, where confidence per test is highest, and the missing half is
closed by looking: render it, screenshot it, compare against the target,
fix, repeat. **I cannot see my own output.** With no screenshot in the loop
there is no feedback loop at all, only me asserting that CSS I never saw is
fine — and the agent that wrote a component is the wrong one to judge how it
looks, for the same reason it is the wrong one to review its own code.

A whole application moves the risk from "is this right" to "do the pieces
meet". Build the thinnest vertical slice that runs end to end and can be
deployed before building any layer completely, and put a contract test on
the seam between the parts: that is where the bugs live that neither side's
own tests are looking for. Vertical slices, not horizontal layers — a
finished backend with nothing calling it is a large batch nobody has
validated.

Two things never scale down, whatever the tier.

**Review, on the branch and before the merge**, however small the change —
a blocker has to be able to mean "do not merge" rather than "write a
follow-up for something already on main". Delegate it, and give the reviewer
a *clean* context deliberately: shared context inherits the author's blind
spots, which is the whole thing a second pair of eyes is for. Check that
whatever workflow you are following actually contains this step, because a
plugin's own skills can disagree with each other about it — as of
Superpowers 6.3.0, `executing-plans` goes straight from the last task to the
merge, while `requesting-code-review` calls itself mandatory before one.
Verify before trusting either.

**Keep the batch small.** Prefer merging a finished, self-contained layer
over holding a branch until the whole feature is done. A big branch makes
the review expensive, makes a regression hard to locate, and buries the one
diff where the mistake was obvious.

Also worth delegating:

- Broad search, verification runs, anything whose output is volume I will
  never read again.
- Independent attempts at an open question, when comparing them beats
  iterating on one.

Prefer a **fork** (`/subtask`) over a cold subagent whenever the task needs
the conversation's background: a fork inherits the history and reuses the
prompt cache, so it pays neither the briefing nor the cold start. A cold
subagent is right when the task is genuinely self-contained, or when clean
context is the point.

Tell every delegated agent to write its report to a file and give me the
path, then check the file is there before acting on it. A report that comes
back only as a message lives in one context window and dies with it. Put it
where the project already keeps that kind of record. The message is the
notification; the file is the artefact.

Delegating is not free — an agent spends several times the tokens of a
chat, and a fleet of them an order of magnitude more. That is a reason to
aim it, not to avoid it.

Before the first task of a plan, read the spec too and compare their dates. A
plan is a snapshot of what was known when it was written, and evidence keeps
arriving after it. Where they disagree the spec's later measurement wins.
Group everything that needs deciding into one question up front rather than
interrupting per task.

When I ask whether something is best practice, judge it against the
authoritative source — the published schema, the vendor's docs, the upstream
release calendar — and not against what is already configured here. Reading a
setup in order to review it biases towards keeping it. Deleting a line is a
valid answer and often the right one: pinning a value that is already the
default buys nothing today and blocks the better default tomorrow.

Prove things rather than assert them. If a claim can be settled with a command,
run it first — and say plainly when something cannot be determined from here
instead of picking the likely answer. When you add a check, break it on purpose
before trusting it: a check nobody has watched fail is a check nobody should
rely on.

Respect the toolchain each project already uses: the package manager the
lockfile points to, the formatter and the linter that are configured. Do not
change them or add new config on your own initiative.

In a new project there is nothing to respect yet, so start from this machine's:
runtimes and tools come from mise and never from apt; Python packages and
virtualenvs from uv, and a project that needs a version other than the global
one gets its own `mise.toml` rather than a global change. Never `pip install`
into the interpreter itself, and never reach for `python -m venv` when
`uv venv` is there. If a project needs a native library — the kind uv installs
a wrapper for and cannot provide, like the pango behind weasyprint — say so,
because that dependency is invisible to the lockfile and only surfaces at
runtime.

A project I will come back to commits its lockfile — `uv.lock`,
`package-lock.json`, whatever its manager writes. Without one, the only record
of which versions worked is the environment itself, and an environment stops
being able to answer the moment its interpreter goes: eight virtualenvs here
died that way on 2026-08-17, four of them with nothing written down. Commit it
for a library too. What a library publishes are the constraints in its
`pyproject.toml`; the lock is so its own development is reproducible, and the
two do not compete. A scratch script is not a project and needs none of this.

For node it is pnpm, declared in `mise/config.toml` and never installed with
`npm i -g`, which writes into a directory named after node's patch version and
loses everything in it on the next bump. npm's `node_modules` is flat, so a
package can require something it never declared — a transitive dependency got
hoisted next to it — and that works until the hoisting changes and then breaks
somewhere else. pnpm resolves only what a package declares, which is the same
thing this file asks for everywhere else: that a declaration mean what it says.
Not yarn, whose Plug'n'Play is stricter still and charges for it continuously,
a trade that pays off for a monorepo with workspaces and not for ten separate
projects. Existing npm projects stay on npm; the rule above about respecting a
project's toolchain outranks this one.

Do not declare `packageManager` in `package.json` on this machine: corepack is
what reads that field, and node removed corepack from the distribution — 26
ships `node`, `npm` and `npx` and nothing else. The lockfile is what says which
manager a project uses, and it cannot be wrong about it, because the manager is
what wrote it.

The version file has to be one something actually reads, and which file that is
depends on who needs the answer. mise leaves `idiomatic_version_file_enable_tools`
empty by default, so it reads neither `.nvmrc` nor `.python-version`. For node
that settles it: corepack is gone, nothing else reads `.nvmrc`, and a project
here asked for node 22 in one, ran on 26 for months, and published from CI on
22. A declaration nothing honours is worse than none, because with none you
look.

`.python-version` is the exception and it matters: uv reads it, and it is what
decides the interpreter `uv venv` builds on. In a uv project that file is the
pin, and deleting it because mise ignores it would break the thing it exists
for. `mise.toml` is for a version something outside a venv has to resolve — a
node project, or a tool that runs before the venv exists.

Do not create files that are not needed. No READMEs, summaries or
"implementation notes" documents unless I ask for them.

## Code

Comment the why, not the what. If the comment repeats what the next line
already says, drop it. The ones worth keeping explain a decision, an edge case,
or something that would surprise the reader.

Write tests when there is logic with real edge cases. Not for getters,
wrappers or one-line functions.

When you finish, tell me what actually happened: if a test fails, show me the
output; if you left something half done, say so. I prefer an uncomfortable
report to an optimistic one.
