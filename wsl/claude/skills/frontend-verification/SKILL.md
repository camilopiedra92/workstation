---
name: frontend-verification
description: Use when building or changing any UI — components, pages, styles, layouts — before claiming the visual work is done. Covers the screenshot loop and the test balance for frontends.
---

# Verifying frontend work

A test can assert that a button with the right accessible name exists. It
cannot say the page looks right. Frontend correctness therefore has two
halves, and each needs its own loop.

## The testable half

- Lean on integration tests over unit tests: confidence per test is highest
  where a test crosses a real boundary without needing a full environment.
- Unit-test real logic (parsers, reducers, date math), not markup.

## The visual half

I cannot see my own output. Without a screenshot in the loop there is no
feedback loop — only an assertion that CSS nobody saw is fine.

1. Render the change in the real app (browser tools are available).
2. Screenshot it.
3. Compare against the target (design, mock, or the before state).
4. List the differences. Fix. Repeat until the list is empty.

- Never claim visual work is done without having looked at it in this loop.
- The agent that wrote a component is the wrong one to judge how it looks —
  same reason it is the wrong one to review its own code. When the judgment
  matters, delegate the comparison to a fresh pair of eyes with the
  screenshot and the target.
