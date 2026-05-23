# `bx` — contract for agents working in `~/.bin`

`~/.bin` is the **single source of truth** for the owner's shell
customization (env, aliases, functions, prompt, motd). Everything is
loaded via `~/.bin/init.sh` and managed by the `bx` CLI. Custom logic
elsewhere (`~/bin/`, `~/.bashrc` body, loose scripts in `$HOME`) breaks
the contract.

## MUST FOLLOW

1. **New automation lives under `~/.bin/`** — never `~/bin/`, never lines added directly to `~/.bashrc`.
2. **Scaffold with `bx new <name>`** (or `--tool`). Only hand-create files if the scaffold genuinely doesn't fit.
3. **Modules MUST start with a load guard**: `[[ -n "${_BX_MOD_<NAME>_LOADED:-}" ]] && return 0; _BX_MOD_<NAME>_LOADED=1`. `bx new` writes it.
4. **Tools MUST declare `# bx-purpose: <one-liner>`** on line 2 so `bx tools` describes them.
5. **Enable via `bx enable <name>`** — never `ln -s` by hand. The filesystem in `enabled/` is the truth.
6. **Never edit `~/.bashrc` directly.** It should only contain `. ~/.bin/init.sh` (added by `bx install`).
7. **Don't add features beyond what was asked.** No speculative modules; no "while we're here" cleanups.
8. **Run `bx selftest` before committing.** All checks must pass.
9. **Preserve load order with NN- prefixes** (see table below). 10-unit gaps let you wedge in.
10. **No comments explaining WHAT the code does.** Only non-obvious WHY (invariant, workaround, gotcha).
11. **Keep CLAUDE.md accurate.** New folder, file convention, metadata field, subcommand, plugin kind, plugin form, env var, lifecycle stage → update this file in the same change.
12. **Decide about README.md.** If the change is user-visible (new command, new top-level folder, new tool/plugin, install flow change, removed capability) → update README.md in the same change.

## Architecture

```
~/.bin/
├── init.sh             master loader — sourced by ~/.bashrc
├── bx                  the CLI
├── lib/                shared helpers (color.sh, log.sh) — sourced by init.sh
├── modules/            shell modules — define funcs/aliases/env, no side effects
├── enabled/            symlinks → modules/  (filesystem = truth for what loads)
├── tools/              one-shot executables — installers, bootstrappers
├── plugins/            customizations that LIVE OUTSIDE ~/.bin/ — see below
├── enabled-plugins/    symlinks → plugins/  (mirror of plugins/'s on-state)
├── completions/        bash completions (auto-sourced by 60-prompt.sh)
├── claude/             config consumed by Claude Code (e.g. statusline.py)
└── docs/               notes & references
```

**Three categories**

- **Modules** (`modules/*.sh`) — *sourced* into every interactive bash. Idempotent. Shape the shell, no further side effects.
- **Tools** (`tools/*.sh`) — *executed* on demand via `bx run <name>`. Install software, bootstrap state.
- **Plugins** — *symlinked* into a tool-mandated external path (Argos, GNOME-ext, systemd). Source of truth stays in git. Two forms:
  - **file form**: `plugins/<name>.<kind>.sh` — single file. Use for one-file plugins.
  - **directory form**: `plugins/<name>/<name>.<kind>.sh` + siblings (`lib.sh`, `widgets/`, `postenable.sh`, …). Use when the plugin needs more than one file. The entrypoint file inside the directory carries the three `bx-plugin-*` headers; `enabled-plugins/<name>` symlinks to the entrypoint (not the directory) so `readlink -f` chains keep working.

**The symlink farm.** `init.sh` sources `enabled/*.sh` in lexical order. `bx enable/disable` create/remove symlinks. No config file, no parsing, no drift.

**State exported by init.sh**: `BX_VERSION`, `BX_HOME`, `BX_MODULES_LOADED`, `BX_MODULES_FAILED`, `BX_LOADED_AT`. The motd reads these.

**Shell guard is PID-scoped.** `init.sh` uses `_BX_INIT_PID=$BASHPID` (*not* exported). Exported guards leak into child shells — every new terminal would short-circuit and load nothing. Same-shell re-source no-ops because PID matches; new shells get a fresh PID. **If you add another guard, tie it to `$BASHPID` and leave it unexported.**

## NN- prefix ranges (modules)

| Prefix | Purpose |
|---|---|
| `10-` | env (`PATH`, exports, locale) |
| `20-` | aliases |
| `30-` | functions |
| `40-` | dev-tools / cheatsheets |
| `50-` | tool integrations (docker, kubectl, …) |
| `60-` | prompt / completions |
| `70-` | cosmetic / greetings |
| `80-` | motd (reserved — runs last, reads bx state) |

## File templates

**Module** (what `bx new` writes):
```bash
[[ -n "${_BX_MOD_my_helper_LOADED:-}" ]] && return 0
_BX_MOD_my_helper_LOADED=1
# code below
```

**Tool** (what `bx new --tool` writes):
```bash
#!/usr/bin/env bash
# bx-purpose: <one-liner>
set -euo pipefail
main() { :; }
main "$@"
```

**Plugin (file form)** — three required header lines:
```bash
# bx-purpose: <one-liner>
# bx-plugin-kind: argos
# bx-plugin-target: ~/.config/argos/mywidget.1s+.sh
```
`bx-plugin-target` is the EXACT external path (including tool-specific filename quirks like Argos's `.2s+.sh` refresh-rate suffix). Supported kinds: `argos`. Add a new kind by editing the `_bx_plugin_apply` case in `~/.bin/bx`, then document it here.

**Plugin (directory form)** — for plugins that need more than one file. Scaffold with `bx plugin new <name> --kind <k> --dir`:
```
plugins/<name>/
├── <name>.<kind>.sh    # entrypoint with the three bx-plugin-* headers
├── config.sh           # optional
├── lib.sh              # optional
├── postenable.sh       # optional — runs after `bx plugin enable <name>`
└── widgets/            # optional — any sub-files
```
The entrypoint filename MUST be `<name>.<kind>.sh` (matching the directory name). Selftest enforces this. The entrypoint resolves its siblings via `__DIR__=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")` then `. "$__DIR__/lib.sh"`. `enabled-plugins/<name>` symlinks to the entrypoint file, and the external target also points at the entrypoint file. If `postenable.sh` exists and is executable, `bx plugin enable <name>` runs it with `BX_PLUGIN_NAME` and `BX_PLUGIN_DIR` in the environment.

## Conventions

- **Public function names**: short, memorable (`sandbox`, `nah`, `shortcuts`). **Internal helpers**: prefix with the module slug + `_` (`_docker_clean_volumes`, `_motd_full`).
- **Output**: use `bx_info` / `bx_ok` / `bx_warn` / `bx_err` from `lib/log.sh` (respects `NO_COLOR`). Don't hand-roll ANSI.
- **Don't source one module from another.** Re-order via NN-prefix, or extract shared code into `lib/`.
- **Don't `echo -e`** — use `printf` or the logging helpers.

## bx commands

```bash
bx                       short status
bx ls                    list modules with ✔/✘
bx enable / disable      toggle a module (accepts short or full name)
bx edit <name>           $EDITOR a module
bx new <name> [--tool]   scaffold a module (or a tool)
bx reload                re-source enabled modules in this shell
bx doctor                health check
bx selftest              full regression check (load, guards, metadata)
bx run <tool>            execute a script in tools/
bx tools                 list tools
bx plugin <verb>         ls / enable / disable / new --kind / doctor
bx install               idempotently wire ~/.bashrc to source init.sh
bx help                  full help with examples
```

## Quick reference — where to put what

| Goal | Location | Register via |
|---|---|---|
| Shell function/alias/env | `modules/NN-name.sh` | `bx enable name` |
| One-shot installer | `tools/name.sh` | `bx run name` (auto) |
| Bash completion | `completions/<cmd>` | auto-sourced |
| Shared helper for modules | `lib/<name>.sh` | source from init.sh |
| External-mount customization | `plugins/<name>.<kind>.sh` (file) or `plugins/<name>/<name>.<kind>.sh` (dir) | `bx plugin enable <name>` |
| Workflow note | `docs/<topic>.md` | link from README |

## Git workflow

- Small focused commits, one logical change each.
- Match existing style: lowercase, imperative, terse. Examples: `harden docker-context-switch for production`, `add bx selftest`.
- Include `Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>` on agent-authored changes.
- Never push or open PRs without explicit user authorization.

## Doc-maintenance tests

Before stopping, apply both tests:

- **CLAUDE.md** — "Could a future agent, using only this file, reproduce the convention I just introduced?" If no → update CLAUDE.md.
- **README.md** — "Would a human reading just the README still know how to use the system?" If user-visible change (new command/folder/tool/plugin, install-flow change, removed capability) → update README.md.

When in doubt about an architectural question (module vs tool vs plugin? new NN- prefix range? new lifecycle stage?), **ask the user** before guessing. The answer materially affects how the file is loaded and discovered.
