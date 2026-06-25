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

# The MOTD panel (80-motd.sh) is now the single home of the Today display, so
# suppress the app's own first-of-day print to avoid a duplicate. Must be set
# before sourcing — todo.sh fires its daily-show hook at load time when
# interactive. The app keeps the capability when used without bx.
export TODO_SUPPRESS_DAILY_SHOW=1

# Fail silently when the app isn't present, so a missing ~/todo never breaks
# shell startup.
[[ -f "$HOME/todo/todo.sh" ]] && source "$HOME/todo/todo.sh"
