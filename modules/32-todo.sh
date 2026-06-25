# 32-todo.sh — bx module
# Sourced by ~/.bin/init.sh into every interactive bash.
# Enabled via:  bx enable todo
# Edit via:     bx edit todo
#
# bx integration point for the self-contained todo app at ~/todo. The app
# owns its data, git history and tests; this module just sources its shell
# integration so `today` / `td` / `tdone` / `tpush` and the first-terminal-
# of-day Today display load through bx — no ~/.bashrc edits (CLAUDE.md #6).

[[ -n "${_BX_MOD_todo_LOADED:-}" ]] && return 0
_BX_MOD_todo_LOADED=1

# Fail silently when the app isn't present, so a missing ~/todo never breaks
# shell startup. todo.sh fires its own daily-show hook only when interactive.
[[ -f "$HOME/todo/todo.sh" ]] && source "$HOME/todo/todo.sh"
