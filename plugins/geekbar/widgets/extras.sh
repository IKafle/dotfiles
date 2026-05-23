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
    argos_item " Local       $(date '+%a %b %d  %H:%M')"
    local entry label tz out
    for entry in "${CLOCK_EXTRA_TZS[@]:-}"; do
        [[ -z "$entry" ]] && continue
        label="${entry%%/*}"
        tz="${entry#*/}"
        [[ -z "$label" || -z "$tz" || "$label" == "$entry" ]] && continue
        # `date` silently falls back to UTC on unknown TZ; verify zoneinfo exists.
        [[ -r "/usr/share/zoneinfo/$tz" ]] || continue
        out=$(TZ="$tz" date '+%a %b %d  %H:%M' 2>/dev/null)
        [[ -z "$out" ]] && continue
        argos_item " $(printf '%-10s' "$label")  $out"
    done
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
    printf '󰖐 %s' "$temp"
}

widget_weather_menu() {
    local loc temp detail
    loc=$(_widget_weather_loc)
    if [[ -z "$loc" ]]; then
        argos_item "󰖐 Weather     no location" "$COLOR_DIM"
        return
    fi
    temp=$(cache_get "weather.$loc" "$CACHE_TTL_WEATHER" weather_compact "$loc")
    detail=$(cache_get "weatherfull.$loc" "$CACHE_TTL_WEATHER" weather_full "$loc")
    if [[ -z "$temp" ]]; then
        argos_item "󰖐 Weather     ($loc) — fetch failed" "$COLOR_DIM"
        return
    fi
    argos_item "󰖐 Weather     ${temp}  $loc"
    [[ -n "$detail" ]] && argos_item "   $detail" "$COLOR_DIM"
}

# ── nepse ────────────────────────────────────────────────────
widget_nepse_bar() {
    local open; open=$(nepse_is_market_open)
    [[ "$open" == "1" ]] || return
    local raw idx chg pct pct_fmt
    raw=$(cache_get nepse "$CACHE_TTL_COLD" nepse_fetch)
    [[ -z "$raw" ]] && return
    IFS='|' read -r idx chg pct <<< "$raw"
    [[ -z "$pct" ]] && return
    pct_fmt=$(awk -v p="$pct" 'BEGIN { printf "%+.2f", p }')
    printf ' %s%%' "$pct_fmt"
}

widget_nepse_menu() {
    local open; open=$(nepse_is_market_open)
    local raw idx chg pct
    if [[ "$open" != "1" ]]; then
        argos_item " NEPSE       market closed" "$COLOR_DIM"
        return
    fi
    raw=$(cache_get nepse "$CACHE_TTL_COLD" nepse_fetch)
    if [[ -z "$raw" ]]; then
        argos_item " NEPSE       fetch failed" "$COLOR_DIM"
        return
    fi
    IFS='|' read -r idx chg pct <<< "$raw"
    argos_item " NEPSE       ${idx}  Δ${chg}  (${pct}%)"
}
