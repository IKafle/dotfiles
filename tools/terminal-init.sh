#!/usr/bin/env bash
# bx-purpose: bind Super-Enter to terminal-launcher via a GNOME custom shortcut (idempotent)
# bx-tool-kind: installer
#
# GNOME ships no terminal shortcut on Wayland (Ubuntu's Ctrl-Alt-T is a custom
# one too). Exit 0 with "Nothing to do" when in place; exit 3 outside GNOME.
set -uo pipefail
BX_HOME="${BX_HOME:-$HOME/.bin}"
. "$BX_HOME/lib/gnome-shortcut.sh"
BINDING="<Super>Return"
bx_shortcut_require terminal-init
bx_shortcut_bind "terminal" "$BINDING" "$BX_HOME/tools/terminal-launcher.sh"
if bx_shortcut_changed; then echo "  Applied. Press $BINDING to open a terminal."
else echo "  Nothing to do — $BINDING already opens a terminal."; fi
