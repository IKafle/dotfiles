# ~/.bin/init.sh — bx master loader
#
# Sourced from ~/.bashrc. Sources every file in ~/.bin/enabled/ in lexical
# order. Each enabled/ entry is a symlink into ~/.bin/modules/ (managed by
# the `bx` CLI).
#
# State exported into your shell:
#   BX_VERSION          version string (semver)
#   BX_HOME             absolute path to this tree
#   BX_LOADED_AT        epoch seconds the load completed
#   BX_MODULES_LOADED   count of modules sourced successfully this shell
#   BX_MODULES_FAILED   comma-separated list of modules that failed (empty on success)
#
# Source guard prevents double-loading WITHIN the same bash process. We use
# $BASHPID (not an exported var) so the guard does not leak into child shells
# — every new interactive bash from the desktop session must run modules from
# scratch, otherwise its motd / functions / aliases never get set up.
# To re-source on demand in the same shell, run `bx reload`.

# ── Source guard ──────────────────────────────────────────────────
[[ "${_BX_INIT_PID:-}" == "$BASHPID" ]] && return 0

# ── Shell guard ───────────────────────────────────────────────────
# We use bash arrays, [[ ]], $BASH_SOURCE. Bail cleanly on non-bash.
if [ -z "${BASH_VERSION:-}" ]; then
    echo "bx: requires bash (current shell is not bash) — skipping" >&2
    return 0 2>/dev/null || exit 0
fi

# ── Constants ─────────────────────────────────────────────────────
# _BX_INIT_PID is intentionally NOT exported — see source guard above.
_BX_INIT_PID=$BASHPID
export BX_VERSION="1.0.0"
export BX_HOME="${BX_HOME:-$HOME/.bin}"
export BX_LIB="$BX_HOME/lib"

# ── Shared helpers (silent on success) ────────────────────────────
if [[ -f "$BX_LIB/color.sh" ]]; then
    . "$BX_LIB/color.sh"
fi
if [[ -f "$BX_LIB/log.sh" ]]; then
    . "$BX_LIB/log.sh"
fi

# ── Put bx on PATH (idempotent) ───────────────────────────────────
case ":$PATH:" in
    *":$BX_HOME:"*) ;;
    *) export PATH="$BX_HOME:$PATH" ;;
esac

# Clear any per-module load guards from a previous source so a re-source
# (e.g. `bx reload`) actually re-loads the modules. The BX_VERSION guard
# above means we only get here on a fresh-or-explicit load.
for _bx_guard in $(compgen -v _BX_MOD_ 2>/dev/null); do
    unset "$_bx_guard"
done
unset _bx_guard

# ── Source every enabled module ───────────────────────────────────
BX_MODULES_LOADED=0
BX_MODULES_FAILED=""
_bx_failed_arr=()

_bx_enabled_dir="$BX_HOME/enabled"

if [[ ! -d "$_bx_enabled_dir" ]]; then
    # Fresh install with no enabled/ dir yet — soft-fail.
    printf '\033[33m⚠ bx: %s does not exist — nothing to load\033[0m\n' "$_bx_enabled_dir" >&2
else
    # Sorted lexicographically by filename. Symlinks are followed.
    for _bx_link in "$_bx_enabled_dir"/*.sh; do
        # No-glob case: if enabled/ is empty, the literal pattern remains.
        [[ -e "$_bx_link" ]] || continue

        # Detect broken symlink early.
        if [[ -L "$_bx_link" && ! -e "$_bx_link" ]]; then
            _bx_failed_arr+=("$(basename "$_bx_link") (broken symlink)")
            continue
        fi

        # Source the module. Capture failure so one broken module does not
        # poison the whole shell.
        if ! . "$_bx_link" 2>/tmp/.bx-load-err.$$; then
            _bx_failed_arr+=("$(basename "$_bx_link")")
            # Print the error inline so the user can see what broke.
            if [[ -s /tmp/.bx-load-err.$$ ]]; then
                printf '\033[33m⚠ bx: error loading %s\033[0m\n' "$(basename "$_bx_link")" >&2
                sed 's/^/    /' /tmp/.bx-load-err.$$ >&2
            fi
        else
            BX_MODULES_LOADED=$(( BX_MODULES_LOADED + 1 ))
        fi
        rm -f /tmp/.bx-load-err.$$
    done
    unset _bx_link
fi

# Pack the failed list into a comma-separated string for the motd module.
if (( ${#_bx_failed_arr[@]} > 0 )); then
    BX_MODULES_FAILED=$(IFS=,; echo "${_bx_failed_arr[*]}")
fi
unset _bx_failed_arr _bx_enabled_dir

export BX_MODULES_LOADED BX_MODULES_FAILED
export BX_LOADED_AT=$EPOCHSECONDS
