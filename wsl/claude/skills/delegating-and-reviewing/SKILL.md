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
- **"Every" includes reviewers.** Read as advice for implementers, this rule
  gets broken the first time a reviewer is dispatched -- a review feels like
  an answer, not an artefact. A reviewer told to return its verdict as its
  final message ran 25 minutes and delivered nothing; a status message got no
  reply either; a fresh one told to WRITE A FILE delivered. Say in the
  dispatch: "this file IS your deliverable, write it complete in one call as
  the last thing you do", and have it return only the verdict lines.
- The file is also how you wait. Block on the artefact appearing
  (`until [ -f <path> ]; do sleep 15; done`) rather than polling a message
  channel: it survives the agent dying, and it stays out of your context
  until you choose to read it.
- **An agent can die mid-task** -- a session limit, a crash -- leaving
  uncommitted work and no report. That tree is ambiguous: partially-applied
  work and a mutation nobody reverted look identical to `git status`, and
  these workflows deliberately mutate source to watch a test fail. Read the
  diff as prose before anything else, back the tree up outside the repo, and
  tell the next agent exactly what is already done. Never resolve it with
  `git checkout`/`stash`/`restore`/`clean`.

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
  author's context inherits the author's blind spots.
- Clean context is what buys the independence; a different model family adds
  to it, and costs far more. So order the choice by price: default to the
  cheapest model that can actually do this review's task, and spend a premium
  family only where the verdict turns on judgement a cheaper reviewer
  demonstrably got wrong. Never pre-emptively, and never merely because the
  premium one is available.
- Never hedge one reviewer with another. Two cold agents under the SAME
  mandate is one review run twice: it doubles the cost and leaves the author
  arbitrating their disagreement, which is precisely the job a review exists
  to take off the author. Two reviewers earn their keep only when the
  mandates DIFFER -- one digging through the evidence, one judging the diff
  -- and each mandate then has to say which half it owns.
- **Two reviewers on one working tree collide if either one writes.** A
  mutation-running reviewer dirties `src/` and restores it; a reviewer reading
  the same tree sees a transient defect and reports a red suite that is the
  first reviewer's, not the branch's. Either serialise them, give the writer
  its own worktree, or tell the reader that a red test may be somebody else's
  mutation and to check `git status` before believing one. Cheapest is the
  last, and it has to be said BEFORE they start — a false finding costs more
  to arbitrate than the warning costs to send.
- **Ask the reviewer to RUN the mutations, not to read for them.** A reviewer
  that reads reports suspicions; one that mutates reports whether a test dies
  and which. The difference showed on 2026-09-07: three rounds of reading had
  missed a guard that was protected by evaluation order rather than by
  anything it did, and one mutation found it in a minute.
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
