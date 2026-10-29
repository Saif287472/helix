#!/usr/bin/env bash
# Builds an Orbit Home server release from a git tag, without touching any
# running server. Run it where Flutter/Dart is installed (CI, a build machine),
# not necessarily on the VM, then copy the folder to the VM
# (rsync -a releases/<tag>/ vm:/opt/helix/releases/<tag>/) and run deploy.sh there.
#
#   ./release.sh <tag> [--allow-off-main] [--require-signed-tag] [out-dir]
#
# Refuses a tag whose commit is not on origin/main (only merged work is
# deployed), builds in a throwaway worktree with the committed lockfile
# (`flutter pub get --enforce-lockfile`), compiles the three executables for
# THIS machine's OS and architecture (build on Linux x86_64 for an x86_64 VM),
# and records their SHA-256 in VERSION, which deploy.sh checks again.
set -euo pipefail
tag=${1:?usage: release.sh <tag> [--allow-off-main] [--require-signed-tag] [out-dir]}; shift
allow_off_main=0; require_signed=0; out_root=
while [ $# -gt 0 ]; do
    case $1 in
        --allow-off-main) allow_off_main=1 ;;
        --require-signed-tag) require_signed=1 ;;
        *) out_root=$1 ;;
    esac
    shift
done
repo=$(git rev-parse --show-toplevel)
out_root=${out_root:-$repo/helix_remote/build/releases}
commit=$(git -C "$repo" rev-parse --verify --quiet "refs/tags/$tag^{commit}") \
    || { echo "No tag $tag (create it with: git tag $tag)" >&2; exit 1; }
if [ "$require_signed" = 1 ]; then
    git -C "$repo" verify-tag "$tag" || { echo "Tag $tag has no valid signature (git tag -s $tag)." >&2; exit 1; }
fi
if [ "$allow_off_main" != 1 ]; then
    git -C "$repo" fetch --quiet origin main || true
    git -C "$repo" merge-base --is-ancestor "$commit" origin/main \
        || { echo "Tag $tag ($commit) is not on origin/main. Merge it first, or pass --allow-off-main." >&2; exit 1; }
fi
out=$out_root/$tag
[ ! -e "$out/helix-server" ] || { echo "$out already has a build. Delete it to build again." >&2; exit 1; }
tree=$(mktemp -d)
trap 'git -C "$repo" worktree remove --force "$tree" 2>/dev/null || true' EXIT
git -C "$repo" worktree add --detach "$tree" "$tag"
mkdir -p "$out"
(
    cd "$tree/helix_remote"
    flutter pub get --enforce-lockfile
    dart compile exe server/bin/server.dart -o "$out/helix-server"
    dart compile exe server/bin/migrate.dart -o "$out/helix-migrate"
    dart compile exe server/bin/admin_tool.dart -o "$out/helix-admin-tool"
)
{
    echo "tag=$tag"
    echo "commit=$commit"
    echo "built=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "platform=$(uname -sm)"
    for exe in helix-server helix-migrate helix-admin-tool; do
        echo "sha256-$exe=$(sha256sum "$out/$exe" | cut -d' ' -f1)"
    done
} >"$out/VERSION"
echo "Built $tag ($commit) into $out"
echo "Next: copy it to the VM's /opt/helix/releases/$tag and run /opt/helix/ops/deploy.sh $tag"
