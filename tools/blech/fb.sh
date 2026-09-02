#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/blech/fb.sh -- DER RAHMENPUFFER, UEBER VIELE GRAFIKKARTEN UND
#                      VIELE AUFLOESUNGEN.
#
# Diese Runde baut ausdruecklich KEINEN GPU-Treiber, und das soll auch so
# bleiben. Was sie stattdessen tut, ist die eine Frage zu beantworten,
# die dann uebrig bleibt: TRAEGT DER WEG UEBER DIE FIRMWARE WIRKLICH?
#
# Osum hat genau drei Wege zu einem Bild, und alle drei enden in
# denselben vier Zahlen (Breite, Hoehe, Farbtiefe, Zeilenlaenge):
#
#   1. Multiboot-Flag Bit 12 -- der Lader (Limine) hat den Rahmenpuffer
#      schon eingerichtet und gibt Adresse und Geometrie weiter. Auf
#      echtem Blech ist das der UEFI-GOP-Puffer.
#   2. Die Bochs-/QEMU-Register 0x1CE/0x1CF (VBE-Erweiterung), wenn der
#      Lader nichts hinterlassen hat.
#   3. Die PCI-BAR der Karte, als letzter Ausweg.
#
# GEMESSEN WIRD NICHT "es kommt ein Bild", sondern die Schluessigkeit der
# vier Zahlen -- und zwar mit einer Rechnung, die eine Karte, die nur
# irgendetwas meldet, nicht besteht:
#
#     pitch >= width * bpp/8        (eine Zeile muss in die Zeile passen)
#     cols  == width  / 8           (der Zeichensatz ist 8 breit)
#     rows  == height / 16          (und 16 hoch)
#     phys  != 0                    (es gibt eine Adresse)
#
# Ein Rahmenpuffer, dessen Zeilenlaenge kleiner ist als seine Breite,
# zeigt Schraegstreifen statt eines Bildes -- und genau das ist der
# Fehler, den man auf fremdem Blech zuerst sieht und im Quelltext nie.
#
# Aufruf:  bash tools/blech/fb.sh [ausgabeverzeichnis]
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

AUS=${1:-}
pass=0
fail=0
OHNE=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hin() { printf '  --    %s\n' "$1"; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "FB: uebersprungen, qemu-system-x86_64 fehlt"
    exit 0
fi

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

bash tools/build-kernel.sh "$TMPD/k.mb" --stufe 0 >/dev/null 2>&1 \
    || { echo "FB: der Kernel liess sich nicht bauen"; exit 1; }

echo "== 0. der Wirt =="
hin "QEMU: $(qemu-system-x86_64 --version | head -1)"
hin "Kern: $(stat -c%s "$TMPD/k.mb") Oktette"

# Eine Zeile "hwdiag: fb 800x600  bpp=32  pitch=3200  src=vbe
# phys=0xfd000000  cols/rows=100/37" auseinandernehmen und nachrechnen.
pruefe() { # $1 = Protokoll, $2 = Name des Falles, $3 = erwartete Breite (oder "")
    local f=$1 name=$2 wollw=$3
    local z
    z=$(grep -a 'hwdiag: fb ' "$f" | tail -1)
    if [ -z "$z" ]; then
        if grep -qa 'fb=KEINER' "$f"; then
            # KEIN Fehler, aber auch kein bestandener Punkt: es ist ein
            # BEFUND. Cirrus und die VMware-SVGA haben die
            # Bochs-Erweiterung 0x1CE/0x1CF nicht; ihr eigener VBE-Weg
            # laeuft ueber INT 10h im realen Modus, und den gibt es in
            # einem 64-Bit-Kern nicht mehr. Auf echtem Blech spielt das
            # keine Rolle -- dort kommt der Puffer von der Firmware --,
            # aber in der Nachbildung ist es der Unterschied zwischen
            # "geht" und "geht nicht", und er steht hier.
            hin "$name: KEIN Rahmenpuffer -- der Kern sagt es (fb=KEINER) und laeuft weiter"
            OHNE=$((OHNE+1))
            return 0
        fi
        bad "$name: keine fb-Zeile im Bericht"
        return 1
    fi
    local w h bpp pitch src phys cols rows
    w=$(sed -E 's/.*fb ([0-9]+)x([0-9]+).*/\1/' <<<"$z")
    h=$(sed -E 's/.*fb ([0-9]+)x([0-9]+).*/\2/' <<<"$z")
    bpp=$(sed -E 's/.*bpp=([0-9]+).*/\1/' <<<"$z")
    pitch=$(sed -E 's/.*pitch=([0-9]+).*/\1/' <<<"$z")
    src=$(sed -E 's/.*src=([a-z]+).*/\1/' <<<"$z")
    phys=$(sed -E 's/.*phys=(0x[0-9a-f]+).*/\1/' <<<"$z")
    cols=$(sed -E 's#.*cols/rows=([0-9]+)/([0-9]+).*#\1#' <<<"$z")
    rows=$(sed -E 's#.*cols/rows=([0-9]+)/([0-9]+).*#\2#' <<<"$z")
    local mindest=$(( w * bpp / 8 ))
    local gut=1
    [ "$pitch" -ge "$mindest" ] || { gut=0; hin "    pitch $pitch < $mindest"; }
    [ "$cols" -eq $(( w / 8 )) ] || { gut=0; hin "    cols $cols != $(( w / 8 ))"; }
    [ "$rows" -eq $(( h / 16 )) ] || { gut=0; hin "    rows $rows != $(( h / 16 ))"; }
    [ "$phys" != "0x0" ] || { gut=0; hin "    phys ist 0"; }
    if [ -n "$wollw" ] && [ "$w" != "$wollw" ]; then
        gut=0; hin "    Breite $w statt $wollw"
    fi
    if [ "$gut" -eq 1 ]; then
        ok "$name: ${w}x${h} bpp=$bpp pitch=$pitch src=$src -- die vier Zahlen sind schluessig"
    else
        bad "$name: ${w}x${h} bpp=$bpp pitch=$pitch src=$src -- die Zahlen passen nicht zusammen"
    fi
}

lauf() { # $1 = Ausgabe, $2 = Kommandozeile, Rest = QEMU
    local out=$1 app=$2
    shift 2
    timeout 120 $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 -append "$app" \
        -serial "file:$out" -display none -no-reboot "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
}

# =====================================================================
echo "== 1. dieselbe Aufloesung auf sieben verschiedenen Grafikkarten =="
# =====================================================================
# Der Punkt: der Kern hat KEINEN Treiber fuer eine davon. Er redet mit
# den Bochs-Registern bzw. mit dem, was der Lader hinterlassen hat --
# also muss das Bild auf allen sieben gleich herauskommen, sofern die
# Karte die VBE-Erweiterung ueberhaupt hat.
i=0
for karte in "-vga std" "-vga cirrus" "-vga vmware" "-vga qxl" \
             "-device bochs-display" "-device VGA" "-device virtio-vga"; do
    i=$((i+1))
    lauf "$TMPD/k$i.txt" "gfx hwdiag nokbd nosched noproc nofs noring3" $karte
    pruefe "$TMPD/k$i.txt" "$karte" ""
done

# UND DIE GEGENPROBE: eine Maschine ohne Grafikkarte darf nicht haengen.
lauf "$TMPD/knone.txt" "gfx hwdiag nokbd nosched noproc nofs noring3" -vga none
if grep -qa 'ENDE DER DIAGNOSE' "$TMPD/knone.txt"; then
    ok "-vga none: der Bericht kommt trotzdem vollstaendig -- kein Haenger"
else
    bad "-vga none: der Bericht bricht ab"
fi
pruefe "$TMPD/knone.txt" "-vga none" ""

# =====================================================================
echo "== 2. zwei Aufloesungen, die der Kern selbst anfordert =="
# =====================================================================
lauf "$TMPD/r1.txt" "gfx hwdiag nokbd nosched noproc nofs noring3" -vga std
pruefe "$TMPD/r1.txt" "Vorgabe" "800"
lauf "$TMPD/r2.txt" "gfx fbbig hwdiag nokbd nosched noproc nofs noring3" -vga std
pruefe "$TMPD/r2.txt" "fbbig" "1024"

# =====================================================================
echo "== 3. was die Zahlen ueber die Herkunft sagen =="
# =====================================================================
# Mit `-kernel` laedt QEMU selbst und hinterlaesst KEINEN Rahmenpuffer;
# der Kern muss also auf die Bochs-Register zurueckfallen. Das ist die
# Gegenprobe zu dem, was `tools/usbimg/run.sh` unter UEFI misst -- dort
# steht `src=multiboot`, weil Limine den GOP-Puffer weitergibt.
z=$(grep -a 'hwdiag: fb ' "$TMPD/r1.txt" | tail -1)
if grep -q 'src=vbe' <<<"$z"; then
    ok "mit -kernel kommt der Puffer aus den Bochs-Registern (src=vbe)"
else
    hin "mit -kernel: src ist nicht vbe -- $z"
fi

if [ -n "$AUS" ]; then
    mkdir -p "$AUS"
    cp "$TMPD"/*.txt "$AUS/" 2>/dev/null
    grep -ah 'hwdiag: fb ' "$TMPD"/*.txt > "$AUS/fb-zeilen.txt" 2>/dev/null
fi

echo
echo "FB: $pass bestanden, $fail gefallen, $OHNE Karten ohne Bochs-Erweiterung"
[ "$fail" -eq 0 ] || exit 1
exit 0
