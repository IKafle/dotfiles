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
