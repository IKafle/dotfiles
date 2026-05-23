[[ -n "${_BX_MOD_prompt_LOADED:-}" ]] && return 0
_BX_MOD_prompt_LOADED=1

export GIT_PS1_SHOWUNTRACKEDFILES=true
export GIT_PS1_SHOWCOLORHINTS=true
export GIT_PS1_SHOWDIRTYSTATE=true

# Source git's __git_ps1 helper if the system provides it.
for f in /usr/lib/git-core/git-sh-prompt /etc/bash_completion.d/git-prompt; do
    [[ -f "$f" ]] && . "$f" && break
done

# Load any extra completion scripts the user has dropped into ~/.bin/completions/
if [[ -d "$HOME/.bin/completions" ]]; then
    for f in "$HOME"/.bin/completions/*; do
        [[ -f "$f" ]] && . "$f"
    done
fi

# Append __git_ps1 to PROMPT_COMMAND without clobbering hooks that earlier
# modules (cmdlog, geekbar-track) prepended. PS1 must be set last, so this
# goes at the END of the chain.
if [[ ";${PROMPT_COMMAND:-};" != *__git_ps1* ]]; then
    PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}"'__git_ps1 "\u@\h:\w" "\\\$ "'
fi
export PROMPT_COMMAND
