#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  geekbar :: widgets/network
#  net (bar: rx/tx) · menu: iface · ssid · local-ip · public-ip · rates
# ─────────────────────────────────────────────────────────────

widget_net_bar() {
    local iface; iface=$(get_default_iface)
    [[ -z "$iface" ]] && return
    local rx_rate tx_rate rx_h tx_h
    rx_rate=$(net_rate "$iface" rx)
    tx_rate=$(net_rate "$iface" tx)
    rx_h=$(human_bytes "$rx_rate")
    tx_h=$(human_bytes "$tx_rate")
    printf ' ↓%s ↑%s' "$rx_h" "$tx_h"
}

widget_net_menu() {
    local iface; iface=$(get_default_iface)
    if [[ -z "$iface" ]]; then
        argos_item " No network" "$COLOR_WARN"
        return
    fi
    local rx_rate tx_rate rx_h tx_h local_ip ssid public_ip
    rx_rate=$(net_rate "$iface" rx)
    tx_rate=$(net_rate "$iface" tx)
    rx_h=$(human_bytes "$rx_rate")
    tx_h=$(human_bytes "$tx_rate")
    local_ip=$(cache_get "localip.$iface" "$CACHE_TTL_SLOW" \
        bash -c "ip -4 addr show '$iface' | awk '/inet / {print \$2}' | cut -d/ -f1")
    ssid=$(cache_get "ssid.$iface" "$CACHE_TTL_LAZY" \
        bash -c "iwgetid -r 2>/dev/null || true")
    public_ip=$(cache_get publicip "$CACHE_TTL_COLD" \
        bash -c "curl -fsS --max-time 3 https://ifconfig.me 2>/dev/null || echo '—'")

    argos_item "󰛳 Interface   $iface"
    [[ -n "$ssid"     ]] && argos_item "󰖩 SSID        $ssid"
    [[ -n "$local_ip" ]] && argos_item " Local IP    $local_ip"
    argos_item " Public IP   $public_ip"
    argos_item " Download    $rx_h/s"
    argos_item " Upload      $tx_h/s"
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
    local sig; sig=$(cache_get "wifi.sig" 5 bash -c "$(declare -f _wifi_signal get_default_iface safe_cmd); _wifi_signal")
    [[ -z "$sig" ]] && return
    local dbm bars ssid
    read -r dbm bars <<< "$sig"
    ssid=$(cache_get "wifi.ssid" 30 \
        bash -c "$(declare -f _wifi_ssid get_default_iface safe_cmd); _wifi_ssid")
    [[ -z "$ssid" ]] && ssid="—"
    printf ' %s %s' "$bars" "$ssid"
}

widget_wifi_menu() {
    local sig; sig=$(cache_get "wifi.sig" 5 bash -c "$(declare -f _wifi_signal get_default_iface safe_cmd); _wifi_signal")
    [[ -z "$sig" ]] && return
    local dbm bars ssid color
    read -r dbm bars <<< "$sig"
    ssid=$(cache_get "wifi.ssid" 30 \
        bash -c "$(declare -f _wifi_ssid get_default_iface safe_cmd); _wifi_ssid")
    [[ -z "$ssid" ]] && ssid="—"
    # Custom interval colors: higher (less-negative) dBm is better.
    if   (( dbm >= -60 )); then color="$COLOR_OK"
    elif (( dbm >= -70 )); then color="$COLOR_WARN"
    else                        color="$COLOR_CRIT"
    fi
    argos_item "󰖩 WiFi        $ssid  (${dbm}dBm · $bars)" "$color"
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
    local servers; servers=$(cache_get "dns.servers" 60 \
        bash -c "$(declare -f _dns_servers safe_cmd); _dns_servers")
    if [[ -z "$servers" ]]; then
        argos_dim " DNS         no resolver configured"
        return
    fi
    argos_item " DNS         $servers"
    if command -v resolvectl >/dev/null 2>&1; then
        echo "▶ resolvectl status (full) | bash='$__DIR__/actions.sh dns-status' terminal=true"
        echo "▶ Flush DNS cache | bash='$__DIR__/actions.sh dns-flush' terminal=true"
    fi
}

# ─────────────────────────────────────────────────────────────
#  sock · established TCP connection count
# ─────────────────────────────────────────────────────────────

widget_sock_bar() { return; }

widget_sock_menu() {
    local n; n=$(cache_get "sock.established" 5 \
        bash -c "ss -tnH state established 2>/dev/null | wc -l")
    n=${n:-0}
    local color
    if   (( n == 0 ));   then color="$COLOR_DIM"
    elif (( n <= 50 ));  then color="$COLOR_ACCENT"
    elif (( n <= 200 )); then color="$COLOR_WARN"
    else                      color="$COLOR_CRIT"
    fi
    argos_item " Connections $n established" "$color"
}
