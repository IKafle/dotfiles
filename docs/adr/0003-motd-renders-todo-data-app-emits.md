---
status: accepted
---

# MOTD renders the todo panel from data the app emits; the app never renders, MOTD never parses

The MOTD (`modules/80-motd.sh`, bx-owned) shows a todo panel beside the system
panel. The todo app (`~/todo`) is deliberately self-contained — it owns its
data, git history, and tests (see `modules/32-todo.sh`). To draw the panel we
split responsibility along that boundary: the app gains a data-emit command
(`today --data`-style) that prints Today's tasks plus the backlog and
done-today counts in a stable, greppable format, and MOTD owns *all*
presentation — the equal-halves split, the `│` divider, numbering, colours, and
the progress bar. MOTD never reads `todo.md`; the app never produces styled
output for the panel.

The boundary holds in both directions on purpose. Data extraction lives with
the data's owner, so a change to `todo.md`'s internal markdown only ripples
through the app's emit command, never silently breaking the MOTD. The
composited two-column visual lives in one place — next to the left column it
must align with — so the panel's UI/UX has a single home rather than being
split across two repos.

## Considered options

- **MOTD parses `todo.md` directly.** Rejected: couples bx to the app's
  internal file format. The app is explicitly a black box that exposes commands
  (`today`, `td`, `tdone`, `tpush`); reaching past that into its storage means a
  future format change inside `~/todo` breaks shell startup with no signal at
  the boundary.
- **The app renders the whole styled right column; MOTD pastes it beside the
  left.** Rejected: the two-column composition — measuring widths, placing the
  divider at `COLUMNS/2`, falling back to a stacked layout below ~135 cols —
  belongs to whoever owns the left column. Splitting that math across two
  codebases means neither side can change the layout alone, and the app would
  have to know MOTD's geometry to align.

## Consequences

The app carries a presentation-adjacent command (`today --data`) it would not
need on its own — but it emits *data*, not style, so it stays a data owner. The
same emit command also lets the app retire its standalone `_todo_daily_show`
print without losing the capability: MOTD now renders Today on every terminal,
and the app suppresses its own daily print via a `TODO_SUPPRESS_DAILY_SHOW`
opt-out that the `32-todo.sh` module sets (see ADR 0001/0002 for the
filesystem-and-lifecycle boundaries this extends).
