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
    k8s-switch)
        run_in_term "kubectl config get-contexts && echo && read -rp 'context to switch to: ' c && kubectl config use-context \"\$c\""
        ;;
    k8s-get-pods)
        run_in_term "kubectl get pods -A"
        ;;
    k8s-events)
        run_in_term "kubectl get events -A --sort-by=.lastTimestamp | tail -50"
        ;;
    cloud-aws-sso)
        run_in_term "aws sso login"
        ;;
    cloud-aws-whoami)
        run_in_term "aws sts get-caller-identity"
        ;;
    cloud-gcp-list)
        run_in_term "gcloud auth list"
        ;;
    vpn-disconnect)
        name="${1:-}"
        [[ -n "$name" ]] && run_in_term "nmcli connection down '$name'"
        ;;
    vpn-routes)
        run_in_term "ip route show"
        ;;
    ports-show)
        run_in_term "ss -tln | less -S"
        ;;
    ports-prompt)
        run_in_term 'read -rp "Port number: " p; [[ -z "$p" ]] && exit 0; echo; ss -tlnp "sport = :$p" 2>/dev/null || ss -tlnp | grep -E ":$p[[:space:]]"'
        ;;
    ssh-add)
        run_in_term "ssh-add"
        ;;
    ssh-add-list)
        run_in_term "ssh-add -L"
        ;;
    dns-status)
        run_in_term "resolvectl status | less -S"
        ;;
    dns-flush)
        run_in_term "sudo resolvectl flush-caches && echo 'DNS cache flushed.'"
        ;;
    apt-list)
        run_in_term "apt list --upgradable 2>/dev/null"
        ;;
    apt-upgrade)
        run_in_term "sudo apt update && sudo apt upgrade"
        ;;
    apt-security)
        run_in_term "apt list --upgradable 2>/dev/null | grep -- '-security/'"
        ;;
    apt-refresh)
        rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/geekbar/apt.count" \
              "${XDG_CACHE_HOME:-$HOME/.cache}/geekbar/apt.security"
        notify-send "geekbar" "apt cache cleared — refreshing on next tick" 2>/dev/null
        ;;
    open-url)
        xdg-open "$1" >/dev/null 2>&1 &
        ;;
    vol-up)    pactl set-sink-volume   @DEFAULT_SINK@   +5% ;;
    vol-down)  pactl set-sink-volume   @DEFAULT_SINK@   -5% ;;
    vol-mute)  pactl set-sink-mute     @DEFAULT_SINK@   toggle ;;
    mic-mute)  pactl set-source-mute   @DEFAULT_SOURCE@ toggle ;;
    mixer)     pavucontrol & ;;

    # ── git ──────────────────────────────────────────────────
    git-fetch-all)
        repo="${1:-$HOME}"
        run_in_term "cd '$repo' && git fetch --all"
        ;;
    git-log)
        repo="${1:-$HOME}"
        run_in_term "cd '$repo' && git log --oneline -20"
        ;;
    git-open-editor)
        repo="${1:-$HOME}"
        # Prefer GUI editor on the repo dir; fall back to $EDITOR in a terminal.
        edit_file "$repo"
        ;;
    git-open-term)
        repo="${1:-$HOME}"
        run_in_term "cd '$repo' && exec \$SHELL"
        ;;

    # ── disk ─────────────────────────────────────────────────
    disk-ncdu)
        path="${1:-$HOME}"
        if ! command -v ncdu >/dev/null 2>&1; then
            notify-send "geekbar" "ncdu not installed" 2>/dev/null
            exit 0
        fi
        run_in_term "ncdu '$path'"
        ;;
    disk-du)
        path="${1:-$HOME}"
        run_in_term "du -sh '$path'/* 2>/dev/null | sort -h | tail -20 || du -sh '$path'/* 2>/dev/null"
        ;;

    # ── top processes ────────────────────────────────────────
    top-kill)
        pid="${1:-}"
        if [[ -z "$pid" || ! "$pid" =~ ^[0-9]+$ ]]; then
            notify-send "geekbar" "top-kill: missing or invalid PID" 2>/dev/null
            exit 1
        fi
        if (( pid == 1 )); then
            notify-send "geekbar" "Refusing to kill PID 1 (init)" 2>/dev/null
            exit 1
        fi
        notify-send "geekbar" "Kill PID $pid? Running kill in terminal" 2>/dev/null
        run_in_term "kill -TERM $pid; sleep 1; ps -p $pid"
        ;;
    top-renice)
        pid="${1:-}"
        if [[ -z "$pid" || ! "$pid" =~ ^[0-9]+$ ]]; then
            notify-send "geekbar" "top-renice: missing or invalid PID" 2>/dev/null
            exit 1
        fi
        run_in_term "renice +10 $pid"
        ;;
    htop-filter)
        pid="${1:-}"
        if [[ -z "$pid" || ! "$pid" =~ ^[0-9]+$ ]]; then
            notify-send "geekbar" "htop-filter: missing or invalid PID" 2>/dev/null
            exit 1
        fi
        run_in_term "htop -p $pid"
        ;;

    # ── network ──────────────────────────────────────────────
    net-nload)
        iface="${1:-}"
        if command -v nload >/dev/null 2>&1; then
            if [[ -n "$iface" ]]; then run_in_term "nload '$iface'"
            else                       run_in_term "nload"
            fi
        elif command -v bmon >/dev/null 2>&1; then
            if [[ -n "$iface" ]]; then run_in_term "bmon -p '$iface'"
            else                       run_in_term "bmon"
            fi
        else
            notify-send "geekbar" "neither nload nor bmon is installed" 2>/dev/null
        fi
        ;;
    net-trace)
        run_in_term "traceroute 8.8.8.8"
        ;;

    # ── system / geekbar self ────────────────────────────────
    argos-restart)
        # Argos's dbus interface name varies by extension build; if the
        # primary call fails, try the USR1 signal and finally surface a
        # hint about the X11-only Alt+F2 → r restart.
        if gdbus call --session \
            --dest com.github.p-e-w.argos \
            --object-path /com/github/p-e-w/argos \
            --method com.github.p-e-w.argos.Reload >/dev/null 2>&1; then
            notify-send "geekbar" "Argos panels reloaded" 2>/dev/null
        elif pkill -USR1 argos 2>/dev/null; then
            notify-send "geekbar" "Argos signalled (USR1)" 2>/dev/null
        else
            notify-send "geekbar" "Couldn't reload Argos — on X11 try Alt+F2 → r" 2>/dev/null
        fi
        ;;
    geekbar-doctor)
        if [[ -x "$HOME/.bin/tools/geekbar-doctor.sh" ]]; then
            run_in_term "$HOME/.bin/tools/geekbar-doctor.sh"
        else
            run_in_term "bx run geekbar-doctor"
        fi
        ;;
    geekbar-test)
        if [[ -x "$HOME/.bin/tools/geekbar-test.sh" ]]; then
            run_in_term "$HOME/.bin/tools/geekbar-test.sh"
        else
            run_in_term "bx run geekbar-test"
        fi
        ;;
    show-widget-catalog)
        if [[ -x "$HOME/.bin/tools/geekbar-test.sh" ]]; then
            run_in_term "$HOME/.bin/tools/geekbar-test.sh"
        else
            run_in_term "bx run geekbar-test"
        fi
        ;;

    # ── reboot ───────────────────────────────────────────────
    reboot-now)
        # Type "yes" to proceed. Any other input cancels.
        run_in_term 'cat /var/run/reboot-required 2>/dev/null; echo; [[ -r /var/run/reboot-required.pkgs ]] && { echo "Triggering packages:"; cat /var/run/reboot-required.pkgs; echo; }; read -rp "Type yes to reboot now: " c; [[ "$c" == "yes" ]] && sudo systemctl reboot || echo "Cancelled."'
        ;;

    # ── activity ─────────────────────────────────────────────
    open-file)
        file="${1:-}"
        if [[ -z "$file" || ! -e "$file" ]]; then
            notify-send "geekbar" "open-file: missing path" 2>/dev/null
            exit 1
        fi
        edit_file "$file"
        ;;

    # ── clipboard ────────────────────────────────────────────
    copy-pubip)
        pubip_file="${XDG_CACHE_HOME:-$HOME/.cache}/geekbar/publicip"
        if [[ ! -s "$pubip_file" ]]; then
            notify-send "geekbar" "No cached public IP yet" 2>/dev/null
            exit 0
        fi
        ip=$(< "$pubip_file")
        if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]] && command -v wl-copy >/dev/null 2>&1; then
            printf '%s' "$ip" | wl-copy
        elif command -v xclip >/dev/null 2>&1; then
            printf '%s' "$ip" | xclip -selection clipboard
        elif command -v wl-copy >/dev/null 2>&1; then
            printf '%s' "$ip" | wl-copy
        else
            notify-send "geekbar" "No clipboard tool (install wl-clipboard or xclip)" 2>/dev/null
            exit 1
        fi
        notify-send "geekbar" "Copied public IP: $ip" 2>/dev/null
        ;;

    *)
        notify-send "geekbar" "Unknown action: $action" 2>/dev/null
        exit 1
        ;;
esac
