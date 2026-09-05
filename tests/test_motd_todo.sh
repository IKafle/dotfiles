#!/usr/bin/env bash
# Tests for the MOTD today card. The card consumes the `today --data` contract
# (ADR-0003) on stdin and renders presentation only — it never parses todo.md.
# We feed fixture rows and assert on visible text.
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib.sh"
MOTD_SH="$HERE/../modules/80-motd.sh"

# Source the module non-interactively so the entry point does not fire; this
# defines __motd_todo_panel for direct testing.
source "$MOTD_SH"

render()     { strip_ansi "$(printf '%s' "$1" | __motd_todo_panel)"; }
render_raw() { printf '%s' "$1" | __motd_todo_panel; }
data()       { printf '%b' "$1"; }

test_header_shows_pending_count() {
    local out; out="$(render "$(data "T\t0\twrite the panel\nT\t0\tship it\nB\t0\nD\t0")")"
    assert_contains "$out" "◆ today · 2 left"
}

test_first_pending_is_focus_rest_are_dots() {
    local out; out="$(render "$(data "T\t0\twrite the panel\nT\t0\tship it\nB\t0\nD\t0")")"
    assert_contains "$out" "▸  write the panel"
    assert_contains "$out" "·  ship it"
    assert_not_contains "$out" "▸  ship it"
}

test_completed_tasks_render_as_check_below_pending() {
    local out; out="$(render "$(data "T\t0\tfirst\nT\t1\tdone one\nT\t0\tsecond\nB\t0\nD\t0")")"
    assert_contains "$out" "▸  first"
    assert_contains "$out" "·  second"
    assert_contains "$out" "✓  done one"
    assert_not_contains "$out" "·  done one"
    assert_contains "$out" "◆ today · 2 left"
}

test_progress_bar_and_footer_render() {
    # 1 of 2 done → bar glyphs present, footer shows backlog + done-today.
    local out; out="$(render "$(data "T\t1\tdone\nT\t0\ttodo\nB\t3\nD\t5")")"
    assert_contains "$out" "█"
    assert_contains "$out" "░"
    assert_contains "$out" " 50%"
    assert_contains "$out" "1/2"
    assert_contains "$out" "backlog 3"
    assert_contains "$out" "done today 5"
}

test_tags_are_colored_in_task_text() {
    local CN=$'\e[36m' GR=$'\e[90m' R=$'\e[0m'
    local out; out="$(render_raw "$(data "T\t0\twrite +bx panel @code\nB\t0\nD\t0")")"
    assert_contains "$out" "${CN}+bx${R}"
    assert_contains "$out" "${GR}@code${R}"
    assert_contains "$out" "write "
}

test_pending_caps_at_five_with_overflow_line() {
    local rows="" i
    for i in $(seq 1 7); do rows+="T\t0\ttask $i\n"; done
    rows+="B\t0\nD\t0"
    local out; out="$(render "$(data "$rows")")"
    assert_contains "$out" "·  task 5"
    assert_contains "$out" "+2 more — run today"
    assert_not_contains "$out" "task 6"
    assert_not_contains "$out" "task 7"
}

test_done_caps_at_three_with_overflow_line() {
    local rows="" i
    for i in $(seq 1 5); do rows+="T\t1\tdone $i\n"; done
    rows+="T\t0\tpending\nB\t0\nD\t0"
    local out; out="$(render "$(data "$rows")")"
    assert_contains "$out" "✓  done 3"
    assert_contains "$out" "+2 more done"
    assert_not_contains "$out" "done 4"
}

test_empty_today_shows_no_plan_message() {
    local out; out="$(render "$(data "B\t4\nD\t0")")"
    assert_contains "$out" "no plan yet — run today"
    assert_not_contains "$out" "█"
    assert_not_contains "$out" "left"
}

test_all_done_shows_badge_and_footer() {
    local out; out="$(render "$(data "T\t1\tone\nT\t1\ttwo\nB\t2\nD\t7")")"
    assert_contains "$out" "all done ✓"
    assert_contains "$out" "100%"
    assert_contains "$out" "backlog 2"
    assert_contains "$out" "done today 7"
    assert_not_contains "$out" "▸"
}

run_tests
