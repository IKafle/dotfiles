#!/usr/bin/env bash
# bx-purpose: audit host for geekbar dependencies (hard, soft, system)
set -euo pipefail

# Pull in the color palette so the doctor matches the rest of bx's
# output. Logging helpers write to stderr; the doctor's report is the
# tool's primary value, so we render to stdout with local printers.
[[ -f "$HOME/.bin/lib/color.sh" ]] && . "$HOME/.bin/lib/color.sh"

# Fall back to empty escapes if color.sh was unavailable.
: "${BX_C_RESET:=}" "${BX_C_BOLD:=}" "${BX_C_DIM:=}"
: "${BX_C_RED:=}" "${BX_C_GREEN:=}" "${BX_C_YELLOW:=}"
: "${BX_C_BLUE:=}" "${BX_C_CYAN:=}" "${BX_C_GRAY:=}"

# ── Section state ──────────────────────────────────────────────────
HARD_FAIL=0
SOFT_FAIL=0
VISUAL_FAIL=0

# ── Render helpers ─────────────────────────────────────────────────
hdr()    { printf '\n%s%s%s\n' "$BX_C_CYAN" "→ $*" "$BX_C_RESET"; }
sect()   { printf '\n%s%s%s\n' "$BX_C_BOLD" "$*" "$BX_C_RESET"; }
yes()    { printf '  %s✓%s %s\n' "$BX_C_GREEN" "$BX_C_RESET" "$*"; }
no()     { printf '  %s✘%s %s\n' "$BX_C_RED"   "$BX_C_RESET" "$*"; }
warnln() { printf '  %s⚠%s %s\n' "$BX_C_YELLOW" "$BX_C_RESET" "$*"; }

# Pretty "✘ <name>  → <reason>  install: <cmd>" with column padding so
# install hints line up. NAME_WIDTH is widest soft-dep name; tweak if
# you add a long-named CLI to the list.
NAME_WIDTH=18
REASON_WIDTH=32

miss_soft() {
    local name=$1 reason=$2 install=${3:-}
    if [[ -n "$install" ]]; then
        printf '  %s✘%s %-*s → %-*s install: %s\n' \
            "$BX_C_RED" "$BX_C_RESET" \
            "$NAME_WIDTH" "$name" \
            "$REASON_WIDTH" "$reason" \
            "$install"
    else
        printf '  %s✘%s %-*s → %s\n' \
            "$BX_C_RED" "$BX_C_RESET" \
            "$NAME_WIDTH" "$name" "$reason"
    fi
}

have_soft() {
    local name=$1 reason=$2
    printf '  %s✓%s %-*s → %s\n' \
        "$BX_C_GREEN" "$BX_C_RESET" "$NAME_WIDTH" "$name" "$reason"
}

have() { command -v "$1" >/dev/null 2>&1; }

# ── Hard deps ──────────────────────────────────────────────────────
check_hard() {
    sect "Hard deps (required):"

    local bash_major
    bash_major=${BASH_VERSINFO[0]:-?}
    if (( bash_major >= 5 )); then
        yes "bash $bash_major.x"
    elif (( bash_major >= 4 )); then
        warnln "bash $bash_major.x  (5.x recommended; some features assume bash 5)"
    else
        no "bash $bash_major.x  → install: sudo apt install bash"
        HARD_FAIL=$((HARD_FAIL + 1))
    fi

    local cmd
    for cmd in awk curl jq; do
        if have "$cmd"; then
            yes "$cmd"
        else
            no "$cmd  → install: sudo apt install $cmd"
            HARD_FAIL=$((HARD_FAIL + 1))
        fi
    done

    # iproute2 ships both ip and ss; either-missing → install iproute2.
    if have ip; then
        yes "ip   (iproute2)"
    else
        no "ip  → install: sudo apt install iproute2"
        HARD_FAIL=$((HARD_FAIL + 1))
    fi
    if have ss; then
        yes "ss   (iproute2)"
    else
        no "ss  → install: sudo apt install iproute2"
        HARD_FAIL=$((HARD_FAIL + 1))
    fi

    # coreutils — present on every sane system; warn rather than fail.
    for cmd in date df timeout; do
        if have "$cmd"; then
            yes "$cmd  (coreutils)"
        else
            warnln "$cmd missing — install: sudo apt install coreutils"
        fi
    done
}

# ── Soft deps ──────────────────────────────────────────────────────
check_soft() {
    sect "Soft deps (per-widget):"

    if have kubectl; then have_soft kubectl "enables k8s widget"
    else miss_soft kubectl "disables k8s" "sudo snap install kubectl --classic"
         SOFT_FAIL=$((SOFT_FAIL + 1)); fi

    if have aws; then have_soft aws "enables cloud (aws)"
    else miss_soft aws "disables cloud (aws)" "sudo apt install awscli"
         SOFT_FAIL=$((SOFT_FAIL + 1)); fi

    if have gcloud; then have_soft gcloud "enables cloud (gcp)"
    else miss_soft gcloud "disables cloud (gcp)" "see https://cloud.google.com/sdk/docs/install"
         SOFT_FAIL=$((SOFT_FAIL + 1)); fi

    if have az; then have_soft az "enables cloud (azure)"
    else miss_soft az "disables cloud (azure)" "curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
         SOFT_FAIL=$((SOFT_FAIL + 1)); fi

    if have nmcli; then have_soft nmcli "enables vpn (NetworkManager)"
    else miss_soft nmcli "disables vpn (NetworkManager)" "sudo apt install network-manager"
         SOFT_FAIL=$((SOFT_FAIL + 1)); fi

    if have wg; then have_soft wg "enables vpn (WireGuard)"
    else miss_soft wg "disables vpn (WireGuard)" "sudo apt install wireguard-tools"
         SOFT_FAIL=$((SOFT_FAIL + 1)); fi

    # wifi probes — either iw or iwconfig is enough for signal parsing.
    if have iw; then
        have_soft iw "enables wifi (signal/SSID)"
    elif have iwconfig; then
        have_soft iwconfig "enables wifi (signal/SSID, legacy)"
    else
        miss_soft "iw or iwconfig" "disables wifi" "sudo apt install iw wireless-tools"
        SOFT_FAIL=$((SOFT_FAIL + 1))
    fi

    if have iwgetid; then have_soft iwgetid "enables wifi SSID"
    else miss_soft iwgetid "disables wifi SSID" "sudo apt install wireless-tools"
         SOFT_FAIL=$((SOFT_FAIL + 1)); fi

    if have pactl; then have_soft pactl "enables audio (vol + mic)"
    else miss_soft pactl "disables audio" "sudo apt install pulseaudio-utils"
         SOFT_FAIL=$((SOFT_FAIL + 1)); fi

    if have sensors; then have_soft sensors "enables cpu temp (fallback path)"
    else miss_soft sensors "cpu temp falls back to /sys/class/hwmon" "sudo apt install lm-sensors"
         SOFT_FAIL=$((SOFT_FAIL + 1)); fi

    if have resolvectl; then have_soft resolvectl "enables dns widget"
    else miss_soft resolvectl "disables dns widget" "sudo apt install systemd-resolved"
         SOFT_FAIL=$((SOFT_FAIL + 1)); fi

    if have apt-get || have apt; then have_soft "apt-get" "enables apt updates widget"
    else miss_soft "apt-get" "disables apt updates" "not an apt-based system?"
         SOFT_FAIL=$((SOFT_FAIL + 1)); fi

    # langver: any one of the version managers enables the widget.
    local vm vm_found=()
    for vm in pyenv nvm rbenv jenv goenv tfenv; do
        # nvm is a function from nvm.sh, not a command; check the script too.
        if have "$vm"; then
            vm_found+=("$vm")
        elif [[ "$vm" == "nvm" && ( -s "$HOME/.nvm/nvm.sh" || -s "/usr/local/opt/nvm/nvm.sh" ) ]]; then
            vm_found+=("nvm")
        fi
    done
    if (( ${#vm_found[@]} > 0 )); then
        have_soft "version managers" "enables langver (found: ${vm_found[*]})"
    else
        miss_soft "pyenv/nvm/rbenv/jenv/goenv/tfenv" \
            "disables langver" "(fine if you don't use version managers)"
        SOFT_FAIL=$((SOFT_FAIL + 1))
    fi

    if have ssh-add; then have_soft ssh-add "enables sshagent widget"
    else miss_soft ssh-add "disables sshagent" "sudo apt install openssh-client"
         SOFT_FAIL=$((SOFT_FAIL + 1)); fi

    if have docker; then have_soft docker "enables docker widget"
    else miss_soft docker "disables docker widget" "bx run docker-init"
         SOFT_FAIL=$((SOFT_FAIL + 1)); fi

    if have notify-send; then have_soft notify-send "enables desktop notifications"
    else miss_soft notify-send "disables notifications" "sudo apt install libnotify-bin"
         SOFT_FAIL=$((SOFT_FAIL + 1)); fi

    if have xdg-open; then have_soft xdg-open "enables menu URL actions"
    else miss_soft xdg-open "disables menu URL actions" "sudo apt install xdg-utils"
         SOFT_FAIL=$((SOFT_FAIL + 1)); fi

    if have htop; then have_soft htop "enables 'Open htop' action"
    else miss_soft htop "disables 'Open htop' action" "sudo apt install htop"
         SOFT_FAIL=$((SOFT_FAIL + 1)); fi

    if have iotop; then have_soft iotop "enables 'Open iotop' action"
    else miss_soft iotop "disables 'Open iotop' action (optional)" "sudo apt install iotop"
         SOFT_FAIL=$((SOFT_FAIL + 1)); fi

    if have ncdu; then have_soft ncdu "enables disk action (optional)"
    else miss_soft ncdu "disables disk action (optional)" "sudo apt install ncdu"
         SOFT_FAIL=$((SOFT_FAIL + 1)); fi
}

# ── System checks ──────────────────────────────────────────────────
check_system() {
    sect "System:"

    # Argos: either the config dir exists OR gnome-extensions lists it.
    local argos_ok=0
    if [[ -d "$HOME/.config/argos" ]]; then
        argos_ok=1
    fi
    if have gnome-extensions && gnome-extensions list 2>/dev/null | grep -qi argos; then
        argos_ok=1
    fi
    if (( argos_ok )); then
        yes "Argos GNOME extension installed"
    else
        no "Argos GNOME extension missing  → install: https://extensions.gnome.org/extension/1176/argos/"
        VISUAL_FAIL=$((VISUAL_FAIL + 1))
    fi

    # JetBrainsMono Nerd Font — the bar's font directive depends on it.
    if have fc-list && fc-list 2>/dev/null | grep -qi 'JetBrainsMono Nerd Font'; then
        yes "JetBrainsMono Nerd Font installed"
    else
        no "JetBrainsMono Nerd Font missing  → install: sudo apt install fonts-jetbrains-mono   (or https://www.nerdfonts.com/font-downloads)"
        VISUAL_FAIL=$((VISUAL_FAIL + 1))
    fi

    # Writable cache + state dirs (one-time bootstrap).
    local d
    for d in "$HOME/.cache/geekbar" "$HOME/.local/state/geekbar"; do
        if [[ ! -d "$d" ]]; then
            mkdir -p "$d" 2>/dev/null || true
        fi
        if [[ -d "$d" && -w "$d" ]]; then
            yes "$d  (writable)"
        else
            no "$d  (NOT writable)  → check permissions / disk full"
            VISUAL_FAIL=$((VISUAL_FAIL + 1))
        fi
    done
}

# ── bx integration ─────────────────────────────────────────────────
check_bx() {
    sect "bx integration:"

    if [[ -L "$HOME/.bin/enabled-plugins/geekbar" ]]; then
        yes "plugin enabled                ~/.config/argos/geekbar.2s+.sh"
    else
        no "plugin not enabled            → run: bx plugin enable geekbar"
        VISUAL_FAIL=$((VISUAL_FAIL + 1))
    fi

    if [[ -L "$HOME/.bin/enabled/45-geekbar-track.sh" ]]; then
        yes "shell hook module enabled     modules/45-geekbar-track.sh"
    else
        warnln "shell hook module not enabled  → run: bx enable geekbar-track (git active-repo tracking will fall back to a hardcoded scan)"
    fi

    # Argos symlink resolves to the plugin entrypoint?
    local argos_link="$HOME/.config/argos/geekbar.2s+.sh"
    local entrypoint="$HOME/.bin/plugins/geekbar/geekbar.argos.sh"
    if [[ -L "$argos_link" ]] && [[ "$(readlink -f "$argos_link")" == "$entrypoint" ]]; then
        yes "Argos symlink resolves"
    elif [[ -e "$argos_link" ]]; then
        no "Argos symlink exists but points elsewhere: $(readlink -f "$argos_link" 2>/dev/null || echo '?')"
        VISUAL_FAIL=$((VISUAL_FAIL + 1))
    else
        no "Argos symlink missing  → run: bx plugin enable geekbar"
        VISUAL_FAIL=$((VISUAL_FAIL + 1))
    fi
}

# ── Verdict ────────────────────────────────────────────────────────
emit_verdict() {
    printf '\n'
    if (( HARD_FAIL > 0 )); then
        printf '%s→ Verdict: BLOCKED — install hard deps first (%d missing)%s\n' \
            "$BX_C_RED" "$HARD_FAIL" "$BX_C_RESET"
    elif (( SOFT_FAIL == 0 && VISUAL_FAIL == 0 )); then
        printf '%s→ Verdict: ready — all dependencies present%s\n' \
            "$BX_C_GREEN" "$BX_C_RESET"
    else
        printf '%s→ Verdict: ready (%d optional widget(s) disabled, %d visual issue(s))%s\n' \
            "$BX_C_YELLOW" "$SOFT_FAIL" "$VISUAL_FAIL" "$BX_C_RESET"
    fi
}

main() {
    hdr "geekbar dependency check"
    check_hard
    check_soft
    check_system
    check_bx
    emit_verdict
    # Doctor is diagnostic only — never fail bx run on missing optionals.
    return 0
}

main "$@"
