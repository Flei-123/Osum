#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/server/run.sh -- DER SERVERBAU, ABGENOMMEN.
#
# Die Runde SERVERBUILD stellt drei Behauptungen auf, und dieser
# Abschnitt macht aus jeder eine Messung:
#
#   1. OSUM LAESST SICH OHNE GRAFIK BAUEN. `--gui off` uebersetzt
#      `kernel/fb.fi`, `wm.fi`, `wig.fi`, `font.fi`, `ttf.fi`,
#      `tile.fi`, `vmode.fi`, `ansi.fi`, `ps2m.fi`, `kgui.fi` und
#      `sysgui.fi` GAR NICHT ERST. Gemessen wird nicht, dass es
#      "funktioniert", sondern der OKTETTUNTERSCHIED der beiden
#      Abbilder -- und dass im Serverabbild keine Zeichenkette der
#      Oberflaeche mehr steht.
#
#   2. DER SCHNITT IST SAUBER. Ausserhalb von `kernel/gfx.fi` schreibt
#      kein Modul dieses Kernels noch `fb.` oder `wm.`. Das zaehlt ein
#      Pruefer nach; vor dieser Runde waren es 745 Stellen in acht
#      Dateien.
#
#   3. DIE SERIELLE LEITUNG IST EIN TERMINAL. Nicht "es kommt eine
#      Meldung heraus" -- sondern: eine Shell laeuft darauf, sie
#      antwortet auf getippte Befehle, der Rueckschritt nimmt ein
#      Zeichen zurueck, STRG-U die Zeile, STRG-C schickt ein Signal,
#      und `echo` laesst sich abschalten. Getippt wird ueber eine
#      UNIX-Steckdose (`tools/server/console.py`), Zeichen fuer
#      Zeichen, mit Warten auf die Antwort dazwischen.
#
# GEGENPROBEN, denn eine Eigenschaft ohne Gegenprobe ist eine
# Behauptung:
#
#   * OHNE `console=ttyS0` darf die Konsole NICHT auf die Leitung
#     hoeren -- dann ist die Eingabe wirkungslos, und der Lauf endet
#     wie jeder Lauf vor dieser Runde.
#   * `noserirq` nimmt den Eintrag im I/O-APIC weg. Die Oktette
#     muessen dann ueber den Abfrageweg kommen, und `sercon: irqs=0`
#     muss es sagen. Kaeme dieselbe Zahl wie vorher heraus, waere
#     nicht bewiesen, dass der Vektor irgendetwas tut.
#   * Ein Serverabbild darf KEIN Programm mit Oberflaeche auf seiner
#     Platte haben (`tools/server/build.sh` prueft das beim Bauen).
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

# KVM, wenn die Maschine es hergibt. Die Runde KVMFIX hat gemessen,
# dass das hier 4,6x schneller ist -- und sie hat zwei echte Fehler
# gefunden, die unter TCG nie auffielen.
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

# DIE ENTSCHEIDENDE GEGENPROBE ZUM BAUSCHALTER. Ein Schalter, der nur
# eine Verzweigung zur Laufzeit setzt, waere am Oktettunterschied allein
# nicht zu unterscheiden -- der Code der Oberflaeche staende weiter im
# Abbild und liefe nur nicht mehr an. Also wird nicht der Unterschied
# gezaehlt, sondern die SYMBOLTAFEL: `_F0.wm__*` ist jede Funktion, die
# aus `kernel/wm.fi` in das Abbild gekommen ist. Im Serverabbild muss es
# davon NULL geben, fuer jedes der elf Module -- und `_F0.gfx__*` muss
# in BEIDEN stehen, denn die Naht bleibt.
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
    # Und dieselbe Frage noch einmal an den Zeichenketten, weil eine
    # Symboltafel wegfallen kann und die Daten nicht.
    treffer=""
    for w in vmode glyph raster focus cursor; do
        grep -qa -- "$w" "$TMPD/srv.mb" && treffer="$treffer $w"
        grep -qa -- "$w" "$TMPD/gui.mb" || bad "'$w' fehlt schon im GUI-Abbild -- der Pruefer misst nichts"
    done
    [ -z "$treffer" ] \
        && ok "GEGENPROBE an den Daten: keines der fuenf Woerter der Oberflaeche steht im Serverabbild" \
        || bad "im Serverabbild stehen noch Daten der Oberflaeche:$treffer"
fi

echo "== 2. der Schnitt: wer im Kernel noch auf Grafik zugreift =="

N=$(python3 tools/server/count.py kernel)
echo "        Stellen ausserhalb von kernel/gfx.fi: $N"
num "kein Modul ausser der Naht greift noch auf die Grafik zu" "$N" eq 0
python3 tools/server/count.py kernel --je-datei | sed 's/^/        /'

# UND DIE ZWEITE HAELFTE DERSELBEN FRAGE: war der Umzug ein Umzug?
# `kgui.fi` und `sysgui.fi` behaupten, dieselben Funktionen zu
# enthalten, die vorher in `kmain.fi` und `sys.fi` standen -- Zeile fuer
# Zeile. Das laesst sich nachrechnen, also wird es nachgerechnet: die
# alten Fassungen kommen aus git, die Rumpfe werden zeichenweise
# verglichen, und erlaubt ist genau die eine Abweichung, die der Umzug
# erzwingt (`neg` -> `sys.neg`, `bnum` -> `kutil.bnum`).
# RUNDE MERGE-2: DIE GRUNDLINIE DES VERGLEICHS IST NACHGEZOGEN.
# Hier stand 4f844b5 -- der Stand, von dem die Runde SERVERBUILD abgezweigt
# ist. Beim Verschmelzen nach mergeline2 stimmt der nicht mehr: main hat an
# sechs der verschobenen Funktionen weitergearbeitet (desk_start, graphics,
# netv_demo, surface, wm_call, wm_list), und diese neueren Fassungen sind
# beim Merge mit umgezogen. Gegen 4f844b5 gemessen muesste der Vergleich
# also FALLEN, und zwar zu Recht -- er verglich dann gegen einen Baum, den
# es nicht mehr gibt. Die Grundlinie ist der Stand von mergeline2
# unmittelbar VOR dem Merge; dann prueft der Vergleich genau das, was er
# prueft soll: dass der Umzug ein Umzug war und keine Neuschrift.
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

bash tools/server/build.sh "$TMPD/s" > "$TMPD/build.txt" 2>&1 \
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

# WAS DIESE ZEILEN BEWEISEN, und es ist mehr als "es lief": jeder
# Befehl wurde GETIPPT, Zeichen fuer Zeichen, in eine Steckdose, und
# die Antwort kam ueber dieselbe Leitung zurueck.
for w in 'hallo-vom-server' 'Kein Bildschirm, eine Leitung'; do
    grep -qa -- "$w" "$TMPD/shell.log" \
        && ok "die Antwort auf der Leitung enthaelt: $w" \
        || bad "die Antwort auf der Leitung enthaelt NICHT: $w"
done

echo "== 4. die Zeilendisziplin auf der Leitung =="

# RUECKSCHRITT. Getippt wird `echo ABX`, dann ein Rueckschritt, dann
# `C`. Herauskommen muss `ABC` -- und NICHT `ABXC`. Ein Terminal ohne
# Zeilenbearbeitung wuerde hier den zweiten Text liefern.
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

# OHNE console= darf die Leitung NICHT hoeren.
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

# noserirq: der Vektor wird nicht eingetragen. Es MUSS trotzdem
# ankommen -- ueber den Abfrageweg -- und `irqs=0` muss es sagen.
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
