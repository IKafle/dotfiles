#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  geekbar :: widgets/system
#  uptime · cpu · ram · load · top_proc · disk · iowait · battery
# ─────────────────────────────────────────────────────────────

# ── uptime ───────────────────────────────────────────────────
widget_uptime_bar() {
    local sec; sec=$(awk '{print int($1)}' /proc/uptime)
    printf ' %s' "$(compact_duration "$sec")"
}

widget_uptime_menu() {
    # Menu-only signal of low value — GNOME shows wall time; uptime is
    # rarely actionable. Suppress; users can bring it back by editing.
    return
}

# ── cpu ──────────────────────────────────────────────────────
widget_cpu_bar() {
    local t usage bucket="ok"
    t=$(cpu_temp)
    usage=$(cpu_usage_pct)
    if   (( t >= CPU_TEMP_CRIT )); then bucket="crit"
    elif (( t >= CPU_TEMP_WARN )); then bucket="warn"
    fi
    notify_edge cpu "$bucket" "🔥 CPU $bucket" "${t}°C — ${usage}% load"
    printf '%s %s %s' \
        "$(bar_icon "")" \
        "$(bar_val "${usage}%" "$(bar_thr "$usage" 50 80)")" \
        "$(bar_val "${t}°" "$(bar_thr "$t" "$CPU_TEMP_WARN" "$CPU_TEMP_CRIT")")"
}

widget_cpu_menu() {
    local temp freq ghz usage gauge_str tooltip danger="" dot
    temp=$(cpu_temp)
    freq=$(cpu_freq_mhz)
    ghz=$(awk -v m="$freq" 'BEGIN { printf "%.1f", m/1000 }')
    usage=$(cpu_usage_pct)
    [[ "$usage" =~ ^[0-9]+$ ]] || usage=0
    gauge_str=$(gauge "$usage" 8 50 80)
    dot="<span color=\"$COLOR_DIM\">·</span>"
    (( temp >= CPU_TEMP_CRIT )) && danger="   $(chip_crit HOT)"
    tooltip="CPU usage=${usage}%  temp=${temp}°C  freq=${ghz}GHz"
    pri_row 1 " CPU   ${gauge_str}   $(printf '%3s' "${usage}")%   ${dot}   ${temp}°C${danger}" \
        "$__DIR__/actions.sh open-htop" true "$tooltip"
}

# ── ram ──────────────────────────────────────────────────────
widget_ram_bar() {
    local pct used total bucket="ok"
    read -r pct used total < <(ram_info)
    if   (( pct >= RAM_PCT_CRIT )); then bucket="crit"
    elif (( pct >= RAM_PCT_WARN )); then bucket="warn"
    fi
    notify_edge ram "$bucket" "🧠 RAM $bucket" "${pct}% used (${used} / ${total} GB)"
    printf '%s %s' \
        "$(bar_icon "")" \
        "$(bar_val "${used}G" "$(bar_thr "$pct" "$RAM_PCT_WARN" "$RAM_PCT_CRIT")")"
}

widget_ram_menu() {
    local pct used total gauge_str tooltip dot
    read -r pct used total < <(ram_info)
    [[ "$pct" =~ ^[0-9]+$ ]] || pct=0
    gauge_str=$(gauge "$pct" 8 "$RAM_PCT_WARN" "$RAM_PCT_CRIT")
    dot="<span color=\"$COLOR_DIM\">·</span>"
    tooltip="RAM used=${used}G total=${total}G (${pct}%)"
    pri_row 1 " RAM   ${gauge_str}   $(printf '%3s' "${pct}")%   ${dot}   ${used}G / ${total}G" \
        "$__DIR__/actions.sh open-htop" true "$tooltip"
}

# ── load ─────────────────────────────────────────────────────
# (no bar segment — menu-only)
widget_load_bar() { :; }

widget_load_menu() {
    # Only render when load exceeds the warn threshold; otherwise hidden.
    local l1 _ cores warn crit chip_label tooltip
    read -r l1 _ < /proc/loadavg
    cores=$(nproc)
    warn=$(awk -v c="$cores" -v m="${LOAD_WARN_MULT:-0.8}" 'BEGIN { printf "%.2f", c*m }')
    crit=$(awk -v c="$cores" -v m="${LOAD_CRIT_MULT:-1.2}" 'BEGIN { printf "%.2f", c*m }')
    awk -v l="$l1" -v w="$warn" 'BEGIN { exit !(l+0 >= w+0) }' || return
    if awk -v l="$l1" -v c="$crit" 'BEGIN { exit !(l+0 >= c+0) }'; then
        chip_label=$(chip_crit "LOAD ${l1}")
    else
        chip_label=$(chip_warn "LOAD ${l1}")
    fi
    tooltip="Load avg=${l1}  cores=${cores}  warn=${warn}  crit=${crit}"
    pri_row 4 "${chip_label}  ${cores} cores" \
        "$__DIR__/actions.sh open-htop" true "$tooltip"
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
    local safe icon
    safe=$(pango_escape "$short")
    if [[ "$kind" == "CPU" ]]; then icon="󰓅"; else icon=""; fi
    printf '%s %s %s' \
        "$(bar_icon "$icon")" \
        "$safe" \
        "$(bar_val "${bar_pct}%" "$(bar_thr "$bar_pct" 50 80)")"
}

widget_top_proc_menu() {
    # One row showing the worst CPU offender; click opens htop filtered
    # to that PID. MEM is dropped — bar already alarms on heavy procs.
    local raw name pid cpu mem args safe_name cpu_int chip_label tooltip
    raw=$(top_cpu_proc)
    [[ -z "$raw" ]] && return
    IFS='|' read -r name pid cpu mem args <<< "$raw"
    safe_name=$(pango_escape "$name")
    cpu_int=$(printf '%.0f' "${cpu:-0}")
    if (( cpu_int >= 200 )); then
        chip_label=$(chip_crit "${cpu_int}%")
    else
        chip_label=$(chip_warn "${cpu_int}%")
    fi
    tooltip="Top CPU process: name=${name} pid=${pid} cpu=${cpu}% mem=${mem}%"
    pri_row 2 "󰓅 ${safe_name} ${chip_label}  pid=${pid}" \
        "$__DIR__/actions.sh htop-filter ${pid}" true "$tooltip"
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
    local raw worst_mount="" worst_pct=0 worst_used=0 worst_size=0
    local mount used size pct
    raw=$(_disk_raw)
    [[ -z "$raw" ]] && return
    while read -r mount used size pct; do
        [[ -z "$mount" ]] && continue
        if (( pct > worst_pct )); then
            worst_pct=$pct
            worst_mount=$mount
            worst_used=$used
            worst_size=$size
        fi
    done <<< "$raw"
    [[ -z "$worst_mount" ]] && return

    local bucket="ok"
    if   (( worst_pct >= DISK_PCT_CRIT )); then bucket="crit"
    elif (( worst_pct >= DISK_PCT_WARN )); then bucket="warn"
    fi
    local used_h size_h
    used_h=$(human_bytes "$(( worst_used * 1024 ))")
    size_h=$(human_bytes "$(( worst_size * 1024 ))")
    notify_edge disk "$bucket" "💾 Disk $bucket" \
        "${worst_mount}: ${worst_pct}% used (${used_h} / ${size_h})"

    if (( worst_pct >= DISK_PCT_CRIT )); then
        printf '!  %d%%' "$worst_pct"
    else
        printf ' %d%%' "$worst_pct"
    fi
}

widget_disk_menu() {
    # One row for the worst (fullest) tracked mount. Click → ncdu if installed.
    local raw mount used size pct worst_mount="" worst_pct=0 worst_used=0 worst_size=0
    raw=$(_disk_raw)
    [[ -z "$raw" ]] && return
    while read -r mount used size pct; do
        [[ -z "$mount" ]] && continue
        if (( pct > worst_pct )); then
            worst_pct=$pct
            worst_mount=$mount
            worst_used=$used
            worst_size=$size
        fi
    done <<< "$raw"
    [[ -z "$worst_mount" ]] && return
    local used_h size_h gauge_str safe_mount tooltip action=""
    used_h=$(human_bytes "$(( worst_used * 1024 ))")
    size_h=$(human_bytes "$(( worst_size * 1024 ))")
    gauge_str=$(gauge "$worst_pct" 8 "$DISK_PCT_WARN" "$DISK_PCT_CRIT")
    safe_mount=$(pango_escape "$worst_mount")
    tooltip="Disk worst-mount=${worst_mount}  used=${used_h}  total=${size_h}  pct=${worst_pct}%"
    if command -v ncdu >/dev/null 2>&1; then
        action="$__DIR__/actions.sh disk-ncdu ${worst_mount}"
    fi
    local dot="<span color=\"$COLOR_DIM\">·</span>"
    pri_row 1 " $(printf '%-3s' "${safe_mount}")  ${gauge_str}   $(printf '%3s' "${worst_pct}")%   ${dot}   ${used_h} / ${size_h}" \
        "$action" true "$tooltip"
}

# ── iowait ───────────────────────────────────────────────────
# Returns "<pct>" between two /proc/stat samples, or empty on first
# call (no baseline). State persists across argos refreshes.
_iowait_pct() {
    local cached
    if cached=$(_gb_memo_get iowait_pct); then
        printf '%s' "$cached"
        return
    fi
    local f="$GB_STATE_DIR/iowait.stat"
    local line; line=$(head -n1 /proc/stat)
    local vals
    read -r -a vals <<< "$line"
    local iowait="${vals[5]}"
    local total=0 v
    for v in "${vals[@]:1}"; do total=$(( total + v )); done

    local result=""
    if [[ -f "$f" ]]; then
        local prev_io prev_total
        read -r prev_io prev_total < "$f"
        local d_io=$(( iowait - prev_io ))
        local d_total=$(( total - prev_total ))
        if (( d_total <= 0 )); then
            result="0.0"
        else
            result=$(awk -v i="$d_io" -v t="$d_total" 'BEGIN { printf "%.1f", (i/t) * 100 }')
        fi
    fi
    echo "$iowait $total" > "$f"
    _gb_memo_set iowait_pct "$result"
    printf '%s' "$result"
}

widget_iowait_bar() {
    local pct; pct=$(_iowait_pct)
    [[ -z "$pct" ]] && return
    if (( $(echo "$pct < $IOWAIT_PCT_WARN" | bc -l 2>/dev/null || echo 1) )); then
        return
    fi
    local rounded; rounded=$(printf "%.0f" "$pct")
    if (( $(echo "$pct >= $IOWAIT_PCT_CRIT" | bc -l 2>/dev/null || echo 0) )); then
        printf '! 󰋊 io %s%%' "$rounded"
    else
        printf '󰋊 io %s%%' "$rounded"
    fi
}

widget_iowait_menu() {
    # Only render when iowait exceeds the warn threshold.
    local pct chip_label rounded
    pct=$(_iowait_pct)
    [[ -z "$pct" ]] && return
    awk -v p="$pct" -v w="${IOWAIT_PCT_WARN:-10}" 'BEGIN { exit !(p+0 >= w+0) }' || return
    rounded=$(printf '%.0f' "$pct")
    if awk -v p="$pct" -v c="${IOWAIT_PCT_CRIT:-25}" 'BEGIN { exit !(p+0 >= c+0) }'; then
        chip_label=$(chip_crit "IO ${rounded}%")
    else
        chip_label=$(chip_warn "IO ${rounded}%")
    fi
    pri_row 2 "󰋊 I/O wait  ${chip_label}" \
        "" false "iowait=${pct}%  warn=${IOWAIT_PCT_WARN}  crit=${IOWAIT_PCT_CRIT}"
}

# ── battery ──────────────────────────────────────────────────
# Self-suppress on desktops. First BAT* dir wins.
_battery_dir() {
    local d
    for d in /sys/class/power_supply/BAT*; do
        [[ -d "$d" ]] || continue
        printf "%s" "$d"
        return
    done
}

widget_battery_bar() {
    local d; d=$(_battery_dir)
    [[ -z "$d" ]] && return
    local pct status
    pct=$(cat "$d/capacity" 2>/dev/null) || return
    status=$(cat "$d/status" 2>/dev/null) || return

    local bucket="ok"
    case "$status" in
        Charging|Full) bucket="ok" ;;
        *)
            if   (( pct < BATTERY_PCT_CRIT )); then bucket="crit"
            elif (( pct < BATTERY_PCT_WARN )); then bucket="warn"
            else bucket="ok"
            fi
            ;;
    esac
    notify_edge battery "$bucket" "🔋 Battery $bucket" "${pct}% (${status})"

    if [[ "$bucket" == "crit" ]]; then
        printf '! 󰁾 %d%%' "$pct"
    else
        printf '󰁾 %d%%' "$pct"
    fi
}

widget_battery_menu() {
    local d; d=$(_battery_dir)
    [[ -z "$d" ]] && return
    local pct status chip_label
    pct=$(cat "$d/capacity" 2>/dev/null) || return
    status=$(cat "$d/status" 2>/dev/null) || return
    # On AC and charged → suppress (top bar already shows the charge icon).
    case "$status" in
        Charging|Full)
            (( pct >= BATTERY_PCT_WARN )) && return
            ;;
    esac
    if (( pct < BATTERY_PCT_CRIT )); then
        chip_label=$(chip_crit "${pct}%")
    else
        chip_label=$(chip_warn "${pct}%")
    fi
    pri_row 4 "󰁾 Battery  ${chip_label}  ${status}" \
        "" false "Battery pct=${pct}%  status=${status}  warn=${BATTERY_PCT_WARN}  crit=${BATTERY_PCT_CRIT}"
}
