# bx — logging helpers
# All output goes to stderr so it never pollutes function returns.

[[ -n "${_BX_LOG_LOADED:-}" ]] && return 0
_BX_LOG_LOADED=1

# shellcheck source=color.sh
. "${BX_LIB:-$HOME/.bin/lib}/color.sh"

bx_info()    { printf '%s%s%s\n' "${BX_C_CYAN}"   "→ $*" "${BX_C_RESET}" >&2; }
bx_ok()      { printf '%s%s%s\n' "${BX_C_GREEN}"  "✔ $*" "${BX_C_RESET}" >&2; }
bx_warn()    { printf '%s%s%s\n' "${BX_C_YELLOW}" "⚠ $*" "${BX_C_RESET}" >&2; }
bx_err()     { printf '%s%s%s\n' "${BX_C_RED}"    "✘ $*" "${BX_C_RESET}" >&2; }
bx_dim()     { printf '%s%s%s\n' "${BX_C_GRAY}"   "$*"   "${BX_C_RESET}" >&2; }

# Print "label: value" with aligned label column. Used by bx status / doctor.
bx_kv() {
    local label=$1 value=$2
    printf '%s%-18s%s %s\n' "${BX_C_GRAY}" "$label" "${BX_C_RESET}" "$value" >&2
}
