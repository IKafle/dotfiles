#!/usr/bin/env bash
# bx-purpose: toggle the rofi app menu (Super-d, bound by rofi-init)
# bx-tool-kind: runtime
# Second press closes: on GNOME wayland an XWayland rofi cannot grab the
# pointer over wayland surfaces, so click-outside never reaches it, and
# Super-d again used to fail with "Rofi already running?".
if pgrep -x rofi >/dev/null; then pkill -x rofi; exit 0; fi

# Rofi 2.x picks its wayland backend whenever WAYLAND_DISPLAY is set, and that
# backend needs the layer-shell protocol, which GNOME does not provide. Unset
# it so rofi runs on X11 via XWayland, which GNOME always has.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DISPLAY="${DISPLAY:-:0}"
unset WAYLAND_DISPLAY

# With xwayland-native-scaling GNOME advertises the DPI X apps must draw at
# in Xft.dpi (192 here); rofi's own detection lands on 96, i.e. half size.
dpi=$(xrdb -query 2>/dev/null | awk '/^Xft\.dpi:/ {print $2}')

# -normal-window: rofi normally maps an override-redirect window and grabs
# keyboard + pointer the X11 way. Mutter refuses X11 grabs from XWayland
# (org.gnome.mutter.wayland xwayland-allow-grabs=false), so that window drew
# but never received a key or a click. As a managed window GNOME focuses it
# like any app: typing, arrows, mouse and Escape all work.
BX_HOME="${BX_HOME:-$HOME/.bin}"
exec rofi -show drun -normal-window -config "$BX_HOME/config/rofi.rasi" -dpi "${dpi:-96}"
