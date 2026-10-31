#!/usr/bin/env bash
#
# WAS GEMESSEN WIRD
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

kopie() {
    local k=$1
    rm -rf "$k"; mkdir -p "$k"
    cp -r kernel lib locale assets tools tests "$k"/ 2>/dev/null
}

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

gegen "eine Beschriftung in einem FENSTERPROGRAMM" \
    "kernel/user/themetest.fi" \
    'g_ent: [u8; 31] = "ein Textfeld mit Einfügemarke\0"' \
    'g_ent: [u8; 31] = "ein Textfeld mit Einfuegemarke\0"' \
    python3 tools/i18n/quellen.py --streng
gegen "eine Meldung eines Befehls" "kernel/user/opk.fi" \
    'E_HASH: [u8; 20] = "opk: checksum wrong\0"' \
    'E_HASH: [u8; 23] = "opk: Pruefsumme falsch\0"' \
    python3 tools/i18n/quellen.py --streng
gegen "eine Beschriftung im Energie-Fenster" "kernel/user/power.fi" \
    'var s_t: [u8; 11] = "Wärme:   \0"' \
    'var s_t: [u8; 11] = "Waerme:  \0"' \
    python3 tools/i18n/quellen.py --streng

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

drahtumlaut() { grep -rnE --include='*.fi' '"[^"]*[äöüÄÖÜß][^"]*".*//[[:space:]]*DRAHT' "$1" | wc -l; }
is "DRAHT-Ketten mit Umlaut (Formatwoerter muessen ASCII bleiben)" "$(drahtumlaut kernel)" "0"
k3="$TMPD/kopie3"; mkdir -p "$k3"
sed 's|"osum-bridge 1|"osum-brücke 1|' kernel/app/jarvisd.fi > "$k3/jarvisd.fi"
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
gegen "die zweite Schreibung eines Unterbefehls" "kernel/user/trashbin.fi" \
    'var c_zur_x: [u8; 8] = "zurück\0"' \
    'var c_zur_x: [u8; 8] = "zurxck\0"' \
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
kopie "$TMPD/kopie3"
python3 - "$TMPD/kopie3/tools/tiling/run.sh" <<'PY2'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
s = s.replace('ok "Kern und Ring 3 zaehlen dieselben Eintraege ($ub)"',
              'ok "Eintraege, die aus der Datei gelesen wurden, '
              'und opk rollback 0 als Eingabe ($ub)"', 1)
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
PROGS="desktop taskbar settings launcher storage explorer locate widgetdemo dhcp sh echo ls cat edit nedit"

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
glyphen() {
    local name=$1 titel=$2 text=$3 erlaubt=${4:-0}
    local d="$TMPD/$name" aus rc kopf n
    aus=$(OSUM_ROOT="$ROOT" python3 tools/look/umlaut.py \
              "$d/serial.txt" "$d/desktop.ppm" "$titel" "$text" 0 --ink \
              2>&1)
    rc=$?
    kopf=$(printf '%s' "$aus" | head -1 | sed 's/^umlaut: //')
    if [ "$rc" -eq 0 ]; then
        ok "$kopf"
        return
    fi
    n=$(printf '%s' "$kopf" | sed -n 's/.* \([0-9]*\) wrong.*/\1/p')
    if [ -n "$n" ] && [ "$n" -le "$erlaubt" ] \
       && ! printf '%s' "$aus" | grep -q 'EMPTY'; then
        ok "$kopf (erlaubt sind $erlaubt)"
    else
        bad "$name: '$text' -- $(printf '%s' "$aus" | head -2 | tr '\n' ' ')"
    fi
}

echo "-- 8. der Starter, und die Zeile, die diese Runde ausgeloest hat"
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
    glyphen einstellungen "Einstellungen" \
        "Text/Akzent 5,16  Akzent/Fläche 4,93  -- WCAG erfüllt"
fi

echo
echo "-- 10. der Speicher-Dialog und seine Spalten"
if foto speicher "append=gfx wm wig wigspeicher wmhold wiglong nokbd nosched noproc nofs"; then
    hat "$TMPD/speicher/serial.txt" "speicher: ready" \
        "der Speicher-Dialog ist oben"
    glyphen speicher "Speicher" "Größe" 3
    glyphen speicher "Speicher" "Größte Dateien" 3
    glyphen speicher "Speicher" "Löschen"

    for paar in "Name:18" "Größe:226" "Anteil:326" "Größte Dateien:418"; do
        w=${paar%:*}; sx=${paar##*:}
        if grep -qaF "kind=5 x=$sx base=71" "$TMPD/speicher/serial.txt" && \
           grep -qa "kind=5 x=$sx base=71 .* t=$w\$" "$TMPD/speicher/serial.txt"
        then
            ok "die Spalte '$w' faengt bei x=$sx an"
        else
            bad "die Spalte '$w' steht nicht bei x=$sx -- die Breiten stimmen nicht mehr"
            grep -a "kind=5 .* base=71" "$TMPD/speicher/serial.txt" \
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
