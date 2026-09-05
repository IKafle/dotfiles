# `~/.bin` — shell customization, one tree

Everything the shell needs lives here. `~/.bashrc` contains one line,
`. ~/.bin/init.sh`, and `init.sh` sources every module linked in `enabled/`.
The `bx` CLI manages the tree.

## Install

```bash
git clone git@github.com:IKafle/dotfiles.git
bash dotfiles/tools/bootstrap.sh
```

Bootstrap moves the clone to `~/.bin`, wires `~/.bashrc`, sets the git
identity, installs packages, tools and plugins, and verifies with a fresh
shell. It is idempotent: `bx run bootstrap` any time, every step skips itself
when done. One sudo prompt. Log out and back in afterwards for GNOME
extensions and the docker group.

| flag | effect |
|---|---|
| `--dry-run` | print the plan, change nothing |
| `--no-apt` `--no-gh` `--no-claude` `--no-docker` `--no-geekbar` `--no-rofi` `--no-vault` | skip that step |
| `--todo-repo`, `--git-name`, `--git-email` | override a config value for this run |
| `--no-verify` | skip doctor / selftest / tests |

What gets installed is data, not script (`docs/adr/0004`):

- `config/bootstrap.conf` — repos, git identity, download sources, Claude plugins.
- `config/packages/<ID>.list` and `<ID>-<VERSION_ID>.list` — package names,
  picked from `/etc/os-release`. A new distro or release is a new file.
- Precedence: flag > `BX_<KEY>` env var > file.

## Daily use

```bash
bx                    # status
bx ls                 # modules, ✔ enabled / ✘ disabled
bx enable <name>      # link a module into enabled/
bx disable <name>     # unlink it
bx reload             # re-source in this shell
bx edit <name>        # open in $EDITOR, reload on save
bx new <name>         # scaffold a module   (--tool for a tool)
bx run <tool>         # run a tool from tools/
bx plugin <verb>      # ls / enable / disable / new / doctor
bx doctor             # health check (runtime)
bx lint               # contract check (structure) — also runs in the pre-commit hook
bx selftest           # lint + doctor + load checks
bx help
```

## Layout

```
~/.bin/
├── init.sh            loader, sourced by ~/.bashrc
├── bx                 the CLI
├── lib/               shared helpers
├── modules/           shell modules (functions, aliases, env)
├── enabled/           symlinks → modules/   — the filesystem is the truth
├── tools/             one-shot executables, run via bx run
├── plugins/           files that must live outside ~/.bin (Argos, …)
├── enabled-plugins/   symlinks → plugins/
├── completions/       bash completions, auto-sourced
├── config/            install-time data read by bootstrap; rofi.rasi, passed by the launcher
├── claude/            Claude Code status line
├── tests/             shell tests, run by the pre-commit hook and bootstrap
├── hooks/             git hooks (pre-commit: lint, tests, load, dry-run; pre-push: is HEAD smoked?)
└── docs/              notes and ADRs
```

Modules load in filename order. Prefixes: `10-` env, `20-` aliases,
`30-` functions, `40-` dev tools, `50-` integrations, `60-` prompt,
`70-` cosmetic, `80-` motd. Gaps of ten let you wedge new ones in.

## Tools

| tool | purpose |
|---|---|
| `bootstrap` | fresh-machine entrypoint |
| `install-gh` | GitHub CLI from its apt repo |
| `docker-init` | Docker Engine + Compose |
| `claude-init` | Claude Code status line |
| `vault-init` | lay out `~/vault`, sweep loose files from `~` into it |
| `rofi-init` | bind Super-d to the rofi launcher (GNOME custom shortcut) |
| `rofi-launcher` | what Super-d runs: toggle rofi, X11 backend, GNOME DPI, `config/rofi.rasi` |
| `geekbar-doctor` | check geekbar's dependencies and install |
| `bootstrap-smoke` | run bootstrap in a clean Ubuntu container, prove a fresh machine comes up green |

## Plugins

Some software wants its file at a fixed path. A plugin keeps the source in
`plugins/` and symlinks it there when enabled. The entrypoint declares
`bx-purpose`, `bx-plugin-kind` and `bx-plugin-target` in its header; a
directory-form plugin may add `postenable.sh`, run after linking.

**geekbar** is the one plugin: an Argos panel for GNOME with system, network,
dev, updates and audio widgets, clickable actions, and threshold
notifications. Configure it in `plugins/geekbar/config.sh`. Bootstrap installs
Argos from upstream master, since the extensions.gnome.org build only
declares GNOME 3.32.

## MOTD

New terminals show a dashboard: system vitals, the todo card fed by
`today --data` from `~/todo` (`docs/adr/0003`), and a shortcuts column. It
adapts to terminal width and reports `bx: N modules loaded`, or a warning
with `bx doctor` as the next step when something failed.

## Changing things

`CLAUDE.md` is the contract, and `bx lint` enforces it: every structural rule
has a numbered check that runs on demand and in the pre-commit hook `bx install`
activates. `bx run bootstrap-smoke` bootstraps HEAD in a fresh container and
`hooks/pre-push` reports whether HEAD has passed it; there is no CI
(`docs/adr/0006`). Decisions with a reason live in `docs/adr/`.
