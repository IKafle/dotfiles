# bx — color helpers
# Sourced by init.sh, bx, and modules. Idempotent.

[[ -n "${_BX_COLOR_LOADED:-}" ]] && return 0
_BX_COLOR_LOADED=1

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    BX_C_RESET=$'\e[0m'
    BX_C_BOLD=$'\e[1m'
    BX_C_DIM=$'\e[2m'
    BX_C_RED=$'\e[31m'
    BX_C_GREEN=$'\e[32m'
    BX_C_YELLOW=$'\e[33m'
    BX_C_BLUE=$'\e[34m'
    BX_C_MAGENTA=$'\e[35m'
    BX_C_CYAN=$'\e[36m'
    BX_C_GRAY=$'\e[90m'
else
    BX_C_RESET=
    BX_C_BOLD=
    BX_C_DIM=
    BX_C_RED=
    BX_C_GREEN=
    BX_C_YELLOW=
    BX_C_BLUE=
    BX_C_MAGENTA=
    BX_C_CYAN=
    BX_C_GRAY=
fi
