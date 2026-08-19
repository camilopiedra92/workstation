---
name: starting-a-project
description: Use when creating a new project, setting up or changing a toolchain, adding a dependency, creating a virtualenv, or writing version/lock files on this machine. Covers mise, uv, pnpm, lockfile and version-file policy.
---

# Starting or configuring a project on this machine

An existing project's toolchain outranks everything below: the package manager
its lockfile points to, the formatter and linter already configured. Do not
change them or add config on your own initiative. The rules here are for
projects with nothing to respect yet.

## Runtimes and tools

- Runtimes and CLI tools come from mise, never from apt.
- A project needing a version other than the global one gets its own
  `mise.toml`. Never change the global version for one project.

## Python

- Packages and virtualenvs come from uv: `uv venv`, `uv pip install`,
  `uv tool install` for CLIs. Bare `pip install` and `python -m venv` are
  blocked by the guard hook; the block is policy, not a malfunction.
- `.python-version` is load-bearing: uv reads it and it decides the
  interpreter `uv venv` builds on. Keep it. `mise.toml` is for versions
  something outside a venv must resolve.
- A native library a wheel merely wraps (the pango behind weasyprint) is
  invisible to the lockfile and surfaces only at runtime. Say so explicitly
  when a project needs one.

## Node

- pnpm, declared in mise config. Existing npm projects stay on npm.
- Do not declare `packageManager` in `package.json`: corepack reads that
  field, and node 26 no longer ships corepack. The lockfile says which
  manager a project uses, and it cannot be wrong about it.
- Do not write `.nvmrc`: nothing on this machine reads it. A declaration
  nothing honours is worse than none, because with none you look.
- Not yarn: Plug'n'Play's strictness is a continuous tax that pays off for a
  workspace monorepo, not for independent projects.

## Lockfiles

- Any project that will be returned to commits its lockfile — `uv.lock`,
  `package-lock.json`, whatever its manager writes. Libraries too: the
  constraints in `pyproject.toml` are what it publishes, the lock is what
  makes its own development reproducible; they do not compete.
- A scratch script is not a project and needs none of this.

<!-- Why the lockfile rule is absolute: without one, the only record of which
versions worked is the environment itself, and an environment stops answering
the moment its interpreter goes. Eight virtualenvs here died that way on
2026-08-17, four with nothing written down. -->
