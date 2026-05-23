#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  geekbar :: widgets/network
#  net (bar: rx/tx) · menu: iface · ssid · local-ip · public-ip · rates
# ─────────────────────────────────────────────────────────────

widget_net_bar() {
    local iface rx_rate tx_rate rx_h tx_h
    iface=$(get_default_iface)
    [[ -z "$iface" ]] && return
    rx_rate=$(net_rate "$iface" rx)
    tx_rate=$(net_rate "$iface" tx)
    rx_h=$(human_bytes "$rx_rate")
    tx_h=$(human_bytes "$tx_rate")
    printf '%s ↓%s ↑%s' "$(bar_icon "")" "$rx_h" "$tx_h"
}

widget_net_menu() {
    local iface; iface=$(get_default_iface)
    if [[ -z "$iface" ]]; then
        pri_row 1 "$(chip_warn 'OFFLINE')  no network" "" false ""
        return
    fi
    local rx_rate tx_rate rx_h tx_h local_ip n tooltip safe_iface safe_ip dot
    rx_rate=$(net_rate "$iface" rx)
    tx_rate=$(net_rate "$iface" tx)
    rx_h=$(human_bytes "$rx_rate")
    tx_h=$(human_bytes "$tx_rate")
    local_ip=$(cache_get "localip.$iface" "$CACHE_TTL_SLOW" \
        bash -c "ip -4 addr show '$iface' | awk '/inet / {print \$2}' | cut -d/ -f1")
    n=$(cache_get "sock.established" 5 \
        bash -c "ss -tnH state established 2>/dev/null | wc -l")
    n=${n:-0}
    safe_iface=$(pango_escape "$iface")
    safe_ip=$(pango_escape "${local_ip:-—}")
    dot="<span color=\"$COLOR_DIM\">·</span>"
    tooltip="iface=${iface}  ip=${local_ip:-—}  rx=${rx_h}/s  tx=${tx_h}/s  est-conn=${n}"
    pri_row 1 "󰛳 ${safe_iface}   ↓  $(printf '%9s' "${rx_h}/s")   ${dot}   ${n} conn" \
        "$__DIR__/actions.sh net-nload ${iface}" true "$tooltip"
    pri_row 1 "  $(printf '%-10s' '')   ↑  $(printf '%9s' "${tx_h}/s")   ${dot}   ${safe_ip}" \
        "$__DIR__/actions.sh net-nload ${iface}" true "$tooltip"
}

# ─────────────────────────────────────────────────────────────
#  wifi · signal strength on the active wireless interface
# ─────────────────────────────────────────────────────────────

# Returns "<dBm> <bars>" or empty when not wireless / no link.
_wifi_signal() {
    local iface; iface=$(get_default_iface)
    [[ -z "$iface" ]] && return
    # `iw dev` lists wireless ifaces; if ours isn't there, bail.
    safe_cmd 1 iw dev 2>/dev/null | grep -q "Interface $iface" || return

    local dbm
    dbm=$(safe_cmd 1 iw dev "$iface" link 2>/dev/null \
        | awk '/signal:/ {print $2; exit}')
    if [[ -z "$dbm" ]]; then
        dbm=$(safe_cmd 1 iwconfig "$iface" 2>/dev/null \
            | grep -oP 'Signal level=\K-?[0-9]+' | head -1)
    fi
    [[ -z "$dbm" ]] && return

    local bars
    if   (( dbm >= -50 )); then bars="▮▮▮▮"
    elif (( dbm >= -60 )); then bars="▮▮▮▯"
    elif (( dbm >= -70 )); then bars="▮▮▯▯"
    else                        bars="▮▯▯▯"
    fi
    printf "%s %s" "$dbm" "$bars"
}

# SSID via iwgetid (preferred) or `iw dev link` fallback (when wireless-tools absent).
_wifi_ssid() {
    local iface; iface=$(get_default_iface)
    [[ -z "$iface" ]] && return
    local s=""
    if command -v iwgetid >/dev/null 2>&1; then
        s=$(iwgetid -r 2>/dev/null || true)
    fi
    if [[ -z "$s" ]]; then
        # Match the leading tab/space-indented "SSID:" line; mawk lacks \s.
        s=$(safe_cmd 1 iw dev "$iface" link 2>/dev/null \
            | awk -F': ' '/^[[:space:]]+SSID:/ {print $2; exit}')
    fi
    printf "%s" "$s"
}

widget_wifi_bar() {
    local sig dbm bars color=""
    sig=$(cache_get "wifi.sig" 5 bash -c "$(declare -f _wifi_signal get_default_iface safe_cmd); _wifi_signal")
    [[ -z "$sig" ]] && return
    read -r dbm bars <<< "$sig"
    if   (( dbm >= -60 )); then color=""
    elif (( dbm >= -70 )); then color="$COLOR_WARN"
    else                        color="$COLOR_CRIT"
    fi
    # SSID stays in the menu — bar keeps width tight with signal-only.
    printf '%s %s' "$(bar_icon "󰖩")" "$(bar_val "$bars" "$color")"
}

widget_wifi_menu() {
    local sig; sig=$(cache_get "wifi.sig" 5 bash -c "$(declare -f _wifi_signal get_default_iface safe_cmd); _wifi_signal")
    [[ -z "$sig" ]] && return
    local dbm bars ssid safe_ssid bars_chip
    read -r dbm bars <<< "$sig"
    ssid=$(cache_get "wifi.ssid" 30 \
        bash -c "$(declare -f _wifi_ssid get_default_iface safe_cmd); _wifi_ssid")
    [[ -z "$ssid" ]] && ssid="—"
    safe_ssid=$(pango_escape "$ssid")
    if   (( dbm >= -60 )); then bars_chip=$(chip_ok   "$bars")
    elif (( dbm >= -70 )); then bars_chip=$(chip_warn "$bars")
    else                        bars_chip=$(chip_crit "$bars")
    fi
    pri_row 4 "󰖩 ${safe_ssid}  ${bars_chip}" \
        "" false "WiFi ssid=${ssid}  signal=${dbm} dBm"
}

# ─────────────────────────────────────────────────────────────
#  dns · current resolver(s)
# ─────────────────────────────────────────────────────────────

_dns_servers() {
    local raw=""
    if command -v resolvectl >/dev/null 2>&1; then
        # Capture the `DNS Servers:` line plus its indented continuation lines.
        raw=$(safe_cmd 1 resolvectl status 2>/dev/null \
            | awk '
                /DNS Servers:/   { sub(/.*DNS Servers:/, ""); print; in_block=1; next }
                in_block && /^[[:space:]]+[^[:space:]:]/ { print; next }
                in_block         { exit }
            ')
    fi
    if [[ -z "$raw" && -r /etc/resolv.conf ]]; then
        raw=$(awk '/^nameserver/ {print $2}' /etc/resolv.conf)
    fi
    [[ -z "$raw" ]] && return
    # Split on whitespace, drop blanks, take ≤3, join with ", ".
    printf "%s" "$raw" | tr -s '[:space:]' '\n' | awk 'NF' | head -3 \
        | paste -sd, - | sed 's/,/, /g'
}

# No-op: dns has no bar segment, but defined so it won't break BAR_WIDGETS.
widget_dns_bar() { return; }

widget_dns_menu() {
    # First DNS only to keep the line short. Click opens full resolvectl status.
    local servers first safe_first action=""
    servers=$(cache_get "dns.servers" 60 \
        bash -c "$(declare -f _dns_servers safe_cmd); _dns_servers")
    [[ -z "$servers" ]] && return
    first=${servers%%,*}
    safe_first=$(pango_escape "$first")
    command -v resolvectl >/dev/null 2>&1 && action="$__DIR__/actions.sh dns-status"
    pri_row 4 " DNS  ${safe_first}" "$action" true "DNS servers: ${servers}"
}

# ─────────────────────────────────────────────────────────────
#  sock · established TCP connection count
# ─────────────────────────────────────────────────────────────

widget_sock_bar() { return; }

# Connection count moved into widget_net_menu so the Network section stays
# at ≤3 rows. This widget now self-suppresses in the menu.
widget_sock_menu() { return; }
