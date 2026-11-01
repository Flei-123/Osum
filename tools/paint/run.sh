#!/usr/bin/env bash
#
# Die Abschnitte:
#
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"

PASS=0
FAIL=0
ok()  { echo "  OK    $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $*"; FAIL=$((FAIL+1)); }

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

echo "== 1. the computation: src-over against the exact computation =="
if out=$(python3 tools/paint/blendcheck.py --schnell --quellen 2>&1); then
    echo "$out" | sed 's/^/     /'
    n=$(echo "$out" | grep -c '^  OK')
    PASS=$((PASS+n))
else
    echo "$out" | sed 's/^/     /'
    bad "blendcheck.py ist fehlgeschlagen"
fi

echo "== 2. the cost: in the kernel and native =="
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "PAINT: skipped, qemu-system-x86_64 is missing"
    exit 0
fi
if ! bash tools/build-kernel.sh "$TMPD/k0.mb" > "$TMPD/k.log" 2>&1; then
    bad "the kernel does not build"; sed 's/^/        /' "$TMPD/k.log" | tail -20
    echo "PAINT: $PASS bestanden, $FAIL fehlgeschlagen"; exit 1
fi
ok "der Kernel baut ($(stat -c%s "$TMPD/k0.mb") Oktette)"

VGA_STD=${VGA_STD:-"-vga std -global VGA.edid=off"}

lauf() { # zeile ausgabe
    timeout 300 qemu-system-x86_64 -kernel "$TMPD/k0.mb" -m 256 \
        -append "$1" -serial "file:$2" -display none -no-reboot $VGA_STD \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
}
GRUND="nokbd nosched noproc nofs noring3"
lauf "gfx $GRUND" "$TMPD/std.txt"
lauf "gfx fbbig $GRUND" "$TMPD/big.txt"

for f in std big; do
    z=$(grep -a 'paintbench:' "$TMPD/$f.txt" | head -1)
    if [ -n "$z" ]; then
        echo "     $z"
        fa=$(echo "$z" | sed -n 's/.*fill_a=\([0-9]*\) cyc.*/\1/p')
        fi_=$(echo "$z" | sed -n 's/.*fill=\([0-9]*\) cyc.*/\1/p')
        bl=$(echo "$z" | sed -n 's/.* blends=\([0-9]*\).*/\1/p')
        wh=$(echo "$z" | sed -n 's/.*paintbench: \([0-9]*\)x\([0-9]*\).*/\1 \2/p')
        set -- $wh
        px=$(( $1 * $2 ))
        if [ "$bl" = "$(( px * 4 ))" ]; then
            ok "$1x$2: $bl gemischte Bildpunkte = $px * 4 Durchgaenge"
        else
            bad "$1x$2: $bl gemischte Bildpunkte, erwartet $(( px * 4 ))"
        fi
        if [ -n "$fa" ] && [ -n "$fi_" ] && [ "$fa" -gt "$fi_" ]; then
            ok "$1x$2: blended costs more than opaque ($fa against $fi_ cycles)"
        else
            bad "$1x$2: the measurement is not plausible ($fa against $fi_)"
        fi
    else
        bad "$f: paintbench hat nichts gemeldet"
    fi
done

if cc -O2 -o "$TMPD/native" tools/paint/native.c 2>"$TMPD/cc.err"; then
    "$TMPD/native" | sed 's/^/     /'
    ok "the same computation measured natively -- the factor of the computation, "\
"nicht der des Emulators"
else
    bad "tools/paint/native.c uebersetzt nicht"
    sed 's/^/        /' "$TMPD/cc.err" | head -5
fi

echo "== 3. the fourteen promises in the kernel =="
z=$(grep -a 'paint: selftest' "$TMPD/std.txt" | head -1)
echo "     ${z:-(nichts gemeldet)}"
if echo "$z" | grep -q 'gezaehlt=14 of 14'; then
    ok "fb.selftest3: 14 von 14"
else
    bad "fb.selftest3 does not keep all fourteen promises"
fi
if echo "$z" | grep -q '  ok$'; then
    ok "and the counter of the blended pixels is right"
else
    bad "the counter of the blended pixels is wrong"
fi

echo "== 4. the anti-aliasing of the glyphs =="
if out=$(python3 tools/paint/aacheck.py 2>&1); then
    echo "$out" | tail -12 | sed 's/^/     /'
    n=$(echo "$out" | grep -c '^  OK')
    PASS=$((PASS+n))
else
    echo "$out" | tail -14 | sed 's/^/     /'
    m=$(echo "$out" | grep -c '^  FAIL')
    n=$(echo "$out" | grep -c '^  OK')
    PASS=$((PASS+n)); FAIL=$((FAIL+m))
fi

echo "== 5. two rounds at the same address =="
if out=$(python3 tools/paint/scalars.py 2>&1); then
    echo "$out" | tail -2 | sed 's/^/     /'
    ok "no two scalars of a kernel file lie on top of each other"
else
    echo "$out" | tail -15 | sed 's/^/     /'
    bad "Skalare ueberschneiden sich"
fi

echo "== 6. the same numbers in three places =="
# WM_FORM und WM_APP
for n in 2115 2116; do
    grep -qE "= $n( |$)" kernel/sys/sys.fi && ok "Aufrufnummer $n steht in kernel/sys/sys.fi" \
        || bad "Aufrufnummer $n fehlt"
done
maxnr=$(grep -oE 'const WM_MAXNR: u64 = [0-9]+' kernel/sys/sys.fi | grep -oE '[0-9]+$')
hoch=$(grep -oE '^const WM_[A-Z_]+: u64 = 21[0-9][0-9]' kernel/sys/sys.fi \
    | grep -v WM_MAXNR | grep -oE '[0-9]+$' | sort -n | tail -1)
if [ -n "${maxnr:-}" ] && [ "$maxnr" -ge 2126 ] && [ "$maxnr" = "${hoch:-x}" ]; then
    ok "WM_MAXNR=$maxnr is the highest call number of the window server (>= 2126)"
else
    bad "WM_MAXNR='$maxnr' passt nicht zu den Aufrufen (hoechste gefunden: '$hoch', erwartet >= 2126)"
fi
for f in kernel/ui/wm.fi kernel/sys/sys.fi kernel/user/wlibc.fi; do
    a=$(grep -cE '(FM|WF)_RADIUS: u64 = 0' "$f")
    b=$(grep -cE '(FM|WF)_SHADOW_C: u64 = 3' "$f")
    if [ "$a" = 1 ] && [ "$b" = 1 ]; then
        ok "$f numbers the shape slots 0..3 the same"
    else
        bad "$f numbers the shape slots differently"
    fi
done
sa=$(grep -c 'const WL_BYTES: u64 = 128' kernel/sys/sys.fi)
sb=$(grep -c 'const WL_BYTES: u64 = 128' kernel/user/wlibc.fi)
if [ "$sa" = 1 ] && [ "$sb" = 1 ]; then
    ok "the WM_LIST record is 128 octets long on both sides"
else
    bad "WL_BYTES diverges between kernel and library"
fi
ka=$(grep -c 'const APP_LEN: u64 = 24' kernel/ui/wm/wmcore.fi)
kb=$(grep -c 'const APP_LEN: u64 = 24' kernel/user/wlibc.fi)
if [ "$ka" = 1 ] && [ "$kb" = 1 ]; then
    ok "and the bundle name is 24 octets long on both sides"
else
    bad "APP_LEN laeuft auseinander"
fi

echo "== 7. the image: modern against classic =="
SH="$TMPD/shots"
if ! LOOKBUILD="$TMPD/build" bash tools/look/shot.sh "$SH/modern" \
        shape=modern scheme=day mode=light shadow=on extra='einst nostart' > "$TMPD/m.log" 2>&1; then
    bad "the run on shape=modern failed"
    tail -5 "$TMPD/m.log" | sed 's/^/        /'
else
    ok "shape=modern gebootet und fotografiert"
    if ! LOOKBUILD="$TMPD/build" bash tools/look/shot.sh "$SH/classic" \
            shape=classic scheme=day mode=light shadow=on extra='einst nostart' > "$TMPD/c.log" 2>&1; then
        bad "the run on shape=classic failed"
    else
        ok "shape=classic gebootet und fotografiert"
    fi
    R=$(grep -a 'wm: win nr=' "$TMPD/m.log" | grep -a 'deco=1' \
        | grep -av 'Terminal' | head -1)
    X=$(echo "$R" | sed -n 's/.* x=\(-\?[0-9]*\) .*/\1/p')
    Y=$(echo "$R" | sed -n 's/.* y=\(-\?[0-9]*\) .*/\1/p')
    OW=$(echo "$R" | sed -n 's/.* ow=\([0-9]*\) .*/\1/p')
    OH=$(echo "$R" | sed -n 's/.* oh=\([0-9]*\) .*/\1/p')
    echo "     the measured window: x=$X y=$Y ow=$OW oh=$OH"
    if [ -n "$X" ] && [ -s "$SH/modern/desktop.ppm" ]; then
        for was in schatten ecke; do
            if [ "$was" = schatten ]; then
                A=(schatten "$SH/classic/desktop.ppm" "$SH/modern/desktop.ppm" \
                   "$X" "$Y" "$OW" "$OH")
            else
                A=(ecke "$SH/classic/desktop.ppm" "$SH/modern/desktop.ppm" \
                   "$X" "$Y" --r 8)
            fi
            out=$(python3 tools/paint/shadow.py "${A[@]}" 2>&1)
            echo "$out" | sed 's/^/     /'
            PASS=$((PASS+$(echo "$out" | grep -c '^  OK')))
            FAIL=$((FAIL+$(echo "$out" | grep -c '^  FAIL')))
        done
    else
        bad "no image and no reported window"
    fi
    ns=$(grep -ac 'taskbar: sym btn=' "$TMPD/m.log")
    if [ "$ns" -gt 0 ]; then
        grep -a 'taskbar: sym btn=' "$TMPD/m.log" | sort -u | sed 's/^/     /'
        leer=$(grep -a 'taskbar: sym btn=' "$TMPD/m.log" | grep -c 'ink=0')
        if [ "$leer" = 0 ]; then
            ok "$ns symbols in taskbar buttons, each with ink"
        else
            bad "$leer symbols without a single coloured pixel"
        fi
    else
        bad "the taskbar reports not a single program symbol"
    fi
    #
    FN=$(grep -aoE 'form n=[0-9]+' "$TMPD/m.log" | tail -1 | grep -oE '[0-9]+')
    if [ "${FN:-0}" -ge 4 ]; then
        ok "the taskbar passed all four shape values to the server (form n=$FN)"
    else
        bad "form_push did not get all four values through (form n=${FN:-missing})"
    fi
fi

echo
echo "PAINT: $PASS bestanden, $FAIL fehlgeschlagen"
[ "$FAIL" -eq 0 ]
