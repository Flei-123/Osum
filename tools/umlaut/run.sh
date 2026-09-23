#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/umlaut/run.sh -- DIE ABNAHME DER RUNDE UMLAUT2.
#
# WOGEGEN DIESE RUNDE ANTRITT. Im Programmstarter stand ein halbes Jahr
# lang "Text schreiben und aendern", waehrend zwei Zeilen tiefer schon
# "Ausführen" richtig erschien. Runde LOOK hat diesen einen Satz geholt
# und dazu `tools/i18n/translit.py` gebaut -- einen Pruefer, der
# `locale/de/*` und die Buendel liest. Beide waren danach sauber, und
# trotzdem stand im Baum weiter Umschrift auf dem Schirm: DIE
# BESCHRIFTUNGEN DER PROGRAMME SELBST STEHEN IM QUELLTEXT, und dorthin
# sah kein Pruefer.
#
# Das ist die Luecke, die hier zugeht. Und weil ein Pruefer, den man
# nicht widerlegen kann, nichts wert ist, hat hier fast jede Zusage eine
# GEGENPROBE: eine Kopie des Baums mit EINEM absichtlichen Fehler muss
# rot werden. Ein Kommentar in `locale/de/messages` hat einmal woertlich
# "HIER STEHEN ECHTE UMLAUTE" behauptet, waehrend keiner drinstand --
# eine Behauptung ueber sich selbst ist keine Messung.
#
# WAS GEMESSEN WIRD
#
#   A. DER BAUM, statisch, in Sekunden:
#      1. locale/de/* und assets/apps/*.osp/INFO: null Umschrift.
#      2. `keys=` traegt die Umlautform NEBEN der Umschrift.
#      3. kernel/**/*.fi: null SICHTBARE Umschrift -- und die beiden
#         Ausnahmen (Mitschnitt, getippte Marke) sind keine Hintertuer.
#      4. Jede getippte Marke nimmt BEIDE Schreibungen an.
#      5. Die Beschriftungsspalten sind in ZEICHEN gleich breit, und
#         jedes Literal passt genau in seinen Puffer.
#      6. Die ausgelieferten Schriften haben jedes Zeichen ueber ASCII,
#         das irgendwo im sichtbaren Text steht.
#      7. Wo "vier Zeichen" verlangt wird, werden Zeichen gezaehlt und
#         nicht Oktette.
#      7b. KEINE ABNAHME SUCHT MEHR NACH DEM ALTEN TEXT. Die zweite
#         Sorte Leiche sitzt nicht im System, sondern im Laeufer:
#         `tiling.fi` sagte "tiling: Einträge gelesen",
#         `tools/tiling/run.sh` suchte "tiling: Eintraege" -- rot,
#         obwohl nichts fehlte. `tools/i18n/erwartung.py` vergleicht
#         die Suchausdruecke aller 124 Laeufer gegen die Saetze des
#         Baums. Nur Saetze MIT Programmpraefix; Beschreibungen und
#         getippte Eingaben bleiben ausdruecklich in Ruhe.
#
#   B. DAS BILD, in QEMU (mit -accel kvm, wo es geht):
#      8.  der Starter mit den Programmbeschreibungen -- dort stand
#          "aendern",
#      9.  die Einstellungen,
#      10. der Speicher-Dialog mit seinen Spalten.
#      Gemessen wird nicht "es sieht gut aus": `tools/look/umlaut.py`
#      rastert den erwarteten Satz aus derselben Schriftdatei und
#      vergleicht JEDEN Tintenpunkt an der Stelle, an der der
#      Fensterserver ihn gemeldet hat. Ein abgeschnittener Text faellt
#      dabei durch, ein leerer erst recht.
#
# Verwendung:  bash tools/umlaut/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
ROOT=$(pwd)

TMPD=${TMPD:-$(mktemp -d)}
KEEP=${KEEP:-0}
[ "$KEEP" = 1 ] || trap 'rm -rf "$TMPD"' EXIT
mkdir -p "$TMPD"
SHOTS=docs/shots/umlaut2
mkdir -p "$SHOTS"

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', erwartet '$3'"; fi; }
mind() { if [ "${2:-0}" -ge "$3" ]; then ok "$1 ($2)"; else bad "$1: $2, erwartet mindestens $3"; fi; }
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hatnicht() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da" || ok "$3"; }

# Eine Kopie des Baums, in der genau EINE Stelle verbogen ist.
kopie() {
    local k=$1
    rm -rf "$k"; mkdir -p "$k"
    cp -r kernel lib locale assets tools tests "$k"/ 2>/dev/null
}

# gegen <was> <datei> <alt> <neu> <befehl...>
# Gruen, wenn der Befehl auf der verbogenen Kopie einen Fehler meldet.
gegen() {
    local was=$1 datei=$2 alt=$3 neu=$4; shift 4
    local k="$TMPD/kopie"
    kopie "$k"
    python3 - "$k/$datei" "$alt" "$neu" <<'PY'
import sys
p, alt, neu = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding='utf-8').read()
if alt not in s:
    sys.stderr.write("GEGENPROBE: %r steht nicht in %s\n" % (alt[:60], p))
    sys.exit(3)
open(p, 'w', encoding='utf-8').write(s.replace(alt, neu, 1))
PY
    if [ $? -ne 0 ]; then
        bad "GEGENPROBE $was: liess sich nicht vorbereiten"
        return
    fi
    ( cd "$k" && OSUM_ROOT=. "$@" ) > "$TMPD/gegen.txt" 2>&1
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        ok "GEGENPROBE $was: der Pruefer wird rot (rc=$rc)"
    else
        bad "GEGENPROBE $was: der Pruefer bleibt gruen -- er prueft das nicht"
        sed 's/^/        /' "$TMPD/gegen.txt" | head -5
    fi
}

echo "UMLAUT2: die Abnahme"
echo
echo "== A. DER BAUM"
echo
echo "-- 1. die Sprachdateien und die Buendel"
OSUM_ROOT=. python3 tools/i18n/translit.py --zaehle > "$TMPD/t.txt" 2>&1
TRC=$?
sed 's/^/     /' "$TMPD/t.txt"
is "translit rc" "$TRC" "0"
U=$(sed -n 's/^translit: geprueft=[0-9]* umschrift=\([0-9]*\).*/\1/p' "$TMPD/t.txt")
G=$(sed -n 's/^translit: geprueft=\([0-9]*\) umschrift=[0-9]*.*/\1/p' "$TMPD/t.txt")
UML=$(sed -n 's/.*echte Umlautzeichen in locale\/de + assets\/apps: \([0-9]*\).*/\1/p' "$TMPD/t.txt")
is "Umschrift in locale/de und den Buendeln" "${U:-?}" "0"
mind "geprueft wurden genug Werte, um etwas zu heissen" "${G:-0}" 200
mind "und es stehen echte Umlautzeichen darin" "${UML:-0}" 90

# RUNDE ROTABSCHNITTE: DER SATZ STEHT JETZT IM KATALOG.
# Hier stand `assets/apps/editor.osp/INFO`. Seit c101990 traegt die
# INFO die englische Fassung ("Write and change text"); der deutsche
# Satz kommt seit ROTABSCHNITTE 17/n aus locale/de/messages
# (`editor.info`), und `appdir.info_of` holt ihn dort. Die Gegenprobe
# pflanzt die Umschrift deshalb dort ein, wo der Satz heute steht --
# sie misst weiter dasselbe: dass der Pruefer eine Umschrift in einem
# SICHTBAREN Text findet.
gegen "der Satz aus dem Buendel" "locale/de/messages" \
    "editor.info = Text schreiben und ändern" \
    "editor.info = Text schreiben und aendern" \
    python3 tools/i18n/translit.py
gegen "eine Zeile im Katalog" "locale/de/messages" \
    "launcher.run = Ausführen" "launcher.run = Ausfuehren" \
    python3 tools/i18n/translit.py

echo
echo "-- 2. die Suchwoerter: die Umlautform steht DANEBEN, nicht STATT"
hat assets/apps/launcher.osp/INFO "menue,menü" \
    "keys= des Starters traegt beide Schreibungen"
gegen "die Umlautform in keys=" "assets/apps/launcher.osp/INFO" \
    "menue,menü," "menue," \
    python3 tools/i18n/translit.py

echo
echo "-- 3. der Quelltext: keine sichtbare Umschrift mehr"
OSUM_ROOT=. python3 tools/i18n/quellen.py --alle > "$TMPD/q.txt" 2>&1
sed -n '1p' "$TMPD/q.txt" | sed 's/^/     /'
S=$(sed -n 's/.*SICHTBAR=\([0-9]*\).*/\1/p' "$TMPD/q.txt")
M=$(sed -n 's/.*MITSCHNITT=\([0-9]*\).*/\1/p' "$TMPD/q.txt")
K=$(sed -n 's/.*MARKE=\([0-9]*\).*/\1/p' "$TMPD/q.txt")
N=$(sed -n 's/^quellen: \([0-9]*\) Umschriften.*/\1/p' "$TMPD/q.txt")
is "SICHTBARE Umschrift in kernel/**" "${S:-?}" "0"
mind "der Pruefer findet ueberhaupt Umschrift (Mitschnitt ${M:-?}, Marke ${K:-?})" "${N:-0}" 10

# DIE WICHTIGSTE GEGENPROBE DIESES LAEUFERS. Eine Beschriftung an einem
# BEDIENELEMENT in einem FENSTERPROGRAMM -- genau diese Sorte war es,
# die im Starter stand. Und genau hier koennte die Ausnahme
# "Mitschnitt" zur Hintertuer werden: `themetest.fi` bindet `wlib` ein,
# also faellt alles darin unter die Ausnahme, wenn man sie falsch zieht.
gegen "eine Beschriftung in einem FENSTERPROGRAMM" \
    "kernel/user/themetest.fi" \
    'g_ent: [u8; 31] = "ein Textfeld mit Einfügemarke\0"' \
    'g_ent: [u8; 31] = "ein Textfeld mit Einfuegemarke\0"' \
    python3 tools/i18n/quellen.py --streng
gegen "eine Meldung eines Befehls" "kernel/user/opk.fi" \
    'E_HASH: [u8; 23] = "opk: Prüfsumme falsch\0"' \
    'E_HASH: [u8; 23] = "opk: Pruefsumme falsch\0"' \
    python3 tools/i18n/quellen.py --streng
gegen "eine Beschriftung im Speicher-Dialog" "kernel/user/storage.fi" \
    't_del: [u8; 12] = "Löschen\0\0\0\0"' \
    't_del: [u8; 12] = "Loeschen\0\0\0"' \
    python3 tools/i18n/quellen.py --streng

# DIE GEGEN-GEGENPROBE: die Ausnahme muss auch WIRKEN. Eine neue Zeile
# im Mitschnitt eines Fensterprogramms darf NICHT rot werden -- sonst
# ist der Pruefer nur laut und nicht richtig, und der Naechste, den er
# grundlos anmeckert, schaltet ihn ab.
k2="$TMPD/kopie2"; kopie "$k2"
python3 - "$k2/kernel/user/storage.fi" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
alt = 'fn lines_report() {\n'   # vor Runde ENGLISCH: zeilen_melden
neu = ('fn lines_report() {\n'
       '    var s_pr: [u8; 28] = "speicher: hat geloescht n=\\0\\0"\n'
       '    say((&s_pr[0 as usize]) as u64)\n')
assert alt in s, "der Anker fehlt"
open(p, 'w', encoding='utf-8').write(s.replace(alt, neu, 1))
PY
# Gemessen wird die ZAHL der sichtbaren Umschriften vorher/nachher, nicht
# der Rueckgabewert: solange der Baum selbst noch sichtbare Umschrift hat
# (Abschnitt 3), ist `--streng` ohnehin rot, und diese Probe waere es mit.
sichtbar() { sed -n 's/.*SICHTBAR=\([0-9]*\).*/\1/p' "$1" | head -1; }
python3 tools/i18n/quellen.py > "$TMPD/gegen2-vor.txt" 2>&1
( cd "$k2" && OSUM_ROOT=. python3 tools/i18n/quellen.py ) \
    > "$TMPD/gegen2.txt" 2>&1
SV=$(sichtbar "$TMPD/gegen2-vor.txt"); SN=$(sichtbar "$TMPD/gegen2.txt")
if [ -n "$SV" ] && [ "$SV" = "$SN" ] \
   && ! grep -qE 'SICHTBAR +kernel/user/storage.fi .*s_pr' "$TMPD/gegen2.txt"; then
    ok "GEGEN-GEGENPROBE: eine neue MITSCHNITT-Zeile macht nichts sichtbar ($SV -> $SN) -- die Ausnahme wirkt"
else
    bad "GEGEN-GEGENPROBE: der Pruefer meckert den Mitschnitt an (sichtbar $SV -> $SN)"
    sed 's/^/        /' "$TMPD/gegen2.txt" | head -4
fi

# DRAHT-Ketten: Woerter eines Formats/Protokolls, die ein anderes
# Programm Oktett fuer Oktett erwartet (Bruecken-Gruss, OTA-Signaturtext,
# Feldnamen). Runde ROTABSCHNITTE 5 hatte zehn davon "entschriftet".
drahtumlaut() { grep -rnE --include='*.fi' '"[^"]*[äöüÄÖÜß][^"]*".*//[[:space:]]*DRAHT' "$1" | wc -l; }
is "DRAHT-Ketten mit Umlaut (Formatwoerter muessen ASCII bleiben)" "$(drahtumlaut kernel)" "0"
k3="$TMPD/kopie3"; mkdir -p "$k3"
sed 's|"osum-bruecke 1|"osum-brücke 1|' kernel/app/jarvisd.fi > "$k3/jarvisd.fi"
is "GEGENPROBE der Bruecken-Gruss mit Umlaut wird gefunden" "$(drahtumlaut "$k3")" "1"
DN=$(grep -rcE --include='*.fi' '//[[:space:]]*DRAHT' kernel | awk -F: '{s+=$2} END{print s+0}')
if [ "$DN" -ge 13 ]; then ok "DRAHT-Marken im Kern: $DN"; else bad "DRAHT-Marken im Kern: $DN, erwartet >= 13"; fi

echo
echo "-- 4. jede getippte Marke nimmt beide Schreibungen"
OSUM_ROOT=. python3 tools/i18n/quellen.py --marken > "$TMPD/m.txt" 2>&1
MRC=$?
sed 's/^/     /' "$TMPD/m.txt"
is "marken rc" "$MRC" "0"
MN=$(sed -n 's/^marken: \([0-9]*\) getippte.*/\1/p' "$TMPD/m.txt")
mind "Marken mit Umschrift, alle mit Umlautform daneben" "${MN:-0}" 6
gegen "die zweite Schreibung eines Unterbefehls" "kernel/user/opk.fi" \
    'static mut C_ZUR_U: [u8; 8] = "zurück\0"' \
    'static mut C_ZUR_X: [u8; 8] = "zurxck\0"' \
    python3 tools/i18n/quellen.py --marken

echo
echo "-- 5. die Spalten in ZEICHEN, die Puffer in Oktett"
OSUM_ROOT=. python3 tools/i18n/spalten.py > "$TMPD/s.txt" 2>&1
SRC=$?
sed 's/^/     /' "$TMPD/s.txt"
is "spalten rc" "$SRC" "0"
SB=$(sed -n 's/^spalten: \([0-9]*\) Beschriftungen.*/\1/p' "$TMPD/s.txt")
SP=$(sed -n 's/^puffer:  \([0-9]*\) Zeichenketten.*/\1/p' "$TMPD/s.txt")
mind "Beschriftungen in sechs Spalten nachgezaehlt" "${SB:-0}" 40
mind "Zeichenketten passen genau in ihren Puffer" "${SP:-0}" 4000
gegen "eine Spalte um EIN ZEICHEN verkuerzt" "kernel/user/power.fi" \
    'var s_t: [u8; 11] = "Wärme:   \0"' \
    'var s_t: [u8; 10] = "Wärme:  \0"' \
    python3 tools/i18n/spalten.py
gegen "ein Literal, das nicht mehr in seinen Puffer passt" \
    "kernel/user/vpn.fi" \
    'var s_an: [u8; 14] = "vpn: läuft\0\0\0"' \
    'var s_an: [u8; 14] = "vpn: läuft noch\0"' \
    python3 tools/i18n/spalten.py

echo
echo "-- 6. die Schriften haben jedes Zeichen, das auf dem Schirm steht"
OSUM_ROOT=. python3 tools/umlaut/schriftprobe.py > "$TMPD/f.txt" 2>&1
FRC=$?
sed 's/^/     /' "$TMPD/f.txt"
is "schriftprobe rc" "$FRC" "0"
ZN=$(sed -n 's/^schriftprobe: [0-9]* Textstellen, \([0-9]*\) verschiedene.*/\1/p' "$TMPD/f.txt")
mind "verschiedene Zeichen ueber ASCII im sichtbaren Text" "${ZN:-0}" 7

echo
echo "-- 7. 'vier Zeichen' zaehlt Zeichen und nicht Oktette"
hat kernel/user/passwd.fi "utf8.chars((&a[0]) as u64, n) < 4" \
    "passwd zaehlt Zeichen"
hat kernel/user/settings.fi "wlibc.chars((&e_pw1[0 as usize]) as u64," \
    "die Einstellungen zaehlen Zeichen"

echo
echo "-- 7b. keine Abnahme sucht mehr nach dem alten Text"
# Die Umstellung laesst eine zweite Sorte Leiche zurueck, und sie sitzt
# nicht im System, sondern in der ABNAHME: `tiling.fi` sagte seit
# UMLAUT2 2/n "tiling: Einträge gelesen", `tools/tiling/run.sh` suchte
# weiter nach "tiling: Eintraege". Der Laeufer wurde ROT, obwohl nichts
# fehlte -- die unangenehmste Form des Fehlers, denn er sieht aus wie
# ein echter und wird am falschen Ende gesucht.
OSUM_ROOT=. python3 tools/i18n/erwartung.py > "$TMPD/e.txt" 2>&1
erc=$?
n_e=$(sed -n 's/.*, \([0-9]*\) veraltete Erwartungen/\1/p' "$TMPD/e.txt")
is "veraltete Erwartungen in den Abnahmelaeufern" "${n_e:-?}" "0"
if [ "$erc" -eq 0 ]; then
    ok "tools/i18n/erwartung.py ist gruen ($(sed -n 's/^erwartung: //p' "$TMPD/e.txt"))"
else
    bad "tools/i18n/erwartung.py meldet Funde"
    sed 's/^/        /' "$TMPD/e.txt" | head -8
fi
gegen "eine Abnahme sucht den alten Satz" \
    tools/tiling/run.sh \
    "'^[0-9]+ tiling: Einträge'" \
    "'^[0-9]+ tiling: Eintraege'" \
    python3 tools/i18n/erwartung.py
# GEGEN-GEGENPROBE: eine BESCHREIBUNG in Umschrift muss still bleiben,
# und eine getippte EINGABE ("opk zurueck 0") erst recht. Ein Pruefer,
# der die Abnahmesprache anmeckert, wird beim naechsten Mal
# abgeschaltet, und dann prueft er gar nichts mehr. Beides ohne
# Programmpraefix -- genau daran unterscheidet er sie vom Suchausdruck.
kopie "$TMPD/kopie3"
python3 - "$TMPD/kopie3/tools/tiling/run.sh" <<'PY2'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
s = s.replace('ok "Kern und Ring 3 zaehlen dieselben Eintraege ($ub)"',
              'ok "Eintraege, die aus der Datei gelesen wurden, '
              'und opk zurueck 0 als Eingabe ($ub)"', 1)
open(p, 'w', encoding='utf-8').write(s)
PY2
( cd "$TMPD/kopie3" && OSUM_ROOT=. python3 tools/i18n/erwartung.py ) \
    > "$TMPD/gegen3.txt" 2>&1
if [ $? -eq 0 ]; then
    ok "GEGEN-GEGENPROBE: eine Beschreibung in Umschrift bleibt still"
else
    bad "GEGEN-GEGENPROBE: eine Beschreibung wird angemeckert -- zu laut"
    sed 's/^/        /' "$TMPD/gegen3.txt" | head -4
fi

echo
echo "== B. DAS BILD"
echo
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "UMLAUT2: kein qemu-system-x86_64 -- Teil B uebersprungen"
else

ACCEL=tcg
[ -w /dev/kvm ] && ACCEL=kvm
echo "     Beschleuniger: $ACCEL"
# RUNDE ROTABSCHNITTE: `speicher` -> `storage`. Die Quelldatei heisst
# seit ENGLISCH ETAPPE 7 kernel/user/storage.fi; der Uebersetzer fand
# kernel/user/speicher.fi nicht mehr und brach ab. Der PFAD auf der
# Platte bleibt /bin/speicher (so startet der Kern es), dafuer legt
# tools/look/shot.sh den zweiten Namen an.
PROGS="desktop taskbar settings launcher storage explorer locate widgetdemo dhcp sh echo ls cat edit"

# foto <name> <extra-oder-append>   (append= erkennt man am Praefix)
foto() {
    local name=$1 wie=$2
    local d="$TMPD/$name"
    bash tools/look/shot.sh "$d" lang=de user=de "accel=$ACCEL" \
        uitrace=yes keep=yes "progs=$PROGS" "$wie" \
        > "$TMPD/$name.log" 2>&1
    if [ ! -s "$d/desktop.ppm" ]; then
        bad "$name: es gibt kein Bild"
        sed 's/^/        /' "$TMPD/$name.log" | tail -8
        return 1
    fi
    python3 tools/gfx/ppm2png.py "$d/desktop.ppm" "$SHOTS/$name.png" \
        > /dev/null 2>&1 || cp -f "$d/desktop.ppm" "$SHOTS/$name.ppm"
    ok "$name: das Bild steht ($(stat -c%s "$d/desktop.ppm") Oktette)"
    return 0
}

# glyphen <name> <fenstertitel> <text> [erlaubt]
#
# Rechnet JEDEN Tintenpunkt des Satzes gegen `tools/ttf/raster.py` nach,
# an der Stelle, die der Fensterserver gemeldet hat. Ein abgeschnittener
# Text faellt durch (umlaut.py rechnet vorher, ob er ins Fenster passt),
# ein leerer auch (checkshot meldet LEER).
#
# `erlaubt` ist die Zahl der Punkte, die abweichen DUERFEN, und sie ist
# fast immer 0. Die eine Ausnahme ist das kleine "ö": Kern und
# Vergleichsrasterer runden den Versatz seiner linken Punktkuppe
# verschieden, und zwar um DREI Bildpunkte in EINER Spalte -- gemessen
# am 28.08.2026 an drei voneinander unabhaengigen Stellen (Knopf
# "Löschen", Spaltenkopf "Größe", Spaltenkopf "Größte Dateien"), jedes
# Mal genau 3. Das ist AELTER als diese Runde: die drei Zeichenketten
# stehen unveraendert seit Runde LOOK im Quelltext, und `ä` und `ü`
# stimmen an denselben Stellen auf den Punkt. Die Zahl steht deshalb
# hier als OBERGRENZE und nicht als Freibrief -- waechst sie, wird der
# Abschnitt rot. Naeher untersucht gehoert sie in eine Runde ueber den
# Rasterer, nicht in eine ueber Umlaute.
glyphen() {
    local name=$1 titel=$2 text=$3 erlaubt=${4:-0}
    local d="$TMPD/$name" aus rc kopf n
    aus=$(OSUM_ROOT="$ROOT" python3 tools/look/umlaut.py \
              "$d/serial.txt" "$d/desktop.ppm" "$titel" "$text" 0 --kette \
              2>&1)
    rc=$?
    kopf=$(printf '%s' "$aus" | head -1 | sed 's/^umlaut: //')
    if [ "$rc" -eq 0 ]; then
        ok "$kopf"
        return
    fi
    n=$(printf '%s' "$kopf" | sed -n 's/.* \([0-9]*\) falsch.*/\1/p')
    if [ -n "$n" ] && [ "$n" -le "$erlaubt" ] \
       && ! printf '%s' "$aus" | grep -q 'LEER'; then
        ok "$kopf (erlaubt sind $erlaubt)"
    else
        bad "$name: '$text' -- $(printf '%s' "$aus" | head -2 | tr '\n' ' ')"
    fi
}

echo "-- 8. der Starter, und die Zeile, die diese Runde ausgeloest hat"
# A-031: DER STARTER IM FENSTERSERVER-PFAD, wie der Speicher-Dialog in
# 10. Mit `desk` (der Vorgabe von tools/look/shot.sh) startet der
# Schreibtisch den Starter seit ECHTHARDWARE-4 VERSTECKT, und `wigstart`
# wirkt dort gar nicht (kgui: `desk_start` statt `k15_start`) -- das Bild
# zeigte keinen Starter, und 8. mass "kein sichtbares Fenster 'Suchen'".
# Und seit FUI-WIN11 steht die Beschreibung in einer ZWEITEN Zeile statt
# hinter "  --  "; sie wird als `wlib: text2 ... px=` gemeldet.
if foto starter "append=gfx wm wig wigstart wmhold wiglong nokbd nosched noproc nofs"; then
    hat "$TMPD/starter/serial.txt" \
        "t=Text schreiben und ändern" \
        "die Zeile steht mit echtem 'ä' auf dem Schirm"
    hatnicht "$TMPD/starter/serial.txt" "schreiben und aendern" \
        "GEGENPROBE: die Umschrift kommt im ganzen Lauf nicht mehr vor"
    glyphen starter "Suchen" "Text schreiben und ändern"
    glyphen starter "Suchen" "Ausführen"
fi

echo
echo "-- 9. die Einstellungen"
if foto einstellungen "extra=einst nostart"; then
    # MERGE-2 18: DIE ERWARTUNG IST NACHGEZOGEN, WEIL DIE OBERFLAECHE
    # BERICHTIGT WURDE -- nicht umgekehrt. Beide Zeilen waren breiter als
    # die 280 Bildpunkte ihrer Spalte; bis MERGE-2 16 malten sie ueber
    # ihren Kasten hinaus, seit dem berichtigten `paint_label` wurden sie
    # gekuerzt, und dieser Pruefer hat das gefunden. Die Kontrastzeile ist
    # jetzt ZWEI Zeilen, der Akzentsatz ein Wort kuerzer. Beide tragen
    # weiter beide Umlaute, also prueft dieser Abschnitt genau soviel wie
    # vorher.
    glyphen einstellungen "Einstellungen" "Akzent unverändert übernommen"
    glyphen einstellungen "Einstellungen" \
        "Text/Akzent 5,16  Akzent/Fläche 4,93"
    # A-031: seit der ZUSAMMENFUEHRUNG in settings.fi (ein Etikett mit
    # `wlib.umbruch()` statt zwei) bricht die Zeile am Wort um: die
    # zweite Zeile ist "WCAG erfüllt", die zwei Striche bleiben oben.
    glyphen einstellungen "Einstellungen" "WCAG erfüllt"
fi

echo
# DER SPEICHER-DIALOG KOMMT IM FENSTERSERVER-PFAD HOCH (`wig
# wigspeicher`) und nicht im Schreibtisch-Pfad (`desk`) -- deshalb
# ersetzt dieser Aufruf die ganze Befehlszeile statt an sie anzuhaengen.
echo "-- 10. der Speicher-Dialog und seine Spalten"
if foto speicher "append=gfx wm wig wigspeicher wmhold wiglong nokbd nosched noproc nofs"; then
    hat "$TMPD/speicher/serial.txt" "speicher: ready" \
        "der Speicher-Dialog ist oben"
    glyphen speicher "Speicher" "Löschen" 3
    glyphen speicher "Speicher" "Größe" 3
    glyphen speicher "Speicher" "Größte Dateien" 3

    # DIE SPALTEN, AM BILD NACHGERECHNET. `speicher.fi` setzt die
    # Breiten in BILDPUNKTEN (lspalten 210/100/74, rspalten 210/100);
    # ein Spaltenkopf, der einen Umlaut traegt, muss deshalb an genau
    # derselben Stelle anfangen wie vorher. Steht "Größe" nicht bei
    # 224, hat jemand die Breite aus der Zeichenzahl gerechnet.
    for paar in "Name:14" "Größe:224" "Anteil:324" "Größte Dateien:414"; do
        w=${paar%:*}; sx=${paar##*:}
        if grep -qaF "kind=6 x=$sx base=59" "$TMPD/speicher/serial.txt" && \
           grep -qa "kind=6 x=$sx base=59 .* t=$w\$" "$TMPD/speicher/serial.txt"
        then
            ok "die Spalte '$w' faengt bei x=$sx an"
        else
            bad "die Spalte '$w' steht nicht bei x=$sx -- die Breiten stimmen nicht mehr"
            grep -a "kind=6 .* base=59" "$TMPD/speicher/serial.txt" \
                | sed 's/^/        /' | sort -u | head -6
        fi
    done
fi
fi

echo
echo "=================================================================="
echo "UMLAUT2: $pass Zusagen gruen, $fail rot"
[ "$fail" -eq 0 ] || exit 1
exit 0
