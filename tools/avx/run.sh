#!/usr/bin/env bash
#
# WAS GEMESSEN WIRD
#
# Verwendung:  bash tools/avx/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

FIRNC=${FIRNC:-vendor/firn/bin/firnc}

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

has()    { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' sollte nicht da sein" || ok "$3"; }
gleich() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: $2, erwartet $3"; fi }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "AVX: skipped, qemu-system-x86_64 is not available"
    exit 0
fi

lauf() {
    local app=$1 out=$2
    shift 2
    timeout 180 $QEMU_X86 -kernel "$TMPD/k0.mb" -m 512 -append "$app" \
        -serial "file:$out" -display none -no-reboot "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}

zahl() { # <logdatei> <zeilenmuster> <schluessel>
    grep -aoE "$2" "$1" | head -1 | grep -oE "$3[0-9]+" | head -1 \
        | grep -oE '[0-9]+$'
}
hexw() { # <logdatei> <zeilenmuster> <schluessel>
    grep -aoE "$2" "$1" | head -1 | grep -oE "$3"'0x[0-9a-f]+' | head -1 \
        | cut -d= -f2
}
FPUZ='fpu: mode=[0-9]+  cr4=0x[0-9a-f]+  xcr0=0x[0-9a-f]+  size=[0-9]+  lazy=[0-9]+'
FPUC='fpu: f1c=0x[0-9a-f]+  f1d=0x[0-9a-f]+  f7b=0x[0-9a-f]+  sup=0x[0-9a-f]+  need=[0-9]+'
FPUA='fpu: aps=[0-9]+  saves=[0-9]+  restores=[0-9]+  nm=[0-9]+  areas=[0-9]+'
VECZ='vec: width=[0-9]+'

cr4bits() { # <logdatei> <maske hex> <erwartet hex> <name>
    local v
    v=$(grep -aoE 'fpu: mode=[0-9]+  cr4=0x[0-9a-f]+' "$1" | head -1 \
        | grep -oE '0x[0-9a-f]+$')
    if [ -z "$v" ]; then bad "$4 -- keine Zeile 'fpu: ... cr4='"; return; fi
    if [ $(( v & $2 )) -eq $(( $3 )) ]; then
        ok "$4 (cr4=$v)"
    else
        bad "$4 -- cr4=$v, Bits $2 sind $(printf '0x%x' $(( v & $2 ))), erwartet $3"
    fi
}

BASIS="nokbd nosched noproc nofs noring3"

# ------------------------------------------------------------ 1. bauen

echo "== 1. the kernel with the vector unit =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 \
    || { echo "AVX: vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }

if bash tools/build-kernel.sh "$TMPD/k0.mb" --stufe 0 > "$TMPD/b0.log" 2>&1; then
    ok "the kernel is built ($(stat -c%s "$TMPD/k0.mb") Oktette)"
else
    bad "the kernel cannot be built"
    sed 's/^/        /' "$TMPD/b0.log" | head -12
    echo "AVX: $pass passed, $fail failed"
    exit 1
fi

#     objdump -d osum.mb.elf | grep -cE 'xmm|ymm|zmm'   ->  0
#
if command -v objdump >/dev/null 2>&1; then
    objdump -d "$TMPD/k0.mb" 2>/dev/null | awk '
        /^[0-9a-f]+ <.*>:/ { sym = $2 }
        /xmm|ymm|zmm/      { c[sym]++ }
        END { for (s in c) printf "%d %s\n", c[s], s }' \
        | sort -rn > "$TMPD/vecsym.txt"
    ALLOWED='<_F0\.((upmisc__)?u_(vec|xmm|ymm|zmm)_[a-z]+|fpu__vec_[a-z]+|(aesni|shani|wmblur|fbpanel)__[a-z0-9_]+|(raster|fuittf|fuiink)__[a-z0-9_]+)>:'
    FOREIGN=$(grep -vE " $ALLOWED\$" "$TMPD/vecsym.txt" | wc -l)
    TOTAL=$(awk '{s += $1} END {print s + 0}' "$TMPD/vecsym.txt")
    ALLOWED_COUNT=$(grep -cE " $ALLOWED\$" "$TMPD/vecsym.txt")
    if [ "$FOREIGN" -eq 0 ]; then
        ok "vector instructions in the kernel ONLY in the $ALLOWED_COUNT functions of the probe ($TOTAL pieces)"
    else
        bad "vector instructions outside the probe, in $FOREIGN functions:"
        grep -vE " $ALLOWED\$" "$TMPD/vecsym.txt" | head -8 | sed 's/^/        /'
    fi
fi

# --------------------------------------------- 2. die Freischaltung

echo "== 2. CR0/CR4/XCR0 stehen wirklich in den Registern =="
rc=0; lauf "$BASIS" "$TMPD/plain.log" -cpu max || rc=$?
gleich "Beendigungscode mit -cpu max" "$rc" 21

# Bit 9 OSFXSR, Bit 10 OSXMMEXCPT, Bit 18 OSXSAVE.
cr4bits "$TMPD/plain.log" 0x40600 0x40600 \
    "CR4 traegt OSFXSR, OSXMMEXCPT und OSXSAVE"

MODE=$(zahl "$TMPD/plain.log" "$FPUZ" 'mode=')
XCR0=$(hexw "$TMPD/plain.log" "$FPUZ" 'xcr0=')
SIZE=$(zahl "$TMPD/plain.log" "$FPUZ" 'size=')
NEED=$(zahl "$TMPD/plain.log" "$FPUC" 'need=')
if [ -n "${MODE:-}" ] && [ "$MODE" -ge 2 ] 2>/dev/null; then
    ok "the kernel uses XSAVE and not only FXSAVE (mode=$MODE)"
else
    bad "mode=$MODE -- erwartet >= 2 (XSAVE) auf -cpu max"
fi
case "${XCR0:-}" in
    0x?*) ok "XCR0 is set and read back: $XCR0" ;;
    *)    bad "keine Zeile 'xcr0=' im Bericht" ;;
esac
if [ -n "${SIZE:-}" ] && [ "$SIZE" -ge 512 ] 2>/dev/null \
   && [ "${SIZE:-0}" = "${NEED:-x}" ]; then
    ok "the save area is exactly what cpuid reports: size=$SIZE = need=$NEED"
else
    bad "size=${SIZE:-missing} against need=${NEED:-missing} -- expected equal and >= 512"
fi

rc=0; lauf "$BASIS nofpu" "$TMPD/off.log" -cpu max || rc=$?
gleich "Beendigungscode mit nofpu" "$rc" 21
cr4bits "$TMPD/off.log" 0x40600 0x0 \
    "mit nofpu steht keines der drei Bits in CR4"
has "$TMPD/off.log" "fpu: mode=0" "und der Kern behauptet auch nichts anderes"

# --------------------------------------------- 3. der Kontextwechsel

echo "== 3. four processes, their vector registers and the switch between them =="
rc=0; lauf "$BASIS vecproc" "$TMPD/vec.log" -cpu max || rc=$?
gleich "Beendigungscode des Vektorlaufs" "$rc" 21
has "$TMPD/vec.log" "vec: begin" "die vier Prozesse starten"
SUM=$(zahl "$TMPD/vec.log" 'vec: sum=[0-9]+' 'sum=')
gleich "Abweichungen ueber alle vier Prozesse (vec: sum=)" "${SUM:-x}" 0
has "$TMPD/vec.log" "vec: clean=1" "kein Prozess hat je die Register eines anderen gesehen"
W=$(zahl "$TMPD/vec.log" "$VECZ" 'width=')
case "${W:-}" in
    1) ok "gemessene Breite: xmm (width=1)" ;;
    2) ok "gemessene Breite: ymm (width=2)" ;;
    3) ok "measured width: zmm (width=3) -- AVX-512 on this machine" ;;
    *) bad "no usable line 'vec: width=' (gelesen: '${W:-}')" ;;
esac
N0=$(grep -ac 'vec: bad=0' "$TMPD/vec.log")
gleich "Prozesse mit bad=0" "$N0" 4
has "$TMPD/vec.log" "vec: forkbad=0" "fork erbt den LEBENDEN Zustand, nicht den vom letzten Wechsel"

SAVES=$(zahl "$TMPD/vec.log" "$FPUA" 'saves=')
REST=$(zahl "$TMPD/vec.log" "$FPUA" 'restores=')
if [ -n "${SAVES:-}" ] && [ "$SAVES" -gt 0 ] 2>/dev/null \
   && [ "${REST:-0}" -gt 0 ] 2>/dev/null; then
    ok "the switch really worked: saves=$SAVES restores=$REST"
else
    bad "saves=$SAVES restores=$REST -- beide muessen groesser als 0 sein"
fi

echo "== 4. the control runs: without the round it MUST turn red =="

rc=0; lauf "$BASIS vecproc nofpuswitch" "$TMPD/nosw.log" -cpu max || rc=$?
gleich "Beendigungscode ohne Sicherung" "$rc" 21
SUM2=$(zahl "$TMPD/nosw.log" 'vec: sum=[0-9]+' 'sum=')
if [ -n "${SUM2:-}" ] && [ "$SUM2" -gt 0 ] 2>/dev/null; then
    ok "CONTROL RUN: without saving the processes see foreign registers (sum=$SUM2)"
else
    bad "CONTROL RUN stayed green (sum=${SUM2:-missing}) -- section 3 then measures nothing"
fi
has "$TMPD/nosw.log" "vec: clean=0" "und der Lauf sagt es auch so"

rc=0; lauf "$BASIS vecproc nofpu" "$TMPD/noud.log" -cpu max || rc=$?
has "$TMPD/noud.log" "vector=6" \
    "GEGENPROBE: ohne die Runde stirbt der erste Prozess an einem #UD"
hasnot "$TMPD/noud.log" "vec: clean=1" "und der Lauf ist NICHT sauber"

# --------------------------------------------- 5. mehrere Prozessoren

echo "== 5. CR4 is per processor -- four cores, six kernel tasks =="
rc=0; lauf "$BASIS vecproc" "$TMPD/smp.log" -cpu max -smp 4 || rc=$?
gleich "Beendigungscode unter -smp 4" "$rc" 21
CORES=$(zahl "$TMPD/smp.log" 'vecsmp: cores=[0-9]+' 'cores=')
gleich "Kerne, die die Freischaltung WIRKLICH in ihrem CR4 tragen" "${CORES:-x}" 4
has "$TMPD/smp.log" "vecsmp: clean=1" \
    "sechs Kernaufgaben wandern ueber die Kerne und behalten ihre Register"

# --------------------------------------------- 6. XCR0 begrenzen

echo "== 6. noavx begrenzt XCR0 auf x87+SSE =="
rc=0; lauf "$BASIS vecproc noavx" "$TMPD/noavx.log" -cpu max || rc=$?
gleich "Beendigungscode mit noavx" "$rc" 21
X2=$(hexw "$TMPD/noavx.log" "$FPUZ" 'xcr0=')
gleich "XCR0 mit noavx" "${X2:-x}" 0x3
W2=$(zahl "$TMPD/noavx.log" "$VECZ" 'width=')
gleich "und die gemessene Breite faellt auf xmm" "${W2:-x}" 1
has "$TMPD/noavx.log" "vec: clean=1" "der schmale Weg bleibt genauso sauber"

echo "== 7. what this machine offers, and that Osum follows exactly that =="
SUP=$(hexw "$TMPD/plain.log" "$FPUC" 'sup=')
if [ -n "${SUP:-}" ] && [ -n "${XCR0:-}" ]; then
    if [ $(( XCR0 & ~SUP )) -eq 0 ]; then
        ok "XCR0 ($XCR0) requires no bit the machine does not offer ($SUP)"
    else
        bad "XCR0 $XCR0 has bits that sup=$SUP does not list"
    fi
    if [ $(( SUP & 0xe0 )) -eq 224 ]; then
        gleich "die Maschine bietet AVX-512 an, also nimmt Osum es auch" \
               "$(( XCR0 & 0xe0 ))" 224
    else
        ok "this machine has no AVX-512 (sup=$SUP) -- see docs/AUFSETZEN.md, section 5"
    fi
else
    bad "keine Zeile 'sup=' oder 'xcr0=' im Bericht"
fi

echo
echo "AVX: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
