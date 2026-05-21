#!/bin/bash
#
# claude-init.sh
# ─────────────────────────────────────────────────────────────────────────────
# Sets up Claude Code's status line on a fresh machine so every laptop you
# use shows the same prompt: model name, cwd, git branch, and token usage.
#
# Safe to run multiple times — skips any work that is already done.
#
# What it does:
#   1. Verifies python3 is installed (the status line is a Python script)
#   2. Creates ~/.claude/ if it doesn't exist
#   3. Symlinks ~/.claude/statusline.py → ~/.bin/dotFiles/claude/statusline.py
#      (so future edits in your .bin repo propagate via `git pull` alone)
#   4. Merges the statusLine block into ~/.claude/settings.json without
#      touching other keys like `model` or `theme`
#
# Usage:
#   bash claude-init.sh
#
# Rules:
#   - Never deletes anything; renames anything in the way to *.bak
#   - Logs every action to ~/.claude/claude-init.log
#   - Source of truth: ~/.bin/dotFiles/claude/statusline.py (git-tracked)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

H="$HOME"
SRC_DIR="$H/.bin/dotFiles/claude"
SRC_SCRIPT="$SRC_DIR/statusline.py"
CLAUDE_DIR="$H/.claude"
DEST_SCRIPT="$CLAUDE_DIR/statusline.py"
SETTINGS="$CLAUDE_DIR/settings.json"
LOG="$CLAUDE_DIR/claude-init.log"
CHANGED_COUNT=0

# ── Helpers ──────────────────────────────────────────────────
ts()   { date '+%Y-%m-%d %H:%M:%S'; }
log()  { echo "[$(ts)] $1" >> "$LOG"; }
ok()   { echo "  OK: $1"; }
skip() { echo "  --: $1"; }
warn() { echo "  WARNING: $1"; }

mark_changed() { (( CHANGED_COUNT++ )) || true; }

# ── Step 1: dependencies ─────────────────────────────────────
check_python() {
    echo "── Step 1: Dependencies ─────────────────────────────────"
    if command -v python3 >/dev/null 2>&1; then
        ok "python3 found: $(python3 --version 2>&1)"
    else
        warn "python3 not found — install it before re-running (apt install python3)"
        exit 1
    fi
    echo ""
}

# ── Step 2: ~/.claude/ directory ─────────────────────────────
ensure_claude_dir() {
    echo "── Step 2: ~/.claude/ directory ─────────────────────────"
    if [ -d "$CLAUDE_DIR" ]; then
        skip "$CLAUDE_DIR already exists"
    else
        mkdir -p "$CLAUDE_DIR"
        ok "Created $CLAUDE_DIR"
        mark_changed
    fi
    echo ""
}

# ── Step 3: statusline.py symlink ────────────────────────────
link_statusline() {
    echo "── Step 3: statusline.py symlink ────────────────────────"

    if [ ! -f "$SRC_SCRIPT" ]; then
        warn "Source script missing: $SRC_SCRIPT"
        warn "Restore your .bin repo first, then re-run."
        exit 1
    fi

    chmod +x "$SRC_SCRIPT" 2>/dev/null || true

    # Already the right symlink — nothing to do
    if [ -L "$DEST_SCRIPT" ] && [ "$(readlink "$DEST_SCRIPT")" = "$SRC_SCRIPT" ]; then
        skip "$DEST_SCRIPT already linked to $SRC_SCRIPT"
        echo ""
        return
    fi

    # Something else is in the way — back it up
    if [ -e "$DEST_SCRIPT" ] || [ -L "$DEST_SCRIPT" ]; then
        local backup="${DEST_SCRIPT}.bak.$(date '+%s')"
        mv "$DEST_SCRIPT" "$backup"
        ok "Backed up existing file → $backup"
        log "BACKED UP: $DEST_SCRIPT → $backup"
    fi

    ln -s "$SRC_SCRIPT" "$DEST_SCRIPT"
    ok "Symlinked $DEST_SCRIPT → $SRC_SCRIPT"
    log "LINKED: $DEST_SCRIPT → $SRC_SCRIPT"
    mark_changed
    echo ""
}

# ── Step 4: settings.json merge ──────────────────────────────
merge_settings() {
    echo "── Step 4: settings.json ────────────────────────────────"

    # Use python3 to read existing settings (or start with {}), set the
    # statusLine block, and write back — preserving every other key.
    # Compares before/after so we only report "changed" when it really changed.
    local result
    result=$(SETTINGS_PATH="$SETTINGS" python3 <<'PY'
import json, os, sys

path = os.environ["SETTINGS_PATH"]

if os.path.exists(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except (json.JSONDecodeError, ValueError):
        print("PARSE_ERROR")
        sys.exit(0)
else:
    data = {}

if not isinstance(data, dict):
    print("NOT_OBJECT")
    sys.exit(0)

desired = {
    "type": "command",
    "command": "~/.claude/statusline.py",
    "refreshInterval": 1,
}

before = json.dumps(data, sort_keys=True)
data["statusLine"] = desired
after = json.dumps(data, sort_keys=True)

if before == after:
    print("UNCHANGED")
    sys.exit(0)

# Back up the existing file before overwriting
if os.path.exists(path):
    import shutil, time
    backup = f"{path}.bak.{int(time.time())}"
    shutil.copy2(path, backup)
    print(f"BACKED_UP:{backup}")

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("WROTE")
PY
)

    case "$result" in
        UNCHANGED)
            skip "statusLine block already configured"
            ;;
        PARSE_ERROR)
            warn "$SETTINGS exists but is not valid JSON — fix or remove it, then re-run"
            exit 1
            ;;
        NOT_OBJECT)
            warn "$SETTINGS is valid JSON but not an object — fix or remove it, then re-run"
            exit 1
            ;;
        *)
            if [[ "$result" == *BACKED_UP:* ]]; then
                local backup="${result#*BACKED_UP:}"
                backup="${backup%%$'\n'*}"
                ok "Backed up settings → $backup"
                log "BACKED UP: $SETTINGS → $backup"
            fi
            ok "Wrote statusLine block into $SETTINGS"
            log "WROTE: statusLine block in $SETTINGS"
            mark_changed
            ;;
    esac
    echo ""
}

# ── Step 5: smoke test ───────────────────────────────────────
smoke_test() {
    echo "── Step 5: Smoke test ───────────────────────────────────"
    # Feed the statusline a minimal payload and check it prints something
    local out
    if out=$(printf '%s' '{"model":{"display_name":"sanity"},"cwd":"'"$H"'","context_window":{"total_input_tokens":1000,"used_percentage":1}}' \
             | python3 "$SRC_SCRIPT" 2>&1) && [ -n "$out" ]; then
        ok "statusline.py runs cleanly"
        echo "      sample → $out"
    else
        warn "statusline.py failed to run — output: $out"
    fi
    echo ""
}

# ── Main ─────────────────────────────────────────────────────
main() {
    check_python
    ensure_claude_dir

    log "══════════════════════════════════════════"
    log "claude-init.sh run at $(ts)"
    log "══════════════════════════════════════════"

    link_statusline
    merge_settings
    smoke_test

    log "══════════════════════════════════════════"
    log "Run complete. Items changed this run: $CHANGED_COUNT"
    log "══════════════════════════════════════════"

    if (( CHANGED_COUNT == 0 )); then
        echo "  Nothing to do — Claude status line is already set up."
    else
        echo "  Applied $CHANGED_COUNT change(s) to your Claude config."
        echo "  Full log: $LOG"
    fi
    echo ""
    echo "  Restart Claude Code (or open a new session) to see the new status line."
    echo ""
}

main
