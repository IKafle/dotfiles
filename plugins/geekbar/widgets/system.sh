#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  geekbar :: widgets/system
#  uptime · cpu · ram · load · top_proc · disk
# ─────────────────────────────────────────────────────────────

# ── uptime ───────────────────────────────────────────────────
widget_uptime_bar() {
    local sec; sec=$(awk '{print int($1)}' /proc/uptime)
    printf ' %s' "$(compact_duration "$sec")"
}

widget_uptime_menu() {
    local sec; sec=$(awk '{print int($1)}' /proc/uptime)
    local kernel; kernel=$(cache_get kernel "$CACHE_TTL_COLD" uname -r)
    argos_item " Kernel      $kernel"
    argos_item " Uptime      $(human_duration "$sec")"
}

# ── cpu ──────────────────────────────────────────────────────
widget_cpu_bar() {
    local t; t=$(cpu_temp)
    printf ' %s°' "$t"
}

widget_cpu_menu() {
    local temp freq ghz usage color
    temp=$(cpu_temp)
    freq=$(cpu_freq_mhz)
    ghz=$(awk -v m="$freq" 'BEGIN { printf "%.1f", m/1000 }')
    usage=$(cpu_usage_pct)
    color=$(color_for "$temp" "$CPU_TEMP_WARN" "$CPU_TEMP_CRIT")
    argos_item " CPU         ${ghz}GHz · ${temp}°C · ${usage}%" "$color"
}

# ── ram ──────────────────────────────────────────────────────
widget_ram_bar() {
    local pct used total spark
    read -r pct used total < <(ram_info)
    spark=$(sparkline "$pct" 4 ram)
    printf '%s %sG' "$spark" "$used"
}

widget_ram_menu() {
    local pct used total color
    read -r pct used total < <(ram_info)
    color=$(color_for "$pct" "$RAM_PCT_WARN" "$RAM_PCT_CRIT")
    argos_item " RAM         ${used}G / ${total}G  (${pct}%)" "$color"
}

# ── load ─────────────────────────────────────────────────────
# (no bar segment — menu-only)
widget_load_bar() { :; }

widget_load_menu() {
    local l1 l5 l15 _ cores
    read -r l1 l5 l15 _ < /proc/loadavg
    cores=$(nproc)
    argos_item "󰖶 Load        ${l1}  ${l5}  ${l15}  (${cores} cores)"
}

# ── top_proc ─────────────────────────────────────────────────
# Smart-picks whichever is the bigger proportional offender:
# CPU% (normalized to single-core scale) vs MEM%. Glyph differs.
widget_top_proc_bar() {
    local top_raw top_mem_raw
    local top_name top_pid top_cpu top_mem top_args
    local m_name m_pid m_cpu m_pct m_args
    local cores cpu_norm pct_int short kind
    cores=$(nproc)

    top_raw=$(top_cpu_proc)
    [[ -n "$top_raw" ]] && IFS='|' read -r top_name top_pid top_cpu top_mem top_args <<< "$top_raw"

    top_mem_raw=$(top_mem_proc)
    [[ -n "$top_mem_raw" ]] && IFS='|' read -r m_name m_pid m_cpu m_pct m_args <<< "$top_mem_raw"

    cpu_norm=0
    if [[ -n "${top_cpu:-}" ]] && (( cores > 0 )); then
        cpu_norm=$(awk -v c="$top_cpu" -v n="$cores" 'BEGIN { printf "%.1f", c/n }')
    fi

    local bar_name="" bar_pct=""
    if (( $(echo "$cpu_norm >= ${m_pct:-0}" | bc -l 2>/dev/null || echo 0) )); then
        bar_name="${top_name:-}"
        [[ -n "${top_cpu:-}" ]] && bar_pct=$(printf "%.0f" "$top_cpu")
        kind="CPU"
    else
        bar_name="${m_name:-}"
        [[ -n "${m_pct:-}" ]] && bar_pct=$(printf "%.0f" "$m_pct")
        kind="MEM"
    fi

    [[ -z "$bar_name" ]] && return
    short="${bar_name:0:10}"
    if [[ "$kind" == "CPU" ]]; then
        printf '󰓅 %s %s%%' "$short" "$bar_pct"
    else
        printf ' %s %s%%' "$short" "$bar_pct"
    fi
}

widget_top_proc_menu() {
    local raw name pid cpu mem args
    raw=$(top_cpu_proc)
    if [[ -n "$raw" ]]; then
        IFS='|' read -r name pid cpu mem args <<< "$raw"
        argos_item "󰓅 Top CPU     ${name} (${cpu}%) pid=${pid}"
    fi
    raw=$(top_mem_proc)
    if [[ -n "$raw" ]]; then
        IFS='|' read -r name pid cpu mem args <<< "$raw"
        argos_item " Top MEM     ${name} (${mem}%) pid=${pid}"
    fi
}

# ── disk ─────────────────────────────────────────────────────
# Cached raw df output: mount, used (1K), size (1K), pct%.
# Filters out pseudo/transient mounts; callers parse from here.
_disk_raw() {
    cache_get disk.usage 30 df --local --output=target,used,size,pcent \
        | awk 'NR>1 {
            t=$1
            if (t ~ /^\/boot/)     next
            if (t ~ /^\/snap/)     next
            if (t ~ /^\/var\/snap/) next
            if (t ~ /^\/run/)      next
            if (t ~ /^\/dev/)      next
            if (t ~ /^\/proc/)     next
            if (t ~ /^\/sys/)      next
            if (t ~ /^\/tmp/)      next
            pct=$4; sub(/%/, "", pct)
            print t, $2, $3, pct
        }'
}

widget_disk_bar() {
    local raw worst_mount="" worst_pct=0 mount used size pct
    raw=$(_disk_raw)
    [[ -z "$raw" ]] && return
    while read -r mount used size pct; do
        [[ -z "$mount" ]] && continue
        if (( pct >= DISK_PCT_WARN )) && (( pct > worst_pct )); then
            worst_pct=$pct
            worst_mount=$mount
        fi
    done <<< "$raw"
    [[ -z "$worst_mount" ]] && return

    local short
    if [[ "$worst_mount" == "/" ]]; then
        short="/"
    else
        short="${worst_mount##*/}"
    fi
    if (( worst_pct >= DISK_PCT_CRIT )); then
        printf '!  %s %d%%' "$short" "$worst_pct"
    else
        printf ' %s %d%%' "$short" "$worst_pct"
    fi
}

widget_disk_menu() {
    local raw rows mount used size pct color used_b size_b used_h size_h
    raw=$(_disk_raw)
    if [[ -z "$raw" ]]; then
        argos_dim " Disk         no tracked mounts"
        return
    fi
    rows=$(printf "%s\n" "$raw" | sort -k4 -n -r)
    while read -r mount used size pct; do
        [[ -z "$mount" ]] && continue
        used_b=$(( used * 1024 ))
        size_b=$(( size * 1024 ))
        used_h=$(human_bytes "$used_b")
        size_h=$(human_bytes "$size_b")
        color=$(color_for "$pct" "$DISK_PCT_WARN" "$DISK_PCT_CRIT")
        argos_item " $(printf '%-12s %s/%s  (%d%%)' "$mount" "$used_h" "$size_h" "$pct")" "$color"
    done <<< "$rows"
}
