#!/usr/bin/env bash
# bx-purpose: launch the rofi app menu (Super-d, bound by rofi-init)
# bx-tool-kind: runtime
# Rofi 2.x picks its Wayland backend whenever WAYLAND_DISPLAY is set, and that
# backend needs the layer-shell protocol, which GNOME's compositor does not
# provide ("Rofi on wayland requires support for the layer shell protocol").
# Unsetting it makes rofi use X11 through XWayland, which GNOME always runs.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DISPLAY="${DISPLAY:-:0}"
unset WAYLAND_DISPLAY
exec rofi -show drun
