# `~/.bin` — the shell, one tree

`~/.bashrc` is one line: `. ~/.bin/init.sh`. `init.sh` sources every module
linked in `enabled/`. `bx` manages the tree. `bx run bootstrap` rebuilds a
machine.

## New machine

Run from a terminal inside the GNOME desktop session (the keyboard shortcuts
need the session bus):

```bash
git clone git@github.com:IKafle/dotfiles.git
bash dotfiles/tools/bootstrap.sh
```

Moves the clone to `~/.bin`, wires `~/.bashrc`, sets the git identity, installs
apt packages, gh, Claude Code + plugins, docker, the geekbar panel and its font,
binds Super-d (rofi) and Super-Enter (terminal), then verifies with a fresh
shell. One sudo prompt. Idempotent: re-run any time, done steps skip.

Still yours to do afterwards: add an SSH key (the todo repo is private), run
`claude` once to log in, log out and back in for the docker group. The Argos
panel activates on that first login.

| flag | effect |
|---|---|
| `--dry-run` | print the plan, change nothing |
| `--no-apt` `--no-gh` `--no-claude` `--no-docker` `--no-geekbar` `--no-rofi` `--no-terminal` `--no-vault` `--no-todo` | skip that step |
| `--todo-repo` `--git-name` `--git-email` | override a config value for this run |
| `--no-verify` | skip doctor / selftest / tests |

Installed things are data: `config/bootstrap.conf` (repos, identity, download
URLs, plugins) and `config/packages/<ID>[-<VERSION_ID>].list` (apt names per
`/etc/os-release`). Precedence: flag > `BX_<KEY>` env > file.

## Keyboard

| combo | does | notes |
|---|---|---|
| Super-d | rofi app menu; press again to close | runs on X11 via XWayland as a managed window — GNOME refuses X11 grabs, so that is the only way it gets focus. Theme and font: `config/rofi.rasi` |
| Super-Enter | new terminal | whatever the desktop's terminal is (Ptyxis on Ubuntu 26.04) |

Both are GNOME custom shortcuts set by `rofi-init` / `terminal-init` through
`lib/gnome-shortcut.sh`.

## Daily use

```bash
bx                    # status
bx ls / enable / disable <name>
bx edit <name>        # $EDITOR, reload on save
bx reload
bx run <tool>
bx plugin ls / enable / disable
bx doctor             # runtime health
bx lint               # structure contract (also the pre-commit hook)
bx selftest           # lint + doctor + load
```

## Layout

```
~/.bin/
├── init.sh            loader
├── bx                 the CLI
├── lib/               color, log, gnome-shortcut
├── modules/           NN-name.sh, sourced in order: 10 env · 20 aliases · 30 functions · 40 dev · 50 integrations · 60 prompt · 70 cosmetic · 80 motd
├── enabled/           symlinks → modules/  (the filesystem is the truth)
├── tools/             executables, bx run <tool>
├── plugins/           files that must live outside ~/.bin (geekbar → ~/.config/argos)
├── enabled-plugins/   symlinks → plugins/
├── completions/       bash completions
├── config/            bootstrap.conf, packages/, rofi.rasi
├── claude/            Claude Code status line
├── tests/             shell tests
├── hooks/             pre-commit: lint, tests, load, dry-run · pre-push: has HEAD passed the smoke?
└── docs/adr/          decisions with reasons
```

## Tools

| tool | purpose |
|---|---|
| `bootstrap` | fresh-machine entrypoint |
| `bootstrap-smoke` | bootstrap HEAD inside a clean `ubuntu:26.04` container; green run stamps `.git/bx-smoked` |
| `install-gh` | GitHub CLI from its apt repo |
| `docker-init` | Docker Engine + Compose |
| `claude-init` | Claude Code status line |
| `vault-init` | lay out `~/vault`, sweep loose files from `~` into it |
| `rofi-init` | bind Super-d to `rofi-launcher` |
| `rofi-launcher` | toggle rofi: X11 backend, GNOME DPI, managed window, `config/rofi.rasi` |
| `terminal-init` | bind Super-Enter to `terminal-launcher` |
| `terminal-launcher` | open the desktop's terminal (`xdg-terminal-exec`, then ptyxis, gnome-terminal, kgx) |
| `geekbar-doctor` | check geekbar's dependencies: Argos installed *and enabled*, Nerd Font, widgets |

## geekbar

An Argos panel for GNOME: system, network, dev, updates and audio widgets with
clickable actions and threshold notifications. Config: `plugins/geekbar/config.sh`.
Bootstrap installs Argos from upstream master (extensions.gnome.org still serves
the GNOME 3.32 build) and the JetBrainsMono Nerd Font the bar's icons need.

## MOTD

New terminals show system vitals, the todo card fed by `today --data` from
`~/todo`, and a shortcuts column. `bx: N modules loaded`, or a warning pointing
at `bx doctor`.

## Changing things

`CLAUDE.md` is the contract; `bx lint` enforces it, on demand and in the
pre-commit hook. No CI: commit, then `bx run bootstrap-smoke` when bootstrap,
config or `init.sh` changed (`docs/adr/0006`). Commit before smoking — the
container clones HEAD, not the working tree.
