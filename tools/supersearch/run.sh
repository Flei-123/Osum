#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/supersearch/run.sh -- RUNDE SUPERSEARCH: DIE TASTE, DAS FELD,
# DIE ORDNUNG UND DIE ZAHLEN.
#
# Was hier bewiesen wird, und nichts davon durch Behauptung:
#
#   1. DIE ZAHLEN STEHEN ZWEIMAL IM BAUM UND SIND DIESELBEN. HK_TAP in
#      kernel/kstate.fi und in kernel/user/nv.fi, WS_FLOAT in
#      kernel/sys.fi und in kernel/user/wlibc.fi. Eine Verabredung, die
#      nur an einer Stelle steht, ist keine -- Runde LOOK hat auf genau
#      diesem Weg einen echten Fehler gefunden (SYS_KBD 1780 gegen 1703).
#   2. DIE ORDNUNG, auf der Standardausgabe und nicht auf einem Bild.
#      `/bin/sucht` ruft DIESELBE Funktion, die das Fenster ruft, mit
#      achtzehn Faellen -- neun davon mit Umlauten, einer davon eine
#      Gegenprobe.
#   3. DIE TASTE ALLEIN MACHT DAS FELD AUF, und zwar durch den echten
#      PS/2-Baustein (`sendkey meta_l` auf dem QEMU-Monitor). Die
#      Gegenprobe ist die Haelfte, die zaehlt: Super+A macht es NICHT
#      auf (das geht weiter an die Schnelleinstellungen), und ein
#      gewoehnliches `a` kommt weiter als Zeichen an.
#   4. TIPPEN SUCHT SOFORT, ohne Eingabetaste, und "gro" findet eine
#      Datei, in deren Namen ueberhaupt kein `o` steht. Gegenprobe: die
#      gleichnamige Datei AUSSERHALB des Heimatverzeichnisses taucht
#      nicht auf.
#   5. OHNE MAUS. Pfeiltasten bewegen die Auswahl, die Eingabetaste
#      startet, und das gestartete Programm hat wirklich ein Fenster.
#   6. DIE BILDER WERDEN GEMESSEN UND NICHT ANGESEHEN. Tintenpunkte je
#      Beschriftung, Symbol je Zeile, die vier Ecken auf Rundung, der
#      Schatten gegen einen Lauf OHNE das Fenster. In diesem Baum war
#      schon einmal jeder Fenstertitel leer, und das Bild sah gut aus.
#   7. DIE ZAHLEN: Tastendruck bis stehendes Fenster, Tastendruck bis
#      gemaltes Fenster, je Suchlauf -- und der Index gegen den
#      Baumdurchlauf, ohne den "ein Index ist schneller" eine Behauptung
#      waere.
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"

PASS=0
FAIL=0
ok()  { echo "  OK    $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $*"; FAIL=$((FAIL+1)); }
num() { # text ist vgl soll
    local t=$1 i=$2 v=$3 s=$4
    case "$v" in
        eq) [ "${i:-x}" = "$s" ] && ok "$t: $i" || bad "$t: $i, erwartet $s" ;;
        lt) [ -n "${i:-}" ] && [ "$i" -lt "$s" ] 2>/dev/null && ok "$t: $i (< $s)" || bad "$t: $i, sollte unter $s liegen" ;;
        gt) [ -n "${i:-}" ] && [ "$i" -gt "$s" ] 2>/dev/null && ok "$t: $i (> $s)" || bad "$t: $i, sollte ueber $s liegen" ;;
    esac
}
has()    { grep -aqF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' steht nicht in $(basename "$1")"; }
hasnot() { grep -aqF -- "$2" "$1" && bad "$3 -- '$2' steht doch in $(basename "$1")" || ok "$3"; }

TMPD=$(mktemp -d)
SHOTS=docs/shots/supersearch
mkdir -p "$SHOTS"
trap 'rm -rf "$TMPD"' EXIT

feld() { grep -a "$2" "$1" | tail -1 | grep -oE "(^| )$3=[0-9]+" | tail -1 | sed 's/.*=//'; }

# =====================================================================
echo "== 1. dieselbe Zahl an beiden Stellen =="
# =====================================================================
K_TAP=$(grep -aoE '^const HK_TAP: u64 = [0-9a-fx]+' kernel/kstate.fi | grep -oE '[0-9a-fx]+$')
N_TAP=$(grep -aoE '^const HK_TAP: u64 = [0-9a-fx]+' kernel/user/nv.fi | grep -oE '[0-9a-fx]+$')
[ -n "$K_TAP" ] && [ "$K_TAP" = "$N_TAP" ] \
    && ok "HK_TAP ist im Kern und in Ring 3 dieselbe Zahl ($K_TAP)" \
    || bad "HK_TAP: Kern sagt '${K_TAP:-nichts}', Ring 3 sagt '${N_TAP:-nichts}'"
# UND SIE LIEGT UEBER UNICODE. Das ist die ganze Begruendung fuer die
# Wahl: ein Zeichen kann diese Zahl nicht sein.
[ -n "$K_TAP" ] && [ "$((K_TAP))" -gt 1114111 ] \
    && ok "und sie liegt ueber dem groessten Codepunkt ($((K_TAP)) > 1114111)" \
    || bad "HK_TAP koennte ein Zeichen sein"
K_FL=$(grep -aoE '^const WS_FLOAT: u64 = [0-9]+' kernel/sys.fi | grep -oE '[0-9]+$')
W_FL=$(grep -aoE '^const WS_FLOAT: u64 = [0-9]+' kernel/user/wlibc.fi | grep -oE '[0-9]+$')
[ -n "$K_FL" ] && [ "$K_FL" = "$W_FL" ] \
    && ok "WS_FLOAT ist im Kern und in der Bibliothek dieselbe Zahl ($K_FL)" \
    || bad "WS_FLOAT: Kern '${K_FL:-nichts}', Bibliothek '${W_FL:-nichts}'"
# DIE ABFRAGE STEHT VOR DEN MODIFIKATOREN. Stuende sie danach, waere
# Super+Umschalt ein Tippen auf Super -- die Umschalttaste kehrt vorher
# zurueck. Die Zeilennummern sagen es.
L_USED=$(grep -n 'KB_SUPER_USED, 1)' kernel/kbd.fi | head -1 | cut -d: -f1)
L_SHIFT=$(grep -n 'KB_SHIFT, 1)' kernel/kbd.fi | head -1 | cut -d: -f1)
[ -n "$L_USED" ] && [ -n "$L_SHIFT" ] && [ "$L_USED" -lt "$L_SHIFT" ] \
    && ok "die Abfrage steht vor den Modifikatoren (Zeile $L_USED vor $L_SHIFT)" \
    || bad "KB_SUPER_USED wird erst nach den Modifikatoren gesetzt ($L_USED/$L_SHIFT)"
# DIE MELDUNG DARF DIE ZAEHLUNG DER RUNDE NETVIEW NICHT BEWEGEN.
if printf 'hk: super\nhk: super+a\n' | grep -c '^hk: super+a$' | grep -q '^1$'; then
    ok "'hk: super' trifft das Muster '^hk: super+a\$' NICHT (die Zaehlung von NETVIEW bleibt)"
else
    bad "die neue Meldung veraendert die Zaehlung der Runde NETVIEW"
fi
if python3 tools/supersearch/pad.py --pruefe kernel/user/sucher.fi \
        kernel/user/sucht.fi > "$TMPD/pad.txt" 2>&1; then
    ok "jedes Zeichenkettenfeld ist so lang wie sein Inhalt ($(tail -1 "$TMPD/pad.txt"))"
else
    bad "Zeichenkettenfelder passen nicht: $(cat "$TMPD/pad.txt")"
fi
echo

# =====================================================================
echo "== 2. die Ordnung, auf der Standardausgabe =="
# =====================================================================
# DIESELBE FUNKTION WIE DAS FENSTER, nicht eine zweite Fassung davon.
# Ein Bild sagt, WAS oben steht; diese Tabelle sagt, WARUM.
bash tools/supersearch/shot.sh "$TMPD/o" script="sucht" > "$TMPD/o.log" 2>&1
if [ -s "$TMPD/o/serial.txt" ]; then
    G=$(feld "$TMPD/o/serial.txt" 'sucht: faelle' 'gut')
    V=$(feld "$TMPD/o/serial.txt" 'sucht: faelle' 'von')
    grep -a '^sucht: fall' "$TMPD/o/serial.txt" | sed 's/^/     /'
    num "alle Faelle der Rangfolge stimmen (von $V)" "$G" eq "${V:-0}"
    num "und es waren wirklich achtzehn" "$V" eq 18
    # DIE EINZELNEN, damit ein gruener Block nicht alles verdeckt
    has "$TMPD/o/serial.txt" 'q=[gro] name=[Größe] rk=1' \
        "2: 'gro' findet 'Groesse' mit Umlaut am WORTANFANG -- und darin steht kein o"
    has "$TMPD/o/serial.txt" 'q=[GRÖSSE] name=[größe] rk=0' \
        "2: gross mit Umlaut und klein mit Umlaut sind dasselbe Wort"
    has "$TMPD/o/serial.txt" 'q=[größe] name=[Größe] rk=0' \
        "2: und mit Umlaut getippt ist es ein GENAUER Treffer"
    has "$TMPD/o/serial.txt" 'q=[x] name=[Größe] rk=9' \
        "2: GEGENPROBE -- ein Buchstabe, der nicht vorkommt, findet nichts"
    has "$TMPD/o/serial.txt" 'falt=[groesse]' \
        "2: die Faltung macht aus dem Umlaut wirklich zwei Buchstaben"
else
    bad "2: der Lauf von /bin/sucht hat nichts geschrieben"
fi
echo
# =====================================================================
echo "== 3. die Taste allein, durch den echten PS/2-Baustein =="
# =====================================================================
lauf() { # name treiber [extra]
    local n=$1 dr=$2 ex=${3:-}
    bash tools/supersearch/shot.sh "$TMPD/$n" drive="$dr" extra="$ex" \
        > "$TMPD/$n.out" 2>&1
    L="$TMPD/$n/serial.txt"
    P="$TMPD/$n/bild.ppm"
    [ -s "$L" ]
}
png() { python3 - "$1" "$SHOTS/$2.png" <<'PYX' 2>/dev/null
import sys
from PIL import Image
Image.open(sys.argv[1]).convert("RGB").save(sys.argv[2])
PYX
}

printf 'warte 8\nsendkey a\nwarte 1\nsendkey meta_l\nwarte 3\n' > "$TMPD/dr-leer"
if lauf leer "$TMPD/dr-leer"; then
    has "$L" "hk: super" "3: der Kern hat das Tippen auf die Taste allein gesehen"
    has "$L" "sucher: open" "3: und das Suchfeld ist aufgegangen"
    n_key=$(grep -ac '^key: a$' "$L")
    num "3: ein gewoehnliches 'a' kommt weiter als Zeichen an" "$n_key" eq 1
    n_hk=$(grep -ac '^hk: super$' "$L")
    num "3: genau ein Tippen auf die Taste in diesem Lauf" "$n_hk" eq 1
    hasnot "$L" "hk: super+" "3: und es war KEIN Kuerzel mit Buchstaben"
    X=$(feld "$L" 'sucher: open' 'x'); Y=$(feld "$L" 'sucher: open' 'y')
    WW=$(feld "$L" 'sucher: open' 'w'); HH=$(feld "$L" 'sucher: open' 'h')
    WX=$(feld "$L" 'taskbar: work' 'x'); WY=$(feld "$L" 'taskbar: work' 'y')
    WW2=$(feld "$L" 'taskbar: work' 'w'); WH2=$(feld "$L" 'taskbar: work' 'h')
    # MITTIG IN DER ARBEITSFLAECHE und nicht in der Mitte des Schirms:
    # bei einer Leiste am oberen Rand ist das ein Unterschied von deren
    # halber Hoehe.
    MX=$(( WX + (WW2 - WW) / 2 )); MY=$(( WY + (WH2 - HH) / 2 ))
    num "3: das Feld steht waagerecht in der Mitte der Arbeitsflaeche" "$X" eq "$MX"
    num "3: und senkrecht ebenso" "$Y" eq "$MY"
    # OHNE EINGABE STEHEN PROGRAMME DA und nicht nichts.
    T0=$(feld "$L" 'sucher: query \[\]' 'treffer')
    num "3: ohne Eingabe stehen die zuletzt benutzten Programme da" "$T0" gt 0
    if [ -s "$P" ]; then
        png "$P" "popup-leer"
        python3 tools/supersearch/messen.py zeilen "$P" "$L" > "$TMPD/z0" 2>&1 \
            && ok "3: jede Beschriftung im Bild hat wirklich Tinte -- $(tail -1 "$TMPD/z0")" \
            || { bad "3: leere Beschriftungen im Bild"; sed 's/^/       /' "$TMPD/z0"; }
        python3 tools/supersearch/messen.py feld "$P" "$L" > "$TMPD/f0" 2>&1 \
            && ok "3: im Eingabefeld steht der Hinweistext -- $(cat "$TMPD/f0")" \
            || bad "3: das Eingabefeld ist leer"
        python3 tools/supersearch/messen.py ecke "$P" "$L" > "$TMPD/e0" 2>&1 \
            && ok "3: alle vier Ecken sind rund und nicht eckig" \
            || { bad "3: eine Ecke ist eckig"; sed 's/^/       /' "$TMPD/e0"; }
    else
        bad "3: kein Bild vom leeren Suchfeld"
    fi
else
    bad "3: der Lauf mit der Super-Taste hat nichts geschrieben"
fi
echo

# =====================================================================
echo "== 4. die Gegenprobe: Super+A ist KEIN Tippen auf Super =="
# =====================================================================
# DAS IST DIE HAELFTE, DIE ZAEHLT. Wuerde Super+A das Suchfeld
# aufmachen, waere jedes bestehende Kuerzel dieses Systems kaputt -- und
# ein Abschnitt 3, der nur zeigt, dass die Taste etwas TUT, bewiese
# nicht, dass sie das RICHTIGE tut.
printf 'warte 8\nsendkey meta_l-a\nwarte 3\n' > "$TMPD/dr-plus"
if lauf plus "$TMPD/dr-plus"; then
    has "$L" "hk: super+a" "4: der Kern hat Super+A als Kuerzel gesehen"
    hasnot "$L" "hk: super
" "4: und NICHT zusaetzlich als Tippen auf die Taste allein"
    hasnot "$L" "sucher: open" "4: das Suchfeld ist zugeblieben"
    has "$L" "qs: open" "4: die Schnelleinstellungen sind aufgegangen -- das Kuerzel wirkt wie vorher"
    n_a=$(grep -ac '^key: a$' "$L")
    num "4: und Super+A hat KEIN 'a' in das Fenster darunter getippt" "$n_a" eq 0
else
    bad "4: der Lauf mit Super+A hat nichts geschrieben"
fi
echo
# =====================================================================
echo "== 5. tippen sucht sofort -- und 'gro' findet ein Wort ohne o =="
# =====================================================================
printf 'warte 8\nsendkey meta_l\nwarte 2\nsendkey g\nwarte 1\nsendkey r\nwarte 1\nsendkey o\nwarte 3\n' > "$TMPD/dr-gro"
if lauf gro "$TMPD/dr-gro"; then
    # DREI SUCHLAEUFE FUER DREI TASTEN, ohne dass eine Eingabetaste
    # gedrueckt wurde. Genau das ist "waehrend der Eingabe".
    n_q=$(grep -ac '^sucher: query \[g' "$L")
    num "5: jeder Tastendruck hat einen Suchlauf ausgeloest" "$n_q" eq 3
    has "$L" "sucher: query [gro]" "5: und der letzte war [gro]"
    T=$(feld "$L" 'sucher: query \[gro\]' 'treffer')
    D=$(feld "$L" 'sucher: query \[gro\]' 'dateien')
    num "5: 'gro' findet Dateien, in deren Namen kein 'o' steht" "$D" gt 0
    num "5: und ueberhaupt Treffer" "$T" gt 0
    grep -a 'sucher: zeile' "$L" | tail -"${T:-2}" | sed 's/^/     /'
    # DIE GEGENPROBE ZUM HEIMATFILTER. Unter /aussen liegt eine Datei
    # mit demselben Namen. Sie darf nicht dabei sein -- sonst waere
    # "Dateien im Heimatverzeichnis" nur die halbe Wahrheit.
    if grep -a 'sucher: zeile' "$L" | tail -"${T:-2}" | grep -qa '/aussen/'; then
        bad "5: eine Datei AUSSERHALB des Heimatverzeichnisses steht in der Liste"
    else
        ok "5: GEGENPROBE -- die gleichnamige Datei unter /aussen taucht NICHT auf"
    fi
    U=$(feld "$L" 'sucher: index' 'unter')
    N=$(feld "$L" 'sucher: index' 'n')
    num "5: der Heimatfilter siebt wirklich (von $N Namen bleiben)" "$U" lt "${N:-99999}"
    if [ -s "$P" ]; then
        png "$P" "treffer-umlaut"
        python3 tools/supersearch/messen.py zeilen "$P" "$L" > "$TMPD/z1" 2>&1 \
            && ok "5: die Treffer mit Umlaut stehen wirklich im Bild -- $(tail -1 "$TMPD/z1")" \
            || { bad "5: der Umlaut-Treffer ist im Bild leer"; sed 's/^/       /' "$TMPD/z1"; }
        # UND DIE EINGABE STEHT IM FELD. Ein Suchfeld, das sucht, ohne zu
        # zeigen, was es sucht, ist keins.
        python3 tools/supersearch/messen.py feld "$P" "$L" > "$TMPD/f1" 2>&1 \
            && ok "5: das Getippte steht im Eingabefeld -- $(cat "$TMPD/f1")" \
            || bad "5: das Eingabefeld ist leer, obwohl getippt wurde"
    else
        bad "5: kein Bild vom Tippen"
    fi
else
    bad "5: der Lauf mit 'gro' hat nichts geschrieben"
fi
echo

# =====================================================================
echo "== 6. die Rangfolge im laufenden System =="
# =====================================================================
printf 'warte 8\nsendkey meta_l\nwarte 2\nsendkey e\nwarte 3\n' > "$TMPD/dr-e"
if lauf ordn "$TMPD/dr-e"; then
    A=$(feld "$L" 'sucher: query \[e\]' 'apps')
    D=$(feld "$L" 'sucher: query \[e\]' 'dateien')
    S=$(feld "$L" 'sucher: query \[e\]' 'einst')
    num "6: ein einzelnes 'e' findet Programme" "$A" gt 0
    num "6: und Dateien" "$D" gt 0
    num "6: und Einstellungsseiten" "$S" gt 0
    # DIE ORDNUNG IST DIE ZUSAGE: nach Rang, und bei gleichem Rang nach
    # Quelle. Beides steht in jeder Zeile, also laesst es sich
    # nachrechnen statt ansehen.
    ordnung=$(grep -a 'sucher: zeile' "$L" | tail -8 \
        | sed -E 's/.* src=([0-9]+) rk=([0-9]+) .*/\2\1/' | tr '\n' ' ')
    sortiert=$(echo "$ordnung" | tr ' ' '\n' | grep -v '^$' | sort -n | tr '\n' ' ')
    if [ "$ordnung" = "$sortiert" ]; then
        ok "6: die Liste steht wirklich nach (Rang, Quelle) sortiert -- $ordnung"
    else
        bad "6: die Liste steht nicht sortiert: [$ordnung] statt [$sortiert]"
    fi
    if [ -s "$P" ]; then
        png "$P" "popup-treffer"
        python3 tools/supersearch/messen.py zeilen "$P" "$L" > "$TMPD/z2" 2>&1 \
            && ok "6: alle acht Zeilen der Liste stehen im Bild -- $(tail -1 "$TMPD/z2")" \
            || { bad "6: eine Zeile der Liste ist im Bild leer"; sed 's/^/       /' "$TMPD/z2"; }
    else
        bad "6: kein Bild der Trefferliste"
    fi
else
    bad "6: der Lauf mit 'e' hat nichts geschrieben"
fi
echo

# =====================================================================
echo "== 7. ohne Maus: Pfeil, Pfeil, Eingabetaste, und ein Fenster =="
# =====================================================================
printf 'warte 8\nsendkey meta_l\nwarte 2\nsendkey w\nwarte 1\nsendkey i\nwarte 1\nsendkey d\nwarte 2\nsendkey ret\nwarte 5\n' > "$TMPD/dr-start"
if lauf start "$TMPD/dr-start"; then
    has "$L" "sucher: query [wid]" "7: drei Tasten, drei Suchlaeufe, keine Eingabetaste dazwischen"
    has "$L" "sucher: start [" "7: die Eingabetaste hat wirklich ein Programm gestartet"
    has "$L" "sucher: closed by start" "7: und das Feld ist danach von selbst zugegangen"
    PID=$(feld "$L" 'sucher: start' 'pid')
    num "7: der Start hat eine Prozessnummer bekommen" "$PID" gt 0
    ZH=$(feld "$L" 'sucher: zaehler' 'n')
    num "7: und der Zaehler des Programms steht auf" "$ZH" gt 0
    if [ -s "$P" ]; then
        png "$P" "programm-gestartet"
        # DAS FENSTER IST WIRKLICH DA. Der Server zaehlt seine Fenster;
        # ein Start, der nur eine Zeile auf der seriellen Leitung
        # erzeugt, ist kein Start.
        NW=$(grep -a 'taskbar: btn' "$L" | tail -1 | grep -oE 'n=[0-9]+' | sed 's/.*=//')
        num "7: die Taskleiste hat einen Knopf mehr" "${NW:-0}" gt 1
        ink=$(python3 tools/look/inkbox.py "$P" 0 0 800 572 255 255 255 2>/dev/null | grep -oE 'ink [0-9]+' | grep -oE '[0-9]+')
        num "7: und auf dem Schirm steht wirklich etwas" "${ink:-0}" gt 10000
    else
        bad "7: kein Bild vom gestarteten Programm"
    fi
else
    bad "7: der Lauf mit der Eingabetaste hat nichts geschrieben"
fi
# DIE PFEILTASTEN, in einem eigenen Lauf: die Auswahl muss sich bewegen.
printf 'warte 8\nsendkey meta_l\nwarte 2\nsendkey e\nwarte 2\nsendkey down\nwarte 1\nsendkey down\nwarte 1\nsendkey up\nwarte 2\nsendkey esc\nwarte 2\n' > "$TMPD/dr-pfeil"
if lauf pfeil "$TMPD/dr-pfeil"; then
    # `sel=1` steht in genau der Zeile, die gerade gewaehlt ist. Ueber
    # den ganzen Lauf muessen es MEHRERE verschiedene gewesen sein.
    versch=$(grep -a 'sucher: zeile' "$L" | grep -a 'sel=1' \
        | sed -E 's/^sucher: zeile n=([0-9]+) .*/\1/' | sort -u | tr '\n' ' ')
    anz=$(echo "$versch" | wc -w)
    num "7: die Pfeiltasten haben die Auswahl auf verschiedene Zeilen bewegt ($versch)" "$anz" gt 1
    has "$L" "sucher: closed by escape" "7: und die Fluchttaste macht es zu"
else
    bad "7: der Lauf mit den Pfeiltasten hat nichts geschrieben"
fi
echo
# =====================================================================
echo "== 8. Schatten und Ecke -- und die Gegenprobe, die sie wegnimmt =="
# =====================================================================
# EIN LAUF OHNE DAS FENSTER, damit der Schatten einen Vergleich hat. Er
# faellt AUSSERHALB des Fensterrechtecks; ohne ein zweites Bild vom
# selben Fleck ist "da ist ein Schatten" nicht nachpruefbar.
bash tools/supersearch/shot.sh "$TMPD/ohne" > "$TMPD/ohne.out" 2>&1
if [ -s "$TMPD/ohne/bild.ppm" ] && [ -s "$TMPD/leer/bild.ppm" ]; then
    if python3 tools/supersearch/messen.py schatten "$TMPD/leer/bild.ppm" \
        "$TMPD/ohne/bild.ppm" "$TMPD/leer/serial.txt" > "$TMPD/sch" 2>&1; then
        ok "8: neben dem Fenster ist es dunkler als ohne das Fenster -- $(cat "$TMPD/sch")"
    else
        bad "8: kein Schatten neben dem Fenster: $(cat "$TMPD/sch")"
    fi
else
    bad "8: der Vergleichslauf ohne Fenster hat kein Bild geliefert"
fi
# DIE GEGENPROBE: der Satz `classic` hat radius_window=0 und shadow=0.
# Dasselbe Fenster MUSS dann eckig und ohne Schatten sein. Eine
# Messung, die nicht scheitern kann, misst nichts.
bash tools/supersearch/shot.sh "$TMPD/klassisch" drive="$TMPD/dr-leer" \
    shape=classic > "$TMPD/kl.out" 2>&1
if [ -s "$TMPD/klassisch/bild.ppm" ]; then
    python3 tools/supersearch/messen.py ecke "$TMPD/klassisch/bild.ppm" \
        "$TMPD/klassisch/serial.txt" > "$TMPD/ek" 2>&1
    ecken=$(grep -c 'ECKIG' "$TMPD/ek")
    num "8: GEGENPROBE shape=classic -- alle vier Ecken sind eckig" "$ecken" eq 4
    if python3 tools/supersearch/messen.py schatten "$TMPD/klassisch/bild.ppm" \
        "$TMPD/ohne/bild.ppm" "$TMPD/klassisch/serial.txt" > "$TMPD/sk" 2>&1; then
        bad "8: GEGENPROBE shape=classic wirft trotzdem einen Schatten -- $(cat "$TMPD/sk")"
    else
        ok "8: GEGENPROBE shape=classic wirft KEINEN Schatten -- $(cat "$TMPD/sk")"
    fi
else
    bad "8: kein Bild vom klassischen Satz"
fi
echo

# =====================================================================
echo "== 9. der Index gegen den Baumdurchlauf =="
# =====================================================================
# OHNE DIESE ZWEITE ZAHL WAERE "EIN INDEX IST SCHNELLER" EINE
# BEHAUPTUNG. Der Baumdurchlauf sieht dieselben Namen an, aber er holt
# sie bei JEDEM Lauf von der Platte; der Index steht im Speicher.
bash tools/supersearch/shot.sh "$TMPD/baum" drive="$TMPD/dr-gro" \
    extra="sbaum" > "$TMPD/baum.out" 2>&1
L="$TMPD/baum/serial.txt"
if [ -s "$L" ]; then
    IB=$(feld "$L" 'sucher: index' 'us')
    IN=$(feld "$L" 'sucher: index' 'n')
    BU=$(feld "$L" 'sucher: baum' 'us')
    SU=$(grep -a 'sucher: query \[gro\]' "$L" | tail -1 | grep -oE 'us=[0-9]+' | sed 's/.*=//')
    if [ -n "${IB:-}" ] && [ -n "${BU:-}" ] && [ -n "${SU:-}" ] && [ "$SU" -gt 0 ]; then
        ok "9: der Aufbau des Index: $IB us fuer $IN Namen -- EINMAL, beim Start der Leiste"
        ok "9: ein Baumdurchlauf: $BU us -- das waere der Preis JEDES Tastendrucks"
        ok "9: ein Suchlauf im Index: $SU us"
        num "9: der Baum ist teurer als eine Suche im Index" "$BU" gt "$SU"
        echo "        -> Faktor $((BU / SU)) je Tastendruck; der Aufbau hat sich nach $((IB / (BU - SU) + 1)) Tasten bezahlt"
    else
        bad "9: nicht beide Zeiten gemessen (index=${IB:-nichts} baum=${BU:-nichts} suche=${SU:-nichts})"
    fi
else
    bad "9: der Lauf mit der Gegenprobe hat nichts geschrieben"
fi
echo

# =====================================================================
echo "== 10. die Zahlen =="
# =====================================================================
L="$TMPD/leer/serial.txt"
if [ -s "$L" ]; then
    UP=$(feld "$L" 'sucher: open' 'up')
    US=$(feld "$L" 'sucher: open' 'us')
    FU=$(feld "$L" 'sucher: open' 'fuell')
    RI=$(feld "$L" 'sucher: open' 'ring')
    ZE=$(feld "$L" 'sucher: open' 'zeilen')
    PU=$(feld "$L" 'sucher: open' 'push')
    ok "10: Tastendruck bis STEHENDES Fenster: $UP us (Warten auf den Blick der Leiste)"
    ok "10: Tastendruck bis GEMALTES Fenster:  $US us"
    ok "10: davon Zeichnen: $((US - UP)) us -- fuellen $FU, Rahmen $RI, Zeilen $ZE, uebergeben $PU"
    num "10: und das Ganze bleibt unter einer fuenftel Sekunde" "$US" lt 200000
    num "10: der Suchlauf bleibt unter zehn Millisekunden" \
        "$(grep -a 'sucher: query' "$L" | tail -1 | grep -oE 'us=[0-9]+' | sed 's/.*=//')" lt 10000
else
    bad "10: keine Zahlen"
fi

echo
echo "SUPERSEARCH: $PASS bestanden, $FAIL fehlgeschlagen"
[ "$FAIL" -eq 0 ]
