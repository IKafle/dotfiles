#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  geekbar :: widgets/extras
#  clock · weather · nepse
# ─────────────────────────────────────────────────────────────

# ── clock ────────────────────────────────────────────────────
widget_clock_bar() {
    printf ' %s' "$(date "${CLOCK_BAR_FORMAT:-+%a %H:%M}")"
}

widget_clock_menu() {
    # GNOME's top-bar already shows the local clock — suppress this row.
    return
}

# Resolve the location once (config override > geo).
_widget_weather_loc() {
    if [[ -n "${WEATHER_LOCATION:-}" ]]; then
        printf "%s" "$WEATHER_LOCATION"
    else
        cache_get geoloc "$CACHE_TTL_GEO" geo_location
    fi
}

widget_weather_bar() {
    local loc temp
    loc=$(_widget_weather_loc)
    [[ -z "$loc" ]] && return
    temp=$(cache_get "weather.$loc" "$CACHE_TTL_WEATHER" weather_compact "$loc")
    [[ -z "$temp" ]] && return
    printf '%s %s' "$(bar_icon "󰖐")" "$(pango_escape "$temp")"
}

widget_weather_menu() {
    local loc temp safe_loc safe_temp
    loc=$(_widget_weather_loc)
    [[ -z "$loc" ]] && return
    temp=$(cache_get "weather.$loc" "$CACHE_TTL_WEATHER" weather_compact "$loc")
    [[ -z "$temp" ]] && return
    safe_loc=$(pango_escape "$loc")
    safe_temp=$(pango_escape "$temp")
    pri_row 4 "<span color=\"$COLOR_ACCENT\">󰖐</span> ${safe_temp}  ${safe_loc}" \
        "" false "Weather: ${temp} in ${loc}"
}

# ── nepse ────────────────────────────────────────────────────
widget_nepse_bar() {
    local open; open=$(nepse_is_market_open)
    [[ "$open" == "1" ]] || return
    local raw idx chg pct pct_fmt color
    raw=$(cache_get nepse "$CACHE_TTL_COLD" nepse_fetch)
    [[ -z "$raw" ]] && return
    IFS='|' read -r idx chg pct <<< "$raw"
    [[ -z "$pct" ]] && return
    pct_fmt=$(awk -v p="$pct" 'BEGIN { printf "%+.2f", p }')
    if awk -v p="$pct" 'BEGIN { exit !(p+0 >= 0) }'; then color="$COLOR_OK"
    else                                                   color="$COLOR_CRIT"
    fi
    printf '%s %s' "$(bar_icon "")" "$(bar_val "${pct_fmt}%" "$color")"
}

widget_nepse_menu() {
    local open; open=$(nepse_is_market_open)
    [[ "$open" != "1" ]] && return
    local raw idx chg pct chip_label safe_idx
    raw=$(cache_get nepse "$CACHE_TTL_COLD" nepse_fetch)
    [[ -z "$raw" ]] && return
    IFS='|' read -r idx chg pct <<< "$raw"
    safe_idx=$(pango_escape "$idx")
    if awk -v p="$pct" 'BEGIN { exit !(p+0 >= 0) }'; then
        chip_label=$(chip_ok "Δ${chg} (${pct}%)")
    else
        chip_label=$(chip_crit "Δ${chg} (${pct}%)")
    fi
    pri_row 4 "<span color=\"$COLOR_ACCENT\"></span> NEPSE  ${safe_idx}  ${chip_label}" \
        "" false "NEPSE index=${idx}  change=${chg}  pct=${pct}%"
}
