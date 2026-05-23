[[ -n "${_BX_MOD_geekbar_track_LOADED:-}" ]] && return 0
_BX_MOD_geekbar_track_LOADED=1

# Writes the active .git root to a state file whenever $PWD changes.
# geekbar's git widget reads this file (Argos has no shell context).
# Stays cheap on every prompt by short-circuiting when PWD is unchanged.

_GEEKBAR_TRACK_STATE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/geekbar/active_repo"
_GEEKBAR_TRACK_LAST_PWD=""

_geekbar_track_update() {
    [[ "$PWD" == "$_GEEKBAR_TRACK_LAST_PWD" ]] && return 0
    _GEEKBAR_TRACK_LAST_PWD="$PWD"

    local dir="$PWD" repo=""
    while [[ -n "$dir" ]]; do
        if [[ -d "$dir/.git" ]]; then
            repo="$dir"
            break
        fi
        [[ "$dir" == "/" ]] && break
        dir="${dir%/*}"
        [[ -z "$dir" ]] && dir="/"
    done

    local state_dir="${_GEEKBAR_TRACK_STATE_FILE%/*}"
    [[ -d "$state_dir" ]] || mkdir -p "$state_dir" 2>/dev/null
    printf '%s\n' "$repo" > "$_GEEKBAR_TRACK_STATE_FILE" 2>/dev/null
}

# Idempotent PROMPT_COMMAND hook — never inject twice in the same shell.
case ";${PROMPT_COMMAND:-};" in
    *\;_geekbar_track_update\;*) : ;;
    *) PROMPT_COMMAND="_geekbar_track_update${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac
