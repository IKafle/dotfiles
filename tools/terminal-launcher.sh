#!/usr/bin/env bash
# bx-purpose: open a new terminal window (Super-Enter, bound by terminal-init)
# bx-tool-kind: runtime
# Resolves the terminal at run time so the same binding works on any machine:
# the desktop's chosen terminal (xdg-terminal-exec → Ptyxis on Ubuntu 26.04),
# then the usual GNOME ones, then the Debian alternative.
# --print: show what would run, without opening anything.
for t in xdg-terminal-exec ptyxis gnome-terminal kgx x-terminal-emulator; do
    if command -v "$t" >/dev/null 2>&1; then
        [[ "${1:-}" == --print ]] && { echo "$t"; exit 0; }
        exec "$t"
    fi
done
echo "terminal-launcher: no terminal emulator found" >&2
exit 1
