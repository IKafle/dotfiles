  #!/usr/bin/env bash
  # docker-context-switch.sh
  # ──────────────────────────────────────────────────────────────────────────────
  # Source this file to get three shell functions for switching between Docker
  # contexts without friction. Add this to your .bashrc or shell config:
  #
  #   . ~/.bin/docker-context-switch.sh
  #
  # Functions provided:
  #   sandbox        switch to Docker Desktop (isolated sandbox for AI agents)
  #   main           switch to Docker Engine (normal dev environment)
  #   docker-context show current context, all contexts, and guidance
  #
  # Context names (registered by Docker):
  #   default        → Docker Engine (system socket)
  #   desktop-linux  → Docker Desktop (KVM VM socket)
  # ──────────────────────────────────────────────────────────────────────────────

  # Guard: we use bash arrays, [[ ]], and ${BASH_SOURCE}. Reject other shells
  # with a clear message rather than a cryptic syntax error.
  # (POSIX test, since bashisms below would fail in dash/sh.)
  if [ -z "${BASH_VERSION:-}" ]; then
      echo "Error: docker-context-switch.sh requires bash (current shell is not bash)" >&2
      return 1 2>/dev/null || exit 1
  fi

  # Guard: this file must be sourced (functions are useless when executed).
  # ${BASH_SOURCE[0]} differs from $0 only when sourced.
  if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
      echo "Error: docker-context-switch.sh must be sourced, not executed" >&2
      echo "  → Add this to your ~/.bashrc:" >&2
      echo "  →   . ~/.bin/docker-context-switch.sh" >&2
      exit 1
  fi

  # Guard: re-sourcing this file is a no-op.
  [[ -n "${_DCS_LOADED:-}" ]] && return 0
  _DCS_LOADED=1

  # ── Constants ──────────────────────────────────────────────────────────────

  _DCS_CTX_ENGINE="default"
  _DCS_CTX_DESKTOP="desktop-linux"

  # ── Internal helpers ───────────────────────────────────────────────────────

  _dcs_docker_installed() {
      # Check if docker binary is available
      if ! command -v docker >/dev/null 2>&1; then
          echo "Error: docker is not installed or not in PATH"
          echo "  → Install Docker Engine:   bash ~/.bin/docker-init.sh"
          echo "  → Install Docker Desktop:  bash ~/.bin/docker-desktop-init.sh"
          return 1
      fi
  }

  _dcs_docker_supports_context() {
      # docker context was added in 19.03. Older docker has no subcommand.
      docker context --help >/dev/null 2>&1 || {
          echo "Error: this docker is too old to support contexts"
          echo "  → docker context requires docker >= 19.03"
          echo "  → Reinstall:  bash ~/.bin/docker-init.sh"
          return 1
      }
  }

  _dcs_can_use_docker() {
      # Check if user can read docker config (no daemon needed for `context ls`).
      # We force LC_ALL=C to keep error messages stable for matching, but only here.
      local err
      err=$(LC_ALL=C docker context ls 2>&1 >/dev/null) || {
          # Disambiguate the failure
          if [[ "$err" == *"permission denied"* ]] || \
             [[ "$err" == *"cannot connect"* && "$err" == *"docker.sock"* ]]; then
              echo "Error: cannot access docker (permission denied on socket)"
              echo "  → Add yourself to the docker group:"
              echo "  →   sudo usermod -aG docker $(id -un 2>/dev/null || echo \$USER)"
              echo "  → Then log out and back in, or run: newgrp docker"
              return 1
          fi
          if groups 2>/dev/null | tr ' ' '\n' | grep -qx docker || [[ ${EUID:-$(id -u)} -eq 0 ]]; then
              echo "Error: docker command failed unexpectedly"
              echo "  → Run: docker context ls  (to see full error)"
              [[ -n "$err" ]] && echo "  → docker said: ${err%%$'\n'*}"
          else
              echo "Error: user '$(id -un)' cannot run docker commands"
              echo "  → Add yourself to the docker group:"
              echo "  →   sudo usermod -aG docker $(id -un)"
              echo "  → Then log out and back in, or run: newgrp docker"
          fi
          return 1
      }
  }

  _dcs_warn_docker_host() {
      # DOCKER_HOST silently overrides the active context — docker uses the
      # env var's socket regardless of what `context use` records. Warn loudly.
      # Args: $1 (optional) — "block" to make this a hard error for switch ops.
      if [[ -n "${DOCKER_HOST:-}" ]]; then
          if [[ "${1:-}" == "block" ]]; then
              echo "Error: DOCKER_HOST is set ($DOCKER_HOST)"
              echo "  → DOCKER_HOST overrides whichever context is selected."
              echo "  → Switching now would silently have no effect."
              echo "  → Unset it first, then retry:"
              echo "  →   unset DOCKER_HOST"
              echo ""
              return 1
          fi
          echo "Warning: DOCKER_HOST is set ($DOCKER_HOST)"
          echo "  → docker is using this socket, ignoring the configured context."
          echo "  → To use contexts again:  unset DOCKER_HOST"
          echo ""
          return 0
      fi
  }

  _dcs_context_exists() {
      # Check if a context name exists in docker config (exact match).
      local ctx="$1"
      LC_ALL=C docker context ls --format '{{.Name}}' 2>/dev/null \
          | grep -Fxq -- "$ctx"
  }

  _dcs_current_context() {
      # Print the effective current context. NOTE: when DOCKER_HOST is set,
      # this returns "default" regardless of what's in config — DOCKER_HOST
      # acts as an implicit override. We warn separately via _dcs_warn_docker_host.
      local out
      if out=$(LC_ALL=C docker context show 2>/dev/null) && [[ -n "$out" ]]; then
          printf '%s\n' "$out"
          return 0
      fi
      # Fallback for older docker without `context show` — parse ls.
      LC_ALL=C docker context ls --format '{{.Name}} {{.Current}}' 2>/dev/null \
          | awk '$NF=="true"{$NF=""; sub(/ +$/,""); print; exit}'
  }

  _dcs_configured_context() {
      # Print the context recorded in ~/.docker/config.json (the "currentContext"
      # key), independent of DOCKER_HOST. Falls back to "default" when missing.
      # Prints "(config unreadable)" on malformed JSON so the caller can show it.
      local cfg="${HOME:-~}/.docker/config.json"
      if [[ ! -f "$cfg" ]]; then
          printf '%s\n' "default"
          return 0
      fi
      if command -v jq >/dev/null 2>&1; then
          local out
          if ! out=$(jq -r '.currentContext // "default"' "$cfg" 2>/dev/null); then
              printf '%s\n' "(config unreadable)"
              return 0
          fi
          [[ -z "$out" || "$out" == "null" ]] && out="default"
          printf '%s\n' "$out"
          return 0
      fi
      # Fallback: grep/sed. Only matches a top-level-ish "currentContext": "value".
      # Reject obviously malformed files (no balanced braces) so we don't lie.
      if ! grep -q '^[[:space:]]*{' "$cfg" 2>/dev/null; then
          printf '%s\n' "(config unreadable)"
          return 0
      fi
      local val
      val=$(grep -E '"currentContext"[[:space:]]*:' "$cfg" 2>/dev/null \
          | sed -E 's/.*"currentContext"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' \
          | head -n1)
      if [[ -z "$val" ]]; then
          # Key may be absent (legitimate) or value may be non-string (malformed).
          if grep -qE '"currentContext"[[:space:]]*:' "$cfg" 2>/dev/null; then
              printf '%s\n' "(config unreadable)"
          else
              printf '%s\n' "default"
          fi
          return 0
      fi
      printf '%s\n' "$val"
  }

  _dcs_daemon_reachable() {
      # Quick liveness probe. `docker info` can hang ~30s on a dead VM, so we
      # use `version` (client+server roundtrip) with a hard timeout.
      # Fall back to no-timeout if coreutils' `timeout` isn't available.
      if command -v timeout >/dev/null 2>&1; then
          timeout 5 docker version --format '{{.Server.Version}}' >/dev/null 2>&1
      else
          docker version --format '{{.Server.Version}}' >/dev/null 2>&1
      fi
  }

  _dcs_switch() {
      # Switch to a docker context.
      # Args: $1=target context name, $2=human-readable label (e.g. "Docker Desktop")
      local target="$1" label="$2"
      local current err

      current=$(_dcs_current_context)

      if [[ "$current" == "$target" ]]; then
          echo "OK: Already on context '$target' ($label) — no switch needed"
          return 0
      fi

      if ! err=$(LC_ALL=C docker context use "$target" 2>&1 >/dev/null); then
          echo "Error: Failed to switch to context '$target'"
          [[ -n "$err" ]] && echo "  → docker said: ${err%%$'\n'*}"
          echo "  → Verify with: docker context ls"
          echo "  → Check config: ~/.docker/config.json"
          return 1
      fi

      echo "OK: Switched ${current:-<unknown>} → $target ($label)"
      return 0
  }

  # ── Shadow detection ───────────────────────────────────────────────────────
  # Refuse to clobber existing functions/aliases. The source guard above means
  # this only runs once per shell, so re-sourcing won't re-trigger warnings.

  _dcs_can_define() {
      # Return 0 if it's safe to define a function called $1; otherwise warn
      # and return 1. `type -t` yields: function | alias | builtin | file | "".
      local name="$1" kind
      kind=$(type -t -- "$name" 2>/dev/null)
      case "$kind" in
          function|alias|builtin)
              printf '\033[33m→ docker-context-switch: '\''%s'\'' already defined elsewhere; skipping (existing definition kept)\033[0m\n' \
                  "$name" >&2
              return 1
              ;;
          file)
              # External executable in PATH with the same name. Warn but skip,
              # so the user's PATH-resolved command keeps winning.
              printf '\033[33m→ docker-context-switch: '\''%s'\'' shadows an executable in PATH; skipping (existing definition kept)\033[0m\n' \
                  "$name" >&2
              return 1
              ;;
          *)
              return 0
              ;;
      esac
  }

  # ── Public functions ───────────────────────────────────────────────────────

  if _dcs_can_define sandbox; then
  sandbox() {
      echo "───────────────────────────────────────────────────────────"
      echo "Switching to sandbox environment (Docker Desktop)"
      echo "───────────────────────────────────────────────────────────"
      echo ""

      _dcs_docker_installed         || return 1
      _dcs_docker_supports_context  || return 1
      _dcs_can_use_docker           || return 1
      _dcs_warn_docker_host block   || return 1

      if ! _dcs_context_exists "$_DCS_CTX_DESKTOP"; then
          echo "Error: Docker Desktop context '$_DCS_CTX_DESKTOP' not found"
          echo "  → Docker Desktop is not installed or hasn't created its context."
          echo "  → Install it: bash ~/.bin/docker-desktop-init.sh"
          echo "  → Or launch Docker Desktop once so it registers the context"
          echo "  → Verify: docker context ls"
          echo "  → Then try again: sandbox"
          echo ""
          return 1
      fi

      _dcs_switch "$_DCS_CTX_DESKTOP" "Docker Desktop" || return 1
      echo ""

      # Smoke test: verify the daemon is reachable
      if ! _dcs_daemon_reachable; then
          echo "→ context switched, but docker desktop daemon is not reachable"
          echo "  start it with: systemctl --user start docker-desktop"
          echo "  or launch the docker desktop app"
          echo "  (on Ubuntu 26.04 qemu-kvm is virtual-only — Desktop may need nested virt)"
          echo ""
          return 0
      fi

      echo "✓ Sandbox is ready."
      echo "  AI agents run here will only have access to provided resources."
      echo "  Switch back to main with: main"
      echo ""
  }
  fi

  if _dcs_can_define main; then
  main() {
      echo "───────────────────────────────────────────────────────────"
      echo "Switching to main environment (Docker Engine)"
      echo "───────────────────────────────────────────────────────────"
      echo ""

      _dcs_docker_installed         || return 1
      _dcs_docker_supports_context  || return 1
      _dcs_can_use_docker           || return 1
      _dcs_warn_docker_host block   || return 1

      if ! _dcs_context_exists "$_DCS_CTX_ENGINE"; then
          echo "Error: Docker Engine context '$_DCS_CTX_ENGINE' not found"
          echo "  → Docker Engine may not be installed."
          echo "  → Install it: bash ~/.bin/docker-init.sh"
          echo "  → Verify: docker context ls"
          echo ""
          return 1
      fi

      _dcs_switch "$_DCS_CTX_ENGINE" "Docker Engine" || return 1
      echo ""

      # Smoke test: verify the daemon is reachable
      if ! _dcs_daemon_reachable; then
          echo "→ context switched, but docker engine daemon is not reachable"
          echo "  check status:  systemctl status docker"
          echo "  start it:      sudo systemctl start docker"
          echo "  enable it:     sudo systemctl enable --now docker"
          echo ""
          return 0
      fi

      echo "✓ Back to main environment."
      echo "  Normal development workflow is active."
      echo "  Switch to sandbox with: sandbox"
      echo ""
  }
  fi

  if _dcs_can_define docker-context; then
  docker-context() {
      echo "───────────────────────────────────────────────────────────"
      echo "Docker context status"
      echo "───────────────────────────────────────────────────────────"
      echo ""

      _dcs_docker_installed         || return 1
      _dcs_docker_supports_context  || return 1
      _dcs_can_use_docker           || return 1
      _dcs_warn_docker_host

      local current
      current=$(_dcs_current_context)

      if [[ -z "$current" ]]; then
          echo "Error: Could not determine current context"
          echo "  → Run: docker context ls"
          echo ""
          return 1
      fi

      if [[ -n "${DOCKER_HOST:-}" ]]; then
          local configured
          configured=$(_dcs_configured_context)
          echo "Configured context: $configured"
          echo "Effective context:  $current   (forced by DOCKER_HOST)"
      else
          echo "Current context: $current"
      fi
      if _dcs_daemon_reachable; then
          echo "Daemon:          reachable"
      else
          echo "Daemon:          NOT REACHABLE (context is set, but no daemon answers)"
      fi
      echo ""
      echo "All contexts:"
      LC_ALL=C docker context ls 2>/dev/null
      echo ""

      echo "Context availability:"
      if _dcs_context_exists "$_DCS_CTX_ENGINE"; then
          echo "  $_DCS_CTX_ENGINE (Docker Engine)     present"
      else
          echo "  $_DCS_CTX_ENGINE (Docker Engine)     NOT FOUND → bash ~/.bin/docker-init.sh"
      fi

      if _dcs_context_exists "$_DCS_CTX_DESKTOP"; then
          echo "  $_DCS_CTX_DESKTOP (Docker Desktop)   present"
      else
          echo "  $_DCS_CTX_DESKTOP (Docker Desktop)   NOT FOUND → bash ~/.bin/docker-desktop-init.sh"
      fi

      echo ""
      echo "Commands:"
      echo "  sandbox         switch to Docker Desktop (isolated sandbox / AI agents)"
      echo "  main            switch to Docker Engine  (normal development)"
      echo "  docker-context  show this status panel"
      echo "───────────────────────────────────────────────────────────"
      echo ""
  }
  fi
