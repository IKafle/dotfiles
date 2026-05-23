#!/usr/bin/env bash
# bx-purpose: render geekbar once and validate the output (smoke test)
set -euo pipefail

# Tmp files are top-level so the EXIT trap can see them after main()
# returns and the function's `local`s have gone out of scope. With
# `set -u`, referencing local vars in a trap fired at process exit
# blows up with "unbound variable".
OUT=""; STDERR=""; WIDGET_REPORT=""
cleanup() {
    rm -f "$OUT" "$STDERR" "$WIDGET_REPORT" 2>/dev/null || true
}
trap cleanup EXIT

main() {
    local plugin="$HOME/.bin/plugins/geekbar/geekbar.argos.sh"
    if [[ ! -x "$plugin" ]]; then
        printf '✘ %s not found or not executable\n' "$plugin" >&2
        exit 1
    fi

    local exit_code=0
    OUT=$(mktemp)
    STDERR=$(mktemp)
    WIDGET_REPORT=$(mktemp)

    # Don't let `set -e` abort on a non-zero plugin exit — we want to
    # report it as a diagnostic, not crash the test runner.
    if "$plugin" >"$OUT" 2>"$STDERR"; then
        exit_code=0
    else
        exit_code=$?
    fi

    printf '── BAR ─────────────────────────────────\n'
    head -n1 "$OUT"
    printf '\n── DROPDOWN ───────────────────────────\n'
    tail -n +2 "$OUT"
    printf '\n── DIAGNOSTICS ────────────────────────\n'

    local fails=0

    # 1. Plugin exited cleanly.
    if (( exit_code == 0 )); then
        printf '✓ plugin exit 0\n'
    else
        printf '✘ plugin exit %d\n' "$exit_code"
        fails=$(( fails + 1 ))
    fi

    # 2. First line has the font directive (bar label).
    if head -n1 "$OUT" | grep -q 'font="JetBrainsMono Nerd Font"'; then
        printf '✓ bar label has font directive\n'
    else
        printf '⚠ bar label missing font directive\n'
    fi

    # 3. Dropdown has a separator.
    if grep -q '^---$' "$OUT"; then
        printf '✓ dropdown separator present\n'
    else
        printf '⚠ dropdown separator not found\n'
    fi

    # 4. No stderr output.
    if [[ ! -s "$STDERR" ]]; then
        printf '✓ no stderr noise\n'
    else
        printf '⚠ stderr:\n'
        sed 's/^/    /' "$STDERR"
    fi

    # 5. Every enabled widget in BAR_WIDGETS has a callable bar function.
    # Use a tmp file (not a piped while-read) so the missing list survives
    # the subshell that sources the config + widgets.
    bash -c '
        # shellcheck disable=SC1091
        source "$HOME/.bin/plugins/geekbar/config.sh"
        for f in "$HOME/.bin/plugins/geekbar/widgets"/*.sh; do
            # shellcheck disable=SC1090
            source "$f"
        done
        for w in "${BAR_WIDGETS[@]}"; do
            if ! declare -F "widget_${w}_bar" >/dev/null; then
                printf "%s\n" "$w"
            fi
        done
    ' >"$WIDGET_REPORT"

    if [[ ! -s "$WIDGET_REPORT" ]]; then
        printf '✓ all BAR_WIDGETS have widget_<name>_bar functions\n'
    else
        local missing
        missing=$(tr '\n' ' ' < "$WIDGET_REPORT" | sed 's/ $//')
        printf '✘ missing widgets: %s\n' "$missing"
        fails=$(( fails + 1 ))
    fi

    printf '\n'
    if (( fails == 0 )); then
        printf '→ Smoke test passed.\n'
        return 0
    else
        printf '→ Smoke test FAILED (%d issues).\n' "$fails"
        return 1
    fi
}

main "$@"
