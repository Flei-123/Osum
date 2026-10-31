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
    echo "SERVER: skipped, qemu-system-x86_64 ist nicht da"; exit 0
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

echo "== 1. der Bauschalter: gui=on und gui=off =="

bash tools/build-kernel.sh "$TMPD/gui.mb" --gui on > "$TMPD/gui.log" 2>&1 \
    && ok "der Bau mit Bildschirm laeuft durch" \
    || { bad "gui=on laesst sich nicht bauen"; sed 's/^/        /' "$TMPD/gui.log" | head -10; }
bash tools/build-kernel.sh "$TMPD/srv.mb" --gui off > "$TMPD/srv.log" 2>&1 \
    && ok "der Bau OHNE Bildschirm laeuft durch" \
    || { bad "gui=off laesst sich nicht bauen"; sed 's/^/        /' "$TMPD/srv.log" | head -20; }

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
        [ "$v" != 0 ] && schlecht="$schlecht $m=$v"
        [ "$g" = 0 ] && schlecht="$schlecht $m-fehlt-im-GUI-Bau"
    done
    echo "        Symbole der Oberflaeche: gui=$gsum  srv=$ssum"
    [ -z "$schlecht" ] \
        && ok "im Serverabbild steht KEINE Funktion der elf Grafikdateien ($gsum im GUI-Bau, 0 hier)" \
        || bad "die Symboltafel sagt etwas anderes:$schlecht"
    ng=$(nm "$TMPD/gui.mb.elf" | grep -c "_F0\.gfx__")
    ns=$(nm "$TMPD/srv.mb.elf" | grep -c "_F0\.gfx__")
    [ "$ng" = "$ns" ] && [ "$ng" -gt 20 ] \
        && ok "die Naht selbst steht in beiden, mit derselben Zahl Symbole: $ng" \
        || bad "die Naht ist verschieden breit: gui=$ng srv=$ns"
    treffer=""
    for w in vmode glyph raster focus cursor; do
        strings -a "$TMPD/srv.mb" | grep -v "gpu_hw_cursor\|ax__focus_node\|ax.focus_node" | grep -qa -- "$w" && treffer="$treffer $w"
        grep -qa -- "$w" "$TMPD/gui.mb" || bad "'$w' fehlt schon im GUI-Abbild -- der Pruefer misst nichts"
    done
    [ -z "$treffer" ] \
        && ok "GEGENPROBE an den Daten: keines der fuenf Woerter der Oberflaeche steht im Serverabbild" \
        || bad "im Serverabbild stehen noch Daten der Oberflaeche:$treffer"
fi

echo "== 2. der Schnitt: wer im Kernel noch auf Grafik zugreift =="

N=$(python3 tools/server/count.py kernel)
echo "        Stellen ausserhalb von kernel/gfx/gfx.fi: $N"
num "kein Modul ausser der Naht greift noch auf die Grafik zu" "$N" eq 0
python3 tools/server/count.py kernel --je-datei | sed 's/^/        /'

BASIS=${SERVERBUILD_BASIS:-5d2550c}
if git rev-parse --verify -q "$BASIS" >/dev/null 2>&1; then
    if python3 tools/server/moved.py "$BASIS" > "$TMPD/moved.txt" 2>&1; then
        sed 's/^/      /' "$TMPD/moved.txt"
        ok "der Umzug nach kgui.fi/sysgui.fi/kutil.fi ist ZEICHENGLEICH mit $BASIS"
    else
        sed 's/^/      /' "$TMPD/moved.txt"
        bad "der Umzug hat den Code veraendert -- siehe oben"
    fi
else
    echo "        ($BASIS ist hier nicht da -- der Vergleich entfaellt)"
fi

echo "== 3. das Serverabbild bootet bis zur Shell auf der Leitung =="

SERVER_INIT=off bash tools/server/build.sh "$TMPD/s" > "$TMPD/build.txt" 2>&1 \
    && ok "tools/server/build.sh: Kern, Userland und Platte" \
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
    --frist 60 \
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
    && ok "die Shell antwortet ueber die serielle Leitung, sechs Befehle" \
    || bad "die Shell antwortet nicht ueber die serielle Leitung"
sed 's/^/        | /' "$TMPD/shell.log" | grep -aE 'osum\$|hallo-vom-server|Kein Bildschirm' | head -12

for w in 'hallo-vom-server' 'Kein Bildschirm, eine Leitung'; do
    grep -qa -- "$w" "$TMPD/shell.log" \
        && ok "die Antwort auf der Leitung enthaelt: $w" \
        || bad "die Antwort auf der Leitung enthaelt NICHT: $w"
done

echo "== 4. die Zeilendisziplin auf der Leitung =="

lauf edit "osum console=ttyS0" \
    --frist 60 \
    --erwarte 'sh: ready' \
    --sende 'echo ABX\010C\n' \
    --erwarte 'ABC' \
    --sende 'echo weg-damit\025echo geblieben\n' \
    --erwarte 'geblieben' \
    --sende 'exit\n' \
    --erwarte 'sh: bye' \
    && ok "Rueckschritt und STRG-U wirken auf der seriellen Leitung" \
    || bad "die Zeilenbearbeitung wirkt auf der Leitung nicht"
if grep -qa 'ABXC' "$TMPD/edit.log"; then
    bad "der Rueckschritt hat NICHT gewirkt -- ABXC steht im Mitschnitt"
else
    ok "GEGENPROBE: ABXC steht NICHT im Mitschnitt"
fi
if grep -qa 'weg-damit: ' "$TMPD/edit.log"; then
    bad "STRG-U hat die Zeile nicht verworfen -- sie wurde ausgefuehrt"
else
    ok "STRG-U hat die Zeile verworfen: sie wurde getippt und nie ausgefuehrt"
fi

echo "== 5. die Gegenproben =="

lauf ohne "osum" \
    --frist 45 \
    --erwarte 'sh: ready' \
    --sende 'echo darf-nicht-ankommen\n' \
    --erwarte 'sh: bye'
if grep -qa 'darf-nicht-ankommen' "$TMPD/ohne.log"; then
    bad "GEGENPROBE ohne console=: die Leitung hoert trotzdem"
else
    ok "GEGENPROBE ohne console=ttyS0: nichts von der Leitung kommt an"
fi
grep -qa 'sercon: off' "$TMPD/ohne.log" \
    && ok "und der Kernel sagt es: sercon: off" \
    || bad "der Kernel meldet die serielle Konsole nicht als aus"

lauf noirq "osum console=ttyS0 noserirq" \
    --frist 60 \
    --erwarte 'sh: ready' \
    --sende 'echo ueber-die-abfrage\n' \
    --erwarte 'ueber-die-abfrage' \
    --sende 'exit\n' \
    --erwarte 'sh: bye' \
    && ok "GEGENPROBE noserirq: es kommt an, aber ueber den Abfrageweg" \
    || bad "GEGENPROBE noserirq: es kommt gar nichts mehr an"
IRQS=$(grep -a 'sercon:' "$TMPD/noirq.log" | tail -1 | sed 's/.*irqs=\([0-9]*\).*/\1/')
[ "${IRQS:-x}" = 0 ] \
    && ok "und der Zaehler beweist es: sercon: irqs=0" \
    || bad "mit noserirq stehen trotzdem $IRQS Unterbrechungen im Zaehler"
IRQ2=$(grep -a 'sercon:' "$TMPD/shell.log" | tail -1 | sed 's/.*irqs=\([0-9]*\).*/\1/')
num "im Regellauf kommen die Oktette ueber den Vektor" "${IRQ2:-0}" gt 0
RX=$(grep -a 'sercon:' "$TMPD/shell.log" | tail -1 | sed 's/.*rx=\([0-9]*\).*/\1/')
num "empfangene Oktette im Regellauf" "${RX:-0}" gt 40
DROPS=$(grep -a 'sercon:' "$TMPD/shell.log" | tail -1 | sed 's/.*drops=\([0-9]*\).*/\1/')
num "kein Oktett ging verloren, weil kein Terminal da war" "${DROPS:-1}" eq 0

echo "== 6. das Abbild, in Zahlen =="
if [ -f "$TMPD/gui.mb" ] && [ -f "$TMPD/srv.mb" ]; then
    echo "        srvbench: gui=$(stat -c%s "$TMPD/gui.mb") srv=$(stat -c%s "$TMPD/srv.mb") delta=$((A - B)) promille=$P"
fi
echo "        srvbench: platte=$(stat -c%s "$TMPD/s/disk.img") programme=$(ls "$TMPD/s/bin" | wc -l)"

echo "SERVER: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
