#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/marke-env.sh"
# SPDX-License-Identifier: GPL-2.0-only
# tools/ota/feed-dev.sh -- publish the CURRENT checkout as the next stand of the live feed
# system/dev (https://store.fleitec.com/osum/system/dev) and verify it. Recipe of docs/OTA-FEED.md
# section 4; first used 20.10.2026.
#
#   bash tools/ota/feed-dev.sh <full-image-dir> "<notes text>" [prog ...] [--dry]
#
# <full-image-dir>  result of `ODB=1 PARTTAB=mbr FS_BLOCKS=122880 IMAGE_ID=x ODB_TOKEN_FILE=... bash
#                   tools/usbimg/build.sh <dir>` of THIS checkout (via /root/jarvis/bin/heavy); it holds <prog>.elf.
# prog ...          the /bin programs that changed since the stand the devices run (the overlay, flat, as
#                   <prog>.elf; each ~0.5 MB gz, the device must have the space for the final sizes).
# OVL_EXTRA_DIR     optional dir copied into the overlay as is: top-level files are /bin names, subdirectories
#                   are absolute destinations (apps/x.osp/start -> /apps/x.osp/start, etc/..., usr/share/...).
# OVL_LINKS         optional file of "<dest> /bin/<name>" lines: <dest> becomes a second name of the new /bin file.
# --dry             build + sign into a temp copy of the feed and verify, publish nothing.
#
# Steps: kernel via build-kernel.sh (--stufe 0) into a dir that holds ONLY osum.mb (a root.img there adds a
# `sysfile root` line that is never served); overlay dir = <prog>.elf copies; publish-system.sh with
# --count $(git rev-list --count HEAD) --gz; then Ed25519 check of VERZEICHNIS against
# system/dev/schluessel.pub, all sysfile/sysgz hashes, and aktuell/ v/ pakete/ register.json unchanged.
# NEVER rsync --delete against /srv/store/osum.
set -euo pipefail
cd "$(dirname "$0")/../.."
[ $# -ge 2 ] || { sed -n 2,19p "$0"; exit 2; }
IMGDIR=$1; NOTES=$2; shift 2
DRY=0; PROGS=()
for a in "$@"; do if [ "$a" = "--dry" ]; then DRY=1; else PROGS+=("$a"); fi; done
FEED=/srv/store/osum
CHANNEL=${CHANNEL:-dev}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
git diff --quiet HEAD -- . || { echo "feed-dev: working tree not clean (commit first, the stand names the commit)"; exit 1; }
COUNT=$(git rev-list --count HEAD)

bash vendor/firn/fetch-firnc.sh > /dev/null
mkdir -p "$T/k" "$T/ovl"
bash tools/build-kernel.sh "$T/k/osum.mb" --stufe 0 > "$T/k.log" 2>&1 || { tail -5 "$T/k.log"; exit 1; }
for p in "${PROGS[@]}"; do
    [ -s "$IMGDIR/$p.elf" ] || { echo "feed-dev: $IMGDIR/$p.elf missing"; exit 1; }
    cp "$IMGDIR/$p.elf" "$T/ovl/$p"
done
if [ -n "${OVL_EXTRA_DIR:-}" ]; then cp -a "$OVL_EXTRA_DIR/." "$T/ovl/"; fi
printf '%s\n' "$NOTES" > "$T/notes.txt"

# checksums of the package feed BEFORE (must be identical after)
sums() { (cd "$FEED" && find aktuell v pakete register.json -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16); }
BEFORE=$(sums)

TARGET=$FEED
if [ "$DRY" = 1 ]; then TARGET=$T/feed; mkdir -p "$TARGET/system"; cp -a "$FEED/system/$CHANNEL" "$TARGET/system/$CHANNEL" 2>/dev/null || true; fi
ARGS=(--count "$COUNT" --gz --notes "$T/notes.txt" --name "${MARKE_PRODUKT} $CHANNEL")
if [ -n "$(ls -A "$T/ovl")" ]; then ARGS+=(--overlay "$T/ovl"); fi
if [ -n "${OVL_LINKS:-}" ]; then ARGS+=(--links "$OVL_LINKS"); fi
bash tools/ota/publish-system.sh "$T/k" "$TARGET" "$CHANNEL" "${ARGS[@]}"

D=$TARGET/system/$CHANNEL
python3 -I - "$D" "$FEED/aktuell/schluessel.pub" <<'PYEOF'
import hashlib, importlib.util, os, sys
d, pubf = sys.argv[1], sys.argv[2]
sys.path.insert(0, "tools/ota")
spec = importlib.util.spec_from_file_location("listing", "tools/ota/listing.py")
L = importlib.util.module_from_spec(spec); spec.loader.exec_module(L)
m = L.load_opk()
doc = open(os.path.join(d, "VERZEICHNIS"), "rb").read()
sig = open(os.path.join(d, "VERZEICHNIS.sig"), "rb").read()
pub = open(pubf, "rb").read()
assert m.ed25519_verify(pub, doc, sig), "VERZEICHNIS signature INVALID"
n = 0
for line in doc.decode().splitlines():
    f = line.split("\t")
    if f[0] == "sysfile":
        p = os.path.join(d, f[4]); want, size = f[2], int(f[3])
    elif f[0] == "sysgz":
        p = os.path.join(d, f[4]); want, size = f[2], int(f[3])
    else:
        continue
    b = open(p, "rb").read()
    assert len(b) == size and hashlib.sha256(b).hexdigest() == want, "hash/size mismatch: " + f[4]
    n += 1
print("verify OK: signature valid, %d files match their hashes" % n)
print(doc.decode().splitlines()[2])
print("VERZEICHNIS octets: %d of 32767 (client buffer)" % len(doc))
assert len(doc) < 32000, "VERZEICHNIS too large for the 32 KiB client buffer"
PYEOF
AFTER=$(sums)
[ "$BEFORE" = "$AFTER" ] && echo "package feed unchanged ($AFTER)" || { echo "feed-dev: aktuell/v/pakete CHANGED ($BEFORE -> $AFTER)"; exit 1; }
[ "$DRY" = 1 ] && echo "(dry run, nothing published)" || echo "published: $(head -4 "$D/VERZEICHNIS" | tail -1 | cut -c1-80)"
