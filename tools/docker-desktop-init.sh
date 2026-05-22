#!/usr/bin/env bash
# bx-purpose: install Docker Desktop (KVM-isolated) on Ubuntu/Debian
# shellcheck shell=bash
#
# If invoked as `sh docker-desktop-init.sh` (or any non-bash POSIX shell),
# the array and [[ ]] syntax below would error out before we can give a useful
# message. Re-exec under bash. This block must stay POSIX-sh-compatible.
# shellcheck disable=SC3028
if [ -z "${BASH_VERSION:-}" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    fi
    printf 'docker-desktop-init.sh requires bash, but bash is not installed.\n' >&2
    printf 'Install it with: apt-get install -y bash\n' >&2
    exit 1
fi
#
# docker-desktop-init.sh
# ─────────────────────────────────────────────────────────────────────────────
# Installs Docker Desktop on Ubuntu — KVM-based VM sandbox for containers.
# Coexists with Docker Engine: adds a 'desktop-linux' context and leaves the
# system 'default' context (Engine, if present) untouched.
#
# Idempotent — safe to re-run. If Docker Desktop is already at the requested
# version, the script is a no-op.
#
# Usage:
#   bash docker-desktop-init.sh                          # install pinned version
#   bash docker-desktop-init.sh --version=4.38.0 --build=181591
#   bash docker-desktop-init.sh --deb-url=https://...    # supply a specific .deb
#   bash docker-desktop-init.sh --no-autostart           # don't enable user service
#   bash docker-desktop-init.sh --no-check               # skip smoke test
#   bash docker-desktop-init.sh --dry-run                # print actions, no changes
#   bash docker-desktop-init.sh --allow-unsupported-os   # proceed on unlisted Ubuntu
#
# Requirements:
#   - Ubuntu 24.04 LTS (noble) or 26.04 LTS (resolute)
#   - x86_64 or arm64 with hardware virtualization (VT-x / AMD-V) enabled
#   - sudo (or root) for system packages, run as your normal user (not root)
#   - ~3-4 GB free disk, network access
#   - systemd init + a desktop environment for the GUI
#
# Logs:    ~/.docker/docker-desktop-init.log
# Exit:    0 success, 1 fatal, 2 bad usage, 130 SIGINT
# ─────────────────────────────────────────────────────────────────────────────

set -Eeuo pipefail
IFS=$'\n\t'

# ── Configuration ───────────────────────────────────────────────────────────
readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_VERSION="1.0.0"

# Default pinned Docker Desktop release.
# Bump these alongside upstream: https://docs.docker.com/desktop/release-notes/
# The "build" is the numeric component in Docker's CDN URL path for that
# release. If unsure or the URL pattern changes, use --deb-url=<full-url>.
# Last verified: 2026-05-21 against docs.docker.com release notes.
readonly DEFAULT_DD_VERSION="4.74.0"
readonly DEFAULT_DD_BUILD="227015"

LOG_DIR="${HOME:-${TMPDIR:-/tmp}}/.docker"
LOG_FILE="${LOG_DIR}/docker-desktop-init.log"
readonly CURL_OPTS=(--fail --silent --show-error --location --connect-timeout 10 --max-time 60 --retry 3 --retry-delay 2)
readonly CACHE_DIR="/var/cache/docker-desktop-init"

# Ubuntu codenames Docker Desktop officially supports (per docs.docker.com).
# Debian / Mint / Pop!_OS are NOT supported by Docker Desktop on Linux — use
# Docker Engine (docker-init.sh) on those.
# Last verified: 2026-05-21 — Docker dropped jammy (22.04) and the interim
# releases (oracular 24.10); only the two current LTSes are listed upstream.
readonly SUPPORTED_UBUNTU_CODENAMES=(noble resolute)

# KVM / qemu packages: required for Docker Desktop's VM backend. The
# arch-specific qemu-system-* package is appended at runtime once DD_ARCH
# is known. `qemu-kvm` is intentionally omitted — it became a virtual-only
# package on Ubuntu 26.04 (resolute) and can no longer be installed
# directly; qemu-system-x86 / qemu-system-arm already pull KVM in.
readonly KVM_PACKAGES_COMMON=(
    libvirt-clients
    libvirt-daemon-system
    bridge-utils
    cpu-checker
)

# Extra dependencies. The .deb's own Depends: pulls in libgtk-3 / libnss3 /
# etc. via `apt install ./file.deb`; we only pre-install the small ones that
# are often missing on server-style installs.
readonly DESKTOP_DEPS=(
    ca-certificates
    curl
    gnupg
    pass
    uidmap
    dbus-user-session
)

# ── Mutable state ───────────────────────────────────────────────────────────
CHANGED_COUNT=0
SKIP_SMOKE_TEST=0
SKIP_AUTOSTART=0
DRY_RUN=0
ALLOW_UNSUPPORTED_OS=0
DD_VERSION="$DEFAULT_DD_VERSION"
DD_BUILD="$DEFAULT_DD_BUILD"
DD_DEB_URL=""
DD_CHECKSUM=""
DD_ARCH=""
OS_CODENAME=""
PRETTY_NAME_DETECTED=""
SUDO_KEEPALIVE_PID=""
KVM_GROUP_ADDED=0
TARGET_USER=""
TARGET_HOME=""
TARGET_UID=""
DEB_LOCAL_PATH=""
TIPS_HEADER_PRINTED=0

# ── Logging ─────────────────────────────────────────────────────────────────
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

say()   { printf '%s\n' "$*"; }
ok()    { printf '  OK: %s\n' "$1"; log "OK: $1"; }
skip()  { printf '  --: %s\n' "$1"; log "SKIP: $1"; }
would() { printf '  WOULD: %s\n' "$1"; log "WOULD: $1"; }
warn()  { printf '  WARNING: %s\n' "$1" >&2; log "WARN: $1"; }
die()   { printf '  ERROR: %s\n' "$1" >&2; log "FATAL: $1"; exit 1; }

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
${SCRIPT_NAME} v${SCRIPT_VERSION} — install Docker Desktop on Ubuntu (KVM sandbox)

Usage: ${SCRIPT_NAME} [OPTIONS]

Options:
  --version=<x.y.z>   Docker Desktop version to install (default: ${DEFAULT_DD_VERSION})
  --build=<id>        Docker CDN build number for that version (default: ${DEFAULT_DD_BUILD}).
                      Found in the install URL on the release notes page:
                      https://docs.docker.com/desktop/release-notes/
  --deb-url=<url>     Full .deb URL (overrides --version / --build entirely).
                      Use this if upstream URL conventions change.
  --checksum=sha256:<hex>
                      Optional sha256 of the .deb. If set, verified after
                      download — strongly recommended for production use,
                      since Docker's CDN doesn't ship a signed apt repo.
  --no-autostart      Skip enabling the docker-desktop user systemd service.
  --no-check          Skip the post-install smoke test.
  --dry-run           Print actions but make no system changes.
  --allow-unsupported-os
                      Proceed even if the detected Ubuntu codename is not on
                      Docker's officially supported list. Use this for brand-
                      new Ubuntu releases that Desktop hasn't yet certified.
                      The .deb install may still fail at dependency resolution.
  -V                  Print this script's version and exit.
  -h, --help          Show this help.

Coexistence with Docker Engine:
  Safe to run on a host that already has Docker Engine (docker-ce).
  Docker Desktop registers a 'desktop-linux' context alongside the existing
  'default' context. Switch with:  docker context use desktop-linux

Logs: ${LOG_FILE}
EOF
}

# ── Arg parsing ─────────────────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --no-check)        SKIP_SMOKE_TEST=1 ;;
        --no-autostart)    SKIP_AUTOSTART=1 ;;
        --dry-run)         DRY_RUN=1 ;;
        --allow-unsupported-os) ALLOW_UNSUPPORTED_OS=1 ;;
        --version=*)       DD_VERSION="${arg#--version=}" ;;
        --version)         printf 'Option --version requires a value: --version=x.y.z\n\n' >&2; usage >&2; exit 2 ;;
        --build=*)         DD_BUILD="${arg#--build=}" ;;
        --build)           printf 'Option --build requires a value: --build=<id>\n\n' >&2; usage >&2; exit 2 ;;
        --deb-url=*)       DD_DEB_URL="${arg#--deb-url=}" ;;
        --deb-url)         printf 'Option --deb-url requires a value: --deb-url=https://...\n\n' >&2; usage >&2; exit 2 ;;
        --checksum=*)      DD_CHECKSUM="${arg#--checksum=}" ;;
        --checksum)        printf 'Option --checksum requires a value: --checksum=sha256:<hex>\n\n' >&2; usage >&2; exit 2 ;;
        -V)                printf '%s %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"; exit 0 ;;
        -h|--help)         usage; exit 0 ;;
        *)                 printf 'Unknown option: %s\n\n' "$arg" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ ! "$DD_VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]]; then
    printf 'Invalid --version value: %q (expected x.y.z)\n' "$DD_VERSION" >&2
    exit 2
fi
if [[ ! "$DD_BUILD" =~ ^[0-9]+$ ]]; then
    printf 'Invalid --build value: %q (expected digits)\n' "$DD_BUILD" >&2
    exit 2
fi
if [[ -n "$DD_DEB_URL" && ! "$DD_DEB_URL" =~ ^https://[^[:space:]]+\.deb([?#].*)?$ ]]; then
    # Allow ports, query strings, fragments — Docker's CDN sometimes serves
    # signed redirect URLs with tokens. Only enforce https:// and .deb suffix
    # (possibly followed by ? or #).
    printf 'Invalid --deb-url value: %q (must be https://...deb[?...])\n' "$DD_DEB_URL" >&2
    exit 2
fi
if [[ -n "$DD_CHECKSUM" && ! "$DD_CHECKSUM" =~ ^sha256:[a-fA-F0-9]{64}$ ]]; then
    printf 'Invalid --checksum value: %q (expected sha256:<64-hex>)\n' "$DD_CHECKSUM" >&2
    exit 2
fi

# ── Helpers ─────────────────────────────────────────────────────────────────
require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

run_priv() {
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

run_as_target_user() {
    # systemctl --user only ever talks to the calling user's session manager,
    # so we must call it as the target user (not root) with the right
    # XDG_RUNTIME_DIR / DBUS_SESSION_BUS_ADDRESS pointing at their session.
    #
    # NOTE: `sudo -u USER VAR=val cmd` does NOT reliably inject env vars —
    # default sudoers refuses SETENV, and even when allowed, env_check
    # strips path-like values. Wrapping with `env` bypasses sudo's env
    # policy entirely (env sets its own environment, then execs).
    if (( DRY_RUN )); then
        printf '  [dry-run] (as %s) %s\n' "$TARGET_USER" "$(printf '%q ' "$@")"
        return 0
    fi
    if [[ "$EUID" -eq "$TARGET_UID" ]]; then
        XDG_RUNTIME_DIR="/run/user/${TARGET_UID}" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${TARGET_UID}/bus" \
            "$@"
    else
        sudo -u "$TARGET_USER" env \
            "XDG_RUNTIME_DIR=/run/user/${TARGET_UID}" \
            "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${TARGET_UID}/bus" \
            "$@"
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

join_words() {
    # Join args with a single space. Needed for user-facing messages because
    # IFS=$'\n\t' makes "${array[*]}" render with embedded newlines, which
    # produces ragged multi-line error/info strings.
    local IFS=' '
    printf '%s' "$*"
}

installed_pkg_version() {
    dpkg-query -W -f='${Version}\n' "$1" 2>/dev/null || true
}

# ── Step 0: prep log dir ───────────────────────────────────────────────────
ensure_log_dir() {
    if mkdir -p "$LOG_DIR" 2>/dev/null && : >> "$LOG_FILE" 2>/dev/null; then
        chmod 700 "$LOG_DIR" 2>/dev/null || true
        chmod 600 "$LOG_FILE" 2>/dev/null || true
        return
    fi
    local fb_dir="${TMPDIR:-/tmp}"
    local fb_file="${fb_dir}/docker-desktop-init-$(id -u).log"
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

    # Determine the *target user* — whose user-systemd we configure and whose
    # graphical session Docker Desktop ultimately runs in. If invoked via sudo,
    # that's SUDO_USER; otherwise it's the caller. Docker Desktop is per-user;
    # configuring it under root's systemd-user instance is wrong.
    if [[ $EUID -eq 0 ]]; then
        if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
            TARGET_USER="$SUDO_USER"
        else
            die "running as root with no SUDO_USER. Docker Desktop is a per-user app — re-run as your normal user (with sudo available)."
        fi
        ok "running as root, user-service target: $TARGET_USER"
        log "Step 1: root (target=$TARGET_USER)"
    else
        TARGET_USER="$(id -un)"
        require_cmd sudo
        if sudo -n true 2>/dev/null; then
            ok "sudo access verified (cached credentials)"
            log "Step 1: sudo cached (target=$TARGET_USER)"
        else
            say "  sudo password required:"
            if (( DRY_RUN )); then
                ok "[dry-run] would prompt for sudo"
            else
                sudo -v || die "sudo authentication failed"
                ok "sudo access verified"
            fi
            log "Step 1: sudo authenticated (target=$TARGET_USER)"
        fi
        if (( ! DRY_RUN )); then
            ( while true; do
                  sudo -n true 2>/dev/null || exit 0
                  sleep 50
                  kill -0 "$$" 2>/dev/null || exit 0
              done ) &
            SUDO_KEEPALIVE_PID=$!
        fi
    fi

    TARGET_UID="$(id -u "$TARGET_USER" 2>/dev/null)" \
        || die "cannot resolve UID for target user '$TARGET_USER'"
    local _pwent
    # Split getent and cut so pipefail+ERR doesn't fire opaquely if the user
    # row is missing. Default _pwent to empty on lookup failure.
    _pwent=$(getent passwd "$TARGET_USER" 2>/dev/null) || _pwent=""
    [[ -n "$_pwent" ]] \
        || die "no passwd entry for target user '$TARGET_USER'"
    TARGET_HOME=$(printf '%s' "$_pwent" | cut -d: -f6)
    [[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] \
        || die "cannot resolve home directory for target user '$TARGET_USER' (got: '${TARGET_HOME:-empty}')"
    log "Step 1: target_user=$TARGET_USER uid=$TARGET_UID home=$TARGET_HOME"
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
    OS_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"

    if [[ "${ID:-}" != "ubuntu" ]]; then
        die "Docker Desktop on Linux only supports Ubuntu (detected: ${ID:-unknown} / $PRETTY_NAME_DETECTED). For Debian and other distros, install Docker Engine via docker-init.sh."
    fi

    if [[ -z "$OS_CODENAME" ]] && command -v lsb_release >/dev/null 2>&1; then
        OS_CODENAME=$(lsb_release -cs 2>/dev/null || true)
    fi

    local supported=0
    for c in "${SUPPORTED_UBUNTU_CODENAMES[@]}"; do
        [[ "$OS_CODENAME" == "$c" ]] && supported=1 && break
    done
    if (( ! supported )); then
        local _list
        _list=$(join_words "${SUPPORTED_UBUNTU_CODENAMES[@]}")
        if (( ALLOW_UNSUPPORTED_OS )); then
            warn "Ubuntu '${OS_CODENAME:-unknown}' is not on Docker Desktop's supported list ($_list)."
            warn "Proceeding because --allow-unsupported-os was given. The .deb install may still fail."
            log "Step 2: unsupported codename allowed via flag: $OS_CODENAME"
        else
            die "Ubuntu '${OS_CODENAME:-unknown}' is not on Docker Desktop's supported list ($_list). Re-run with --allow-unsupported-os to proceed anyway (install may still fail at dependency resolution)."
        fi
    fi

    ok "$PRETTY_NAME_DETECTED  (codename: $OS_CODENAME)"
    log "Step 2: PRETTY=$PRETTY_NAME_DETECTED codename=$OS_CODENAME"
    say ""
}

# ── Step 3: architecture ───────────────────────────────────────────────────
check_arch() {
    say "── Step 3: architecture check ────────────────────────"
    local arch
    arch=$(dpkg --print-architecture)
    case "$arch" in
        amd64) DD_ARCH=amd64 ;;
        arm64) DD_ARCH=arm64 ;;
        *) die "unsupported architecture for Docker Desktop: $arch (supported: amd64, arm64)" ;;
    esac
    ok "architecture: $DD_ARCH"
    log "Step 3: arch=$DD_ARCH"
    say ""
}

# ── Step 4: hardware virtualization ───────────────────────────────────────
check_virtualization() {
    say "── Step 4: hardware virtualization check ─────────────"

    # CPU support flag: vmx for Intel VT-x, svm for AMD-V. If neither is
    # present, /dev/kvm never appears and Docker Desktop's qemu VM can't boot.
    if [[ "$DD_ARCH" == "amd64" ]]; then
        if grep -Eq '^flags[[:space:]]*:.*\b(vmx|svm)\b' /proc/cpuinfo; then
            ok "CPU virtualization extensions present (vmx/svm)"
        else
            die "CPU virtualization (VT-x / AMD-V) is not exposed by the kernel. Enable it in your BIOS/UEFI firmware (look for 'Intel Virtualization Technology' or 'SVM Mode') and reboot."
        fi
    fi

    # Warn if running inside a VM — nested KVM must be enabled by the parent
    # hypervisor for Docker Desktop's VM-in-VM setup to work.
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        local virt
        virt=$(systemd-detect-virt 2>/dev/null || true)
        if [[ "$virt" != "none" && -n "$virt" ]]; then
            warn "host appears virtualized (systemd-detect-virt: $virt). Nested KVM must be enabled in the parent hypervisor, or Docker Desktop will fail to boot its VM."
        fi
    fi

    log "Step 4 PASSED"
    say ""
}

# ── Step 5: install KVM packages ──────────────────────────────────────────
install_kvm_packages() {
    say "── Step 5: install KVM / qemu packages ───────────────"
    local kvm_packages=("${KVM_PACKAGES_COMMON[@]}")
    case "$DD_ARCH" in
        amd64) kvm_packages+=(qemu-system-x86) ;;
        arm64) kvm_packages+=(qemu-system-arm) ;;
        *)     die "no KVM package set for arch: $DD_ARCH" ;;
    esac
    local missing=()
    for pkg in "${kvm_packages[@]}"; do
        if package_installed "$pkg"; then
            skip "$pkg already installed"
        else
            missing+=("$pkg")
        fi
    done
    if (( ${#missing[@]} > 0 )); then
        local _list
        _list=$(join_words "${missing[@]}")
        apt_get update || die "apt-get update failed (see log)"
        apt_get install -y "${missing[@]}" \
            || die "failed to install KVM packages: $_list"
        if (( DRY_RUN )); then
            would "install: $_list"
        else
            ok "installed: $_list"
        fi
        mark_changed
        log "Step 5: installed $_list"
    else
        log "Step 5 SKIPPED: all KVM packages present"
    fi
    say ""
}

# ── Step 6: /dev/kvm + kvm group ──────────────────────────────────────────
configure_kvm_access() {
    say "── Step 6: configure /dev/kvm access ─────────────────"

    if (( DRY_RUN )) && [[ ! -e /dev/kvm ]]; then
        skip "[dry-run] /dev/kvm not present; would verify after kvm modules load"
    elif [[ ! -e /dev/kvm ]]; then
        local diag=""
        if command -v kvm-ok >/dev/null 2>&1; then
            diag=$(kvm-ok 2>&1 || true)
        fi
        die "/dev/kvm does not exist. Likely causes: virtualization disabled in firmware, kvm kernel module not loaded (try: sudo modprobe kvm_intel  or  kvm_amd), or host is a VM without nested virt. kvm-ok output: ${diag:-n/a}"
    else
        ok "/dev/kvm exists"
    fi

    if ! getent group kvm >/dev/null; then
        run_priv groupadd kvm || die "failed to create kvm group"
        if (( DRY_RUN )); then would "create kvm group"; else ok "created kvm group"; fi
        mark_changed
    fi

    if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx kvm; then
        skip "user '$TARGET_USER' already in kvm group"
        log "Step 6 SKIPPED: $TARGET_USER already in kvm group"
    else
        run_priv usermod -aG kvm "$TARGET_USER" \
            || die "usermod -aG kvm $TARGET_USER failed"
        if (( DRY_RUN )); then
            would "add '$TARGET_USER' to kvm group"
        else
            ok "added '$TARGET_USER' to kvm group"
        fi
        mark_changed
        KVM_GROUP_ADDED=1
        log "Step 6: added $TARGET_USER to kvm group"
    fi
    say ""
}

# ── Step 7: detect existing Docker Engine ─────────────────────────────────
check_engine_coexistence() {
    say "── Step 7: scan for existing Docker Engine ───────────"
    if package_installed docker-ce; then
        local v
        v=$(installed_pkg_version docker-ce)
        warn "docker-ce already installed (version: $v)"
        warn "Docker Desktop will install alongside and add a 'desktop-linux' context."
        warn "Switch between them with:"
        warn "  docker context use default        # Docker Engine (local socket)"
        warn "  docker context use desktop-linux  # Docker Desktop (VM)"
        log  "Step 7: docker-ce coexistence detected ($v)"
    else
        skip "no docker-ce installed"
        log "Step 7: no docker-ce"
    fi
    say ""
}

# ── Step 8: install desktop dependencies ──────────────────────────────────
install_dependencies() {
    say "── Step 8: install Docker Desktop dependencies ───────"
    local missing=()
    for pkg in "${DESKTOP_DEPS[@]}"; do
        if package_installed "$pkg"; then
            skip "$pkg already installed"
        else
            missing+=("$pkg")
        fi
    done
    if (( ${#missing[@]} > 0 )); then
        local _list
        _list=$(join_words "${missing[@]}")
        apt_get install -y "${missing[@]}" \
            || die "failed to install dependencies: $_list"
        if (( DRY_RUN )); then
            would "install: $_list"
        else
            ok "installed: $_list"
            # dbus-user-session only takes effect at next graphical login.
            # If the user just got it from this script, Step 11 will likely
            # fail to talk to the session bus.
            for pkg in "${missing[@]}"; do
                if [[ "$pkg" == "dbus-user-session" ]]; then
                    warn "dbus-user-session was just installed — log out and back in for user-systemd to fully activate before Step 11 can manage docker-desktop.service."
                fi
            done
        fi
        mark_changed
        log "Step 8: installed $_list"
    else
        log "Step 8 SKIPPED: all deps present"
    fi
    say ""
}

# ── Step 9: download Docker Desktop .deb ──────────────────────────────────
download_deb() {
    say "── Step 9: download Docker Desktop .deb ──────────────"
    require_cmd curl

    if [[ -z "$DD_DEB_URL" ]]; then
        DD_DEB_URL="https://desktop.docker.com/linux/main/${DD_ARCH}/${DD_BUILD}/docker-desktop-${DD_ARCH}.deb"
    fi

    local installed_v
    installed_v=$(installed_pkg_version docker-desktop)
    # Docker Desktop's package Version field sometimes carries a build suffix,
    # so accept a prefix match against $DD_VERSION as "already at target".
    if [[ -n "$installed_v" && "$installed_v" == "$DD_VERSION"* ]]; then
        skip "docker-desktop $installed_v already installed (matches $DD_VERSION)"
        log "Step 9 SKIPPED: already at $installed_v"
        DEB_LOCAL_PATH=""
        say ""
        return
    fi
    [[ -n "$installed_v" ]] && warn "docker-desktop $installed_v installed; will replace with $DD_VERSION"

    local deb_path="${CACHE_DIR}/docker-desktop-${DD_VERSION}-${DD_BUILD}-${DD_ARCH}.deb"

    # HEAD-probe the URL before any dry-run short-circuit: this is the only
    # check that catches a stale --build / --version pin, and it's read-only
    # so it's safe to run in dry-run too (mirrors probe_codename_available
    # in docker-init.sh).
    log "Step 9: HEAD probing $DD_DEB_URL"
    (( DRY_RUN )) && printf '  [dry-run] HEAD %s\n' "$DD_DEB_URL"
    if ! curl "${CURL_OPTS[@]}" --output /dev/null --head "$DD_DEB_URL" 2>/dev/null; then
        die "Docker Desktop .deb not found at $DD_DEB_URL. The pinned --version=$DD_VERSION / --build=$DD_BUILD likely doesn't match a real release. Look up the current URL at https://docs.docker.com/desktop/release-notes/ and re-run with --deb-url=<full-url>."
    fi
    ok "URL exists: $DD_DEB_URL"

    if (( DRY_RUN )); then
        would "mkdir -p $CACHE_DIR"
        would "download → $deb_path"
        if [[ -n "$DD_CHECKSUM" ]]; then
            would "verify ${DD_CHECKSUM%%:*} checksum after download"
        else
            warn "no --checksum supplied — integrity of the .deb will not be verified. Consider passing --checksum=sha256:<hex> in production."
        fi
        mark_changed
        DEB_LOCAL_PATH="$deb_path"
        say ""
        return
    fi

    run_priv mkdir -p "$CACHE_DIR" || die "failed to create cache dir: $CACHE_DIR"

    if [[ -s "$deb_path" ]]; then
        # A non-empty file isn't necessarily a valid .deb — a SIGKILL'd
        # previous run can leave a truncated archive behind. Validate the
        # control structure before trusting the cache (cheap: dpkg-deb only
        # reads the archive header).
        if ! dpkg-deb --info "$deb_path" >/dev/null 2>&1; then
            warn "cached .deb at $deb_path is corrupt or truncated; re-downloading"
            run_priv rm -f "$deb_path"
        elif [[ -n "$DD_CHECKSUM" ]]; then
            require_cmd sha256sum
            local _exp _got
            _exp="${DD_CHECKSUM#sha256:}"
            _got=$(sha256sum "$deb_path" 2>/dev/null | awk '{print $1}')
            if [[ "$_got" != "$_exp" ]]; then
                warn "cached .deb at $deb_path has wrong checksum (got ${_got:-empty}); re-downloading"
                run_priv rm -f "$deb_path"
            else
                ok "cached .deb checksum verified"
                skip "reusing cached .deb at $deb_path"
                log "Step 9: cache hit + checksum ok ($deb_path)"
                DEB_LOCAL_PATH="$deb_path"
                say ""
                return
            fi
        else
            skip "reusing cached .deb at $deb_path"
            log "Step 9: cache hit ($deb_path)"
            DEB_LOCAL_PATH="$deb_path"
            say ""
            return
        fi
    fi

    printf '  Downloading Docker Desktop %s (%s)... this takes a while\n' "$DD_VERSION" "$DD_ARCH"
    # Drop --silent so the user sees curl's progress bar. Bump --max-time:
    # the .deb is ~700 MB and Docker's CDN throttles on some networks.
    if ! run_priv curl --fail --show-error --location \
            --connect-timeout 10 --max-time 1800 \
            --retry 3 --retry-delay 2 \
            -o "$deb_path" "$DD_DEB_URL"; then
        run_priv rm -f "$deb_path"
        die "failed to download .deb from $DD_DEB_URL"
    fi
    [[ -s "$deb_path" ]] || { run_priv rm -f "$deb_path"; die "downloaded .deb is empty"; }

    if [[ -n "$DD_CHECKSUM" ]]; then
        require_cmd sha256sum
        local expected actual
        expected="${DD_CHECKSUM#sha256:}"
        actual=$(sha256sum "$deb_path" 2>/dev/null | awk '{print $1}')
        if [[ "$actual" != "$expected" ]]; then
            run_priv rm -f "$deb_path"
            die "checksum mismatch for $deb_path: expected $expected, got ${actual:-empty}. The download was either corrupted or tampered with — re-fetch and verify the --checksum value."
        fi
        ok "checksum verified (sha256)"
    else
        warn "no --checksum supplied — integrity of the .deb is not verified. Consider passing --checksum=sha256:<hex> in production."
    fi

    local size
    size=$(du -h "$deb_path" 2>/dev/null | cut -f1 || echo unknown)
    ok "downloaded: $deb_path ($size)"
    mark_changed
    log "Step 9 PASSED"
    DEB_LOCAL_PATH="$deb_path"
    say ""
}

# ── Step 10: install Docker Desktop .deb ──────────────────────────────────
install_docker_desktop() {
    say "── Step 10: install Docker Desktop ───────────────────"

    if [[ -z "$DEB_LOCAL_PATH" ]]; then
        log "Step 10 SKIPPED: nothing to install (already at target version)"
        say ""
        return
    fi

    if (( DRY_RUN )); then
        would "dpkg --configure -a (recover any half-installed state)"
        would "apt-get install -y $DEB_LOCAL_PATH"
        mark_changed
        say ""
        return
    fi

    # If a previous run was interrupted mid-apt, dpkg may be half-configured,
    # which causes the next `apt-get install` to fail opaquely. Recover first.
    run_priv dpkg --configure -a >/dev/null 2>&1 || true

    # `apt-get install ./file.deb` resolves the .deb's Depends: in a single
    # transaction. `dpkg -i` would leave broken deps to chase by hand.
    apt_get install -y "$DEB_LOCAL_PATH" \
        || die "apt-get install of $DEB_LOCAL_PATH failed (see log)"

    local installed_v
    installed_v=$(installed_pkg_version docker-desktop)
    ok "installed docker-desktop ${installed_v:-(version unknown)}"
    mark_changed
    log "Step 10 PASSED: $installed_v"
    say ""
}

# ── Step 11: enable user systemd service ──────────────────────────────────
enable_user_service() {
    say "── Step 11: enable Docker Desktop user service ───────"

    if (( SKIP_AUTOSTART )); then
        skip "autostart disabled by --no-autostart"
        log "Step 11 SKIPPED: --no-autostart"
        printf '      To start manually:  systemctl --user start docker-desktop\n'
        say ""
        return
    fi

    # In dry-run, the systemctl probe helpers all return 0, which makes the
    # is-enabled / is-active checks below falsely report the service as
    # already configured. Short-circuit with a clear preview instead.
    if (( DRY_RUN )); then
        would "enable docker-desktop user service for $TARGET_USER"
        would "start docker-desktop user service"
        mark_changed
        log "Step 11 (dry-run): would enable + start docker-desktop user service"
        say ""
        return
    fi

    # systemctl --user only talks to the calling user's session manager.
    # If the target user has no graphical session, /run/user/$UID/bus is
    # missing and the call fails with "Failed to connect to bus". Detect
    # that condition and surface a useful next step instead of crashing.
    if [[ ! -S "/run/user/${TARGET_UID}/bus" ]]; then
        warn "no active user D-Bus session for $TARGET_USER (no /run/user/${TARGET_UID}/bus)."
        warn "Skipping autostart. After your next graphical login, run:"
        warn "  systemctl --user enable --now docker-desktop"
        log "Step 11 SKIPPED: no user bus"
        say ""
        return
    fi

    local _err
    if run_as_target_user systemctl --user is-enabled --quiet docker-desktop 2>/dev/null; then
        skip "docker-desktop.service already enabled for $TARGET_USER"
        log "Step 11: already enabled"
    else
        _err=$(run_as_target_user systemctl --user enable docker-desktop 2>&1) && _err=""
        if [[ -z "$_err" ]]; then
            ok "enabled docker-desktop user service for $TARGET_USER"
            mark_changed
        else
            warn "failed to enable docker-desktop user service: $_err"
            log "Step 11 WARN: enable failed: $_err"
            say ""
            return
        fi
    fi

    if run_as_target_user systemctl --user is-active --quiet docker-desktop 2>/dev/null; then
        skip "docker-desktop.service already active"
    else
        _err=$(run_as_target_user systemctl --user start docker-desktop 2>&1) && _err=""
        if [[ -z "$_err" ]]; then
            ok "started docker-desktop user service"
            mark_changed
        else
            warn "could not start docker-desktop via systemctl --user: $_err"
            warn "First run may need a graphical launch to accept the EULA."
            log "Step 11 WARN: start failed: $_err"
        fi
    fi
    say ""
}

# ── Step 12: smoke test ───────────────────────────────────────────────────
smoke_test() {
    say "── Step 12: smoke test ───────────────────────────────"
    if (( SKIP_SMOKE_TEST )); then
        skip "smoke test skipped (--no-check)"
        log "Step 12 SKIPPED: --no-check"
        say ""
        return
    fi
    if (( DRY_RUN )); then
        skip "smoke test skipped (--dry-run)"
        say ""
        return
    fi

    require_cmd docker
    ok "docker CLI present: $(docker --version 2>/dev/null | head -n1)"

    # 'desktop-linux' is registered by the .deb's postinst, so it should be
    # visible immediately after install — even before the VM finishes booting.
    if docker context ls --format '{{.Name}}' 2>/dev/null | grep -qx desktop-linux; then
        ok "'desktop-linux' context registered"
    else
        warn "'desktop-linux' context not yet registered. First-run may require launching Docker Desktop from your application menu once."
        log "Step 12 WARN: desktop-linux context missing"
        say ""
        return
    fi

    # Give the VM up to 60s to come up — cold boot of the LinuxKit guest is
    # noticeably slower than `dockerd` starting on the host.
    local i=0
    until docker --context desktop-linux version >/dev/null 2>&1; do
        i=$((i + 1))
        if (( i > 60 )); then
            warn "Docker Desktop VM is not responding after 60s. It may still be initializing — wait a minute and retry: docker --context desktop-linux version"
            log "Step 12 WARN: VM not responsive within 60s"
            say ""
            return
        fi
        sleep 1
    done
    ok "Docker Desktop VM is responding via desktop-linux context"
    log "Step 12 PASSED: VM up"
    say ""
}

# ── Post-install tips ─────────────────────────────────────────────────────
# Surface non-obvious Docker Desktop settings the user is likely to want to
# know about: GUI flags that ship off-by-default, plus available CLI plugins.
# All checks are best-effort — silent if the relevant state isn't readable.
emit_tip_header() {
    (( TIPS_HEADER_PRINTED )) && return
    say ""
    say "  Tips you might not know:"
    TIPS_HEADER_PRINTED=1
}

print_optional_tips() {
    # Best-effort: every check below silently no-ops if the relevant state
    # isn't readable, so this is safe in dry-run and on fresh boxes too.
    local settings="${TARGET_HOME}/.docker/desktop/settings-store.json"

    if [[ -r "$settings" ]]; then
        # 'EnableDockerAI' gates Ask Gordon, the AI panel, and the related
        # GUI surfaces. The 'docker sandbox' / 'docker mcp' CLI plugins work
        # independently, but the GUI integration is gated by this flag.
        if grep -Eq '"EnableDockerAI"[[:space:]]*:[[:space:]]*false' "$settings"; then
            emit_tip_header
            say "    • Docker AI features (Ask Gordon, AI panel) are currently disabled."
            say "      Toggle: Docker Desktop → Settings → Features → 'Docker AI', or"
            say "      edit ~/.docker/desktop/settings-store.json: \"EnableDockerAI\": true"
            say "      Then: systemctl --user restart docker-desktop"
        fi

        # 'AutoStart' controls whether the user-systemd service auto-starts
        # on login. Off by default — most users want this on.
        if grep -Eq '"AutoStart"[[:space:]]*:[[:space:]]*false' "$settings"; then
            emit_tip_header
            say "    • Docker Desktop won't start automatically on login."
            say "      Toggle: Docker Desktop → Settings → General → 'Start when you log in', or"
            say "      edit ~/.docker/desktop/settings-store.json: \"AutoStart\": true"
        fi
    fi

    # Modern Docker Desktop (4.40+) ships 'docker sandbox' and 'docker mcp' as
    # CLI plugins for AI agent workflows. Surface them once they exist —
    # easy to miss otherwise.
    if command -v docker >/dev/null 2>&1 && docker sandbox --help >/dev/null 2>&1; then
        emit_tip_header
        say "    • docker sandbox / docker mcp are available for AI agent workflows:"
        say "        docker sandbox create --help     # provision an agent sandbox"
        say "        docker mcp --help                # MCP Toolkit (catalog, clients)"
    fi
}

# ── Main ───────────────────────────────────────────────────────────────────
main() {
    say "╔═══════════════════════════════════════════════════════════╗"
    printf '║  %s v%s%*s║\n' "$SCRIPT_NAME" "$SCRIPT_VERSION" \
        $((57 - ${#SCRIPT_NAME} - ${#SCRIPT_VERSION} - 2)) ""
    say "╚═══════════════════════════════════════════════════════════╝"
    (( DRY_RUN )) && say "  (dry-run mode — no changes will be applied)"
    say "  target: Docker Desktop ${DD_VERSION} (build ${DD_BUILD})"
    [[ -n "$DD_DEB_URL" ]] && say "  source: $DD_DEB_URL"
    say ""

    ensure_log_dir

    log "═══════════════════════════════════════════════════════════"
    log "$SCRIPT_NAME v$SCRIPT_VERSION started"
    log "user=$(id -un) uid=$(id -u) host=$(uname -nsr)"
    log "args: VERSION=$DD_VERSION BUILD=$DD_BUILD DEB_URL=${DD_DEB_URL:-(default-pattern)} CHECKSUM=${DD_CHECKSUM:-(none)} SKIP_SMOKE_TEST=$SKIP_SMOKE_TEST SKIP_AUTOSTART=$SKIP_AUTOSTART DRY_RUN=$DRY_RUN ALLOW_UNSUPPORTED_OS=$ALLOW_UNSUPPORTED_OS"
    log "═══════════════════════════════════════════════════════════"

    check_sudo
    check_os
    check_arch
    check_virtualization
    install_kvm_packages
    configure_kvm_access
    check_engine_coexistence
    install_dependencies
    download_deb
    install_docker_desktop
    enable_user_service
    smoke_test

    say "─────────────────────────────────────────────────────────"
    if (( CHANGED_COUNT == 0 )); then
        say "  ✓ Nothing to do — Docker Desktop is already properly installed."
        log "RESULT: 0 changes"
    elif (( DRY_RUN )); then
        say "  ✓ Would apply $CHANGED_COUNT change(s) (dry-run — no changes made)."
        log "RESULT: dry-run, $CHANGED_COUNT would-change(s)"
    else
        say "  ✓ Applied $CHANGED_COUNT change(s)."
        say "    Log: $LOG_FILE"
        log "RESULT: $CHANGED_COUNT changes"
    fi

    if (( KVM_GROUP_ADDED && ! DRY_RUN )); then
        say ""
        say "  IMPORTANT: log out and back in (or run: newgrp kvm)"
        say "             before launching Docker Desktop in this shell."
    fi

    say ""
    say "  Next:"
    say "    docker context use desktop-linux"
    say "    docker --context desktop-linux run --rm hello-world"
    say "    systemctl --user status docker-desktop"
    say "    tail -f $LOG_FILE"

    print_optional_tips

    say "─────────────────────────────────────────────────────────"
    say ""

    log "$SCRIPT_NAME completed cleanly"
}

main "$@"
