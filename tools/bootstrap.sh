#!/usr/bin/env bash
# bx-purpose: fresh-machine entrypoint — relocate to ~/.bin, wire bashrc, install deps, verify (idempotent)
# bx-tool-kind: entrypoint
#
# Usage:
#   git clone git@github.com:IKafle/dotfiles.git && bash dotfiles/tools/bootstrap.sh [flags]
#   bx run bootstrap [flags]            # re-run any time; every step is a no-op when already done
#
# Configuration (ADR-0004): config/bootstrap.conf holds repos, identity and
# download sources; config/packages/<ID>[-<VERSION_ID>].list holds the package
# names for the OS detected from /etc/os-release. Precedence for any value:
# flag > BX_<KEY> env var > config file. Nothing OS-specific lives in here.
#
# Flags:
#   --todo-repo <url>   override TODO_REPO
#   --git-name <name>   override GIT_NAME
#   --git-email <addr>  override GIT_EMAIL
#   --no-apt            skip the apt package step
#   --no-gh             skip GitHub CLI install
#   --no-claude         skip Claude Code CLI install + status-line setup
#   --no-docker         skip docker-init (Docker's apt repo, engine + compose)
#   --no-geekbar        skip the Argos GNOME extension + geekbar plugin
#   --no-rofi           skip binding Super-d to the rofi launcher (rofi-init)
#   --no-vault          skip vault-init (creates ~/vault AND sweeps loose files from ~ into it)
#   --no-todo           skip cloning TODO_REPO into ~/todo (e.g. no key for a private repo)
#   --no-verify         skip doctor/selftest/tests at the end
#   --dry-run           print what would happen; change nothing
#
# Exit: 0 all done, 1 a required step failed, 2 bad usage

set -uo pipefail

TARGET="$HOME/.bin"
SELF=$(readlink -f "${BASH_SOURCE[0]}")
ROOT=$(dirname "$(dirname "$SELF")")

DRY_RUN=0
WITH_DOCKER=1 WITH_GEEKBAR=1 WITH_ROFI=1 WITH_VAULT=1 WITH_TODO=1
SKIP_APT=0 SKIP_GH=0 SKIP_CLAUDE=0 SKIP_VERIFY=0
CONFIG_DIR="$ROOT/config"
OS_RELEASE_FILE="${BX_OS_RELEASE_FILE:-/etc/os-release}"
# A fresh install knows no marketplace; plugins in CLAUDE_PLUGINS come from this one.
CLAUDE_MARKETPLACE="anthropics/claude-plugins-official"

# Filled by load_config (file) / env / flags — see precedence above.
TODO_REPO="" GIT_NAME="" GIT_EMAIL=""
ARGOS_UUID="" ARGOS_TARBALL="" ARGOS_TARBALL_SUBDIR="" CLAUDE_INSTALLER="" CLAUDE_PLUGINS=""
declare -A FLAG_OVERRIDE=()

# Filled by detect_os.
OS_ID="" OS_VERSION="" OS_CODENAME="" OS_LIKE="" OS_KERNEL="" GNOME_MAJOR=""
APT_PACKAGES=()

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
                           FLAG_OVERRIDE[TODO_REPO]=$2; shift ;;
            --todo-repo=*) FLAG_OVERRIDE[TODO_REPO]=${1#*=} ;;
            --git-name)    [[ -n "${2:-}" ]] || { bx_err "--git-name needs a value"; exit 2; }
                           FLAG_OVERRIDE[GIT_NAME]=$2; shift ;;
            --git-name=*)  FLAG_OVERRIDE[GIT_NAME]=${1#*=} ;;
            --git-email)   [[ -n "${2:-}" ]] || { bx_err "--git-email needs a value"; exit 2; }
                           FLAG_OVERRIDE[GIT_EMAIL]=$2; shift ;;
            --git-email=*) FLAG_OVERRIDE[GIT_EMAIL]=${1#*=} ;;
            --no-docker)   WITH_DOCKER=0 ;;
            --no-geekbar)  WITH_GEEKBAR=0 ;;
            --no-rofi)     WITH_ROFI=0 ;;
            --no-vault)    WITH_VAULT=0 ;;
            --no-todo)     WITH_TODO=0 ;;
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

# ── Configuration & OS detection (ADR-0004) ─────────────────────
# KEY=VALUE parser rather than `source`: config is data, not code.
load_config() {
    local f="$CONFIG_DIR/bootstrap.conf" line key val
    [[ -f "$f" ]] || { bx_err "missing $f"; exit 1; }
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=${line%%#*}; line=${line#"${line%%[![:space:]]*}"}; line=${line%"${line##*[![:space:]]}"}
        [[ -z "$line" ]] && continue
        key=${line%%=*}; val=${line#*=}
        [[ "$key" =~ ^[A-Z][A-Z0-9_]*$ ]] || { bx_warn "bootstrap.conf: ignoring malformed line: $line"; continue; }
        val=${val#\"}; val=${val%\"}
        printf -v "$key" '%s' "$val"
    done < "$f"

    local k envk
    for k in TODO_REPO GIT_NAME GIT_EMAIL ARGOS_UUID ARGOS_TARBALL ARGOS_TARBALL_SUBDIR CLAUDE_INSTALLER CLAUDE_PLUGINS; do
        envk="BX_$k"
        [[ -n "${!envk:-}" ]] && printf -v "$k" '%s' "${!envk}"
        [[ -n "${FLAG_OVERRIDE[$k]:-}" ]] && printf -v "$k" '%s' "${FLAG_OVERRIDE[$k]}"
        # CLAUDE_PLUGINS may legitimately be empty.
        [[ -n "${!k}" || "$k" == CLAUDE_PLUGINS ]] || { bx_err "bootstrap.conf: $k is not set"; exit 1; }
    done
}

detect_os() {
    if [[ -f "$OS_RELEASE_FILE" ]]; then
        # shellcheck disable=SC1090
        OS_ID=$(. "$OS_RELEASE_FILE"; printf '%s' "${ID:-}")
        OS_VERSION=$(. "$OS_RELEASE_FILE"; printf '%s' "${VERSION_ID:-}")
        OS_CODENAME=$(. "$OS_RELEASE_FILE"; printf '%s' "${VERSION_CODENAME:-}")
        OS_LIKE=$(. "$OS_RELEASE_FILE"; printf '%s' "${ID_LIKE:-}")
    fi
    OS_KERNEL=$(uname -r)
    GNOME_MAJOR=$(gnome-shell --version 2>/dev/null | awk '{print $3}' | cut -d. -f1)
    export BX_OS_ID="$OS_ID" BX_OS_VERSION="$OS_VERSION" BX_OS_CODENAME="$OS_CODENAME" \
           BX_OS_LIKE="$OS_LIKE" BX_OS_KERNEL="$OS_KERNEL" BX_GNOME_MAJOR="$GNOME_MAJOR"
}

# Resolve config/packages/*.list for the detected OS into APT_PACKAGES.
# Order: <ID>.list (or first ID_LIKE with a list), then <ID>-<VERSION_ID>.list.
# A leading '-' removes a package added earlier.
load_packages() {
    local dir="$CONFIG_DIR/packages" base="" like f line
    APT_PACKAGES=(); PACKAGE_LISTS=()
    if [[ -f "$dir/$OS_ID.list" ]]; then
        base="$OS_ID"
    else
        for like in $OS_LIKE; do [[ -f "$dir/$like.list" ]] && { base="$like"; break; }; done
    fi
    [[ -n "$base" ]] || return 1
    local -A want=()
    local -a order=()
    for f in "$dir/$base.list" "$dir/$OS_ID-$OS_VERSION.list"; do
        [[ -f "$f" ]] || continue
        PACKAGE_LISTS+=("${f##*/}")
        while IFS= read -r line || [[ -n "$line" ]]; do
            line=${line%%#*}; line=${line//[[:space:]]/}
            [[ -z "$line" ]] && continue
            if [[ "$line" == -* ]]; then unset "want[${line#-}]"
            else want[$line]=1; order+=("$line"); fi
        done < "$f"
    done
    local p
    for p in "${order[@]}"; do [[ -n "${want[$p]:-}" ]] && APT_PACKAGES+=("$p"); done
    return 0
}
PACKAGE_LISTS=()

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
    bx_ok "os: ${OS_ID:-unknown} ${OS_VERSION:-?} (${OS_CODENAME:-no codename}) · kernel $OS_KERNEL · gnome ${GNOME_MAJOR:-none}"
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
        ROOT=$TARGET; CONFIG_DIR="$ROOT/config"
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
    if (( DRY_RUN )); then bx_dim "  [dry-run] bx install"; return 0; fi
    local out
    if out=$("$TARGET/bx" install 2>&1); then
        case "$out" in
            *"already canonical"*) skip "~/.bashrc already canonical" ;;
            *"replaced"*)          done_ "~/.bashrc reduced to the bx hook ($(grep -o 'previous copy: [^ ]*' <<< "$out"))" ;;
            *)                     done_ "~/.bashrc created with the bx hook" ;;
        esac
    else
        failed "bx install: $out"
    fi
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
# One password for the whole run: after the first prompt, refresh the sudo
# timestamp in the background until bootstrap exits.
_SUDO_KEEPALIVE=""
need_sudo() {
    if ! sudo -n true 2>/dev/null; then
        bx_info "sudo needed for: $1"
        sudo -v || return 1
    fi
    if [[ -z "$_SUDO_KEEPALIVE" ]]; then
        ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
        _SUDO_KEEPALIVE=$!
        trap '[[ -n "$_SUDO_KEEPALIVE" ]] && kill "$_SUDO_KEEPALIVE" 2>/dev/null' EXIT
    fi
    return 0
}

apt_packages() {
    phase "apt packages"
    if (( SKIP_APT )); then skip "apt (--no-apt)"; return 0; fi
    if ! load_packages; then
        skip "no package list for ${OS_ID:-unknown} ${OS_VERSION:-} — add config/packages/${OS_ID:-<id>}.list"
        return 0
    fi
    bx_dim "  lists: ${PACKAGE_LISTS[*]} (${#APT_PACKAGES[@]} packages)"
    if ! command -v apt-get >/dev/null; then
        skip "apt-get not found — only apt-family installs are implemented (ADR-0004)"
        return 0
    fi

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
    if (( ! WITH_TODO )); then skip "todo clone (--no-todo)"; return 0; fi
    if [[ -f "$HOME/todo/todo.sh" ]]; then skip "~/todo already present"; return 0; fi
    if run git clone --quiet "$TODO_REPO" "$HOME/todo"; then
        done_ "cloned $TODO_REPO → ~/todo"
    else
        failed "git clone $TODO_REPO — the today column in the MOTD stays hidden until ~/todo exists"
    fi
}

vault() {
    phase "vault (~/vault)"
    if (( ! WITH_VAULT )); then skip "vault-init (--no-vault)"; return 0; fi
    bx_dim "  vault-init also sweeps loose files from ~, ~/Documents and ~/Desktop into ~/vault"
    if (( DRY_RUN )); then bx_dim "  [dry-run] bx run vault-init"; return 0; fi
    local out
    if out=$(bash "$TARGET/tools/vault-init.sh" 2>&1); then
        case "$out" in
            *"Nothing new to organize"*) skip "vault-init: nothing new to organize" ;;
            *) done_ "vault-init: $(printf '%s\n' "$out" | grep -oE 'Moved [0-9]+ item\(s\)' || echo 'laid out ~/vault')" ;;
        esac
    else
        failed "vault-init"
    fi
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
    if (( DRY_RUN )); then bx_dim "  [dry-run] curl -fsSL $CLAUDE_INSTALLER | bash"; return 0; fi
    # Official native installer: user-local (~/.local/bin), no sudo, self-updating.
    if curl -fsSL "$CLAUDE_INSTALLER" | bash >/dev/null 2>&1; then
        done_ "claude CLI installed to ~/.local/bin (run \`claude\` once to log in)"
    else
        failed "claude CLI install — see https://code.claude.com/docs/en/setup"
    fi
}

claude_statusline() {
    phase "Claude Code status line"
    if (( SKIP_CLAUDE )); then skip "claude-init (--no-claude)"; return 0; fi
    if (( DRY_RUN )); then bx_dim "  [dry-run] bx run claude-init"; return 0; fi
    local out
    if out=$(bash "$TARGET/tools/claude-init.sh" 2>&1); then
        case "$out" in
            *"Nothing to do"*) skip "status line already wired" ;;
            *)                 done_ "claude status line configured" ;;
        esac
    else
        failed "claude-init: $(printf '%s\n' "$out" | grep -m1 WARNING || echo 'see ~/.claude/claude-init.log')"
    fi
}

# Plugins from the official marketplace. `claude plugins list --json` ids are
# <name>@<marketplace>; a bare name in config matches any marketplace.
claude_plugins() {
    phase "Claude Code plugins"
    if (( SKIP_CLAUDE )); then skip "claude plugins (--no-claude)"; return 0; fi
    [[ -n "${CLAUDE_PLUGINS//[[:space:]]/}" ]] || { skip "CLAUDE_PLUGINS empty in bootstrap.conf"; return 0; }
    local claude_bin
    claude_bin=$(command -v claude || echo "$HOME/.local/bin/claude")
    if [[ ! -x "$claude_bin" ]]; then
        # The CLI phase installs it first; in a dry run that hasn't happened.
        if (( DRY_RUN )); then bx_dim "  [dry-run] claude plugins install $CLAUDE_PLUGINS"; return 0; fi
        failed "claude CLI not available — plugins need it"; return 1
    fi
    local installed p missing=()
    installed=$("$claude_bin" plugins list --json 2>/dev/null | jq -r '.[].id' 2>/dev/null || true)
    for p in $CLAUDE_PLUGINS; do
        grep -qx "$p@.*" <<< "$installed" || grep -qx "$p" <<< "$installed" || missing+=("$p")
    done
    if (( ${#missing[@]} == 0 )); then skip "plugins present: $CLAUDE_PLUGINS"; return 0; fi
    if (( DRY_RUN )); then bx_dim "  [dry-run] claude plugins install ${missing[*]}"; return 0; fi
    # `plugins install <name>` only searches configured marketplaces, and a
    # fresh machine has none — register the official one first (idempotent).
    local mk_name="${CLAUDE_MARKETPLACE##*/}" mk_out
    if ! "$claude_bin" plugin marketplace list --json 2>/dev/null | jq -e --arg n "$mk_name" \
            'any(.[]; .name == $n)' >/dev/null 2>&1; then
        if mk_out=$("$claude_bin" plugin marketplace add "$CLAUDE_MARKETPLACE" 2>&1); then
            bx_dim "  marketplace added: $mk_name"
        else
            printf '%s\n' "$mk_out" | tail -3 | sed 's/^/    /' >&2
            failed "claude plugin marketplace add: $CLAUDE_MARKETPLACE"; return 1
        fi
    fi
    local bad=() out
    for p in "${missing[@]}"; do
        if ! out=$("$claude_bin" plugins install "$p" 2>&1); then
            printf '%s\n' "$out" | tail -3 | sed 's/^/    /' >&2
            bad+=("$p")
        fi
    done
    if (( ${#bad[@]} )); then failed "claude plugins install: ${bad[*]}"
    else done_ "claude plugins installed: ${missing[*]}"; fi
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
# The running shell only lists an extension after the next login, so also
# accept it being on disk — otherwise every re-run before logout reinstalls.
argos_installed() {
    gnome-extensions list 2>/dev/null | grep -qx "$ARGOS_UUID" \
        || [[ -f "$HOME/.local/share/gnome-shell/extensions/$ARGOS_UUID/metadata.json" ]]
}
argos_enabled() { gnome-extensions list --enabled 2>/dev/null | grep -qx "$ARGOS_UUID"; }

# `enable` right after `install` fails silently on Wayland: the shell only sees a
# new extension after the next login. So a re-run must retry it — otherwise
# Argos sits on disk, disabled, and geekbar never appears.
argos_ensure_enabled() {
    if argos_enabled; then skip "Argos extension enabled"; return 0; fi
    if (( DRY_RUN )); then bx_dim "  [dry-run] gnome-extensions enable $ARGOS_UUID"; return 0; fi
    if gnome-extensions list 2>/dev/null | grep -qx "$ARGOS_UUID"; then
        if gnome-extensions enable "$ARGOS_UUID" 2>/dev/null && argos_enabled; then
            done_ "Argos extension enabled"
        else
            failed "gnome-extensions enable $ARGOS_UUID"; return 1
        fi
    else
        bx_warn "Argos is installed but the shell has not loaded it yet — log out and back in, then re-run bootstrap to enable it"
    fi
}

install_argos() {
    local shell_ver=$GNOME_MAJOR tmp zip src
    [[ -n "$shell_ver" ]] || { failed "gnome-shell version undetectable"; return 1; }
    tmp=$(mktemp -d)
    if ! curl -fsSL "$ARGOS_TARBALL" | tar -xz -C "$tmp" 2>/dev/null; then
        failed "download Argos from $ARGOS_TARBALL"; rm -rf "$tmp"; return 1
    fi
    src="$tmp/$ARGOS_TARBALL_SUBDIR/$ARGOS_UUID"
    if ! grep -q "\"$shell_ver\"" "$src/metadata.json" 2>/dev/null; then
        failed "Argos at $ARGOS_TARBALL does not declare GNOME Shell $shell_ver"; rm -rf "$tmp"; return 1
    fi
    zip="$tmp/argos.zip"
    ( cd "$src" && zip -qr "$zip" . ) || { failed "zip Argos"; rm -rf "$tmp"; return 1; }
    if ! gnome-extensions install --force "$zip" >/dev/null 2>&1; then
        failed "gnome-extensions install Argos"; rm -rf "$tmp"; return 1
    fi
    rm -rf "$tmp"
    gnome-extensions enable "$ARGOS_UUID" 2>/dev/null || true
    done_ "Argos extension installed for GNOME $shell_ver — log out and back in to activate it"
}

geekbar() {
    phase "geekbar"
    if (( ! WITH_GEEKBAR )); then skip "geekbar (--no-geekbar)"; return 0; fi
    if ! command -v gnome-extensions >/dev/null; then skip "not a GNOME session"; return 0; fi
    if argos_installed; then
        skip "Argos extension present"
        argos_ensure_enabled || return 1
    elif (( DRY_RUN )); then
        bx_dim "  [dry-run] install Argos from $ARGOS_TARBALL"
    else
        install_argos || return 1
    fi
    if (( DRY_RUN )); then bx_dim "  [dry-run] bx plugin enable geekbar"; return 0; fi
    local out
    if out=$("$TARGET/bx" plugin enable geekbar 2>&1); then
        case "$out" in
            *"already enabled"*) skip "geekbar plugin already enabled" ;;
            *)                   done_ "geekbar plugin enabled (postenable ran geekbar-doctor)" ;;
        esac
    else
        failed "bx plugin enable geekbar"
    fi
}

# ── Phase 6b: rofi launcher ─────────────────────────────────────
rofi_launcher() {
    phase "rofi launcher"
    if (( ! WITH_ROFI )); then skip "rofi-init (--no-rofi)"; return 0; fi
    if ! command -v gsettings >/dev/null; then skip "not a GNOME session"; return 0; fi
    if (( DRY_RUN )); then bx_dim "  [dry-run] bx run rofi-init"; return 0; fi
    local out
    if out=$(bash "$TARGET/tools/rofi-init.sh" 2>&1); then
        case "$out" in
            *"Nothing to do"*) skip "Super-d already launches rofi" ;;
            *)                 done_ "Super-d → rofi-launcher (GNOME custom shortcut)" ;;
        esac
    else
        failed "rofi-init: $(printf '%s\n' "$out" | tail -1)"
        return 1
    fi

    # The launcher is what Super-d actually runs — check the whole chain.
    local launcher="$TARGET/tools/rofi-launcher.sh" bound
    bound=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ command 2>/dev/null | tr -d "'")
    [[ -x "$launcher" ]] || run chmod +x "$launcher"
    if ! command -v rofi >/dev/null; then
        failed "rofi binary missing — the apt phase installs it (drop --no-apt)"
    elif ! bash -n "$launcher" 2>/dev/null; then
        failed "rofi-launcher.sh has a syntax error"
    elif [[ "$bound" != "$launcher" ]]; then
        failed "Super-d is bound to '${bound:-nothing}', not $launcher"
    else
        done_ "launcher ready: Super-d → rofi -show drun ($(rofi -version 2>/dev/null | head -1))"
    fi
}

# ── Phase 7: verify ─────────────────────────────────────────────
verify() {
    phase "verify"
    if (( SKIP_VERIFY )); then skip "verify (--no-verify)"; return 0; fi
    if (( DRY_RUN )); then bx_dim "  [dry-run] fresh-shell load, bx doctor, bx selftest, tests/"; return 0; fi

    local out loaded fails
    out=$(env -i HOME="$HOME" TERM=dumb PATH="/usr/bin:/bin" \
          BX_FORCE_LOAD=1 bash -c '. "$HOME/.bin/init.sh" >/dev/null 2>&1; echo "$BX_MODULES_LOADED|${BX_MODULES_FAILED:-}"')
    loaded=${out%%|*}; fails=${out#*|}
    if [[ -n "$fails" ]]; then failed "fresh shell: modules failed: $fails"
    else done_ "fresh shell loads $loaded modules, none failed"; fi

    # selftest covers doctor, the clean-env load, guards and metadata.
    if (BX_FORCE_LOAD=1 bash -c '. "$HOME/.bin/init.sh" >/dev/null 2>&1; "$HOME/.bin/bx" selftest' >/dev/null 2>&1); then
        done_ "bx selftest (includes bx doctor)"
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
    load_config
    detect_os
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
    claude_plugins
    docker_engine
    geekbar
    rofi_launcher
    verify
    summary
}

main "$@"
