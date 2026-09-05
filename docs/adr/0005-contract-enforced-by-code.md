---
status: accepted
date: 2026-09-05
---

# ADR 0005 — the contract is enforced by code, not by reading CLAUDE.md

## Context

CLAUDE.md describes how this tree must be shaped: where files go, load
guards, tool headers, one-line bashrc, docs kept in step. Until now it was
advice. A human in a hurry or an agent with a partial view could break any
of it and nothing would object until a shell failed to load somewhere.

## Decision

Every structural rule in CLAUDE.md has an `L<n>` check in `bx lint`. The
same checks run in three places, so they cannot be skipped by accident:

1. `bx lint` — on demand, static, seconds. `bx selftest` calls it.
2. `hooks/pre-commit` — tracked in the repo, activated by `bx install`
   (`core.hooksPath=hooks`). Runs lint and `tests/`; blocks the commit.
3. `.github/workflows/ci.yml` — the same on every push and PR, on a clean
   Ubuntu, with shellcheck present.

A rule that cannot be checked by `bx lint` is written into CLAUDE.md as a
policy with a named reviewer step, and marked as such.

## Consequences

- Adding a rule means adding an `L` check first, then the CLAUDE.md line
  that cites it. A rule without a check is a smell.
- `bx lint` must stay fast and side-effect free; anything that touches the
  system belongs in `bx doctor`.
- `--no-verify` is allowed but must be justified in the commit message.
