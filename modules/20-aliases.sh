[[ -n "${_BX_MOD_aliases_LOADED:-}" ]] && return 0
_BX_MOD_aliases_LOADED=1

# ── Navigation ───────────────────────────────────────────────
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias -- -='cd -'                        # go back to previous dir

# ── Listing ───────────────────────────────────────────────────
alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias cls='clear && ls'

# ── Safer defaults ────────────────────────────────────────────
alias cp='cp -i'                         # prompt before overwrite
alias mv='mv -i'                         # prompt before overwrite
alias mkdir='mkdir -pv'                  # make parents + verbose

# ── Readable system commands ──────────────────────────────────
alias df='df -h'
alias du='du -sh'
alias free='free -h'
alias psg='ps aux | grep -v grep | grep' # usage: psg python
alias ports='ss -tulpn'                  # listening ports
alias myip='curl -s ifconfig.me'         # external IP
alias iplocal='hostname -I | awk "{print \$1}"'

# ── Git ───────────────────────────────────────────────────────
# Convention: oh-my-zsh `git` plugin (curated subset). Functions that
# need args (gco, gcb, gcmsg, gca, gsync, gparent, …) live in
# 40-dev-tools.sh — Bash aliases can't take parameters.

alias g='git'

# status
alias gst='git status'                    # full status
alias gss='git status -sb'                # short branch view — quick glance

# add
alias ga='git add'
alias gaa='git add --all'
alias gap='git add --patch'               # interactive hunk picker

# branch
alias gb='git branch'
alias gba='git branch --all'
alias gbd='git branch --delete'
alias gbD='git branch --delete --force'

# diff
alias gd='git diff'
alias gdc='git diff --cached'             # staged diff
alias gds='git diff --staged'
alias gdw='git diff --word-diff'

# fetch
alias gf='git fetch'
alias gfa='git fetch --all --prune'       # full sync

# pull / push (oh-my-zsh: gl=pull, gp=push — flipped from previous convention)
alias gl='git pull'
alias glr='git pull --rebase'             # linear history
alias gp='git push'
alias gpf='git push --force-with-lease'   # safe force-push
alias gpff='git push --force'             # raw force — use with care

# log
alias glo='git log --oneline --decorate'
alias glog='git log --oneline --decorate --graph'
alias gloga='git log --oneline --decorate --graph --all'

# stash
alias gsta='git stash push'
alias gstp='git stash pop'
alias gstl='git stash list'
alias gsts='git stash show --text'
alias gstd='git stash drop'

# rebase
alias grb='git rebase'
alias grbi='git rebase --interactive'
alias grba='git rebase --abort'
alias grbc='git rebase --continue'

# merge
alias gm='git merge'
alias gma='git merge --abort'

# cherry-pick
alias gcp='git cherry-pick'
alias gcpa='git cherry-pick --abort'
alias gcpc='git cherry-pick --continue'

# reset / clean / worktree / remote / show
alias grh='git reset'
alias grhh='git reset --hard'
alias gclean='git clean -fd'
alias gwt='git worktree'
alias gr='git remote'
alias grv='git remote -v'
alias gsh='git show'

# ── Docker ────────────────────────────────────────────────────
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias dc='docker compose'
alias dcu='docker compose up -d'
alias dcd='docker compose down'
alias use-sandbox='use_sandbox'              # switch to sandbox (Docker Desktop)
alias use-docker='use_docker'                # switch to docker engine (main dev)
alias docker-status='docker_status'          # show docker context status
# dlogs() is defined in dev-tools (a function, not an alias, so it can show usage)

# ── Python ────────────────────────────────────────────────────
alias py='python3'
alias pip='pip3'

# ── Vault shortcuts ───────────────────────────────────────────
alias vault='cd ~/vault'
alias inbox='ls ~/vault/inbox'
alias dev='cd ~/vault/code'

# ── VPN (path updated to vault location) ─────────────────────
alias lisnepal='sudo openvpn --config ~/vault/work/vpn/lis-vpn-config.ovpn~'

# ── Edit modules quickly (uses $EDITOR, falls back to vim) ───
# These all live under ~/.bin/modules/ now. For arbitrary module editing
# (with auto-reload), use:  bx edit <name>
_dotedit() { ${EDITOR:-vim} "$1"; }
alias en='_dotedit ~/.bin/modules/10-env.sh'
alias al='_dotedit ~/.bin/modules/20-aliases.sh'
alias fun='_dotedit ~/.bin/modules/30-functions.sh'
alias con='_dotedit ~/.bin/modules/70-holidays.sh'
alias pr='_dotedit ~/.bin/modules/60-prompt.sh'

# ── Shell ─────────────────────────────────────────────────────
alias reload='source ~/.bashrc && echo "Shell reloaded."'
alias battery='upower -i $(upower -e | grep BAT) | grep -E "state|to full|to empty|percentage"'
alias settings='gnome-control-center'

# ── Virtual terminal switching ────────────────────────────────
alias tone='sudo chvt 1'
alias ttwo='sudo chvt 2'
alias tthree='sudo chvt 3'
alias tfour='sudo chvt 4'
alias tfive='sudo chvt 5'
alias tsix='sudo chvt 6'
alias tseven='sudo chvt 7'
