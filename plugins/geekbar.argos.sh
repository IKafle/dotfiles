#!/usr/bin/env bash
# bx-purpose: GNOME panel widget showing system stats (CPU, mem, disk, net)
# bx-plugin-kind: argos
# bx-plugin-target: ~/.config/argos/geekbar.2s+.sh
# ─────────────────────────────────────────────────────────────
#  geekbar :: main
#  Compact status bar + expanded dropdown menu.
#  Runs every 2s via Argos (filename: geekbar.2s+.sh)
# ─────────────────────────────────────────────────────────────

GEEKBAR_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/geekbar"
# shellcheck source=/dev/null
source "$GEEKBAR_DIR/config.sh"
# shellcheck source=/dev/null
source "$GEEKBAR_DIR/lib.sh"

# ═════════════════════════════════════════════════════════════
#  GATHER DATA
# ═════════════════════════════════════════════════════════════

# ── system (cold cache, 5min) ────────────────────────────────
KERNEL=$(cache_get kernel "$CACHE_TTL_COLD" uname -r)

# ── uptime ──────────────────────────────────────────────────
UPTIME_SEC=$(awk '{print int($1)}' /proc/uptime)
UPTIME_COMPACT=$(compact_duration "$UPTIME_SEC")
UPTIME_LONG=$(human_duration "$UPTIME_SEC")

# ── cpu ──────────────────────────────────────────────────────
CPU_TEMP=$(cpu_temp)
CPU_FREQ=$(cpu_freq_mhz)
CPU_FREQ_GHZ=$(awk -v m="$CPU_FREQ" 'BEGIN { printf "%.1f", m/1000 }')
CPU_USAGE=$(cpu_usage_pct)
CORES=$(nproc)

# ── ram ──────────────────────────────────────────────────────
read -r RAM_PCT RAM_USED_GB RAM_TOTAL_GB < <(ram_info)
RAM_SPARK=$(sparkline "$RAM_PCT" 4 ram)

# ── load ─────────────────────────────────────────────────────
read -r LOAD1 LOAD5 LOAD15 _ < /proc/loadavg

# ── network ──────────────────────────────────────────────────
IFACE=$(get_default_iface)
if [[ -n "$IFACE" ]]; then
    RX_RATE=$(net_rate "$IFACE" rx)
    TX_RATE=$(net_rate "$IFACE" tx)
    RX_H=$(human_bytes "$RX_RATE")
    TX_H=$(human_bytes "$TX_RATE")
    LOCAL_IP=$(cache_get "localip.$IFACE" "$CACHE_TTL_SLOW" \
        bash -c "ip -4 addr show '$IFACE' | awk '/inet / {print \$2}' | cut -d/ -f1")
    SSID=$(cache_get "ssid.$IFACE" "$CACHE_TTL_LAZY" \
        bash -c "iwgetid -r 2>/dev/null || true")
else
    RX_H="—"; TX_H="—"; LOCAL_IP=""; SSID=""
fi
PUBLIC_IP=$(cache_get publicip "$CACHE_TTL_COLD" \
    bash -c "curl -fsS --max-time 3 https://ifconfig.me 2>/dev/null || echo '—'")

# ── audio ────────────────────────────────────────────────────
VOL=""; MUTED=0; MIC_MUTED=1
if (( ENABLE_AUDIO )); then
    VOL=$(volume_pct)
    MUTED=$(is_muted)
    MIC_MUTED=$(is_mic_muted)
fi

# ── weather ──────────────────────────────────────────────────
WEATHER_TEMP=""; WEATHER_DETAIL=""; WEATHER_LOC=""
if (( ENABLE_WEATHER )); then
    if [[ -n "$WEATHER_LOCATION" ]]; then
        WEATHER_LOC="$WEATHER_LOCATION"
    else
        WEATHER_LOC=$(cache_get geoloc "$CACHE_TTL_GEO" geo_location)
    fi
    if [[ -n "$WEATHER_LOC" ]]; then
        WEATHER_TEMP=$(cache_get "weather.$WEATHER_LOC" "$CACHE_TTL_WEATHER" \
            weather_compact "$WEATHER_LOC")
        WEATHER_DETAIL=$(cache_get "weatherfull.$WEATHER_LOC" "$CACHE_TTL_WEATHER" \
            weather_full "$WEATHER_LOC")
    fi
fi

# ── NEPSE ────────────────────────────────────────────────────
NEPSE_IDX=""; NEPSE_CHG=""; NEPSE_PCT=""; NEPSE_OPEN=0
if (( ENABLE_NEPSE )); then
    NEPSE_OPEN=$(nepse_is_market_open)
    NEPSE_RAW=$(cache_get nepse "$CACHE_TTL_COLD" nepse_fetch)
    if [[ -n "$NEPSE_RAW" ]]; then
        IFS='|' read -r NEPSE_IDX NEPSE_CHG NEPSE_PCT <<< "$NEPSE_RAW"
    fi
fi

# ── top process (always visible) ─────────────────────────────
# Gather both: top-by-CPU and top-by-MEM, then pick whichever is
# the bigger proportional offender for the bar display.
TOP_NAME=""; TOP_PID=""; TOP_CPU=""; TOP_MEM=""; TOP_ARGS=""
TOP_MEM_NAME=""; TOP_MEM_PID=""; TOP_MEM_CPU=""; TOP_MEM_PCT=""; TOP_MEM_ARGS=""
BAR_PROC_NAME=""; BAR_PROC_PCT=""; BAR_PROC_KIND=""   # kind: CPU | MEM

if (( ENABLE_TOP_PROC )); then
    TOP_RAW=$(top_cpu_proc)
    [[ -n "$TOP_RAW" ]] && IFS='|' read -r TOP_NAME TOP_PID TOP_CPU TOP_MEM TOP_ARGS <<< "$TOP_RAW"

    TOP_MEM_RAW=$(top_mem_proc)
    [[ -n "$TOP_MEM_RAW" ]] && IFS='|' read -r TOP_MEM_NAME TOP_MEM_PID TOP_MEM_CPU TOP_MEM_PCT TOP_MEM_ARGS <<< "$TOP_MEM_RAW"

    # Normalize CPU% to single-core scale so it compares fairly with MEM%.
    # ps reports CPU% as sum across cores (800% possible on 8-core system).
    # Divide by core count → now both values are 0-100 of the total resource.
    CPU_NORM=0
    if [[ -n "$TOP_CPU" ]] && (( CORES > 0 )); then
        CPU_NORM=$(awk -v c="$TOP_CPU" -v n="$CORES" 'BEGIN { printf "%.1f", c/n }')
    fi

    # Pick the bigger offender
    if (( $(echo "$CPU_NORM >= ${TOP_MEM_PCT:-0}" | bc -l 2>/dev/null || echo 0) )); then
        BAR_PROC_NAME="$TOP_NAME"
        BAR_PROC_PCT=$(printf "%.0f" "$TOP_CPU")   # show raw CPU% (can be >100 on multi-core hogs)
        BAR_PROC_KIND="CPU"
    else
        BAR_PROC_NAME="$TOP_MEM_NAME"
        BAR_PROC_PCT=$(printf "%.0f" "$TOP_MEM_PCT")
        BAR_PROC_KIND="MEM"
    fi
fi

# ── docker ───────────────────────────────────────────────────
DOCKER_N=""
if (( ENABLE_DOCKER )); then
    DOCKER_N=$(cache_get docker "$CACHE_TTL_SLOW" bash -c 'docker ps -q 2>/dev/null | wc -l')
    [[ "$DOCKER_N" == "0" ]] && DOCKER_N=""
fi

# ── git ──────────────────────────────────────────────────────
GIT_LINE=""; GIT_REPO=""
G_BRANCH=""; G_AHEAD=0; G_BEHIND=0; G_DIRTY=0; G_PATH=""
if (( ENABLE_GIT )); then
    GIT_REPO=$(cache_get gitrepo "$CACHE_TTL_LAZY" find_active_repo)
    if [[ -n "$GIT_REPO" ]]; then
        GIT_RAW=$(cache_get gitstatus "$CACHE_TTL_LAZY" git_status "$GIT_REPO")
        if [[ -n "$GIT_RAW" ]]; then
            IFS='|' read -r G_BRANCH G_AHEAD G_BEHIND G_DIRTY G_PATH <<< "$GIT_RAW"
            GIT_COMPACT=" $G_BRANCH"
            (( G_AHEAD  > 0 )) && GIT_COMPACT+=" ↑$G_AHEAD"
            (( G_BEHIND > 0 )) && GIT_COMPACT+=" ↓$G_BEHIND"
            (( G_DIRTY  > 0 )) && GIT_COMPACT+=" ●$G_DIRTY"
            GIT_LINE="$GIT_COMPACT"
        fi
    fi
fi

# ═════════════════════════════════════════════════════════════
#  BUILD COMPACT BAR LABEL
# ═════════════════════════════════════════════════════════════

BAR=""
(( ENABLE_UPTIME )) && BAR+=" $UPTIME_COMPACT"
(( ENABLE_CPU    )) && BAR+="  │  ${CPU_TEMP}°"
(( ENABLE_RAM    )) && BAR+="  │ $RAM_SPARK ${RAM_USED_GB}G"
(( ENABLE_NET    )) && [[ -n "$IFACE" ]] && BAR+="  │  ↓${RX_H} ↑${TX_H}"

# Mic muted → show warning glyph only when muted.
if (( ENABLE_AUDIO )) && [[ "$MIC_MUTED" == "1" ]]; then
    BAR+="  │ 󰍭"
fi

# Weather: show if we have a reading
if (( ENABLE_WEATHER )) && [[ -n "$WEATHER_TEMP" ]]; then
    BAR+="  │ 󰖐 $WEATHER_TEMP"
fi

# NEPSE: only during market hours
if (( ENABLE_NEPSE )) && [[ "$NEPSE_OPEN" == "1" ]] && [[ -n "$NEPSE_PCT" ]]; then
    NEPSE_PCT_FMT=$(awk -v p="$NEPSE_PCT" 'BEGIN { printf "%+.2f", p }')
    BAR+="  │  ${NEPSE_PCT_FMT}%"
fi

# Top process: always visible — smart-picks CPU or MEM as the bigger offender.
# Glyph changes: 󰓅 CPU hog,  memory hog.
if [[ -n "$BAR_PROC_NAME" ]]; then
    PROC_NAME_SHORT="${BAR_PROC_NAME:0:10}"
    if [[ "$BAR_PROC_KIND" == "CPU" ]]; then
        BAR+="  │ 󰓅 ${PROC_NAME_SHORT} ${BAR_PROC_PCT}%"
    else
        BAR+="  │  ${PROC_NAME_SHORT} ${BAR_PROC_PCT}%"
    fi
fi

[[ -n "$DOCKER_N" ]] && BAR+="  │  $DOCKER_N"
[[ -n "$GIT_LINE" ]] && BAR+="  │ $GIT_LINE"

BAR="${BAR# }"
printf '%s | font="JetBrainsMono Nerd Font" size=11\n' "$BAR"

# ═════════════════════════════════════════════════════════════
#  DROPDOWN MENU
# ═════════════════════════════════════════════════════════════
argos_sep

echo "geekbar | color=$COLOR_ACCENT size=10"
echo "---"

# ── System ──
argos_dim "── System ──"
argos_item " Kernel      $KERNEL"
argos_item " Uptime      $UPTIME_LONG"

CPU_COLOR=$(color_for "$CPU_TEMP" "$CPU_TEMP_WARN" "$CPU_TEMP_CRIT")
argos_item " CPU         ${CPU_FREQ_GHZ}GHz · ${CPU_TEMP}°C · ${CPU_USAGE}%" "$CPU_COLOR"

RAM_COLOR=$(color_for "$RAM_PCT" "$RAM_PCT_WARN" "$RAM_PCT_CRIT")
argos_item " RAM         ${RAM_USED_GB}G / ${RAM_TOTAL_GB}G  (${RAM_PCT}%)" "$RAM_COLOR"

argos_item "󰖶 Load        ${LOAD1}  ${LOAD5}  ${LOAD15}  (${CORES} cores)"

echo "---"

# ── Network ──
argos_dim "── Network ──"
if [[ -n "$IFACE" ]]; then
    argos_item "󰛳 Interface   $IFACE"
    [[ -n "$SSID"     ]] && argos_item "󰖩 SSID        $SSID"
    [[ -n "$LOCAL_IP" ]] && argos_item " Local IP    $LOCAL_IP"
    argos_item " Public IP   $PUBLIC_IP"
    argos_item " Download    $RX_H/s"
    argos_item " Upload      $TX_H/s"
else
    argos_item " No network" "$COLOR_WARN"
fi

echo "---"

# ── Dev ──
argos_dim "── Dev ──"

# Docker: list running containers with names + images + uptime
if [[ -n "$DOCKER_N" ]]; then
    argos_item " Docker      $DOCKER_N containers running" "$COLOR_OK"
    # Pull container details (cached briefly so we don't hit docker on every tick)
    DOCKER_LIST=$(cache_get dockerlist "$CACHE_TTL_SLOW" \
        bash -c 'docker ps --format "{{.Names}}|{{.Image}}|{{.Status}}" 2>/dev/null')
    if [[ -n "$DOCKER_LIST" ]]; then
        while IFS='|' read -r d_name d_image d_status; do
            [[ -z "$d_name" ]] && continue
            # Trim image tag noise, clamp long names
            d_image_short="${d_image##*/}"
            d_image_short="${d_image_short:0:25}"
            d_name_short="${d_name:0:20}"
            argos_item "   $d_name_short  $d_image_short" "$COLOR_ACCENT"
            argos_item "     $d_status" "$COLOR_DIM"
        done <<< "$DOCKER_LIST"
    fi
    # Management actions
    echo "▶ docker ps (full) | bash='$GEEKBAR_DIR/geekbar-actions.sh docker-ps' terminal=false"
    echo "📊 docker stats | bash='$GEEKBAR_DIR/geekbar-actions.sh docker-stats' terminal=false"
    echo "🧹 Prune unused | bash='$GEEKBAR_DIR/geekbar-actions.sh docker-prune' terminal=false"
else
    argos_item " Docker      idle" "$COLOR_DIM"
    # Even when idle, offer the management entrypoint
    if command -v docker >/dev/null 2>&1; then
        echo "📊 docker stats | bash='$GEEKBAR_DIR/geekbar-actions.sh docker-stats' terminal=false"
        echo "🧹 Prune unused | bash='$GEEKBAR_DIR/geekbar-actions.sh docker-prune' terminal=false"
    fi
fi

if [[ -n "$GIT_LINE" ]]; then
    GIT_DETAIL="$G_BRANCH"
    (( G_AHEAD  > 0 )) && GIT_DETAIL+=" ↑$G_AHEAD"
    (( G_BEHIND > 0 )) && GIT_DETAIL+=" ↓$G_BEHIND"
    (( G_DIRTY  > 0 )) && GIT_DETAIL+=" ●$G_DIRTY"
    argos_item " Git         $GIT_DETAIL"
    argos_item "   $G_PATH" "$COLOR_DIM"
else
    argos_item " Git         no active repo" "$COLOR_DIM"
fi

echo "---"

# ── Actions ──
argos_dim "── Actions ──"
echo " Refresh now | refresh=true"
echo " Edit config | bash='$GEEKBAR_DIR/geekbar-actions.sh edit-config' terminal=false"
echo " Open config folder | bash='$GEEKBAR_DIR/geekbar-actions.sh open-config-folder' terminal=false"
echo " Open htop | bash='$GEEKBAR_DIR/geekbar-actions.sh open-htop' terminal=false"
