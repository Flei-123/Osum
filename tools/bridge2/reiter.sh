#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bridge2/reiter.sh -- RUNDE BRUECKE: DIE SEITE IN DEN EINSTELLUNGEN, FOTOGRAFIERT.
#
# ====================================================================
# WARUM EIN BILD UND NICHT EIN HAKEN IM PROTOKOLL
# ====================================================================
#
# Justins Vorgabe zu dieser Runde: "Die Bruecke muss sich AUSSCHALTEN
# lassen, und zwar in den Einstellungen, nicht nur per Kommandozeile."
# Ob ein Reiter WIRKLICH dasteht, sieht man nicht daran, dass ein
# Programm uebersetzt -- Runde LOOK hat einen ganzen Tag damit
# verbracht, dass die Seiten SIEBEN und ACHT uebereinander gezeichnet
# wurden, weil eine Tafel voll war und das still hinnahm. Im Quelltext
# war davon nichts zu sehen.
#
# Also: Osum starten, `settings` oeffnen, auf den letzten Reiter
# klicken und ein Bild machen. Das Bild ist der Beleg.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
OUT=${REITER_OUT:-/tmp/bruecke-reiter}
mkdir -p "$OUT"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }

command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo "REITER: uebersprungen, qemu fehlt"; exit 0; }

SOCK="$OUT/mon.sock"
QPID=""
cleanup() { [ -n "$QPID" ] && kill "$QPID" 2>/dev/null; rm -f "$SOCK"; }
trap cleanup EXIT

echo "== 1. das Abbild =="
# `tools/look/shot.sh keep=yes` baut genau das Abbild, das diese Runde
# braucht: mit /apps, den Schemata, dem Symbolzeichensatz und
# `settings` darin. Es wird NICHT nachgebaut, wenn es schon daliegt --
# der Bau dauert Minuten und aendert an dieser Messung nichts.
if [ ! -f "$OUT/disk.img" ]; then
    bash tools/look/shot.sh "$OUT" keep=yes >"$OUT/bau.log" 2>&1 || {
        echo "der Bau ist gescheitert"; tail -6 "$OUT/bau.log"; exit 1; }
fi
[ -f "$OUT/disk.img" ] || { echo "kein disk.img"; exit 1; }
BUILDD=${LOOKBUILD:-/tmp/osum-lookbuild-$(pwd | md5sum | cut -c1-12)}
[ -f "$BUILDD/k0.mb" ] || { echo "kein Kern in $BUILDD"; exit 1; }
ok "Abbild und Kern stehen"

echo "== 2. Osum starten und settings oeffnen =="
rm -f "$OUT/serial.txt" "$SOCK"
cp "$OUT/disk.img" "$OUT/lauf.img"
timeout 420 qemu-system-x86_64 -kernel "$BUILDD/k0.mb" -m 512 \
    -append "gfx wm wig wigicons desk wmhold wiglong nokbd nosched noproc nofs fbres=1280x800" \
    -serial "file:$OUT/serial.txt" -display none -no-reboot -vga std \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$OUT/lauf.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$OUT/qemu.log" 2>&1 &
QPID=$!

# `wm: hold` ist das Zeichen, dass der Schreibtisch steht -- dieselbe
# Marke, auf die tools/look/shot.sh wartet.
i=0
while [ $i -lt 2400 ]; do
    grep -qaE '^wm: hold' "$OUT/serial.txt" 2>/dev/null && break
    kill -0 "$QPID" 2>/dev/null || break
    sleep 0.15; i=$((i+1))
done
if grep -qaE '^wm: hold' "$OUT/serial.txt" 2>/dev/null; then
    ok "der Schreibtisch steht"
else
    bad "der Schreibtisch kam nicht hoch"
    tail -8 "$OUT/serial.txt" 2>/dev/null | sed 's/^/        /'
    echo "REITER: $pass bestanden, $fail durchgefallen"; exit 1
fi

klick() {
    python3 tools/themestore/click.py "$1" > "$OUT/k.txt" 2>/dev/null || return 1
    python3 tools/wm/monitor.py "$SOCK" "$OUT/k.txt" >/dev/null 2>&1 || return 1
    sleep "${2:-2}"
    return 0
}

# Der Starter sitzt links in der Taskleiste (y = 800 - 28/2 = 786).
klick 20,786 2
# DIE STELLE KOMMT AUS DEM PROTOKOLL UND NICHT AUS DEM AUGENMASS --
# UND SIE MUSS ZWEIMAL GERECHNET WERDEN.
#
# `launcher: rows x=40 base=99 zh=20` sagt, wo die Liste IM FENSTER
# beginnt, und `launcher: treffer i=3 name=[Settings]` sagt, dass
# Settings der vierte Eintrag ist. Das ergibt 200,169 -- FENSTERWEIT.
#
# Der Zeiger arbeitet aber BILDSCHIRMWEIT, und das Starterfenster
# liegt nicht im Ursprung: `wm: win ... x=8 y=464 ... t=[Search]`.
# Also kommt der Fensterursprung dazu. Ohne ihn landete der Klick bei
# y=169, also im Terminal darueber; der Starter verlor den Fokus und
# machte zu ("launcher: fokus weg", "launcher: zugemacht") -- was im
# Protokoll aussieht wie ein Programm, das nicht startet.
#
# Der Ursprung wird GELESEN und nicht angenommen: das Fenster kann
# woanders liegen, sobald sich die Bildschirmgroesse aendert.
SX=$(grep -a 'wm: win .*t=\[Search\]' "$OUT/serial.txt" | tail -1 \
     | grep -oE ' x=[0-9]+' | head -1 | tr -dc '0-9')
SY=$(grep -a 'wm: win .*t=\[Search\]' "$OUT/serial.txt" | tail -1 \
     | grep -oE ' y=[0-9]+' | head -1 | tr -dc '0-9')
SX=${SX:-8}; SY=${SY:-464}
note "Starterfenster bei $SX,$SY -- Settings also bei $((SX+200)),$((SY+169))"
klick "$((SX+200)),$((SY+169))" 3
sleep 2

if grep -qa 'settings: stand' "$OUT/serial.txt" 2>/dev/null; then
    ok "settings laeuft"
    note "$(grep -a 'settings: elemente' "$OUT/serial.txt" | tail -1)"
else
    bad "settings ist nicht aufgegangen"
    grep -aE 'launcher:|settings:' "$OUT/serial.txt" | tail -6 | sed 's/^/        /'
fi

echo "== 3. auf den Brueckenreiter klicken =="
# Elf Reiter auf der Breite des Fensters. Der Brueckenreiter ist der
# LETZTE -- genau deshalb steht er dort (siehe R_BRUECKE in
# kernel/user/settings.fi): jede andere Seite behaelt ihre Nummer.
STAND_VOR=$(grep -a 'settings: stand' "$OUT/serial.txt" | tail -1)
klick 700,150 2
STAND_NACH=$(grep -a 'settings: stand' "$OUT/serial.txt" | tail -1)
note "vorher: $STAND_VOR"
note "nachher: $STAND_NACH"

echo "== 4. das Bild =="
python3 tools/wm/monitor.py "$SOCK" /dev/stdin >/dev/null 2>&1 <<CMD
screendump $OUT/reiter.ppm
CMD
sleep 2
if [ -s "$OUT/reiter.ppm" ]; then
    python3 - "$OUT/reiter.ppm" "$OUT/reiter.png" <<'PYEOF'
import sys, zlib, struct
roh = open(sys.argv[1], "rb").read()
# P6\n<w> <h>\n255\n
teile = roh.split(b"\n", 3)
w, h = [int(x) for x in teile[1].split()]
pix = teile[3]
zeilen = b""
for y in range(h):
    zeilen += b"\x00" + pix[y * w * 3:(y + 1) * w * 3]
def stueck(t, d):
    return (struct.pack(">I", len(d)) + t + d
            + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF))
png = (b"\x89PNG\r\n\x1a\n"
       + stueck(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
       + stueck(b"IDAT", zlib.compress(zeilen, 6))
       + stueck(b"IEND", b""))
open(sys.argv[2], "wb").write(png)
print("%dx%d, %d Oktette" % (w, h, len(png)))
PYEOF
    ok "Bild gemacht: $OUT/reiter.png"
else
    bad "kein Bild"
fi

echo
echo "REITER: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ] || exit 1
