#!/usr/bin/env bash
# bx-purpose: run bootstrap inside a clean Ubuntu container to prove a fresh machine comes up green
# bx-tool-kind: check
#
# The only test that catches "it worked here because this laptop already had
# it". Mounts this tree and ~/todo read-only, clones both inside a throwaway
# container as an unprivileged user with passwordless sudo, runs the full
# bootstrap (minus docker: no systemd in a container; minus todo when there is
# no ~/todo to mount — the repo is private and the container has no key), and
# prints the summary.
# Image comes from SMOKE_IMAGE in config/bootstrap.conf (or BX_SMOKE_IMAGE).
# The container gets a `git clone` of this tree, i.e. HEAD — commit first;
# uncommitted edits are not exercised. A green run records HEAD in
# .git/bx-smoked; hooks/pre-push reads it to say whether HEAD is proven.
#
# Usage: bx run bootstrap-smoke [--keep]      (--keep: leave the container for inspection)
set -uo pipefail

BX_HOME="${BX_HOME:-$HOME/.bin}"
IMAGE="${BX_SMOKE_IMAGE:-$(sed -nE 's/^SMOKE_IMAGE=(.*)$/\1/p' "$BX_HOME/config/bootstrap.conf")}"
[[ -n "$IMAGE" ]] || { echo "bootstrap-smoke: SMOKE_IMAGE not set in config/bootstrap.conf" >&2; exit 2; }
KEEP=0; [[ "${1:-}" == --keep ]] && KEEP=1

DOCKER=(docker)
if ! docker info >/dev/null 2>&1; then
    if sudo -n docker info >/dev/null 2>&1; then DOCKER=(sudo docker)
    else echo "bootstrap-smoke: cannot reach the docker daemon (not in the docker group yet? log out/in, or: sudo -v)" >&2; exit 1; fi
fi

TODO_MOUNT=() TODO_FLAG=--no-todo
[[ -d "$HOME/todo/.git" ]] && { TODO_MOUNT=(-v "$HOME/todo:/src-todo:ro" -e BX_TODO_REPO=/src-todo); TODO_FLAG=; }

name="bx-smoke-$(date +%s)"
rm_flag=(--rm); (( KEEP )) && rm_flag=()

printf '── bootstrap-smoke: %s ──\n' "$IMAGE" >&2
"${DOCKER[@]}" run "${rm_flag[@]}" --name "$name" \
    -v "$BX_HOME:/src:ro" "${TODO_MOUNT[@]}" \
    -e DEBIAN_FRONTEND=noninteractive -e BX_TODO_FLAG="$TODO_FLAG" \
    "$IMAGE" bash -euo pipefail -c '
        apt-get update -q >/dev/null
        apt-get install -y -q git curl sudo ca-certificates >/dev/null
        useradd -m -s /bin/bash tester
        echo "tester ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/tester
        su - tester -c "
            set -e
            # The mounts are owned by the host uid, not tester: git would refuse them.
            git config --global --add safe.directory \"*\"
            git clone -q /src ~/dotfiles
            git -C ~/dotfiles remote set-url origin git@github.com:IKafle/dotfiles.git
            ${BX_TODO_REPO:+export BX_TODO_REPO=$BX_TODO_REPO;}
            bash ~/dotfiles/tools/bootstrap.sh --no-docker $BX_TODO_FLAG
        "
    '
rc=$?
(( KEEP )) && printf 'container kept: %s  (docker exec -it %s bash)\n' "$name" "$name" >&2
if (( rc == 0 )); then
    git -C "$BX_HOME" rev-parse HEAD > "$(git -C "$BX_HOME" rev-parse --git-dir)/bx-smoked" 2>/dev/null || true
    printf '✔ fresh %s bootstraps clean\n' "$IMAGE" >&2
else printf '✘ bootstrap failed inside %s (exit %d)\n' "$IMAGE" "$rc" >&2; fi
exit $rc
