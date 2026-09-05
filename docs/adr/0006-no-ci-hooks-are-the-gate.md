---
status: accepted
date: 2026-09-05
---

# ADR 0006 — no CI: the git hooks are the whole gate

## Context

ADR 0005 ran the contract in three places, the third being a GitHub Actions
workflow on every push. This tree has one author and one machine that
matters. A remote job duplicated what the laptop can run, cost a round-trip
per push, and its one real advantage — a clean Ubuntu — is now covered by
`tools/bootstrap-smoke.sh`, which bootstraps HEAD inside a throwaway
container locally.

## Decision

`.github/` is removed. The checks that ran there run in tracked git hooks,
activated by `bx install` (`core.hooksPath=hooks`):

- `hooks/pre-commit` — `bx lint`, `tests/`, every enabled module loads,
  `bootstrap --dry-run`. Under a minute.
- `hooks/pre-push` — `bootstrap-smoke`: clone HEAD into a fresh
  `SMOKE_IMAGE` container and run the full bootstrap. Minutes; needs docker.

## Consequences

- Nothing runs anywhere but this machine. `--no-verify` on commit or push
  is the only way around the gate; the reason goes in the commit message.
- The smoke tests HEAD, not the working tree — commit, then push.
- If a second machine or contributor ever appears, revisit: the hooks are
  tracked, so re-adding a workflow is one file.
