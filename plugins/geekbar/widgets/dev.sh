#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  geekbar :: widgets/dev
#  docker (bar: count when ≥1; menu: list running + management actions)
# ─────────────────────────────────────────────────────────────

widget_docker_bar() {
    local n
    n=$(cache_get docker "$CACHE_TTL_SLOW" bash -c 'docker ps -q 2>/dev/null | wc -l')
    [[ -z "$n" || "$n" == "0" ]] && return
    printf ' %s' "$n"
}

widget_docker_menu() {
    local n
    n=$(cache_get docker "$CACHE_TTL_SLOW" bash -c 'docker ps -q 2>/dev/null | wc -l')
    if [[ -n "$n" && "$n" != "0" ]]; then
        argos_item " Docker      $n containers running" "$COLOR_OK"
        local list
        list=$(cache_get dockerlist "$CACHE_TTL_SLOW" \
            bash -c 'docker ps --format "{{.Names}}|{{.Image}}|{{.Status}}" 2>/dev/null')
        if [[ -n "$list" ]]; then
            while IFS='|' read -r d_name d_image d_status; do
                [[ -z "$d_name" ]] && continue
                local d_image_short="${d_image##*/}"
                d_image_short="${d_image_short:0:25}"
                local d_name_short="${d_name:0:20}"
                argos_item "   $d_name_short  $d_image_short" "$COLOR_ACCENT"
                argos_item "     $d_status" "$COLOR_DIM"
            done <<< "$list"
        fi
        echo "▶ docker ps (full) | bash='$__DIR__/actions.sh docker-ps' terminal=false"
        echo "📊 docker stats | bash='$__DIR__/actions.sh docker-stats' terminal=false"
        echo "🧹 Prune unused | bash='$__DIR__/actions.sh docker-prune' terminal=false"
    else
        argos_item " Docker      idle" "$COLOR_DIM"
        if command -v docker >/dev/null 2>&1; then
            echo "📊 docker stats | bash='$__DIR__/actions.sh docker-stats' terminal=false"
            echo "🧹 Prune unused | bash='$__DIR__/actions.sh docker-prune' terminal=false"
        fi
    fi
}

# ── ports ────────────────────────────────────────────────────
# Listening dev-server ports from DEV_PORTS. Bar self-suppresses
# when none match; menu always renders the configured set.

# Cached "port[ name]" lines (one per listening port in DEV_PORTS).
# Name is empty when the process is owned by another user / root —
# ss -p only reveals procs the caller can see.
_ports_listening() {
    cache_get ports.listening 5 bash -c '
        command -v ss >/dev/null 2>&1 || exit 0
        wanted=" '"${DEV_PORTS[*]}"' "
        ss -tlnpH 2>/dev/null | awk -v wanted="$wanted" '"'"'
            {
                addr = $4
                n = split(addr, a, ":")
                port = a[n]
                if (index(wanted, " " port " ") == 0) next
                name = ""
                if (match($0, /users:\(\("[^"]+"/)) {
                    name = substr($0, RSTART+9, RLENGTH-10)
                }
                if (seen[port]++) next
                print port (name ? " " name : "")
            }
        '"'"'
    '
}

widget_ports_bar() {
    command -v ss >/dev/null 2>&1 || return
    local data; data=$(_ports_listening)
    [[ -z "$data" ]] && return
    local ports=()
    while IFS=' ' read -r p _; do
        [[ -z "$p" ]] && continue
        ports+=("$p")
    done <<< "$data"
    (( ${#ports[@]} == 0 )) && return
    local shown=("${ports[@]:0:5}")
    local suffix=""
    (( ${#ports[@]} > 5 )) && suffix="…"
    printf ' %d %s%s' "${#ports[@]}" "${shown[*]}" "$suffix"
}

widget_ports_menu() {
    if ! command -v ss >/dev/null 2>&1; then
        argos_item " ss not installed" "$COLOR_DIM"
        return
    fi
    local data; data=$(_ports_listening)
    declare -A live=()
    if [[ -n "$data" ]]; then
        while IFS=' ' read -r p name; do
            [[ -z "$p" ]] && continue
            live["$p"]="${name:-?}"
        done <<< "$data"
    fi
    local p
    for p in "${DEV_PORTS[@]}"; do
        if [[ -n "${live[$p]:-}" ]]; then
            argos_item " $p      ${live[$p]}" "$COLOR_OK"
        else
            argos_item " $p      —" "$COLOR_DIM"
        fi
    done
    argos_sep
    local total
    total=$(ss -tlnH 2>/dev/null | wc -l)
    argos_item " Total       ${total} listening" "$COLOR_DIM"
    echo "▶ Show all listening (ss -tln) | bash='$__DIR__/actions.sh ports-show' terminal=true"
    echo "▶ What's on port… | bash='$__DIR__/actions.sh ports-prompt' terminal=true"
}
