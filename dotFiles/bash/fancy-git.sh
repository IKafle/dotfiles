export GIT_PS1_SHOWUNTRACKEDFILES=true
export GIT_PS1_SHOWCOLORHINTS=true
export GIT_PS1_SHOWDIRTYSTATE=true

export PROMPT_COMMAND='__git_ps1 "\u@\h:\w" "\\\$ "'

for f in ~/.bin/dotFiles/bash/git-autocompletion/*; do
    . $f
done
