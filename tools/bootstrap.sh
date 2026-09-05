#!/usr/bin/env bash
# bx-purpose: fresh-machine entrypoint — relocate to ~/.bin, wire bashrc, install deps, verify (idempotent)
#
# Usage:
#   git clone git@github.com:IKafle/dotfiles.git && bash dotfiles/tools/bootstrap.sh [flags]
#   bx run bootstrap [flags]            # re-run any time; every step is a no-op when already done
#
# Flags:
#   --todo-repo <url>   todo app repo to clone to ~/todo (default: BX_TODO_REPO or git@github.com:IKafle/todo.git)
#   --git-name <name>   global git identity to enforce (default: BX_GIT_NAME or "ishwor kafle")
#   --git-email <addr>  ... and its email (default: BX_GIT_EMAIL or hello.ishworkafle@gmail.com)
#   --no-apt            skip the apt package step
#   --no-gh             skip GitHub CLI install
#   --no-claude         skip Claude Code CLI install + status-line setup
#   --no-docker         skip docker-init (Docker's apt repo, engine + compose)
#   --no-geekbar        skip the Argos GNOME extension + geekbar plugin
#   --vault             run vault-init (creates ~/vault AND sweeps loose files from ~ into it)
#   --no-verify         skip doctor/selftest/tests at the end
#   --dry-run           print what would happen; change nothing
#
# Exit: 0 all done, 1 a required step failed, 2 bad usage

set -uo pipefail

TARGET="$HOME/.bin"
SELF=$(readlink -f "${BASH_SOURCE[0]}")
ROOT=$(dirname "$(dirname "$SELF")")

DRY_RUN=0
WITH_DOCKER=1 WITH_GEEKBAR=1 WITH_VAULT=0
SKIP_APT=0 SKIP_GH=0 SKIP_CLAUDE=0 SKIP_VERIFY=0
TODO_REPO="${BX_TODO_REPO:-git@github.com:IKafle/todo.git}"
GIT_NAME="${BX_GIT_NAME:-ishwor kafle}"
GIT_EMAIL="${BX_GIT_EMAIL:-hello.ishworkafle@gmail.com}"
ARGOS_UUID="argos@pew.worldwidemann.com"

# Every external command the modules, plugins and tools call, mapped to its
# Ubuntu package. Cloud CLIs (aws/gcloud/az/kubectl) and language version
# managers are deliberately absent: they are project tooling, not harness deps.
APT_PACKAGES=(
    # base / shell
    curl wget gnupg ca-certificates openssh-client gawk bc jq zip unzip p7zip-full
    python3 vim emacs fonts-jetbrains-mono
    # system / hardware
    iproute2 lm-sensors htop iotop ncdu lsof upower cpu-checker
    # network
    network-manager wireguard-tools wireless-tools iw traceroute bmon nload
    # desktop
    libnotify-bin xdg-utils wl-clipboard xclip pulseaudio-utils cowsay
)

FAILED=() SKIPPED=() DONE=()

# ── Output ──────────────────────────────────────────────────────
# lib/ is sourced from the checkout we're running from, not ~/.bin, because
# ~/.bin may not exist yet.
BX_LIB="$ROOT/lib"
if [[ -f "$BX_LIB/log.sh" ]]; then
    . "$BX_LIB/log.sh"
else
    bx_info() { echo "→ $*" >&2; }; bx_ok() { echo "✔ $*" >&2; }
    bx_warn() { echo "⚠ $*" >&2; }; bx_err() { echo "✘ $*" >&2; }
    bx_dim()  { echo "$*" >&2; }
fi

phase() { printf '\n%s── %s ──%s\n' "${BX_C_BOLD:-}" "$*" "${BX_C_RESET:-}" >&2; }
done_() {
    if (( DRY_RUN )); then bx_dim "  [dry-run] would: $1"; return 0; fi
    DONE+=("$1"); bx_ok "$1"
}
skip()   { SKIPPED+=("$1"); bx_dim "  skip: $1"; }
failed() { FAILED+=("$1");  bx_err "$1"; }

run() {
    if (( DRY_RUN )); then
        bx_dim "  [dry-run] $*"
        return 0
    fi
    "$@"
}

usage() { sed -n '3,20p' "$SELF" | sed 's/^# \{0,1\}//'; }

parse_args() {
    while (( $# )); do
        case "$1" in
            --todo-repo)   [[ -n "${2:-}" ]] || { bx_err "--todo-repo needs a url"; exit 2; }
                           TODO_REPO=$2; shift ;;
            --todo-repo=*) TODO_REPO=${1#*=} ;;
            --git-name)    [[ -n "${2:-}" ]] || { bx_err "--git-name needs a value"; exit 2; }
                           GIT_NAME=$2; shift ;;
            --git-name=*)  GIT_NAME=${1#*=} ;;
            --git-email)   [[ -n "${2:-}" ]] || { bx_err "--git-email needs a value"; exit 2; }
                           GIT_EMAIL=$2; shift ;;
            --git-email=*) GIT_EMAIL=${1#*=} ;;
            --no-docker)   WITH_DOCKER=0 ;;
            --no-geekbar)  WITH_GEEKBAR=0 ;;
            --vault)       WITH_VAULT=1 ;;
            --no-apt)      SKIP_APT=1 ;;
            --no-gh)       SKIP_GH=1 ;;
            --no-claude)   SKIP_CLAUDE=1 ;;
            --no-verify)   SKIP_VERIFY=1 ;;
            --dry-run)     DRY_RUN=1 ;;
            -h|--help)     usage; exit 0 ;;
            *)             bx_err "unknown flag: $1"; usage >&2; exit 2 ;;
        esac
        shift
    done
}

# ── Phase 0: pre-flight ─────────────────────────────────────────
preflight() {
    phase "pre-flight"
    if (( EUID == 0 )); then
        bx_err "run as your normal user, not root — sudo is requested only where needed"
        exit 1
    fi
    if (( BASH_VERSINFO[0] < 5 )); then
        bx_err "bash 5+ required (have $BASH_VERSION)"
        exit 1
    fi
    local missing=() c
    for c in git curl; do command -v "$c" >/dev/null || missing+=("$c"); done
    if (( ${#missing[@]} )); then
        bx_err "missing required commands: ${missing[*]} — install with: sudo apt install ${missing[*]}"
        exit 1
    fi
    if [[ ! -f "$ROOT/init.sh" || ! -x "$ROOT/bx" ]]; then
        bx_err "$ROOT does not look like the bx tree (no init.sh / bx)"
        exit 1
    fi
    bx_ok "checkout: $ROOT"
    (( DRY_RUN )) && bx_warn "dry-run: no changes will be made"
    return 0
}

# ── Phase 1: put the tree at ~/.bin ─────────────────────────────
same_repo() {
    local a=$1 b=$2 ra rb
    ra=$(git -C "$a" config --get remote.origin.url 2>/dev/null) || return 1
    rb=$(git -C "$b" config --get remote.origin.url 2>/dev/null) || return 1
    [[ -n "$ra" && "$ra" == "$rb" ]]
}

relocate() {
    phase "location"
    if [[ "$ROOT" == "$TARGET" ]]; then
        skip "already at $TARGET"
        return 0
    fi

    if [[ -e "$TARGET" || -L "$TARGET" ]]; then
        if [[ -d "$TARGET/.git" ]] && same_repo "$ROOT" "$TARGET"; then
            bx_warn "$TARGET already holds this repo — using it and leaving $ROOT untouched"
            reexec_from_target
        fi
        local bak="$TARGET.bak.$(date +%Y%m%d%H%M%S)"
        bx_warn "$TARGET exists and is not this repo — moving it to $bak"
        run mv "$TARGET" "$bak" || { failed "back up $TARGET"; exit 1; }
    fi

    if [[ -d "$HOME/bin" ]]; then
        bx_warn "~/bin exists — the bx contract says automation belongs in ~/.bin; nothing was touched"
    fi

    bx_info "moving $ROOT → $TARGET"
    run mv "$ROOT" "$TARGET" || { failed "move to $TARGET"; exit 1; }
    done_ "tree relocated to $TARGET"
    reexec_from_target
}

# The rest of the run must execute from ~/.bin so every hardcoded path in bx,
# init.sh and the tools resolves. Re-exec the moved copy of this script.
reexec_from_target() {
    if (( DRY_RUN )); then
        bx_dim "  [dry-run] would re-exec from $TARGET/tools/bootstrap.sh"
        ROOT=$TARGET
        return 0
    fi
    [[ -n "${BX_BOOTSTRAP_REEXEC:-}" ]] && { bx_err "re-exec loop detected"; exit 1; }
    export BX_BOOTSTRAP_REEXEC=1
    cd "$HOME" || exit 1
    exec bash "$TARGET/tools/bootstrap.sh" "${ORIG_ARGS[@]}"
}

# ── Phase 2: shell wiring ───────────────────────────────────────
wire_shell() {
    phase "shell"
    export BX_HOME="$TARGET"
    if grep -Eq "(\\\$HOME|~|$HOME)/\.bin/init\.sh" "$HOME/.bashrc" 2>/dev/null; then
        skip "~/.bashrc already sources init.sh"
    else
        run "$TARGET/bx" install >/dev/null 2>&1 && done_ "~/.bashrc sources ~/.bin/init.sh" \
            || failed "bx install"
    fi
    [[ -x "$TARGET/bx" ]] || run chmod +x "$TARGET/bx"
    run chmod +x "$TARGET"/tools/*.sh 2>/dev/null
    return 0
}

# ── Phase 2b: git identity ──────────────────────────────────────
# bx is the source of truth for the global identity: whatever is there is
# replaced by the configured values (defaults above, or --git-name/--git-email).
git_identity() {
    phase "git identity"
    local cur_name cur_email
    cur_name=$(git config --global --get user.name 2>/dev/null || true)
    cur_email=$(git config --global --get user.email 2>/dev/null || true)
    if [[ "$cur_name" == "$GIT_NAME" && "$cur_email" == "$GIT_EMAIL" ]]; then
        skip "global identity already $GIT_NAME <$GIT_EMAIL>"
        return 0
    fi
    [[ -n "$cur_name$cur_email" ]] && bx_warn "replacing global identity ${cur_name:-?} <${cur_email:-?}>"
    run git config --global user.name  "$GIT_NAME"  || { failed "git config user.name"; return 1; }
    run git config --global user.email "$GIT_EMAIL" || { failed "git config user.email"; return 1; }
    done_ "global git identity: $GIT_NAME <$GIT_EMAIL>"
}

# ── Phase 3: apt packages ───────────────────────────────────────
need_sudo() {
    sudo -n true 2>/dev/null && return 0
    bx_info "sudo needed for: $1"
    sudo -v
}

apt_packages() {
    phase "apt packages"
    if (( SKIP_APT )); then skip "apt (--no-apt)"; return 0; fi
    if ! command -v apt-get >/dev/null; then skip "apt-get not found (non-Debian host)"; return 0; fi

    local missing=() p
    for p in "${APT_PACKAGES[@]}"; do
        dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || missing+=("$p")
    done
    if (( ${#missing[@]} == 0 )); then
        skip "all ${#APT_PACKAGES[@]} packages present"
        return 0
    fi
    bx_info "installing: ${missing[*]}"
    if (( DRY_RUN )); then bx_dim "  [dry-run] sudo apt-get update && sudo apt-get install -y ${missing[*]}"; return 0; fi
    need_sudo "apt-get install" || { failed "sudo unavailable for apt"; return 1; }
    sudo apt-get update -q >/dev/null 2>&1 || bx_warn "apt-get update failed — installing from the current index"
    if sudo apt-get install -y -q "${missing[@]}" >/dev/null 2>&1; then
        done_ "apt: ${missing[*]}"
        return 0
    fi
    # One unknown package name must not sink the whole batch: retry singly.
    local bad=()
    for p in "${missing[@]}"; do
        sudo apt-get install -y -q "$p" >/dev/null 2>&1 || bad+=("$p")
    done
    if (( ${#bad[@]} )); then
        failed "apt: could not install ${bad[*]}"
    else
        done_ "apt: ${missing[*]}"
    fi
}

# ── Phase 4: companion state ────────────────────────────────────
todo_app() {
    phase "todo app (~/todo)"
    if [[ -f "$HOME/todo/todo.sh" ]]; then skip "~/todo already present"; return 0; fi
    if run git clone --quiet "$TODO_REPO" "$HOME/todo"; then
        done_ "cloned $TODO_REPO → ~/todo"
    else
        failed "git clone $TODO_REPO — the today column in the MOTD stays hidden until ~/todo exists"
    fi
}

vault() {
    phase "vault (~/vault)"
    if (( ! WITH_VAULT )); then skip "vault-init not requested (--vault); it sweeps loose files from ~ into ~/vault"; return 0; fi
    if [[ -d "$HOME/vault/inbox" && -d "$HOME/vault/code" ]]; then skip "~/vault already laid out"; return 0; fi
    bx_info "vault-init also sweeps loose files from ~, ~/Documents and ~/Desktop into ~/vault"
    if run bash "$TARGET/tools/vault-init.sh" >/dev/null; then done_ "vault-init"; else failed "vault-init"; fi
}

ssh_key_hint() {
    local remote
    remote=$(git -C "$TARGET" config --get remote.origin.url 2>/dev/null || true)
    [[ "$remote" == git@* ]] || return 0
    if ! ssh-add -l >/dev/null 2>&1 && [[ ! -f "$HOME/.ssh/id_ed25519" && ! -f "$HOME/.ssh/id_rsa" ]]; then
        bx_warn "origin is $remote but no SSH key found — git pull in ~/.bin will fail until one is added"
    fi
}

# ── Phase 5: installers ─────────────────────────────────────────
github_cli() {
    phase "GitHub CLI"
    if (( SKIP_GH )); then skip "gh (--no-gh)"; return 0; fi
    if command -v gh >/dev/null; then skip "gh already installed"; return 0; fi
    if (( DRY_RUN )); then bx_dim "  [dry-run] bx run install-gh"; return 0; fi
    need_sudo "install-gh" || { failed "sudo unavailable for install-gh"; return 1; }
    if bash "$TARGET/tools/install-gh.sh"; then done_ "gh installed"; else failed "install-gh"; fi
}

claude_cli() {
    phase "Claude Code CLI"
    if (( SKIP_CLAUDE )); then skip "claude CLI (--no-claude)"; return 0; fi
    if command -v claude >/dev/null || [[ -x "$HOME/.local/bin/claude" ]]; then skip "claude already installed"; return 0; fi
    if (( DRY_RUN )); then bx_dim "  [dry-run] curl -fsSL https://claude.ai/install.sh | bash"; return 0; fi
    # Official native installer: user-local (~/.local/bin), no sudo, self-updating.
    if curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1; then
        done_ "claude CLI installed to ~/.local/bin (run \`claude\` once to log in)"
    else
        failed "claude CLI install — see https://code.claude.com/docs/en/setup"
    fi
}

claude_statusline() {
    phase "Claude Code status line"
    if (( SKIP_CLAUDE )); then skip "claude-init (--no-claude)"; return 0; fi
    if ! command -v python3 >/dev/null; then failed "python3 missing — claude-init needs it"; return 1; fi
    local link="$HOME/.claude/statusline.py"
    if [[ -L "$link" && "$(readlink "$link")" == "$TARGET/claude/statusline.py" ]] \
        && grep -q '"statusLine"' "$HOME/.claude/settings.json" 2>/dev/null; then
        skip "status line already wired"
        return 0
    fi
    if run bash "$TARGET/tools/claude-init.sh" >/dev/null; then
        done_ "claude status line configured"
    else
        failed "claude-init"
    fi
}

docker_engine() {
    phase "Docker"
    if (( ! WITH_DOCKER )); then skip "docker-init (--no-docker)"; return 0; fi
    if command -v docker >/dev/null; then skip "docker already installed"; return 0; fi
    if (( DRY_RUN )); then bx_dim "  [dry-run] bx run docker-init"; return 0; fi
    need_sudo "docker-init" || { failed "sudo unavailable for docker-init"; return 1; }
    if bash "$TARGET/tools/docker-init.sh"; then done_ "docker installed"; else failed "docker-init"; fi
}

# ── Phase 6: geekbar ────────────────────────────────────────────
argos_installed() {
    command -v gnome-extensions >/dev/null && gnome-extensions list 2>/dev/null | grep -qx "$ARGOS_UUID"
}

install_argos() {
    local shell_ver info url zip
    shell_ver=$(gnome-shell --version 2>/dev/null | awk '{print $3}' | cut -d. -f1)
    [[ -n "$shell_ver" ]] || { failed "gnome-shell version undetectable"; return 1; }
    info=$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=$ARGOS_UUID&shell_version=$shell_ver") \
        || { failed "extensions.gnome.org lookup for GNOME $shell_ver"; return 1; }
    url=$(printf '%s' "$info" | jq -r '.download_url // empty')
    [[ -n "$url" ]] || { failed "Argos has no build for GNOME Shell $shell_ver — install it manually"; return 1; }
    zip=$(mktemp --suffix=.zip)
    curl -fsSL "https://extensions.gnome.org$url" -o "$zip" || { failed "download Argos"; rm -f "$zip"; return 1; }
    gnome-extensions install --force "$zip" >/dev/null && rm -f "$zip" || { failed "gnome-extensions install"; rm -f "$zip"; return 1; }
    gnome-extensions enable "$ARGOS_UUID" 2>/dev/null || true
    done_ "Argos extension installed (log out/in or restart GNOME Shell to activate)"
}

geekbar() {
    phase "geekbar"
    if (( ! WITH_GEEKBAR )); then skip "geekbar (--no-geekbar)"; return 0; fi
    if ! command -v gnome-extensions >/dev/null; then skip "not a GNOME session"; return 0; fi
    if argos_installed; then
        skip "Argos extension present"
    elif (( DRY_RUN )); then
        bx_dim "  [dry-run] install Argos from extensions.gnome.org"
    else
        install_argos || return 1
    fi
    local link="$HOME/.config/argos/geekbar.2s+.sh"
    if [[ -L "$link" && "$(readlink -f "$link")" == "$TARGET/plugins/geekbar/geekbar.argos.sh" ]]; then
        skip "geekbar plugin already enabled"
    elif run "$TARGET/bx" plugin enable geekbar >/dev/null 2>&1; then
        done_ "geekbar plugin enabled"
    else
        failed "bx plugin enable geekbar"
    fi
}

# ── Phase 7: verify ─────────────────────────────────────────────
verify() {
    phase "verify"
    if (( SKIP_VERIFY )); then skip "verify (--no-verify)"; return 0; fi
    if (( DRY_RUN )); then bx_dim "  [dry-run] fresh-shell load, bx doctor, bx selftest, tests/"; return 0; fi

    local out loaded fails
    out=$(env -i HOME="$HOME" TERM=dumb PATH="/usr/bin:/bin" \
          bash -c '. "$HOME/.bin/init.sh" >/dev/null 2>&1; echo "$BX_MODULES_LOADED|${BX_MODULES_FAILED:-}"')
    loaded=${out%%|*}; fails=${out#*|}
    if [[ -n "$fails" ]]; then failed "fresh shell: modules failed: $fails"
    else done_ "fresh shell loads $loaded modules, none failed"; fi

    # doctor is expected to flag "init.sh NOT loaded in this shell" here; source it first.
    if (BX_HOME="$TARGET" bash -c '. "$HOME/.bin/init.sh" >/dev/null 2>&1; "$HOME/.bin/bx" doctor' >/dev/null 2>&1); then
        done_ "bx doctor"
    else
        failed "bx doctor — run it for details"
    fi

    if (bash -c '. "$HOME/.bin/init.sh" >/dev/null 2>&1; "$HOME/.bin/bx" selftest' >/dev/null 2>&1); then
        done_ "bx selftest"
    else
        failed "bx selftest — run it for details"
    fi

    local t pass=0 fail=0
    for t in "$TARGET"/tests/test_*.sh; do
        [[ -f "$t" ]] || continue
        if bash "$t" >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); bx_warn "test failed: ${t##*/}"; fi
    done
    # tests/ is not part of selftest and is not gating: a stale test must not block an install.
    if (( fail )); then bx_warn "tests/: $pass passed, $fail failed (not gating)"; else done_ "tests/: $pass passed"; fi
}

summary() {
    phase "summary"
    printf '  done:    %d\n  skipped: %d\n  failed:  %d\n' "${#DONE[@]}" "${#SKIPPED[@]}" "${#FAILED[@]}" >&2
    local f
    for f in "${FAILED[@]+"${FAILED[@]}"}"; do bx_err "  $f"; done
    if (( ${#FAILED[@]} )); then
        bx_err "bootstrap finished with failures — fix and re-run: bx run bootstrap"
        return 1
    fi
    bx_ok "bootstrap complete — open a new terminal (or: exec bash)"
    return 0
}

main() {
    ORIG_ARGS=("$@")
    parse_args "$@"
    preflight
    relocate
    wire_shell
    git_identity
    apt_packages
    todo_app
    vault
    ssh_key_hint
    github_cli
    claude_cli
    claude_statusline
    docker_engine
    geekbar
    verify
    summary
}

main "$@"
