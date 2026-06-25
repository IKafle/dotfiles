# tests/lib.sh — minimal dependency-free test harness (mirrors ~/todo/tests).
#
# Each test is a function named test_*. Define them, then call run_tests.
#
# Usage (from a test file):
#   source "$(dirname "$0")/lib.sh"
#   test_something() { assert_eq "a" "a"; }
#   run_tests

set -u

_TESTS_PASS=0
_TESTS_FAIL=0
_CUR_TEST=""

# Strip ANSI escape sequences so assertions match on visible text.
strip_ansi() {
    printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g'
}

fail() {
    _TESTS_FAIL=$((_TESTS_FAIL + 1))
    printf '  ✗ %s\n      %s\n' "$_CUR_TEST" "$*" >&2
    return 1
}

assert_eq() {
    if [ "$1" != "$2" ]; then
        fail "expected [$2] but got [$1]"
    fi
}

assert_contains() {
    case "$1" in
        *"$2"*) : ;;
        *) fail "expected output to contain [$2]; got [$1]" ;;
    esac
}

assert_not_contains() {
    case "$1" in
        *"$2"*) fail "expected output NOT to contain [$2]; got [$1]" ;;
        *) : ;;
    esac
}

run_tests() {
    local t
    for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
        _CUR_TEST="$t"
        local before_fail=$_TESTS_FAIL
        "$t"
        if [ "$_TESTS_FAIL" -eq "$before_fail" ]; then
            _TESTS_PASS=$((_TESTS_PASS + 1))
            printf '  ✓ %s\n' "$t"
        fi
    done
    printf '\n%d passed, %d failed\n' "$_TESTS_PASS" "$_TESTS_FAIL"
    [ "$_TESTS_FAIL" -eq 0 ]
}
