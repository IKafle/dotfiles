#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  geekbar :: widgets/context
#  git — primary signal is the shell hook in
#  modules/45-geekbar-track.sh, which writes the active .git
#  root to $XDG_CACHE_HOME/geekbar/active_repo on every cd.
#  Cold-boot fallback is find_active_repo() in lib.sh.
# ─────────────────────────────────────────────────────────────

# Resolve the active repo. Order:
#   1. State file written by the shell hook (cheap, accurate).
#   2. find_active_repo cold-boot scan, cached for CACHE_TTL_COLD.
_widget_git_active_repo() {
    local state="${XDG_CACHE_HOME:-$HOME/.cache}/geekbar/active_repo"
    if [[ -f "$state" ]]; then
        local repo; repo=$(< "$state")
        if [[ -n "$repo" && -d "$repo/.git" ]]; then
            printf '%s' "$repo"
            return
        fi
    fi
    cache_get gitrepo "$CACHE_TTL_COLD" find_active_repo
}

_widget_git_raw() {
    local repo
    repo=$(_widget_git_active_repo)
    [[ -z "$repo" ]] && return
    cache_get gitstatus "$CACHE_TTL_LAZY" git_status "$repo"
}

widget_git_bar() {
    local raw branch ahead behind dirty path
    raw=$(_widget_git_raw)
    [[ -z "$raw" ]] && return
    IFS='|' read -r branch ahead behind dirty path <<< "$raw"
    local out=" $branch"
    (( ahead  > 0 )) && out+=" ↑$ahead"
    (( behind > 0 )) && out+=" ↓$behind"
    (( dirty  > 0 )) && out+=" ●$dirty"
    printf '%s' "$out"
}

widget_git_menu() {
    local raw branch ahead behind dirty path
    raw=$(_widget_git_raw)
    [[ -z "$raw" ]] && return
    IFS='|' read -r branch ahead behind dirty path <<< "$raw"
    local detail="$branch"
    (( ahead  > 0 )) && detail+=" ↑$ahead"
    (( behind > 0 )) && detail+=" ↓$behind"
    (( dirty  > 0 )) && detail+=" ●$dirty"
    argos_item " Git         $detail"
    argos_item "--  $path" "$COLOR_DIM"
}

# ─────────────────────────────────────────────────────────────
#  k8s — current kubectl context + namespace
# ─────────────────────────────────────────────────────────────

_widget_k8s_context() {
    command -v kubectl >/dev/null 2>&1 || return
    cache_get k8s.context 30 safe_cmd 1 kubectl config current-context
}

_widget_k8s_namespace() {
    command -v kubectl >/dev/null 2>&1 || return
    local ns
    ns=$(cache_get k8s.namespace 30 safe_cmd 1 kubectl config view --minify -o 'jsonpath={..namespace}')
    printf '%s' "${ns:-default}"
}

_widget_k8s_is_danger() {
    local ctx="$1"
    [[ -z "$ctx" || -z "${K8S_DANGER_CONTEXTS:-}" ]] && return 1
    [[ "$ctx" =~ $K8S_DANGER_CONTEXTS ]]
}

widget_k8s_bar() {
    command -v kubectl >/dev/null 2>&1 || return
    local ctx ns bucket body
    ctx=$(_widget_k8s_context)
    if [[ -n "$ctx" ]] && _widget_k8s_is_danger "$ctx"; then
        bucket="crit"; body="$ctx (danger context — be careful)"
    else
        bucket="ok"
        if [[ -n "$ctx" ]]; then body="$ctx (safe context)"
        else body="no context"
        fi
    fi
    notify_edge k8s "$bucket" "⚠️ k8s context" "$body"
    [[ -z "$ctx" ]] && return
    ns=$(_widget_k8s_namespace)
    # Argos bar honors only a single trailing `| color=` directive; selective
    # Pango spans inside the label are unreliable. Surface danger contexts
    # with a textual ⚠ prefix instead.
    if _widget_k8s_is_danger "$ctx"; then
        printf '⚠ 󱃾 %s · %s' "$ctx" "$ns"
    else
        printf '󱃾 %s · %s' "$ctx" "$ns"
    fi
}

widget_k8s_menu() {
    command -v kubectl >/dev/null 2>&1 || return
    local ctx ns ctx_color="$COLOR_ACCENT"
    ctx=$(_widget_k8s_context)
    [[ -z "$ctx" ]] && return
    ns=$(_widget_k8s_namespace)
    _widget_k8s_is_danger "$ctx" && ctx_color="$COLOR_CRIT"
    argos_item "󱃾 Context      $ctx" "$ctx_color"
    argos_item "--󰛢 Namespace    $ns"
    echo "--▶ Switch context | bash='$__DIR__/actions.sh k8s-switch' terminal=true"
    echo "--📋 get pods | bash='$__DIR__/actions.sh k8s-get-pods' terminal=true"
    echo "--📊 recent events | bash='$__DIR__/actions.sh k8s-events' terminal=true"
}

# ─────────────────────────────────────────────────────────────
#  cloud — first detected provider identity (aws / gcp / az)
# ─────────────────────────────────────────────────────────────

_widget_cloud_aws() {
    command -v aws >/dev/null 2>&1 || return
    if [[ -n "${AWS_PROFILE:-}" ]]; then
        printf '%s' "$AWS_PROFILE"
        return
    fi
    cache_get cloud.aws 60 bash -c \
        'aws configure list 2>/dev/null | awk '\''/^[[:space:]]*profile/ {print $2}'\'''
}

_widget_cloud_gcp() {
    command -v gcloud >/dev/null 2>&1 || return
    cache_get cloud.gcp 60 safe_cmd 2 gcloud config get-value account
}

_widget_cloud_az() {
    command -v az >/dev/null 2>&1 || return
    cache_get cloud.az 60 safe_cmd 2 az account show --query name -o tsv
}

widget_cloud_bar() {
    local v
    v=$(_widget_cloud_aws); [[ -n "$v" && "$v" != "<not" ]] && { printf ' aws:%s' "$v"; return; }
    v=$(_widget_cloud_gcp); [[ -n "$v" ]] && { printf ' gcp:%s' "$v"; return; }
    v=$(_widget_cloud_az);  [[ -n "$v" ]] && { printf ' az:%s'  "$v"; return; }
}

widget_cloud_menu() {
    local aws gcp az shown=0 parent_emitted=0
    aws=$(_widget_cloud_aws)
    gcp=$(_widget_cloud_gcp)
    az=$(_widget_cloud_az)

    if [[ -n "$aws" && "$aws" != "<not" ]]; then
        argos_item " AWS profile  $aws"
        parent_emitted=1
        if command -v aws >/dev/null 2>&1; then
            echo "--▶ aws sso login | bash='$__DIR__/actions.sh cloud-aws-sso' terminal=true"
            echo "--▶ aws sts get-caller-identity | bash='$__DIR__/actions.sh cloud-aws-whoami' terminal=true"
        fi
        shown=1
    fi
    if [[ -n "$gcp" ]]; then
        argos_item " GCP account  $gcp"
        if command -v gcloud >/dev/null 2>&1; then
            echo "--▶ gcloud auth list | bash='$__DIR__/actions.sh cloud-gcp-list' terminal=true"
        fi
        shown=1
    fi
    if [[ -n "$az" ]]; then
        argos_item " Azure sub    $az"
        shown=1
    fi
    (( shown == 0 )) && return
}

# ─────────────────────────────────────────────────────────────
#  vpn — active VPN connection name (self-suppresses when down)
# ─────────────────────────────────────────────────────────────

_widget_vpn_detect() {
    local name
    if command -v nmcli >/dev/null 2>&1; then
        name=$(cache_get vpn.nm 5 bash -c \
            "nmcli -t -f NAME,TYPE,DEVICE connection show --active 2>/dev/null | awk -F: '\$2 ~ /vpn|wireguard|tun/ {print \$1; exit}'")
        [[ -n "$name" ]] && { printf '%s' "$name"; return; }
    fi
    if command -v wg >/dev/null 2>&1; then
        name=$(cache_get vpn.wg 5 bash -c 'wg show interfaces 2>/dev/null | awk "{print \$1; exit}"')
        [[ -n "$name" ]] && { printf '%s' "$name"; return; }
    fi
    name=$(cache_get vpn.tun 5 bash -c \
        "ip -o link show 2>/dev/null | awk -F': ' '/tun[0-9]+:/ && /state UP/ {print \$2; exit}'")
    [[ -n "$name" ]] && printf '%s' "$name"
}

widget_vpn_bar() {
    local name bucket body
    name=$(_widget_vpn_detect)
    if [[ -n "$name" ]]; then
        bucket="up"; body="$name"
    else
        bucket="down"; body=""
    fi
    notify_edge vpn "$bucket" "🔓 VPN $bucket" "$body"
    [[ -z "$name" ]] && return
    printf '󰦝 %s' "$name"
}

widget_vpn_menu() {
    local name
    name=$(_widget_vpn_detect)
    [[ -z "$name" ]] && return
    argos_item "󰦝 VPN          $name" "$COLOR_OK"
    echo "--▶ Disconnect | bash='$__DIR__/actions.sh vpn-disconnect $name' terminal=true"
    echo "--▶ Show route table | bash='$__DIR__/actions.sh vpn-routes' terminal=true"
}
