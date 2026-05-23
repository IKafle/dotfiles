#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  geekbar :: widgets/context
#  git — Stage 2 still walks GIT_WATCH_DIRS via find_active_repo;
#  Stage 3 swaps in the shell hook.
# ─────────────────────────────────────────────────────────────

# Stage 2: cache parsed git status as "branch|ahead|behind|dirty|path".
# Helper shared by bar and menu so we don't probe git twice.
_widget_git_raw() {
    local repo
    repo=$(cache_get gitrepo "$CACHE_TTL_LAZY" find_active_repo)
    [[ -z "$repo" ]] && return
    cache_get gitstatus "$CACHE_TTL_LAZY" git_status "$repo"
}

widget_git_bar() {
    local raw branch ahead behind dirty path
    raw=$(_widget_git_raw)
    [[ -z "$raw" ]] && return
    IFS='|' read -r branch ahead behind dirty path <<< "$raw"
    local out=" $branch"
    (( ahead  > 0 )) && out+=" ↑$ahead"
    (( behind > 0 )) && out+=" ↓$behind"
    (( dirty  > 0 )) && out+=" ●$dirty"
    printf '%s' "$out"
}

widget_git_menu() {
    local raw branch ahead behind dirty path
    raw=$(_widget_git_raw)
    if [[ -z "$raw" ]]; then
        argos_item " Git         no active repo" "$COLOR_DIM"
        return
    fi
    IFS='|' read -r branch ahead behind dirty path <<< "$raw"
    local detail="$branch"
    (( ahead  > 0 )) && detail+=" ↑$ahead"
    (( behind > 0 )) && detail+=" ↓$behind"
    (( dirty  > 0 )) && detail+=" ●$dirty"
    argos_item " Git         $detail"
    argos_item "   $path" "$COLOR_DIM"
}
