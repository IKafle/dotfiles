# motd — terminal greeting
#   new terminal  →  evenly-spread multi-column dashboard
#   reload        →  single confirmation line + redraw
#
# Layout: three content blocks (vitals · today · shortcuts) composed into
# columns that are spread evenly across the live terminal width — equal left
# margin, gutters and right margin, recomputed each render. Falls back to two
# columns, then a stacked layout, when the width can't hold the wider form.

[[ -n "${_BX_MOD_motd_LOADED:-}" ]] && return 0
_BX_MOD_motd_LOADED=1

# Visible width of a string, ignoring ANSI SGR escapes (pure bash, no fork).
__motd_vislen() {
    local s=$1 stripped
    local had_extglob=1; shopt -q extglob || had_extglob=0
    shopt -s extglob
    stripped="${s//$'\e'\[*([0-9;])m/}"
    (( had_extglob )) || shopt -u extglob
    printf '%s' "${#stripped}"
}

# Max visible line width across a multi-line block.
__motd_blockwidth() {
    local line w=0 vis
    while IFS= read -r line || [[ -n "$line" ]]; do
        vis=$(__motd_vislen "$line")
        (( vis > w )) && w=$vis
    done <<< "$1"
    printf '%s' "$w"
}

# ── Column 1 · system vitals ───────────────────────────────────
# Machine state at a glance. No header (the master header crowns all columns)
# and no shortcuts — just identity/load/resources, then recent activity.
__motd_vitals() {
    local R=$'\e[0m' B=$'\e[1m' CY=$'\e[1;36m' GN=$'\e[32m' YL=$'\e[33m' RD=$'\e[31m' GR=$'\e[90m'

    local os kernel up load_str ip inbox_count
    local mk ma mt mu mp mug mtg du dt dp
    os=$(awk -F'"' '/PRETTY_NAME/{print $2}' /etc/os-release 2>/dev/null || echo Linux)
    kernel=$(uname -r)
    up=$(uptime -p 2>/dev/null | sed 's/up //')
    load_str=$(awk '{printf "%s · %s · %s", $1, $2, $3}' /proc/loadavg)

    mk=$(awk '/^MemTotal:/{print $2}'     /proc/meminfo)
    ma=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
    mt=$(( mk / 1024 )); mu=$(( (mk - ma) / 1024 )); mp=$(( mu * 100 / mt ))
    mug=$(awk "BEGIN{printf \"%.1f\", $mu/1024}")
    mtg=$(awk "BEGIN{printf \"%.1f\", $mt/1024}")

    read -r du dt dp < <(df -h / | awk 'NR==2{gsub(/%/,""); print $3, $2, $5}')

    ip=$(hostname -I 2>/dev/null | awk '{print $1}'); [[ -z "$ip" ]] && ip="—"

    inbox_count=0
    [[ -d "$HOME/vault/inbox" ]] \
        && inbox_count=$(find "$HOME/vault/inbox" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l)

    local bx_loaded=${BX_MODULES_LOADED:-0}
    [[ -z "${BX_LOADED_AT:-}" ]] && bx_loaded=$(( bx_loaded + 1 ))
    local bx_failed_count=0
    [[ -n "${BX_MODULES_FAILED:-}" ]] \
        && bx_failed_count=$(printf '%s' "$BX_MODULES_FAILED" | tr ',' '\n' | grep -c .)
    local bx_line
    if [[ -z "${BX_VERSION:-}" ]]; then
        bx_line="${RD}${B}⚠ not loaded${R}"
    elif (( bx_failed_count > 0 )); then
        bx_line="${YL}${B}⚠${R} ${GR}${bx_loaded} up · ${bx_failed_count} failed${R}"
    else
        bx_line="${GN}●${R} ${GR}bx · ${bx_loaded} modules${R}"
    fi

    _bar() {
        local p=$1 w=10 f e i s="" col
        if   (( p >= 85 )); then col="$RD"
        elif (( p >= 70 )); then col="$YL"
        else                     col="$GN"
        fi
        f=$(( p * w / 100 )); e=$(( w - f ))
        s="${col}"; for (( i=0; i<f; i++ )); do s+="█"; done
        s+="${GR}";  for (( i=0; i<e; i++ )); do s+="░"; done
        s+="${R}"; printf '%s' "$s"
    }
    _pct() {
        local p=$1 col
        if   (( p >= 85 )); then col="$RD"
        elif (( p >= 70 )); then col="$YL"
        else                     col="$GN"
        fi
        printf "${col}${B}%3d%%${R}" "$p"
    }

    printf "  ${GR}os${R}      %s\n" "$os"
    printf "  ${GR}kernel${R}  %s\n" "$kernel"
    printf "  ${GR}uptime${R}  %s\n" "$up"
    printf "  ${GR}load${R}    %s\n" "$load_str"
    printf '\n'
    printf "  ${GR}mem${R}     %s  %s  ${B}%sG${R} · %sG\n" "$(_bar $mp)" "$(_pct $mp)" "$mug" "$mtg"
    printf "  ${GR}disk${R}    %s  %s  ${B}%s${R} · %s\n"   "$(_bar $dp)" "$(_pct $dp)" "$du" "$dt"
    printf "  ${GR}ip${R}      %s\n" "$ip"
    printf "  ${GR}status${R}  %s\n" "$bx_line"
    (( inbox_count > 0 )) && \
        printf "  ${RD}${B}⚑${R}  ${GR}%d in ~/vault/inbox${R}\n" "$inbox_count"

    if declare -F _bx_cmdlog_top >/dev/null 2>&1; then
        local top_out; top_out=$(_bx_cmdlog_top 3 3600)
        if [[ -n "$top_out" ]]; then
            printf '\n'
            local first=1 count cmd
            while IFS=$'\t' read -r count cmd; do
                [[ -z "$count" ]] && continue
                (( ${#cmd} > 22 )) && cmd="${cmd:0:21}…"
                if (( first )); then
                    printf "  ${GR}top 1h${R}  ${CY}${B}×%-3s${R}  %s\n" "$count" "$cmd"; first=0
                else
                    printf "          ${CY}${B}×%-3s${R}  %s\n" "$count" "$cmd"
                fi
            done <<< "$top_out"
        fi
    fi

    unset -f _bar _pct
}

# ── Column 2 · today ───────────────────────────────────────────
# Renders from `today --data` rows on stdin (ADR-0003): the app owns data
# extraction, this owns presentation. Never parses todo.md. Emits a tight
# card (no outer blank lines) so it aligns row-for-row beside the other
# columns; the composer supplies the surrounding whitespace.
__motd_todo_panel() {
    local R=$'\e[0m' B=$'\e[1m' CY=$'\e[1;36m' CN=$'\e[36m' GN=$'\e[32m' GR=$'\e[90m'

    _color_tags() {
        local word out=""
        for word in $1; do
            case "$word" in
                +?*) out+="${CN}${word}${R} " ;;
                @?*) out+="${GR}${word}${R} " ;;
                *)   out+="${word} " ;;
            esac
        done
        printf '%s' "${out% }"
    }

    local -a texts=() states=()
    local backlog=0 done_today=0 kind a b
    while IFS=$'\t' read -r kind a b || [[ -n "$kind" ]]; do
        case "$kind" in
            T) states+=("$a"); texts+=("$b") ;;
            B) backlog="$a" ;;
            D) done_today="$a" ;;
        esac
    done

    local total=${#texts[@]} done_count=0 i
    local -a pending=() finished=()
    for (( i=0; i<total; i++ )); do
        if [[ "${states[i]}" == "1" ]]; then
            finished+=("${texts[i]}"); done_count=$(( done_count + 1 ))
        else
            pending+=("${texts[i]}")
        fi
    done
    local pend_n=${#pending[@]}

    # Header: ◆ today + a stateful badge right-aligned to the card width.
    local PW=40 badge_raw="" badge_fmt=""
    if   (( total == 0 ));  then :
    elif (( pend_n == 0 )); then badge_raw="all done ✓"; badge_fmt="${GN}${B}all done ✓${R}"
    else                         badge_raw="$pend_n left"; badge_fmt="${GR}$pend_n left${R}"
    fi
    if [[ -n "$badge_raw" ]]; then
        local hpad=$(( PW - 7 - ${#badge_raw} )); (( hpad < 1 )) && hpad=1
        printf "  ${CY}${B}◆ today${R}%*s%s\n" "$hpad" "" "$badge_fmt"
    else
        printf "  ${CY}${B}◆ today${R}\n"
    fi

    if (( total == 0 )); then
        printf '\n'
        printf "  ${GR}no plan yet — run ${R}${B}today${R}\n"
    else
        local pct=$(( done_count * 100 / total ))
        local w=10 f e bar=""
        f=$(( pct * w / 100 )); e=$(( w - f ))
        bar="${GN}"; for (( i=0; i<f; i++ )); do bar+="█"; done
        bar+="${GR}";  for (( i=0; i<e; i++ )); do bar+="░"; done
        bar+="${R}"
        printf '\n'
        printf "  ${GR}done${R}    %s  ${GN}${B}%3d%%${R}   ${B}%d${R}${GR}/${R}${B}%d${R}\n" \
            "$bar" "$pct" "$done_count" "$total"

        if (( pend_n > 0 )); then
            printf '\n'
            local pcap=5 shown=0
            for (( i=0; i<pend_n; i++ )); do
                (( shown >= pcap )) && break
                (( shown > 0 )) && printf '\n'
                if (( i == 0 )); then
                    printf "  ${CY}${B}▸${R}  ${B}%s${R}\n" "$(_color_tags "${pending[i]}")"
                else
                    printf "  ${GR}·${R}  %s\n" "$(_color_tags "${pending[i]}")"
                fi
                shown=$(( shown + 1 ))
            done
            (( pend_n > shown )) && \
                printf "\n  ${GR}   +%d more — run ${R}${B}today${R}\n" "$(( pend_n - shown ))"
        fi

        if (( done_count > 0 )); then
            printf '\n'
            local dcap=3 dshown=0
            for (( i=0; i<done_count; i++ )); do
                (( dshown >= dcap )) && break
                printf "  ${GN}✓${R}  ${GR}%s${R}\n" "${finished[i]}"
                dshown=$(( dshown + 1 ))
            done
            (( done_count > dshown )) && \
                printf "  ${GR}   +%d more done${R}\n" "$(( done_count - dshown ))"
        fi
    fi

    printf '\n'
    printf "  ${GR}backlog${R} ${B}%d${R}    ${GR}done today${R} ${B}%d${R}\n" "$backlog" "$done_today"

    unset -f _color_tags
}

# ── Column 3 · shortcuts ───────────────────────────────────────
# Themed clusters of the cheatsheet, one blank line apart. Reference material,
# so it earns its own column rather than crowding the live status.
__motd_shortcuts() {
    local R=$'\e[0m' B=$'\e[1m' CY=$'\e[1;36m' GR=$'\e[90m'
    printf "  ${CY}nav   ${R}..  ...  ....  -    dev  vault  inbox\n"
    printf "  ${CY}git   ${R}gst  gss  gaa  gcmsg  gp  gl  gco  gcb  gsync  gparent  nah\n"
    printf '\n'
    printf "  ${CY}code  ${R}mkcd  extract  serve  activate  countdown  note\n"
    printf "  ${CY}todo  ${R}today  td  tdone  tpush\n"
    printf '\n'
    printf "  ${CY}net   ${R}netspeed  ports  myip  portcheck\n"
    printf "  ${CY}sys   ${R}battery  psg  dsize  ff\n"
    printf '\n'
    printf "  ${CY}edit  ${R}en  al  fun  con  pr  reload\n"
    printf "  ${CY}dock  ${R}dps  dpsa  dcu  dcd  dlogs  docker_clean\n"
    printf "  ${CY}bx    ${R}bx ls  bx enable  bx disable  bx reload  bx doctor  bx help\n"
    printf '\n'
    printf "  ${GR}type ${R}${B}shortcuts${R}${GR} for the full reference${R}\n"
}

# Compose blocks into a cohesive, left-anchored column group. Every block
# starts at the left edge so the text reads naturally left-to-right; columns
# are separated by a fixed, equal gutter (not a width-scaled one) so the
# spacing between them is uniform and they stay grouped as one dashboard at any
# width. Leftover width pools on the right, like any CLI output. The master
# header's date is right-aligned to the block's own right edge.
#   $1 cols  $2 header-left (fmt)  $3 header-date (fmt)  $4.. column blocks
__motd_layout() {
    local cols=$1 hfmt=$2 hdate=$3; shift 3
    local -a blocks=("$@")
    local n=${#blocks[@]}

    local -A L
    local -a colw=()
    local i r w line vis maxrows=0
    for (( i=0; i<n; i++ )); do
        r=0; w=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            L[$i,$r]="$line"
            vis=$(__motd_vislen "$line")
            (( vis > w )) && w=$vis
            (( r++ ))
        done <<< "${blocks[i]}"
        colw[i]=$w
        (( r > maxrows )) && maxrows=$r
    done

    local GUTTER=$__MOTD_GUTTER
    local gut; printf -v gut '%*s' "$GUTTER" ''

    # Block width = column widths + the gutters between them.
    local blockw=0
    for (( i=0; i<n; i++ )); do blockw=$(( blockw + colw[i] )); done
    blockw=$(( blockw + GUTTER * (n - 1) ))

    # Left-anchored: no centering margin. The columns already carry a 2-space
    # indent, which serves as the left margin so the block lines up naturally.

    # Header: identity at the block's left edge (offset by the columns' 2-space
    # indent), date right-aligned to the block's right edge.
    local hvis dvis hpad
    hvis=$(__motd_vislen "$hfmt"); dvis=$(__motd_vislen "$hdate")
    hpad=$(( blockw - 2 - hvis - dvis )); (( hpad < 2 )) && hpad=2
    printf '\n'
    printf '  %s%*s%s\n' "$hfmt" "$hpad" '' "$hdate"
    printf '\n'

    local c out pad
    for (( r=0; r<maxrows; r++ )); do
        out=""
        for (( c=0; c<n; c++ )); do
            line="${L[$c,$r]:-}"
            vis=$(__motd_vislen "$line")
            pad=$(( colw[c] - vis )); (( pad < 0 )) && pad=0
            if (( c < n - 1 )); then
                printf -v out '%s%s%*s%s' "$out" "$line" "$pad" '' "$gut"
            else
                out+="$line"
            fi
        done
        printf '%s\n' "$out"
    done
    printf '\n'
}

# Stacked fallback for narrow terminals: header, then each block full-width,
# one blank line apart.
__motd_stacked() {
    local cols=$1 hfmt=$2 hdate=$3; shift 3
    local -a blocks=("$@")
    local frame=$(( cols - 4 )); (( frame > 76 )) && frame=76
    local hvis dvis hpad
    hvis=$(__motd_vislen "$hfmt"); dvis=$(__motd_vislen "$hdate")
    hpad=$(( frame - hvis - dvis )); (( hpad < 2 )) && hpad=2
    printf '\n'
    printf '  %s%*s%s\n' "$hfmt" "$hpad" '' "$hdate"
    printf '\n'
    local blk first=1
    for blk in "${blocks[@]}"; do
        [[ -z "$blk" ]] && continue
        (( first )) || printf '\n'
        printf '%s\n' "$blk"
        first=0
    done
    printf '\n'
}

# Live terminal width, falling back when COLUMNS is unset (non-login shells).
__motd_cols() {
    if [[ -n "${COLUMNS:-}" ]]; then
        printf '%s' "$COLUMNS"
    else
        tput cols 2>/dev/null || printf '80'
    fi
}

# Fixed gutter between columns — comfortable but tight, so the columns stay
# grouped as one dashboard at any width. The composed block is centered in the
# terminal, with equal margins either side.
__MOTD_GUTTER=6

# Orchestrate the layout per render from the live width: three even columns
# when they fit, then vitals+shortcuts | today as two, then stacked.
__motd_full() {
    local cols; cols=$(__motd_cols)
    local R=$'\e[0m' B=$'\e[1m' CY=$'\e[1;36m' GR=$'\e[90m'

    local hhost datestr hfmt hdate
    hhost="$(hostname -s)"
    datestr="$(date '+%a %d %b  %H:%M')"
    printf -v hfmt  "${CY}${B}◆ %s${GR}@${CY}%s${R}" "$USER" "$hhost"
    printf -v hdate "${GR}%s${R}" "$datestr"

    local vitals shorts todo=""
    vitals="$(__motd_vitals)"
    shorts="$(__motd_shortcuts)"
    if declare -F today >/dev/null 2>&1; then
        todo="$(today --data 2>/dev/null | __motd_todo_panel)"
    fi

    # A column form is used only when the cohesive block (columns + fixed
    # gutters) fits with a little room to centre it.
    local w1 w2 w3 wL gut=$__MOTD_GUTTER
    w1=$(__motd_blockwidth "$vitals")
    w3=$(__motd_blockwidth "$shorts")

    if [[ -n "$todo" ]]; then
        w2=$(__motd_blockwidth "$todo")
        if (( cols >= w1 + w2 + w3 + 2 * gut + 4 )); then
            __motd_layout "$cols" "$hfmt" "$hdate" "$vitals" "$todo" "$shorts"
            return
        fi
        local leftblock; printf -v leftblock '%s\n\n%s' "$vitals" "$shorts"
        wL=$(__motd_blockwidth "$leftblock")
        if (( cols >= wL + w2 + gut + 4 )); then
            __motd_layout "$cols" "$hfmt" "$hdate" "$leftblock" "$todo"
            return
        fi
        __motd_stacked "$cols" "$hfmt" "$hdate" "$vitals" "$todo" "$shorts"
        return
    fi

    if (( cols >= w1 + w3 + gut + 4 )); then
        __motd_layout "$cols" "$hfmt" "$hdate" "$vitals" "$shorts"
    else
        __motd_stacked "$cols" "$hfmt" "$hdate" "$vitals" "$shorts"
    fi
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
