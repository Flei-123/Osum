#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ota/republish-hp.sh ["<notes>"] [--dry]
#   One command: fetch origin/main, build the HP image of it, select every /bin program that differs from the
#   baseline the HP was installed with (HP_BASE, default hp-stick33), publish kernel + overlay to the dev feed
#   (tools/ota/publish-hp.sh) and clean up. Afterwards the HP only needs `/bin/ota system apply restart`.
#   Env: HP_BASE=<image dir of the installed baseline>  HP_REF=<git ref, default origin/main>
#        HP_KEEP_IMAGE=1 keeps the built image dir.  Run directly (not via heavy) when the heavy queue hangs.
set -euo pipefail
REPO=${OSUM_MAIN_CHECKOUT:-/root/jarvis/projects/u_DiS4in7esMF1/osum}
HP_BASE=${HP_BASE:-/root/abbilder/hp-stick33}
HP_REF=${HP_REF:-origin/main}
NOTES=${1:-"HP update from $HP_REF"}
DRY=""
for a in "$@"; do [ "$a" = "--dry" ] && DRY=--dry; done
[ "$NOTES" = "--dry" ] && NOTES="HP update from $HP_REF"
[ -d "$HP_BASE" ] || { echo "republish-hp: baseline $HP_BASE missing"; exit 1; }
cd "$REPO"
git fetch -q origin
WT=$(mktemp -d /root/jarvis/data/staff_wt/orientos/republish.XXXXXX)
IMG=/root/abbilder/hp-feed-$$
cleanup() {
    git -C "$REPO" worktree remove --force "$WT" > /dev/null 2>&1 || rm -rf "$WT"
    git -C "$REPO" worktree prune
    [ -n "${HP_KEEP_IMAGE:-}" ] || rm -rf "$IMG"
}
trap cleanup EXIT
rm -rf "$WT"
git worktree add -q --detach "$WT" "$HP_REF"
for d in bin lib .gebaut; do [ -e "$REPO/vendor/firn/$d" ] && cp -a "$REPO/vendor/firn/$d" "$WT/vendor/firn/"; done
cd "$WT"
COUNT=$(git rev-list --count HEAD)
echo "republish-hp: $(git rev-parse --short HEAD) count $COUNT"
IMAGE_ID=hp-feed HP_STICK=1 bash tools/usbimg/build.sh "$IMG" > "$IMG.log" 2>&1 || { tail -20 "$IMG.log"; exit 1; }
PROGS=()
for f in "$IMG"/*.elf; do
    n=$(basename "$f" .elf)
    [ "$n" = "osum.mb" ] && continue
    [ -s "$f" ] || continue
    if [ ! -f "$HP_BASE/$n.elf" ] || ! cmp -s "$HP_BASE/$n.elf" "$f"; then PROGS+=("$n"); fi
done
echo "republish-hp: ${#PROGS[@]} overlay programs"
bash tools/ota/publish-hp.sh "$IMG" "$NOTES" "${PROGS[@]}" $DRY
rm -f "$IMG.log"
