#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  geekbar :: widgets/audio
#  mic (bar: glyph only when muted) · vol (menu-only)
# ─────────────────────────────────────────────────────────────

widget_mic_bar() {
    local m; m=$(is_mic_muted)
    [[ "$m" == "1" ]] || return
    bar_val "󰍭" "$COLOR_CRIT"
}

widget_mic_menu() {
    # Render only when actionable (muted) — top bar/headset usually
    # signals when live.
    local m; m=$(is_mic_muted)
    [[ "$m" == "1" ]] || return
    pri_row 2 "<span color=\"$COLOR_WARN\">󰍭 Mic</span>  $(chip_warn MUTED)" \
        "$__DIR__/actions.sh mic-mute" false "Microphone is muted — click to toggle"
}

# vol — menu-only (no bar segment in current behavior)
widget_vol_bar() { :; }

widget_vol_menu() {
    # Render only when muted; otherwise GNOME's audio applet covers it.
    local v m
    v=$(volume_pct)
    m=$(is_muted)
    [[ "$m" == "1" ]] || return
    pri_row 2 "<span color=\"$COLOR_WARN\"> Volume</span>  $(chip_warn "MUTED ${v}%")" \
        "$__DIR__/actions.sh vol-mute" false "Output volume muted at ${v}% — click to toggle"
}
