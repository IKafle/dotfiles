# `~/.bin` — central source of truth for shell customization

This directory is the single entry point for all my shell automation.
`~/.bashrc` sources `~/.bin/init.sh` and nothing else interesting happens
outside this tree.

## Quick start

```bash
bx                # short status
bx ls             # list all modules, ✔ enabled / ✘ disabled
bx enable docker  # symlink a module into enabled/ (loads on next shell)
bx disable docker # remove the symlink
bx reload         # re-source enabled modules in THIS shell
bx edit aliases   # open module in $EDITOR; reload on save
bx read aliases   # print module contents to stdout (alias: cat, show)
bx new <name>     # scaffold a new module from template
bx doctor         # health check: missing symlinks, failed modules, bashrc hook
bx selftest       # full regression check (load, idempotency, guards, metadata)
bx run <tool>     # run a one-shot tool from tools/  (e.g. bx run docker-init)
bx tools          # list available tools
bx plugin ls      # list plugins (external customizations like Argos scripts)
bx plugin disable geekbar   # remove the external symlink (source kept)
bx plugin enable  geekbar   # restore the external symlink
bx install        # idempotently wire ~/.bashrc to source init.sh
bx help           # show all commands
```

## Layout

```
~/.bin/
├── init.sh           # master loader (~/.bashrc sources this)
├── bx                # the CLI command
├── CLAUDE.md         # contract for agents working in this tree
├── lib/              # shared helpers (color, logging)
├── modules/          # all available modules (each is a .sh file)
├── enabled/          # symlinks → modules/ — filesystem IS the truth
├── tools/            # one-shot scripts (installers, init scripts)
├── plugins/          # customizations that live OUTSIDE ~/.bin/ (Argos, etc.)
├── enabled-plugins/  # symlinks → plugins/ — like enabled/, for plugins
├── completions/      # bash completion scripts (auto-loaded by prompt module)
├── claude/           # config consumed by Claude Code
└── docs/             # notes & references
```

## Module naming convention

Modules are sourced in lexical order. Use a numeric prefix to control order:

| prefix | purpose                                                          |
|--------|------------------------------------------------------------------|
| `10-`  | environment (`PATH`, exports, locale)                            |
| `20-`  | aliases                                                          |
| `30-`  | functions                                                        |
| `40-`  | dev-tools / cheatsheets                                          |
| `50-`  | tool integrations (docker, kubectl, etc.)                        |
| `60-`  | prompt / completion                                              |
| `70-`  | greetings / holidays / cosmetic                                  |
| `80-`  | motd (must be last so it can read load state)                    |

10-unit gaps let you wedge new modules in between without renaming.

## Adding a new automation

```bash
bx new my-thing            # creates modules/45-my-thing.sh from template
bx enable my-thing         # symlink into enabled/
bx reload                  # source it into current shell
```

Every new automation belongs here. That's the rule.

## Failure mode visibility

- New terminals show a `bx: N modules loaded` line in the MOTD panel.
- Partial load → yellow `⚠ bx: M loaded, N failed — run \`bx doctor\``.
- `~/.bin/init.sh` never ran → red `⚠ bx: not loaded`.
- `bx doctor` prints the full diagnosis.

## Todo panel

New terminals (and `bx reload`) render a todo panel in the MOTD: a numbered
priority list of today's tasks (completed ones collapse to a dimmed `✓`), a
completion bar, and a `backlog N · done today N` footer. The panel is pure
presentation — it consumes `today --data` from the `~/todo` app (ADR-0003) and
never parses `todo.md`. With no plan it shows `no plan yet — run today`; all
done shows `all done ✓`. Skipped silently when the todo app isn't enabled.

The layout is responsive, chosen per render from the live terminal width: at
≥135 columns the panel sits **beside** the system panel as equal halves split
by a `│` divider at the midpoint; below that it falls back to stacking
full-width underneath. Resize, then open a new terminal (or `bx reload`) to
switch layouts.

## Tools (one-shot installers)

| tool                       | purpose                                  |
|----------------------------|------------------------------------------|
| `docker-init`              | install docker-ce + compose on Ubuntu    |
| `docker-desktop-init`      | install Docker Desktop (KVM-isolated)    |
| `vault-init`               | bootstrap `~/vault` workspace            |
| `claude-init`              | install Claude Code CLI                  |
| `geekbar-doctor`           | diagnose the geekbar plugin install      |
| `geekbar-test`             | render the bar + dropdown to stdout      |

Run with `bx run <tool>` or directly: `bash ~/.bin/tools/<tool>.sh`.

## Plugins (customizations that live outside `~/.bin/`)

Some tools insist on finding their config at a specific path — Argos
scripts at `~/.config/argos/`, GNOME extensions, systemd user units.
Plugins keep the source-of-truth file in `~/.bin/plugins/` (so it's in
git) and symlink it into the external location when enabled.

```bash
bx plugin ls                              # list plugins, ✔/✘
bx plugin enable geekbar                  # creates ~/.config/argos/geekbar.2s+.sh → plugins/
bx plugin disable geekbar                 # removes that symlink (source kept in plugins/)
bx plugin new mywidget --kind argos       # scaffold a new plugin (file form)
bx plugin new mywidget --kind argos --dir # scaffold a new plugin (directory form)
bx plugin doctor                          # verify each enabled plugin's external symlink
bx plugin help                            # full plugin subcommand reference
```

Plugins come in two forms. **File form** — `~/.bin/plugins/<name>.<kind>.sh`
— for single-file plugins:

```bash
# bx-purpose: GNOME panel widget showing system stats
# bx-plugin-kind: argos
# bx-plugin-target: ~/.config/argos/geekbar.2s+.sh
```

**Directory form** — `~/.bin/plugins/<name>/` with entrypoint
`<name>.<kind>.sh` plus sibling files (`lib.sh`, `widgets/`, etc.) — for
plugins that span multiple files. If `plugins/<name>/postenable.sh`
exists and is executable, `bx plugin enable <name>` runs it after
linking, with `BX_PLUGIN_NAME` and `BX_PLUGIN_DIR` in the environment.

| plugin    | kind  | target                              |
|-----------|-------|-------------------------------------|
| `geekbar` | argos | `~/.config/argos/geekbar.2s+.sh`    |

Supported kinds today: `argos`. Adding a new kind requires editing
`_bx_plugin_apply` in `bx` — see `CLAUDE.md` for the contract.

## Geekbar

`geekbar` is the directory-form Argos plugin under
`~/.bin/plugins/geekbar/`. It paints a compact GNOME top-panel readout
that refreshes every 2s and unfolds into a categorised dropdown of ~24
widgets covering:

- **System** — uptime, cpu (temp/freq/usage), ram, load, top processes,
  disk, I/O wait, battery.
- **Network** — connectivity, default route, vpn, public IP, listening
  ports, ssh-agent keys, DNS.
- **Dev** — git status of tracked repos, docker, kubectl context,
  cloud auth (AWS/GCP).
- **Updates** — apt upgrade counts (with a security-only sub-count).
- **Audio / extras** — volume + mic, weather, clock.

The dropdown menu items are clickable: kill a runaway process, open
`htop -p <pid>`, fetch a git repo, run `ncdu` on `/home`, copy the
cached public IP, restart Argos, etc. Click handlers route through
`plugins/geekbar/actions.sh`.

Geekbar also fires **edge-triggered desktop notifications** when a
metric crosses a warn/crit threshold (CPU temp, RAM, disk, battery,
APT security count, …). State lives under
`~/.cache/geekbar/` and `~/.local/state/geekbar/` so notifications
don't repeat until the bucket changes.

```bash
bx plugin enable geekbar     # symlink into ~/.config/argos/
bx enable geekbar-track      # shell hook: refresh git/cloud caches on cd / aws login
bx run geekbar-doctor        # verify the install, missing deps, stale state
bx run geekbar-test          # render the bar + dropdown to stdout for inspection
```

Customisation lives in **one file**: `~/.bin/plugins/geekbar/config.sh`.
Edit the `BAR_WIDGETS` array (what shows in the panel), the
`MENU_SECTIONS` / `MENU_SECTION_<name>` arrays (what shows in the
dropdown and in what order), and the per-widget thresholds
(`CPU_TEMP_WARN`, `RAM_PCT_CRIT`, `DISK_PCT_WARN`, …).
