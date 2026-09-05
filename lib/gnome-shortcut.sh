# shellcheck shell=bash
# lib/gnome-shortcut.sh — bind a key combo to a command via GNOME's own
# custom-keybinding schema. No keybinding daemon, works on Wayland, survives
# logout. Idempotent: prints "OK:" for each change and "--:" for each thing
# already in place; bx_shortcut_changed tells the caller whether anything moved.
#
#   . "$HOME/.bin/lib/gnome-shortcut.sh"
#   bx_shortcut_require "rofi-init"            # exit 3 no GNOME, 1 no session bus
#   bx_shortcut_bind "rofi launcher" "<Super>d" "$HOME/.bin/tools/rofi-launcher.sh"
#
# Any stock GNOME/mutter/shell binding that already uses the combo loses just
# that combo (its other combos stay), so the custom one actually fires.

_BX_SC_MK=org.gnome.settings-daemon.plugins.media-keys
_BX_SC_CK=$_BX_SC_MK.custom-keybinding
_BX_SC_BASE=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings
_BX_SC_CHANGED=0

_bx_sc_ok()   { printf '  OK: %s\n' "$1"; _BX_SC_CHANGED=$(( _BX_SC_CHANGED + 1 )); }
_bx_sc_skip() { printf '  --: %s\n' "$1"; }
bx_shortcut_changed() { (( _BX_SC_CHANGED > 0 )); }

# gsettings prints GVariant arrays as python-literal lists ("@as []" when empty).
_bx_sc_as_list() { python3 -c 'import ast,sys; v=sys.argv[1]; v=v.split(" ",1)[1] if v.startswith("@as ") else v; print("\n".join(ast.literal_eval(v)))' "$1"; }
_bx_sc_to_gv()   { python3 -c 'import sys; print(repr([l for l in sys.stdin.read().split("\n") if l]))'; }
_bx_sc_unq()     { local s=$1; s=${s#\'}; printf '%s' "${s%\'}"; }

bx_shortcut_require() {  # $1 = caller name for messages
    command -v gsettings >/dev/null || { echo "$1: gsettings not found — not a GNOME session"; exit 3; }
    gsettings get "$_BX_SC_MK" custom-keybindings >/dev/null 2>&1 \
        || { echo "$1: cannot reach the GNOME session bus (run from a terminal inside the desktop session)"; exit 1; }
}

# Remove $1 from every stock binding that lists it (wm, shell, mutter schemas).
_bx_sc_free_combo() {
    local binding=$1 schema line key cur
    for schema in org.gnome.desktop.wm.keybindings org.gnome.shell.keybindings org.gnome.mutter.keybindings; do
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            key=${line#"$schema" }; key=${key%% *}
            cur=$(gsettings get "$schema" "$key")
            if _bx_sc_as_list "$cur" 2>/dev/null | grep -qx "$binding"; then
                gsettings set "$schema" "$key" "$(_bx_sc_as_list "$cur" | grep -vx "$binding" | _bx_sc_to_gv)"
                _bx_sc_ok "removed $binding from $key"
            fi
        done < <(gsettings list-recursively "$schema" 2>/dev/null | grep -i "$binding'" || true)
    done
}

bx_shortcut_bind() {  # $1 = slot name, $2 = binding e.g. "<Super>d", $3 = command
    local name=$1 binding=$2 cmd=$3 paths target="" p n
    _bx_sc_free_combo "$binding"
    paths=$(_bx_sc_as_list "$(gsettings get "$_BX_SC_MK" custom-keybindings)")
    while IFS= read -r p; do
        [[ -n "$p" ]] || continue
        [[ "$(_bx_sc_unq "$(gsettings get "$_BX_SC_CK:$p" name)")" == "$name" ]] && { target=$p; break; }
    done <<< "$paths"
    if [[ -z "$target" ]]; then
        n=0; while grep -qx "$_BX_SC_BASE/custom$n/" <<< "$paths"; do n=$(( n + 1 )); done
        target="$_BX_SC_BASE/custom$n/"
        gsettings set "$_BX_SC_MK" custom-keybindings "$(printf '%s\n%s\n' "$paths" "$target" | _bx_sc_to_gv)"
        gsettings set "$_BX_SC_CK:$target" name "$name"
        _bx_sc_ok "allocated custom shortcut slot $target for '$name'"
    fi
    if [[ "$(_bx_sc_unq "$(gsettings get "$_BX_SC_CK:$target" binding)")" != "$binding" ]]; then
        gsettings set "$_BX_SC_CK:$target" binding "$binding"; _bx_sc_ok "$name: binding → $binding"
    else _bx_sc_skip "$name: binding already $binding"; fi
    if [[ "$(_bx_sc_unq "$(gsettings get "$_BX_SC_CK:$target" command)")" != "$cmd" ]]; then
        gsettings set "$_BX_SC_CK:$target" command "$cmd"; _bx_sc_ok "$name: command → $cmd"
    else _bx_sc_skip "$name: command already $cmd"; fi
}
