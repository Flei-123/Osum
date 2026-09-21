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
#  11. RUNDE GLAS: RUNDUNG, DURCHSICHT, MILCHGLAS. Der Radius kommt bei
#      jedem Widgettyp an und verschiebt keinen Inhalt; die Leiste
#      mischt wirklich, Bildpunkt fuer Bildpunkt gegen eine zweite,
#      auf dem Wirt gerechnete Mischung (`glascheck.py`); das
#      Milchglas senkt die Streuung messbar und seine Zeit je Vollbild
#      steht als Zahl da; die Leistenschrift haelt 4,5:1 gegen den
#      GEMISCHTEN Grund ueber hellem und dunklem Bild; und nach einem
#      Zug unter der Leiste hindurch bleibt kein Bildpunkt stehen, der
#      dort nicht hingehoert.
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
echo "== 2. die Vorlagen als Dateien: elf Schluessel und kein zwoelfter =="
num "mitgelieferte Vorlagen" "$NPRESET" ge 8
KEYS_BAD=0
KEYS_MISS=0
for p in $PRESETS; do
    f="assets/themes/$p.preset"
    while IFS= read -r k; do
        case "$k" in
            name|scheme|mode|shape|accent|edge|align) ;;
            radius|taskbar_alpha|window_alpha|taskbar_blur) ;;
            # `dark_scheme` ist der zwoelfte, und er ist KEIN Pflichtteil:
            # nur eine Vorlage, die im Dunkelmodus auf ein anderes Schema
            # umschaltet, traegt ihn (Runde FARBE, `tageslicht`). Er
            # steht hier, weil `template.parse_key` ihn kennt -- die
            # Liste der Datei und die des Quelltextes sind dieselbe.
            dark_scheme) ;;
            *) echo "        $p: unbekannter Schluessel '$k'"; KEYS_BAD=$((KEYS_BAD+1));;
        esac
    done < <(grep -aoE '^[a-z_]+=' "$f" | sed 's/=$//')
    # ELF PFLICHTSCHLUESSEL, und zwar jeder einzeln nachgesehen: eine
    # blosse Anzahl waere bei einer Vorlage mit `dark_scheme` und ohne
    # `radius` genauso gross und trotzdem falsch.
    for k in name scheme mode shape accent edge align radius \
             taskbar_alpha window_alpha taskbar_blur; do
        grep -qaE "^$k=" "$f" || { echo "        $p: '$k' fehlt"
            KEYS_MISS=$((KEYS_MISS+1)); }
    done
done
num "kein Schluessel ausserhalb der elf" "$KEYS_BAD" eq 0
num "und jeder der elf Pflichtschluessel steht in jeder Vorlage" "$KEYS_MISS" eq 0
# RUNDE GLAS: DIE LISTE IST GEWACHSEN, DIE ZUSAGE NICHT GESCHRUMPFT.
# Vier Schluessel sind dazugekommen, und jeder einzelne ist eine ZAHL
# in einem festen Bereich -- kein Pfad, kein Befehl, kein Text freier
# Form. Genau das wird hier nachgemessen: der Wert besteht nur aus
# Ziffern, und er liegt in den Grenzen, die `template.parse_key`
# klemmt. Ein `radius=/bin/sh` faellt damit schon auf der Platte auf
# und nicht erst im Gast.
NUMBAD=0
for p in $PRESETS; do
    f="assets/themes/$p.preset"
    while IFS='=' read -r k v; do
        case "$k" in
            radius) lo=0; hi=24;;
            taskbar_alpha|window_alpha) lo=0; hi=100;;
            taskbar_blur) lo=0; hi=16;;
            *) continue;;
        esac
        case "$v" in
            ''|*[!0-9]*) echo "        $p: $k='$v' ist keine Zahl"
                         NUMBAD=$((NUMBAD+1)); continue;;
        esac
        if [ "$v" -lt "$lo" ] || [ "$v" -gt "$hi" ]; then
            echo "        $p: $k=$v liegt ausserhalb $lo..$hi"
            NUMBAD=$((NUMBAD+1))
        fi
    done < <(grep -aE '^[a-z_]+=' "$f")
done
num "und die vier neuen Schluessel tragen nur Ziffern im erlaubten Bereich" "$NUMBAD" eq 0
# GEGENPROBE ZU DEM, WORAUF ES ANKOMMT: das Vokabular ist im Quelltext
# genauso eng wie in den Dateien. Ein zwoelfter Schluessel muesste hier
# stehen; steht er nicht, kann eine fremde Vorlage keinen tragen.
PK=$(grep -acE 'var k_(name|scheme|dscheme|mode|shape|accent|edge|align|radius|taskbar_alpha|window_alpha|taskbar_blur): ' kernel/user/template.fi)
num "und vorlage.parse_key kennt genau zwoelf Schluesselnamen" "$PK" eq 12
# UND DIE VIER NEUEN GEHEN DURCH EINEN LESER, DER NUR ZIFFERN NIMMT.
# `dec_of` gibt NUM_NONE zurueck, sobald ein Zeichen keine Ziffer ist,
# und `parse_key` antwortet darauf `false` -- die Zeile wird als
# schlecht gezaehlt statt stillschweigend als 0 gelesen.
DEC=$(grep -acE 'fn dec_of\(' kernel/user/template.fi)
num "und der Leser der Zahlen ist genau einer" "$DEC" eq 1
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
    case "$k" in
        name|scheme|dark_scheme|mode|shape|accent|edge|align) ;;
        radius|taskbar_alpha|window_alpha|taskbar_blur) ;;
        *) XK=$((XK+1));;
    esac
done < <(grep -aoE '^[a-z_]+=' "$TMPD/x.otheme" | sed 's/=$//')
num "in einer ausgegebenen Vorlage steht kein Schluessel ausser den elf" "$XK" eq 0
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
num "und die echten Schluessel trotzdem gelesen" "${smk:-0}" ge 7
# UND DIE GEGENPROBE AUF DIE NEUEN VIER: ein `radius=/bin/sh` ist kein
# Radius. Die Zeile sieht aus wie eine erlaubte, traegt aber keine
# Zahl -- sie MUSS als schlecht gezaehlt werden, sonst waere der
# Zahlenbereich nur eine Behauptung.
cp "$TMPD/meins.otheme" "$TMPD/zahl.otheme"
printf 'radius=/bin/sh\ntaskbar_alpha=viel\n' >> "$TMPD/zahl.otheme"
bash tools/themestore/build.sh "$TMPD/zn" xfile="/zahl.otheme=$TMPD/zahl.otheme" \
    script='theme import /zahl.otheme zahl;theme show zahl;exit' \
    > "$TMPD/zn.log" 2>&1
ZN="$TMPD/zn/serial.txt"
znbad=$(grep -a 'theme: preset id=zahl ' "$ZN" | tail -1 | grep -oE ' bad=[0-9]+' | grep -oE '[0-9]+')
num "GEGENPROBE: ein Wert, der keine Zahl ist, wird GEZAEHLT" "${znbad:-0}" eq 2

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
# ---------------------------------------- RUNDE GLAS (nachtrag): DIE WAAGERECHTE
#
# Abschnitt 8 hat bis hierher NUR die Hoehe gemessen. Die Breite war
# damit unbeobachtet -- und genau dort sass der Fehler dieser Runde:
# die vier Regler standen bei x=316..744, ihre Karte endete bei x=696,
# also lagen Regler und Zahlenanzeige neben ihrem eigenen Untergrund.
# Ein Bild zeigt das sofort, eine Hoehenpruefung nie.
#
# Zwei Massstaebe, weil es zwei Fehler sind: `x+w` gegen die
# INNENBREITE des Fensters faengt das Widget, das aus dem Fenster
# laeuft; `x+w` gegen die Karte, auf der es liegt, faengt das Widget,
# das im Fenster bleibt und trotzdem neben seiner Flaeche schwebt. Die
# Karten melden ihr Rechteck selbst (`settings: rect name=kartel/karter`),
# damit hier nichts nachgerechnet wird, was das Programm schon weiss.
# Die Breite kommt aus derselben Zeile wie die Hoehe oben, und sie wird
# HIER geholt: `$WW` entsteht erst in Abschnitt 10, und eine Zahl, die
# aus ihrer Vorgabe kommt statt aus dem Lauf, misst nichts.
WBR=$(grep -ao 'name=win x=[0-9]* y=[0-9]* w=[0-9]*' "$SE" | tail -1 \
      | grep -oE 'w=[0-9]+' | cut -d= -f2)
IWIN=$(( ${WBR:-760} - 4 ))
HOVER=$(python3 - "$IWIN" "$SE" "$SEV" <<'PYX'
import re, sys
innen = int(sys.argv[1])
RE = re.compile(r'settings: rect name=(\w+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)')
n = 0
for path in sys.argv[2:]:
    txt = open(path, 'rb').read().decode('latin1')
    karten = {}
    rects = []
    for m in RE.finditer(txt):
        r = (m.group(1), int(m.group(2)), int(m.group(3)),
             int(m.group(4)), int(m.group(5)))
        if r[0] in ('kartel', 'karter'):
            karten[r[0]] = r
        elif r[0] != 'win' and re.match(r'^w[a-z][a-z]$', r[0]):
            rects.append(r)
    for (nm, x, y, w, h) in rects:
        if x + w > innen:
            print("        breit: %s in %s endet bei %d, das Fenster ist %d "
                  "breit" % (nm, path.split('/')[-2], x + w, innen),
                  file=sys.stderr)
            n += 1
        # Auf welcher Karte liegt es? Die, deren Rechteck seine Mitte
        # enthaelt. Widgets ueber beiden Spalten (Reiterleiste,
        # Statuszeile) liegen auf keiner und werden nur gegen das
        # Fenster gemessen.
        mx, my = x + w // 2, y + h // 2
        for k in karten.values():
            if k[1] == x and k[2] == y and k[3] == w and k[4] == h:
                continue
            if not (k[1] <= mx < k[1] + k[3] and k[2] <= my < k[2] + k[4]):
                continue
            if x < k[1] or x + w > k[1] + k[3]:
                print("        karte: %s in %s liegt bei %d..%d, die Karte %s "
                      "bei %d..%d" % (nm, path.split('/')[-2], x, x + w, k[0],
                                      k[1], k[1] + k[3]), file=sys.stderr)
                n += 1
print(n)
PYX
)
num "Widgets, die ueber die Fensterbreite oder ueber ihre Karte hinausragen" \
    "$HOVER" eq 0
KARTEN=$({ grep -ac 'settings: rect name=kart' "$SE" || true; })
num "und die Karten melden ihr Rechteck selbst" "${KARTEN:-0}" ge 2
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
# ---- UND DER REITER HEISST, WIE ER IN DER SPRACHDATEI HEISST.
#
# Die Reiterleiste hat ihre Namen bis zu dieser Runde still gekuerzt
# ("Netzzugrif" statt "Netzzugriff"): elf deutsche Reiter brauchen mehr
# Platz, als die Leiste hat, und `fit` schnitt ab, ohne dass irgendwo
# eine Zahl davon wusste. Jetzt meldet `say_tab` den GANZEN Namen und
# daneben, wie viele Oktette wirklich gemalt wurden. Hier wird der
# gemeldete Name Zeichen fuer Zeichen gegen locale/de/messages
# gehalten -- die Datei, aus der das Programm ihn holt. Ungleich ist
# rot, und zwar fuer jeden einzelnen Reiter.
TABNAME=$(python3 - "$SE" locale/de/messages <<'PY'
import re, sys
txt = open(sys.argv[1], 'rb').read().decode('latin1')
soll = None
for raw in open(sys.argv[2], 'rb').read().decode('utf-8').splitlines():
    if raw.startswith('settings.tabs'):
        soll = raw.split('=', 1)[1].strip().split('\\n')
if not soll:
    print('KEINE SPRACHDATEI'); raise SystemExit
ist = {}
for m in re.finditer(r'wlib: tab i=(\d+) .* nq=(\d+) nv=(\d+) t=(.*)', txt):
    ist[int(m.group(1))] = (m.group(4).encode('latin1').decode('utf-8',
                                                               'replace'),
                            int(m.group(2)), int(m.group(3)))
schlecht = []
for i, name in enumerate(soll):
    if i not in ist:
        schlecht.append('%d fehlt (%s)' % (i, name))
    elif ist[i][0] != name:
        schlecht.append("%d meldet '%s' statt '%s'" % (i, ist[i][0], name))
print(len(schlecht), ';'.join(schlecht[:4]) if schlecht else '')
PY
)
num "jeder Reiter meldet den Namen, der in der Sprachdatei steht ($TABNAME)" \
    "$(printf '%s' "$TABNAME" | cut -d' ' -f1)" eq 0
# ---- UND KEIN BLAUER STRICH UNTER DER REITERZEILE.
#
# In 02/03/08/10/13/14 stand unter der Reiterzeile ein Rest der
# Akzentfarbe bei x=313..330 und x=713..759: der Fokusring lag um die
# GANZE Leiste, und die zwei Karten der Seite ragen vier Bildpunkte in
# sie hinein und malten ihn streckenweise zu. Uebrig blieben zwei
# Striche, die zu nichts gehoeren. Der Ring liegt jetzt um den AKTIVEN
# REITER; gemessen wird das im Bild und gegen die Rechtecke, die
# `say_tab` selbst gemeldet hat: kein Bildpunkt der Akzentfarbe
# unterhalb der Reiterzeile.
STRICH=$(python3 - "$SE" "$TMPD/set/desktop.png" <<'PY'
import re, sys
from PIL import Image
txt = open(sys.argv[1], 'rb').read().decode('latin1')
tabs = {}
for m in re.finditer(r'wlib: tab i=(\d+) x=\d+ y=\d+ w=(\d+) h=(\d+)'
                     r' ax=(\d+) ay=(\d+)', txt):
    tabs[int(m.group(1))] = (int(m.group(4)), int(m.group(5)),
                             int(m.group(2)), int(m.group(3)))
if not tabs:
    print('999 keine tab-zeile'); raise SystemExit
unten = max(t[1] + t[3] for t in tabs.values())
im = Image.open(sys.argv[2]).convert('RGB')
# Die drei untersten Zeilen der Reiterzeile: dort lag die untere Kante
# des Fokusrings, und dort standen die Reste. Gezaehlt wird nicht in
# Bildpunkten, sondern in REITERN -- in wie vielen der gemeldeten
# Rechtecke ueberhaupt Akzentfarbe liegt. Ein Ring um den aktiven
# Reiter faerbt genau einen; ein Ring um die ganze Leiste faerbt alle,
# und ein von Karten zerschnittener Ring faerbt ein paar davon. Mehr
# als einer ist ein Rest.
betroffen = []
for i, (tx, ty, tw, th) in sorted(tabs.items()):
    n = 0
    for y in range(unten - 3, unten):
        for x in range(tx, tx + tw):
            p = im.getpixel((x, y))
            # Kraeftiges Blau: der Akzent (37,99,235) und der
            # Fokusring (18,49,117) erfuellen beides, jeder Grund und
            # jede graue Trennlinie dieser Themen keines von beiden.
            if p[2] > p[0] + 60 and p[2] > 110:
                n += 1
    if n > 2:
        betroffen.append('%d:%d' % (i, n))
print(len(betroffen), 'reiter mit Akzent in den untersten Zeilen',
      ','.join(betroffen[:6]))
PY
)
num "hoechstens EIN Reiter traegt Akzentfarbe an seiner Unterkante ($STRICH)" \
    "$(printf '%s' "$STRICH" | cut -d' ' -f1)" le 1

# --------------------------------------------------------- 9. die Bilder
echo
echo "== 9. ein Bild je Vorlage =="
SHOTN=0
# RUNDE GLAS: DIE AUFNAHME ZEIGT EIN FENSTER, und das ist kein
# Schoenheitswunsch.
#
# Bis hierher fuhren diese zehn Laeufe den blossen Schreibtisch. Auf dem
# steht kein Widget, und die einzigen `wlib: text`-Zeilen kamen vom
# Starter, den `desk` seit Runde WMPLUGIN UNSICHTBAR hochbringt
# (`launcher: versteckt`). Abschnitt 10 mass also die Beschriftungen
# eines Fensters, das gar nicht auf dem Schirm ist -- und meldete
# "leere Beschriftung" fuer jede davon. Mit `einst` steht das
# Einstellungsfenster IN DER VORLAGE da: dieselben zehn Bilder zeigen
# jetzt Schrift, Knoepfe, Listen und Regler in den Farben und der
# Rundung, um die es geht, und Abschnitt 10 misst etwas, das wirklich
# gemalt wurde.
for p in $PRESETS; do
    bash tools/themestore/build.sh "$TMPD/s-$p" preset="$p" extra='einst' \
        uitrace=yes keep=yes > "$TMPD/s-$p.log" 2>&1
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
# ---- UND JEDE KACHEL BLEIBT IN IHRER EIGENEN RUNDUNG.
#
# Eine Kachel malt ihren Umriss rund und ihren Inhalt aus Rechtecken.
# Der senkrechte Balken der Miniaturleiste sass buendig an der rechten
# Kante und lief damit an der Rundung vorbei ins Freie: in Bild 09 ein
# sechs Bildpunkte breiter Farbschlitz bei x=768..774 an den Vorlagen
# "Tafel" und "Studio", ausserhalb des Umrisses und ausserhalb der
# Spalte. `glascheck.py kachel` misst das an jeder der zehn Kacheln:
# `tiefe` sagt, dass die Kachel ueberhaupt rund ist, `fremd`, dass in
# den Eckvierteln nichts ausserhalb der Rundung steht.
# Der Radius kommt von der Kachel selbst (`wlib: radius ... typ=kachel`)
# und nicht aus dem laufenden Satz: eine Kachel malt in der Rolle
# "Tafel", und die hat ihre eigene Marke.
KACHR=$(grep -aoE 'wlib: radius rolle=[0-9]+ r=[0-9]+ typ=kachel' \
        "$TMPD/setv/serial.txt" | tail -1 | grep -oE 'r=[0-9]+' | cut -d= -f2)
KACHELN=$(python3 - "$TMPD/setv/serial.txt" <<'PY'
import re, sys
txt = open(sys.argv[1], 'rb').read().decode('latin1')
cut = txt.rfind('settings: rect name=waa ')
tail = txt[cut:] if cut >= 0 else txt
grp = {}
for m in re.finditer(r'settings: rect name=w\w\w x=\d+ y=\d+ w=(\d+) h=(\d+)'
                     r' ax=(\d+) ay=(\d+)', tail):
    w, h, ax, ay = (int(v) for v in m.groups())
    if h > 40:
        continue
    grp.setdefault((ax, w, h), []).append(ay)
if not grp:
    raise SystemExit
k, ys = max(grp.items(), key=lambda kv: len(kv[1]))
for ay in sorted(ys):
    print(k[0], ay, k[1], k[2])
PY
)
KN=$(printf '%s\n' "$KACHELN" | grep -c .)
num "die zehn Vorschaukacheln melden ihr Rechteck" "$KN" ge 10
KBAD=0; KTIEF=0
[ -s "$SHOTS/settings-vorlagen.png" ] || { KBAD=99; KTIEF=99; }
while read -r kx ky kw kh; do
    [ -n "$kx" ] || continue
    [ -s "$SHOTS/settings-vorlagen.png" ] || continue
    O=$(python3 tools/themestore/glascheck.py kachel \
        "$SHOTS/settings-vorlagen.png" "$kx" "$ky" "$kw" "$kh" \
        "${KACHR:-12}" 2>&1 | tail -1)
    f=$(printf '%s' "$O" | grep -oE 'fremd=[0-9]+' | cut -d= -f2)
    t=$(printf '%s' "$O" | grep -oE 'tiefe=[0-9]+' | cut -d= -f2)
    [ "${f:-9}" = 0 ] || { KBAD=$((KBAD+1)); echo "        $ky: $O"; }
    [ "${t:-0}" -gt 0 ] || KTIEF=$((KTIEF+1))
done <<EOF
$KACHELN
EOF
num "keine Kachel malt etwas ausserhalb ihrer Rundung" "$KBAD" eq 0
num "und jede der Kacheln ist wirklich rund (tiefe > 0)" "$KTIEF" eq 0

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
    # `cut` zaehlt seit dieser Runde auch die STILLE Kuerzung: eine
    # Beschriftung, von der weniger Oktette gemalt als gemeldet wurden,
    # ohne die drei Punkte, die einem Leser sagen, dass etwas fehlt.
    # `gekuerzt` daneben ist die Zahl der Beschriftungen, die
    # ueberhaupt gekuerzt wurden -- sie darf ungleich 0 sein (elf
    # Reiter passen nicht in eine Leiste), aber sie steht damit als
    # Zahl im Lauf statt nur im Bild.
    gk=$(printf '%s' "$out" | grep -oE 'gekuerzt [0-9]+' | grep -oE '[0-9]+')
    echo "        Seite $nm: gekuerzte Beschriftungen: ${gk:-0}"
    num "Seite $nm: abgeschnittene (still gekuerzte eingerechnet)" "${c:-1}" eq 0
    num "Seite $nm: ueberlappende" "${o:-1}" eq 0
    [ "${e:-1}" = 0 ] && [ "${c:-1}" = 0 ] && [ "${o:-1}" = 0 ] || \
        printf '%s\n' "$out" | sed 's/^/        /' | head -12
done
# ---------------- RUNDE GLAS (nachtrag): UND WIE VIEL DAVON UEBRIG IST
#
# Dass der gemeldete Name der der Sprachdatei ist, misst Abschnitt 8
# ("jeder Reiter meldet den Namen..."); das steht dort einmal und wird
# hier nicht noch einmal gerechnet. Was hier dazukommt, ist die andere
# Haelfte derselben Zeile: `nv` muss die Laenge DIESES Namens in
# Oktetten sein. Eine gemeldete Laenge, die nicht zum gemeldeten Text
# passt, macht jede Aussage ueber "gekuerzt" wertlos -- und genau
# diese zwei Zahlen benutzt tools/themestore/shotcheck.py, um eine
# stille Kuerzung von einem kurzen Namen zu unterscheiden.
TABNV=$(python3 - locale/de/messages "$SE" <<'PY'
import re, sys
want = None
for zeile in open(sys.argv[1], 'rb').read().decode('utf-8').splitlines():
    if zeile.startswith('settings.tabs'):
        want = zeile.split('=', 1)[1].strip().split('\\n')
if want is None:
    print(99)
    raise SystemExit
txt = open(sys.argv[2], 'rb').read().decode('utf-8', 'replace')
ist = {}
for m in re.finditer(r'wlib: tab i=(\d+) .* nq=(\d+) nv=(\d+) t=', txt):
    ist[int(m.group(1))] = (int(m.group(2)), int(m.group(3)))
n = 0
if len(ist) != len(want):
    print("        %d Reiter gemeldet, %d in der Sprachdatei"
          % (len(ist), len(want)), file=sys.stderr)
    n += 1
for i, w in enumerate(want):
    if i in ist and ist[i][1] != len(w.encode('utf-8')):
        print("        Reiter %d meldet nv=%d, '%s' hat %d Oktette"
              % (i, ist[i][1], w, len(w.encode('utf-8'))), file=sys.stderr)
        n += 1
print(n)
PY
)
num "Reiter, deren gemeldete Laenge nicht zu ihrem Namen passt" "${TABNV:-99}" eq 0
# UND WIE VIELE DAVON GEKUERZT GEMALT WERDEN. Das ist keine Zusage auf
# 0 -- elf deutsche Reiter passen in 728 Bildpunkte nur gekuerzt --,
# sondern die Zahl, die der naechste Umbau der Reiterleiste senken
# muss. Sie steht hier, damit sie nicht wieder unbemerkt steigt.
TABKURZ=$(python3 - "$SE" <<'PY'
import re, sys
# DER LETZTE BERICHT JE REITER GILT. Die Leiste malt sich mehrfach neu
# (Themenwechsel, erster Aufbau); die Zeilen zu zaehlen statt der
# Reiter haengt die Zahl an die Zahl der Neuzeichnungen.
ist = {}
txt = open(sys.argv[1], 'rb').read().decode('utf-8', 'replace')
for m in re.finditer(r'wlib: tab i=(\d+) .* nq=(\d+) nv=(\d+) t=', txt):
    ist[int(m.group(1))] = (int(m.group(2)), int(m.group(3)))
print(sum(1 for (nq, nv) in ist.values() if nq != nv))
PY
)
echo "        gekuerzt gemalte Reiterbeschriftungen: ${TABKURZ:-?} von $TABS"
num "und hoechstens neun der elf Reiter muessen gekuerzt werden" \
    "${TABKURZ:-99}" le 9
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

# ============================================== 11. RUNDE GLAS
echo
echo "== 11. Runde GLAS: Rundung, Durchsicht, Milchglas =="

# ---- 11a. DER RADIUS KOMMT AN, UND ER VERSCHIEBT NICHTS.
#
# Drei Laeufe mit 0, 12 und 24, und aus jedem drei Zahlen: was das
# Einstellungsfenster als laufenden Radius meldet, wie gross der
# groesste Radius ist, den ein Widget wirklich gemalt hat, und wie
# viele Widgetarten ihren Radius ueberhaupt gemeldet haben. Die
# Rechtecke derselben Seite muessen bei 0 und bei 24 ZEICHEN FUER
# ZEICHEN dieselben sein -- eine Rundung, die den Inhalt verschiebt,
# faellt genau hier auf.
for r in 0 12 24; do
    bash tools/themestore/build.sh "$TMPD/rad$r" extra='einst' uitrace=yes \
        keep=yes radius="$r" > "$TMPD/rad$r.log" 2>&1
    f="$TMPD/rad$r/serial.txt"
    g=$(grep -a 'settings: glas radius=' "$f" | tail -1 \
        | grep -oE 'radius=[0-9]+' | cut -d= -f2)
    same "Radius $r kommt in der laufenden Darstellung an" "$r" "${g:-}"
    # ROLLE 4 IST DER GRIFF DES REGLERS, und der ist ein KREIS. Er
    # sagt "so rund wie moeglich" und meint damit seinen halben
    # Durchmesser; ihn bei Radius 0 eckig zu machen hiesse, aus einem
    # Knopf ein Kaestchen zu machen. Er zaehlt deshalb hier nicht mit
    # -- und dass er ueberhaupt durch dieselbe eine Stelle geht, sagt
    # seine Meldung.
    MAXR=$(grep -aoE 'wlib: radius rolle=[0-3] r=[0-9]+' "$f" \
        | grep -oE 'r=[0-9]+$' | cut -d= -f2 | sort -n | tail -1)
    TYPEN=$(grep -aoE 'wlib: radius .*typ=[a-z]+' "$f" \
        | grep -oE 'typ=[a-z]+' | sort -u | wc -l)
    num "und $TYPEN Widgetarten melden, mit welchem Radius sie gemalt haben" \
        "$TYPEN" ge 8
    if [ "$r" = 0 ]; then
        num "bei Radius 0 malt KEIN Widget eine Rundung" "${MAXR:-99}" eq 0
        R0MAX=${MAXR:-0}
    else
        num "bei Radius $r ist der groesste gemalte Radius groesser als bei 0" \
            "${MAXR:-0}" gt "${R0MAX:-0}"
    fi
    cp "$TMPD/rad$r/desktop.png" "$SHOTS/glas-radius-$r.png" 2>/dev/null
done
R12MAX=$(grep -aoE 'wlib: radius rolle=[0-3] r=[0-9]+' "$TMPD/rad12/serial.txt" \
    | grep -oE 'r=[0-9]+$' | cut -d= -f2 | sort -n | tail -1)
R24MAX=$(grep -aoE 'wlib: radius rolle=[0-3] r=[0-9]+' "$TMPD/rad24/serial.txt" \
    | grep -oE 'r=[0-9]+$' | cut -d= -f2 | sort -n | tail -1)
# UND DER GRIFF BLEIBT RUND, auch wenn alles andere eckig ist.
GRIFF=$(grep -aoE 'wlib: radius rolle=4 r=[0-9]+' "$TMPD/rad0/serial.txt" \
    | grep -oE 'r=[0-9]+$' | cut -d= -f2 | sort -n | tail -1)
num "der Griff des Reglers bleibt auch bei Radius 0 ein Kreis" "${GRIFF:-0}" gt 0
num "und 24 rundet staerker als 12 (Bildpunkte)" "${R24MAX:-0}" gt "${R12MAX:-0}"
# DER INHALT SITZT BEI JEDEM RADIUS AN DERSELBEN STELLE.
grep -ao 'settings: rect name=[a-z]* x=[0-9]* y=[0-9]* w=[0-9]* h=[0-9]*' \
    "$TMPD/rad0/serial.txt" | sort -u > "$TMPD/rect0.txt"
grep -ao 'settings: rect name=[a-z]* x=[0-9]* y=[0-9]* w=[0-9]* h=[0-9]*' \
    "$TMPD/rad24/serial.txt" | sort -u > "$TMPD/rect24.txt"
RDIFF=$(diff "$TMPD/rect0.txt" "$TMPD/rect24.txt" | grep -c '^[<>]' || true)
num "und kein einziges Rechteck der Seite wandert zwischen Radius 0 und 24" \
    "$RDIFF" eq 0
num "und es sind ueberhaupt Rechtecke gemessen worden" \
    "$(grep -c . "$TMPD/rect0.txt")" ge 20
# DIE ECKE IST KANTENGEGLAETTET. In einem Quadrat von 24 Bildpunkten in
# der oberen linken Ecke des Fensters zaehlt `glascheck.py ecke`, wie
# viele Bildpunkte WEDER Fensterfarbe NOCH Untergrund sind. Bei einer
# Treppe gibt es keine solchen; jeder Zwischenton ist ein Beleg fuer
# die Glaettung. GEGENPROBE: bei Radius 0 ist die Ecke ein rechter
# Winkel und hat fast keine.
WX0=$(grep -ao 'name=win x=[0-9]*' "$TMPD/rad24/serial.txt" | tail -1 | cut -d= -f3)
WY0=$(grep -ao 'name=win x=[0-9]* y=[0-9]*' "$TMPD/rad24/serial.txt" | tail -1 \
      | grep -oE 'y=[0-9]+' | cut -d= -f2)
for r in 0 12 24; do
    E=$(python3 tools/themestore/glascheck.py ecke "$SHOTS/glas-radius-$r.png" \
        "${WX0:-20}" "${WY0:-3}" 24)
    eval "T$r=$(printf '%s' "$E" | grep -oE 'tiefe=[0-9]+' | cut -d= -f2)"
    eval "W$r=$(printf '%s' "$E" | grep -oE 'weich=[0-9]+' | cut -d= -f2)"
    echo "        Radius $r: $E"
done
num "bei Radius 12 ist die Ecke wirklich abgeschnitten (Bildpunkte)" "${T12:-0}" ge 8
num "und bei 24 tiefer als bei 12" "${T24:-0}" gt "${T12:-0}"
num "die Rundung bei 24 ist kantengeglaettet (Zeilen mit Mischton)" "${W24:-0}" ge 12
num "und die bei 12 auch" "${W12:-0}" ge 6
num "GEGENPROBE: bei Radius 0 ist die Ecke ein rechter Winkel" "${T0:-99}" eq 0
num "und hat keinen einzigen Mischton -- da ist nichts zu glaetten" "${W0:-99}" eq 0

# ---- 11b. DIE LEISTE MISCHT WIRKLICH -- GEGEN EINE ZWEITE RECHNUNG.
#
# Drei Laeufe ueber DEMSELBEN gemusterten Hintergrundbild, und in jedem
# wird jeder Bildpunkt des Leistengrundes gegen die Mischung gehalten,
# die `tools/themestore/glascheck.py` auf dem Wirt aus den zwei Farben
# des Bildes und der Schluesselfarbe der Leiste rechnet -- dieselbe
# Rolle, die `model.py` fuer die Kontraste spielt.
for a in 100 70 40; do
    bash tools/themestore/build.sh "$TMPD/al$a" tbalpha="$a" blur=0 \
        wallpaper=hell uitrace=yes keep=yes > "$TMPD/al$a.log" 2>&1
    cp "$TMPD/al$a/desktop.png" "$SHOTS/glas-alpha-$a.png" 2>/dev/null
    out=$(python3 tools/themestore/glascheck.py mix "$TMPD/al$a/desktop.png" "$a")
    pct=$(printf '%s' "$out" | grep -oE 'prozent=[0-9]+' | cut -d= -f2)
    fab=$(printf '%s' "$out" | grep -oE 'farben=[0-9]+' | cut -d= -f2)
    num "Leiste bei $a %%: Bildpunkte, die der nachgerechneten Mischung gleichen" \
        "${pct:-0}" ge 99
    if [ "$a" = 100 ]; then
        num "und bei voller Deckung ist der Grund EINE Farbe" "${fab:-0}" eq 1
    else
        num "und bei $a %% traegt der Grund das Muster des Bildes" "${fab:-0}" ge 2
    fi
done
# UND DIE DREI SIND WIRKLICH VERSCHIEDEN -- ein Mensch sieht es, und
# hier steht die Zahl dazu: die Streuung des Leistengrundes waechst mit
# der Durchsicht.
V100=$(python3 tools/themestore/glascheck.py var "$SHOTS/glas-alpha-100.png" \
       | grep -oE '^var [0-9]+' | cut -d' ' -f2)
V70=$(python3 tools/themestore/glascheck.py var "$SHOTS/glas-alpha-70.png" \
      | grep -oE '^var [0-9]+' | cut -d' ' -f2)
V40=$(python3 tools/themestore/glascheck.py var "$SHOTS/glas-alpha-40.png" \
      | grep -oE '^var [0-9]+' | cut -d' ' -f2)
num "voll deckend streut der Leistengrund nicht" "${V100:-1}" eq 0
num "bei 70 %% streut er" "${V70:-0}" gt 0
num "und bei 40 %% mehr als bei 70 %%" "${V40:-0}" gt "${V70:-0}"

# ---- 11c. MILCHGLAS: WEICHER, UND SCHNELL GENUG.
bash tools/themestore/build.sh "$TMPD/blur" tbalpha=70 blur=12 \
    wallpaper=hell uitrace=yes keep=yes > "$TMPD/blur.log" 2>&1
cp "$TMPD/blur/desktop.png" "$SHOTS/glas-milchglas.png" 2>/dev/null
VB=$(python3 tools/themestore/glascheck.py var "$SHOTS/glas-milchglas.png" \
     | grep -oE '^var [0-9]+' | cut -d' ' -f2)
FB=$(python3 tools/themestore/glascheck.py var "$SHOTS/glas-milchglas.png" \
     | grep -oE 'farben [0-9]+' | cut -d' ' -f2)
num "Milchglas: die Streuung des Ausschnitts SINKT (gegen $V70 ohne)" \
    "${VB:-999999}" lt "${V70:-0}"
num "und aus zwei Farben ist ein Verlauf geworden" "${FB:-0}" ge 4
GL=$(grep -a 'wm: glas r=' "$TMPD/blur/serial.txt" | tail -1)
BUS=$(printf '%s' "$GL" | grep -oE ' max=[0-9]+' | grep -oE '[0-9]+')
BPX=$(printf '%s' "$GL" | grep -oE ' px=[0-9]+' | grep -oE '[0-9]+')
echo "        Weichzeichner: $GL"
num "der Weichzeichner meldet seine Zeit je Vollbild (Mikrosekunden, QEMU/TCG)" \
    "${BUS:-0}" gt 0
# DIE SCHRANKE IST DIE EINES EMULIERTEN RECHNERS UND NICHT DIE EINES
# SCHREIBTISCHS. Gemessen wird unter QEMU/TCG, also ohne
# Hardwarebeschleunigung und neben anderen Laeufen auf derselben
# Maschine; dieselbe Schleife ueber 35 840 Bildpunkte sind drei
# Durchgaenge mit laufender Summe, also rund 100 000 Rechenschritte.
# Die Zahl hier faengt die Groessenordnung ab -- eine naive Faltung
# mit r=12 waere das Fuenfundzwanzigfache und riebe sich an ihr wund.
num "und sie bleibt unter einer Drittelsekunde (QEMU/TCG, ohne KVM)" \
    "${BUS:-999999999}" lt 300000
num "und er hat wirklich Bildpunkte angefasst" "${BPX:-0}" ge 10000
# O(1) JE BILDPUNKT, und das ist keine Meinung: der laufende Summe folgt
# genau eine Schleife je Zeile, und ein naiver Kasten haette hier die
# Fensterbreite als Faktor. Die Zahl dazu ist die Zeit oben; die Form
# steht im Quelltext, und dass sie nur EINMAL dasteht, misst 11e.
# UND DER ZWISCHENSPEICHER, an der Schlusszeile des Laufs abgelesen
# (`wm.glas_bericht`): wie oft ein Streifen gebraucht und wie oft er
# WIEDERVERWENDET wurde. Ohne diese Zahl waere "wird nicht neu
# gerechnet, wenn sich nichts ruehrt" eine Behauptung -- die einzige
# Zeile im Betrieb ist die des ersten Streifens, und in der steht
# zwangslaeufig cache=0/1.
GLC=$(printf '%s' "$GL" | grep -oE 'cache=[0-9]+/[0-9]+' | cut -d= -f2)
num "der Streifen wurde mehr als einmal gebraucht (cache $GLC)" \
    "$(printf '%s' "$GLC" | cut -d/ -f2)" ge 2
num "und dabei wiederverwendet statt neu gerechnet" \
    "$(printf '%s' "$GLC" | cut -d/ -f1)" ge 1

# ---- 11d. LESBAR BLEIBT LESBAR -- GEGEN DEN GEMISCHTEN GRUND.
#
# Nicht gegen die Flaechenfarbe des Themas, sondern gegen das, was
# wirklich im Bild steht. Und nicht gegen die HAEUFIGSTE Farbe des
# Leistengrundes, sondern gegen die SCHLECHTESTE: ueber einem
# gemusterten Bild liegt die Schrift mal auf der einen, mal auf der
# anderen Kachel, und eine Zusage, die nur die groessere von beiden
# misst, sagt ueber die Stelle, an der es eng wird, gar nichts.
# `glascheck.py kontrast` nimmt deshalb jede Farbe, die mindestens ein
# Prozent des Streifens ausmacht, und davon das Minimum -- und der
# Streifen reicht jetzt bis an den rechten Rand, also ueber die UHR,
# die vorher bei x=1100 abgeschnitten war. Einmal ueber einem hellen
# und einmal ueber einem dunklen Bild, denn die Schranke, die die
# Lesbarkeit haelt, greift auf beiden Seiten.
bash tools/themestore/build.sh "$TMPD/dunkel" tbalpha=40 blur=0 \
    wallpaper=dunkel uitrace=yes keep=yes > "$TMPD/dunkel.log" 2>&1
for pair in "al40:hell" "dunkel:dunkel"; do
    d=${pair%%:*}; nm=${pair##*:}
    FG=$(grep -a 'taskbar: text clock ' "$TMPD/$d/serial.txt" | tail -1 \
         | grep -oE 'fg=[0-9]+' | cut -d= -f2)
    FGH=$(printf '%06x' "${FG:-0}")
    KZ=$(python3 tools/themestore/glascheck.py kontrast \
         "$TMPD/$d/desktop.png" "$FGH")
    echo "        $nm: $KZ"
    K=$(printf '%s' "$KZ" | grep -oE '^kontrast [0-9]+' | cut -d' ' -f2)
    num "Leistenschrift gegen den SCHLECHTESTEN gemischten Grund ($nm, 40 %%), x100" \
        "${K:-0}" ge 450
    # GEGENPROBE, damit die Zahl nicht aus einem leeren Streifen
    # kommt: es muss wirklich mehr als ein Grund unter der Leiste
    # gelegen haben, sonst misst "der schlechteste" dasselbe wie "der
    # haeufigste" und die Verschaerfung waere keine.
    KK=$(printf '%s' "$KZ" | grep -oE 'kandidaten=[0-9]+' | cut -d= -f2)
    num "und es waren wirklich mehrere Gruende zu messen ($nm)" "${KK:-0}" ge 2
done

# ---- 11e. KEIN ZWEITER ORT FUER DIESELBE SACHE.
RR=$(grep -ac '^fn fill_round(' kernel/ui/wm.fi)
BL=$(grep -ac '^fn blend(' kernel/ui/wm.fi)
num "genau eine Stelle im Fensterserver malt ein rundes Rechteck" "$RR" eq 1
num "und genau eine mischt" "$BL" eq 1
GM=$(grep -ac '^fn glass_mix(' kernel/ui/wm.fi)
num "und genau eine entscheidet, wie deckend ein Punkt ist" "$GM" eq 1
SELF=$(grep -a 'wm: glastest ' "$TMPD/blur/serial.txt" | tail -1)
SN=$(printf '%s' "$SELF" | grep -oE 'glastest [0-9]+' | grep -oE '[0-9]+')
SM=$(printf '%s' "$SELF" | grep -oE '/ [0-9]+' | grep -oE '[0-9]+')
same "der Selbsttest der Mischung und des Weichzeichners laeuft durch" \
    "${SM:-7}" "${SN:-0}"

# ---- 11f. KEINE SCHLIEREN NACH EINEM ZUG UNTER DER LEISTE.
#
# Zweimal derselbe Stand, einmal mit einem Zug: das Fenster wird an
# seinem Titel unter die Leiste gezogen und wieder zurueck, OHNE
# loszulassen. Danach muss der Leistengrund Bildpunkt fuer Bildpunkt
# der des ungezogenen Laufs sein.
#
# WAS DIESE ZAHL BELEGT UND WAS NICHT: die Uhr malt die Leiste jede
# Sekunde neu, und die Aufnahme entsteht zwei Sekunden nach dem Zug --
# ein Bild allein kann also nicht zeigen, dass die Regel waehrend des
# Zuges gegriffen hat. Dass sie gegriffen HAT, sagt der Fensterserver
# selbst: `grow=` zaehlt jedes Schmutzrechteck, das auf die volle
# Leiste aufgezogen wurde, und mit `noglasgrow` steht die Regel still.
# Erst beide Zahlen zusammen sind die Zusage.
bash tools/themestore/build.sh "$TMPD/ruhe" extra='einst' tbalpha=70 blur=0 \
    wallpaper=hell uitrace=yes keep=yes > "$TMPD/ruhe.log" 2>&1
bash tools/themestore/build.sh "$TMPD/zug" extra='einst' tbalpha=70 blur=0 \
    wallpaper=hell uitrace=yes keep=yes click="400,10>400,600>400,10" \
    > "$TMPD/zug.log" 2>&1
ZD=$(python3 tools/themestore/glascheck.py diff "$TMPD/zug/desktop.png" \
     "$TMPD/ruhe/desktop.png" | grep -oE 'diff [0-9]+' | cut -d' ' -f2)
num "nach dem Zug unter der Leiste bleibt kein Bildpunkt stehen" "${ZD:-9999}" eq 0
ZG=$(grep -a 'wm: schlieren ' "$TMPD/zug/serial.txt" | tail -1 \
     | grep -oE 'grow=[0-9]+' | cut -d= -f2)
num "und die Schlierenregel hat wirklich gegriffen" "${ZG:-0}" ge 1
bash tools/themestore/build.sh "$TMPD/nogrow" extra='einst noglasgrow' \
    tbalpha=70 blur=0 wallpaper=hell uitrace=yes keep=yes \
    click="400,10>400,600>400,10" > "$TMPD/nogrow.log" 2>&1
NG=$(grep -a 'wm: schlieren ' "$TMPD/nogrow/serial.txt" | tail -1)
same "GEGENPROBE: mit noglasgrow steht die Regel still" "1" \
    "$(printf '%s' "$NG" | grep -oE 'aus=[0-9]+' | cut -d= -f2)"
same "und sie hat dort kein einziges Rechteck aufgezogen" "0" \
    "$(printf '%s' "$NG" | grep -oE 'grow=[0-9]+' | cut -d= -f2)"

# ---- 11f2. EIN ZUG OHNE RUECKWEG -- UND DAS FENSTER MALT SICH NEU.
#
# Die Probe darueber zieht hin UND ZURUECK. Ein Fenster, das am Ende
# wieder dort steht, wo es angefangen hat, belegt nichts ueber das
# Malen an der NEUEN Stelle: der Vergleich mit dem ungezogenen Lauf ist
# dann zwangslaeufig gleich. Genau daran ist Bild 15 dieser Runde
# vorbeigelaufen, und es kam noch etwas dazu:
#
#   * Der Griffpunkt 400,10 lag im oberen GREIFRAND (acht Bildpunkte
#     ueber einer Titelleiste von zweiundzwanzig). Der Lauf zog also
#     nie ein Fenster, sondern schob vierzehnmal dessen Oberkante nach
#     unten (`wm: zieh k=4 ... h=16`). Der "leere Rumpf" auf Bild 15
#     war ein auf seine Mindesthoehe zusammengeschobenes Fenster und
#     kein Zeichenfehler. Der Greifrand oben ist jetzt so dick wie der
#     Rahmen (kernel/ui/wm.fi, `grip_oben`); dass hier KEINE einzige
#     `wm: zieh`-Zeile mehr steht, ist die Gegenprobe dazu.
#
#   * 400,600 als Ziel schiebt das Fenster zu drei Vierteln aus dem
#     Schirm. Eine Beschriftung, die unter dem Bildrand liegt, ist
#     nicht gemalt -- und das ist richtig so, aber es ist kein
#     Zeichenfehler. Gezogen wird deshalb auf 400,210: das Fenster
#     reicht dann MIT SEINER UNTERKANTE unter die Leiste (die
#     Ueberlappung steht als Zahl da) und liegt trotzdem ganz auf dem
#     Schirm, so dass "leer 0" eine Aussage ueber das Malen ist.
bash tools/themestore/build.sh "$TMPD/zug1" extra='einst' tbalpha=70 blur=0 \
    wallpaper=hell uitrace=yes keep=yes click="400,10>400,210" \
    > "$TMPD/zug1.log" 2>&1
num "ein Griff in die Titelleiste ZIEHT das Fenster (Zahl der Groessenaenderungen)" \
    "$({ grep -ac 'wm: zieh ' "$TMPD/zug1/serial.txt" || true; })" eq 0
# DAS BREITESTE gemeldete Fenster ist das der Einstellungen (760
# gegen 440 des Starters), und die LETZTE seiner Zeilen ist die nach
# dem Zug. `tail -1` allein nimmt, wer zuletzt gesprochen hat, und das
# ist auf einem Schreibtisch mit fuenf Programmen kein Kriterium.
ZW=$(grep -ao 'wlib: win id=[0-9]* x=[0-9]* y=[0-9]* w=[0-9]* h=[0-9]*' \
     "$TMPD/zug1/serial.txt" \
     | awk '{ w=$0; sub(/.* w=/, "", w); sub(/ .*/, "", w)
              if (w+0 >= best+0) { best=w; line=$0 } } END { print line }')
ZWY=$(printf '%s' "$ZW" | grep -oE ' y=[0-9]+' | grep -oE '[0-9]+')
ZWH=$(printf '%s' "$ZW" | grep -oE ' h=[0-9]+' | grep -oE '[0-9]+')
ZWW=$(printf '%s' "$ZW" | grep -oE ' w=[0-9]+' | grep -oE '[0-9]+')
num "und es steht danach woanders als vorher (y)" "${ZWY:-3}" gt 100
LEIY=$(grep -a 'taskbar: STEHT ' "$TMPD/zug1/serial.txt" | tail -1 \
       | grep -oE 'y=[0-9]+' | cut -d= -f2)
# Die Ueberlappung in Bildpunkten, damit "keine Schliere" nicht ueber
# einem leeren Schnitt entsteht: Unterkante des Fensters SAMT Schmuck
# (Rahmen 2 + Titel 22) gegen die Oberkante der Leiste.
UEB=$(( (${ZWY:-3} + ${ZWH:-0} + 24 - ${LEIY:-772}) * ${ZWW:-0} ))
[ "$UEB" -lt 0 ] && UEB=0
echo "        Fenster ${ZWW:-?}x${ZWH:-?} bei y=${ZWY:-?}, Leiste ab y=${LEIY:-?}"
num "das Fenster reicht wirklich unter die Leiste (Bildpunkte Ueberlappung)" \
    "$UEB" ge 1000
ZOUT=$(python3 tools/themestore/shotcheck.py "$TMPD/zug1/desktop.ppm" \
       "$TMPD/zug1/serial.txt" 2>&1 | head -1)
echo "        $ZOUT"
num "nach dem Zug OHNE Rueckweg: leere Beschriftungen" \
    "$(printf '%s' "$ZOUT" | grep -oE 'empty [0-9]+' | grep -oE '[0-9]+')" eq 0
num "und abgeschnittene" \
    "$(printf '%s' "$ZOUT" | grep -oE ' cut [0-9]+' | grep -oE '[0-9]+')" eq 0
cp "$TMPD/zug1/desktop.png" "$SHOTS/glas-zug-unter-die-leiste.png" 2>/dev/null
[ -s "$SHOTS/glas-zug-unter-die-leiste.png" ] \
    && ok "und die Aufnahme dazu liegt in $SHOTS" \
    || bad "die Aufnahme des Zuges fehlt"

# ---- 11g. DER REGLER WIRKT SOFORT UND UEBERLEBT DEN NEUSTART.
#
# Kein Zeugenbericht, sondern ein Klick: der Lauf faehrt mit radius=4
# hoch, klickt auf die rechte Haelfte der Reglerbahn der Eckenrundung
# und sieht danach zweimal nach -- was die laufende Darstellung sagt
# (`settings: glas radius=`) und was in /etc/theme.conf auf der PLATTE
# steht. Das eine ist "wirkt ohne Neustart", das andere ist
# "ueberlebt einen Neustart", denn genau diese Zeile liest der naechste
# Start (11a misst, dass sie ankommt).
#
# ZWEI KLICKS UND NICHT EINER: der erste holt das Fenster nach vorn.
# Die Stelle kommt aus dem Rechteck, das die Seite selbst meldet, und
# nicht aus einer abgemessenen Zahl.
bash tools/themestore/build.sh "$TMPD/rvor" extra='einst' uitrace=yes \
    keep=yes radius=4 > "$TMPD/rvor.log" 2>&1
SL=$(grep -ao 'settings: rect name=[a-z]* x=[0-9]* y=40[0-9] w=[0-9]* h=[0-9]*' \
     "$TMPD/rvor/serial.txt" | tail -1)
SLX=$(printf '%s' "$SL" | grep -oE ' x=[0-9]+' | grep -oE '[0-9]+')
SLY=$(printf '%s' "$SL" | grep -oE ' y=[0-9]+' | grep -oE '[0-9]+')
SLW=$(printf '%s' "$SL" | grep -oE ' w=[0-9]+' | grep -oE '[0-9]+')
# Fensterinneres: 22 nach rechts (Rahmen) und 25 nach unten (Rahmen
# und Titel), wie es die Reiterzeile selbst meldet (x=16 -> ax=38).
CX=$(( ${SLX:-316} + 22 + (${SLW:-428} * 2 / 3) ))
CY=$(( ${SLY:-408} + 25 + 12 ))
bash tools/themestore/build.sh "$TMPD/rklick" extra='einst' uitrace=yes \
    keep=yes radius=4 click="$CX,$CY" click="$CX,$CY" \
    > "$TMPD/rklick.log" 2>&1
RNEU=$(grep -a 'settings: glas radius=' "$TMPD/rklick/serial.txt" | tail -1 \
       | grep -oE 'radius=[0-9]+' | cut -d= -f2)
num "ein Klick auf den Regler aendert die laufende Eckenrundung (von 4)" \
    "${RNEU:-4}" gt 4
RDAT=$(python3 tools/osum/mkfs.py cat "$TMPD/rklick/disk.img" /etc/theme.conf \
       2>/dev/null | grep -aE '^radius=' | tail -1 | cut -d= -f2)
same "und dieselbe Zahl steht danach in /etc/theme.conf auf der Platte" \
    "${RNEU:-4}" "${RDAT:-}"
# GEGENPROBE: ohne den Klick bleibt beides bei 4.
RVOR=$(grep -a 'settings: glas radius=' "$TMPD/rvor/serial.txt" | tail -1 \
       | grep -oE 'radius=[0-9]+' | cut -d= -f2)
same "GEGENPROBE: ohne Klick bleibt die Eckenrundung, wo sie war" "4" "${RVOR:-}"
same "und die Datei auch" "4" \
    "$(python3 tools/osum/mkfs.py cat "$TMPD/rvor/disk.img" /etc/theme.conf \
       2>/dev/null | grep -aE '^radius=' | tail -1 | cut -d= -f2)"
# UND EIN KASTEN FAENGT KEINEN KLICK MEHR AB. Ohne diese Zeile waere
# der Klick oben nie angekommen: `wlib.card` liegt als erstes Widget
# der Spalte ueber allem, was danach kommt, und `hit_at` nimmt das
# erste passende.
num "Schmuck-Widgets sind von der Trefferpruefung ausgenommen" \
    "$(grep -ac 'fn nur_schmuck(' kernel/user/wlib.fi)" eq 1

# UND DIE NEUEN BILDER WERDEN GENAUSO GEMESSEN WIE DIE ALTEN.
GSHOT=0
for s in glas-radius-0 glas-radius-12 glas-radius-24 glas-alpha-100 \
         glas-alpha-70 glas-alpha-40 glas-milchglas; do
    [ -s "$SHOTS/$s.png" ] && GSHOT=$((GSHOT+1)) || echo "        $s: kein Bild"
done
num "die sieben Aufnahmen der Runde GLAS" "$GSHOT" eq 7
GBAD=0
for pair in "rad0:glas-radius-0" "rad12:glas-radius-12" "rad24:glas-radius-24" \
            "al100:glas-alpha-100" "al70:glas-alpha-70" "al40:glas-alpha-40" \
            "blur:glas-milchglas"; do
    d=${pair%%:*}
    o=$(python3 tools/themestore/shotcheck.py "$TMPD/$d/desktop.ppm" \
        "$TMPD/$d/serial.txt" 2>&1 | head -1)
    e=$(printf '%s' "$o" | grep -oE 'empty [0-9]+' | grep -oE '[0-9]+')
    c=$(printf '%s' "$o" | grep -oE 'cut [0-9]+' | grep -oE '[0-9]+')
    ov=$(printf '%s' "$o" | grep -oE 'overlapping [0-9]+' | grep -oE '[0-9]+')
    if [ "${e:-1}" != 0 ] || [ "${c:-1}" != 0 ] || [ "${ov:-1}" != 0 ]; then
        echo "        $d: $o"; GBAD=$((GBAD+1))
    fi
done
num "und in keiner von ihnen eine leere, abgeschnittene oder ueberlappende Beschriftung" \
    "$GBAD" eq 0

# =========================== 12. NACHTRAG: DIE SCHRIFT IM TERMINAL
#                                UND DIE LEISTE SELBST
echo
echo "== 12. Nachtrag: der Umlaut im Terminal und die gemessene Leiste =="

# Auf JEDER Aufnahme dieser Runde stand "KEIN EINZIGES GERT!" im
# Terminalfenster. Die Quelle (kernel/ui/kgui.fi) schreibt "GERAET" mit
# einem richtigen UTF-8-Ä, also zwei Oktetten -- und `wm.term_putc` hat
# beide verschluckt, weil dort `if ch < 32 || ch > 126 { return }`
# stand. Kein Werkzeug konnte das melden: `shotcheck.py` misst, was
# Ring 3 ueber `wlib: text` meldet, und das Terminal malt durch den
# KERN. Deshalb hier, und deshalb mit demselben zweiten Rasterer, den
# tools/wm/run.sh seit Runde K10 benutzt.
TLOG="$TMPD/al100/serial.txt"
TPPM="$TMPD/al100/desktop.ppm"
has "$TLOG" "wm: termgitter win=" \
    "der Kern nennt das Zellenraster des Terminals (Lage, Zelle, Aufsteiger)"
UM=$(python3 tools/look/umlaut.py "$TLOG" "$TPPM" --gitter=1,1 \
     'KEIN EINZIGES GERÄT!' 2>&1 | head -1)
UF=$(printf '%s' "$UM" | grep -oE '[0-9]+ falsch' | grep -oE '^[0-9]+')
UT=$(printf '%s' "$UM" | grep -oE '[0-9]+ Tintenpunkte' | grep -oE '^[0-9]+')
num "das Ä im Terminal ist bildpunktgenau gerastert (falsche Punkte)" \
    "${UF:-99}" eq 0
num "und es ist ueberhaupt Tinte gemessen worden" "${UT:-0}" ge 500
# GEGENPROBE: die Zeichenkette, die VOR dem Nachtrag auf dem Schirm
# stand, darf jetzt NICHT mehr passen -- sonst misst die Zusage oben
# nichts.
#
# Gerechnet wird mit GENAU DEN Zahlen, die `umlaut.py` oben benutzt
# hat: das Zellenraster aus der Zeile des Kerns und die zwei Farben,
# die das Programm aus dem Bild gelesen und mitgedruckt hat.
TG=$(grep -a 'wm: termgitter win=' "$TLOG" | tail -1)
tgv() { printf '%s' "$TG" | grep -oE " $1=[0-9]+" | grep -oE '[0-9]+'; }
TGX=$(tgv x); TGY=$(tgv y); TGW=$(tgv cellw); TGH=$(tgv cellh)
TGP=$(tgv px)
hexrgb() { printf '%d %d %d' "0x${1:0:2}" "0x${1:2:2}" "0x${1:4:2}"; }
UFG=$(hexrgb "$(printf '%s' "$UM" | grep -oE 'fg=[0-9a-f]{6}' | cut -d= -f2)")
UBG=$(hexrgb "$(printf '%s' "$UM" | grep -oE 'bg=[0-9a-f]{6}' | cut -d= -f2)")
if python3 tools/gfx/checkshot.py tgrid "$TPPM" assets/osum-mono.ttf \
        "${TGP:-16}" "${TGX:-0}" "${TGY:-0}" "${TGW:-10}" "${TGH:-19}" 1 1 \
        $UFG $UBG 'KEIN EINZIGES GERT!' 0 >/dev/null 2>&1; then
    bad "GEGENPROBE: 'GERT!' und 'GERÄT!' sind fuer den Rasterer dasselbe"
else
    ok "GEGENPROBE: die alte, verstuemmelte Zeile passt NICHT mehr"
fi

# UND DIE LEISTE WIRD GEMESSEN WIE JEDES FENSTER. Bis zu diesem
# Nachtrag hat `shotcheck.py` GENAU EIN Fenster angesehen -- das mit
# dem meisten Text -- und die Taskleiste nie. Der titellose
# Fensterknopf lag deshalb in einem Bereich, den nichts geprueft hat.
BL=$(python3 tools/themestore/shotcheck.py "$TPPM" "$TLOG" --leiste 2>&1 \
     | grep -a 'shotcheck: leiste')
echo "        $BL"
BN=$(printf '%s' "$BL" | grep -oE 'texts [0-9]+' | grep -oE '[0-9]+')
BE=$(printf '%s' "$BL" | grep -oE 'empty [0-9]+' | grep -oE '[0-9]+')
BC=$(printf '%s' "$BL" | grep -oE 'cut [0-9]+' | grep -oE '[0-9]+')
BO=$(printf '%s' "$BL" | grep -oE 'overlapping [0-9]+' | grep -oE '[0-9]+')
num "die Leiste meldet ihre Beschriftungen mit gemessener Breite" \
    "${BN:-0}" ge 3
num "und keine davon ist leer" "${BE:-9}" eq 0
num "und keine ragt aus ihrem Bedienelement heraus" "${BC:-9}" eq 0
num "und keine ueberlappt eine andere" "${BO:-9}" eq 0
# DER FENSTERKNOPF TRAEGT EINEN TITEL UND NICHT NUR EIN SYMBOL.
BT=$(grep -aE '^taskbar: btn i=0 ' "$TLOG" | tail -1 | sed -E 's/.* t=//')
if [ -n "$BT" ]; then
    ok "der Fensterknopf der Leiste traegt den Fenstertitel: $BT"
else
    bad "der Fensterknopf der Leiste ist titellos (nur Symbol)"
fi

echo
echo "THEMESTORE: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
