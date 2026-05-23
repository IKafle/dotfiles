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
