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
    local rx_rate tx_rate rx_h tx_h local_ip ssid label
    local safe_iface safe_ip safe_label dot tooltip
    rx_rate=$(net_rate "$iface" rx)
    tx_rate=$(net_rate "$iface" tx)
    rx_h=$(human_bytes "$rx_rate")
    tx_h=$(human_bytes "$tx_rate")
    local_ip=$(cache_get "localip.$iface" "$CACHE_TTL_SLOW" \
        bash -c "ip -4 addr show '$iface' | awk '/inet / {print \$2}' | cut -d/ -f1")
    [[ -z "$local_ip" ]] && local_ip="—"
    ssid=$(cache_get "wifi.ssid" 30 \
        bash -c "$(declare -f _wifi_ssid get_default_iface safe_cmd); _wifi_ssid")
    if [[ -n "$ssid" ]]; then label="$ssid"; else label="$iface"; fi
    safe_iface=$(pango_escape "$iface")
    safe_ip=$(pango_escape "$local_ip")
    safe_label=$(pango_escape "$label")
    dot="<span color=\"$COLOR_DIM\">·</span>"
    tooltip="iface=${iface}  ip=${local_ip}  ${ssid:+ssid=${ssid}  }rx=${rx_h}/s  tx=${tx_h}/s"
    pri_row 1 "<span color=\"$COLOR_ACCENT\">󰛳</span> ${safe_iface}   ${dot}   ${safe_ip} (${safe_label})   ${dot}   ↓${rx_h} ↑${tx_h}" \
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
    # SSID now lives on the Network row (as "IP (ssid)"); signal stays in the bar.
    return
}

# ─────────────────────────────────────────────────────────────
#  pubip · external IP + city/country/org (ipapi.co, cached 1h)
# ─────────────────────────────────────────────────────────────
# Side effect: writes the plain IP to $GB_CACHE_DIR/publicip so the
# pre-existing copy-pubip action can read it without re-parsing JSON.

_widget_pubip_raw() {
    cache_get pubip.json "$CACHE_TTL_GEO" bash -c '
        out=$(curl -fsS --ipv4 --max-time 3 "https://ipapi.co/json/" 2>/dev/null)
        [[ -z "$out" ]] && out=$(curl -fsS --max-time 3 "https://ipapi.co/json/" 2>/dev/null)
        printf "%s" "$out"
    '
}

widget_pubip_bar() { return; }

widget_pubip_menu() {
    command -v jq >/dev/null 2>&1 || return
    local raw ip city cc org safe_ip safe_loc dot tooltip loc=""
    raw=$(_widget_pubip_raw)
    [[ -z "$raw" ]] && return
    ip=$(jq -r   '.ip // empty'           <<< "$raw" 2>/dev/null)
    city=$(jq -r '.city // empty'         <<< "$raw" 2>/dev/null)
    cc=$(jq -r   '.country_code // empty' <<< "$raw" 2>/dev/null)
    org=$(jq -r  '.org // empty'          <<< "$raw" 2>/dev/null)
    [[ -z "$ip" ]] && return
    printf '%s' "$ip" > "$GB_CACHE_DIR/publicip"
    safe_ip=$(pango_escape "$ip")
    [[ -n "$city" ]] && loc="$city"
    [[ -n "$cc"   ]] && loc="${loc:+$loc, }$cc"
    safe_loc=$(pango_escape "$loc")
    dot="<span color=\"$COLOR_DIM\">·</span>"
    tooltip="Public IP: ${ip}  loc=${city}, ${cc}  org=${org}  (click to copy)"
    local label="<span color=\"$COLOR_ACCENT\">󰖟</span> ${safe_ip}"
    [[ -n "$safe_loc" ]] && label+="   ${dot}   ${safe_loc}"
    pri_row 4 "$label" \
        "$__DIR__/actions.sh copy-pubip" false "$tooltip"
}

# ─────────────────────────────────────────────────────────────
#  xfer · cumulative RX/TX on the default interface since boot
# ─────────────────────────────────────────────────────────────

widget_xfer_bar() { return; }

widget_xfer_menu() {
    local iface rx tx rx_h tx_h dot tooltip
    iface=$(get_default_iface)
    [[ -z "$iface" ]] && return
    rx=$(net_bytes "$iface" rx)
    tx=$(net_bytes "$iface" tx)
    [[ -z "$rx" && -z "$tx" ]] && return
    rx_h=$(human_bytes "${rx:-0}")
    tx_h=$(human_bytes "${tx:-0}")
    dot="<span color=\"$COLOR_DIM\">·</span>"
    tooltip="${iface} cumulative since boot:  rx=${rx_h}  tx=${tx_h}"
    pri_row 4 "<span color=\"$COLOR_ACCENT\">Σ</span> ↓${rx_h}  ↑${tx_h}   ${dot}   since boot" \
        "" false "$tooltip"
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
