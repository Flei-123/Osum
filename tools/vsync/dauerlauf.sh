#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vsync/dauerlauf.sh -- N LAEUFE MIT VIER KERNEN, UND WAS DABEI STARB.
#
#     tools/vsync/dauerlauf.sh [anzahl] [kerne] [extra-woerter]
#
# Eine Eigenschaft, die in EINEM Lauf funktioniert, ist nicht gemessen:
# die Runde VIELKERN hat Fehler gefunden, die in einem von fuenf Laeufen
# zuschlugen. Die Bildgrenze fasst den Rahmenpuffer an, und der Ableser
# der Zerreissprobe laeuft auf einem ZWEITEN Kern -- also wird
# ausdruecklich mit mehreren Kernen und ausdruecklich oft gestartet.
#
# Gezaehlt wird, was ein Lauf hinterlaesst: `kernel: done` (er ist bis
# zum Ende gekommen), jede PANIC- und EXCEPTION-Zeile, und der
# Rueckgabewert von QEMU. Ein Lauf, der stillschweigend haengt, faellt
# ueber `timeout` auf und wird als Fehler gezaehlt und nicht als Erfolg.
set -u

cd "$(dirname "$0")/../.." || exit 1
. tools/lib/qemu.sh

N=${1:-20}
KERNE=${2:-4}
EXTRA=${3:-"vsync flip wmanim"}

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

echo "== Dauerlauf: $N Laeufe mit -smp $KERNE, '$EXTRA' =="

if ! bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/b.log" 2>&1; then
    echo "der Kernel laesst sich nicht bauen"; sed 's/^/    /' "$TMPD/b.log" | head; exit 1
fi
python3 tools/osum/mkfs.py build "$TMPD/disk.img" 4096 /lib/ \
    /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf \
    > "$TMPD/mkfs.txt" 2>&1 || { echo "mkfs fehlgeschlagen"; exit 1; }

fertig=0
panik=0
haenger=0
risse_gesamt=0
for i in $(seq 1 "$N"); do
    cp -f "$TMPD/disk.img" "$TMPD/live.img"
    L="$TMPD/l$i.txt"
    timeout 120 $QEMU_X86 -smp "$KERNE" -kernel "$TMPD/k.mb" -m 256 \
        -append "gfx wm wmhold wmsig wmruhe wighalt=3 $EXTRA nokbd noproc nofs" \
        -serial "file:$L" -display none -no-reboot \
        -vga std -global VGA.edid=off \
        -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    rc=$?
    # 33 ist der Wert, den `isa-debug-exit` fuer den geordneten Schluss
    # liefert (2*16+1); 124 ist `timeout`.
    if [ "$rc" = "124" ]; then
        haenger=$((haenger + 1))
    fi
    grep -qa '^kernel: done' "$L" 2>/dev/null && fertig=$((fertig + 1))
    p=$(grep -acE 'PANIC|EXCEPTION' "$L" 2>/dev/null || true)
    panik=$((panik + ${p:-0}))
    r=$(grep -aoE 'risse=[0-9]+' "$L" 2>/dev/null | tail -1 | grep -oE '[0-9]+' || true)
    risse_gesamt=$((risse_gesamt + ${r:-0}))
    printf '.'
done
echo

echo "    Laeufe:            $N"
echo "    'kernel: done':    $fertig"
echo "    PANIC/EXCEPTION:   $panik"
echo "    Haenger (timeout): $haenger"
echo "    Risse zusammen:    $risse_gesamt"

if [ "$fertig" -eq "$N" ] && [ "$panik" -eq 0 ] && [ "$haenger" -eq 0 ]; then
    echo "DAUERLAUF: $N von $N sauber, 0 Panik"
    exit 0
fi
echo "DAUERLAUF: NICHT SAUBER"
grep -ahE 'PANIC|EXCEPTION' "$TMPD"/l*.txt 2>/dev/null | head -5 | sed 's/^/    /'
exit 1
