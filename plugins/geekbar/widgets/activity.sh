#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  geekbar :: widgets/activity
#  top_repo   — most-active repo today (commits by global git email)
#  last_file  — most recently edited file in the active repo
#  Both menu-only, self-suppressing when nothing to show.
#  Repo discovery: same conventional roots as find_active_repo,
#  plus the currently-active repo (which may live outside them,
#  e.g. dotfile repos under ~/.bin).
# ─────────────────────────────────────────────────────────────

# ── top_repo ─────────────────────────────────────────────────

_activity_collect_top_repo() {
    local email; email=$(git config --global user.email 2>/dev/null)
    [[ -z "$email" ]] && return

    local roots=("$HOME/dev" "$HOME/code" "$HOME/Projects" "$HOME/projects" "$HOME/src" "$HOME/work" "$HOME/repos")
    local repos=() root repo
    for root in "${roots[@]}"; do
        [[ -d "$root" ]] || continue
        while IFS= read -r repo; do
            [[ -n "$repo" ]] && repos+=("$repo")
        done < <(find "$root" -maxdepth 3 -type d -name ".git" -printf '%h\n' 2>/dev/null)
    done
    local active_file="${XDG_CACHE_HOME:-$HOME/.cache}/geekbar/active_repo"
    if [[ -f "$active_file" ]]; then
        local cur; cur=$(< "$active_file")
        [[ -n "$cur" && -d "$cur/.git" ]] && repos+=("$cur")
    fi

    local winner_path="" winner_count=0 winner_ts=0 count ts
    declare -A seen
    for repo in "${repos[@]}"; do
        [[ -n "${seen[$repo]:-}" ]] && continue
        seen[$repo]=1
        count=$(timeout 2 git -C "$repo" rev-list --count --author="$email" --since=midnight HEAD 2>/dev/null || echo 0)
        [[ "$count" =~ ^[0-9]+$ ]] || count=0
        if (( count > winner_count )); then
            winner_count=$count
            winner_path="$repo"
            winner_ts=$(stat -c %Y "$repo/.git" 2>/dev/null || echo 0)
        elif (( count == winner_count && count > 0 )); then
            ts=$(stat -c %Y "$repo/.git" 2>/dev/null || echo 0)
            (( ts > winner_ts )) && { winner_path="$repo"; winner_ts=$ts; }
        fi
    done
    (( winner_count == 0 )) && return
    printf '%s|%s' "$winner_path" "$winner_count"
}

widget_top_repo_bar() { return; }

widget_top_repo_menu() {
    local raw path count basename safe_name dot tooltip
    raw=$(cache_get activity.top_repo "$CACHE_TTL_COLD" bash -c \
        "$(declare -f _activity_collect_top_repo); _activity_collect_top_repo")
    [[ -z "$raw" ]] && return
    IFS='|' read -r path count <<< "$raw"
    [[ -z "$path" || -z "$count" ]] && return
    (( count > 0 )) || return
    basename="${path##*/}"
    safe_name=$(pango_escape "$basename")
    dot="<span color=\"$COLOR_DIM\">·</span>"
    tooltip="Most active today: ${path} (${count} commit$( ((count==1)) || echo s ))"
    pri_row 3 "<span color=\"$COLOR_ACCENT\">󰊢</span> ${safe_name}   ${dot}   ${count} commits today" \
        "$__DIR__/actions.sh git-log ${path}" true "$tooltip"
}

# ── last_file ────────────────────────────────────────────────

_activity_last_file() {
    local state="${XDG_CACHE_HOME:-$HOME/.cache}/geekbar/active_repo"
    [[ -f "$state" ]] || return
    local repo; repo=$(< "$state")
    [[ -n "$repo" && -d "$repo/.git" ]] || return

    local files newest_ts=0 newest_file="" f ts
    files=$(timeout 2 git -C "$repo" status --porcelain 2>/dev/null | awk '{print $NF}')
    if [[ -n "$files" ]]; then
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            [[ -f "$repo/$f" ]] || continue
            ts=$(stat -c %Y "$repo/$f" 2>/dev/null || echo 0)
            (( ts > newest_ts )) && { newest_ts=$ts; newest_file="$f"; }
        done <<< "$files"
    fi

    if [[ -z "$newest_file" ]]; then
        newest_file=$(timeout 2 git -C "$repo" log -1 --name-only --pretty=format: 2>/dev/null \
            | awk 'NF' | head -1)
        if [[ -n "$newest_file" && -f "$repo/$newest_file" ]]; then
            newest_ts=$(stat -c %Y "$repo/$newest_file" 2>/dev/null || echo 0)
        else
            newest_file=""
        fi
    fi

    [[ -z "$newest_file" ]] && return
    local now ago
    now=$(date +%s)
    ago=$(( now - newest_ts ))
    (( ago < 0 )) && ago=0
    printf '%s|%s|%s' "$repo" "$newest_file" "$ago"
}

widget_last_file_bar() { return; }

widget_last_file_menu() {
    local raw repo rel ago abs display safe dot tooltip ago_h
    raw=$(cache_get activity.last_file 30 bash -c \
        "$(declare -f _activity_last_file); _activity_last_file")
    [[ -z "$raw" ]] && return
    IFS='|' read -r repo rel ago <<< "$raw"
    [[ -z "$repo" || -z "$rel" ]] && return
    abs="${repo%/}/${rel}"
    [[ -e "$abs" ]] || return
    display="$rel"
    if (( ${#display} > 40 )); then
        display="…${display: -39}"
    fi
    safe=$(pango_escape "$display")
    ago_h=$(compact_duration "${ago:-0}")
    dot="<span color=\"$COLOR_DIM\">·</span>"
    tooltip="${abs}  (edited ${ago_h} ago)"
    pri_row 3 "<span color=\"$COLOR_ACCENT\">✎</span> ${safe}   ${dot}   ${ago_h} ago" \
        "$__DIR__/actions.sh open-file ${abs}" false "$tooltip"
}
