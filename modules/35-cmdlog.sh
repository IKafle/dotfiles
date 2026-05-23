[[ -n "${_BX_MOD_cmdlog_LOADED:-}" ]] && return 0
_BX_MOD_cmdlog_LOADED=1

# Records each interactive command with a unix timestamp so the motd
# can show the user's most-used commands in the last hour. We can't
# rely on HISTTIMEFORMAT alone — existing history has no timestamps,
# and we want a single rolling log independent of HISTFILE rotation.

_BX_CMDLOG_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/bx/cmdlog"
_BX_CMDLOG_MAX_LINES=10000
__bx_cmdlog_last_histnum=""

_bx_cmdlog_record() {
    local cur num cmd
    cur=$(HISTTIMEFORMAT='' history 1 2>/dev/null) || return 0
    # `history 1` output is space-padded like "  498  ls -la".
    # Strip leading whitespace before extracting the history number.
    cur=${cur#"${cur%%[![:space:]]*}"}
    num=${cur%% *}
    [[ "$num" == "$__bx_cmdlog_last_histnum" ]] && return 0
    __bx_cmdlog_last_histnum=$num
    cmd=${cur#"$num"}
    # Strip leading whitespace between the number column and the command.
    cmd=${cmd#"${cmd%%[![:space:]]*}"}
    [[ -z "$cmd" ]] && return 0

    local dir="${_BX_CMDLOG_FILE%/*}"
    [[ -d "$dir" ]] || mkdir -p "$dir" 2>/dev/null || return 0
    printf '%d\t%s\n' "$(date +%s)" "$cmd" >> "$_BX_CMDLOG_FILE" 2>/dev/null
}

# Cap the log so it can't grow unbounded; runs once per shell session.
_bx_cmdlog_trim() {
    [[ -f "$_BX_CMDLOG_FILE" ]] || return 0
    local lines
    lines=$(wc -l < "$_BX_CMDLOG_FILE" 2>/dev/null) || return 0
    (( lines > _BX_CMDLOG_MAX_LINES )) || return 0
    local tmp="${_BX_CMDLOG_FILE}.tmp"
    tail -n "$_BX_CMDLOG_MAX_LINES" "$_BX_CMDLOG_FILE" > "$tmp" 2>/dev/null \
        && mv "$tmp" "$_BX_CMDLOG_FILE"
}

# Print top-N most-used commands from the last <secs> (default: 3600s, top 3).
# Each output line: "<count>\t<command>".
_bx_cmdlog_top() {
    local n=${1:-3} window=${2:-3600} cutoff
    [[ -f "$_BX_CMDLOG_FILE" ]] || return 0
    cutoff=$(( $(date +%s) - window ))
    awk -F '\t' -v c="$cutoff" 'NF>=2 && $1 >= c { sub(/^[0-9]+\t/, ""); print }' \
        "$_BX_CMDLOG_FILE" \
        | sort | uniq -c | sort -rn | head -n "$n" \
        | awk '{ count=$1; $1=""; sub(/^ /, ""); printf "%d\t%s\n", count, $0 }'
}

_bx_cmdlog_trim

case ";${PROMPT_COMMAND:-};" in
    *\;_bx_cmdlog_record\;*) : ;;
    *) PROMPT_COMMAND="_bx_cmdlog_record${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac
