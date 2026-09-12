#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/themestore/run.sh -- DIE ABNAHME DER RUNDE THEMESTORE.
#
# Zehn Abschnitte, und der rote Faden ist der der Runden davor: zu jeder
# Zusage gehoert eine GEGENPROBE, und eine Zahl, die nur die gepruefte
# Sache selbst erzeugt, ist keine Messung.
#
#   1. BAUEN. Kern und Programme aus dem festgenagelten Uebersetzer.
#   2. DIE VORLAGEN ALS DATEIEN. Zehn Stueck, sieben Schluessel, und
#      KEIN anderer -- mechanisch geprueft, denn genau daran haengt die
#      Zusage "in einer Vorlage steckt kein Geheimnis".
#   3. ZWEI UMSETZUNGEN, EIN ERGEBNIS. `/bin/theme list` rechnet die
#      Kontraste IM SYSTEM aus, `tools/theme/model.py` auf dem Wirt --
#      zwei Rechnungen, die nichts voneinander wissen, Zahl fuer Zahl
#      verglichen. Fuer eine Vorlage zusaetzlich alle 17 Paarungen.
#   4. KEINE VORLAGE UNTER IHRER LATTE. 4,5:1, und 7:1 fuer ein
#      Schema, das `contrast=high` sagt. GEGENPROBE: eine Vorlage auf
#      einem absichtlich schlechten Schema MUSS als geringer Kontrast
#      erkannt werden -- sonst ist die Regel nie gelaufen.
#   5. ANWENDEN. Ein Aufruf schreibt beide Dateien; ein NEUER Start mit
#      diesen Dateien zeigt die Vorlage -- gemessen an den aufgeloesten
#      Marken und an der Lage der Taskleiste.
#   6. EIGENE VORLAGE: sichern, ausgeben, einlesen -- und sie ueberlebt
#      einen Neustart. Die Datei wird aus dem Plattenabbild geholt und
#      auf die zweite Platte gelegt; die Oktette sind die aus dem Gast.
#   7. DAS KONTO IST KOMFORT, NIE BEDINGUNG. Einmal MIT Konto
#      (verknuepfen, wiederherstellen) und einmal OHNE -- und ohne muss
#      ALLES gehen, inklusive Ausgeben und Einlesen.
#   8. DIE SEITE PASST INS FENSTER. Jedes gemeldete Rechteck jeder
#      Seite gegen die Innenhoehe. Das ist die Zusage, die Runde LOOK
#      absichtlich rot stehen liess.
#   9. DIE BILDER. Eine Aufnahme je Vorlage nach docs/shots/themestore/,
#      plus die zwei Seiten des Einstellungsfensters.
#  10. DIE BILDER WERDEN GEMESSEN. Keine leere Beschriftung, nichts
#      abgeschnitten, nichts ueberlappend -- `shotcheck.py`, gegen die
#      Stellen, die die Programme selbst gemeldet haben.
#
# Verwendung:  bash tools/themestore/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
TMPD=${TS_OUT:-$(mktemp -d)}
mkdir -p "$TMPD"
# Ein roter Lauf, dessen Beweisstuecke geloescht sind, ist nicht
# nachmessbar. Mit TS_OUT=<pfad> bleibt alles liegen.
[ -n "${TS_OUT:-}" ] || trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { local name=$1 wert=$2 op=$3 want=$4
    if [ -z "${wert:-}" ]; then bad "$name: keine Zahl (erwartet $op $want)"; return; fi
    if [ "$wert" -"$op" "$want" ] 2>/dev/null; then ok "$name: $wert"
    else bad "$name: $wert, erwartet $op $want"; fi
}
same() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$3' statt '$2'"; fi }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || {
    echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "THEMESTORE: uebersprungen, qemu-system-x86_64 ist nicht da"
    exit 0
fi

PRESETS=$(cd assets/themes && ls *.preset | sed 's/\.preset$//')
NPRESET=$(printf '%s\n' $PRESETS | wc -l)
SHOTS=docs/shots/themestore
mkdir -p "$SHOTS"

# ------------------------------------------------------------- 1. bauen
echo "== 1. bauen =="
if bash tools/themestore/build.sh "$TMPD/b0" script='theme where;exit' \
       > "$TMPD/build.log" 2>&1; then
    ok "Kern und Programme gebaut ($(grep -a '^kernel ' "$TMPD/build.log" | head -1))"
    ok "die Platte steht ($(grep -a '^disk ' "$TMPD/build.log" | head -1))"
else
    bad "tools/themestore/build.sh fehlgeschlagen"
    tail -20 "$TMPD/build.log"
    exit 1
fi

# --------------------------------------------------- 2. die Vorlagendateien
echo
echo "== 2. die Vorlagen als Dateien: sieben Schluessel und kein achter =="
num "mitgelieferte Vorlagen" "$NPRESET" ge 8
KEYS_BAD=0
KEYS_MISS=0
for p in $PRESETS; do
    f="assets/themes/$p.preset"
    while IFS= read -r k; do
        case "$k" in
            name|scheme|mode|shape|accent|edge|align) ;;
            *) echo "        $p: unbekannter Schluessel '$k'"; KEYS_BAD=$((KEYS_BAD+1));;
        esac
    done < <(grep -aoE '^[a-z_]+=' "$f" | sed 's/=$//')
    n=$(grep -acE '^[a-z_]+=' "$f")
    [ "$n" -eq 7 ] || { echo "        $p: $n Schluessel statt 7"; KEYS_MISS=$((KEYS_MISS+1)); }
done
num "kein Schluessel ausserhalb der sieben" "$KEYS_BAD" eq 0
num "und jede Vorlage hat alle sieben" "$KEYS_MISS" eq 0
# GEGENPROBE ZU DEM, WORAUF ES ANKOMMT: das Vokabular ist im Quelltext
# genauso eng wie in den Dateien. Ein achter Schluessel muesste hier
# stehen; steht er nicht, kann eine fremde Vorlage keinen tragen.
PK=$(grep -acE 'var k_(name|scheme|mode|shape|accent|edge|align): ' kernel/user/template.fi)
num "und vorlage.parse_key kennt genau sieben Schluesselnamen" "$PK" eq 7
DIFF=$(printf '%s\n' $PRESETS | while read -r p; do
    grep -aE '^(scheme|mode|shape|accent|edge|align)=' "assets/themes/$p.preset" | tr '\n' ' '; echo; done | sort -u | wc -l)
num "und die zehn sind wirklich verschieden (verschiedene Wertesaetze)" "$DIFF" eq "$NPRESET"
EDGES=$(grep -ah '^edge=' assets/themes/*.preset | sort -u | wc -l)
SCHEMES=$(grep -ah '^scheme=' assets/themes/*.preset | sort -u | wc -l)
SHAPES=$(grep -ah '^shape=' assets/themes/*.preset | sort -u | wc -l)
MODES=$(grep -ah '^mode=' assets/themes/*.preset | sort -u | wc -l)
ACCENTS=$(grep -ah '^accent=' assets/themes/*.preset | sort -u | wc -l)
num "vier Taskleisten-Kanten kommen vor" "$EDGES" ge 4
num "alle fuenf Schemata kommen vor" "$SCHEMES" ge 5
num "beide Formsaetze kommen vor" "$SHAPES" ge 2
num "beide Modi kommen vor" "$MODES" ge 2
num "und mehrere Akzentfarben" "$ACCENTS" ge 4

# ------------------------------------------- 3. zwei Umsetzungen, ein Wert
echo
echo "== 3. dieselben Kontraste, im System und auf dem Wirt gerechnet =="
bash tools/themestore/build.sh "$TMPD/list" script='theme list;exit' \
    > "$TMPD/list.log" 2>&1
L="$TMPD/list/serial.txt"
n=$(grep -a 'theme: presets n=' "$L" | tail -1 | grep -oE '[0-9]+$')
same "das System findet alle mitgelieferten Vorlagen" "$NPRESET" "${n:-0}"
AGREE=0; DISAGREE=0
for p in $PRESETS; do
    line=$(grep -a "theme: preset id=$p " "$L" | tail -1)
    if [ -z "$line" ]; then
        echo "        $p: keine Zeile im Gast"; DISAGREE=$((DISAGREE+1)); continue
    fi
    gtxt=$(printf '%s' "$line" | grep -oE ' txt=[0-9]+' | grep -oE '[0-9]+')
    gmin=$(printf '%s' "$line" | grep -oE ' min=[0-9]+' | grep -oE '[0-9]+')
    read -r htxt hmin < <(python3 tools/themestore/model.py pair "assets/themes/$p.preset")
    if [ "$gtxt" = "$htxt" ] && [ "$gmin" = "$hmin" ]; then
        AGREE=$((AGREE+1))
        printf '        %-14s Text auf Grund %s  schlechtestes Paar %s\n' \
            "$p" "$(python3 -c "print('%.2f:1'%($gtxt/100))")" \
            "$(python3 -c "print('%.2f:1'%($gmin/100))")"
    else
        DISAGREE=$((DISAGREE+1))
        echo "        $p: Gast txt=$gtxt min=$gmin, Wirt txt=$htxt min=$hmin"
    fi
done
num "Vorlagen, bei denen Gast und Wirt Ziffer fuer Ziffer gleich rechnen" "$AGREE" eq "$NPRESET"
num "und keine, bei der sie sich unterscheiden" "$DISAGREE" eq 0
# alle siebzehn Paarungen einer Vorlage, einzeln
bash tools/themestore/build.sh "$TMPD/show" script='theme show mitternacht;exit' \
    > "$TMPD/show.log" 2>&1
S="$TMPD/show/serial.txt"
PN=$(grep -ac 'theme: pair i=' "$S")
num "eine Vorlage meldet alle siebzehn Textpaarungen einzeln" "$PN" eq 17
PD=0
while read -r i fg bg r; do
    hr=$(python3 tools/themestore/model.py onepair "assets/themes/mitternacht.preset" "$fg" "$bg")
    [ "$r" = "$hr" ] || { echo "        Paar $i $fg/$bg: Gast $r, Wirt $hr"; PD=$((PD+1)); }
done < <(grep -a 'theme: pair i=' "$S" | sed -E 's/.*i=([0-9]+) fg=([a-z-]+) bg=([a-z-]+) r=([0-9]+).*/\1 \2 \3 \4/')
num "und jede der siebzehn stimmt mit dem Modell ueberein" "$PD" eq 0

# ----------------------------------------------- 4. die Latte, und die Probe
echo
echo "== 4. keine Vorlage unter ihrer Latte -- und die Gegenprobe =="
LOW=0; UNDER=0
for p in $PRESETS; do
    line=$(grep -a "theme: preset id=$p " "$L" | tail -1)
    gmin=$(printf '%s' "$line" | grep -oE ' min=[0-9]+' | grep -oE '[0-9]+')
    gbar=$(printf '%s' "$line" | grep -oE ' bar=[0-9]+' | grep -oE '[0-9]+')
    glow=$(printf '%s' "$line" | grep -oE ' low=[0-9]+' | grep -oE '[0-9]+')
    [ "${glow:-1}" = 0 ] || LOW=$((LOW+1))
    [ "${gmin:-0}" -ge "${gbar:-450}" ] || UNDER=$((UNDER+1))
done
num "Vorlagen, die als 'geringer Kontrast' gekennzeichnet sind" "$LOW" eq 0
num "Vorlagen unter ihrer eigenen Latte" "$UNDER" eq 0
HIGHBAR=$(grep -a "theme: preset id=kontrast " "$L" | tail -1 | grep -oE ' bar=[0-9]+' | grep -oE '[0-9]+')
same "und ein Schema mit contrast=high wird gegen 7:1 gemessen" "700" "${HIGHBAR:-}"
# DIE GEGENPROBE: ein absichtlich schlechtes Schema, eine Vorlage darauf.
mkdir -p "$TMPD/lowdir"
cat > "$TMPD/flat.scheme" <<'EOF'
# flat.scheme -- NOT A SCHEME ANYBODY SHOULD USE. It exists so that the
# counter-check of this round has something to fail on: every neutral
# step is a middle grey, so text on surface lands far under 4.5:1.
name=Flat Grey
mode=light
contrast=normal
neutral0=9a9a9a
neutral50=989898
neutral100=969696
neutral200=949494
neutral300=929292
neutral400=8e8e8e
neutral500=8a8a8a
neutral600=868686
neutral700=828282
neutral800=7e7e7e
neutral900=7a7a7a
neutral950=767676
neutral1000=707070
accent=888888
danger=8b3030
warning=8b6a30
success=30703f
EOF
cat > "$TMPD/lowdir/grau" <<'EOF'
name=Grau in Grau
scheme=flat
mode=light
shape=modern
accent=
edge=bottom
align=left
EOF
bash tools/themestore/build.sh "$TMPD/low" script='theme list;exit' \
    xscheme="$TMPD/flat.scheme" localdir="$TMPD/lowdir" > "$TMPD/low.log" 2>&1
LW="$TMPD/low/serial.txt"
gl=$(grep -a 'theme: preset id=grau ' "$LW" | tail -1)
glow=$(printf '%s' "$gl" | grep -oE ' low=[0-9]+' | grep -oE '[0-9]+')
gmin=$(printf '%s' "$gl" | grep -oE ' min=[0-9]+' | grep -oE '[0-9]+')
same "GEGENPROBE: die schlechte Vorlage wird als geringer Kontrast gemeldet" "1" "${glow:-}"
num "und ihr schlechtestes Paar liegt wirklich unter 4,5:1" "${gmin:-9999}" lt 450
has "$LW" "LOW CONTRAST" "und das Wort steht in der Ausgabe, nicht nur in einer Zahl"
read -r ftxt fmin < <(python3 tools/themestore/model.py pairscheme "$TMPD/flat.scheme" light "")
same "und der Wirt rechnet dieselbe Zahl" "$fmin" "${gmin:-}"

# --------------------------------------------------------- 5. anwenden
echo
echo "== 5. anwenden: ein Aufruf, zwei Dateien, und der naechste Start zeigt es =="
bash tools/themestore/build.sh "$TMPD/ap" script='theme apply studio;exit' \
    keep=yes > "$TMPD/ap.log" 2>&1
A="$TMPD/ap/serial.txt"
has "$A" "theme: applied studio" "der Aufruf meldet die Vorlage"
python3 tools/osum/mkfs.py cat "$TMPD/ap/disk.img" /etc/theme.conf \
    > "$TMPD/theme.conf" 2>/dev/null
python3 tools/osum/mkfs.py cat "$TMPD/ap/disk.img" /etc/taskbar.conf \
    > "$TMPD/taskbar.conf" 2>/dev/null
same "und /etc/theme.conf traegt das Schema der Vorlage" "midnight" \
    "$(grep -a '^scheme=' "$TMPD/theme.conf" | cut -d= -f2)"
same "den Modus" "dark" "$(grep -a '^mode=' "$TMPD/theme.conf" | cut -d= -f2)"
# RUNDE OBERFLAECHE: die Vorlage `studio` nennt jetzt die HAUSFORM
# (assets/shapes/osum.shape) und nicht mehr `modern`.  Die Zeile hier
# wird mitgezogen und nicht weggelassen: sie prueft, dass `theme apply`
# den Formsatz der Vorlage in die Datei schreibt, und das ist unabhaengig
# davon, wie er heisst.
same "den Formsatz" "osum" "$(grep -a '^shape=' "$TMPD/theme.conf" | cut -d= -f2)"
same "die Akzentfarbe" "0891b2" "$(grep -a '^accent=' "$TMPD/theme.conf" | cut -d= -f2)"
same "und /etc/taskbar.conf die Kante" "left" \
    "$(grep -a '^edge=' "$TMPD/taskbar.conf" | cut -d= -f2)"
same "und die Ausrichtung" "center" \
    "$(grep -a '^align=' "$TMPD/taskbar.conf" | cut -d= -f2)"
# DIE ANDEREN VIER SCHLUESSEL DER LEISTE BLEIBEN STEHEN. Eine Vorlage,
# die bei jedem Anwenden die Balkenhoehe zuruecksetzt, wendet man
# einmal an.
same "und die Hoehe der Leiste ist NICHT angefasst worden" "28" \
    "$(grep -a '^height=' "$TMPD/taskbar.conf" | cut -d= -f2)"
same "und ontop auch nicht" "1" \
    "$(grep -a '^ontop=' "$TMPD/taskbar.conf" | cut -d= -f2)"

# --------------------------------------------------- 6. die eigene Vorlage
echo
echo "== 6. eine eigene Vorlage: sichern, ausgeben, einlesen, neu starten =="
bash tools/themestore/build.sh "$TMPD/save" keep=yes \
    script='theme apply terminal;theme save meins Meins;theme export meins /meins.otheme;theme list;exit' \
    > "$TMPD/save.log" 2>&1
SV="$TMPD/save/serial.txt"
has "$SV" "theme: saved meins" "die laufende Erscheinung ist als eigene Vorlage gesichert"
has "$SV" "theme: exported meins" "und in eine Datei ausgegeben"
python3 tools/osum/mkfs.py cat "$TMPD/save/disk.img" /meins.otheme \
    > "$TMPD/meins.otheme" 2>/dev/null
num "die ausgegebene Datei hat Inhalt" "$(stat -c%s "$TMPD/meins.otheme" 2>/dev/null || echo 0)" gt 40
ok "und sie ist lesbarer Text: $(grep -acE '^[a-z]+=' "$TMPD/meins.otheme") Zeilen key=value, \
$(grep -acv '[[:print:]]' "$TMPD/meins.otheme" || true) unlesbare Zeilen"
same "sie traegt das Schema der laufenden Erscheinung" "night" \
    "$(grep -a '^scheme=' "$TMPD/meins.otheme" | cut -d= -f2)"
same "und die Kante der laufenden Leiste" "top" \
    "$(grep -a '^edge=' "$TMPD/meins.otheme" | cut -d= -f2)"
# `grep -c` gibt bei null Treffern SELBST die 0 aus UND meldet Rueckgabe 1;
# das angehaengte `echo 0` machte daraus zwei Zeilen "0\n0", und verglichen
# wurde ein Zweizeiler mit einer Zahl. Dieselbe Zusage, nur einmal gezaehlt.
BIN=$({ grep -acP '[\x00-\x08\x0e-\x1f]' "$TMPD/meins.otheme" 2>/dev/null || true; } | head -1)
num "und kein einziges Steuerzeichen -- kein Binaerformat" "$BIN" eq 0
# NEUSTART: eine ZWEITE Platte, die nur die exportierte Datei traegt.
mkdir -p "$TMPD/restore"
cp "$TMPD/meins.otheme" "$TMPD/restore/meins"
bash tools/themestore/build.sh "$TMPD/rest" localdir="$TMPD/restore" \
    script='theme list;theme apply meins;exit' > "$TMPD/rest.log" 2>&1
R="$TMPD/rest/serial.txt"
has "$R" "theme: preset id=meins" "nach dem Neustart ist die eigene Vorlage wieder da"
same "und sie kommt aus dem eigenen Ablageort" "local" \
    "$(grep -a 'theme: preset id=meins ' "$R" | tail -1 | grep -oE ' origin=[a-z]+' | cut -d= -f2)"
has "$R" "theme: applied meins" "und sie laesst sich anwenden"
n2=$(grep -a 'theme: presets n=' "$R" | head -1 | grep -oE '[0-9]+$')
same "der Laden hat jetzt eine Vorlage mehr" "$((NPRESET+1))" "${n2:-0}"
# EINLESEN, aus einer Datei, die von aussen kommt
bash tools/themestore/build.sh "$TMPD/imp" xfile="/fremd.otheme=$TMPD/meins.otheme" \
    script='theme import /fremd.otheme fremd;theme list;exit' > "$TMPD/imp.log" 2>&1
I="$TMPD/imp/serial.txt"
has "$I" "theme: imported fremd" "eine Vorlage von aussen laesst sich einlesen"
same "und liegt danach im eigenen Ablageort" "local" \
    "$(grep -a 'theme: preset id=fremd ' "$I" | tail -1 | grep -oE ' origin=[a-z]+' | cut -d= -f2)"

# ------------------------------------------------------------- 7. das Konto
echo
echo "== 7. das Konto ist Komfort, nie Bedingung =="
bash tools/themestore/build.sh "$TMPD/acc" \
    script='theme where;theme apply papier;theme save meins Meins;theme link;theme restore;theme list;exit' \
    > "$TMPD/acc.log" 2>&1
AC="$TMPD/acc/serial.txt"
same "MIT Konto: der Ablageort wird gefunden" "1" \
    "$(grep -a 'theme: account have=' "$AC" | tail -1 | grep -oE 'have=[0-9]' | cut -d= -f2)"
has "$AC" "/users/root/config/themes/" "und er liegt unter dem Heim des Kontos"
same "verknuepfen kopiert die eigene Vorlage hinein" "1" \
    "$(grep -a 'theme: linked n=' "$AC" | tail -1 | grep -oE '[0-9]+$')"
num "und wiederherstellen holt sie zurueck" \
    "$(grep -a 'theme: restored n=' "$AC" | tail -1 | grep -oE '[0-9]+$')" ge 1
# OHNE KONTO: alles muss trotzdem gehen.
bash tools/themestore/build.sh "$TMPD/noacc" account=no \
    script='theme where;theme list;theme apply tafel;theme save meins Meins;theme export meins /x.otheme;theme import /x.otheme zwei;theme link;theme list;exit' \
    keep=yes > "$TMPD/noacc.log" 2>&1
NA="$TMPD/noacc/serial.txt"
same "OHNE Konto: es gibt keinen Konto-Ablageort" "0" \
    "$(grep -a 'theme: account have=' "$NA" | tail -1 | grep -oE 'have=[0-9]' | cut -d= -f2)"
has "$NA" "theme: no account -- nothing to do" "und 'verknuepfen' sagt das, statt zu scheitern"
has "$NA" "theme: applied tafel" "OHNE Konto laesst sich eine Vorlage anwenden"
has "$NA" "theme: saved meins" "OHNE Konto laesst sich eine eigene sichern"
has "$NA" "theme: exported meins" "OHNE Konto laesst sich ausgeben"
has "$NA" "theme: imported zwei" "OHNE Konto laesst sich einlesen"
nn=$(grep -a 'theme: presets n=' "$NA" | tail -1 | grep -oE '[0-9]+$')
num "und der Laden hat ohne Konto genauso viele Vorlagen" "${nn:-0}" ge "$NPRESET"
# UND ES STECKT NICHTS DRIN AUSSER DARSTELLUNG.
python3 tools/osum/mkfs.py cat "$TMPD/noacc/disk.img" /x.otheme > "$TMPD/x.otheme" 2>/dev/null
XK=0
while IFS= read -r k; do
    case "$k" in name|scheme|mode|shape|accent|edge|align) ;; *) XK=$((XK+1));; esac
done < <(grep -aoE '^[a-z_]+=' "$TMPD/x.otheme" | sed 's/=$//')
num "in einer ausgegebenen Vorlage steht kein Schluessel ausser den sieben" "$XK" eq 0
num "und kein Pfad, kein Befehl, kein Kennwort" \
    "$(grep -acE '(/bin/|/etc/|passwd|token|key=|http)' "$TMPD/x.otheme" || true)" eq 0
# GEGENPROBE ZUR GEGENPROBE: eine Vorlage MIT einem achten Schluessel
# wird gezaehlt und nicht verschluckt.
cp "$TMPD/meins.otheme" "$TMPD/schmuggel.otheme"
printf 'command=/bin/sh\npassword=hunter2\n' >> "$TMPD/schmuggel.otheme"
bash tools/themestore/build.sh "$TMPD/sm" xfile="/schmuggel.otheme=$TMPD/schmuggel.otheme" \
    script='theme import /schmuggel.otheme schmuggel;theme show schmuggel;exit' \
    > "$TMPD/sm.log" 2>&1
SM="$TMPD/sm/serial.txt"
smbad=$(grep -a 'theme: preset id=schmuggel ' "$SM" | tail -1 | grep -oE ' bad=[0-9]+' | grep -oE '[0-9]+')
num "GEGENPROBE: die zwei geschmuggelten Schluessel werden GEZAEHLT" "${smbad:-0}" eq 2
smk=$(grep -a 'theme: preset id=schmuggel ' "$SM" | tail -1 | grep -oE ' keys=[0-9]+' | grep -oE '[0-9]+')
same "und die sieben echten trotzdem gelesen" "7" "${smk:-}"

# ------------------------------------------------ 8. die Seite passt hinein
echo
echo "== 8. die Seite Darstellung passt ins Fenster -- alle Seiten =="
bash tools/themestore/build.sh "$TMPD/set" extra='einst' uitrace=yes keep=yes \
    > "$TMPD/set.log" 2>&1
SE="$TMPD/set/serial.txt"
WH=$(grep -ao 'name=win x=[0-9]* y=[0-9]* w=[0-9]* h=[0-9]*' "$SE" | tail -1 \
     | grep -oE 'h=[0-9]+' | cut -d= -f2)
num "das Fenster ist so hoch wie der Arbeitsbereich zulaesst" "${WH:-0}" ge 560
INNER=$((${WH:-566} - 24))
# BEIDE Seiten, nicht nur die sichtbare: die Kacheln der Seite Vorlagen
# sind Widgets wie alle anderen und muessen genauso ins Fenster passen.
# Die Seite wird hier gebaut und in Abschnitt 9 und 10 wiederverwendet.
# RUNDE MERGE8: 548,41 statt 680,51. Die Reiterleiste hat seit den
# Runden KONTO und ABGLEICH ZEHN Reiter statt acht -- der alte Punkt
# 680,51 traf damit nicht mehr "Vorlagen" (Reiter 7, x=526..601),
# sondern den letzten Reiter "Abgleich". Gemessen wurden dann elf
# Beschriftungen der Abgleich-Seite statt der zwoelf der Vorlagen.
bash tools/themestore/build.sh "$TMPD/setv" extra='einst' uitrace=yes keep=yes \
    click=548,41 > "$TMPD/setv.log" 2>&1
SEV="$TMPD/setv/serial.txt"
NR=$({ grep -ac 'settings: rect name=w[a-z][a-z] ' "$SE" "$SEV" || true; } \
     | cut -d: -f2 | awk '{n=n+$1} END {print n+0}')
num "gemeldete Rechtecke beider Seiten (vor dieser Runde waren es fuenf)" "${NR:-0}" ge 25
OVER=$(python3 - "$INNER" "$SE" "$SEV" <<'PYX'
import re, sys
inner = int(sys.argv[1])
n = 0
for path in sys.argv[2:]:
    txt = open(path, 'rb').read().decode('latin1')
    # NUR die Zeilen von `settings` selbst. Die Zeile des FENSTERS
    # (name=win) sieht genauso aus, ist aber das Fenster und nicht sein
    # Inhalt -- sie gegen die INNENhoehe zu halten misst das Fenster
    # gegen sich selbst und ist immer rot.
    for m in re.finditer(
            r'settings: rect name=(w[a-z][a-z]) x=(\d+) y=(\d+) w=(\d+) h=(\d+)', txt):
        # `win` ist das FENSTER und kein Widget darin -- es traegt
        # zufaellig einen Namen aus drei Buchstaben mit w am Anfang.
        if m.group(1) == 'win':
            continue
        y, h = int(m.group(3)), int(m.group(5))
        if y + h > inner:
            print("        outside: %s in %s ends at %d, the window is %d high"
                  % (m.group(1), path.split('/')[-2], y + h, inner), file=sys.stderr)
            n += 1
print(n)
PYX
)
num "Widgets, die aus ihrem Fenster ragen (Runde LOOK: 132 Bildpunkte fehlten)" "$OVER" eq 0
TABS=$(grep -aoc 'wlib: tab i=' "$SE" || true)
num "die Reiterleiste meldet ihre Reiter" "$TABS" ge 8
TABOUT=$(python3 - "$SE" <<'PY'
import re, sys
txt = open(sys.argv[1], 'rb').read().decode('latin1')
w = re.findall(r'settings: rect name=waa x=(\d+) y=\d+ w=(\d+)', txt)
if not w:
    print(0); raise SystemExit
bx, bw = int(w[-1][0]), int(w[-1][1])
n = 0
for m in re.finditer(r'wlib: tab i=(\d+) x=(\d+) y=\d+ w=(\d+)', txt):
    if int(m.group(2)) + int(m.group(3)) > bx + bw:
        n += 1
print(n)
PY
)
num "und kein Reiter wird ausserhalb der Leiste gemalt" "$TABOUT" eq 0

# --------------------------------------------------------- 9. die Bilder
echo
echo "== 9. ein Bild je Vorlage =="
SHOTN=0
for p in $PRESETS; do
    bash tools/themestore/build.sh "$TMPD/s-$p" preset="$p" uitrace=yes keep=yes \
        > "$TMPD/s-$p.log" 2>&1
    if [ -s "$TMPD/s-$p/desktop.png" ]; then
        cp "$TMPD/s-$p/desktop.png" "$SHOTS/$p.png"
        SHOTN=$((SHOTN+1))
    else
        echo "        $p: kein Bild"
    fi
done
num "Bildschirmfotos nach $SHOTS" "$SHOTN" eq "$NPRESET"
# die zwei Seiten des Fensters
cp "$TMPD/set/desktop.png" "$SHOTS/settings-darstellung.png" 2>/dev/null
cp "$TMPD/setv/desktop.png" "$SHOTS/settings-vorlagen.png" 2>/dev/null
[ -s "$SHOTS/settings-vorlagen.png" ] \
    && ok "und die Seite Vorlagen mit den zehn Kacheln" \
    || bad "die Seite Vorlagen wurde nicht aufgenommen"
TL=$(grep -a 'settings: tiles n=' "$TMPD/setv/serial.txt" | tail -1 | grep -oE 'shown=[0-9]+' | cut -d= -f2)
num "und sie zeigt zehn Kacheln" "${TL:-0}" eq 10
# DIE KACHELN SIND AUS DEN MARKEN GEMALT: jede Kachel meldet die
# Flaechenfarbe, mit der sie gemalt hat, und die muss die AUFGELOESTE
# Flaechenfarbe IHRER Vorlage sein -- nicht die des laufenden Satzes.
TDIFF=$(python3 - "$TMPD/setv/serial.txt" <<'PY'
import re, sys
txt = open(sys.argv[1], 'rb').read().decode('latin1')
bg = set()
for m in re.finditer(r'settings: preset i=\d+ id=(\S+) min=\d+ low=\d+ bg=(\d+)', txt):
    bg.add(m.group(2))
print(len(bg))
PY
)
num "und die Kacheln haben verschiedene Flaechenfarben (nicht die des laufenden Satzes)" \
    "$TDIFF" ge 4

# ------------------------------------------------- 10. die Bilder MESSEN
echo
echo "== 10. die Bilder werden gemessen, nicht angeschaut =="
WX=$(grep -ao 'name=win x=[0-9]*' "$SE" | tail -1 | cut -d= -f3)
WY=$(grep -ao 'name=win x=[0-9]* y=[0-9]*' "$SE" | tail -1 | grep -oE 'y=[0-9]+' | cut -d= -f2)
WW=$(grep -ao 'name=win x=[0-9]* y=[0-9]* w=[0-9]*' "$SE" | tail -1 | grep -oE 'w=[0-9]+' | cut -d= -f2)
IX=$(( ${WX:-50} + 2 )); IY=$(( ${WY:-3} + 22 ))
IW=$(( ${WW:-700} - 4 ))
for pair in "set:Darstellung" "setv:Vorlagen"; do
    d=${pair%%:*}; nm=${pair##*:}
    out=$(python3 tools/themestore/shotcheck.py "$TMPD/$d/desktop.ppm" \
          "$TMPD/$d/serial.txt" "--window=$IX,$IY,$IW,$INNER" 2>&1)
    e=$(printf '%s' "$out" | grep -oE 'empty [0-9]+' | grep -oE '[0-9]+')
    c=$(printf '%s' "$out" | grep -oE 'cut [0-9]+' | grep -oE '[0-9]+')
    o=$(printf '%s' "$out" | grep -oE 'overlapping [0-9]+' | grep -oE '[0-9]+')
    t=$(printf '%s' "$out" | grep -oE 'measured [0-9]+' | grep -oE '[0-9]+')
    num "Seite $nm: gemessene Beschriftungen" "${t:-0}" ge 12
    num "Seite $nm: leere Beschriftungen" "${e:-1}" eq 0
    num "Seite $nm: abgeschnittene" "${c:-1}" eq 0
    num "Seite $nm: ueberlappende" "${o:-1}" eq 0
    [ "${e:-1}" = 0 ] && [ "${c:-1}" = 0 ] && [ "${o:-1}" = 0 ] || \
        printf '%s\n' "$out" | sed 's/^/        /' | head -12
done
# und jede der zehn Aufnahmen: die Taskleiste sagt, wo sie ist, und im
# Bild ist sie dort.
BARBAD=0
for p in $PRESETS; do
    f="$TMPD/s-$p/serial.txt"
    [ -s "$f" ] || { BARBAD=$((BARBAD+1)); continue; }
    want=$(grep -aE '^edge=' "assets/themes/$p.preset" | cut -d= -f2)
    got=$(grep -a 'taskbar: conf ' "$f" | tail -1 | grep -oE 'ename=[a-z]+' | cut -d= -f2)
    [ "$want" = "$got" ] || { echo "        $p: Leiste $got statt $want"; BARBAD=$((BARBAD+1)); }
done
num "in jeder Aufnahme sitzt die Leiste an der Kante, die die Vorlage nennt" "$BARBAD" eq 0
# und der Formsatz auch
SHBAD=0
for p in $PRESETS; do
    f="$TMPD/s-$p/serial.txt"
    want=$(grep -aE '^shape=' "assets/themes/$p.preset" | cut -d= -f2)
    got=$(grep -a 'taskbar: shape file=' "$f" 2>/dev/null | tail -1 | grep -oE 'file=[a-z]+' | cut -d= -f2)
    [ -z "$got" ] && got=$(grep -a 'shape file=' "$f" 2>/dev/null | tail -1 | grep -oE 'file=[a-z]+' | cut -d= -f2)
    [ "$want" = "$got" ] || { echo "        $p: Form $got statt $want"; SHBAD=$((SHBAD+1)); }
done
num "und der Formsatz ist der, den die Vorlage nennt" "$SHBAD" eq 0
SHOTCHK=0
for p in $PRESETS; do
    o=$(python3 tools/themestore/shotcheck.py "$TMPD/s-$p/desktop.ppm" \
        "$TMPD/s-$p/serial.txt" 2>&1 | head -1)
    e=$(printf '%s' "$o" | grep -oE 'empty [0-9]+' | grep -oE '[0-9]+')
    c=$(printf '%s' "$o" | grep -oE 'cut [0-9]+' | grep -oE '[0-9]+')
    ov=$(printf '%s' "$o" | grep -oE 'overlapping [0-9]+' | grep -oE '[0-9]+')
    if [ "${e:-1}" != 0 ] || [ "${c:-1}" != 0 ] || [ "${ov:-1}" != 0 ]; then
        echo "        $p: $o"
        SHOTCHK=$((SHOTCHK+1))
    fi
done
num "und in keiner der zehn Aufnahmen eine leere, abgeschnittene oder ueberlappende Beschriftung" \
    "$SHOTCHK" eq 0

echo
echo "THEMESTORE: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
