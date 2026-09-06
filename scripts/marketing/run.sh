#!/bin/sh
set -eu
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../.." && pwd)
export MSYS_NO_PATHCONV=1
mkdir -p "$repo_root/demo/marketing" "$repo_root/docs/media"
docker_root=$repo_root
if command -v cygpath >/dev/null 2>&1; then
    docker_root=$(cygpath -m "$repo_root")
fi
if [ "${1:-}" = '--verify' ] && [ "$#" -eq 1 ]; then
    exec docker run --rm --entrypoint node \
        -v "$docker_root:/src:ro" -v "$docker_root/demo/marketing:/output" \
        git-review-marketing /src/scripts/marketing/verify.cjs
fi
if [ "${1:-}" = '--render' ] && [ "$#" -le 2 ]; then
    client=${2:-vscode}
    case "$client" in vscode) source_dir=/output ;; jetbrains|visualstudio) source_dir=/output/$client ;; *) echo 'Unknown demo client' >&2; exit 2 ;; esac
    exec docker run --rm --entrypoint node \
        -v "$docker_root:/src:ro" -v "$docker_root/demo/marketing:/output" \
        -v "$docker_root/docs/media:/media" \
        git-review-marketing /src/scripts/marketing/render.mjs "$source_dir" /media "$client"
fi
if [ "$#" -ne 0 ]; then
    echo 'Usage: sh scripts/marketing/run.sh [--render [vscode|jetbrains|visualstudio]|--verify]' >&2
    exit 2
fi
if ! docker image inspect git-review-vscode-tests >/dev/null 2>&1; then
    docker build -t git-review-vscode-tests "$docker_root/vscode-extension/test"
fi
docker build -t git-review-marketing "$docker_root/scripts/marketing"
docker run --rm --shm-size=1g \
    -v "$docker_root:/src:ro" \
    -v "$docker_root/demo/marketing:/output" \
    -v "$docker_root/docs/media:/media" \
    -v grv-marketing-node-modules:/work/vscode-extension/node_modules \
    -v grv-vscode-test-cache:/work/vscode-extension/.vscode-test \
    git-review-marketing
