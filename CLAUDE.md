# bx — contract for anyone (human or agent) changing `~/.bin`

`~/.bin` is the single source of truth for the owner's shell. `~/.bashrc` is one
line, `init.sh` loads `enabled/*.sh`, `bx` manages the tree, `bx run bootstrap`
reproduces a machine. This file is the policy; **`bx lint` is the enforcement.**
Every rule below that carries an `L<n>` is checked by `bx lint`, by the
pre-commit hook, and by CI (`docs/adr/0005`). A rule without an `L` is reviewed
by reading, so state your compliance in the commit message.

## Non-negotiables

1. Automation lives under `~/.bin/`. Never `~/bin/`, never lines in `~/.bashrc`.
   `bx install` rewrites `~/.bashrc` to the hook and nothing else. **L9**
2. The filesystem is truth (`docs/adr/0001`). `enabled/` and `enabled-plugins/`
   hold only relative symlinks made by `bx enable` / `bx plugin enable`. **L4 L7**
3. Nothing OS-, release- or desktop-specific is hard-coded in a script. Package
   names go in `config/packages/<ID>[-<VERSION_ID>].list`; repos, identity and
   download URLs in `config/bootstrap.conf` (`docs/adr/0004`). **L8**
4. Every install-time step is an idempotent phase of `tools/bootstrap.sh` that
   reuses an existing tool. No README step says "then run X by hand". **L6**
5. Don't add what wasn't asked for. No speculative modules, flags, or tools.
6. `bx selftest` passes before every commit. The hook runs it for you.

## Three categories — pick one, never blend

| category | lives in | how it runs | rule |
|---|---|---|---|
| **module** | `modules/NN-name.sh` | sourced into every interactive shell | idempotent, silent, no side effects |
| **tool** | `tools/name.sh` | `bx run name`, or by bootstrap | does one thing, safe to re-run |
| **plugin** | `plugins/name/…` | symlinked to an external path | source stays here, target declared in header |

Runtime state (caches, logs) goes under `~/.cache/<slug>/` or
`~/.local/state/<slug>/`, never into the tree.

## Modules

- File name `NN-name.sh`, `NN` from the table, lowercase and dashes. **L1**
- First code line is the guard, slug = name with `-`→`_`: **L2**
  `[[ -n "${_BX_MOD_<slug>_LOADED:-}" ]] && return 0` then `_BX_MOD_<slug>_LOADED=1`
- Parses, never sources another module (extract to `lib/` or reorder), never
  `echo -e` (use `printf`). **L3** Output via `bx_info/ok/warn/err` from `lib/log.sh`.
- Public names short (`sandbox`, `nah`); internals prefixed `_<slug>_`.
- Scaffold with `bx new <name>`, enable with `bx enable <name>`.

| prefix | purpose | | prefix | purpose |
|---|---|---|---|---|
| `10-` | env: PATH, exports, shell options | | `50-` | tool integrations (docker, kubectl) |
| `20-` | aliases | | `60-` | prompt / completions |
| `30-` | functions | | `70-` | cosmetic / greetings |
| `40-` | dev tools / cheatsheets | | `80-` | motd — last, reads load state |

Ten-unit gaps are for wedging; a new range needs an ADR.

## Tools

- `tools/name.sh`, executable, bash shebang, then exactly: **L5**
  line 2 `# bx-purpose: <one line>` · line 3 `# bx-tool-kind: installer|runtime|check`
- `installer` → bootstrap calls it (`tools/name.sh` or `bx run name`). **L6**
  `runtime` → something else runs it (a keybinding, a menu). `check` → read-only.
- Idempotent: detect state, skip or act, say which. Print "Nothing to do" when
  nothing changed; bootstrap reads that. Back up before replacing a user file.
- Needs root? Use `sudo` per command; never require running the tool as root.
- Scaffold with `bx new <name> --tool`.

## Plugins

- Entrypoint header (all three): `# bx-purpose:`, `# bx-plugin-kind: <kind>`,
  `# bx-plugin-target: <exact external path>`. Kinds: `BX_PLUGIN_KINDS` in `bx`. **L7**
- Directory form: `plugins/<name>/<name>.<kind>.sh` + siblings; optional
  executable `postenable.sh` (gets `BX_PLUGIN_NAME`, `BX_PLUGIN_DIR`).
- New kind: add to `BX_PLUGIN_KINDS`, handle it in `_bx_plugin_apply`, document here.

## Bootstrap and config

- One phase per concern, in `tools/bootstrap.sh`: `phase` → check → `skip` /
  `run …` + `done_` / `failed`. Honour `--dry-run` via `run`. Reuse the tool;
  parse its output rather than re-deriving its state.
- Values come from `config/bootstrap.conf` (`KEY=VALUE`, parsed not sourced);
  precedence flag > `BX_<KEY>` env > file. New key: add to the required list in
  `load_config` and to **L8**.
- Package lists: one name per line, `-name` removes, `# comment`. Release file
  needs its base file. **L8**
- Changing `init.sh`: keep `_BX_INIT_PID=$BASHPID` unexported and the `*i*)`
  interactive guard; checks set `BX_FORCE_LOAD=1`. **L9**

## Docs

- README names every tool in its table; keep it minimal. **L10**
- This file stays ≤ 150 lines. **L10**
- Load-bearing decisions become `docs/adr/NNNN-slug.md`, sequential, with a
  `status:` front-matter line. **L10**

## Change procedure

**Add** — `bx new` (or `bx plugin new`), fill in, `bx enable`, wire into
bootstrap if it installs something, add the README row, `bx lint`, commit.
**Update** — keep the header lines and guard intact; if behaviour changes, the
tool must still skip when already applied; run the affected `tests/` file.
**Remove** — `bx disable` first, `git rm` the file, drop every reference
(`grep -rn <name>`), drop the README row, and say in the commit why.
**Rule change** — write the `L` check in `bx lint` first, add a case to
`tests/test_lint.sh`, then the line here, then the ADR if it's a decision.

## Enforcement

- `bx lint` — static, seconds. `bx selftest` — lint + doctor + load checks.
- `hooks/pre-commit` — lint + `tests/`; `bx install` activates it.
  `--no-verify` only with the reason in the commit message.
- `.github/workflows/ci.yml` — the same on every push, clean Ubuntu, shellcheck on.
- `tests/test_lint.sh` proves each rule catches what it claims.

## Git

Small commits, lowercase imperative subject (`add bx lint`). Explain the why
in the body. Agent-authored commits carry `Co-Authored-By`. Never push or open
a PR without being told to.
