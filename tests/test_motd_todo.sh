#!/usr/bin/env bash
# Tests for the MOTD todo panel (Issue 0002). The panel consumes the
# `today --data` contract (ADR-0003) on stdin and renders presentation only —
# it never parses todo.md. We feed fixture data and assert on visible text.
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib.sh"
MOTD_SH="$HERE/../modules/80-motd.sh"
TAB="$(printf '\t')"

# Source the module non-interactively so the entry point does not fire; this
# defines __motd_todo_panel for direct testing.
source "$MOTD_SH"

# Render the panel from a here-string of `today --data` rows, ANSI-stripped.
render() { strip_ansi "$(printf '%s' "$1" | __motd_todo_panel)"; }
render_raw() { printf '%s' "$1" | __motd_todo_panel; }

data() { printf '%b' "$1"; }

test_today_tasks_render_as_numbered_priority_list() {
    local out; out="$(render "$(data "T\t0\twrite the panel\nT\t0\tship 0002\nB\t0\nD\t0")")"
    assert_contains "$out" "1  write the panel"
    assert_contains "$out" "2  ship 0002"
}

test_completed_tasks_collapse_to_check_and_skip_numbering() {
    local out; out="$(render "$(data "T\t0\tfirst\nT\t1\tdone one\nT\t0\tsecond\nB\t0\nD\t0")")"
    assert_contains "$out" "1  first"
    assert_contains "$out" "✓  done one"
    assert_contains "$out" "2  second"
    assert_not_contains "$out" "2  done one"
}

test_progress_bar_and_footer_render() {
    # 1 of 2 done → bar glyphs present, footer shows backlog + done-today.
    local out; out="$(render "$(data "T\t1\tdone\nT\t0\ttodo\nB\t3\nD\t5")")"
    assert_contains "$out" "█"
    assert_contains "$out" "░"
    assert_contains "$out" "1/2"
    assert_contains "$out" "backlog 3 · done today 5"
}

test_tags_are_dimmed_in_task_text() {
    local GR=$'\033[90m' R=$'\033[0m'
    local out; out="$(render_raw "$(data "T\t0\twrite +bx panel @code\nB\t0\nD\t0")")"
    # The +project / @context tokens are wrapped in the dim (gray) sequence.
    assert_contains "$out" "${GR}+bx${R}"
    assert_contains "$out" "${GR}@code${R}"
    # Body words are not dimmed.
    assert_contains "$out" "write "
}

test_list_caps_at_ten_with_overflow_line() {
    local rows="" i
    for i in $(seq 1 12); do rows+="T\t0\ttask $i\n"; done
    rows+="B\t0\nD\t0"
    local out; out="$(render "$(data "$rows")")"
    assert_contains "$out" "10  task 10"
    assert_contains "$out" "+2 more — run today"
    assert_not_contains "$out" "task 11"
    assert_not_contains "$out" "task 12"
}

test_empty_today_shows_no_plan_message() {
    local out; out="$(render "$(data "B\t4\nD\t0")")"
    assert_contains "$out" "no plan yet — run today"
    assert_not_contains "$out" "█"
}

test_all_done_shows_all_done_with_footer() {
    local out; out="$(render "$(data "T\t1\tone\nT\t1\ttwo\nB\t2\nD\t7")")"
    assert_contains "$out" "all done ✓"
    assert_contains "$out" "backlog 2 · done today 7"
}

run_tests
