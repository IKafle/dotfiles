#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  geekbar :: widgets/dev
#  docker (bar: count when ≥1; menu: list running + management actions)
# ─────────────────────────────────────────────────────────────

widget_docker_bar() {
    command -v docker >/dev/null 2>&1 || return
    local n
    n=$(cache_get docker "$CACHE_TTL_SLOW" bash -c 'docker ps -q 2>/dev/null | wc -l')
    [[ -z "$n" || "$n" == "0" ]] && return
    printf '%s %s' "$(bar_icon "")" "$n"
}

widget_docker_menu() {
    # Suppress when docker is missing or idle; on hits, one clickable row.
    command -v docker >/dev/null 2>&1 || return
    local n
    n=$(cache_get docker "$CACHE_TTL_SLOW" bash -c 'docker ps -q 2>/dev/null | wc -l')
    [[ -z "$n" || "$n" == "0" ]] && return
    pri_row 3 " docker  $(chip_ok "${n} running")" \
        "$__DIR__/actions.sh docker-stats" false "Docker containers running: ${n}"
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
    # Suppress unless something in the watchlist is actually listening.
    command -v ss >/dev/null 2>&1 || return
    local data; data=$(_ports_listening)
    [[ -z "$data" ]] && return
    local hits="" count=0 safe_hits
    while IFS=' ' read -r p name; do
        [[ -z "$p" ]] && continue
        if [[ -n "$hits" ]]; then hits+=" "; fi
        hits+="${p}${name:+($name)}"
        count=$(( count + 1 ))
    done <<< "$data"
    [[ -z "$hits" ]] && return
    safe_hits=$(pango_escape "$hits")
    pri_row 4 " Ports  $(chip_ok "${count}")  ${safe_hits}" \
        "$__DIR__/actions.sh ports-show" true "Listening dev ports: ${hits}"
}

# ── sshagent ─────────────────────────────────────────────────
# Alarm-style: bar only fires when ssh-agent is running but has
# zero identities loaded — the typical "forgot to ssh-add" trap.
# Cached count: integer ≥ 0, or -1 for "agent not running".

_sshagent_status() {
    cache_get sshagent.status 10 bash -c '
        command -v ssh-add >/dev/null 2>&1 || { echo -1; exit 0; }
        out=$(ssh-add -l 2>&1); rc=$?
        if [[ $rc -eq 0 ]]; then
            printf "%s\n" "$out" | wc -l
        elif [[ $rc -eq 1 ]] || [[ "$out" == *"no identities"* ]]; then
            echo 0
        else
            echo -1
        fi
    '
}

widget_sshagent_bar() {
    command -v ssh-add >/dev/null 2>&1 || return
    local n; n=$(_sshagent_status)
    if [[ "$n" == "0" ]]; then
        notify_edge sshagent empty "🔑 ssh-agent" "no identities loaded — run 'ssh-add'"
    elif [[ "$n" != "-1" && -n "$n" ]]; then
        notify_edge sshagent loaded "🔑 ssh-agent" "$n identities loaded"
    fi
    [[ "$n" == "0" ]] || return
    printf '%s %s' "$(bar_icon "󰌆")" "$(chip_warn "no keys")"
}

widget_sshagent_menu() {
    # Render only when ssh-agent has zero identities loaded — that's the
    # actionable case. Click runs `ssh-add` in a terminal.
    command -v ssh-add >/dev/null 2>&1 || return
    local n; n=$(_sshagent_status)
    [[ "$n" == "0" ]] || return
    pri_row 2 "󰌆 ssh-agent  $(chip_warn 'no keys')" \
        "$__DIR__/actions.sh ssh-add" true "ssh-agent is running but has 0 identities loaded — click to run ssh-add"
}

# ── langver ──────────────────────────────────────────────────
# Heartbeat: shows active language-version-manager versions.
# Bar = first (highest priority) detected version; menu = all.
# All probes batched into one cached fetch (300s) — these tools
# spawn subshells and are too slow to call on every Argos tick.

_langver_probe_all() {
    cache_get langver.all 300 bash -c '
        out=""
        add() {
            local prefix="$1" val="$2"
            val="${val%%[[:space:]]*}"
            [[ -z "$val" || "$val" == "system" ]] && return
            [[ -n "$out" ]] && out+=" · "
            out+="${prefix}${val}"
        }
        if command -v pyenv >/dev/null 2>&1; then
            add "py:" "$(timeout --signal=KILL 1s pyenv version-name 2>/dev/null)"
        fi
        if [[ -f "$HOME/.nvm/nvm.sh" ]]; then
            add "node:" "$(timeout --signal=KILL 1s bash -c ". $HOME/.nvm/nvm.sh >/dev/null 2>&1 && nvm current" 2>/dev/null)"
        fi
        if command -v rbenv >/dev/null 2>&1; then
            add "rb:" "$(timeout --signal=KILL 1s rbenv version-name 2>/dev/null)"
        fi
        if command -v jenv >/dev/null 2>&1; then
            add "java:" "$(timeout --signal=KILL 1s jenv version-name 2>/dev/null)"
        fi
        if command -v goenv >/dev/null 2>&1; then
            add "go:" "$(timeout --signal=KILL 1s goenv version-name 2>/dev/null)"
        fi
        if command -v tfenv >/dev/null 2>&1; then
            add "tf:" "$(timeout --signal=KILL 1s tfenv version-name 2>/dev/null)"
        fi
        printf "%s" "$out"
    '
}

_langver_any_installed() {
    command -v pyenv >/dev/null 2>&1 && return 0
    [[ -f "$HOME/.nvm/nvm.sh" ]] && return 0
    command -v rbenv >/dev/null 2>&1 && return 0
    command -v jenv  >/dev/null 2>&1 && return 0
    command -v goenv >/dev/null 2>&1 && return 0
    command -v tfenv >/dev/null 2>&1 && return 0
    return 1
}

widget_langver_bar() {
    _langver_any_installed || return
    local all; all=$(_langver_probe_all)
    [[ -z "$all" ]] && return
    local first="${all%% · *}"
    printf ' %s' "$first"
}

widget_langver_menu() {
    _langver_any_installed || return
    local all safe_all; all=$(_langver_probe_all)
    [[ -z "$all" ]] && return
    safe_all=$(pango_escape "$all")
    pri_row 4 "<span color=\"$COLOR_ACCENT\"> ${safe_all}</span>" \
        "" false "Language versions: ${all}"
}
