#!/usr/bin/env bash
# bx-purpose: launch the rofi app menu (Super-d, bound by rofi-init)
# WAYLAND_DISPLAY / XDG_RUNTIME_DIR are filled in only when absent, for callers
# that run outside the session environment. GNOME shortcuts already have them.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    WAYLAND_DISPLAY=$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | grep -v '\.lock$' | head -1 | xargs -r basename)
    export WAYLAND_DISPLAY
fi
exec rofi -show drun
