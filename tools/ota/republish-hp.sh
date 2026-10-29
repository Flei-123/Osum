#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ota/republish-hp.sh ["<notes>"] [--dry]
#   One command: fetch origin/main, build the HP image of it, select every /bin program that differs from the
#   baseline the HP was installed with (HP_BASE, default hp-stick33), publish kernel + overlay to the dev feed
#   (tools/ota/publish-hp.sh) and clean up. Afterwards the HP only needs `/bin/ota system apply restart`.
#   Env: HP_BASE=<image dir of the installed baseline>  HP_REF=<git ref, default origin/main>
#        HP_ONLY="a b c" limits the overlay to the listed programs (small first step for a slow bridge)
#        HP_NO_EXTRAS=1 drops the absolute-path files (a device with an old ota refuses them: first step only /bin)
#        HP_SAME_KERNEL=1 publishes the kernel of HP_BASE (what the HP runs): the HP applies the overlay live, no trial boot
#        HP_FX_PACK=<dir from tools/linuxapps/hppack.py> adds usr/share/xfx/{firefox.tar.partNNN (gz <= 3.9 MB each, from HP_FX_PACK/parts or packsplit.py),firefox.manifest,user.js} to the overlay (HP_ONLY must then list wayd tar xfx);
#                   the HP needs a root of >= 1 GiB (HP_STICK=1 images since ba9f4ee5), the apply refuses cleanly below 2x the size
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
EXTRA=$(mktemp -d)
LINKS=$(mktemp)
trap 'cleanup; rm -rf "$EXTRA" "$LINKS"' EXIT
for f in "$IMG"/*.elf; do
    n=$(basename "$f" .elf)
    [ "$n" = "osum.mb" ] && continue
    [ -s "$f" ] || continue
    if [ -n "${HP_ONLY:-}" ]; then case " $HP_ONLY " in *" $n "*) ;; *) continue ;; esac; fi
    if [ ! -f "$HP_BASE/$n.elf" ] || ! cmp -s "$HP_BASE/$n.elf" "$f"; then PROGS+=("$n"); fi
done
while read -r dest rel; do
    [ -s "$IMG/$rel" ] || continue
    if [ ! -f "$HP_BASE/$rel" ] || ! cmp -s "$HP_BASE/$rel" "$IMG/$rel"; then
        mkdir -p "$EXTRA/$(dirname "${dest#/}")"
        cp "$IMG/$rel" "$EXTRA/${dest#/}"
        echo "republish-hp: extra $dest"
    fi
done < <([ -n "${HP_NO_EXTRAS:-}" ] || cat tools/ota/overlay-extras.txt)
if [ -n "${HP_FX_PACK:-}" ]; then
    mkdir -p "$EXTRA/usr/share/xfx"
    if [ -f "$HP_FX_PACK/parts/firefox.tar.part000" ]; then
        cp "$HP_FX_PACK"/parts/firefox.tar.part* "$EXTRA/usr/share/xfx/"
    else
        python3 -I tools/linuxapps/packsplit.py "$HP_FX_PACK/firefox.tar" "$EXTRA/usr/share/xfx" > /dev/null
    fi
    cp "$HP_FX_PACK/firefox.manifest" assets/xfx/user.js "$EXTRA/usr/share/xfx/"
    echo "republish-hp: firefox pack $(stat -c%s "$HP_FX_PACK/firefox.tar") octets in $(ls "$EXTRA/usr/share/xfx" | grep -c '\.part') parts"
fi
python3 tools/k15/bundle.py assets/apps "$EXTRA.bundle" nur="${PROGS[*]} term" \
    | sed -n 's|^\(/apps/[A-Za-z0-9._-]*/start\)@\(/bin/[A-Za-z0-9._-]*\)$|\1 \2|p' > "$LINKS"
rm -rf "$EXTRA.bundle"
echo "republish-hp: ${#PROGS[@]} overlay programs, $(wc -l < "$LINKS") app links"
[ -n "${HP_SAME_KERNEL:-}" ] && export FEED_KERNEL="$HP_BASE/osum.mb"
OVL_EXTRA_DIR="$EXTRA" OVL_LINKS="$LINKS" bash tools/ota/publish-hp.sh "$IMG" "$NOTES" "${PROGS[@]}" $DRY
rm -f "$IMG.log"
