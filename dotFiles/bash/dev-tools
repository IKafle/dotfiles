# dev-tools — practical developer utility functions

# ── Git ───────────────────────────────────────────────────────

# git commit with message — fixes the broken "alias cm" that couldn't take args
cm() { git commit -m "$*"; }

# git checkout — fixes the broken "alias gc" that couldn't take args
gc() { git checkout "$@"; }

# Pretty git log with graph
gitlog() {
    git log \
        --graph \
        --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' \
        --abbrev-commit "$@"
}

# ── Files & directories ───────────────────────────────────────

# mkdir then cd into it
mkcd() { mkdir -p "$1" && cd "$1" || return; }

# Universal archive extractor — handles any format
extract() {
    if [[ -z "$1" ]]; then echo "Usage: extract <archive>"; return 1; fi
    if [[ ! -f "$1" ]]; then echo "Not a file: $1"; return 1; fi
    case "$1" in
        *.tar.bz2)  tar xjf "$1"    ;;
        *.tar.gz)   tar xzf "$1"    ;;
        *.tar.xz)   tar xJf "$1"    ;;
        *.tar)      tar xf  "$1"    ;;
        *.bz2)      bunzip2 "$1"    ;;
        *.gz)       gunzip  "$1"    ;;
        *.zip)      unzip   "$1"    ;;
        *.7z)       7z x    "$1"    ;;
        *.rar)      unrar x "$1"    ;;
        *.Z)        uncompress "$1" ;;
        *)          echo "Unknown format: $1"; return 1 ;;
    esac
}

# Show directory sizes sorted largest first
dsize() { du -sh -- "${1:-.}"/* 2>/dev/null | sort -rh; }

# Find a file by name (case-insensitive)
ff() { find . -iname "*${1}*" 2>/dev/null; }

# Search text inside files recursively
ftext() { grep -rn --color=auto "$1" "${2:-.}"; }

# ── Python ────────────────────────────────────────────────────

# Start a quick HTTP server from current directory
serve() {
    local port=${1:-8000}
    echo "Serving $(pwd) on http://localhost:${port}"
    python3 -m http.server "$port"
}

# Activate Python venv — searches current dir and parents
activate() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        for venv in "$dir/venv" "$dir/.venv" "$dir/env"; do
            if [[ -f "$venv/bin/activate" ]]; then
                # shellcheck disable=SC1090
                source "$venv/bin/activate"
                echo "Activated: $venv"
                return 0
            fi
        done
        dir=$(dirname "$dir")
    done
    echo "No virtual environment found in $PWD or any parent directory"
    return 1
}

# ── Docker ────────────────────────────────────────────────────

# Remove stopped containers, dangling images, unused volumes + networks
docker_clean() {
    echo "→ Removing stopped containers..."
    docker container prune -f
    echo "→ Removing dangling images..."
    docker image prune -f
    echo "→ Removing unused volumes..."
    docker volume prune -f
    echo "→ Removing unused networks..."
    docker network prune -f
    echo "Done."
}

# Show running container logs with a friendly prompt
dlogs() {
    if [[ -z "$1" ]]; then
        echo "Usage: dlogs <container-name-or-id>"
        docker ps --format "table {{.Names}}\t{{.Status}}"
        return 1
    fi
    docker logs -f "$1"
}

# ── Network ───────────────────────────────────────────────────

# Check if a remote host/port is reachable
portcheck() {
    if [[ -z "$1" || -z "$2" ]]; then echo "Usage: portcheck <host> <port>"; return 1; fi
    timeout 3 bash -c "cat < /dev/null > /dev/tcp/$1/$2" 2>/dev/null \
        && echo "✓  $1:$2 is open" \
        || echo "✗  $1:$2 is closed or unreachable"
}

# ── Productivity ──────────────────────────────────────────────

# Countdown timer: countdown 5m "Coffee ready"
countdown() {
    local input="${1:-60}" msg="${2:-Time is up!}"
    local secs
    case "$input" in
        *h) secs=$(( ${input%h} * 3600 )) ;;
        *m) secs=$(( ${input%m} * 60   )) ;;
        *s) secs=${input%s}               ;;
        *)  secs=$input                   ;;
    esac
    echo "Countdown: ${secs}s — $msg"
    while (( secs > 0 )); do
        printf "\r  %02d:%02d remaining " $(( secs/60 )) $(( secs%60 ))
        sleep 1
        (( secs-- ))
    done
    printf "\r  Done! — %s\n" "$msg"
    command -v notify-send &>/dev/null && notify-send "Timer" "$msg"
}

# Quick notes to a daily log file
note() {
    local logfile="$HOME/vault/inbox/notes-$(date +%Y-%m-%d).txt"
    if [[ -z "$1" ]]; then
        [[ -f "$logfile" ]] && cat "$logfile" || echo "No notes today."
        return
    fi
    echo "[$(date '+%H:%M')] $*" >> "$logfile"
    echo "Saved to $logfile"
}

# ── Network speed monitor ────────────────────────────

netspeed() {
    local R=$'\e[0m' B=$'\e[1m'
    local CY=$'\e[1;36m' GN=$'\e[32m' YL=$'\e[33m' RD=$'\e[31m' GR=$'\e[90m'

    # Detect default interface
    local iface="${1:-}"
    [[ -z "$iface" ]] && iface=$(ip route 2>/dev/null | awk '/^default/{print $5; exit}')
    [[ -z "$iface" ]] && iface=$(awk 'NR>1 && $2=="00000000"{print $1; exit}' /proc/net/route 2>/dev/null)

    if [[ -z "$iface" ]] || ! grep -q "^ *${iface}:" /proc/net/dev 2>/dev/null; then
        printf "  No active interface found.\n  Usage: netspeed [interface]\n"
        return 1
    fi

    local LINE="${GR}$(printf '%.0s─' {1..54})${R}"
    local GRAPH_W=20
    local rx_hist=() tx_hist=()
    local rx_peak=0 tx_peak=0 rx_total=0 tx_total=0
    local start_time=$SECONDS i

    for (( i=0; i<GRAPH_W; i++ )); do rx_hist+=( 0 ); tx_hist+=( 0 ); done

    _net_read() {
        awk -v dev="${iface}:" '$1==dev{print $2, $10}' /proc/net/dev
    }

    _net_fmt_speed() {
        local b=$1
        if   (( b >= 1073741824 )); then awk "BEGIN{printf \"%.2f GB/s\", $b/1073741824}"
        elif (( b >= 1048576   )); then awk "BEGIN{printf \"%.2f MB/s\", $b/1048576}"
        elif (( b >= 1024      )); then awk "BEGIN{printf \"%.1f KB/s\", $b/1024}"
        else                            printf "%d B/s" "$b"
        fi
    }

    _net_fmt_bytes() {
        local b=$1
        if   (( b >= 1073741824 )); then awk "BEGIN{printf \"%.2f GB\", $b/1073741824}"
        elif (( b >= 1048576   )); then awk "BEGIN{printf \"%.2f MB\", $b/1048576}"
        elif (( b >= 1024      )); then awk "BEGIN{printf \"%.1f KB\", $b/1024}"
        else                            printf "%d B" "$b"
        fi
    }

    _net_spark() {
        local values=("$@") peak=0 out="" idx
        local blocks=( '▁' '▂' '▃' '▄' '▅' '▆' '▇' '█' )
        for v in "${values[@]}"; do (( v > peak )) && peak=$v; done
        for v in "${values[@]}"; do
            if (( peak == 0 )); then out+='▁'
            else
                idx=$(( v * 7 / peak ))
                (( idx > 7 )) && idx=7
                out+="${blocks[$idx]}"
            fi
        done
        printf '%s' "$out"
    }

    _net_color() {
        if   (( $1 >= 10485760 )); then printf '%s' "$RD"
        elif (( $1 >= 1048576  )); then printf '%s' "$YL"
        else                           printf '%s' "$GN"
        fi
    }

    _net_elapsed() {
        local s=$(( SECONDS - start_time ))
        printf '%02d:%02d:%02d' $(( s/3600 )) $(( (s%3600)/60 )) $(( s%60 ))
    }

    _net_cleanup() {
        tput cnorm
        printf '\033[2K\r  %s Stopped.\n\n' "${GR}"
        unset -f _net_read _net_fmt_speed _net_fmt_bytes _net_spark _net_color _net_elapsed _net_cleanup
        trap - INT TERM
    }

    local prev_rx prev_tx
    read -r prev_rx prev_tx < <(_net_read)

    printf '\n'
    printf "  ${CY}${B}Network Monitor${R}  ${GR}·  %s  ·  Ctrl+C to exit${R}\n" "$iface"
    printf "  %s\n" "$LINE"
    printf '\n\n\n\n\n'   # reserve 5 lines for the live block

    tput civis
    trap '_net_cleanup; return' INT TERM

    while true; do
        sleep 1
        local rx tx rx_s tx_s
        read -r rx tx < <(_net_read)

        rx_s=$(( rx - prev_rx )); (( rx_s < 0 )) && rx_s=0
        tx_s=$(( tx - prev_tx )); (( tx_s < 0 )) && tx_s=0

        rx_total=$(( rx_total + rx_s ))
        tx_total=$(( tx_total + tx_s ))
        (( rx_s > rx_peak )) && rx_peak=$rx_s
        (( tx_s > tx_peak )) && tx_peak=$tx_s

        rx_hist=( "${rx_hist[@]:1}" "$rx_s" )
        tx_hist=( "${tx_hist[@]:1}" "$tx_s" )

        prev_rx=$rx; prev_tx=$tx

        printf '\033[5A'   # move up 5 lines to overwrite

        printf "  ${GR}↓ down${R}  %s  $(_net_color $rx_s)${B}%-14s${R}  ${GR}peak${R}  %s\n" \
            "$(_net_spark "${rx_hist[@]}")" "$(_net_fmt_speed $rx_s)" "$(_net_fmt_speed $rx_peak)"
        printf "  ${GR}↑ up  ${R}  %s  $(_net_color $tx_s)${B}%-14s${R}  ${GR}peak${R}  %s\n" \
            "$(_net_spark "${tx_hist[@]}")" "$(_net_fmt_speed $tx_s)" "$(_net_fmt_speed $tx_peak)"
        printf '\n'
        printf "  ${GR}session${R}  ↓ %-20s  ↑ %s\n" \
            "$(_net_fmt_bytes $rx_total)" "$(_net_fmt_bytes $tx_total)"
        printf "  ${GR}elapsed${R}  %s\n" "$(_net_elapsed)"
    done
}

# ── Full command reference ────────────────────────────

shortcuts() {
    local R=$'\e[0m'
    local B=$'\e[1m'
    local CY=$'\e[1;36m'
    local GR=$'\e[90m'

    local LINE="${GR}$(printf '%.0s─' {1..56})${R}"

    _sec() { printf "\n  ${CY}${B}%s${R}\n\n" "$1"; }
    _cmd() { printf "  ${B}%-26s${R}${GR}%s${R}\n" "$1" "$2"; }

    {
        printf '\n'
        printf "  ${CY}${B}Command Reference${R}  ${GR}— all shortcuts and functions${R}\n"
        printf "  %s\n" "$LINE"

        _sec "Navigation"
        _cmd ".."                    "go up one directory"
        _cmd "..."                   "go up two directories"
        _cmd "...."                  "go up three directories"
        _cmd "-"                     "go to previous directory"
        _cmd "dev"                   "cd ~/vault/code"
        _cmd "vault"                 "cd ~/vault"
        _cmd "inbox"                 "ls ~/vault/inbox"

        _sec "Git"
        _cmd "gs"                    "git status"
        _cmd "gaa"                   "git add ."
        _cmd "cm <msg>"              "git commit -m"
        _cmd "gpu"                   "git push"
        _cmd "gp"                    "git pull"
        _cmd "gl"                    "git log — graph, all branches"
        _cmd "gb"                    "git branch"
        _cmd "gd"                    "git diff"
        _cmd "gds"                   "git diff --staged"
        _cmd "gst"                   "git stash"
        _cmd "gsp"                   "git stash pop"
        _cmd "gc <branch>"           "git checkout"
        _cmd "gitlog"                "pretty graph log with author + time"

        _sec "Files & Directories"
        _cmd "mkcd <dir>"            "mkdir + cd in one step"
        _cmd "extract <file>"        "extract any archive (tar, zip, 7z, rar…)"
        _cmd "dsize [dir]"           "directory sizes sorted largest first"
        _cmd "ff <name>"             "find file by name (case-insensitive)"
        _cmd "ftext <text>"          "search text inside files recursively"
        _cmd "ll"                    "ls -alF (long list, all, classify)"
        _cmd "la"                    "ls -A (include hidden files)"
        _cmd "cls"                   "clear screen then ls"

        _sec "Python"
        _cmd "py"                    "python3"
        _cmd "pip"                   "pip3"
        _cmd "serve [port]"          "HTTP server from current dir  (default 8000)"
        _cmd "activate"              "activate nearest venv (searches up to /)"

        _sec "Docker"
        _cmd "dps"                   "docker ps"
        _cmd "dpsa"                  "docker ps -a  (include stopped)"
        _cmd "dcu"                   "docker compose up -d"
        _cmd "dcd"                   "docker compose down"
        _cmd "dc"                    "docker compose"
        _cmd "dlogs <name>"          "follow container logs  (Ctrl-C to exit)"
        _cmd "docker_clean"          "prune stopped containers, images, volumes"

        _sec "Network"
        _cmd "netspeed [iface]"      "live ↓↑ speed monitor with sparkline graph"
        _cmd "ports"                 "show all listening ports  (ss -tulpn)"
        _cmd "myip"                  "external / public IP address"
        _cmd "iplocal"               "local network IP address"
        _cmd "portcheck <host> <p>"  "check if remote host:port is reachable"

        _sec "Productivity"
        _cmd "countdown <t> [msg]"   "timer — e.g.  countdown 25m 'Pomodoro done'"
        _cmd "note [text]"           "append timestamped note; no args = read today"
        _cmd "battery"               "battery state, percentage, time remaining"

        _sec "Dotfile Editing"
        _cmd "en"                    "edit env  (PATH, exports, EDITOR)"
        _cmd "al"                    "edit aliases"
        _cmd "fun"                   "edit functions"
        _cmd "con"                   "edit config  (holiday greetings)"
        _cmd "pr"                    "edit prompt"
        _cmd "reload"                "reload shell  (source ~/.bashrc)"

        _sec "System"
        _cmd "psg <name>"            "search running processes by name"
        _cmd "df"                    "disk usage  (human-readable)"
        _cmd "free"                  "memory usage  (human-readable)"
        _cmd "settings"              "open GNOME control centre"

        printf "  %s\n\n" "$LINE"

    } | ${PAGER:-less -R}

    unset -f _sec _cmd
}
