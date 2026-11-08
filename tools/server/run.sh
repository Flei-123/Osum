#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/server/run.sh -- DER SERVERBAU, ABGENOMMEN.
#
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "  OK    $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL  $1"; }
num() { # name wert op soll
    if [ "$2" -"$3" "$4" ] 2>/dev/null; then ok "$1: $2"; else bad "$1: $2 (erwartet $3 $4)"; fi
}

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "SERVER: skipped, qemu-system-x86_64 is not there"; exit 0
fi

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

ACCEL=""
if [ -w /dev/kvm ] && qemu-system-x86_64 -accel kvm -m 32 -display none \
        -no-reboot -kernel /dev/null >/dev/null 2>&1; then
    ACCEL="-accel kvm -cpu host"
elif [ -w /dev/kvm ]; then
    ACCEL="-accel kvm -cpu host"
fi

echo "== 1. the build switch: gui=on and gui=off =="

bash tools/build-kernel.sh "$TMPD/gui.mb" --gui on > "$TMPD/gui.log" 2>&1 \
    && ok "the build with a screen goes through" \
    || { bad "gui=on cannot be built"; sed 's/^/        /' "$TMPD/gui.log" | head -10; }
bash tools/build-kernel.sh "$TMPD/srv.mb" --gui off > "$TMPD/srv.log" 2>&1 \
    && ok "the build WITHOUT a screen goes through" \
    || { bad "gui=off cannot be built"; sed 's/^/        /' "$TMPD/srv.log" | head -20; }

if [ -f "$TMPD/gui.mb" ] && [ -f "$TMPD/srv.mb" ]; then
    A=$(stat -c%s "$TMPD/gui.mb")
    B=$(stat -c%s "$TMPD/srv.mb")
    D=$((A - B))
    P=$((D * 1000 / A))
    echo "        gui=on  $A Oktette"
    echo "        gui=off $B Oktette"
    echo "        Unterschied $D Oktette ($((P / 10)),$((P % 10)) %)"
    num "das Serverabbild ist kleiner, in Oktett" "$D" gt 500000
    num "das Serverabbild ist kleiner, in Promille" "$P" gt 200
fi

if [ -f "$TMPD/gui.mb.elf" ] && [ -f "$TMPD/srv.mb.elf" ]; then
    gsum=0; ssum=0; schlecht=""
    for m in wm fb wig font ttf tile vmode ansi ps2m kgui sysgui; do
        g=$(nm "$TMPD/gui.mb.elf" 2>/dev/null | grep -c "_F0\.${m}__")
        v=$(nm "$TMPD/srv.mb.elf" 2>/dev/null | grep -c "_F0\.${m}__")
        gsum=$((gsum + g)); ssum=$((ssum + v))
        want=0
        [ "$m" = fb ] && want=$(grep -c '^fn ' kernel/gfx/fb-aus.fi)
        [ "$v" != "$want" ] && schlecht="$schlecht $m=$v"
        [ "$g" = 0 ] && schlecht="$schlecht $m-fehlt-im-GUI-Bau"
    done
    echo "        Symbole der Oberflaeche: gui=$gsum  srv=$ssum"
    [ -z "$schlecht" ] \
        && ok "the server image contains no function of the eleven graphics files except the fb stub ($gsum in the GUI build)" \
        || bad "the symbol table says otherwise:$schlecht"
    ng=$(nm "$TMPD/gui.mb.elf" | grep -c "_F0\.gfx__")
    ns=$(nm "$TMPD/srv.mb.elf" | grep -c "_F0\.gfx__")
    seamout=$(python3 tools/server/seam.py kernel/gfx/gfx.fi kernel/gfx/gfx-aus.fi)
    seamrc=$?
    echo "$seamout" | sed 's/^/        /'
    [ "$seamrc" = 0 ] && [ "$ng" -gt 20 ] && [ "$ns" -gt 20 ] \
        && ok "the seam has the same exports in both builds (symbols gui=$ng srv=$ns)" \
        || bad "the seam has a different width: gui=$ng srv=$ns"
    treffer=""
    for w in vmode glyph raster focus cursor; do
        strings -a "$TMPD/srv.mb" | grep -v "gpu_hw_cursor\|ax__focus_node\|ax.focus_node" | grep -qa -- "$w" && treffer="$treffer $w"
        grep -qa -- "$w" "$TMPD/gui.mb" || bad "'$w' fehlt schon im GUI-Abbild -- der Pruefer misst nichts"
    done
    [ -z "$treffer" ] \
        && ok "NEGATIVE on the data: none of the five words of the surface is in the server image" \
        || bad "the server image still contains surface data:$treffer"
fi

echo "== 2. the cut: who in the kernel still touches graphics =="

N=$(python3 tools/server/count.py kernel)
echo "        places outside kernel/gfx/gfx.fi: $N"
num "kein Modul ausser der Naht greift noch auf die Grafik zu" "$N" eq 0
python3 tools/server/count.py kernel --je-datei | sed 's/^/        /'

BASIS=${SERVERBUILD_BASIS:-5d2550c}
if git rev-parse --verify -q "$BASIS" >/dev/null 2>&1; then
    if python3 tools/server/moved.py "$BASIS" > "$TMPD/moved.txt" 2>&1; then
        sed 's/^/      /' "$TMPD/moved.txt"
        ok "the move to kgui.fi/sysgui.fi/kutil.fi is CHARACTER-IDENTICAL with $BASIS"
    else
        sed 's/^/      /' "$TMPD/moved.txt"
        bad "the move changed the code -- see above"
    fi
else
    echo "        ($BASIS is not here -- the comparison is dropped)"
fi

echo "== 3. the server image boots to the shell on the line =="

SERVER_INIT=off bash tools/server/build.sh "$TMPD/s" > "$TMPD/build.txt" 2>&1 \
    && ok "tools/server/build.sh: kernel, userland and disk" \
    || { bad "tools/server/build.sh"; sed 's/^/        /' "$TMPD/build.txt" | head -20; }
sed 's/^/        /' "$TMPD/build.txt"

lauf() { # name append erwartungen...
    local name=$1 append=$2; shift 2
    cp "$TMPD/s/disk.img" "$TMPD/$name.img"
    rm -f "$TMPD/$name.sock"
    ( timeout 120 qemu-system-x86_64 $ACCEL -kernel "$TMPD/s/k.mb" -m 256 \
        -display none -serial "unix:$TMPD/$name.sock,server,nowait" \
        -append "$append" \
        -drive "file=$TMPD/$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 -no-reboot \
        > /dev/null 2>&1; echo $? > "$TMPD/$name.rc" ) &
    local qpid=$!
    python3 tools/server/console.py "$TMPD/$name.sock" "$TMPD/$name.log" "$@"
    local rc=$?
    wait $qpid 2>/dev/null
    return $rc
}

lauf shell "osum console=ttyS0" \
    --deadline 60 \
    --erwarte 'sh: ready' \
    --sende 'echo hallo-vom-server\n' \
    --erwarte 'hallo-vom-server' \
    --sende 'uname\n' \
    --erwarte 'osum' \
    --sende 'pwd\n' \
    --sende 'ls /bin\n' \
    --erwarte 'grep' \
    --sende 'cat /readme.txt\n' \
    --erwarte 'Kein Bildschirm, eine Leitung' \
    --sende 'echo 1 2 3 | wc\n' \
    --sende 'df\n' \
    --erwarte 'total' \
    --sende 'exit\n' \
    --erwarte 'sh: bye' \
    && ok "the shell answers over the serial line, six commands" \
    || bad "the shell does not answer over the serial line"
sed 's/^/        | /' "$TMPD/shell.log" | grep -aE 'osum\$|hallo-vom-server|Kein Bildschirm' | head -12

for w in 'hallo-vom-server' 'Kein Bildschirm, eine Leitung'; do
    grep -qa -- "$w" "$TMPD/shell.log" \
        && ok "the answer on the line contains: $w" \
        || bad "the answer on the line does NOT contain: $w"
done

echo "== 4. line discipline on the line =="

lauf edit "osum console=ttyS0" \
    --deadline 60 \
    --erwarte 'sh: ready' \
    --sende 'echo ABX\010C\n' \
    --erwarte 'ABC' \
    --sende 'echo weg-damit\025echo geblieben\n' \
    --erwarte 'geblieben' \
    --sende 'exit\n' \
    --erwarte 'sh: bye' \
    && ok "backspace and CTRL-U work on the serial line" \
    || bad "line editing does not work on the line"
if grep -qa 'ABXC' "$TMPD/edit.log"; then
    bad "backspace did NOT work -- ABXC is in the capture"
else
    ok "NEGATIVE: ABXC is NOT in the capture"
fi
if grep -qa 'weg-damit: ' "$TMPD/edit.log"; then
    bad "CTRL-U did not discard the line -- it was executed"
else
    ok "CTRL-U discarded the line: it was typed and never executed"
fi

echo "== 5. die Gegenproben =="

lauf ohne "osum" \
    --deadline 45 \
    --erwarte 'sh: ready' \
    --sende 'echo darf-nicht-ankommen\n' \
    --erwarte 'sh: bye'
if grep -qa 'darf-nicht-ankommen' "$TMPD/ohne.log"; then
    bad "NEGATIVE without console=: the line listens anyway"
else
    ok "NEGATIVE without console=ttyS0: nothing arrives from the line"
fi
grep -qa 'sercon: off' "$TMPD/ohne.log" \
    && ok "and the kernel says so: sercon: off" \
    || bad "the kernel does not report the serial console as off"

lauf noirq "osum console=ttyS0 noserirq" \
    --deadline 60 \
    --erwarte 'sh: ready' \
    --sende 'echo ueber-die-abfrage\n' \
    --erwarte 'ueber-die-abfrage' \
    --sende 'exit\n' \
    --erwarte 'sh: bye' \
    && ok "NEGATIVE noserirq: it arrives, but over the polling path" \
    || bad "NEGATIVE noserirq: nothing arrives anymore"
IRQS=$(grep -a 'sercon:' "$TMPD/noirq.log" | tail -1 | sed 's/.*irqs=\([0-9]*\).*/\1/')
[ "${IRQS:-x}" = 0 ] \
    && ok "and the counter proves it: sercon: irqs=0" \
    || bad "with noserirq $IRQS interrupts are in the counter anyway"
IRQ2=$(grep -a 'sercon:' "$TMPD/shell.log" | tail -1 | sed 's/.*irqs=\([0-9]*\).*/\1/')
num "im Regellauf kommen die Oktette ueber den Vektor" "${IRQ2:-0}" gt 0
RX=$(grep -a 'sercon:' "$TMPD/shell.log" | tail -1 | sed 's/.*rx=\([0-9]*\).*/\1/')
num "empfangene Oktette im Regellauf" "${RX:-0}" gt 40
DROPS=$(grep -a 'sercon:' "$TMPD/shell.log" | tail -1 | sed 's/.*drops=\([0-9]*\).*/\1/')
num "kein Oktett ging verloren, weil kein Terminal da war" "${DROPS:-1}" eq 0

echo "== 6. the image, in numbers =="
if [ -f "$TMPD/gui.mb" ] && [ -f "$TMPD/srv.mb" ]; then
    echo "        srvbench: gui=$(stat -c%s "$TMPD/gui.mb") srv=$(stat -c%s "$TMPD/srv.mb") delta=$((A - B)) promille=$P"
fi
echo "        srvbench: platte=$(stat -c%s "$TMPD/s/disk.img") programme=$(ls "$TMPD/s/bin" | wc -l)"

echo "SERVER: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
