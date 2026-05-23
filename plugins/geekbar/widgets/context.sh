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
    local raw branch ahead behind dirty path safe_branch
    raw=$(_widget_git_raw)
    [[ -z "$raw" ]] && return
    IFS='|' read -r branch ahead behind dirty path <<< "$raw"
    safe_branch=$(pango_escape "$branch")
    local out
    out="$(bar_icon "") ${safe_branch}"
    (( ahead  > 0 )) && out+=" ↑${ahead}"
    (( behind > 0 )) && out+=" ↓${behind}"
    (( dirty  > 0 )) && out+=" $(bar_val "●${dirty}" "$COLOR_WARN")"
    printf '%s' "$out"
}

widget_git_menu() {
    # Single row: repo basename + branch + activity chips.
    local raw branch ahead behind dirty path basename
    raw=$(_widget_git_raw)
    [[ -z "$raw" ]] && return
    IFS='|' read -r branch ahead behind dirty path <<< "$raw"
    basename="${path##*/}"
    local safe_basename safe_branch chips=""
    safe_basename=$(pango_escape "$basename")
    safe_branch=$(pango_escape "$branch")
    (( ahead  > 0 )) && chips+="  $(chip_ok   "↑${ahead}")"
    (( behind > 0 )) && chips+="  $(chip_warn "↓${behind}")"
    (( dirty  > 0 )) && chips+="  $(chip_warn "●${dirty}")"
    pri_row 3 "<span color=\"$COLOR_ACCENT\"></span> ${safe_basename} · ${safe_branch}${chips}" \
        "$__DIR__/actions.sh git-open-term ${path}" true \
        "Repo: ${path}  branch=${branch}  ahead=${ahead}  behind=${behind}  dirty=${dirty}"
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
    local safe_ctx safe_ns danger=""
    safe_ctx=$(pango_escape "$ctx")
    safe_ns=$(pango_escape "$ns")
    _widget_k8s_is_danger "$ctx" && danger="  $(chip_crit DANGER)"
    printf '%s %s · %s%s' "$(bar_icon "󱃾")" "$safe_ctx" "$safe_ns" "$danger"
}

widget_k8s_menu() {
    # One row: ctx · ns. Click → context switch.
    command -v kubectl >/dev/null 2>&1 || return
    local ctx ns safe_ctx safe_ns danger=""
    ctx=$(_widget_k8s_context)
    [[ -z "$ctx" ]] && return
    ns=$(_widget_k8s_namespace)
    safe_ctx=$(pango_escape "$ctx")
    safe_ns=$(pango_escape "$ns")
    _widget_k8s_is_danger "$ctx" && danger="  $(chip_crit DANGER)"
    pri_row 3 "<span color=\"$COLOR_ACCENT\">󱃾</span> ${safe_ctx} · ${safe_ns}${danger}" \
        "$__DIR__/actions.sh k8s-switch" true "k8s context=${ctx}  namespace=${ns}"
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
    local v safe
    v=$(_widget_cloud_aws); [[ -n "$v" && "$v" != "<not" ]] && { safe=$(pango_escape "$v"); printf '%s aws %s' "$(bar_icon "")" "$safe"; return; }
    v=$(_widget_cloud_gcp); [[ -n "$v" ]] && { safe=$(pango_escape "$v"); printf '%s gcp %s' "$(bar_icon "")" "$safe"; return; }
    v=$(_widget_cloud_az);  [[ -n "$v" ]] && { safe=$(pango_escape "$v"); printf '%s az %s'  "$(bar_icon "")" "$safe"; return; }
}

widget_cloud_menu() {
    # One compact row per active provider. AWS click → aws sso login.
    local aws gcp az safe
    aws=$(_widget_cloud_aws)
    gcp=$(_widget_cloud_gcp)
    az=$(_widget_cloud_az)

    if [[ -n "$aws" && "$aws" != "<not" ]]; then
        safe=$(pango_escape "$aws")
        pri_row 3 "<span color=\"$COLOR_ACCENT\"></span> aws  ${safe}" \
            "$__DIR__/actions.sh cloud-aws-sso" true "AWS profile=${aws}"
    fi
    if [[ -n "$gcp" ]]; then
        safe=$(pango_escape "$gcp")
        pri_row 3 "<span color=\"$COLOR_ACCENT\"></span> gcp  ${safe}" \
            "" false "GCP account=${gcp}"
    fi
    if [[ -n "$az" ]]; then
        safe=$(pango_escape "$az")
        pri_row 3 "<span color=\"$COLOR_ACCENT\"></span> az   ${safe}" \
            "" false "Azure account=${az}"
    fi
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
    printf '%s %s' "$(bar_icon "󰦝")" "$(pango_escape "$name")"
}

widget_vpn_menu() {
    # Click → disconnect.
    local name safe_name
    name=$(_widget_vpn_detect)
    [[ -z "$name" ]] && return
    safe_name=$(pango_escape "$name")
    pri_row 3 "<span color=\"$COLOR_OK\">󰦝</span> ${safe_name}  $(chip_ok UP)" \
        "$__DIR__/actions.sh vpn-disconnect ${name}" true "VPN connection: ${name} (click to disconnect)"
}
