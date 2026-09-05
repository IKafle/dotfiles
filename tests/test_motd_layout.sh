#!/usr/bin/env bash
# Tests for the MOTD grid layout. __motd_layout places N blocks side by side,
# left-anchored, with a dim `│` divider in each gutter and ┬/┴ junctions on the
# framing rules; __motd_stacked is the narrow fallback; __motd_full picks the
# tier (3 → 2 → stacked) from the live width. We assert on ANSI-stripped text.
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib.sh"
MOTD_SH="$HERE/../modules/80-motd.sh"

# Source the module non-interactively so the entry point does not fire.
source "$MOTD_SH"

count() { printf '%s\n' "$1" | grep -o -- "$2" | wc -l | tr -d ' '; }

# Visible column of the first `│` on every row that has one, joined by spaces.
divider_columns() {
    local l pre cols=""
    while IFS= read -r l; do
        case "$l" in *"│"*) pre="${l%%│*}"; cols+="${#pre} " ;; esac
    done <<< "$1"
    printf '%s' "${cols% }"
}

test_layout_places_blocks_left_divider_right() {
    local out; out="$(strip_ansi "$(__motd_layout 100 "hdr" "date" "left" "right")")"
    assert_contains "$out" "left"
    assert_contains "$out" "│"
    assert_contains "$out" "right"
    assert_contains "$out" "left  │  right"
}

test_layout_frames_grid_with_junction_rules() {
    local out; out="$(strip_ansi "$(__motd_layout 100 "hdr" "date" "a" "b" "c")")"
    # Two gutters → two junctions on the top rule and two on the bottom rule.
    assert_eq "$(count "$out" '┬')" "2"
    assert_eq "$(count "$out" '┴')" "2"
    assert_contains "$out" "hdr"
    assert_contains "$out" "date"
}

test_layout_aligns_divider_across_ragged_and_colored_lines() {
    local CY=$'\e[1;36m' R=$'\e[0m'
    local left; left="$(printf '%s\n%s' "ab" "${CY}abcdef${R}")"
    local out; out="$(strip_ansi "$(__motd_layout 100 "hdr" "date" "$left" "x
y")")"
    # Widest left line is 6 visible cols + 2-space gutter → divider at col 8 on both rows.
    assert_eq "$(divider_columns "$out")" "8 8"
}

test_layout_keeps_divider_full_height_when_right_is_shorter() {
    local left; left="$(printf '%s\n%s\n%s' "alpha" "beta" "gamma")"
    local out; out="$(strip_ansi "$(__motd_layout 100 "hdr" "date" "$left" "only")")"
    assert_contains "$out" "alpha"
    assert_contains "$out" "beta"
    assert_contains "$out" "gamma"
    assert_eq "$(count "$out" '│')" "3"
}

test_stacked_has_no_divider_and_keeps_block_order() {
    local out; out="$(strip_ansi "$(__motd_stacked 60 "hdr" "date" "first" "second")")"
    assert_not_contains "$out" "│"
    assert_contains "$out" "first"
    assert_contains "$out" "second"
    case "$out" in
        *first*second*) : ;;
        *) fail "blocks out of order: [$out]" ;;
    esac
}

# A deterministic `today` stub so __motd_full has a today card to place.
today() { printf 'T\t0\tship the grid\nT\t0\twrite docs\nB\t2\nD\t1\n'; }

test_full_renders_three_columns_when_wide() {
    local out; COLUMNS=400; out="$(strip_ansi "$(__motd_full)")"
    assert_eq "$(count "$out" '┬')" "2"
    assert_contains "$out" "▸  ship the grid"
    assert_contains "$out" "◆ today"
    assert_contains "$out" "◆ shortcuts"
    # The vitals block is intact alongside: its first visible line survives.
    local v1; v1="$(strip_ansi "$(__motd_vitals)" | sed -n '1p' | sed 's/[[:space:]]*$//')"
    assert_contains "$out" "$v1"
}

test_full_drops_to_two_columns_at_mid_width() {
    local vitals shorts todo w1 w2 w3
    vitals="$(__motd_vitals)"; shorts="$(__motd_shortcuts)"
    todo="$(today --data | __motd_todo_panel)"
    w1=$(__motd_blockwidth "$vitals"); w2=$(__motd_blockwidth "$todo"); w3=$(__motd_blockwidth "$shorts")
    # One column short of the three-column threshold.
    local out; COLUMNS=$(( w1 + w2 + w3 + 2 * __MOTD_GUTTER + 3 )); out="$(strip_ansi "$(__motd_full)")"
    assert_eq "$(count "$out" '┬')" "1"
    assert_contains "$out" "▸  ship the grid"
}

test_full_falls_back_to_stacked_when_narrow() {
    local out; COLUMNS=40; out="$(strip_ansi "$(__motd_full)")"
    assert_not_contains "$out" "│"
    assert_contains "$out" "▸  ship the grid"
    assert_contains "$out" "◆ shortcuts"
}

run_tests
