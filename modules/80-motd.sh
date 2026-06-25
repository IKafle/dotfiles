# motd — terminal greeting
#   new terminal  →  system info panel + compact shortcuts
#   reload        →  single confirmation line

[[ -n "${_BX_MOD_motd_LOADED:-}" ]] && return 0
_BX_MOD_motd_LOADED=1

# Renders the todo panel from `today --data` rows on stdin (ADR-0003): the app
# owns data extraction, this owns presentation. Never parses todo.md.
__motd_todo_panel() {
    local R=$'\e[0m' B=$'\e[1m' CY=$'\e[1;36m' CN=$'\e[36m' GN=$'\e[32m' GR=$'\e[90m'

    # Color tags so they read at a glance without drowning the task text:
    # +project in cyan (ties to the panel accent), @context in muted gray.
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
    local backlog=0 done_today=0
    local kind a b
    while IFS=$'\t' read -r kind a b || [[ -n "$kind" ]]; do
        case "$kind" in
            T) states+=("$a"); texts+=("$b") ;;
            B) backlog="$a" ;;
            D) done_today="$a" ;;
        esac
    done

    # Split into pending / done, preserving file order (= priority order).
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

    # Open with a blank line so this panel's header lands on the same row as the
    # system panel's header when composed side-by-side (that panel opens with a
    # blank line too). Closes with a matching blank — same top/bottom envelope.
    printf '\n'

    # ── Header ────────────────────────────────────────────────
    # A title bar: ◆ accent + name on the left, a status badge right-aligned to
    # the panel's content width (PW) for a clean right margin. The badge is
    # stateful — a muted "N left" while there's work, a green "all done ✓" when
    # the list is clear. Same name-then-trailing-detail rhythm as the left header.
    local PW=42 badge_raw="" badge_fmt=""
    if (( total == 0 )); then
        :
    elif (( pend_n == 0 )); then
        badge_raw="all done ✓"; badge_fmt="${GN}${B}all done ✓${R}"
    else
        badge_raw="$pend_n left"; badge_fmt="${GR}$pend_n left${R}"
    fi
    if [[ -n "$badge_raw" ]]; then
        local hpad=$(( PW - 7 - ${#badge_raw} ))   # "◆ today" is 7 visible cols
        (( hpad < 1 )) && hpad=1
        printf "  ${CY}${B}◆ today${R}%*s%s\n" "$hpad" "" "$badge_fmt"
    else
        printf "  ${CY}${B}◆ today${R}\n"
    fi

    if (( total == 0 )); then
        printf '\n'
        printf "  ${GR}no plan yet — run ${R}${B}today${R}\n"
    else
        # ── Progress ──────────────────────────────────────────
        # Completion bar built like the mem/disk bars (same █/░ glyphs), but
        # filled green at any level — more-done is good, opposite of pressure.
        local pct=$(( done_count * 100 / total ))
        local w=10 f e bar=""
        f=$(( pct * w / 100 )); e=$(( w - f ))
        bar="${GN}"
        for (( i=0; i<f; i++ )); do bar+="█"; done
        bar+="${GR}"
        for (( i=0; i<e; i++ )); do bar+="░"; done
        bar+="${R}"
        printf '\n'
        printf "  ${GR}done${R}    %s  ${GN}${B}%3d%%${R}   ${B}%d${R}${GR}/${R}${B}%d${R}\n" \
            "$bar" "$pct" "$done_count" "$total"

        # ── Pending ───────────────────────────────────────────
        # One glyph language, text aligned at col 5: ▸ marks the focus (top of
        # the list = highest priority, since the app has no labels), · the rest.
        # A blank line between entries gives the list room to breathe.
        if (( pend_n > 0 )); then
            printf '\n'
            local pcap=6 shown=0
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

        # ── Done today ────────────────────────────────────────
        # Grouped below pending and fully dimmed — finished work recedes.
        if (( done_count > 0 )); then
            printf '\n'
            local dcap=4 dshown=0
            for (( i=0; i<done_count; i++ )); do
                (( dshown >= dcap )) && break
                printf "  ${GN}✓${R}  ${GR}%s${R}\n" "${finished[i]}"
                dshown=$(( dshown + 1 ))
            done
            (( done_count > dshown )) && \
                printf "  ${GR}   +%d more done${R}\n" "$(( done_count - dshown ))"
        fi
    fi

    # ── Summary ───────────────────────────────────────────────
    printf '\n'
    printf "  ${GR}backlog${R} ${B}%d${R}    ${GR}done today${R} ${B}%d${R}\n" \
        "$backlog" "$done_today"
    printf '\n'

    unset -f _color_tags
}

# Visible width of a string, ignoring ANSI SGR escapes (pure bash, no fork).
__motd_vislen() {
    local s=$1 stripped
    local had_extglob=1; shopt -q extglob || had_extglob=0
    shopt -s extglob
    stripped="${s//$'\e'\[*([0-9;])m/}"
    (( had_extglob )) || shopt -u extglob
    printf '%s' "${#stripped}"
}

# Compose two text blocks side-by-side: LEFT padded to COLUMNS/2, then a
# whitespace gutter, then RIGHT — no divider rule. Left lines are padded (ANSI
# aware) to a common edge so the right column aligns; the left panel is emitted
# verbatim, never reflowed. Right runs out before left when it has fewer lines.
__motd_compose() {
    local left=$1 right=$2 cols=$3
    local half=$(( cols / 2 ))

    local -a llines=() rlines=()
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do llines+=("$line"); done <<< "$left"
    while IFS= read -r line || [[ -n "$line" ]]; do rlines+=("$line"); done <<< "$right"

    local n=${#llines[@]} i ll rl pad vis
    (( ${#rlines[@]} > n )) && n=${#rlines[@]}
    for (( i=0; i<n; i++ )); do
        ll="${llines[i]:-}"
        rl="${rlines[i]:-}"
        vis=$(__motd_vislen "$ll")
        pad=$(( half - vis ))
        (( pad < 0 )) && pad=0
        # No divider rule — the left column is padded to a common edge and a
        # whitespace gutter carries the split, so the columns separate by
        # alignment and space rather than a drawn line.
        printf '%s%*s   %s\n' "$ll" "$pad" "" "$rl"
    done
    # Trailing blank to match the leading one — the system panel ends with one,
    # but $(…) capture above strips it, so re-add it here for symmetry with the
    # top and breathing room before the prompt (stacked mode keeps its own).
    printf '\n'
}

# The system panel — the existing greeting, rendered verbatim and never
# reflowed. Optional $1 is pre-rendered todo-panel text: when given it is
# stacked full-width below the system-info block (the issue-0002 layout); in
# two-column mode it is omitted here and composed beside this block instead.
__motd_system_panel() {
    local todo_block=${1:-}
    local R=$'\e[0m'
    local B=$'\e[1m'
    local CY=$'\e[1;36m'   # bold cyan   — header / cheatsheet labels
    local GN=$'\e[32m'     # green       — ok
    local YL=$'\e[33m'     # yellow      — warn
    local RD=$'\e[31m'     # red         — critical / inbox alert
    local GR=$'\e[90m'     # dark gray   — labels / separators / bar empty

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
    # Same title-bar structure as the todo panel: ◆ accent + bold name on the
    # left, metadata (the date) right-aligned to the panel's content width (LW),
    # so the two panels read as sibling cards composed side by side.
    local LW=56 hhost hdate hleft hpad
    hhost="$(hostname -s)"
    hdate="$(date '+%a %d %b  %H:%M')"
    printf -v hleft "◆ %s@%s" "$USER" "$hhost"
    hpad=$(( LW - ${#hleft} - ${#hdate} ))
    (( hpad < 2 )) && hpad=2
    printf '\n'
    printf "  ${CY}${B}◆ %s${GR}@${CY}%s${R}%*s${GR}%s${R}\n" \
        "$USER" "$hhost" "$hpad" "" "$hdate"
    printf '\n'

    # ── System info ───────────────────────────────────────────
    # Airy rhythm to match the todo panel: one blank line between entries, two
    # between groups so the grouping (identity · resources) stays visible.
    printf "  ${GR}os${R}      %s\n" "$os"
    printf '\n'
    printf "  ${GR}kernel${R}  %s\n" "$kernel"
    printf '\n'
    printf "  ${GR}uptime${R}  %-26s  ${GR}load${R}  %s\n" "$up" "$load_str"
    printf '\n\n'
    printf "  ${GR}mem${R}     %s  %s  ${B}%sG${R} · %sG\n" \
        "$(_bar $mp)" "$(_pct $mp)" "$mug" "$mtg"
    printf '\n'
    printf "  ${GR}disk${R}    %s  %s  ${B}%s${R} · %s\n" \
        "$(_bar $dp)" "$(_pct $dp)" "$du" "$dt"
    printf '\n'
    printf "  ${GR}ip${R}      %s\n" "$ip"
    printf '\n'
    printf "  ${GR}status${R}  %s\n" "$bx_line"

    if (( inbox_count > 0 )); then
        printf '\n\n'
        printf "  ${RD}${B}⚑  %d item(s) waiting in ~/vault/inbox${R}\n" "$inbox_count"
    fi

    # ── Top commands in the last hour ─────────────────────────
    if declare -F _bx_cmdlog_top >/dev/null 2>&1; then
        local top_out
        top_out=$(_bx_cmdlog_top 3 3600)
        if [[ -n "$top_out" ]]; then
            printf '\n\n'
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

    # ── Todo panel (stacked) ──────────────────────────────────
    # Only when pre-rendered todo text was passed in (stacked layout). In
    # two-column mode the orchestrator composes it beside this block instead.
    # The block carries its own leading blank + header, so it needs no extra
    # separator here — printing it directly keeps the whitespace rhythm.
    if [[ -n "$todo_block" ]]; then
        printf '%s\n' "$todo_block"
    fi

    # ── Shortcuts ─────────────────────────────────────────────
    printf '\n\n'
    # Themed clusters — navigate/version · develop/track · inspect · configure
    # — one blank line apart, rows tight within a cluster. Light grouping for a
    # reference legend, echoing the stats' grouping without bloating the grid.
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
    printf "  ${GR}type ${R}${B}shortcuts${R}${GR} for the full reference with descriptions${R}\n\n"

    unset -f _bar _pct
}

# Live terminal width, falling back when COLUMNS is unset (non-login shells).
__motd_cols() {
    if [[ -n "${COLUMNS:-}" ]]; then
        printf '%s' "$COLUMNS"
    else
        tput cols 2>/dev/null || printf '80'
    fi
}

# Below this width the equal halves would force the ~67-col system panel to
# wrap, so we fall back to the stacked layout. 2 × widest left line ≈ 135.
__MOTD_TWO_COL_MIN=135

# Orchestrates layout per render from the live terminal width: side-by-side
# when there is room, otherwise the stacked layout from issue 0002.
__motd_full() {
    local todo="" cols
    cols=$(__motd_cols)

    # Presentation only; data comes from `today --data` (ADR-0003). Skipped
    # silently when the todo app isn't loaded.
    if declare -F today >/dev/null 2>&1; then
        todo="$(today --data 2>/dev/null | __motd_todo_panel)"
    fi

    if [[ -n "$todo" ]] && (( cols >= __MOTD_TWO_COL_MIN )); then
        __motd_compose "$(__motd_system_panel)" "$todo" "$cols"
    else
        __motd_system_panel "$todo"
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
