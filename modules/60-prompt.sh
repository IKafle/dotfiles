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

export PROMPT_COMMAND='__git_ps1 "\u@\h:\w" "\\\$ "'
