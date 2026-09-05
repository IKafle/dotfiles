#!/usr/bin/env bash
# `bx install` owns ~/.bashrc: it reduces any existing file to the bx hook
# exactly once (keeping a backup) and is a no-op afterwards.
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib.sh"
BX="$HERE/../bx"

with_home() {  # $1 = initial bashrc content or NOFILE; runs bx install, echoes fake HOME
    local h; h=$(mktemp -d)
    mkdir -p "$h/.bin"; ln -s "$(cd "$HERE/.." && pwd)/lib" "$h/.bin/lib"
    [[ "$1" == NOFILE ]] || printf '%s\n' "$1" > "$h/.bashrc"
    HOME="$h" BX_HOME="$h/.bin" bash "$BX" install >/dev/null 2>&1
    printf '%s' "$h"
}

test_stock_bashrc_is_reduced_to_hook_with_backup() {
    local h; h=$(with_home $'# stock\nHISTSIZE=1000\nalias ll="ls -alF"')
    assert_eq "$(grep -c '' "$h/.bashrc")" "2"
    assert_contains "$(cat "$h/.bashrc")" ". ~/.bin/init.sh"
    assert_contains "$(cat "$h/.bashrc.pre-bx")" "HISTSIZE=1000"
    rm -rf "$h"
}

test_second_install_changes_nothing() {
    local h; h=$(with_home $'# stock\nexport FOO=1')
    local before; before=$(cat "$h/.bashrc")
    HOME="$h" BX_HOME="$h/.bin" bash "$BX" install >/dev/null 2>&1
    assert_eq "$(cat "$h/.bashrc")" "$before"
    assert_eq "$(ls "$h"/.bashrc.pre-bx* | wc -l)" "1"
    rm -rf "$h"
}

test_missing_bashrc_is_created_without_backup() {
    local h; h=$(with_home NOFILE)
    assert_contains "$(cat "$h/.bashrc")" ". ~/.bin/init.sh"
    assert_eq "$(ls "$h"/.bashrc.pre-bx* 2>/dev/null | wc -l)" "0"
    rm -rf "$h"
}

test_non_interactive_shell_loads_nothing() {
    local out
    out=$(bash -c '. "'"$HERE"'/../init.sh"; echo "${BX_MODULES_LOADED:-none}"' 2>&1)
    assert_eq "$out" "none"
}

run_tests
