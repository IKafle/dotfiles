[[ -n "${_BX_MOD_shell_options_LOADED:-}" ]] && return 0
_BX_MOD_shell_options_LOADED=1

# What Ubuntu's stock ~/.bashrc used to do, so that file can be one line.

# ── History ──────────────────────────────────────────────────
HISTCONTROL=ignoreboth
HISTSIZE=1000
HISTFILESIZE=2000
shopt -s histappend

# ── Terminal ─────────────────────────────────────────────────
shopt -s checkwinsize

# ── less on binaries / archives ──────────────────────────────
[[ -x /usr/bin/lesspipe ]] && eval "$(SHELL=/bin/sh lesspipe)"

# ── ls colours ───────────────────────────────────────────────
if [[ -x /usr/bin/dircolors ]]; then
    if [[ -r ~/.dircolors ]]; then eval "$(dircolors -b ~/.dircolors)"; else eval "$(dircolors -b)"; fi
fi

# ── Programmable completion ──────────────────────────────────
if ! shopt -oq posix; then
    if [[ -f /usr/share/bash-completion/bash_completion ]]; then
        . /usr/share/bash-completion/bash_completion
    elif [[ -f /etc/bash_completion ]]; then
        . /etc/bash_completion
    fi
fi
