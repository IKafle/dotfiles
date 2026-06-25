#!/usr/bin/env bash
# Tests for the MOTD two-column layout (Issue 0003). The compositor places the
# (untouched) system panel in the left half and the todo panel in the right
# half with a `│` divider at COLUMNS/2; below the threshold it falls back to the
# stacked layout from 0002. We assert on ANSI-stripped visible text.
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib.sh"
MOTD_SH="$HERE/../modules/80-motd.sh"

# Source the module non-interactively so the entry point does not fire.
source "$MOTD_SH"

test_compose_places_left_divider_right_on_one_line() {
    local out; out="$(strip_ansi "$(__motd_compose "left" "right" 40)")"
    assert_contains "$out" "left"
    assert_contains "$out" "│"
    assert_contains "$out" "right"
    # All three sit on a single composed line.
    assert_contains "$out" "│ right"
}

test_compose_aligns_divider_across_ragged_and_colored_lines() {
    local CY=$'\033[1;36m' R=$'\033[0m'
    # Left lines differ in both visible length and ANSI content.
    local left; left="$(printf '%s\n%s' "ab" "${CY}abcdef${R}")"
    local out; out="$(strip_ansi "$(__motd_compose "$left" "x
y" 40)")"
    # The divider must sit at the same visible column on every line.
    local col1 col2 l
    while IFS= read -r l; do
        case "$l" in
            *"│"*) col1="${l%%│*}"; break ;;
        esac
    done <<< "$out"
    local seen=0
    while IFS= read -r l; do
        case "$l" in
            *"│"*)
                seen=$(( seen + 1 ))
                if (( seen == 2 )); then col2="${l%%│*}"; fi
                ;;
        esac
    done <<< "$out"
    assert_eq "${#col1}" "${#col2}"
    # COLUMNS/2 = 20, so the divider prefix is 20 visible columns wide.
    assert_eq "${#col1}" "20"
}

test_compose_keeps_left_lines_when_right_is_shorter() {
    local left; left="$(printf '%s\n%s\n%s' "alpha" "beta" "gamma")"
    local out; out="$(strip_ansi "$(__motd_compose "$left" "only" 40)")"
    assert_contains "$out" "alpha"
    assert_contains "$out" "beta"
    assert_contains "$out" "gamma"
    # The divider continues down the full height of the left panel.
    assert_eq "$(printf '%s' "$out" | grep -c '│')" "3"
}

# A deterministic `today` stub so __motd_full has a todo panel to place.
today() { printf 'T\t0\tship 0003\nT\t0\twrite docs\nB\t2\nD\t1\n'; }

test_full_renders_side_by_side_when_wide() {
    local out; COLUMNS=160; out="$(strip_ansi "$(__motd_full)")"
    assert_contains "$out" "│"
    assert_contains "$out" "ship 0003"
    # System panel is intact alongside it.
    assert_contains "$out" "kernel"
    assert_contains "$out" "disk"
}

test_full_falls_back_to_stacked_when_narrow() {
    local out; COLUMNS=80; out="$(strip_ansi "$(__motd_full)")"
    assert_not_contains "$out" "│"
    # Todo still renders, stacked below the system panel.
    assert_contains "$out" "ship 0003"
    assert_contains "$out" "kernel"
}

run_tests
