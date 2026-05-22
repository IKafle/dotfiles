#!/usr/bin/env bash
# bx-purpose: install Docker Engine + Compose v2 + Buildx on Ubuntu/Debian
# shellcheck shell=bash
#
# If invoked as `sh docker-init.sh` (or any non-bash POSIX shell), the array
# and [[ ]] syntax below would error out before we can give a useful message.
# Re-exec under bash. This block must stay POSIX-sh-compatible.
# shellcheck disable=SC3028
if [ -z "${BASH_VERSION:-}" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    fi
    printf 'docker-init.sh requires bash, but bash is not installed.\n' >&2
    printf 'Install it with: apt-get install -y bash\n' >&2
    exit 1
fi
#
# docker-init.sh
# ─────────────────────────────────────────────────────────────────────────────
# Installs Docker Engine + Docker Compose v2 + Buildx on Ubuntu/Debian
# (or derivatives via ID_LIKE), following Docker's official upstream method.
# Idempotent — safe to re-run.
#
# Usage:
#   bash docker-init.sh                 # full install + smoke test
#   bash docker-init.sh --no-check      # skip smoke test
#   bash docker-init.sh --dry-run       # print actions, don't execute
#   bash docker-init.sh --help
#
# Requirements: Ubuntu/Debian, sudo (or root), ~2-3 GB free, network access
#
# Logs:    ~/.docker/docker-init.log
# Exit:    0 success, 1 fatal, 2 bad usage, 130 SIGINT
# ─────────────────────────────────────────────────────────────────────────────

set -Eeuo pipefail
IFS=$'\n\t'

# ── Configuration ───────────────────────────────────────────────────────────
readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_VERSION="2.0.2"
# LOG_DIR / LOG_FILE are mutable: ensure_log_dir() may fall back to /tmp if the
# primary location is unwritable. HOME is guarded for cron / env -i / systemd
# unit contexts where HOME may be unset.
LOG_DIR="${HOME:-${TMPDIR:-/tmp}}/.docker"
LOG_FILE="${LOG_DIR}/docker-init.log"
readonly KEYRING_DIR="/etc/apt/keyrings"
readonly KEYRING="${KEYRING_DIR}/docker.gpg"
readonly REPO_FILE="/etc/apt/sources.list.d/docker.list"
readonly CURL_OPTS=(--fail --silent --show-error --location --connect-timeout 10 --max-time 60 --retry 3 --retry-delay 2)

readonly DOCKER_PACKAGES=(
    docker-ce
    docker-ce-cli
    containerd.io
    docker-buildx-plugin
    docker-compose-plugin
)

# Packages Docker's official guide says to remove before installing Docker CE.
readonly CONFLICTING_PACKAGES=(
    docker.io
    docker-doc
    docker-compose
    docker-compose-v2
    podman-docker
    containerd
    runc
)

# ── Mutable state ───────────────────────────────────────────────────────────
CHANGED_COUNT=0
SKIP_SMOKE_TEST=0
DRY_RUN=0
OS_ID=""
OS_CODENAME=""
OS_CODENAME_OVERRIDE=""
PRETTY_NAME_DETECTED=""
SUDO_KEEPALIVE_PID=""
USER_GROUP_ADDED=0
TIPS_HEADER_PRINTED=0

# ── Logging ─────────────────────────────────────────────────────────────────
# Safe even before LOG_DIR exists: falls back to stderr.

_ts() { date '+%Y-%m-%d %H:%M:%S'; }

log() {
    local line
    line="[$(_ts)] $*"
    if [[ -d "$LOG_DIR" && -w "$LOG_DIR" ]]; then
        printf '%s\n' "$line" >> "$LOG_FILE"
    else
        printf '%s\n' "$line" >&2
    fi
}

say()  { printf '%s\n' "$*"; }
ok()   { printf '  OK: %s\n' "$1"; log "OK: $1"; }
skip() { printf '  --: %s\n' "$1"; log "SKIP: $1"; }
warn() { printf '  WARNING: %s\n' "$1" >&2; log "WARN: $1"; }
die()  { printf '  ERROR: %s\n' "$1" >&2; log "FATAL: $1"; exit 1; }

mark_changed() { CHANGED_COUNT=$((CHANGED_COUNT + 1)); }

# ── Signal & error handling ─────────────────────────────────────────────────
on_err() {
    local exit_code=$?
    local line=${BASH_LINENO[0]:-?}
    local cmd=${BASH_COMMAND:-?}
    log "ERR trap: exit=$exit_code at line $line: $cmd"
    printf '\n  ERROR: command failed (exit %d) at %s:%s\n    > %s\n' \
        "$exit_code" "$SCRIPT_NAME" "$line" "$cmd" >&2
    [[ -f "$LOG_FILE" ]] && printf '  See log: %s\n' "$LOG_FILE" >&2
    cleanup_keepalive
    exit "$exit_code"
}

on_int()  { log "Caught SIGINT — aborting";  printf '\n  Aborted.\n' >&2; cleanup_keepalive; exit 130; }
on_term() { log "Caught SIGTERM — aborting"; cleanup_keepalive; exit 143; }

cleanup_keepalive() {
    if [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
}

trap on_err  ERR
trap on_int  INT
trap on_term TERM
trap cleanup_keepalive EXIT

# ── Usage ───────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${SCRIPT_NAME} v${SCRIPT_VERSION} — install Docker Engine + Compose v2 + Buildx

Usage: ${SCRIPT_NAME} [OPTIONS]

Options:
  --no-check         Skip the post-install smoke test (docker ps)
  --dry-run          Print actions but make no system changes
  --codename=<name>  Override detected OS codename (e.g. noble, bookworm).
                     Use this when Docker hasn't yet published packages for
                     your distro's codename (common on brand-new releases).
  -V, --version      Print version and exit
  -h, --help         Show this help

The script is idempotent. Logs: ${LOG_FILE}
EOF
}

# ── Arg parsing ─────────────────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --no-check)        SKIP_SMOKE_TEST=1 ;;
        --dry-run)         DRY_RUN=1 ;;
        --codename=*)      OS_CODENAME_OVERRIDE="${arg#--codename=}" ;;
        --codename)        printf 'Option --codename requires a value: --codename=<name>\n\n' >&2; usage >&2; exit 2 ;;
        -V|--version)      printf '%s %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"; exit 0 ;;
        -h|--help)         usage; exit 0 ;;
        *)                 printf 'Unknown option: %s\n\n' "$arg" >&2; usage >&2; exit 2 ;;
    esac
done

# Validate --codename value if provided (reject empty / shell-meta nonsense).
if [[ -n "$OS_CODENAME_OVERRIDE" ]]; then
    if [[ ! "$OS_CODENAME_OVERRIDE" =~ ^[a-z][a-z0-9._-]*$ ]]; then
        printf 'Invalid --codename value: %q\n' "$OS_CODENAME_OVERRIDE" >&2
        exit 2
    fi
fi

# ── Helpers ─────────────────────────────────────────────────────────────────
require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

run_priv() {
    # Run a command with privileges. Honors --dry-run.
    if (( DRY_RUN )); then
        printf '  [dry-run] %s\n' "$(printf '%q ' "$@")"
        return 0
    fi
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

apt_get() {
    if (( DRY_RUN )); then
        printf '  [dry-run] apt-get'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi
    local sudo_prefix=()
    (( EUID != 0 )) && sudo_prefix=(sudo)
    local tmp rc=0
    tmp=$(mktemp) || die "mktemp failed"
    if "${sudo_prefix[@]}" env DEBIAN_FRONTEND=noninteractive \
            apt-get -o Dpkg::Options::=--force-confdef \
                    -o Dpkg::Options::=--force-confold \
                    "$@" >"$tmp" 2>&1; then
        log "apt-get $*"
    else
        rc=$?
        log "apt-get $* FAILED (rc=$rc)"
        log "----- apt-get output -----"
        log "$(cat "$tmp")"
        log "--------------------------"
        printf '%s\n' "----- apt-get $* -----" >&2
        cat "$tmp" >&2
        printf '%s\n' "----------------------" >&2
    fi
    rm -f "$tmp"
    return "$rc"
}

package_installed() {
    dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null \
        | grep -qx 'install ok installed'
}

current_docker_version() {
    command -v docker >/dev/null 2>&1 || return 0
    docker --version 2>/dev/null | sed -n 's/^Docker version \([^,]*\).*/\1/p' || true
}

# ── Step 0: prep log dir ───────────────────────────────────────────────────
ensure_log_dir() {
    if mkdir -p "$LOG_DIR" 2>/dev/null && : >> "$LOG_FILE" 2>/dev/null; then
        chmod 700 "$LOG_DIR" 2>/dev/null || true
        chmod 600 "$LOG_FILE" 2>/dev/null || true
        return
    fi
    # Primary location unwritable (read-only $HOME, cron-locked user, etc.).
    # Fall back to a per-uid file in /tmp so the script can still complete.
    local fb_dir="${TMPDIR:-/tmp}"
    local fb_file="${fb_dir}/docker-init-$(id -u).log"
    if : >> "$fb_file" 2>/dev/null; then
        chmod 600 "$fb_file" 2>/dev/null || true
        warn "primary log location ($LOG_DIR) not writable; falling back to $fb_file"
        LOG_DIR="$fb_dir"
        LOG_FILE="$fb_file"
        return
    fi
    die "no writable location for log file (tried $LOG_DIR and $fb_dir)"
}

# ── Step 1: sudo / privilege ───────────────────────────────────────────────
check_sudo() {
    say "── Step 1: verify privileges ─────────────────────────"
    if [[ $EUID -eq 0 ]]; then
        ok "running as root"
        log "Step 1: root"
        say ""
        return
    fi

    require_cmd sudo
    if sudo -n true 2>/dev/null; then
        ok "sudo access verified (cached credentials)"
        log "Step 1: sudo cached"
    else
        say "  sudo password required:"
        if (( DRY_RUN )); then
            ok "[dry-run] would prompt for sudo"
        else
            sudo -v || die "sudo authentication failed"
            ok "sudo access verified"
        fi
        log "Step 1: sudo authenticated"
    fi

    # Keep sudo timestamp alive while the script runs.
    if (( ! DRY_RUN )); then
        ( while true; do
              sudo -n true 2>/dev/null || exit 0
              sleep 50
              kill -0 "$$" 2>/dev/null || exit 0
          done ) &
        SUDO_KEEPALIVE_PID=$!
    fi
    say ""
}

# ── Step 2: OS detection ───────────────────────────────────────────────────
check_os() {
    say "── Step 2: OS detection ──────────────────────────────"
    require_cmd apt-get
    require_cmd dpkg
    [[ -r /etc/os-release ]] || die "/etc/os-release missing or unreadable"

    # shellcheck disable=SC1091
    . /etc/os-release
    PRETTY_NAME_DETECTED="${PRETTY_NAME:-${NAME:-unknown}}"
    OS_CODENAME="${VERSION_CODENAME:-}"

    # Map ID + ID_LIKE → upstream Docker repo family
    local id="${ID:-}" idlike=",${ID_LIKE:-},"
    case "$id" in
        ubuntu) OS_ID=ubuntu ;;
        debian) OS_ID=debian ;;
        *)
            if [[ "$idlike" == *,ubuntu,* ]]; then
                OS_ID=ubuntu
                # Derivatives (Mint, Pop!_OS) often have their own codename;
                # use UBUNTU_CODENAME if exposed.
                OS_CODENAME="${UBUNTU_CODENAME:-$OS_CODENAME}"
            elif [[ "$idlike" == *,debian,* ]]; then
                OS_ID=debian
            else
                die "unsupported OS: $PRETTY_NAME_DETECTED (only ubuntu/debian + derivatives)"
            fi
            ;;
    esac

    if [[ -z "$OS_CODENAME" ]] && command -v lsb_release >/dev/null 2>&1; then
        OS_CODENAME=$(lsb_release -cs 2>/dev/null || true)
    fi

    # User-provided override wins (used when Docker hasn't published the
    # detected codename yet, or to force a known-good codename).
    if [[ -n "$OS_CODENAME_OVERRIDE" ]]; then
        log "Step 2: codename overridden via flag: $OS_CODENAME → $OS_CODENAME_OVERRIDE"
        OS_CODENAME="$OS_CODENAME_OVERRIDE"
    fi

    # Reject empty / lsb_release-on-container placeholders. Without this, a
    # bogus codename gets written into the repo file and apt-get update fails
    # with an opaque error.
    case "$OS_CODENAME" in
        ""|n/a|unknown|none)
            die "unable to determine a valid OS codename (got: '${OS_CODENAME:-empty}'). Use --codename=<name> to specify manually (e.g., --codename=noble, --codename=bookworm)."
            ;;
    esac

    ok "$PRETTY_NAME_DETECTED  (repo family: $OS_ID, codename: $OS_CODENAME)"
    log "Step 2: OS=$OS_ID codename=$OS_CODENAME pretty=$PRETTY_NAME_DETECTED"
    say ""
}

# ── Step 3: conflict scan ──────────────────────────────────────────────────
check_conflicts() {
    say "── Step 3: scan for conflicting packages ─────────────"
    local found=()
    for pkg in "${CONFLICTING_PACKAGES[@]}"; do
        package_installed "$pkg" && found+=("$pkg")
    done
    if (( ${#found[@]} > 0 )); then
        warn "found packages that conflict with Docker CE: ${found[*]}"
        warn "Docker's official guide recommends removing them first:"
        warn "  sudo apt-get remove ${found[*]}"
        warn "Continuing — installation may still succeed, but a mixed setup is possible."
        log  "Step 3: conflicts present: ${found[*]}"
    else
        ok "no conflicting packages installed"
        log "Step 3: no conflicts"
    fi
    say ""
}

# ── Step 4: update package index ───────────────────────────────────────────
update_packages() {
    say "── Step 4: refresh package index ─────────────────────"
    apt_get update || die "apt-get update failed (see log)"
    ok "package lists refreshed"
    log "Step 4 PASSED"
    say ""
}

# ── Step 5: install transport deps ─────────────────────────────────────────
install_dependencies() {
    say "── Step 5: install transport dependencies ────────────"
    local deps=(ca-certificates curl gnupg lsb-release)
    local missing=()
    for pkg in "${deps[@]}"; do
        if package_installed "$pkg"; then
            skip "$pkg already installed"
        else
            missing+=("$pkg")
        fi
    done
    if (( ${#missing[@]} > 0 )); then
        apt_get install -y "${missing[@]}" \
            || die "failed to install dependencies: ${missing[*]}"
        ok "installed: ${missing[*]}"
        mark_changed
        log "Step 5: installed ${missing[*]}"
    else
        log "Step 5 SKIPPED: all deps present"
    fi
    say ""
}

# ── Step 6: GPG key ────────────────────────────────────────────────────────
add_docker_gpg_key() {
    say "── Step 6: install Docker GPG key ────────────────────"
    if [[ -s "$KEYRING" ]]; then
        skip "GPG key already installed at $KEYRING"
        log "Step 6 SKIPPED: $KEYRING present"
        say ""
        return
    fi

    require_cmd curl
    require_cmd gpg

    run_priv install -m 0755 -d "$KEYRING_DIR" \
        || die "failed to create $KEYRING_DIR"

    local key_url="https://download.docker.com/linux/${OS_ID}/gpg"
    local tmp_armored tmp_dearmored
    tmp_armored=$(mktemp) || die "mktemp failed (armored)"
    tmp_dearmored=$(mktemp) || { rm -f "$tmp_armored"; die "mktemp failed (dearmored)"; }
    trap 'rm -f "$tmp_armored" "$tmp_dearmored"; on_err' ERR

    if (( DRY_RUN )); then
        printf '  [dry-run] curl %s → gpg --dearmor → %s\n' "$key_url" "$KEYRING"
    else
        log "Step 6: fetching $key_url"
        if ! curl "${CURL_OPTS[@]}" -o "$tmp_armored" "$key_url"; then
            rm -f "$tmp_armored" "$tmp_dearmored"
            die "failed to download GPG key from $key_url"
        fi
        [[ -s "$tmp_armored" ]] \
            || { rm -f "$tmp_armored" "$tmp_dearmored"; die "downloaded GPG key is empty"; }

        if ! gpg --dearmor --batch --yes -o "$tmp_dearmored" "$tmp_armored" 2>/dev/null; then
            rm -f "$tmp_armored" "$tmp_dearmored"
            die "gpg --dearmor failed on downloaded key"
        fi
        [[ -s "$tmp_dearmored" ]] \
            || { rm -f "$tmp_armored" "$tmp_dearmored"; die "dearmored GPG key is empty"; }

        run_priv install -m 0644 "$tmp_dearmored" "$KEYRING" \
            || { rm -f "$tmp_armored" "$tmp_dearmored"; die "failed to install GPG key to $KEYRING"; }
        rm -f "$tmp_armored" "$tmp_dearmored"
    fi
    trap on_err ERR

    ok "Docker GPG key installed: $KEYRING"
    mark_changed
    log "Step 6 PASSED"
    say ""
}

# ── Step 7: repository ─────────────────────────────────────────────────────
probe_codename_available() {
    # HEAD-check that Docker has actually published packages for this codename.
    # Common failure mode: brand-new OS release where Docker's mirror lags.
    # Without this probe, the script writes a repo file that apt-get update
    # would reject opaquely. The HEAD is read-only, so it runs in dry-run too —
    # that way --dry-run actually catches codename mismatches.
    local probe_url="https://download.docker.com/linux/${OS_ID}/dists/${OS_CODENAME}/Release"
    log "Step 7: probing $probe_url"
    (( DRY_RUN )) && printf '  [dry-run] HEAD %s\n' "$probe_url"
    if curl "${CURL_OPTS[@]}" --output /dev/null --head "$probe_url" 2>/dev/null; then
        log "Step 7: codename '${OS_CODENAME}' is published by Docker"
        return 0
    fi
    return 1
}

add_docker_repo() {
    say "── Step 7: configure Docker apt repository ───────────"

    require_cmd curl
    if ! probe_codename_available; then
        die "Docker has not published packages for '${OS_ID}/${OS_CODENAME}' (HEAD probe failed at https://download.docker.com/linux/${OS_ID}/dists/${OS_CODENAME}/Release). This is common for brand-new OS releases. Re-run with --codename=<older> (e.g. --codename=noble for Ubuntu, --codename=bookworm for Debian)."
    fi

    local arch repo_line
    arch=$(dpkg --print-architecture)
    repo_line="deb [arch=${arch} signed-by=${KEYRING}] https://download.docker.com/linux/${OS_ID} ${OS_CODENAME} stable"

    if [[ -f "$REPO_FILE" ]] && grep -qxF "$repo_line" "$REPO_FILE"; then
        skip "repository already configured"
        log "Step 7 SKIPPED: repo matches"
        say ""
        return
    fi

    if (( DRY_RUN )); then
        printf '  [dry-run] write %s →\n    %s\n' "$REPO_FILE" "$repo_line"
    else
        # Write via tee with explicit content (no shell-meta expansion surprises).
        printf '%s\n' "$repo_line" | run_priv tee "$REPO_FILE" >/dev/null \
            || die "failed to write $REPO_FILE"
    fi
    ok "wrote $REPO_FILE  (${OS_ID} / ${OS_CODENAME} / ${arch})"
    mark_changed
    log "Step 7: $repo_line"

    apt_get update || die "apt-get update failed after adding Docker repo"
    ok "package lists refreshed against Docker repo"
    log "Step 7 PASSED"
    say ""
}

# ── Step 8: install Docker ─────────────────────────────────────────────────
install_docker_engine() {
    say "── Step 8: install Docker Engine + Compose + Buildx ──"

    local before_version=""
    if command -v docker >/dev/null 2>&1; then
        before_version=$(current_docker_version)
        skip "docker present (version: ${before_version:-unknown})"
    fi

    # Always run install — apt-get is a no-op when all packages are already at latest.
    apt_get install -y "${DOCKER_PACKAGES[@]}" \
        || die "failed to install Docker packages"

    local after_version
    after_version=$(current_docker_version)

    if [[ -z "$before_version" ]]; then
        ok "installed Docker ${after_version:-(version unknown)}"
        mark_changed
        log "Step 8 PASSED: fresh install ${after_version:-?}"
    elif [[ "$before_version" != "$after_version" ]]; then
        ok "upgraded Docker: $before_version → $after_version"
        mark_changed
        log "Step 8 PASSED: upgrade $before_version → $after_version"
    else
        skip "Docker already at latest available version ($after_version)"
        log "Step 8 SKIPPED: already up to date ($after_version)"
    fi
    say ""
}

# ── Step 9: daemon ─────────────────────────────────────────────────────────
enable_docker_daemon() {
    say "── Step 9: start and enable Docker daemon ────────────"

    if ! command -v systemctl >/dev/null 2>&1; then
        warn "systemctl not found — skipping daemon enable (non-systemd host?)"
        log "Step 9 SKIPPED: no systemctl"
        say ""
        return
    fi

    local was_active=0 was_enabled=0
    systemctl is-active --quiet docker  && was_active=1
    systemctl is-enabled --quiet docker 2>/dev/null && was_enabled=1

    if (( was_active )); then
        skip "docker.service already active"
    else
        run_priv systemctl start docker || die "systemctl start docker failed"
        if (( ! DRY_RUN )); then
            # Cold-boot containerd / slow disks regularly need 15-30s.
            local i=0
            until systemctl is-active --quiet docker; do
                i=$((i+1))
                (( i > 30 )) && die "docker.service did not become active within 30s (check: systemctl status docker, journalctl -u docker)"
                sleep 1
            done
        fi
        ok "docker.service started"
        mark_changed
    fi

    if (( was_enabled )); then
        skip "docker.service already enabled on boot"
    else
        if run_priv systemctl enable docker 2>/dev/null; then
            ok "docker.service enabled on boot"
            mark_changed
        else
            warn "failed to enable docker.service on boot"
        fi
    fi
    log "Step 9 PASSED (was_active=$was_active was_enabled=$was_enabled)"
    say ""
}

# ── Step 10: docker group ──────────────────────────────────────────────────
add_user_to_docker_group() {
    say "── Step 10: add user to docker group ─────────────────"

    if [[ $EUID -eq 0 ]]; then
        skip "running as root — docker group not needed"
        log "Step 10 SKIPPED: root"
        say ""
        return
    fi

    local current_user
    current_user=$(id -un)

    if ! getent group docker >/dev/null; then
        run_priv groupadd docker || die "failed to create docker group"
        ok "created docker group"
        mark_changed
        log "Step 10: created group"
    fi

    if id -nG "$current_user" | tr ' ' '\n' | grep -qx docker; then
        skip "user '$current_user' already in docker group"
        log "Step 10 SKIPPED: $current_user already in group"
    else
        run_priv usermod -aG docker "$current_user" \
            || die "usermod -aG docker $current_user failed"
        ok "added '$current_user' to docker group"
        mark_changed
        USER_GROUP_ADDED=1
        log "Step 10: added $current_user to docker group"
        printf '      Note: log out / back in (or run: newgrp docker) for this to apply.\n'
    fi
    say ""
}

# ── Step 11: smoke test ────────────────────────────────────────────────────
smoke_test() {
    say "── Step 11: smoke test ───────────────────────────────"
    if (( SKIP_SMOKE_TEST )); then
        skip "smoke test skipped (--no-check)"
        log "Step 11 SKIPPED: --no-check"
        say ""
        return
    fi
    if (( DRY_RUN )); then
        skip "smoke test skipped (--dry-run)"
        say ""
        return
    fi

    local current_user
    current_user=$(id -un)

    # Try the real test first — plain `docker ps`. If it works, we're done.
    # The previous version checked `id -nG <user>` (which reads /etc/group) and
    # assumed that meant the *current shell* had docker privileges. It doesn't:
    # supplementary groups are baked into a process at login, so right after
    # usermod the /etc/group view shows docker but the running shell can't
    # actually talk to the daemon. That mismatch produced a misleading
    # "daemon up but client cannot connect" warning.
    if docker ps >/dev/null 2>&1; then
        ok "docker ps succeeded"
        log "Step 11 PASSED: docker ps"
        say ""
        return
    fi

    # `docker ps` failed. Disambiguate why.
    if [[ $EUID -eq 0 ]]; then
        warn "docker ps failed as root — daemon up but client cannot connect (check: systemctl status docker, journalctl -u docker)"
        log "Step 11 FAILED: docker ps as root"
    elif id -nG "$current_user" | tr ' ' '\n' | grep -qx docker; then
        # User is in docker group per /etc/group, but the current shell's
        # credentials don't include it yet — classic post-usermod state.
        if sudo -n docker ps >/dev/null 2>&1; then
            ok "sudo docker ps succeeded — docker group not yet effective in this shell"
            printf '      Run: newgrp docker   (or log out and back in) before using docker without sudo.\n'
            log "Step 11 PASSED: sudo docker ps (group pending re-login)"
        else
            warn "docker ps failed in this shell; docker group is set but not yet active here. Run 'newgrp docker' or log out / back in."
            log "Step 11 FAILED: group set but not effective; sudo unavailable to verify"
        fi
    else
        warn "user '$current_user' not in docker group — run: sudo usermod -aG docker $current_user (then log out / back in)"
        log "Step 11 FAILED: user not in docker group"
    fi
    say ""
}

# ── Step 12: compose check ─────────────────────────────────────────────────
verify_compose() {
    say "── Step 12: verify Docker Compose v2 ─────────────────"
    if (( DRY_RUN )); then
        skip "skipped (--dry-run)"
        say ""
        return
    fi
    if docker compose version >/dev/null 2>&1; then
        local v
        v=$(docker compose version 2>/dev/null | head -n1)
        ok "$v"
        log "Step 12 PASSED: $v"
    else
        warn "docker compose plugin not available (may require shell reload)"
        log "Step 12 WARN: compose unavailable"
    fi
    say ""
}

# ── Post-install tips ─────────────────────────────────────────────────────
# Surface non-obvious Engine customization paths and coexistence quirks.
# Each check is stateful — once the user has acted on a tip (e.g. created
# /etc/docker/daemon.json), the corresponding line stops firing on re-runs.
emit_tip_header() {
    (( TIPS_HEADER_PRINTED )) && return
    say ""
    say "  Tips you might not know:"
    TIPS_HEADER_PRINTED=1
}

print_optional_tips() {
    # 1. /etc/docker/daemon.json is the canonical place to tune the daemon
    # (registry mirrors, log-driver/log-opts, default-address-pools, storage
    # driver). It's not created by the .deb — surface that the file is
    # missing/empty so the user knows the knob exists.
    local daemon_json="/etc/docker/daemon.json"
    local needs_daemon_tip=0
    if [[ ! -e "$daemon_json" ]]; then
        needs_daemon_tip=1
    elif [[ -r "$daemon_json" ]]; then
        # Treat an empty {} (or completely empty file) as "untouched".
        local _normalized
        _normalized=$(tr -d '[:space:]' < "$daemon_json" 2>/dev/null || true)
        [[ -z "$_normalized" || "$_normalized" == "{}" ]] && needs_daemon_tip=1
    fi
    if (( needs_daemon_tip )); then
        emit_tip_header
        say "    • /etc/docker/daemon.json is empty — that's the canonical place"
        say "      to tune the daemon (registry mirrors, log rotation, address pools,"
        say "      storage driver). Edit it, then: sudo systemctl reload docker"
    fi

    # 2. If Docker Desktop is also installed on this host, the user has two
    # contexts and 'docker ps' targets whichever is active — common source of
    # 'where did my containers go?' confusion.
    if [[ -e /opt/docker-desktop/bin/com.docker.backend ]]; then
        emit_tip_header
        say "    • Docker Desktop is also installed — you have multiple contexts:"
        say "        docker context ls"
        say "        docker context use default        # this Engine (local socket)"
        say "        docker context use desktop-linux  # Docker Desktop (VM)"
    fi

    # 3. The standalone docker-compose v1 package coexists awkwardly with the
    # v2 plugin (which we install). Flag it so the user can drop v1.
    if package_installed docker-compose 2>/dev/null; then
        emit_tip_header
        say "    • Legacy docker-compose v1 package is installed alongside the"
        say "      v2 plugin. v1 is unmaintained; prefer 'docker compose' (no hyphen)."
        say "      Remove v1: sudo apt-get remove docker-compose"
    fi
}

# ── Main ───────────────────────────────────────────────────────────────────
main() {
    say "╔═══════════════════════════════════════════════════════════╗"
    printf '║  %s v%s%*s║\n' "$SCRIPT_NAME" "$SCRIPT_VERSION" \
        $((57 - ${#SCRIPT_NAME} - ${#SCRIPT_VERSION} - 2)) ""
    say "╚═══════════════════════════════════════════════════════════╝"
    (( DRY_RUN )) && say "  (dry-run mode — no changes will be applied)"
    say ""

    ensure_log_dir

    log "═══════════════════════════════════════════════════════════"
    log "$SCRIPT_NAME v$SCRIPT_VERSION started"
    log "user=$(id -un) uid=$(id -u) host=$(uname -nsr)"
    log "args: SKIP_SMOKE_TEST=$SKIP_SMOKE_TEST DRY_RUN=$DRY_RUN"
    log "═══════════════════════════════════════════════════════════"

    check_sudo
    check_os
    check_conflicts
    update_packages
    install_dependencies
    add_docker_gpg_key
    add_docker_repo
    install_docker_engine
    enable_docker_daemon
    add_user_to_docker_group
    smoke_test
    verify_compose

    say "─────────────────────────────────────────────────────────"
    if (( CHANGED_COUNT == 0 )); then
        say "  ✓ Nothing to do — Docker is already properly installed."
        log "RESULT: 0 changes"
    else
        say "  ✓ Applied $CHANGED_COUNT change(s)."
        say "    Log: $LOG_FILE"
        log "RESULT: $CHANGED_COUNT changes"
    fi

    # `id -nG` reads /etc/group fresh, so it would report docker membership
    # right after usermod even though the current shell doesn't have it yet.
    # Track the actual usermod via a flag so the warning fires when it's needed.
    if (( USER_GROUP_ADDED )); then
        say ""
        say "  IMPORTANT: log out and back in (or run: newgrp docker)"
        say "             before running docker without sudo in this shell."
    fi

    say ""
    say "  Next:"
    say "    docker ps"
    say "    docker compose version"
    say "    tail -f $LOG_FILE"

    print_optional_tips

    say "─────────────────────────────────────────────────────────"
    say ""

    log "$SCRIPT_NAME completed cleanly"
}

main "$@"
