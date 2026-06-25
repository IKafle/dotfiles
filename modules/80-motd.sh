# motd — terminal greeting
#   new terminal  →  system info panel + compact shortcuts
#   reload        →  single confirmation line

[[ -n "${_BX_MOD_motd_LOADED:-}" ]] && return 0
_BX_MOD_motd_LOADED=1

# Renders the todo panel from `today --data` rows on stdin (ADR-0003): the app
# owns data extraction, this owns presentation. Never parses todo.md.
__motd_todo_panel() {
    local R=$'\e[0m' B=$'\e[1m' CY=$'\e[1;36m' GN=$'\e[32m' GR=$'\e[90m'

    # Dim +project / @context tags so they don't dominate the task text.
    _dim_tags() {
        local word out=""
        for word in $1; do
            case "$word" in
                +?*|@?*) out+="${GR}${word}${R} " ;;
                *)       out+="${word} " ;;
            esac
        done
        printf '%s' "${out% }"
    }

    local -a texts=() states=()
    local backlog=0 done_today=0
    local kind a b
    while IFS=$'\t' read -r kind a b || [[ -n "$kind" ]]; do
        case "$kind" in
            T) states+=("$a"); texts+=("$b") ;;
            B) backlog="$a" ;;
            D) done_today="$a" ;;
        esac
    done

    local total=${#texts[@]} done_count=0 i
    for (( i=0; i<total; i++ )); do
        [[ "${states[i]}" == "1" ]] && done_count=$(( done_count + 1 ))
    done

    if (( total == 0 )); then
        printf "  ${GR}no plan yet — run today${R}\n"
    elif (( done_count == total )); then
        printf "  ${GN}${B}all done ✓${R}\n"
    else
        local pct=$(( done_count * 100 / total ))
        # Completion bar: same █/░ glyphs as the mem/disk bars, but filled green
        # at any level — more-done is good here, opposite of resource pressure.
        local w=10 f e bar=""
        f=$(( pct * w / 100 )); e=$(( w - f ))
        bar="${GN}"
        for (( i=0; i<f; i++ )); do bar+="█"; done
        bar+="${GR}"
        for (( i=0; i<e; i++ )); do bar+="░"; done
        bar+="${R}"
        printf "  ${GR}today${R}   %s  ${B}%d${R}${GR}/${R}${B}%d${R}\n" "$bar" "$done_count" "$total"

        local n=0 shown=0 cap=10
        for (( i=0; i<total; i++ )); do
            (( shown >= cap )) && break
            if [[ "${states[i]}" == "1" ]]; then
                printf "  ${GR}✓  %s${R}\n" "${texts[i]}"
            else
                n=$(( n + 1 ))
                printf "  ${CY}${B}%d${R}  %s\n" "$n" "$(_dim_tags "${texts[i]}")"
            fi
            shown=$(( shown + 1 ))
        done
        (( total > shown )) && printf "  ${GR}+%d more — run today${R}\n" "$(( total - shown ))"
    fi

    printf "  ${GR}backlog ${R}${B}%d${R}${GR} · done today ${R}${B}%d${R}\n" \
        "$backlog" "$done_today"

    unset -f _dim_tags
}

__motd_full() {
    local R=$'\e[0m'
    local B=$'\e[1m'
    local CY=$'\e[1;36m'   # bold cyan   — header / cheatsheet labels
    local GN=$'\e[32m'     # green       — ok
    local YL=$'\e[33m'     # yellow      — warn
    local RD=$'\e[31m'     # red         — critical / inbox alert
    local GR=$'\e[90m'     # dark gray   — labels / separators / bar empty

    local SEP="${GR}$(printf '%.0s─' {1..54})${R}"

    # ── Gather ────────────────────────────────────────────────
    local os kernel up load_str ip inbox_count
    local mk ma mt mu mp mug mtg du dt dp

    os=$(awk -F'"' '/PRETTY_NAME/{print $2}' /etc/os-release 2>/dev/null || echo Linux)
    kernel=$(uname -r)
    up=$(uptime -p 2>/dev/null | sed 's/up //')
    load_str=$(awk '{printf "%s · %s · %s", $1, $2, $3}' /proc/loadavg)

    mk=$(awk '/^MemTotal:/{print $2}'     /proc/meminfo)
    ma=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
    mt=$(( mk / 1024 ))
    mu=$(( (mk - ma) / 1024 ))
    mp=$(( mu * 100 / mt ))
    mug=$(awk "BEGIN{printf \"%.1f\", $mu/1024}")
    mtg=$(awk "BEGIN{printf \"%.1f\", $mt/1024}")

    read -r du dt dp < <(df -h / | awk 'NR==2{gsub(/%/,""); print $3, $2, $5}')

    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [[ -z "$ip" ]] && ip="—"

    inbox_count=0
    [[ -d "$HOME/vault/inbox" ]] \
        && inbox_count=$(find "$HOME/vault/inbox" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l)

    # bx load status — derived from state set by ~/.bin/init.sh.
    # During the initial load, BX_LOADED_AT is not yet set (init.sh sets it
    # AFTER the loop). In that case we're still inside the source of motd
    # itself, so add 1 to the count to include ourselves.
    local bx_loaded=${BX_MODULES_LOADED:-0}
    if [[ -z "${BX_LOADED_AT:-}" ]]; then
        bx_loaded=$(( bx_loaded + 1 ))
    fi
    local bx_failed_count=0
    if [[ -n "${BX_MODULES_FAILED:-}" ]]; then
        bx_failed_count=$(printf '%s' "$BX_MODULES_FAILED" | tr ',' '\n' | grep -c .)
    fi
    local bx_line
    if [[ -z "${BX_VERSION:-}" ]]; then
        bx_line="${RD}${B}⚠ bx: not loaded${R} ${GR}— check ~/.bashrc${R}"
    elif (( bx_failed_count > 0 )); then
        bx_line="${YL}${B}⚠ bx${R} ${GR}: ${bx_loaded} loaded, ${bx_failed_count} failed — run \`bx doctor\`${R}"
    else
        bx_line="${GN}● bx${R} ${GR}: ${bx_loaded} modules loaded${R}"
    fi

    # ── Helpers ───────────────────────────────────────────────
    _bar() {
        local p=$1 w=16 f e i bar_str="" col
        if   (( p >= 85 )); then col="$RD"
        elif (( p >= 70 )); then col="$YL"
        else                     col="$GN"
        fi
        f=$(( p * w / 100 )); e=$(( w - f ))
        bar_str="${col}"
        for (( i=0; i<f; i++ )); do bar_str+="█"; done
        bar_str+="${GR}"
        for (( i=0; i<e; i++ )); do bar_str+="░"; done
        bar_str+="${R}"
        printf '%s' "$bar_str"
    }

    _pct() {
        local p=$1 col
        if   (( p >= 85 )); then col="$RD"
        elif (( p >= 70 )); then col="$YL"
        else                     col="$GN"
        fi
        printf "${col}${B}%3d%%${R}" "$p"
    }

    # ── Header ────────────────────────────────────────────────
    printf '\n'
    printf "  ${CY}${B}%s${GR}@${CY}%s${R}   ${GR}%s${R}\n" \
        "$USER" "$(hostname -s)" "$(date '+%a %d %b  %H:%M')"
    printf "  %s\n" "$SEP"

    # ── System info ───────────────────────────────────────────
    printf "  ${GR}os${R}      %s\n" "$os"
    printf "  ${GR}kernel${R}  %s\n" "$kernel"
    printf "  ${GR}uptime${R}  %-26s  ${GR}load${R}  %s\n" "$up" "$load_str"
    printf '\n'
    printf "  ${GR}mem${R}     %s  %s  ${B}%sG${R} · %sG\n" \
        "$(_bar $mp)" "$(_pct $mp)" "$mug" "$mtg"
    printf "  ${GR}disk${R}    %s  %s  ${B}%s${R} · %s\n" \
        "$(_bar $dp)" "$(_pct $dp)" "$du" "$dt"
    printf "  ${GR}ip${R}      %s\n" "$ip"

    printf "  ${GR}status${R}  %s\n" "$bx_line"

    if (( inbox_count > 0 )); then
        printf '\n'
        printf "  ${RD}${B}⚑  %d item(s) waiting in ~/vault/inbox${R}\n" "$inbox_count"
    fi

    # ── Top commands in the last hour ─────────────────────────
    if declare -F _bx_cmdlog_top >/dev/null 2>&1; then
        local top_out
        top_out=$(_bx_cmdlog_top 3 3600)
        if [[ -n "$top_out" ]]; then
            printf '\n'
            local first=1 count cmd
            while IFS=$'\t' read -r count cmd; do
                [[ -z "$count" ]] && continue
                # Trim very long lines so they don't wrap.
                if (( ${#cmd} > 44 )); then
                    cmd="${cmd:0:43}…"
                fi
                if (( first )); then
                    printf "  ${GR}top 1h${R}  ${CY}${B}×%-3s${R}  %s\n" "$count" "$cmd"
                    first=0
                else
                    printf "          ${CY}${B}×%-3s${R}  %s\n" "$count" "$cmd"
                fi
            done <<< "$top_out"
        fi
    fi

    # ── Todo panel ────────────────────────────────────────────
    # Presentation only; data comes from `today --data` (ADR-0003). Skipped
    # silently when the todo app isn't loaded.
    if declare -F today >/dev/null 2>&1; then
        printf '\n'
        printf "  %s\n" "$SEP"
        today --data 2>/dev/null | __motd_todo_panel
    fi

    # ── Shortcuts ─────────────────────────────────────────────
    printf '\n'
    printf "  %s\n" "$SEP"
    printf "  ${CY}nav   ${R}..  ...  ....  -    dev  vault  inbox\n"
    printf "  ${CY}git   ${R}gst  gss  gaa  gcmsg  gp  gl  gco  gcb  gsync  gparent  nah\n"
    printf "  ${CY}code  ${R}mkcd  extract  serve  activate  countdown  note\n"
    printf "  ${CY}net   ${R}netspeed  ports  myip  portcheck\n"
    printf "  ${CY}sys   ${R}battery  psg  dsize  ff\n"
    printf "  ${CY}edit  ${R}en  al  fun  con  pr                   reload\n"
    printf "  ${CY}dock  ${R}dps  dpsa  dcu  dcd  dlogs  docker_clean\n"
    printf "  ${CY}bx    ${R}bx ls  bx enable  bx disable  bx reload  bx doctor  bx help\n"
    printf "  %s\n" "$SEP"
    printf "  ${GR}type ${R}${B}shortcuts${R}${GR} for the full reference with descriptions${R}\n\n"

    unset -f _bar _pct
}

__motd_reload() {
    local R=$'\e[0m' B=$'\e[1m' GN=$'\e[32m' GR=$'\e[90m'
    printf "\n  ${GN}${B}✓${R}  ${GR}reloaded · %s${R}" "$(date '+%H:%M:%S')"
    __motd_full
}

# ── Entry point ───────────────────────────────────────────────
if [[ $- == *i* ]]; then
    if [[ "${BX_MOTD_SHOWN:-0}" == "1" ]]; then
        __motd_reload
    else
        # NOT exported — child shells should show the full panel, not "reloaded".
        BX_MOTD_SHOWN=1
        __motd_full
    fi
fi
