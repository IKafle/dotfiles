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

  # Guard: re-sourcing this file is a no-op
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

  _dcs_can_use_docker() {
      # Check if user can run docker commands (reads docker config, no daemon needed)
      if ! docker context ls >/dev/null 2>&1; then
          # Disambiguate the failure
          if groups | tr ' ' '\n' | grep -qx docker || [[ $EUID -eq 0 ]]; then
              # User is in docker group but command still failed — unexpected
              echo "Error: docker command failed unexpectedly"
              echo "  → Run: docker context ls  (to see full error)"
          else
              # User is not in docker group
              echo "Error: user '$(id -un)' cannot run docker commands"
              echo "  → Add yourself to the docker group:"
              echo "  →   sudo usermod -aG docker $(id -un)"
              echo "  → Then log out and back in, or run: newgrp docker"
          fi
          return 1
      fi
  }

  _dcs_context_exists() {
      # Check if a context name exists in docker config
      local ctx="$1"
      docker context ls --format '{{.Name}}' 2>/dev/null | grep -qx "$ctx"
  }

  _dcs_current_context() {
      # Print the name of the currently active context
      docker context ls --format '{{.Name}}\t{{.Current}}' 2>/dev/null \
          | awk -F'\t' '$2=="true"{print $1; exit}'
  }

  _dcs_daemon_reachable() {
      # Check if the Docker daemon for the current context is reachable (smoke test)
      docker info >/dev/null 2>&1
  }

  _dcs_switch() {
      # Switch to a docker context
      # Args: $1=target context name, $2=human-readable label (e.g. "Docker Desktop")
      local target="$1" label="$2"
      local current

      current=$(_dcs_current_context)

      if [[ "$current" == "$target" ]]; then
          echo "OK: Already on context '$target' ($label) — no switch needed"
          return 0
      fi

      if ! docker context use "$target" >/dev/null 2>&1; then
          echo "Error: Failed to switch to context '$target'"
          echo "  → Verify with: docker context ls"
          echo "  → Check config: ~/.docker/config.json"
          return 1
      fi

      echo "OK: Switched $current → $target ($label)"
      return 0
  }

  # ── Public functions ───────────────────────────────────────────────────────

  sandbox() {
      echo "───────────────────────────────────────────────────────────"
      echo "Switching to sandbox environment (Docker Desktop)"
      echo "───────────────────────────────────────────────────────────"
      echo ""

      _dcs_docker_installed || return 1
      _dcs_can_use_docker   || return 1

      if ! _dcs_context_exists "$_DCS_CTX_DESKTOP"; then
          echo "Error: Docker Desktop context '$_DCS_CTX_DESKTOP' not found"
          echo "  → Docker Desktop is not installed or hasn't created its context."
          echo "  → Install it: bash ~/.bin/docker-desktop-init.sh"
          echo "  → Start Docker Desktop from your applications menu"
          echo "  → Verify: docker context ls"
          echo "  → Then try again: sandbox"
          echo ""
          return 1
      fi

      _dcs_switch "$_DCS_CTX_DESKTOP" "Docker Desktop" || return 1
      echo ""

      # Smoke test: verify the daemon is reachable
      if ! _dcs_daemon_reachable; then
          echo "Warning: Docker Desktop context is active, but the daemon isn't responding"
          echo "  → Open Docker Desktop from your applications menu"
          echo "  → Wait for it to fully start, then try: docker ps"
          echo ""
          echo "The context is switched, but AI agents may fail until the Desktop VM is running."
          echo ""
          return 0
      fi

      echo "✓ Sandbox is ready."
      echo "  AI agents run here will only have access to provided resources."
      echo "  Switch back to main with: main"
      echo ""
  }

  main() {
      echo "───────────────────────────────────────────────────────────"
      echo "Switching to main environment (Docker Engine)"
      echo "───────────────────────────────────────────────────────────"
      echo ""

      _dcs_docker_installed || return 1
      _dcs_can_use_docker   || return 1

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
          echo "Warning: Docker Engine context is active, but the daemon isn't responding"
          echo "  → Start it: sudo systemctl start docker"
          echo "  → Verify: docker ps"
          echo ""
          echo "The context is switched, but Docker commands will fail until the daemon starts."
          echo ""
          return 0
      fi

      echo "✓ Back to main environment."
      echo "  Normal development workflow is active."
      echo "  Switch to sandbox with: sandbox"
      echo ""
  }

  docker-context() {
      echo "───────────────────────────────────────────────────────────"
      echo "Docker context status"
      echo "───────────────────────────────────────────────────────────"
      echo ""

      _dcs_docker_installed || return 1
      _dcs_can_use_docker   || return 1

      local current
      current=$(_dcs_current_context)

      if [[ -z "$current" ]]; then
          echo "Error: Could not determine current context"
          echo "  → Run: docker context ls"
          echo ""
          return 1
      fi

      echo "Current context: $current"
      echo ""
      echo "All contexts:"
      docker context ls 2>/dev/null
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
