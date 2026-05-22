# `bx` — contract for agents working in `~/.bin`

You are an AI agent acting on this repository. Read this file before
making any changes.

`~/.bin` is the **single source of truth** for the owner's shell
customization. Everything that shapes their interactive shell — env,
aliases, functions, prompts, docker context switching, motd — lives here
and is managed by the `bx` CLI. If you add an automation anywhere else,
or wire it into `~/.bashrc` directly, you have broken the contract.

---

## MUST FOLLOW

1. **Every new automation lives under `~/.bin/`.** Never `~/bin/`, never
   loose scripts in `$HOME`, never one-off lines in `~/.bashrc`.
2. **Use `bx new <name>` to create a new module**, or
   `bx new <name> --tool` for a one-shot installer. Do not hand-create
   files in `modules/` or `tools/` unless the scaffold genuinely doesn't
   fit — and then still match the conventions below.
3. **Modules MUST be idempotent** — start with a load guard:
   `[[ -n "${_BX_MOD_<NAME>_LOADED:-}" ]] && return 0`. `bx new` writes
   this for you. Re-sourcing a module must not duplicate work.
4. **Tools MUST declare `# bx-purpose: <one-liner>`** near the top so
   `bx tools` can list them with a real description.
5. **Enable a module via symlink in `enabled/`** — use `bx enable <name>`,
   never `ln -s` by hand. The filesystem in `enabled/` is the truth for
   what `init.sh` loads.
6. **Never edit `~/.bashrc` directly.** The only line it needs is
   `. ~/.bin/init.sh` (added by `bx install`). All customization happens
   inside `~/.bin/`.
7. **Don't add features beyond what was asked.** No speculative modules,
   no "while we're here" cleanups outside the task scope.
8. **Test in a subshell before committing**:
   `bash -lic 'bx doctor && bx ls'`. If `bx doctor` reports issues, fix
   them before you stop.
9. **Preserve module load order with numeric prefixes** (`10-`, `20-`,
   …, `80-`). 10-unit gaps let you wedge in without renaming.
10. **Don't write comments explaining WHAT the code does.** Only the
    non-obvious WHY (a hidden invariant, a workaround, a surprising
    behavior).
11. **Keep this CLAUDE.md accurate.** If you introduce any architectural
    concept this file doesn't already explain — a new top-level folder,
    a new file-type convention, a new metadata field, a new `bx`
    subcommand, a new plugin kind, a new env var the loader exports, a
    new lifecycle stage — you MUST update CLAUDE.md in the same change.
    See [Keeping this document accurate](#keeping-this-document-accurate)
    for the test.

---

## Architecture

```
~/.bin/
├── init.sh             master loader — sourced by ~/.bashrc
├── bx                  the CLI; on $PATH because ~/.bin is on $PATH
├── lib/                shared helpers (color, log) — sourced by init.sh
│   ├── color.sh        BX_C_* color codes; respects NO_COLOR
│   └── log.sh          bx_info / bx_ok / bx_warn / bx_err / bx_dim / bx_kv
├── modules/            ALL available shell modules (.sh files)
│   ├── 10-env.sh       PATH, JAVA_HOME, EDITOR, etc.
│   ├── 20-aliases.sh   shell aliases
│   ├── 30-functions.sh ~50 utility functions (legacy, large)
│   ├── 40-dev-tools.sh `shortcuts` function — full cheatsheet
│   ├── 50-docker.sh    sandbox/main/docker-context functions
│   ├── 60-prompt.sh    git-aware PS1 + completion loader
│   ├── 70-holidays.sh  date-driven greetings
│   └── 80-motd.sh      MOTD panel (must run last — reads bx state)
├── enabled/            symlinks → modules/  (filesystem = truth)
├── tools/              one-shot runnable scripts (NOT sourced)
│   ├── claude-init.sh         each has `# bx-purpose: ...`
│   ├── docker-init.sh
│   ├── docker-desktop-init.sh
│   └── vault-init.sh
├── plugins/            customizations that LIVE OUTSIDE ~/.bin/
│   └── geekbar.argos.sh       <name>.<kind>.sh — source of truth in git
├── enabled-plugins/    symlinks → plugins/ — like enabled/ but for plugins
├── completions/        bash completion scripts (auto-sourced by 60-prompt.sh)
├── claude/             config consumed by Claude Code (statusline.py)
└── docs/               READMEs, notes, references
```

**Sourced vs runnable vs externally-mounted — three categories**

- `modules/*.sh` are **sourced** into every interactive bash via
  `init.sh`. They define functions, aliases, env vars. They must not
  have side effects beyond shell-environment shaping.
- `tools/*.sh` are **executed** on demand via `bx run <name>` or
  `bash ~/.bin/tools/<name>.sh`. They install software, bootstrap
  workspaces, perform one-time setup.
- `plugins/<name>.<kind>.sh` are **mounted into an external location**
  (a tool-mandated path outside `~/.bin/`) via symlink. The source of
  truth stays in `plugins/`, version-controlled with the rest of your
  dotfiles. Examples: Argos panel scripts (`~/.config/argos/`), GNOME
  extensions, systemd user units. Managed with `bx plugin ls/enable/
  disable/new/doctor`.

**The symlink farm**

`init.sh` iterates `enabled/*.sh` in lexical order and sources each
one. Each entry is a symlink pointing back into `modules/`. To enable a
module: `bx enable <name>` creates the symlink. To disable: `bx disable
<name>` removes it. The filesystem itself encodes "what is on" — no
config file, no parsing, no drift.

**State exposed to the shell**

After `init.sh` runs, these env vars are set:
- `BX_VERSION` — semver of the loader
- `BX_HOME` — absolute path (`/home/<user>/.bin`)
- `BX_MODULES_LOADED` — count of modules that sourced cleanly
- `BX_MODULES_FAILED` — comma-separated list (empty on full success)
- `BX_LOADED_AT` — epoch seconds when the loop finished

The MOTD module reads these to print the `bx: N modules loaded` line.

---

## Adding a new automation — step by step

### Adding a module (shell function/alias/env var)

```bash
bx new my-helper                         # creates modules/45-my-helper.sh
                                         # with a load guard already in place
$EDITOR ~/.bin/modules/45-my-helper.sh   # OR: bx edit my-helper
bx enable my-helper                      # symlink into enabled/
eval "$(bx reload)"                      # apply to current shell
bx doctor                                # confirm clean load
```

If your module needs a specific load order, rename it with a different
NN- prefix:
- `10-` env-only (sets `PATH`, exports)
- `20-` aliases
- `30-` functions
- `40-` interactive helpers / cheatsheets
- `50-` tool integrations (docker, kubectl, gcloud, etc.)
- `60-` prompt / completions
- `70-` cosmetic / greetings
- `80-` motd (reserved — runs last)

### Adding a tool (one-shot installer/init script)

```bash
bx new install-foo --tool                # creates tools/install-foo.sh
$EDITOR ~/.bin/tools/install-foo.sh      # implement; keep `# bx-purpose:`
bx run install-foo                       # test
```

Tools should be idempotent (safe to re-run), check prerequisites, and
print clear progress. They MUST start with:
```bash
#!/usr/bin/env bash
# bx-purpose: one-line description shown by `bx tools`
```

### Adding bash completion

Drop the completion script into `~/.bin/completions/`. The `60-prompt.sh`
module sources every file in that directory automatically. No
registration needed.

### Adding a plugin (customization that lives outside ~/.bin/)

Plugins are for things some other tool insists on finding at a specific
path (Argos at `~/.config/argos/`, GNOME extensions at
`~/.local/share/gnome-shell/extensions/`, systemd user units at
`~/.config/systemd/user/`). The source-of-truth file lives in
`~/.bin/plugins/<name>.<kind>.sh`; `bx plugin enable` creates a symlink
at the external location.

```bash
bx plugin new mywidget --kind argos      # scaffolds plugins/mywidget.argos.sh
$EDITOR ~/.bin/plugins/mywidget.argos.sh # implement
bx plugin enable mywidget                # symlinks into ~/.config/argos/
bx plugin doctor                         # verify external symlinks healthy
```

Plugin files MUST declare three header fields:
```bash
# bx-purpose: <one-liner>
# bx-plugin-kind: argos
# bx-plugin-target: ~/.config/argos/mywidget.1s+.sh
```

`bx-plugin-target` is the EXACT path (including any tool-specific filename
encoding like Argos's `.1s+.sh` refresh-rate suffix). `bx plugin enable`
creates `target → source` as a symlink; disable removes the target only
if it still points at our source.

**Supported plugin kinds**: `argos` (chmod-based via symlink, since Argos
just runs anything executable in its dir).

**Adding a new kind**: edit `_bx_plugin_apply` in `~/.bin/bx` to add a
case for the new kind, then document it in this file. Likely candidates:
- `gnome-extension`: enable/disable via `gnome-extensions enable/disable`
- `systemd-user-unit`: link into `~/.config/systemd/user/` and `systemctl --user enable/disable`
- `autostart`: link `.desktop` file into `~/.config/autostart/`

---

## Conventions

### Module file template (what `bx new` writes)

```bash
# 45-my-helper.sh — bx module
# Sourced by ~/.bin/init.sh into every interactive bash.
# Enabled via:  bx enable my-helper
# Edit via:     bx edit my-helper

[[ -n "${_BX_MOD_my_helper_LOADED:-}" ]] && return 0
_BX_MOD_my_helper_LOADED=1

# Your code below.
```

### Tool file template (what `bx new --tool` writes)

```bash
#!/usr/bin/env bash
# bx-purpose: <one-liner>

set -euo pipefail

main() {
    # implementation
    :
}

main "$@"
```

### Function naming inside modules

- Public functions visible to the user: short, memorable
  (`sandbox`, `nah`, `shortcuts`).
- Internal helpers: prefix with the module's slug + `_`
  (`_docker_clean_volumes`, `_motd_full`). Removes naming collisions
  when modules grow.

### Color and logging

If your module prints user-facing output, use the shared helpers:
```bash
# Already sourced by init.sh — available everywhere.
bx_info "doing X"      # cyan →
bx_ok   "done"         # green ✔
bx_warn "watch out"    # yellow ⚠
bx_err  "failed"       # red ✘
```
Don't hand-roll ANSI escape codes — `lib/color.sh` already respects
`NO_COLOR` and terminal-detection.

---

## Common bx operations

```bash
bx                       # short status
bx ls                    # list modules with ✔/✘
bx enable <name>         # turn on
bx disable <name>        # turn off
bx reload                # re-source enabled modules in current shell
bx edit <name>           # $EDITOR a module
bx new <name> [--tool]   # scaffold
bx doctor                # health check
bx run <tool>            # execute a tool
bx tools                 # list tools
bx install               # idempotently add source line to ~/.bashrc
bx help                  # full help with examples
```

Module names accept either short form (`docker`) or full filename
(`50-docker.sh`). The resolver finds them either way.

---

## Pitfalls — what NOT to do

| Anti-pattern                                       | Why it's wrong                                              | Correct way                            |
|----------------------------------------------------|--------------------------------------------------------------|----------------------------------------|
| Add an automation under `~/.local/bin/` or `~/bin/`| Breaks "single source of truth"                              | Put it in `~/.bin/modules/` or `tools/`|
| Edit `~/.bashrc` directly                          | Future `bx install` may overwrite; bypasses doctor           | All customization → modules            |
| Write `ln -s` by hand into `enabled/`              | Easy to typo; doesn't validate the target exists             | `bx enable <name>`                     |
| Omit the `_LOADED` guard in a module               | Re-sourcing duplicates aliases / re-runs init code           | Start with the template guard          |
| Add a tool without `# bx-purpose:`                 | `bx tools` shows `—` instead of a description                | Add it on line 2                       |
| Source a module from another module                | Hidden dependency outside the symlink farm                   | Re-enable / re-order; or use `lib/`    |
| Use `echo -e` for colored output                   | Not portable; ignores NO_COLOR                               | Use `bx_info`/`bx_ok`/etc. from log.sh |
| Write multi-paragraph docstrings or banner comments| Noise; the contract is here, not in every file               | One-line `#` header is enough          |

---

## Testing changes

Always validate before declaring done:

```bash
# 1. Subshell smoke test — does init.sh load cleanly?
bash -c '. ~/.bin/init.sh && echo "loaded=$BX_MODULES_LOADED failed=[${BX_MODULES_FAILED:-}]"'
# Expected: loaded=8 (or however many), failed=[]

# 2. Doctor — full health check
bx doctor
# Expected: "all checks passed"

# 3. Interactive shell sanity — modules still produce their functions/aliases
bash -lic 'type sandbox; type shortcuts; alias en' | head

# 4. If you changed a tool, dry-run it
bash ~/.bin/tools/<name>.sh --help 2>&1 | head
```

Failing any of these means more work to do; don't stop.

---

## Quick reference — where to put what

| You want to…                                  | Put it in                          | Register via      |
|-----------------------------------------------|------------------------------------|-------------------|
| Define a new shell function/alias             | `modules/NN-name.sh`               | `bx enable name`  |
| Add a one-shot installer                      | `tools/name.sh`                    | (auto, via `bx run`) |
| Add a bash completion script                  | `completions/<cmd>`                | (auto)            |
| Add a shared helper used by multiple modules  | `lib/<name>.sh`                    | source from init.sh or module |
| Manage an Argos / GNOME-ext / systemd-unit    | `plugins/<name>.<kind>.sh`         | `bx plugin enable <name>` |
| Document a workflow                           | `docs/<topic>.md`                  | link from README  |
| Configure an external tool (e.g. Claude Code) | `claude/<file>` or similar         | tool reads it directly |

---

## Git workflow

- Commits should be focused and small (one logical change per commit).
- Match the existing commit-message style: lowercase, imperative, terse.
  Recent examples: `harden docker-context-switch for production`,
  `add concrete usage examples to bx help`.
- Always include the Co-Authored-By trailer when an agent authored the
  change.
- Never push or open PRs without explicit user authorization.

---

## Keeping this document accurate

This file is the handover contract for every future agent. It only
works if it stays in sync with the code. Apply this test before you
stop work:

> **"Could a future agent, using only what's in CLAUDE.md, reproduce
> the convention I just introduced?"**

If the answer is **no**, update CLAUDE.md in the same change.

### What requires a doc update (non-exhaustive)

- A new top-level folder under `~/.bin/` (e.g. `hooks/`, `cron/`, `state/`)
- A new file-type convention (e.g. `*.bxconf` files read by the loader)
- A new metadata field (e.g. `# bx-requires:`, `# bx-os:`, …)
- A new `bx` subcommand or flag
- A new env var exported by `init.sh` (anything `BX_*`)
- A new lifecycle stage (e.g. a post-load hook mechanism)
- A new naming convention or NN- prefix range
- A change to how `enabled/` works (the symlink semantics)
- A new shared `lib/` helper that modules are expected to use
- Renaming or relocating any file path mentioned in this document

### What does NOT require a doc update

- Adding a routine module that fits an existing prefix range and uses
  the standard template (`bx new` did the right thing — that's the
  convention CLAUDE.md already describes)
- Adding a routine tool with `# bx-purpose:` (already covered)
- Fixing a bug inside an existing module/tool
- Editing a function's implementation without changing its name or
  signature
- Adding a bash completion under `completions/`

### How to update

1. Add the new concept to the relevant section (architecture diagram,
   conventions, quick reference table, pitfalls — wherever it fits).
2. If the concept is structural enough that an agent might miss it,
   also add a line to **MUST FOLLOW** at the top.
3. Stage the CLAUDE.md change in the **same commit** as the code
   change. Don't ship the convention without the documentation.

If you're refactoring something that's already documented, update both
in lockstep — code and doc.

---

## If you're unsure

Read these in order, top-down, until you have your answer:
1. `bx help` — concrete command syntax + examples
2. This file (`CLAUDE.md`) — conventions, architecture, rules
3. `~/.bin/README.md` — user-facing intro
4. The module/tool source itself — the actual behavior

If still unsure, ASK the user before making structural changes. Never
guess on architectural questions like "should this be a module or a
tool?" — the answer materially affects how the file is loaded and
discovered.
