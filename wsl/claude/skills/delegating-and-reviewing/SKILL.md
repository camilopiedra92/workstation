---
name: delegating-and-reviewing
description: Use when spawning subagents or forks, splitting a plan across agents, or running the pre-merge review. Covers the single-writer rule, fork vs cold subagent, report files, and the reviewer's mandate.
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
- Parallel writers only when file ownership is disjoint and planned before
  fanning out, with the merge order decided in advance. Isolation is easy;
  recombination is where parallel implementation fails.

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

<!-- Why single-writer: an action carries an implicit decision, and two
agents deciding differently produce work nobody can reconcile. Vendor
guidance agrees writes parallelise badly ("most coding tasks") and endorses
parallel writers only with disjoint ownership plus mechanical conflict
resolution. Why clean-context review: self-preference bias in LLM evaluators
is measured and traced to perplexity-based familiarity, which also operates
at model-family level — hence the different-family preference. -->
