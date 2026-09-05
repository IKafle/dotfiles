#!/usr/bin/env bash
# bx-purpose: bind Super-d to rofi-launcher via a GNOME custom shortcut (idempotent)
# bx-tool-kind: installer
#
# Ubuntu binds <Super>d to show-desktop by default; lib/gnome-shortcut.sh frees
# that one combo (the others stay). Exit 0 with "Nothing to do" when everything
# is already in place; exit 3 when not in a GNOME session.
set -uo pipefail
BX_HOME="${BX_HOME:-$HOME/.bin}"
. "$BX_HOME/lib/gnome-shortcut.sh"
BINDING="<Super>d"
bx_shortcut_require rofi-init
command -v rofi >/dev/null || echo "  WARNING: rofi is not installed yet — bx run bootstrap installs it from config/packages"
bx_shortcut_bind "rofi launcher" "$BINDING" "$BX_HOME/tools/rofi-launcher.sh"
if bx_shortcut_changed; then echo "  Applied. Press $BINDING to launch rofi."
else echo "  Nothing to do — $BINDING already launches rofi."; fi
