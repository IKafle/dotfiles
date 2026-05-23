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
    if (( first_section )); then
        first_section=0
    else
        echo "---"
    fi
    _section_title "$section"
    # Look up MENU_SECTION_<section> array indirectly.
    members_var="MENU_SECTION_${section}[@]"
    for w in "${!members_var}"; do
        if declare -F "widget_${w}_menu" >/dev/null; then
            "widget_${w}_menu"
        fi
    done
done

echo "---"

# ── Actions ──
argos_dim "── Actions ──"
echo " Refresh now | refresh=true"
echo " Edit config | bash='$__DIR__/actions.sh edit-config' terminal=false"
echo " Open config folder | bash='$__DIR__/actions.sh open-config-folder' terminal=false"
echo " Open htop | bash='$__DIR__/actions.sh open-htop' terminal=false"
