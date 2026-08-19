---
name: data-migrations
description: Use when changing a database schema or migrating anything that holds data — before writing the migration. Covers expand/contract and rollback rehearsal.
---

# Changing anything that holds data

Ceremony belongs on doors that only open one way, and a schema with data in
it is the clearest one there is. Reversibility is the design property, not a
nice-to-have.

## The shape: expand, migrate, contract

1. **Expand** — add the new shape beside the old. Old readers and writers
   keep working untouched.
2. **Migrate** — move and backfill the data. Dual writes (or triggers) keep
   both shapes consistent while both exist; on a live system, shadow reads
   prove the new shape under real traffic before anything switches.
3. **Contract** — switch readers, then remove the old shape, as its own
   separately deployed step.

- Each step is backwards-compatible and separately revertible without data
  loss. Never one destructive step.
- Never combine a schema change and a behaviour change in one deploy.

## The rollback

- Rehearse the rollback, not just the migration. The migration runs once, on
  a good day; the rollback is the one needed on the bad day, and it must have
  been run by someone before that day.
- Write the rollback for each phase before running that phase.

## Process weight

This is the full-ceremony tier regardless of how small the diff looks: the
decision on paper first (context, alternatives, cost — one page beside the
code), a failing test per behaviour, and review at each phase rather than at
the end.
