#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  geekbar :: config
#  Tracked defaults. Edit in-place to tune your bar.
#
#  Active-repo signal: the git widget reads
#  $XDG_CACHE_HOME/geekbar/active_repo, populated by the shell
#  hook in modules/45-geekbar-track.sh. Enable it with:
#      bx enable geekbar-track
#  Until terminals start writing that file, the widget falls
#  back to a hardcoded conventional-roots scan (see
#  find_active_repo in lib.sh) — not user-configurable.
# ─────────────────────────────────────────────────────────────

# BAR_WIDGETS — left-to-right order on the compact panel. Empty list = blank bar.
# Each widget's bar may self-suppress (return empty) when its condition is not met;
# see widgets/<section>.sh for per-widget behavior.
BAR_WIDGETS=(
    uptime       # heartbeat
    git          # heartbeat — only when in/under a tracked repo
    k8s          # heartbeat — only when kubectl context configured
    cloud        # heartbeat — only when AWS/GCP/Azure profile detected
    vpn          # alarm — only when a VPN connection is active
    docker       # heartbeat — only when ≥1 container running
    cpu          # heartbeat (temp °C)
    ram          # heartbeat (spark + used GB)
    net          # heartbeat (rx/tx) — only when an interface is up
    disk         # alarm — only when a mount's used% ≥ DISK_PCT_WARN
    top_proc     # alarm — only when CPU% or MEM% above threshold
    mic          # alarm — only when mic is muted
    weather      # heartbeat — only when location available
    # nepse      # opt-in: uncomment to show NEPSE during market hours
    # ports      # opt-in: bar segment showing count + listening DEV_PORTS
)

# MENU_SECTIONS — top-to-bottom in the dropdown. Each maps to a widget set.
MENU_SECTIONS=(
    context      # git, k8s, cloud, vpn — "what am I touching"
    system       # uptime, cpu, ram, load, top_proc, disk
    network      # net (iface/ssid/local-ip/public-ip/rates)
    dev          # docker, ports
    audio        # vol, mic
    extras       # weather, nepse
)

# Per-section widget membership (used by the menu loop).
MENU_SECTION_context=(git k8s cloud vpn)
MENU_SECTION_system=(uptime cpu ram load top_proc disk)
MENU_SECTION_network=(net)
MENU_SECTION_dev=(docker ports)
MENU_SECTION_audio=(vol mic)
MENU_SECTION_extras=(weather)

# ── weather location override ────────────────────────────────
# Leave empty for auto-detect via IP geolocation.
# Set to a city for explicit control, e.g. "Kathmandu" or "Berlin".
WEATHER_LOCATION=""

# ── thresholds ───────────────────────────────────────────────
# Two tiers: WARN (yellow) and CRIT (red).
CPU_TEMP_WARN=75          # °C
CPU_TEMP_CRIT=88

RAM_PCT_WARN=80           # %
RAM_PCT_CRIT=92

DISK_PCT_WARN=80          # %  — alarm when any tracked mount used% ≥ this
DISK_PCT_CRIT=92          # %  — critical (bar shows "!" prefix)

# Load average threshold is expressed as a multiplier of core count.
# On an 8-core machine, LOAD_WARN_MULT=0.8 means warn at load >= 6.4
LOAD_WARN_MULT="0.8"
LOAD_CRIT_MULT="1.2"

# ── k8s danger context ───────────────────────────────────────
# Regex matched against the kubectl context name. When it matches,
# the bar segment is prefixed with a ⚠ and the menu row is red.
K8S_DANGER_CONTEXTS="prod|production|live"

# ── dev-port watchlist ───────────────────────────────────────
# Ports the `ports` widget tracks. Edit to match your stack.
# Defaults: React/Next 3000, Angular 4200, Vite 5173, Postgres 5432,
# Redis 6379, Django/Flask 8000, generic 8080, Prometheus 9090.
DEV_PORTS=(3000 4200 5173 5432 6379 8000 8080 9090)

# ── colors (Pango markup, used in dropdown) ──────────────────
# Compact bar colors are inherited from your GNOME theme by default.
# These only affect the expanded dropdown menu.
COLOR_OK="#a6e3a1"
COLOR_WARN="#f9e2af"
COLOR_CRIT="#f38ba8"
COLOR_DIM="#6c7086"
COLOR_ACCENT="#89b4fa"

# ── network interface detection ──────────────────────────────
# Leave empty for auto-detect (picks the default-route interface).
# Set explicitly if auto-detect picks the wrong one, e.g. "wlp3s0".
NET_IFACE=""

# ── refresh tiers ────────────────────────────────────────────
# Argos refreshes the whole script on its filename interval (2s).
# These are internal cache TTLs for expensive operations.
CACHE_TTL_SLOW=15     # seconds — docker, local IP
CACHE_TTL_LAZY=60     # seconds — uptime text, SSID, git
CACHE_TTL_COLD=300    # seconds — kernel, public IP, NEPSE
CACHE_TTL_WEATHER=900 # seconds — weather (wttr.in is rate-limited)
CACHE_TTL_GEO=3600    # seconds — IP geolocation (you're not teleporting)
