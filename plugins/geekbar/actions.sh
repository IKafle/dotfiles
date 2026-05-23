#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  geekbar :: actions
#  Helper for Argos click handlers.
#  Usage: actions.sh <action-name> [args...]
#
#  Why this exists: Argos menu-item syntax uses '|' as the
#  separator between label and attributes, and our dropdown
#  commands need '||', pipes, and nested quotes. Rather than
#  fighting Argos's parser, we dispatch through this script
#  with single-word action names.
# ─────────────────────────────────────────────────────────────
set -u

__DIR__="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# ── terminal launcher — tries each terminal in order
run_in_term() {
    local cmd="$*"
    for term in gnome-terminal konsole xfce4-terminal alacritty kitty xterm; do
        if command -v "$term" >/dev/null 2>&1; then
            case "$term" in
                gnome-terminal) "$term" -- bash -c "$cmd; echo; read -rp 'Press enter to close… '" ;;
                konsole)        "$term" -e bash -c "$cmd; echo; read -rp 'Press enter to close… '" ;;
                xterm|alacritty|kitty|xfce4-terminal) \
                                "$term" -e bash -c "$cmd; echo; read -rp 'Press enter to close… '" ;;
            esac
            return
        fi
    done
    notify-send "geekbar" "No terminal emulator found" 2>/dev/null
}

# ── editor launcher — GUI editors first, then $EDITOR in a term
edit_file() {
    local file="$1"
    for ed in code gedit gnome-text-editor kate xed mousepad; do
        if command -v "$ed" >/dev/null 2>&1; then
            "$ed" "$file" &
            return
        fi
    done
    run_in_term "${EDITOR:-nano} '$file'"
}

action="${1:-}"
shift || true

case "$action" in
    edit-config)
        edit_file "$__DIR__/config.sh"
        ;;
    open-config-folder)
        xdg-open "$__DIR__" >/dev/null 2>&1 &
        ;;
    open-htop)
        run_in_term "htop"
        ;;
    docker-ps)
        run_in_term "docker ps"
        ;;
    docker-stats)
        # docker stats is already interactive — no need for the pause wrapper
        for term in gnome-terminal konsole xfce4-terminal alacritty kitty xterm; do
            if command -v "$term" >/dev/null 2>&1; then
                case "$term" in
                    gnome-terminal) "$term" -- docker stats ;;
                    *)              "$term" -e docker stats ;;
                esac
                break
            fi
        done
        ;;
    docker-prune)
        run_in_term "docker system prune -f"
        ;;
    open-url)
        xdg-open "$1" >/dev/null 2>&1 &
        ;;
    vol-up)    pactl set-sink-volume   @DEFAULT_SINK@   +5% ;;
    vol-down)  pactl set-sink-volume   @DEFAULT_SINK@   -5% ;;
    vol-mute)  pactl set-sink-mute     @DEFAULT_SINK@   toggle ;;
    mic-mute)  pactl set-source-mute   @DEFAULT_SOURCE@ toggle ;;
    mixer)     pavucontrol & ;;
    *)
        notify-send "geekbar" "Unknown action: $action" 2>/dev/null
        exit 1
        ;;
esac
