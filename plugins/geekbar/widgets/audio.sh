#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  geekbar :: widgets/audio
#  mic (bar: glyph only when muted) · vol (menu-only)
# ─────────────────────────────────────────────────────────────

widget_mic_bar() {
    local m; m=$(is_mic_muted)
    [[ "$m" == "1" ]] || return
    printf '󰍭'
}

widget_mic_menu() {
    local m; m=$(is_mic_muted)
    if [[ "$m" == "1" ]]; then
        argos_item "󰍭 Mic         muted" "$COLOR_WARN"
    else
        argos_item " Mic         live" "$COLOR_OK"
    fi
}

# vol — menu-only (no bar segment in current behavior)
widget_vol_bar() { :; }

widget_vol_menu() {
    local v m
    v=$(volume_pct)
    m=$(is_muted)
    if [[ -z "$v" ]]; then
        argos_item " Volume      (no pactl)" "$COLOR_DIM"
        return
    fi
    if [[ "$m" == "1" ]]; then
        argos_item " Volume      muted (${v}%)" "$COLOR_WARN"
    else
        argos_item " Volume      ${v}%"
    fi
}
