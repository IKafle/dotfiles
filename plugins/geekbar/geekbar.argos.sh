#!/usr/bin/env bash
# bx-purpose: GNOME panel widget showing system stats and dev context (CPU, mem, net, git, docker, more)
# bx-plugin-kind: argos
# bx-plugin-target: ~/.config/argos/geekbar.2s+.sh
# ─────────────────────────────────────────────────────────────
#  geekbar :: entrypoint (directory-plugin form)
#  Compact status bar + expanded dropdown menu.
#  Runs every 2s via Argos (filename: geekbar.2s+.sh).
# ─────────────────────────────────────────────────────────────

__DIR__="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=/dev/null
source "$__DIR__/config.sh"
# shellcheck source=/dev/null
source "$__DIR__/lib.sh"
for f in "$__DIR__"/widgets/*.sh; do
    # shellcheck source=/dev/null
    source "$f"
done

# ═════════════════════════════════════════════════════════════
#  BAR — iterate BAR_WIDGETS, join non-empty segments with "│ "
# ═════════════════════════════════════════════════════════════

BAR=""
_bar_sep="  <span color=\"$COLOR_DIM\">·</span>  "
for w in "${BAR_WIDGETS[@]}"; do
    if ! declare -F "widget_${w}_bar" >/dev/null; then
        continue
    fi
    seg=$("widget_${w}_bar")
    [[ -z "$seg" ]] && continue
    if [[ -z "$BAR" ]]; then
        BAR="$seg"
    else
        BAR+="${_bar_sep}${seg}"
    fi
done
printf '%s | useMarkup=true font="JetBrainsMono Nerd Font" size=11\n' "$BAR"

# ═════════════════════════════════════════════════════════════
#  DROPDOWN MENU  (v2 — Pango markup, priority cap, dual sparklines)
# ═════════════════════════════════════════════════════════════
argos_sep

# Row ceiling for the popup (GNOME PopupMenu doesn't scroll; overflow is invisible).
# Override per-invocation: GB_MENU_MAX_ROWS=14 bash geekbar.argos.sh
GB_MENU_MAX_ROWS="${GB_MENU_MAX_ROWS:-17}"

# ── 1. Collect widget rows ───────────────────────────────────
# Each widget _menu emits #P<n>#-prefixed lines. We split priority +
# section + payload here for downstream prioritization / separator logic.
WIDGET_LINES=()
for section in "${MENU_SECTIONS[@]}"; do
    members_var="MENU_SECTION_${section}[@]"
    for w in "${!members_var}"; do
        declare -F "widget_${w}_menu" >/dev/null || continue
        out=$("widget_${w}_menu")
        [[ -z "$out" ]] && continue
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            if [[ "$line" =~ ^#P([0-9])#(.*)$ ]]; then
                _prio="${BASH_REMATCH[1]}"
                _clean="${BASH_REMATCH[2]}"
            else
                _prio=4
                _clean="$line"
            fi
            WIDGET_LINES+=("$_prio|$section|$_clean")
        done <<< "$out"
    done
done

# ── 2. Priority-cap to fit GB_MENU_MAX_ROWS ──────────────────
_count_total() {
    local n=${#WIDGET_LINES[@]} entry sec
    local -A seen=()
    for entry in "${WIDGET_LINES[@]}"; do
        IFS='|' read -r _ sec _ <<< "$entry"
        seen[$sec]=1
    done
    local sections=${#seen[@]}
    local inter_seps=$(( sections > 1 ? sections - 1 : 0 ))
    local top_sep=$(( n > 0 ? 1 : 0 ))
    # 1 header + top_sep + n widget rows + inter_seps + 1 footer_sep + 3 footer rows
    echo $(( 1 + top_sep + n + inter_seps + 1 + 3 ))
}

_drop_class() {
    local cls="$1" entry prio
    local kept=()
    for entry in "${WIDGET_LINES[@]}"; do
        IFS='|' read -r prio _ _ <<< "$entry"
        [[ "$prio" == "$cls" ]] && continue
        kept+=("$entry")
    done
    WIDGET_LINES=("${kept[@]}")
}

# Drop order: P4 ambient → P3 context → P2 alarms. P0/P1 never drop.
for _cls in 4 3 2; do
    (( $(_count_total) <= GB_MENU_MAX_ROWS )) && break
    _drop_class "$_cls"
done

# ── 3. Header pulse row ──────────────────────────────────────
_uptime_sec=$(awk '{print int($1)}' /proc/uptime)
_uptime_h=$(human_duration "$_uptime_sec")
read -r _load1 _ _ < /proc/loadavg
_dot="<span color=\"$COLOR_DIM\">·</span>"
ui_row "<span color=\"$COLOR_ACCENT\"> ${_uptime_h}</span>   ${_dot}   load ${_load1}   ${_dot}   ⟳ 2s   ${_dot}   $(date +%H:%M:%S)" \
    "" false ""

# ── 4. Widget rows with section separators only between non-empty sections ──
if (( ${#WIDGET_LINES[@]} > 0 )); then
    echo "---"
    _last_section=""
    for entry in "${WIDGET_LINES[@]}"; do
        IFS='|' read -r _prio _sec _line <<< "$entry"
        if [[ -n "$_last_section" && "$_last_section" != "$_sec" ]]; then
            echo "---"
        fi
        printf '%s\n' "$_line"
        _last_section="$_sec"
    done
fi

# ── 5. Footer (always 3 rows) ────────────────────────────────
echo "---"
printf '<span color="%s">↻ Refresh</span> | useMarkup=true font="JetBrainsMono Nerd Font" refresh=true\n' "$COLOR_OK"
ui_row "<span color=\"$COLOR_ACCENT\"> Edit config</span>" \
    "$__DIR__/actions.sh edit-config" false ""
ui_row "<span color=\"$COLOR_DIM\">↻ Reload Argos</span>" \
    "$__DIR__/actions.sh argos-restart" false ""
