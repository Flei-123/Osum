#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/glass/run.sh -- W-GLASS gate: frosted glass on the lock and sign-in screens (pixels, tools/glass/check.py).
#   /root/jarvis/bin/heavy bash tools/glass/run.sh            all cases (one VM boot each)
#   CASES="glogin-light" bash tools/glass/run.sh              some cases
# Cases: glogin-light, lock-dark (field variance/soft/border/surround on the sea wallpaper), caret (burst: the caret bar toggles
# inside the glass field), noglass (control: /etc/noglass -> the variance check must turn RED).
# STATUS: written, NOT yet run (heavy queue was full); first run may need threshold tuning in check.py.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT
export OSUM_RTC="base=2026-10-11T11:00:00,clock=vm"
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
echo on > "$OUT/uiblink"; echo 1 > "$OUT/flag"
printf 'warte 6\ntippe ab\nwarte 1\nserie idle 120 blink 25\nfoto done\n' > "$OUT/book"
run_case() { # name app mode [extra xfile...]
    local nm=$1 app=$2 mode=$3; shift 3
    bash tools/alltag/build.sh "$OUT/$nm" mode="$mode" kbd=yes uitrace=yes warten=12 bloecke=32768 \
        extra="wigapp=/bin/$app wighalt=100" progs="$app theme sh echo ls cat" \
        xfile=/etc/shadow="$OUT/shadow" xfile=/etc/uiblink="$OUT/uiblink" passwdfile="$OUT/passwd" \
        xfile=/etc/wallpaper=assets/wallpaper-sea.osym "$@" \
        mon=warte\ 3 mon=sendkey\ a mon=warte\ 1 mon=sendkey\ b mon=warte\ 1 mon=sendkey\ c mon=warte\ 1 mon=mouse_move\ -4000\ -4000 mon=warte\ 1 \
        > "$OUT/$nm.log" 2>&1
    [ -s "$OUT/$nm/desktop.ppm" ] || { echo "  FAIL  $nm: no screenshot"; fail=$((fail+1)); return 1; }
}
judge() { # text exit
    if [ "$2" = 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); fi
}
for c in ${CASES:-glogin-light lock-dark glogin-strong glogin-off noglass caret}; do
    echo "== $c"
    case "$c" in
      glogin-light) run_case "$c" glogin light && { python3 -I tools/glass/check.py field "$OUT/$c" glogin "$c" | tee "$OUT/$c.txt"; pass=$((pass+$(grep -c '^  OK' "$OUT/$c.txt"))); fail=$((fail+$(grep -c '^  FAIL' "$OUT/$c.txt"))); } ;;
      lock-dark)    run_case "$c" lock dark && { python3 -I tools/glass/check.py field "$OUT/$c" lock "$c" | tee "$OUT/$c.txt"; pass=$((pass+$(grep -c '^  OK' "$OUT/$c.txt"))); fail=$((fail+$(grep -c '^  FAIL' "$OUT/$c.txt"))); } ;;
      glogin-strong) # counter-proof: transparency=strong = the old raw look, judged by the old (stricter) limits
        printf 'transparency=strong\n' > "$OUT/strong.conf"
        run_case "$c" glogin light xfile=/etc/theme.conf="$OUT/strong.conf" && { python3 -I tools/glass/check.py field "$OUT/$c" glogin "$c" strong | tee "$OUT/$c.txt"; pass=$((pass+$(grep -c '^  OK' "$OUT/$c.txt"))); fail=$((fail+$(grep -c '^  FAIL' "$OUT/$c.txt"))); } ;;
      glogin-off)    # control: transparency=off = opaque, no blur: the variance check must turn red
        printf 'transparency=off\n' > "$OUT/off.conf"
        run_case "$c" glogin light xfile=/etc/theme.conf="$OUT/off.conf" && { python3 -I tools/glass/check.py field "$OUT/$c" glogin "$c" flat | tee "$OUT/$c.txt"; judge x $?; } ;;
      noglass)      run_case "$c" glogin light xfile=/etc/noglass="$OUT/flag" && { python3 -I tools/glass/check.py field "$OUT/$c" glogin "$c" flat | tee "$OUT/$c.txt"; judge x $?; } ;;
      caret)
        run_case "$c" glogin light drive="$OUT/book" || continue
        R=$(grep -a "glogin: rect id=7 kind=4" "$OUT/$c/serial.txt" | tail -1 | sed 's/.* x=\([0-9]*\) y=\([0-9]*\) w=\([0-9]*\) h=\([0-9]*\).*/\1 \2 \3 \4/'); set -- $R
        [ $# = 4 ] || { echo "  FAIL  caret: no field rect"; fail=$((fail+1)); continue; }
        python3 -I tools/glass/check.py caret "$OUT/$c" blink $(($1+6)) $(($2+6)) $(($1+$3-6)) $(($2+$4-6)) light | tee "$OUT/$c.txt"
        t=$(grep -a '^TRANSITIONS' "$OUT/$c.txt" | cut -d' ' -f2)
        if [ "${t:-0}" -ge 2 ]; then echo "  OK    caret toggles inside the glass field ($t changes)"; pass=$((pass+1)); else echo "  FAIL  caret does not toggle ($t changes)"; fail=$((fail+1)); fi ;;
    esac
    rm -rf "$OUT/$c"
done
echo "GLASS: $pass passed, $fail failed"
[ "$fail" = 0 ]
