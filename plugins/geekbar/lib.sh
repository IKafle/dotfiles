#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  geekbar :: lib
#  Reusable helpers. Keep pure — no global state mutations
#  beyond the declared caches.
# ─────────────────────────────────────────────────────────────

# ── paths ────────────────────────────────────────────────────
GB_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/geekbar"
GB_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/geekbar"
mkdir -p "$GB_CACHE_DIR" "$GB_STATE_DIR"

# ── per-invocation memo cache ─────────────────────────────────
# Producer functions (cpu_usage_pct, net_rate, _iowait_pct, …) are
# called from both bar AND menu widgets in a single Argos invocation.
# For delta-based samplers that's a bug: the bar's call overwrites the
# state file's baseline, so the menu's call computes delta vs the
# bar's just-written sample (≈ 0). Result: bar shows "880 B/s", menu
# shows "0 B/s" for the same instant.
#
# This memo cache serves the first call's value to every later call
# in the same invocation. Files keyed on parent PID — $$ stays the
# parent's PID inside $(...) subshells, so widgets see the same dir.
# Wiped on script exit.
_GB_MEMO_DIR="/dev/shm/geekbar.invocation.$$"
[[ -d /dev/shm ]] || _GB_MEMO_DIR="${TMPDIR:-/tmp}/geekbar.invocation.$$"
rm -rf "$_GB_MEMO_DIR" 2>/dev/null
mkdir -p "$_GB_MEMO_DIR"
trap 'rm -rf "$_GB_MEMO_DIR" 2>/dev/null' EXIT

_gb_memo_get() {
    local f="$_GB_MEMO_DIR/$1"
    [[ -e "$f" ]] || return 1
    cat "$f"
}
_gb_memo_set() {
    printf '%s' "$2" > "$_GB_MEMO_DIR/$1"
}

# ── safe_cmd <timeout_s> <cmd...>
# Run a command with a hard wall-clock cap. Stderr is swallowed.
# Non-zero exit → empty stdout (callers expect either output or "").
safe_cmd() {
    local t="$1"; shift
    timeout --signal=KILL "${t}s" "$@" 2>/dev/null || true
}

# ── cache_get <key> <ttl_seconds> <producer_cmd...>
# Runs producer only if cached value is missing or older than ttl.
# Producer's stdout becomes the cached value.
cache_get() {
    local key="$1" ttl="$2"; shift 2
    local f="$GB_CACHE_DIR/$key"
    if [[ -f "$f" ]]; then
        local age=$(( $(date +%s) - $(stat -c %Y "$f") ))
        if (( age < ttl )); then
            cat "$f"; return
        fi
    fi
    "$@" > "$f" 2>/dev/null || echo "" > "$f"
    cat "$f"
}

# ── sparkline <current_value> [max_samples=8]
# Maintains a ring buffer of samples and returns a Unicode sparkline.
sparkline() {
    local value="$1" max="${2:-8}" key="${3:-default}"
    local f="$GB_STATE_DIR/sparkline.$key"
    echo "$value" >> "$f"
    tail -n "$max" "$f" > "$f.tmp" && mv "$f.tmp" "$f"

    local blocks=("▁" "▂" "▃" "▄" "▅" "▆" "▇" "█")
    local samples=() lo=999999 hi=0
    while IFS= read -r n; do
        [[ -z "$n" ]] && continue
        samples+=("$n")
        (( $(echo "$n < $lo" | bc -l 2>/dev/null || echo 0) )) && lo="$n"
        (( $(echo "$n > $hi" | bc -l 2>/dev/null || echo 0) )) && hi="$n"
    done < "$f"

    local range; range=$(echo "$hi - $lo" | bc -l 2>/dev/null || echo 0)
    local out=""
    for s in "${samples[@]}"; do
        local idx=0
        if (( $(echo "$range > 0" | bc -l 2>/dev/null || echo 0) )); then
            idx=$(echo "($s - $lo) / $range * 7" | bc -l 2>/dev/null | awk '{printf "%d", $1+0.5}')
        fi
        (( idx < 0 )) && idx=0; (( idx > 7 )) && idx=7
        out+="${blocks[$idx]}"
    done
    printf "%s" "$out"
}

# ── color_for <value> <warn_threshold> <crit_threshold>
color_for() {
    local v="$1" warn="$2" crit="$3"
    if (( $(echo "$v >= $crit" | bc -l 2>/dev/null || echo 0) )); then
        printf "%s" "$COLOR_CRIT"
    elif (( $(echo "$v >= $warn" | bc -l 2>/dev/null || echo 0) )); then
        printf "%s" "$COLOR_WARN"
    else
        printf "%s" "$COLOR_OK"
    fi
}

# ── notify_edge <widget> <new_bucket> <title> <body>
# Fires notify-send only on BUCKET TRANSITIONS — when the widget moves
# from one bucket to another. Bucket transitions are the events that
# warrant a desktop notification; sustained states do not.
#
# Per-widget state stored at $GB_STATE_DIR/notify.<widget>. Contains
# the last-observed bucket. Initial run sets the bucket without firing.
#
# Respects ENABLE_NOTIFICATIONS (master switch) and NOTIFY_<widget>
# (per-widget switch; defaults to 1 = enabled).
#
# Returns 0 unconditionally; never an error path.
notify_edge() {
    local widget="$1" new_bucket="$2" title="$3" body="$4"

    (( ${ENABLE_NOTIFICATIONS:-1} == 1 )) || return 0
    local per_widget_var="NOTIFY_${widget}"
    local per_widget="${!per_widget_var:-1}"
    (( per_widget == 1 )) || return 0
    command -v notify-send >/dev/null 2>&1 || return 0

    local state_file="$GB_STATE_DIR/notify.${widget}"
    local old_bucket=""
    [[ -f "$state_file" ]] && old_bucket=$(< "$state_file")

    printf '%s' "$new_bucket" > "$state_file"

    [[ -z "$old_bucket" ]] && return 0
    [[ "$old_bucket" == "$new_bucket" ]] && return 0

    local urgency="normal"
    [[ "$new_bucket" == "crit" ]] && urgency="critical"

    notify-send -u "$urgency" -a geekbar "$title" "$body" 2>/dev/null || true
}

# ── human_bytes <bytes_per_sec> → "2.1M" / "340K" / "12B"
human_bytes() {
    local b="${1:-0}"
    awk -v b="$b" 'BEGIN {
        if (b >= 1073741824) printf "%.1fG", b/1073741824;
        else if (b >= 1048576) printf "%.1fM", b/1048576;
        else if (b >= 1024)    printf "%.0fK", b/1024;
        else                   printf "%.0fB", b;
    }'
}

# ── human_duration <seconds> → "47d 3h 22m"
human_duration() {
    local s="${1:-0}"
    local d=$(( s / 86400 ))
    local h=$(( (s % 86400) / 3600 ))
    local m=$(( (s % 3600) / 60 ))
    local out=""
    (( d > 0 )) && out+="${d}d "
    (( h > 0 )) && out+="${h}h "
    (( m > 0 )) && out+="${m}m"
    [[ -z "$out" ]] && out="${s}s"
    printf "%s" "${out% }"
}

# ── compact_duration <seconds> → biggest unit only ("47d")
compact_duration() {
    local s="${1:-0}"
    if   (( s >= 86400 )); then printf "%dd" $(( s / 86400 ))
    elif (( s >= 3600  )); then printf "%dh" $(( s / 3600 ))
    elif (( s >= 60    )); then printf "%dm" $(( s / 60 ))
    else                        printf "%ds" "$s"
    fi
}

# ── get_default_iface → interface carrying the default route, or ""
get_default_iface() {
    if [[ -n "${NET_IFACE:-}" ]]; then
        printf "%s" "$NET_IFACE"; return
    fi
    ip route show default 2>/dev/null \
        | awk '/^default/ {print $5; exit}'
}

# ── net_bytes <iface> <direction>    direction: rx|tx
net_bytes() {
    local iface="$1" dir="$2"
    local f="/sys/class/net/$iface/statistics/${dir}_bytes"
    [[ -r "$f" ]] && cat "$f" || echo 0
}

# ── net_rate <iface> <direction> → bytes/sec since last call
net_rate() {
    local iface="$1" dir="$2"
    local memo_key="net_rate.${iface}.${dir}"
    local cached
    if cached=$(_gb_memo_get "$memo_key"); then
        printf '%s' "$cached"
        return
    fi
    local key="net.${iface}.${dir}"
    local f="$GB_STATE_DIR/$key"
    local now_b; now_b=$(net_bytes "$iface" "$dir")
    local now_t; now_t=$(date +%s%N)
    local rate=0
    if [[ -f "$f" ]]; then
        local prev_b prev_t
        IFS=' ' read -r prev_b prev_t < "$f"
        local delta_b=$(( now_b - prev_b ))
        local delta_t_ns=$(( now_t - prev_t ))
        (( delta_t_ns <= 0 )) && delta_t_ns=1
        rate=$(awk -v b="$delta_b" -v t="$delta_t_ns" 'BEGIN { printf "%d", (b*1000000000)/t }')
    fi
    echo "$now_b $now_t" > "$f"
    _gb_memo_set "$memo_key" "$rate"
    printf '%s' "$rate"
}

# ── cpu_temp → °C; tries sensors -j, then thermal_zone fallback
cpu_temp() {
    local cached
    if cached=$(_gb_memo_get cpu_temp); then
        printf '%s' "$cached"
        return
    fi
    local t=""
    if command -v sensors >/dev/null 2>&1; then
        t=$(sensors -j 2>/dev/null | jq -r '
            .. | objects
            | to_entries[]
            | select(.key | test("^(Package id 0|Tctl|Tdie|CPU)"; "i"))
            | .value.input // empty
        ' 2>/dev/null | head -1)
    fi
    if [[ -z "$t" ]]; then
        for z in /sys/class/thermal/thermal_zone*/temp; do
            [[ -r "$z" ]] || continue
            t=$(cat "$z")
            t=$(awk -v v="$t" 'BEGIN { printf "%.0f", v/1000 }')
            break
        done
    fi
    local result; result=$(printf "%.0f" "${t:-0}")
    _gb_memo_set cpu_temp "$result"
    printf '%s' "$result"
}

# ── cpu_freq_mhz → mean core frequency, MHz
cpu_freq_mhz() {
    awk '/^cpu MHz/ { sum+=$4; n++ } END { if(n>0) printf "%.0f", sum/n; else print 0 }' \
        /proc/cpuinfo
}

# ── cpu_usage_pct → instantaneous-ish CPU% (needs prev sample in state)
cpu_usage_pct() {
    local cached
    if cached=$(_gb_memo_get cpu_usage); then
        printf '%s' "$cached"
        return
    fi
    local f="$GB_STATE_DIR/cpu.stat"
    local line; line=$(head -n1 /proc/stat)
    local vals
    read -r -a vals <<< "$line"
    local idle=$(( vals[4] + vals[5] ))
    local total=0
    for v in "${vals[@]:1}"; do total=$(( total + v )); done

    local pct=0
    if [[ -f "$f" ]]; then
        local prev_idle prev_total
        read -r prev_idle prev_total < "$f"
        local d_idle=$(( idle  - prev_idle ))
        local d_total=$(( total - prev_total ))
        (( d_total <= 0 )) && d_total=1
        pct=$(awk -v i="$d_idle" -v t="$d_total" 'BEGIN { printf "%.0f", (1 - i/t) * 100 }')
    fi
    echo "$idle $total" > "$f"
    _gb_memo_set cpu_usage "$pct"
    printf '%s' "$pct"
}

# ── ram_info → "<pct> <used_gb> <total_gb>"
ram_info() {
    local cached
    if cached=$(_gb_memo_get ram_info); then
        printf '%s' "$cached"
        return
    fi
    local result
    result=$(awk '/^MemTotal:/     { total=$2 }
         /^MemAvailable:/ { avail=$2 }
         END {
             used = total - avail
             printf "%d %.1f %.1f",
                 (used*100)/total,
                 used/1048576,
                 total/1048576
         }' /proc/meminfo)
    _gb_memo_set ram_info "$result"
    printf '%s' "$result"
}

# ── docker_count → running container count, or "" if docker absent/down
docker_count() {
    command -v docker >/dev/null 2>&1 || { echo ""; return; }
    docker ps -q 2>/dev/null | wc -l | grep -v '^0$' || echo ""
}

# ── git_status <path> → "branch|ahead|behind|dirty|path" or empty
git_status() {
    local d="$1"
    [[ -d "$d/.git" ]] || return
    (
        cd "$d" || exit
        local branch ahead=0 behind=0 dirty
        branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")
        local upstream
        upstream=$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null || true)
        if [[ -n "$upstream" ]]; then
            read -r ahead behind < <(git rev-list --left-right --count "HEAD...$upstream" 2>/dev/null)
            ahead=${ahead:-0}; behind=${behind:-0}
        fi
        dirty=$(git status --porcelain 2>/dev/null | wc -l)
        printf "%s|%s|%s|%s|%s" "$branch" "$ahead" "$behind" "$dirty" "$d"
    )
}

# ── find_active_repo — cold-boot fallback only.
# The shell hook in modules/45-geekbar-track.sh is the primary signal
# (writes $XDG_CACHE_HOME/geekbar/active_repo on every cd). This function
# runs when that state file is missing/empty — e.g. fresh login session
# before any terminal has fired a prompt. It scans a portable set of
# conventional project roots for the most-recently-modified .git and
# is intentionally NOT user-configurable (no tracked machine paths).
find_active_repo() {
    local roots=(
        "$HOME/dev"
        "$HOME/code"
        "$HOME/Projects"
        "$HOME/projects"
        "$HOME/src"
        "$HOME/work"
        "$HOME/repos"
    )
    local newest="" newest_ts=0
    for root in "${roots[@]}"; do
        [[ -d "$root" ]] || continue
        while IFS= read -r repo; do
            [[ -z "$repo" ]] && continue
            local ts; ts=$(stat -c %Y "$repo/.git" 2>/dev/null || echo 0)
            if (( ts > newest_ts )); then
                newest_ts=$ts
                newest="$repo"
            fi
        done < <(find "$root" -maxdepth 3 -type d -name ".git" -printf '%h\n' 2>/dev/null)
    done
    printf "%s" "$newest"
}

# ─────────────────────────────────────────────────────────────
#  AUDIO (PipeWire / PulseAudio)
# ─────────────────────────────────────────────────────────────

# ── volume_pct → output volume as integer %
volume_pct() {
    command -v pactl >/dev/null 2>&1 || { echo ""; return; }
    pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null \
        | grep -oP '\d+%' | head -1 | tr -d '%'
}

# ── is_muted → "1" if output muted, "0" otherwise
is_muted() {
    command -v pactl >/dev/null 2>&1 || { echo "0"; return; }
    [[ "$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null)" == *"yes"* ]] \
        && echo "1" || echo "0"
}

# ── is_mic_muted → "1" if default source (mic) muted
is_mic_muted() {
    local cached
    if cached=$(_gb_memo_get is_mic_muted); then
        printf '%s' "$cached"
        return
    fi
    local result="1"
    if command -v pactl >/dev/null 2>&1; then
        if [[ "$(pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null)" == *"yes"* ]]; then
            result="1"
        else
            result="0"
        fi
    fi
    _gb_memo_set is_mic_muted "$result"
    printf '%s' "$result"
}

# ─────────────────────────────────────────────────────────────
#  LOCATION & WEATHER
# ─────────────────────────────────────────────────────────────

# ── geo_location → "City,Country" from public IP (ipapi.co, no key)
geo_location() {
    local raw
    raw=$(curl -fsS --max-time 3 'https://ipapi.co/json/' 2>/dev/null) || { echo ""; return; }
    echo "$raw" | jq -r '"\(.city),\(.country_code)"' 2>/dev/null
}

# ── weather_compact → "18°" for the bar
weather_compact() {
    local loc="$1"
    [[ -z "$loc" ]] && { echo ""; return; }
    curl -fsS --max-time 4 "https://wttr.in/${loc}?format=%t" 2>/dev/null \
        | tr -d '+' | sed 's/°C/°/; s/°F/°/'
}

# ── weather_full → richer report for dropdown
weather_full() {
    local loc="$1"
    [[ -z "$loc" ]] && { echo ""; return; }
    curl -fsS --max-time 4 "https://wttr.in/${loc}?format=%C|%t|%f|%w|%h" 2>/dev/null
}

# ─────────────────────────────────────────────────────────────
#  NEPSE (Nepal Stock Exchange)
# ─────────────────────────────────────────────────────────────

# ── nepse_is_market_open → "1" during NPT trading hours, Sun–Thu, 11:00–15:00
nepse_is_market_open() {
    local npt_day npt_hm
    npt_day=$(TZ='Asia/Kathmandu' date +%u)
    npt_hm=$(TZ='Asia/Kathmandu' date +%H%M)
    case "$npt_day" in
        1|2|3|4|7) ;;
        *) echo "0"; return ;;
    esac
    if (( 10#$npt_hm >= 1100 && 10#$npt_hm <= 1500 )); then
        echo "1"
    else
        echo "0"
    fi
}

# ── nepse_fetch → "index|change|pct" (nepalipaisa primary, sharesansar fallback)
nepse_fetch() {
    local resp idx chg pct
    resp=$(curl -fsS --max-time 4 \
        -H 'User-Agent: Mozilla/5.0' \
        'https://www.nepalipaisa.com/api/GetNepseIndex' 2>/dev/null)
    if [[ -n "$resp" ]]; then
        idx=$(echo "$resp" | jq -r '.Data[0].CurrentValue // .data[0].currentValue // empty' 2>/dev/null)
        chg=$(echo "$resp" | jq -r '.Data[0].Change // .data[0].change // empty' 2>/dev/null)
        pct=$(echo "$resp" | jq -r '.Data[0].PerChange // .data[0].perChange // empty' 2>/dev/null)
    fi
    if [[ -z "$idx" ]]; then
        resp=$(curl -fsS --max-time 4 -H 'User-Agent: Mozilla/5.0' \
            'https://www.sharesansar.com/live-trading' 2>/dev/null)
        if [[ -n "$resp" ]]; then
            idx=$(echo "$resp" | grep -oP 'NEPSE[^<]*</[^>]+>\s*<[^>]+>\s*\K[0-9,.]+' | head -1)
        fi
    fi
    [[ -z "$idx" ]] && return
    printf "%s|%s|%s" "${idx:-}" "${chg:-0}" "${pct:-0}"
}

# ─────────────────────────────────────────────────────────────
#  TOP PROCESS
# ─────────────────────────────────────────────────────────────

# ── top_cpu_proc [min_pct=50] → "name|pid|cpu|mem|args" if above threshold
top_cpu_proc() {
    local min="${1:-50}"
    local memo_key="top_cpu_proc.${min}"
    local cached
    if cached=$(_gb_memo_get "$memo_key"); then
        printf '%s' "$cached"
        return
    fi
    local line result=""
    line=$(ps -eo pid=,pcpu=,pmem=,comm=,args= --sort=-pcpu \
        | awk 'NR==1 {print; exit}')
    if [[ -n "$line" ]]; then
        local pid cpu mem comm args
        pid=$(awk '{print $1}' <<< "$line")
        cpu=$(awk '{print $2}' <<< "$line")
        mem=$(awk '{print $3}' <<< "$line")
        comm=$(awk '{print $4}' <<< "$line")
        args=$(awk '{for(i=5;i<=NF;i++) printf "%s ", $i; print ""}' <<< "$line" | sed 's/ $//')
        if (( $(echo "$cpu >= $min" | bc -l 2>/dev/null || echo 0) )); then
            result=$(printf "%s|%s|%s|%s|%s" "$comm" "$pid" "$cpu" "$mem" "$args")
        fi
    fi
    _gb_memo_set "$memo_key" "$result"
    printf '%s' "$result"
}

# ── top_mem_proc → same shape as top_cpu_proc, sorted by mem
top_mem_proc() {
    local line
    line=$(ps -eo pid=,pcpu=,pmem=,comm=,args= --sort=-pmem \
        | awk 'NR==1 {print; exit}')
    [[ -z "$line" ]] && return
    local pid cpu mem comm args
    pid=$(awk '{print $1}' <<< "$line")
    cpu=$(awk '{print $2}' <<< "$line")
    mem=$(awk '{print $3}' <<< "$line")
    comm=$(awk '{print $4}' <<< "$line")
    args=$(awk '{for(i=5;i<=NF;i++) printf "%s ", $i; print ""}' <<< "$line" | sed 's/ $//')
    printf "%s|%s|%s|%s|%s" "$comm" "$pid" "$cpu" "$mem" "$args"
}

# ── argos helpers ────────────────────────────────────────────
# In Argos, a line before `---` is the bar label; lines after are
# the dropdown menu. `|` separates label from attributes.
argos_sep()   { echo "---"; }
argos_dim()   { printf '%s | color=%s\n' "$1" "$COLOR_DIM"; }
argos_item()  { printf '%s | color=%s font="JetBrainsMono Nerd Font"\n' "$1" "${2:-$COLOR_ACCENT}"; }

# ─────────────────────────────────────────────────────────────
#  PREMIUM UI HELPERS (Pango-markup primitives)
#  Used for the v2 dropdown. ui_row emits useMarkup=true rows and
#  intentionally OMITS `color=` — row-level color attribute clobbers
#  inline <span color="..."> on some Argos builds.
# ─────────────────────────────────────────────────────────────

# Pango-escape a label fragment. Required for any user-controlled
# string (process names, paths) interpolated into a markup row.
pango_escape() {
    printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

# Pango chip badge — colored pill rendered inline.
# Usage: chip <label> <bg-color> [fg-color]
chip() {
    local label="$1" bg="$2" fg="${3:-${COLOR_BG:-#1e1e2e}}"
    printf '<span background="%s" foreground="%s" font_weight="bold" font_family="JetBrainsMono Nerd Font"> %s </span>' \
        "$bg" "$fg" "$label"
}
chip_crit() { chip "$1" "$COLOR_CRIT"; }
chip_warn() { chip "$1" "$COLOR_WARN"; }
chip_ok()   { chip "$1" "$COLOR_OK"; }
chip_dim()  { chip "$1" "$COLOR_DIM" "#cdd6f4"; }

# ── BAR-segment helpers ──────────────────────────────────────
# The panel label (bar) uses Pango markup too. Convention: accent-colored
# icon prefix + bare value at idle + warn/crit color span only when a
# threshold is crossed. The eye is drawn only by anomalies.

# Accent-colored icon prefix.
bar_icon() { printf '<span color="%s">%s</span>' "$COLOR_ACCENT" "$1"; }

# Value wrapped in a color span only when $2 is non-empty; bare otherwise.
bar_val() {
    local value="$1" thr_color="${2:-}"
    if [[ -n "$thr_color" ]]; then
        printf '<span color="%s">%s</span>' "$thr_color" "$value"
    else
        printf '%s' "$value"
    fi
}

# Threshold→color, but empty when value is below warn (or empty/non-numeric).
# Pair with bar_val to keep idle values uncolored.
bar_thr() {
    local v="${1:-}" warn="$2" crit="$3"
    [[ "$v" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || return 0
    if (( $(echo "$v >= $crit" | bc -l 2>/dev/null || echo 0) )); then
        printf '%s' "$COLOR_CRIT"
    elif (( $(echo "$v >= $warn" | bc -l 2>/dev/null || echo 0) )); then
        printf '%s' "$COLOR_WARN"
    fi
}

# Multi-color severity gauge. Each block is colored by where IT falls
# relative to warn/crit thresholds — green/yellow/red bands are
# pre-visualized in the gauge regardless of current value.
# In-process memoization across one Argos invocation keyed on (filled,width,thresholds).
declare -gA _GB_GAUGE_CACHE
gauge() {
    local pct="${1:-0}" w="${2:-8}" warn_pct="${3:-50}" crit_pct="${4:-80}"
    [[ "$pct" =~ ^[0-9]+$ ]] || pct=0
    (( pct < 0 )) && pct=0
    (( pct > 100 )) && pct=100
    local filled=$(( pct * w / 100 ))
    local key="${filled}.${w}.${warn_pct}.${crit_pct}"
    if [[ -n "${_GB_GAUGE_CACHE[$key]:-}" ]]; then
        printf '%s' "${_GB_GAUGE_CACHE[$key]}"
        return
    fi
    local out="" i seg color
    for (( i=0; i<w; i++ )); do
        seg=$(( (i+1) * 100 / w ))
        if   (( seg > crit_pct )); then color="$COLOR_CRIT"
        elif (( seg > warn_pct )); then color="$COLOR_WARN"
        else                            color="$COLOR_OK"; fi
        if (( i < filled )); then
            out+="<span color=\"$color\">▰</span>"
        else
            out+="<span color=\"$COLOR_DIM\">▱</span>"
        fi
    done
    _GB_GAUGE_CACHE[$key]="$out"
    printf '%s' "$out"
}

# Dual sparkline — wider history window on the left, recent window on
# the right, separated by '│'. Reveals derivative: was trending vs. is trending.
# Two independent ring-buffer keys (.long and .short) per metric.
spark_dual() {
    local value="$1" key="$2"
    local long short
    long=$(sparkline "$value" 6 "${key}.long")
    short=$(sparkline "$value" 4 "${key}.short")
    printf '%s│%s' "$long" "$short"
}

# Markup row emitter. Always sets useMarkup, font; appends optional
# bash/terminal/tooltip. NEVER sets row-level color= (it would clobber
# inline span colors).
# Usage: ui_row <markup_label> [bash_cmd] [terminal] [tooltip]
ui_row() {
    local label="$1" bash_cmd="${2:-}" terminal="${3:-false}" tooltip="${4:-}"
    local line="$label | useMarkup=true font=\"JetBrainsMono Nerd Font\""
    [[ -n "$bash_cmd" ]] && line+=" bash='$bash_cmd' terminal=$terminal"
    [[ -n "$tooltip"  ]] && line+=" tooltip=\"$tooltip\""
    printf '%s\n' "$line"
}

# Tagged markup row. Prefixes the emitted line with #P<n># so the
# dispatcher can prioritize/drop the row when the menu would overflow.
# Usage: pri_row <prio 0-5> <markup_label> [bash_cmd] [terminal] [tooltip]
pri_row() {
    local prio="$1"; shift
    printf '#P%s#' "$prio"
    ui_row "$@"
}
