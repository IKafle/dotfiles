#!/bin/bash
# bx-purpose: launch rofi app menu under Wayland (bound to Super-d via xremap)
export WAYLAND_DISPLAY=$(ls /run/user/$(id -u)/wayland-* 2>/dev/null | head -1 | xargs basename)
export XDG_RUNTIME_DIR=/run/user/$(id -u)
/usr/local/bin/rofi -show drun
