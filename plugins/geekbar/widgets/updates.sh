#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  geekbar :: widgets/updates
#  apt (alarm — self-suppresses when zero pending)
# ─────────────────────────────────────────────────────────────

# ── apt ──────────────────────────────────────────────────────
# `apt list --upgradable` is a 1–5s probe, so we cache aggressively
# (1h). The cache file is what actions.sh:apt-refresh removes to
# force a fresh fetch on the next argos tick.

_apt_count() {
    safe_cmd 5 bash -c 'apt list --upgradable 2>/dev/null | grep -c upgradable'
}

_apt_security_count() {
    safe_cmd 5 bash -c 'apt list --upgradable 2>/dev/null | grep -c -- "-security/"'
}

widget_apt_bar() {
    command -v apt >/dev/null 2>&1 || return
    local count
    count=$(cache_get apt.count 3600 _apt_count)
    [[ -z "$count" || "$count" == "0" ]] && return

    local sec
    sec=$(cache_get apt.security 3600 _apt_security_count)
    sec="${sec:-0}"

    if (( sec > 0 )); then
        printf '! 󰚰 %d (%d sec)' "$count" "$sec"
    else
        printf '󰚰 %d' "$count"
    fi
}

widget_apt_menu() {
    if ! command -v apt >/dev/null 2>&1; then
        argos_dim "󰚰 apt          not available"
        return
    fi

    local count sec color
    count=$(cache_get apt.count 3600 _apt_count)
    sec=$(cache_get apt.security 3600 _apt_security_count)
    count="${count:-0}"
    sec="${sec:-0}"

    if (( count == 0 )); then
        argos_dim "󰚰 Updates     none pending"
        return
    fi

    if (( sec > 0 )); then
        color="$COLOR_CRIT"
    else
        color="$COLOR_WARN"
    fi
    argos_item "$(printf '󰚰 Updates     %d pending  (%d security)' "$count" "$sec")" "$color"

    echo "▶ Show upgradable | bash='$__DIR__/actions.sh apt-list' terminal=true"
    echo "▶ apt upgrade (interactive) | bash='$__DIR__/actions.sh apt-upgrade' terminal=true"
    echo "▶ Security only | bash='$__DIR__/actions.sh apt-security' terminal=true"
    echo "▶ Refresh now | bash='$__DIR__/actions.sh apt-refresh' terminal=false"
}
