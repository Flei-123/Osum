#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/winfloatlock/run.sh -- W-WINOPTS stage 2 follow-up: A FLOAT WINDOW (L_FLOAT) LIES BEHIND THE LOCK SCREEN.
#
#   bash tools/winfloatlock/run.sh [<workdir>]        (start it through /root/jarvis/bin/heavy)
#
# Same idea as tools/lockseal/run.sh, in the desktop image of tools/alltag: /bin/floatlock (kernel/user/floatlock.fi) makes a red 300x200
# window of a labelled app (app:fprobe, uid 1000, right `window.float` granted) on the layer L_FLOAT at (700,100) and starts the lock screen
# (/bin/lock) 12 s later. The host takes photos through tools/design/drive.py.
#   1. baseline   before the lock the float window sits on L_FLOAT (c-float 0 8) and the photo shows its red area
#   2. locked     the same screen area has no red at all (also after clicks into it); the window never fell back to L_NORMAL
#   3. unlock     the password opens the lock; the float window is red again (the seal is no demolition)
set -uo pipefail
cd "$(dirname "$0")/../.."
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }

if [ -n "${1:-}" ]; then D=$1; mkdir -p "$D"; else D=$(mktemp -d); trap 'rm -rf "$D"' EXIT; fi
[ -w /dev/kvm ] && export OSUM_ACCEL=kvm

# the account: root with the password geheim12
python3 - "$D" <<'PYEOF'
import binascii, hashlib, sys
d = sys.argv[1]
it, salt = 1024, bytes(range(8))
dk = hashlib.pbkdf2_hmac("sha256", b"geheim12", salt, it, 32)
rec = "$osum1$%d$%s$%s" % (it, binascii.hexlify(salt).decode(), binascii.hexlify(dk).decode())
open(d + "/shadow", "w").write("root:%s:0:0:99999:7:::\n" % rec)
PYEOF

cat > "$D/book" <<'EOF'
warteauf floatlock: c-layer 8 || 150
warte 3
foto pre
warteauf sperre: bereit || 90
warte 3
foto b
klick 850,150
klick 850,230
foto c
taste g
taste e
taste h
taste e
taste i
taste m
taste 1
taste 2
taste ret
warteauf sperre: aufgesperrt || 60
warte 3
foto d
warte 1
EOF

echo "== build + run: float window, lock, photos =="
bash tools/alltag/build.sh "$D/w1" kbd=yes accel=kvm shot=no uitrace=no bloecke=32768 \
    "extra=wigapp=/bin/floatlock wighalt=260" progs="floatlock lock sh echo" \
    xfile=/etc/shadow="$D/shadow" drive="$D/book" > "$D/w1.log" 2>&1
S="$D/w1/serial.txt"
if [ ! -s "$S" ]; then
    grep -a "FEHLGESCHLAGEN\|error" "$D/w1.log" | head -5
    bad "no serial output"
fi
[ -n "${FLOATLOCK_KEEP:-}" ] && tr -cd '\11\12\15\40-\176' < "$S" > "$FLOATLOCK_KEEP"
grep -a '^floatlock:' "$S" | sed 's/^/        /'
for q in "$D/w1"/*.ppm; do
    [ -s "$q" ] && python3 -c "from PIL import Image; Image.open('$q').save('${q%.ppm}.png')" 2>/dev/null
done

echo "== 1. baseline: the float window before the lock =="
has "$S" "floatlock: p-grant 1" "the person granted window.float to app:fprobe"
has "$S" "floatlock: c-float 0 8" "the labelled app got L_FLOAT (WI_LAYER 8)"
has "$S" "floatlock: p-lock 1" "the lock screen was started"
has "$S" "sperre: bereit" "the lock screen is up"
hasnot "$S" "floatlock: c-layer 1" "the float window never left L_FLOAT (no fall back to L_NORMAL)"

echo "== 2. the photos =="
cat > "$D/px.py" <<'PYEOF'
import sys
from PIL import Image
from collections import Counter
d = sys.argv[1]
def load(n):
    try: return Image.open("%s/%s.png" % (d, n)).convert("RGB")
    except Exception: return None
box = (720, 130, 980, 280)    # inside the float window (700,100, 300x200)
def stats(x):
    raw = x.crop(box).tobytes()
    px = [raw[i:i+3] for i in range(0, len(raw), 3)]
    red = sum(1 for p in px if abs(p[0]-204) <= 24 and p[1] <= 24 and p[2] <= 24)
    top = Counter(px).most_common(1)[0]
    warm = sum(1 for p in px if p[0] > 120 and p[0] > p[1] + 60)
    return 100.0 * red / len(px), 100.0 * warm / len(px), tuple(top[0])
def same(x, y):
    bx, by = x.tobytes(), y.tobytes()
    n = len(bx) // 3
    diff = sum(1 for i in range(0, len(bx), 3)
               if abs(bx[i]-by[i]) + abs(bx[i+1]-by[i+1]) + abs(bx[i+2]-by[i+2]) > 24)
    return 100.0 - 100.0 * diff / n
imgs = dict((n, load(n)) for n in ("pre", "b", "c", "d"))
for n in ("pre", "b", "c", "d"):
    if imgs[n] is None:
        print("MISSING", n)
    else:
        r, dom, col = stats(imgs[n])
        print("RED_%s %.1f %.1f colour=%d,%d,%d" % ((n, r, dom) + col))   # field 3 = share of warm (red-ish) pixels
if imgs["b"] is not None and imgs["c"] is not None:
    print("B_VS_C %.1f" % same(imgs["b"], imgs["c"]))
PYEOF
python3 "$D/px.py" "$D/w1" > "$D/shot.txt" 2>&1
sed 's/^/        /' "$D/shot.txt"
pv() { grep -a "^$1 " "$D/shot.txt" | awk -v f="$2" '{print $f}'; }
gt()  { [ -n "$1" ] && awk -v v="$1" -v t="$2" 'BEGIN{exit !(v>t)}'; }
lt()  { [ -n "$1" ] && awk -v v="$1" -v t="$2" 'BEGIN{exit !(v<t)}'; }
gt "$(pv RED_pre 2)" 95 && ok "before the lock the float window's area is red ($(pv RED_pre 2) %)" || bad "before the lock the area is not red ('$(pv RED_pre 2)' %)"
lt "$(pv RED_b 2)" 1 && ok "at the lock none of the float window shows through (red: $(pv RED_b 2) %)" || bad "at the lock the float window shows through ('$(pv RED_b 2)' % red)"
lt "$(pv RED_b 3)" 1 && ok "at the lock the same area has no red-ish pixel at all ($(pv RED_b 3) % warm)" || bad "at the lock the area has red-ish pixels ('$(pv RED_b 3)' % warm)"
lt "$(pv RED_c 2)" 1 && ok "after the clicks into the area: still no red ($(pv RED_c 2) %)" || bad "after the clicks the float window shows ('$(pv RED_c 2)' % red)"
gt "$(pv B_VS_C 2)" 97 && ok "the locked screen after the clicks looks as before them ($(pv B_VS_C 2) % equal)" || bad "the locked screen changed by the clicks ('$(pv B_VS_C 2)' % equal)"

echo "== 3. the password opens it, the float window is back =="
has "$S" "sperre: aufgesperrt" "the right password unlocks"
gt "$(pv RED_d 2)" 95 && ok "unlocked again: the float window is red again ($(pv RED_d 2) %)" || bad "unlocked: the area is not red ('$(pv RED_d 2)' %)"

echo; echo "FLOATLOCK: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
