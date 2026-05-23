#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  geekbar :: widgets/context
#  git — primary signal is the shell hook in
#  modules/45-geekbar-track.sh, which writes the active .git
#  root to $XDG_CACHE_HOME/geekbar/active_repo on every cd.
#  Cold-boot fallback is find_active_repo() in lib.sh.
# ─────────────────────────────────────────────────────────────

# Resolve the active repo. Order:
#   1. State file written by the shell hook (cheap, accurate).
#   2. find_active_repo cold-boot scan, cached for CACHE_TTL_COLD.
_widget_git_active_repo() {
    local state="${XDG_CACHE_HOME:-$HOME/.cache}/geekbar/active_repo"
    if [[ -f "$state" ]]; then
        local repo; repo=$(< "$state")
        if [[ -n "$repo" && -d "$repo/.git" ]]; then
            printf '%s' "$repo"
            return
        fi
    fi
    cache_get gitrepo "$CACHE_TTL_COLD" find_active_repo
}

_widget_git_raw() {
    local repo
    repo=$(_widget_git_active_repo)
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
