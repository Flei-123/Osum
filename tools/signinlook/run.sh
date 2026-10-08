#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/signinlook/run.sh -- r470: SIGN-IN SCREEN AND LOCK SCREEN, LIGHT AND DARK,
# MEASURED (contrast ratios, not a look at the picture).
#
#   bash tools/signinlook/run.sh [<out dir>]
#
# Boots /bin/glogin and /bin/lock on a small disk, once in the light and once
# in the dark scheme, with the sea wallpaper (the shipped one) and, for two
# cases, without it (the flat gradient). Three keys are typed so that the
# password field shows dots, and the pointer is parked in the top left corner. The screenshot goes through tools/check.py:
# text contrast against the worst part of the picture under it, glyphs on
# their faces, the milk-glass plates, the field's edge, no clipped text.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
[ -w /dev/kvm ] && export OSUM_ACCEL=kvm
OUT=${1:-$(mktemp -d)}
[ -n "${1:-}" ] || trap 'rm -rf "$OUT"' EXIT
mkdir -p "$OUT"
B=tools/alltag/build.sh

python3 - "$OUT" <<'PY'
import binascii, hashlib, sys
d = sys.argv[1]
it, salt = 1024, bytes(range(8))
dk = hashlib.pbkdf2_hmac("sha256", b"geheim12", salt, it, 32)
rec = "$osum1$%d$%s$%s" % (it, binascii.hexlify(salt).decode(), binascii.hexlify(dk).decode())
open(d + "/shadow", "w").write("justin:%s:1000:0:99999:7:::\nroot:%s:0:0:99999:7:::\n" % (rec, rec))
open(d + "/passwd", "w").write("root:x:0:0:root:/root:/bin/sh\njustin:x:1000:1000:Justin:/users/justin:/bin/sh\n")
PY
echo on > "$OUT/uiblink"

pass=0; fail=0
one() { # one <app> <mode> <wallpaper yes|no>
    local app=$1 mode=$2 wp=$3
    local nm="$app-$mode-$([ "$wp" = yes ] && echo sea || echo flat)"
    local W=()
    [ "$wp" = yes ] && W=(xfile=/etc/wallpaper=assets/wallpaper-sea.osym)
    bash "$B" "$OUT/$nm" mode="$mode" kbd=yes uitrace=yes warten=12 bloecke=32768 \
        extra="wigapp=/bin/$app wighalt=100" progs="$app theme sh echo ls cat" \
        xfile=/etc/shadow="$OUT/shadow" xfile=/etc/uiblink="$OUT/uiblink" \
        passwdfile="$OUT/passwd" "${W[@]}" \
        mon=warte\ 3 mon=sendkey\ a mon=warte\ 1 mon=sendkey\ b mon=warte\ 1 mon=sendkey\ c mon=warte\ 1 mon=mouse_move\ -4000\ -4000 mon=warte\ 1 \
        > "$OUT/$nm.log" 2>&1
    echo "== $nm"
    if [ ! -s "$OUT/$nm/desktop.ppm" ]; then
        echo "  FAIL  no screenshot"; fail=$((fail+1)); return
    fi
    python3 tools/signinlook/check.py "$OUT/$nm" "$app" "$nm" | tee "$OUT/$nm.txt"
    pass=$((pass + $(grep -c '^  OK' "$OUT/$nm.txt")))
    fail=$((fail + $(grep -c '^  FAIL' "$OUT/$nm.txt")))
}
for app in glogin lock; do
    for mode in light dark; do
        one "$app" "$mode" yes
    done
done
one glogin light no
one lock dark no

echo; echo "SIGNINLOOK: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
