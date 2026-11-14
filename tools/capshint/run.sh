#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
[ -w /dev/kvm ] && export OSUM_ACCEL=kvm
OUT=${1:-$(mktemp -d)}
[ -n "${1:-}" ] || trap 'rm -rf "$OUT"' EXIT
mkdir -p "$OUT"
B=tools/alltag/build.sh
pass=0; fail=0

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

shot() { # shot <tree> <name> <app> <mode>
    local tree=$1 nm=$2 app=$3 mode=$4
    cat > "$OUT/$nm.txt" <<'SEOF'
warte 12
foto off
taste caps_lock
warte 3
foto on
taste caps_lock
warte 3
foto twice
SEOF
    (cd "$tree" && FIRNLIB="$tree/lib" EH_MKFS_EXTRA="/proc/" DESIGNBUILD="$OUT/$nm.build" \
        bash tools/design/eh6.sh "$OUT/$nm" res=1280x800 accel=kvm tafel=nein mode="$mode" \
        moreprogs="$app" "extra=vfs wigapp=/bin/$app wighalt=100 lang=en" \
        xfile=/etc/shadow="$OUT/shadow" xfile=/etc/uiblink="$OUT/uiblink" \
        xfile=/etc/wallpaper="$tree/assets/wallpaper-sea.osym" \
        drehbuch="$OUT/$nm.txt" > "$OUT/$nm.log" 2>&1)
    rm -rf "$OUT/$nm.build"
}

judge() { # judge <label> <mode> <off> <on>
    echo "== $1"
    if [ ! -s "$OUT/$3" ] || [ ! -s "$OUT/$4" ]; then
        echo "  FAIL  no screenshot"; fail=$((fail+1)); return
    fi
    python3 -I tools/capshint/check.py "$2" "$OUT/$3" "$OUT/$4" | tee "$OUT/judge.txt"
    pass=$((pass + $(grep -c '^  OK' "$OUT/judge.txt")))
    fail=$((fail + $(grep -c '^  FAIL' "$OUT/judge.txt")))
}

OLD=$(mktemp -d)
cleanup() { git worktree remove --force "$OLD/tree" >/dev/null 2>&1; rm -rf "$OLD"; [ -n "${1:-}" ] || true; }
trap 'cleanup; [ -n "${1:-}" ] || rm -rf "$OUT"' EXIT
git worktree add --detach "$OLD/tree" origin/main >/dev/null 2>&1

for app in glogin lock; do
    for mode in light dark; do
        nm="$app-$mode"
        shot "$ROOT" "$nm" "$app" "$mode"
        judge "$app $mode: caps on shows the hint" show "$nm/off.ppm" "$nm/on.ppm"
        judge "$app $mode: caps off again hides it" same "$nm/off.ppm" "$nm/twice.ppm"
    done
done
shot "$OLD/tree" glogin-old glogin light
judge "glogin old kernel: counter-proof, no hint" same glogin-old/off.ppm glogin-old/on.ppm

echo; echo "CAPSHINT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
