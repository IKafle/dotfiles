# bx — contract for anyone (human or agent) changing `~/.bin`

`~/.bashrc` is one line, `init.sh` loads `enabled/*.sh`, `bx` manages the tree,
`bx run bootstrap` reproduces a machine. This file is the policy; **`bx lint` is
the enforcement.** A rule marked `L<n>` is checked by `bx lint` and the
pre-commit hook. A rule without one is reviewed by reading: state your
compliance in the commit message.

## Non-negotiables

1. Automation lives under `~/.bin/`. Never `~/bin/`, never lines in `~/.bashrc`
   or `~/.inputrc`; `bx install` rewrites `~/.bashrc` to the hook only. **L9**
2. The filesystem is truth (`docs/adr/0001`). `enabled/` and `enabled-plugins/`
   hold only relative symlinks made by `bx enable` / `bx plugin enable`. **L4 L7**
3. Nothing OS-, release- or desktop-specific is hard-coded. Package names go in
   `config/packages/<ID>[-<VERSION_ID>].list`; repos, identity, download URLs
   and font/plugin names in `config/bootstrap.conf` (`docs/adr/0004`). **L8**
4. Every install-time step is an idempotent phase of `tools/bootstrap.sh` that
   calls an existing tool. No doc says "then run X by hand". **L6**
5. Runtime state (caches, logs, stamps) goes under `~/.cache/<slug>/`,
   `~/.local/state/<slug>/` or `.git/`, never into the tree.

## Three categories — pick one, never blend

| category | lives in | how it runs | rule |
|---|---|---|---|
| **module** | `modules/NN-name.sh` | sourced into every interactive shell | idempotent, silent, no side effects |
| **tool** | `tools/name.sh` | `bx run name`, bootstrap, or a keybinding | one job, safe to re-run |
| **plugin** | `plugins/name/…` | symlinked to an external path | source stays here, target in header |

## Modules

- `NN-name.sh`, lowercase and dashes. **L1** Prefixes: `10` env · `20` aliases ·
  `30` functions · `40` dev tools · `50` integrations · `60` prompt · `70`
  cosmetic · `80` motd (last, reads load state). A new range needs an ADR.
- First code line is the guard, slug = name with `-`→`_`: **L2**
  `[[ -n "${_BX_MOD_<slug>_LOADED:-}" ]] && return 0` then `_BX_MOD_<slug>_LOADED=1`
- Never sources another module (extract to `lib/`), never `echo -e`. **L3**
  Output via `bx_info/ok/warn/err` from `lib/log.sh`.
- Anything that needs line editing (`bind`) is wrapped in `[[ $- == *i* ]]`:
  hooks and tests load modules non-interactively with `BX_FORCE_LOAD=1`.
- Public names short (`nah`, `serve`); internals `_<slug>_*`. `bx new <name>`.

## Tools

- Executable, bash shebang, then exactly: **L5**
  line 2 `# bx-purpose: <one line>` · line 3 `# bx-tool-kind: installer|runtime|check`
- `installer` → bootstrap calls it. **L6** `runtime` → a keybinding or menu
  runs it. `check` → read-only.
- Idempotent: detect, skip or act, say which. Print "Nothing to do" when nothing
  changed; bootstrap parses that. Back up before replacing a user file.
- `sudo` per command; never require running the tool as root.
- GNOME shortcuts: `lib/gnome-shortcut.sh` (`bx_shortcut_require`,
  `bx_shortcut_bind name combo cmd`). Bind to a `*-launcher.sh` tool that
  resolves the program at run time, not to a binary path.

## Plugins

- Header (all three): `# bx-purpose:`, `# bx-plugin-kind: <kind>`,
  `# bx-plugin-target: <exact external path>`. Kinds: `BX_PLUGIN_KINDS` in `bx`. **L7**
- Directory form: `plugins/<name>/<name>.<kind>.sh` + siblings; optional
  executable `postenable.sh` (gets `BX_PLUGIN_NAME`, `BX_PLUGIN_DIR`).
- New kind: add to `BX_PLUGIN_KINDS`, handle in `_bx_plugin_apply`, document here.

## Bootstrap and config

- One phase per concern: `phase` → check → `skip` / `run …` + `done_` /
  `failed`. Honour `--dry-run`. Reuse the tool; parse its output rather than
  re-deriving its state. A step that is a no-op outside GNOME prints
  `skip: not a GNOME session`, it does not fail.
- `config/bootstrap.conf` is `KEY=VALUE`, parsed not sourced; precedence flag >
  `BX_<KEY>` env > file. New key: add to `load_config`'s list and to **L8**.
- Package lists: one name per line, `-name` removes, `# comment`; a release file
  needs its base file. **L8**
- `init.sh`: keep `_BX_INIT_PID=$BASHPID` unexported and the `*i*)` guard. **L9**

## Platform facts (Ubuntu 26.04, GNOME 50, Wayland) — do not rediscover

- `gsettings` needs the session bus: bootstrap and the `*-init` tools work
  only from a terminal inside the desktop session.
- A freshly installed GNOME extension cannot be enabled until re-login. Queue
  it in `org.gnome.shell enabled-extensions` (see `argos_queue_enable`).
- Mutter refuses X11 grabs from XWayland. Rofi's wayland backend needs
  layer-shell, which GNOME lacks. Hence `rofi-launcher`: unset
  `WAYLAND_DISPLAY`, `-normal-window`, `-dpi` from `xrdb -query` (Xft.dpi),
  and a second Super-d kills it because click-outside can never reach it.
- Under `set -o pipefail`, `cmd | grep -q` fails when grep quits early and
  `cmd` dies of SIGPIPE (fc-list, anything long). Use `[[ -n "$(cmd | grep …)" ]]`.
- `fc-cache -f <dir>` leaves the parent cache stale; run `fc-cache -f`.
- geekbar's icons need the *Nerd Font* build of JetBrains Mono, not the apt
  package. `NERD_FONT_URL` installs it per-user.
- The `~/todo` repo is private: the smoke passes `--no-todo` when it cannot
  mount a local clone.

## Docs

- README names every tool; keep it to what a fresh laptop needs. **L10**
- This file ≤ 150 lines. **L10**
- Decisions become `docs/adr/NNNN-slug.md`, sequential, `status:` line. **L10**

## Change procedure

**Add** — `bx new` / `bx plugin new`, wire into bootstrap if it installs
something, README row, `bx lint`, commit. **Remove** — `bx disable`, `git rm`,
`grep -rn <name>` for references, README row, reason in the commit. **Rule
change** — the `L` check in `bx lint` first, a case in `tests/test_lint.sh`,
then the line here, then an ADR if it is a decision.

## Enforcement — no CI (`docs/adr/0006`)

- `hooks/pre-commit` (activated by `bx install`): `bx lint`, `tests/`, every
  module loads, `bootstrap --dry-run`. ~40 s. `--no-verify` only with the
  reason in the commit message.
- `bx run bootstrap-smoke`: HEAD bootstraps a clean `ubuntu:26.04` container,
  5–10 min, needs docker, stamps `.git/bx-smoked`. It clones **HEAD**: commit
  first. Run it when `tools/bootstrap*.sh`, `config/` or `init.sh` changed.
- `hooks/pre-push`: instant, advisory, reports whether HEAD carries the stamp.
- `bx selftest` = lint + doctor + load checks, on demand.

## Git

Small commits, lowercase imperative subject, the why in the body,
`Co-Authored-By` on agent commits. Never push or open a PR without being told.
