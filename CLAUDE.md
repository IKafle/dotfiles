# `bx` — contract for agents working in `~/.bin`

`~/.bin` is the single source of truth for the owner's shell customization. Everything loads via `~/.bin/init.sh` and is managed by the `bx` CLI. Custom logic elsewhere (`~/bin/`, `~/.bashrc` body, loose scripts in `$HOME`) breaks the contract.

## MUST FOLLOW

1. New automation lives under `~/.bin/` — never `~/bin/`, never lines added directly to `~/.bashrc`.
2. Scaffold with `bx new <name>` (or `--tool`). Only hand-create files if the scaffold doesn't fit.
3. Modules MUST start with a load guard: `[[ -n "${_BX_MOD_<NAME>_LOADED:-}" ]] && return 0; _BX_MOD_<NAME>_LOADED=1`.
4. Tools MUST declare `# bx-purpose: <one-liner>` on line 2.
5. Enable via `bx enable <name>` — never `ln -s` by hand. `enabled/` is the truth.
6. Never edit `~/.bashrc` directly. It should only contain `. ~/.bin/init.sh`.
7. Don't add features beyond what was asked. No speculative modules.
8. Run `bx selftest` before committing.
9. Preserve load order with NN- prefixes (table below). 10-unit gaps let you wedge in.
10. No comments explaining WHAT the code does. Only non-obvious WHY.
11. **Keep CLAUDE.md ≤ 150 lines.** If your edit pushes it over, trim before stopping.
12. Update README.md for user-visible changes (new command/folder/tool/plugin, install-flow change, removed capability).

## Architecture

```
~/.bin/
├── init.sh             master loader — sourced by ~/.bashrc
├── bx                  the CLI
├── lib/                shared helpers — sourced by init.sh
├── modules/            shell modules — define funcs/aliases/env
├── enabled/            symlinks → modules/  (filesystem = truth)
├── tools/              one-shot executables — `bx run <name>`
├── plugins/            customizations living OUTSIDE ~/.bin/
├── enabled-plugins/    symlinks → plugins/
├── completions/        bash completions (auto-sourced)
├── claude/             config consumed by Claude Code
└── docs/               notes, references & adr/ (architecture decision records)
```

**Three categories**
- **Modules** (`modules/*.sh`) — *sourced* into every interactive bash. Idempotent, no side effects.
- **Tools** (`tools/*.sh`) — *executed* on demand via `bx run`. Install software, bootstrap state.
- **Plugins** — *symlinked* into a tool-mandated external path (Argos, etc.). Two forms:
  - **file**: `plugins/<name>.<kind>.sh`
  - **directory**: `plugins/<name>/<name>.<kind>.sh` + siblings (`lib.sh`, `postenable.sh`). Entrypoint filename MUST match directory name. `enabled-plugins/<name>` symlinks to the entrypoint, not the directory.

`init.sh` sources `enabled/*.sh` in lexical order. No config file — filesystem is truth (rationale: `docs/adr/0001-filesystem-is-truth.md`). Record load-bearing, hard-to-reverse decisions as new ADRs in `docs/adr/` (sequential `NNNN-slug.md`).

**Init guard is PID-scoped.** `init.sh` uses `_BX_INIT_PID=$BASHPID` (*not* exported) — exported guards leak into child shells and break new terminals. If you add another guard, tie it to `$BASHPID` and leave it unexported.

State exported by init.sh: `BX_VERSION`, `BX_HOME`, `BX_MODULES_LOADED`, `BX_MODULES_FAILED`, `BX_LOADED_AT`.

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

## Plugin headers (top of entrypoint, all three required)

```
# bx-purpose: <one-liner>
# bx-plugin-kind: argos
# bx-plugin-target: ~/.config/argos/mywidget.1s+.sh
```

`bx-plugin-target` is the EXACT external path including tool-specific filename quirks (e.g. Argos's `.2s+.sh` refresh-rate suffix). Supported kinds: `argos`. Add a new kind by editing `_bx_plugin_apply` in `~/.bin/bx`, then document here.

Directory-form entrypoints resolve siblings via `__DIR__=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")`. If `postenable.sh` exists and is executable, `bx plugin enable` runs it with `BX_PLUGIN_NAME` and `BX_PLUGIN_DIR` set.

## Conventions

- Public function names: short, memorable (`sandbox`, `nah`). Internal helpers: prefix with module slug + `_` (`_docker_clean_volumes`).
- Output: use `bx_info` / `bx_ok` / `bx_warn` / `bx_err` from `lib/log.sh`. Don't hand-roll ANSI. Don't `echo -e` — use `printf`.
- Don't source one module from another. Reorder via NN-prefix or extract shared code into `lib/`.

## bx commands

Run `bx help` for the full list. Most-used: `bx ls`, `bx enable/disable <name>`, `bx new <name> [--tool]`, `bx reload`, `bx doctor`, `bx selftest`, `bx run <tool>`, `bx plugin <verb>`.

## Git workflow

Small focused commits, one logical change each. Lowercase imperative messages (`add bx selftest`, `harden docker-context-switch`). Include `Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>` on agent-authored changes. Never push or open PRs without explicit authorization.

## Before stopping

- **CLAUDE.md**: could a future agent reproduce the convention I just introduced? If no → update it. If file > 150 lines → trim it.
- **README.md**: user-visible change (new command/folder/tool/plugin, install-flow change, removed capability)? → update it.
- Architectural ambiguity (module vs tool vs plugin? new NN- prefix range?) → ask the user.
