#!/usr/bin/env bash
# A dry run must never fail because of what a fresh machine lacks: it is the
# plan, and every phase has to reason from "not installed yet" without erroring.
# Runs against an empty HOME with a bare PATH, the way CI and a new laptop look.
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib.sh"
ROOT="$(cd "$HERE/.." && pwd)"

test_dry_run_on_empty_home_exits_clean() {
    local h out rc; h=$(mktemp -d)
    mkdir -p "$h/.bin"; cp -a "$ROOT/." "$h/.bin/"; rm -rf "$h/.bin/.git"
    out=$(HOME="$h" PATH=/usr/bin:/bin bash "$h/.bin/tools/bootstrap.sh" --dry-run --no-verify 2>&1); rc=$?
    assert_eq "$rc" "0"
    assert_contains "$out" "failed:  0"
    assert_not_contains "$out" "✘"
    rm -rf "$h"
}

test_dry_run_writes_nothing() {
    local h; h=$(mktemp -d)
    mkdir -p "$h/.bin"; cp -a "$ROOT/." "$h/.bin/"; rm -rf "$h/.bin/.git"
    HOME="$h" PATH=/usr/bin:/bin bash "$h/.bin/tools/bootstrap.sh" --dry-run --no-verify >/dev/null 2>&1
    [[ -e "$h/.bashrc" ]] && fail "dry run created ~/.bashrc"
    [[ -e "$h/.gitconfig" ]] && fail "dry run created ~/.gitconfig"
    [[ -e "$h/todo" ]] && fail "dry run cloned ~/todo"
    rm -rf "$h"
}

run_tests
