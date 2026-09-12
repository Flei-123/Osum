#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/r5.sh -- R5: LAEUFT ETWAS UNTER DIE TASKLEISTE?
#
#   bash tools/design/r5.sh [kern.mb] [wurzel.img] [ausgabe]
#
# Justin: "search programs overlapped mit der taskbar und das soll
# nicht sein, sondern wie bei windows drueber sein."
#
# Gemessen werden ZWEI Zahlen und ihr Abstand, nicht der Eindruck:
#
#   Unterkante des Suchfensters   (launcher: geom y= + h=)
#   Oberkante der Taskleiste      (Schirmhoehe - taskbar: conf height=)
#
# Dasselbe fuer ein MAXIMIERTES Fenster: auch das darf nicht unter die
# Leiste laufen. Beides in 3440x1440, Justins Aufloesung.
set -uo pipefail
cd "$(dirname "$0")/../.."
KERN=${1:-/tmp/r5b-k.mb}
WURZEL=${2:-/tmp/img2/root.img}
W=${3:-/tmp/r5mess}
rm -rf "$W"; mkdir -p "$W"
cp "$WURZEL" "$W/disk.img"

cat > "$W/drehbuch.txt" <<'DREH'
warteauf launcher: ready || 120
warte 6
taste meta_l
warte 4
foto 01-suchfenster
taste esc
warte 2
taste meta_l
warte 2
taste s
taste e
taste t
warte 2
klickauf lzeile0
warte 6
foto 02-fenster-offen
DREH

qemu-system-x86_64 -kernel "$KERN" -m 2048 \
  -append "osum gfx disp fbres=3440x1440 wm wig desk wmshell wmdauer herz absturzhalt nopuls tz=120 lang=en usb hidgen modfs nosched noproc nofs" \
  -serial "file:$W/serial.txt" -display none -no-reboot \
  -device "VGA,edid=on,xres=3440,yres=1440,vgamem_mb=128" \
  -drive "file=$W/disk.img,format=raw,if=ide,index=0" \
  -monitor "unix:$W/mon,server,nowait" > "$W/qemu.log" 2>&1 &
QP=$!
sleep 3
python3 tools/design/drive.py "$W/mon" "$W/serial.txt" "$W" \
    "$W/drehbuch.txt" > "$W/fahren.log" 2>&1 || true
kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null

echo "== gemeldete Geometrien =="
grep -aE 'launcher: geom|taskbar: conf|settings: ready' "$W/serial.txt" \
    | head -4 | sed 's/^/   /'
echo

python3 - "$W/serial.txt" <<'PY'
import re, sys
t = open(sys.argv[1], 'rb').read().decode('utf-8', 'replace')
SH = 1440
m = re.search(r'launcher: geom x=(\d+) y=(\d+) w=(\d+) h=(\d+)', t)
c = re.search(r'taskbar: conf edge=\d+ ename=\w+ height=(\d+)', t)
if not m or not c:
    print("  konnte die Zahlen nicht lesen"); sys.exit(1)
x, y, w, h = (int(v) for v in m.groups())
bar = int(c.group(1))
ok = SH - bar
unten = y + h
print("  Schirmhoehe                 %d" % SH)
print("  Taskleiste hoch             %d   -> Oberkante y=%d" % (bar, ok))
print("  Suchfenster y=%d h=%d       -> Unterkante y=%d" % (y, h, unten))
print()
if unten > ok:
    print("  ERGEBNIS: ragt %d Bildpunkte IN die Taskleiste   FAIL" % (unten - ok))
    sys.exit(1)
print("  ERGEBNIS: %d Bildpunkte Abstand ueber der Taskleiste   OK" % (ok - unten))
PY
E=$?

echo
echo "== deckt irgendetwas die Taskleiste zu? (Bildpunkte im Leistenband) =="
python3 - "$W/01-suchfenster.ppm" <<'PY'
import sys
p = sys.argv[1]
d = open(p, 'rb').read()
i = 2; tok = []
while len(tok) < 3:
    while d[i:i+1].isspace(): i += 1
    if d[i:i+1] == b'#':
        while d[i:i+1] not in (b'\n', b''): i += 1
        continue
    j = i
    while not d[j:j+1].isspace(): j += 1
    tok.append(int(d[i:j])); i = j
i += 1
w, h, _ = tok
px = d[i:]
# Die Leiste ist das unterste Band. Wie viele verschiedene Farben
# stehen dort? Ein zugedecktes Stueck brachte die Farben des Menues mit.
for band, name in ((80, "unterste 80 Zeilen (Leiste)"),):
    s = set()
    for y in range(h - band, h, 2):
        for x in range(0, w, 4):
            k = (y * w + x) * 3
            s.add((px[k], px[k+1], px[k+2]))
    print("   %s: %d verschiedene Farben" % (name, len(s)))
PY
exit $E
