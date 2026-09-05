#!/usr/bin/env bash
# bx-purpose: bind Super-d to rofi-launcher via a GNOME custom shortcut (idempotent)
#
# Uses GNOME's own custom-keybinding schema — no keybinding daemon, works on
# Wayland, survives logout. Ubuntu binds <Super>d to show-desktop by default;
# that single combo is removed (the others stay). Exit 0 with "Nothing to do"
# when everything is already in place; exit 3 when not in a GNOME session.
set -uo pipefail

NAME="rofi launcher"
BINDING="<Super>d"
CMD="$HOME/.bin/tools/rofi-launcher.sh"
MK=org.gnome.settings-daemon.plugins.media-keys
CK=$MK.custom-keybinding
BASE=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings
CHANGED=0

ok()   { printf '  OK: %s\n' "$1"; CHANGED=$(( CHANGED + 1 )); }
skip() { printf '  --: %s\n' "$1"; }

# gsettings prints GVariant arrays as python-literal lists ("@as []" when empty).
as_list() { python3 -c 'import ast,sys; v=sys.argv[1]; v=v.split(" ",1)[1] if v.startswith("@as ") else v; print("\n".join(ast.literal_eval(v)))' "$1"; }
to_gv()   { python3 -c 'import sys; print(repr([l for l in sys.stdin.read().split("\n") if l]))'; }
unq()     { local s=$1; s=${s#\'}; printf '%s' "${s%\'}"; }

command -v gsettings >/dev/null || { echo "rofi-init: gsettings not found — not a GNOME session"; exit 3; }
gsettings get "$MK" custom-keybindings >/dev/null 2>&1 \
    || { echo "rofi-init: cannot reach the GNOME session bus (run from a terminal inside the desktop session)"; exit 1; }

command -v rofi >/dev/null || echo "  WARNING: rofi is not installed yet — bx run bootstrap installs it from config/packages"

# 1. free <Super>d from show-desktop, keep the other combos
cur=$(gsettings get org.gnome.desktop.wm.keybindings show-desktop)
if as_list "$cur" | grep -qx "$BINDING"; then
    gsettings set org.gnome.desktop.wm.keybindings show-desktop "$(as_list "$cur" | grep -vx "$BINDING" | to_gv)"
    ok "removed $BINDING from show-desktop"
else
    skip "show-desktop does not use $BINDING"
fi

# 2. find (or allocate) the custom slot named "$NAME"
paths=$(as_list "$(gsettings get "$MK" custom-keybindings)")
target=""
while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    [[ "$(unq "$(gsettings get "$CK:$p" name)")" == "$NAME" ]] && { target=$p; break; }
done <<< "$paths"
if [[ -z "$target" ]]; then
    n=0; while grep -qx "$BASE/custom$n/" <<< "$paths"; do n=$(( n + 1 )); done
    target="$BASE/custom$n/"
    gsettings set "$MK" custom-keybindings "$(printf '%s\n%s\n' "$paths" "$target" | to_gv)"
    gsettings set "$CK:$target" name "$NAME"
    ok "allocated custom shortcut slot $target"
fi

# 3. make the slot say exactly what we want
if [[ "$(unq "$(gsettings get "$CK:$target" binding)")" != "$BINDING" ]]; then
    gsettings set "$CK:$target" binding "$BINDING"; ok "binding → $BINDING"
else skip "binding already $BINDING"; fi
if [[ "$(unq "$(gsettings get "$CK:$target" command)")" != "$CMD" ]]; then
    gsettings set "$CK:$target" command "$CMD"; ok "command → $CMD"
else skip "command already $CMD"; fi

if (( CHANGED == 0 )); then echo "  Nothing to do — $BINDING already launches rofi."
else echo "  Applied $CHANGED change(s). Press $BINDING to launch rofi."; fi
