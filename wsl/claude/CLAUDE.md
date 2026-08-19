# Global preferences

<!-- Contract for this file: every line is either a fact about this machine
or a rule concrete enough to verify. Long rationale lives in comments like
this one (stripped before injection) or in ~/workstation/docs/decisions.md
(R43-R45 cover this file's own restructure). Rules that must ALWAYS hold are
not prose at all -- they are permission denies and the guard-bash.sh
PreToolUse hook, because prompted rules decay within a session and mechanisms
do not. Procedures live in skills, loading only when they apply. The test for
every line here: would removing it cause a mistake? If not, it goes. -->

<!-- AUDIT: last measured against vendor guidance and delivery research on
2026-08-19. Re-audit by 2027-02 or after the next major model release. Every
rule below encodes an assumption about what the model cannot do on its own,
and those assumptions go stale -- the vendor retired its own sprint
decomposition one model generation after building it. -->

## Environment

- `~/Development` is a container folder, not a project: each subfolder has
  its own git, toolchain and conventions. Nothing seen in one project applies
  to another. No loose files at its root.
- Claude Code and shell config are versioned in `~/workstation`; changes to
  `~/.claude/*` files belong there, never in stray copies.
- Usual stack: Python, Node/TypeScript/JavaScript, React, shell, infra.

## The Windows boundary

Ubuntu under WSL2 on a Windows host. Never write to `/mnt/c`: work lives on
ext4 (`~/Development`), 9-20x faster. Mechanisms back the rule -- one
`Edit(//mnt/c/**)` deny, which covers Write and NotebookEdit too, and
guard-bash.sh for Bash -- and a denial naming the guard is policy working,
not a malfunction; where the guard's net has a gap, the rule still holds.
Reading and copying FROM `/mnt/c` is fine.

Windows PATH interop is off on purpose (`appendWindowsPath = false` in
/etc/wsl.conf). Never assume a Windows binary is on PATH: the ones this
environment uses are aliased individually in `.zshrc` -- add an alias there
rather than putting the Windows PATH back. When something must cross the
boundary, cross it explicitly and say so in the commit message.

## Language

Reply to me in Spanish. Everything written into a file is English -- names,
comments, commit messages, docs, log strings, test fixtures, CLI output.

## How to work

**Calibrate ceremony to blast radius, not task-list length.**

- Diff describable in one sentence: do it, tell me after, let the suite
  verify.
- Several files, an interface change, or a design with real alternatives:
  propose the approach before writing.
- Irreversible or outward-facing (a live system, a security boundary, a
  migration, a published contract): spec, plan, a failing test per
  behaviour, review per milestone. For anything holding data, use the
  data-migrations skill.

Uniform ceremony is not safety: it buys latency, latency grows the batch,
and the batch is where the risk lives.

**Close the loop before claiming done.**

- Every task needs a check that can run: a test, a build exit code, a
  linter, a diff against a fixture, a screenshot against a target. For UI
  work use the frontend-verification skill -- I cannot see my own output.
- Show evidence, not claims: the command run and what it returned.
- Tests I wrote and then made green are weak evidence -- confirm the test
  failed before the fix existed.
- If a command can settle a claim, run it first; say plainly when something
  cannot be determined from here. Break every new check on purpose once:
  a check nobody has watched fail is a check nobody should rely on.
- Backend logic is the easy case: input, output and state can nearly all be
  asserted, so a failing test first pays in full there. The less a domain
  can assert, the more the loop leans on looking.

**Keep the batch small.**

- Merge a finished, self-contained slice instead of holding a branch until
  the feature is done. Vertical slices over horizontal layers, with a
  contract test on each seam.
- Keep one review unit under ~400 changed lines; past that, split it.

<!-- The ~400 threshold is justified by detection quality, NOT review speed:
defect detection collapses with diff size while latency barely moves.
Sources in docs/decisions.md, R43/R44 completion note. Comments in this file
must start at column 0 -- Claude Code strips only column-0 blocks before
injection, and check.sh asserts it. -->

**Review before every merge, however small.** A blocker must be able to
mean "do not merge", not "follow-up on main". Delegate the review to clean
context and scope its mandate -- the delegating-and-reviewing skill carries
the protocol, the single-writer rule, fork vs cold subagent, and report
files.

**Architecture and data models: review the decision before the code
exists.** One page beside the code -- context, alternatives weighed, what it
costs. Then make the boundary a check, not a memory: a test that fails when
a layer imports what it must not. Design is also the one place where several
independent attempts, compared, earn their cost.

**Session hygiene.**

- After two failed corrections of the same issue, stop and say so: a fresh
  session with a better prompt beats a long session of accumulated
  corrections.
- Scope investigations narrowly, or delegate them to a subagent.

**Dependencies and toolchains.**

- Ask before adding a dependency; prefer the stdlib or what the project
  already has.
- Respect the existing toolchain: the lockfile's package manager, the
  configured formatter and linter. A new project starts from this machine's
  -- the starting-a-project skill carries the mise/uv/pnpm, lockfile and
  version-file policy.

**When I ask what best practice is**, judge against the authoritative source
-- the published schema, the vendor's docs, the release calendar -- never
against what is already configured here. Deleting a line is a valid answer
and often the right one.

Group everything that needs deciding into one question up front. Before a
plan's first task, read its spec and compare their dates; where they
disagree, the later measurement wins.

Do not create files nobody asked for: no READMEs, summaries or
"implementation notes".

## Code

- Comment the why, not the what; keep the ones explaining a decision, an
  edge case, or a surprise.
- Tests where logic has real edge cases -- not for getters, wrappers or
  one-line functions.
- Report what actually happened: failing output shown, half-done work named.
  An uncomfortable report beats an optimistic one.
