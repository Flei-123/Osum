#!/usr/bin/env bash
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
    || { echo "FB: the kernel could not be built"; exit 1; }

echo "== 0. der Wirt =="
hin "QEMU: $(qemu-system-x86_64 --version | head -1)"
hin "Kern: $(stat -c%s "$TMPD/k.mb") Oktette"

pruefe() { # $1 = Protokoll, $2 = Name des Falles, $3 = erwartete Breite (oder "")
    local f=$1 name=$2 wollw=$3
    local z
    z=$(grep -a 'hwdiag: fb ' "$f" | tail -1)
    if [ -z "$z" ]; then
        if grep -qa 'fb=NONE' "$f"; then
            hin "$name: KEIN Rahmenpuffer -- der Kern sagt es (fb=KEINER) und laeuft weiter"
            OHNE=$((OHNE+1))
            return 0
        fi
        bad "$name: no fb line in the report"
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
        ok "$name: ${w}x${h} bpp=$bpp pitch=$pitch src=$src -- the four numbers are consistent"
    else
        bad "$name: ${w}x${h} bpp=$bpp pitch=$pitch src=$src -- the numbers do not fit together"
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
i=0
for karte in "-vga std" "-vga cirrus" "-vga vmware" "-vga qxl" \
             "-device bochs-display" "-device VGA" "-device virtio-vga"; do
    i=$((i+1))
    lauf "$TMPD/k$i.txt" "gfx hwdiag nokbd nosched noproc nofs noring3" $karte
    pruefe "$TMPD/k$i.txt" "$karte" ""
done

lauf "$TMPD/knone.txt" "gfx hwdiag nokbd nosched noproc nofs noring3" -vga none
if grep -qa 'ENDE DER DIAGNOSE' "$TMPD/knone.txt"; then
    ok "-vga none: the report still arrives complete -- no hang"
else
    bad "-vga none: der Bericht bricht ab"
fi
pruefe "$TMPD/knone.txt" "-vga none" ""

# =====================================================================
echo "== 2. two resolutions the kernel requests itself =="
# =====================================================================
lauf "$TMPD/r1.txt" "gfx hwdiag nokbd nosched noproc nofs noring3" -vga std
pruefe "$TMPD/r1.txt" "Vorgabe" "800"
lauf "$TMPD/r2.txt" "gfx fbbig hwdiag nokbd nosched noproc nofs noring3" -vga std
pruefe "$TMPD/r2.txt" "fbbig" "1024"

# =====================================================================
echo "== 3. what the numbers say about the origin =="
z=$(grep -a 'hwdiag: fb ' "$TMPD/r1.txt" | tail -1)
if grep -q 'src=vbe' <<<"$z"; then
    ok "with -kernel the buffer comes from the Bochs registers (src=vbe)"
else
    hin "mit -kernel: src ist nicht vbe -- $z"
fi

if [ -n "$AUS" ]; then
    mkdir -p "$AUS"
    cp "$TMPD"/*.txt "$AUS/" 2>/dev/null
    grep -ah 'hwdiag: fb ' "$TMPD"/*.txt > "$AUS/fb-zeilen.txt" 2>/dev/null
fi

echo
echo "FB: $pass passed, $fail failed, $OHNE cards without Bochs extension"
[ "$fail" -eq 0 ] || exit 1
exit 0
