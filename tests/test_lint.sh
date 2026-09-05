#!/usr/bin/env bash
# `bx lint` must pass on the tree as committed and must catch the violations
# it claims to catch. Each case copies the tree, breaks one thing, expects failure.
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib.sh"
ROOT="$(cd "$HERE/.." && pwd)"

copy_tree() { local d; d=$(mktemp -d); cp -a "$ROOT/." "$d/"; rm -rf "$d/.git"; printf '%s' "$d"; }
lint_in()   { BX_HOME="$1" bash "$1/bx" lint 2>&1; }

test_clean_tree_passes() {
    local d; d=$(copy_tree)
    assert_contains "$(lint_in "$d")" "lint: contract holds"
    rm -rf "$d"
}

test_missing_guard_is_caught() {
    local d; d=$(copy_tree)
    sed -i '1,2d' "$d/modules/10-env.sh"
    assert_contains "$(lint_in "$d")" "L2"
    rm -rf "$d"
}

test_bad_module_prefix_is_caught() {
    local d; d=$(copy_tree)
    printf '[[ -n "${_BX_MOD_x_LOADED:-}" ]] && return 0\n_BX_MOD_x_LOADED=1\n' > "$d/modules/95-x.sh"
    assert_contains "$(lint_in "$d")" "L1"
    rm -rf "$d"
}

test_tool_without_headers_is_caught() {
    local d; d=$(copy_tree)
    printf '#!/usr/bin/env bash\necho hi\n' > "$d/tools/naked.sh"; chmod +x "$d/tools/naked.sh"
    local out; out=$(lint_in "$d")
    assert_contains "$out" "L5"
    assert_contains "$out" "L10"     # README does not mention it either
    rm -rf "$d"
}

test_installer_not_in_bootstrap_is_caught() {
    local d; d=$(copy_tree)
    printf '#!/usr/bin/env bash\n# bx-purpose: t\n# bx-tool-kind: installer\ntrue\n' > "$d/tools/orphan.sh"; chmod +x "$d/tools/orphan.sh"
    printf '| `orphan` | x |\n' >> "$d/README.md"
    assert_contains "$(lint_in "$d")" "L6"
    rm -rf "$d"
}

test_stray_file_in_enabled_is_caught() {
    local d; d=$(copy_tree)
    printf 'x\n' > "$d/enabled/99-stray.sh"
    assert_contains "$(lint_in "$d")" "L4"
    rm -rf "$d"
}

test_oversized_claude_md_is_caught() {
    local d; d=$(copy_tree)
    yes '- filler' | head -160 >> "$d/CLAUDE.md"
    assert_contains "$(lint_in "$d")" "L10"
    rm -rf "$d"
}

run_tests
