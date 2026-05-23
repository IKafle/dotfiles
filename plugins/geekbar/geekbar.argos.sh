#!/usr/bin/env bash
# bx-purpose: GNOME panel widget showing system stats and dev context (CPU, mem, net, git, docker, more)
# bx-plugin-kind: argos
# bx-plugin-target: ~/.config/argos/geekbar.2s+.sh
# ─────────────────────────────────────────────────────────────
#  geekbar :: entrypoint (directory-plugin form)
#  Compact status bar + expanded dropdown menu.
#  Runs every 2s via Argos (filename: geekbar.2s+.sh).
# ─────────────────────────────────────────────────────────────

__DIR__="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=/dev/null
source "$__DIR__/config.sh"
# shellcheck source=/dev/null
source "$__DIR__/lib.sh"
for f in "$__DIR__"/widgets/*.sh; do
    # shellcheck source=/dev/null
    source "$f"
done

# ═════════════════════════════════════════════════════════════
#  BAR — iterate BAR_WIDGETS, join non-empty segments with "│ "
# ═════════════════════════════════════════════════════════════

BAR=""
for w in "${BAR_WIDGETS[@]}"; do
    if ! declare -F "widget_${w}_bar" >/dev/null; then
        continue
    fi
    seg=$("widget_${w}_bar")
    [[ -z "$seg" ]] && continue
    if [[ -z "$BAR" ]]; then
        BAR="$seg"
    else
        BAR+="  │ $seg"
    fi
done
printf '%s | font="JetBrainsMono Nerd Font" size=11\n' "$BAR"

# ═════════════════════════════════════════════════════════════
#  DROPDOWN MENU
# ═════════════════════════════════════════════════════════════
argos_sep

echo "geekbar | color=$COLOR_ACCENT size=10"
echo "---"

_section_title() {
    # Capitalize first letter, e.g. system → System.
    local s=$1
    argos_dim "── ${s^} ──"
}

first_section=1
for section in "${MENU_SECTIONS[@]}"; do
    # Buffer the section's widget output so we can skip the whole section
    # (and its separator + header) when no widget produced any line.
    members_var="MENU_SECTION_${section}[@]"
    section_body=""
    for w in "${!members_var}"; do
        if declare -F "widget_${w}_menu" >/dev/null; then
            out=$("widget_${w}_menu")
            [[ -z "$out" ]] && continue
            section_body+="$out"$'\n'
        fi
    done
    [[ -z "$section_body" ]] && continue
    if (( first_section )); then
        first_section=0
    else
        echo "---"
    fi
    _section_title "$section"
    printf '%s' "$section_body"
done

echo "---"

# ── Actions ── (collapsed under a parent row via Argos `--` submenu)
echo " geekbar | font=\"JetBrainsMono Nerd Font\""
echo "-- Refresh now | refresh=true"
echo "-- Edit config | bash='$__DIR__/actions.sh edit-config' terminal=false"
echo "-- Open config folder | bash='$__DIR__/actions.sh open-config-folder' terminal=false"
echo "-- Open htop | bash='$__DIR__/actions.sh open-htop' terminal=false"
echo "-- Reload Argos | bash='$__DIR__/actions.sh argos-restart' terminal=false"
echo "-- Run doctor | bash='$__DIR__/actions.sh geekbar-doctor' terminal=false"
