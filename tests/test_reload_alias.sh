#!/usr/bin/env bash
# The `reload` alias must clear the PID-scoped init guard before re-sourcing,
# otherwise init.sh short-circuits (init.sh:21) and reload is a silent no-op in
# the current shell — module edits never take effect without a new terminal.
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib.sh"
ALIASES_SH="$HERE/../modules/20-aliases.sh"

# Source the module fresh (bypass its load guard) and capture the alias body.
reload_body() {
    bash -c '
        unset _BX_MOD_ALIASES_LOADED
        source "$1" >/dev/null 2>&1
        alias reload 2>/dev/null
    ' _ "$ALIASES_SH"
}

test_reload_alias_clears_init_guard() {
    local body; body="$(reload_body)"
    assert_contains "$body" "_BX_INIT_PID"
}

test_reload_alias_still_sources_bashrc() {
    local body; body="$(reload_body)"
    assert_contains "$body" "source ~/.bashrc"
}

run_tests
