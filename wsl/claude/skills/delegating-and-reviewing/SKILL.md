---
name: delegating-and-reviewing
description: Use when spawning subagents or forks, splitting a plan across agents, or when finishing a branch, opening a PR, or about to merge. Covers the single-writer rule, fork vs cold subagent, report files, and the pre-merge review's protocol and mandate.
---

# Delegating work and reviewing it

## What to delegate

- Broad search, verification runs, anything whose output is volume nobody
  re-reads: always delegable — a separate context window returns a summary.
- Independent attempts at an open question, when comparing beats iterating.
  Design work is where this pays most: nothing is being written yet, so there
  is no writer to keep single.
- Cost: an agent spends several times the tokens of a chat, a fleet an order
  of magnitude more. A reason to aim delegation, not to avoid it.

## Writes stay single-threaded

- One agent holds the plan and edits the files; every other contributes
  intelligence, not actions. A serial chain over the same files runs inline.
- The one exception, decided in R45: parallel writers only when the
  partition is written down BEFORE fanning out -- which agent owns which
  files or modules, and in what order the branches merge. That page is a
  plan-time condition someone can check. If it cannot be written, the work
  is not partitionable and one writer holds the pen.
- Where a plan or a skill recommends splitting work across agents, read its
  own gate before obeying its header -- Superpowers'
  `subagent-driven-development` asks whether the tasks are mostly
  independent and sends tightly-coupled work elsewhere itself. Deciding
  which shape the work has is the whole judgement.

## Fork vs cold subagent

- Fork (`/subtask`) when the task needs the conversation's background: it
  inherits history and reuses the prompt cache.
- Cold subagent when the task is self-contained, or when clean context IS the
  point (a reviewer, an independent attempt).

## Reports

- Every delegated agent writes its report to a file and returns the path.
  Check the file exists before acting on it. The message is the notification;
  the file is the artefact. Put it where the project keeps that kind of
  record.

## The pre-merge review

- Every branch gets a review before the merge, however small the change. A
  blocker must be able to mean "do not merge", not "follow-up on main".
- Check that whatever workflow is being followed actually contains this
  step: a plugin's own skills can disagree with each other about it -- as of
  Superpowers 6.3.0, `executing-plans` goes straight from the last task to
  the merge, while `requesting-code-review` calls itself mandatory before
  one. Verify before trusting either.
- The reviewer gets deliberately clean context: a cold agent that sees the
  diff and the criteria, not the reasoning that produced the change. The
  author's context inherits the author's blind spots. A different model
  family is a stronger independent check than a fresh session of the same
  model, when one is available.
- Scope the mandate explicitly: flag only what affects correctness or the
  stated requirements; everything else is optional. A reviewer told to find
  gaps will find some even in sound work, and chasing every finding produces
  over-engineering.
- Tests the implementing agent just made green are weak evidence. Confirm the
  test failed before the fix existed, or have the reviewer run the
  verification independently.

<!-- Why single-writer, why its exception has the shape it has, and the
citations behind the clean-context and different-family preferences:
docs/decisions.md R45 in ~/workstation. -->
