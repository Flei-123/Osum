#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/lockflicker/run.sh -- W-LOCK2: the lock screen and the login screen are laid out ONCE-scaled at interface scale 1 and 2, and a burst of
# frames after a click into the empty screen shows no flicker.
#
#   /root/jarvis/bin/heavy bash tools/lockflicker/run.sh                 all cases (each one VM boot, about 3-6 min)
#   CASES="lock-3440x1440-s2 glogin-3440x1440-s2" bash tools/lockflicker/run.sh
#
# Case names: <lock|glogin>-<W>x<H>-s<scale>[-old][-tcg]
#   per case: layout measurement (check.py: entry rect inside the screen and centred, entry width 240 * scale, avatar disc complete and centred,
#   name text in the column) from serial `<app>: rect` lines + the screendump, then a burst series (`serie click 60`, drive.py) into the empty
#   screen compared frame by frame with the picture `pre` (taken after moving the pointer, before the click) (series.py).
#   -old   writes /etc/lockold: the old DOUBLE scaling comes back (signin.lay_mul) = COUNTER-PROOF, the layout check must turn RED.
#   -tcg   QEMU without KVM (slow painting, wide window for a compositor pull in the middle of a repaint).
# The series only counts as FLICKER when frames really differ; otherwise the result is "no flicker measured".
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
export OSUM_RTC="base=2026-10-11T11:00:00,clock=vm"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

python3 - "$TMPD" <<'PY'
import binascii, hashlib, sys
d = sys.argv[1]
it, salt = 1024, bytes(range(8))
dk = hashlib.pbkdf2_hmac("sha256", b"geheim12", salt, it, 32)
rec = "$osum1$%d$%s$%s" % (it, binascii.hexlify(salt).decode(), binascii.hexlify(dk).decode())
open(d + "/shadow", "w").write("root:%s:0:0:99999:7:::\njustin:%s:1000:1000:99999:7:::\n" % (rec, rec))
open(d + "/passwd", "w").write("root:x:0:0:root:/root:/bin/sh\njustin:x:1000:1000:Justin:/users/justin:/bin/sh\n")
open(d + "/old", "w").write("1\n")
PY

for c in ${CASES:-lock-1920x1080-s1 glogin-1920x1080-s1 lock-3440x1440-s2 glogin-3440x1440-s2 lock-1280x800-s2 glogin-1280x800-s2 lock-3440x1440-s2-old glogin-3440x1440-s2-old}; do
    app=${c%%-*}; rest=${c#*-}; res=${rest%%-*}; rest=${rest#*-}; sc=${rest%%-*}; sc=${sc#s}
    old=0; tcg=0; blink=0
    case "$c" in *-blink*) blink=1 ;; esac
    direct=0; case "$c" in *-direct*) direct=1 ;; esac
    eyeold=0; case "$c" in *-eyeold*) eyeold=1 ;; esac
    case "$c" in *-old*) old=1 ;; esac
    case "$c" in *-tcg*) tcg=1 ;; esac
    W=${res%x*}; H=${res#*x}
    px=$((W / 5)); py=$((H * 4 / 5))
    smode=click; [ $blink = 1 ] && smode=move
    [ $blink = 1 ] && px=$((W * 3 / 4)) && py=$((H / 2))
    printf 'warte 5\nfoto base\nfahre %d,%d\nwarte 1\nfoto pre\nschritt click\nserie %s 60 c\nwarte 2\nfoto post\n' "$px" "$py" "$smode" > "$TMPD/$c.book"
    echo "== case $c ($res, scale $sc, old=$old, tcg=$tcg) =="
    acc=kvm; [ $tcg = 1 ] && acc=tcg
    xo=(); [ $old = 1 ] && xo=(xfile=/etc/lockold="$TMPD/old")
    # -blink: the caret blinks (/etc/uiblink) and every picture is logged (/etc/paintlog) = the real machine's repaint rhythm
    xo+=(xfile=/etc/paintlog="$TMPD/old")
    [ $blink = 1 ] && xo+=(xfile=/etc/uiblink="$TMPD/old")
    [ $direct = 1 ] && xo+=(xfile=/etc/paintdirect="$TMPD/old")
    [ $eyeold = 1 ] && xo+=(xfile=/etc/eyeold="$TMPD/old")
    OSUM_ACCEL=$acc bash tools/alltag/build.sh "$TMPD/$c" kbd=yes uitrace=yes warten=6 res="$res" uiscale="$sc" bloecke=32768 \
        extra="wigapp=/bin/$app wighalt=100" progs="$app theme sh echo ls cat" xfile=/etc/shadow="$TMPD/shadow" \
        xfile=/etc/wallpaper=assets/wallpaper-sea.osym passwdfile="$TMPD/passwd" "${xo[@]}" drive="$TMPD/$c.book" > "$TMPD/$c.log" 2>&1
    if [ ! -f "$TMPD/$c/base.ppm" ] || [ ! -f "$TMPD/$c/serial.txt" ]; then bad "case $c: no picture/serial (build or boot failed)"; tail -3 "$TMPD/$c.log"; continue; fi
    python3 -I tools/lockflicker/check.py "$TMPD/$c" "$app" "$W" "$H" "$sc" > "$TMPD/$c.chk" 2>&1; rc=$?
    sed 's/^/        /' "$TMPD/$c.chk"
    if [ $eyeold = 1 ]; then
        python3 -I tools/lockflicker/icons.py "$TMPD/$c" "$app" "$W" "$H" "$sc" > "$TMPD/$c.ico" 2>&1; ri=$?
        sed 's/^/        /' "$TMPD/$c.ico"
        [ $ri = 1 ] && ok "case $c (counter-proof eyeold): the icon check turns red" || bad "case $c: counter-proof did not turn red (rc=$ri) -- the icon check is blind"
    elif [ $old = 0 ]; then
        [ $rc = 0 ] && ok "case $c: layout inside the screen, centred, scaled once" || bad "case $c: layout wrong (rc=$rc)"
        python3 -I tools/lockflicker/icons.py "$TMPD/$c" "$app" "$W" "$H" "$sc" > "$TMPD/$c.ico" 2>&1; ri=$?
        sed 's/^/        /' "$TMPD/$c.ico"
        [ $ri = 0 ] && ok "case $c: every symbol sits in the middle of its tile (<= 1 px)" || bad "case $c: a symbol is off the middle of its tile (rc=$ri)"
        mp=0; [ $blink = 1 ] && mp=$((260 * sc * sc))   # blink: the caret (two bars) may change, the middle may not
        python3 -I tools/lockflicker/series.py "$TMPD/$c" pre c "$px" "$py" $mp > "$TMPD/$c.ser" 2>&1; rs=$?
        tail -4 "$TMPD/$c.ser" | sed 's/^/        /'
        case $rs in
          0) ok "case $c: burst series ($smode): no frame differs (no flicker measured)" ;;
          1) bad "case $c: burst series: frames DIFFER (flicker measured)" ;;
          *) bad "case $c: burst series produced no frames" ;;
        esac
        if [ $blink = 0 ]; then
            python3 -I tools/lockflicker/paints.py "$TMPD/$c" 0 -1 > "$TMPD/$c.pnt" 2>&1; rp=$?
            sed 's/^/        /' "$TMPD/$c.pnt"
            [ $rp = 0 ] && ok "case $c: a click into the empty screen shows no new picture (frames shown after a click into the empty screen == 0)" || bad "case $c: click into the empty screen shows a picture (rc=$rp)"
        else
            python3 -I tools/lockflicker/paints.py "$TMPD/$c" -1 -1 > "$TMPD/$c.pnt" 2>&1
            sed 's/^/        /' "$TMPD/$c.pnt"
        fi
    else
        [ $rc = 1 ] && ok "case $c (counter-proof lockold): the layout check turns red" || bad "case $c: counter-proof did not turn red (rc=$rc) -- the check is blind"
    fi
    if [ -n "${KEEP:-}" ]; then mkdir -p "$KEEP/$c"; cp "$TMPD/$c/base.ppm" "$TMPD/$c/pre.ppm" "$TMPD/$c/post.ppm" "$TMPD/$c/c-000.ppm" "$TMPD/$c/c-030.ppm" "$TMPD/$c/c-031.ppm" "$TMPD/$c/c-059.ppm" "$TMPD/$c/serial.txt" "$KEEP/$c/" 2>/dev/null; cp "$TMPD/$c.chk" "$TMPD/$c.ser" "$KEEP/$c/" 2>/dev/null; fi
    rm -rf "$TMPD/$c"
done
echo "LOCKFLICKER: $pass passed, $fail failed"
[ "$fail" = 0 ]
