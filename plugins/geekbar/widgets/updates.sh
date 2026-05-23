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
    local count sec
    count=$(cache_get apt.count 3600 _apt_count)
    count="${count:-0}"
    sec=$(cache_get apt.security 3600 _apt_security_count)
    sec="${sec:-0}"

    local bucket="ok"
    if   (( sec > 0   )); then bucket="crit"
    elif (( count > 0 )); then bucket="warn"
    fi
    notify_edge apt "$bucket" "🛡️ apt updates" "${count} pending (${sec} security)"

    (( count == 0 )) && return

    if (( sec > 0 )); then
        printf '%s %d  %s' "$(bar_icon "󰚰")" "$count" "$(chip_crit "sec ${sec}")"
    else
        printf '%s %d' "$(bar_icon "󰚰")" "$count"
    fi
}

widget_apt_menu() {
    command -v apt >/dev/null 2>&1 || return

    local count sec sec_chip="" count_color
    count=$(cache_get apt.count 3600 _apt_count)
    sec=$(cache_get apt.security 3600 _apt_security_count)
    count="${count:-0}"
    sec="${sec:-0}"

    (( count == 0 )) && return

    if (( sec > 0 )); then
        count_color="$COLOR_CRIT"
        sec_chip="  $(chip_crit "${sec} sec")"
    else
        count_color="$COLOR_WARN"
    fi
    pri_row 2 "<span color=\"$count_color\">󰚰 ${count} updates</span>${sec_chip}" \
        "$__DIR__/actions.sh apt-upgrade" true "apt: ${count} pending (${sec} security)"
}

# ── reboot ───────────────────────────────────────────────────
# Debian/Ubuntu touches /var/run/reboot-required after kernel / libc /
# microcode updates land. Self-suppresses when the flag file is absent.
# /var/run/reboot-required.pkgs lists the triggering packages.
widget_reboot_bar() { return; }

widget_reboot_menu() {
    [[ -f /var/run/reboot-required ]] || return
    local first n pkgs="" safe tooltip
    if [[ -r /var/run/reboot-required.pkgs ]]; then
        n=$(wc -l < /var/run/reboot-required.pkgs 2>/dev/null)
        first=$(head -n1 /var/run/reboot-required.pkgs 2>/dev/null)
    fi
    if [[ -n "${first:-}" ]]; then
        if (( n > 1 )); then pkgs="${first} +$((n-1)) more"
        else                 pkgs="$first"
        fi
    fi
    safe=$(pango_escape "${pkgs:-restart pending}")
    tooltip="Reboot required${pkgs:+ — packages: ${pkgs}}"
    pri_row 2 "$(chip_crit ' REBOOT')  ${safe}" \
        "$__DIR__/actions.sh reboot-now" true "$tooltip"
}
