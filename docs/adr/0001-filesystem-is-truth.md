---
status: accepted
---

# Filesystem (the `enabled/` symlink directory) is the source of truth

`bx` decides which shell modules to load by listing `~/.bin/enabled/`, a
directory of symlinks pointing into `~/.bin/modules/`. There is no manifest,
config file, or declared list of active modules anywhere. `init.sh` sources
`enabled/*.sh` in lexical filename order, and every `bx` verb
(`enable`/`disable`/`ls`/`doctor`) is a thin wrapper over creating, removing,
and inspecting those symlinks. We chose this because the state is then fully
inspectable with `ls -la enabled/`, enabling/disabling is an atomic `ln`/`rm`
with no file to keep in sync, and `bx` itself stays optional — the shell loads
correctly even if the CLI is unavailable.

## Considered options

- **A declarative manifest** (`enabled.toml` / `enabled.list` naming the active
  modules and their order). Rejected: it creates a second source of truth that
  must be kept in sync with the files on disk, you can no longer see the active
  set with a plain `ls`, and enable/disable becomes an edit-and-reparse instead
  of an atomic filesystem operation. This is what most dotfile managers do, so
  it's the alternative a reader will reach for first — hence recording why we
  didn't.
- **Real files directly in `enabled/`** (no `modules/` library; disable by
  moving or deleting). Rejected: disabling would mean deleting work or inventing
  a parallel `disabled/` directory. Keeping `modules/` as the library and
  `enabled/` as a symlink *view* means every module always exists on disk and a
  toggle is just a symlink.

## Consequences

Load order has nowhere to live except the filenames themselves. Modules are
therefore prefixed with `NN-` (e.g. `10-env`, `30-functions`), ordered
lexically, with 10-unit gaps so new modules can be wedged between existing ones,
and the prefix ranges are documented in `CLAUDE.md`. Reordering means renaming a
file and its symlink. This is the accepted, permanent price of
filesystem-is-truth — no manifest will be introduced to centralize ordering.
