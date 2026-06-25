---
status: accepted
---

# Customizations are split into modules, tools, and plugins by lifecycle

Everything `bx` manages falls into exactly one of three categories, decided by
*how and when the code runs*, not by what it does:

- **Modules** (`modules/*.sh`) are **sourced** into every interactive bash via
  `init.sh`. They define functions, aliases, and environment, so they must be
  idempotent and free of side effects.
- **Tools** (`tools/*.sh`) are **executed** on demand via `bx run`. They install
  software or bootstrap state in their own subprocess.
- **Plugins** are **symlinked** from `plugins/` into a tool-mandated path
  *outside* `~/.bin` (e.g. an Argos widget directory), keeping files that can't
  live in the tree under `bx`'s enable/disable lifecycle anyway.

The lifecycle is what makes these incompatible: a sourced installer would
pollute or break the interactive shell, and an executed module's functions would
vanish with its subshell. Encoding the distinction in *which directory a file
lives in* makes the category — and therefore the run semantics — unambiguous and
mechanically checkable (`bx selftest` enforces per-category rules).

## Considered options

- **A single `scripts/` directory** with no source-vs-execute distinction.
  Rejected: sourcing a one-shot installer pollutes the interactive shell, while
  executing a module runs it in a subshell where its functions and aliases
  immediately disappear. The category a file belongs to *is* the contract for
  how it runs; collapsing them invites that category error.
- **Modules and tools only, no plugins** — manage external-path customizations
  (Argos widgets and similar) by hand. Rejected: those files must live at a
  tool-mandated path outside `~/.bin`, so without a plugin category they escape
  version control and `bx`'s enable/disable/selftest entirely. The plugin
  category exists precisely to pull OUTSIDE-`~/.bin` files back under the same
  lifecycle via a symlink whose source stays in-repo.

## Consequences

There are three concepts to learn instead of one, and adding a new kind of
managed thing means deciding which category it belongs to (or, rarely,
justifying a fourth — see CLAUDE.md's "architectural ambiguity → ask"). In
exchange, the directory layout doubles as documentation of run semantics, and
`bx selftest` can enforce category-specific invariants (load guards on modules,
`# bx-purpose:` on tools, metadata headers on plugins).
