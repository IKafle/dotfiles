# ADR 0004 — install-time dependencies are declarative config

**Status:** accepted · 2026-09-05

## Context

`tools/bootstrap.sh` is the single fresh-machine entrypoint. Its first version
hard-coded the Ubuntu package names, the Argos download, the todo repo and
the git identity. Anything that depends on the OS, its version or the desktop
therefore meant editing the installer, and a second distro meant forking it.

ADR-0001 says "no config file — the filesystem is truth". That decision is
about *which modules are enabled*, where a symlink is the fact. It does not
cover *what a fresh machine needs*, which is data, not state.

## Decision

- `config/bootstrap.conf` holds every install-time value bootstrap needs
  (repos, identity, download sources). `KEY=VALUE`; precedence is
  flag > `BX_<KEY>` env > file.
- `config/packages/<ID>.list` and `<ID>-<VERSION_ID>.list` hold package names,
  selected from `/etc/os-release` at run time (`ID_LIKE` as fallback).
  bootstrap never carries a package name itself.
- bootstrap detects `ID`, `VERSION_ID`, `VERSION_CODENAME`, `ID_LIKE`, the
  kernel release and the GNOME Shell major, and exports them as `BX_OS_*`
  for any tool it runs. Tools with their own detection (docker-init) keep it.

## Consequences

- Supporting a new distro or release is a new file under `config/packages/`,
  no script change.
- `enabled/` stays symlink-only; ADR-0001 is unchanged in scope.
- Only apt-family installs are implemented; other families are detected and
  skipped with a message naming the missing list.
