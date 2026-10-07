#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/screens.sh -- r399 design audit: ONE PROGRAM PER MACHINE, ONE PICTURE EACH.
#
#   bash tools/design/screens.sh <outdir> [name:program ...]
#
# The lock screen, the sign-in screen, the editor, the task manager and the
# calculator are whole-screen or standalone programs; the desktop script
# (tools/design/audit.sh) does not reach them.  Each one boots alone through
# tools/alltag/build.sh (`wigapp=`), the same way the test runners of the scene
# programs (tools/lockscene, tools/loginscene) start them, with the sea
# wallpaper and a shadow file with one account, and leaves <outdir>/<name>.png.
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
OUT=${1:?usage: screens.sh <outdir> [name:program ...]}
shift || true
mkdir -p "$OUT"
LIST=("$@")
[ ${#LIST[@]} -eq 0 ] && LIST=(lock:lock login:glogin editor:edit nedit:nedit taskmgr:taskmgr calc:calc)
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
# older trees have no passwdfile= option
PWOPT=()
grep -q "passwdfile=" tools/alltag/build.sh && PWOPT=(passwdfile="$OUT/passwd")
python3 - "$OUT" <<'PY'
import binascii, hashlib, sys
d = sys.argv[1]
it, salt = 1024, bytes(range(8))
dk = hashlib.pbkdf2_hmac("sha256", b"geheim12", salt, it, 32)
rec = "$osum1$%d$%s$%s" % (it, binascii.hexlify(salt).decode(), binascii.hexlify(dk).decode())
open(d + "/shadow", "w").write("justin:%s:1000:0:99999:7:::\nroot:%s:0:0:99999:7:::\n" % (rec, rec))
open(d + "/passwd", "w").write("root:x:0:0:root:/root:/bin/sh\njustin:x:1000:1000:Justin:/users/justin:/bin/sh\n")
PY
for it in "${LIST[@]}"; do
    nm=${it%%:*}; app=${it#*:}
    {
        bash tools/alltag/build.sh "$OUT/$nm" accel=$ACC uitrace=yes warten=12 bloecke=32768 \
            extra="wigapp=/bin/$app wighalt=60" progs="$app theme sh echo ls cat" \
            xfile=/etc/shadow="$OUT/shadow" xfile=/etc/wallpaper=assets/wallpaper-sea.osym \
            ${PWOPT[@]+"${PWOPT[@]}"} > "$OUT/$nm.log" 2>&1
        for f in "$OUT/$nm/desktop.png" "$OUT/$nm/shot.png" "$OUT/$nm/screen.png"; do
            [ -s "$f" ] && cp "$f" "$OUT/$nm.png" && break
        done
        echo "$nm: $(ls "$OUT/$nm.png" 2>/dev/null || echo 'no picture')"
    }
done
