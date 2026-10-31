#!/usr/bin/env bash
#
# Verwendung:  bash tools/themestore/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
TMPD=${TS_OUT:-$(mktemp -d)}
mkdir -p "$TMPD"
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
#
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "THEMESTORE: UEBERSPRUNGEN (0 Zusagen geprueft)," \
         "qemu-system-x86_64 ist nicht da"
    exit 77
fi

PRESETS=$(cd assets/themes && ls *.preset | sed 's/\.preset$//')
NPRESET=$(printf '%s\n' $PRESETS | wc -l)
SHOTS=docs/shots/themestore
GSHOTS=docs/shots/glas
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
            dark_scheme) ;;
            *) echo "        $p: unbekannter Schluessel '$k'"; KEYS_BAD=$((KEYS_BAD+1));;
        esac
    done < <(grep -aoE '^[a-z_]+=' "$f" | sed 's/=$//')
    for k in name scheme mode shape accent edge align radius \
             taskbar_alpha window_alpha taskbar_blur; do
        grep -qaE "^$k=" "$f" || { echo "        $p: '$k' fehlt"
            KEYS_MISS=$((KEYS_MISS+1)); }
    done
done
num "kein Schluessel ausserhalb der elf" "$KEYS_BAD" eq 0
num "und jeder der elf Pflichtschluessel steht in jeder Vorlage" "$KEYS_MISS" eq 0
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
PK=$(grep -acE 'var k_(name|scheme|dscheme|mode|shape|accent|edge|align|radius|taskbar_alpha|window_alpha|taskbar_blur): ' kernel/user/template.fi)
num "und vorlage.parse_key kennt genau zwoelf Schluesselnamen" "$PK" eq 12
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
bash tools/themestore/build.sh "$TMPD/show" script='theme show mitternacht;exit' \
    > "$TMPD/show.log" 2>&1
S="$TMPD/show/serial.txt"
PN=$(grep -ac 'theme: pair i=' "$S")
num "eine Vorlage meldet alle einundzwanzig Textpaarungen einzeln" "$PN" eq 21
PD=0
while read -r i fg bg r; do
    hr=$(python3 tools/themestore/model.py onepair "assets/themes/mitternacht.preset" "$fg" "$bg")
    [ "$r" = "$hr" ] || { echo "        Paar $i $fg/$bg: Gast $r, Wirt $hr"; PD=$((PD+1)); }
done < <(grep -a 'theme: pair i=' "$S" | sed -E 's/.*i=([0-9]+) fg=([a-z-]+) bg=([a-z-]+) r=([0-9]+).*/\1 \2 \3 \4/')
num "und jede der siebzehn stimmt mit dem Modell ueberein" "$PD" eq 0

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
same "den Formsatz" "osum" "$(grep -a '^shape=' "$TMPD/theme.conf" | cut -d= -f2)"
same "die Akzentfarbe" "0891b2" "$(grep -a '^accent=' "$TMPD/theme.conf" | cut -d= -f2)"
same "und /etc/taskbar.conf die Kante" "left" \
    "$(grep -a '^edge=' "$TMPD/taskbar.conf" | cut -d= -f2)"
same "und die Ausrichtung" "center" \
    "$(grep -a '^align=' "$TMPD/taskbar.conf" | cut -d= -f2)"
same "und die Hoehe der Leiste ist NICHT angefasst worden" "28" \
    "$(grep -a '^height=' "$TMPD/taskbar.conf" | cut -d= -f2)"
same "und ontop auch nicht" "1" \
    "$(grep -a '^ontop=' "$TMPD/taskbar.conf" | cut -d= -f2)"

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
BIN=$({ grep -acP '[\x00-\x08\x0e-\x1f]' "$TMPD/meins.otheme" 2>/dev/null || true; } | head -1)
num "und kein einziges Steuerzeichen -- kein Binaerformat" "$BIN" eq 0
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
cp "$TMPD/meins.otheme" "$TMPD/zahl.otheme"
printf 'radius=/bin/sh\ntaskbar_alpha=viel\n' >> "$TMPD/zahl.otheme"
bash tools/themestore/build.sh "$TMPD/zn" xfile="/zahl.otheme=$TMPD/zahl.otheme" \
    script='theme import /zahl.otheme zahl;theme show zahl;exit' \
    > "$TMPD/zn.log" 2>&1
ZN="$TMPD/zn/serial.txt"
znbad=$(grep -a 'theme: preset id=zahl ' "$ZN" | tail -1 | grep -oE ' bad=[0-9]+' | grep -oE '[0-9]+')
num "GEGENPROBE: ein Wert, der keine Zahl ist, wird GEZAEHLT" "${znbad:-0}" eq 2

echo
echo "== 8. die Seite Darstellung passt ins Fenster -- alle Seiten =="
bash tools/themestore/build.sh "$TMPD/set" extra='einst' uitrace=yes keep=yes \
    > "$TMPD/set.log" 2>&1
SE="$TMPD/set/serial.txt"
bash tools/themestore/build.sh "$TMPD/setflat" extra='einst' uitrace=yes sidebar=flat \
    > "$TMPD/setflat.log" 2>&1
SEF="$TMPD/setflat/serial.txt"
WH=$(grep -ao 'name=win x=[0-9]* y=[0-9]* w=[0-9]* h=[0-9]*' "$SE" | tail -1 \
     | grep -oE 'h=[0-9]+' | cut -d= -f2)
num "das Fenster ist so hoch wie der Arbeitsbereich zulaesst" "${WH:-0}" ge 560
INNER=$((${WH:-566} - 24))
#
VKLICK=$(python3 - "$SE" locale/de/messages <<'PYV'
import re, sys
txt = open(sys.argv[1], 'rb').read().decode('latin1')
soll = []
for raw in open(sys.argv[2], 'rb').read().decode('utf-8').splitlines():
    if raw.startswith('settings.tabs'):
        soll = soll + raw.split('=', 1)[1].strip().split('\\n')
ziel = soll.index('Vorlagen') if 'Vorlagen' in soll else 7
for m in re.finditer(r'wlib: tab i=(\d+) x=\d+ y=\d+ w=(\d+) h=(\d+) '
                     r'ax=(\d+) ay=(\d+)', txt):
    if int(m.group(1)) == ziel:
        print('%d,%d' % (int(m.group(4)) + int(m.group(2)) // 2,
                         int(m.group(5)) + int(m.group(3)) // 2))
        raise SystemExit
print('548,41')
PYV
)
echo "        Reiter 'Vorlagen' wird bei $VKLICK angeklickt"
bash tools/themestore/build.sh "$TMPD/setv" extra='einst' uitrace=yes keep=yes \
    click=$VKLICK click=$VKLICK > "$TMPD/setv.log" 2>&1
SEV="$TMPD/setv/serial.txt"
NR=$({ grep -ac 'settings: rect name=w[a-z][a-z] ' "$SE" "$SEV" || true; } \
     | cut -d: -f2 | awk '{n=n+$1} END {print n+0}')
num "gemeldete Rechtecke beider Seiten (vor dieser Runde waren es fuenf)" "${NR:-0}" ge 25
# ------------------------------- RUNDE GLAS (fix-r3-2): KEIN STILLER FILTER
#
GEPRUEFT=$(python3 - "$SE" "$SEV" <<'PYX'
import re, sys
n = 0
for path in sys.argv[1:]:
    txt = open(path, 'rb').read().decode('latin1')
    for m in re.finditer(
            r'settings: rect name=(\w+) x=\d+ y=\d+ w=\d+ h=\d+', txt):
        if m.group(1) != 'win':
            n += 1
print(n)
PYX
)
num "gemessene Rechtecke beider Seiten, ohne jeden Namensfilter" \
    "${GEPRUEFT:-0}" ge 88
OVER=$(python3 - "$INNER" "$SE" "$SEV" <<'PYX'
import re, sys
inner = int(sys.argv[1])
n = 0
for path in sys.argv[2:]:
    txt = open(path, 'rb').read().decode('latin1')
    # NUR die Zeilen von `settings` selbst. Die Zeile des FENSTERS
    # (name=win) sieht genauso aus, ist aber das Fenster und nicht sein
    # Inhalt -- sie gegen die INNENhoehe zu halten misst das Fenster
    # gegen sich selbst und ist immer rot. Jeder ANDERE Name wird
    # gemessen, auch `kartel`/`karter` und die Sachnamen.
    for m in re.finditer(
            r'settings: rect name=(\w+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)', txt):
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
        # RUNDE GLAS (fix-r3-2): die Karten sind Karten UND Rechtecke.
        # Bis hierher wurden sie nur als Untergrund gefuehrt und selbst
        # nie gegen die Fensterbreite gehalten -- und der Namensfilter
        # daneben hat ausserdem `edge`, `size`, `autohide`, `ontop` und
        # `apply` verschluckt. Gemessen wird ab jetzt jeder Name ausser
        # `win`; dass eine Karte nicht gegen sich selbst gemessen wird,
        # besorgt der Vergleich weiter unten.
        if r[0] in ('kartel', 'karter'):
            karten[r[0]] = r
        if r[0] != 'win':
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
#
TABNAME=$(python3 - "$SEF" locale/de/messages <<'PY'
import re, sys
txt = open(sys.argv[1], 'rb').read().decode('latin1')
soll = []
for raw in open(sys.argv[2], 'rb').read().decode('utf-8').splitlines():
    if raw.startswith('settings.tabs'):
        soll = soll + raw.split('=', 1)[1].strip().split('\\n')
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
        continue
    if ist[i][0] != name:
        schlecht.append("%d meldet '%s' statt '%s'" % (i, ist[i][0], name))
print(len(schlecht), ';'.join(schlecht[:4]) if schlecht else '')
PY
)
num "jeder Reiter meldet den Namen, der in der Sprachdatei steht ($TABNAME)" \
    "$(printf '%s' "$TABNAME" | cut -d' ' -f1)" eq 0
#
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
#
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
cp "$TMPD/set/desktop.png" "$SHOTS/settings-darstellung.png" 2>/dev/null
cp "$TMPD/setv/desktop.png" "$SHOTS/settings-vorlagen.png" 2>/dev/null
[ -s "$SHOTS/settings-vorlagen.png" ] \
    && ok "und die Seite Vorlagen mit den zehn Kacheln" \
    || bad "die Seite Vorlagen wurde nicht aufgenommen"
TL=$(grep -a 'settings: tiles n=' "$TMPD/setv/serial.txt" | tail -1 | grep -oE 'shown=[0-9]+' | cut -d= -f2)
num "und sie zeigt zehn Kacheln" "${TL:-0}" eq 10
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
#
KACHR=$(grep -aoE 'wlib: radius rolle=[0-9]+ r=[0-9]+ typ=kachel' \
        "$TMPD/setv/serial.txt" | tail -1 | grep -oE 'r=[0-9]+' | cut -d= -f2)
KACHELN=$(python3 - "$TMPD/setv/serial.txt" <<'PY'
import re, sys
txt = open(sys.argv[1], 'rb').read().decode('latin1')
cut = txt.rfind('settings: rect name=waa ')
tail = txt[cut:] if cut >= 0 else txt
win = re.findall(r'settings: rect name=win x=(\d+) y=(\d+)', txt)
ox, oy = (int(win[-1][0]) + 2, int(win[-1][1]) + 22) if win else (22, 25)
seen = set()
for m in re.finditer(r'wlib: kachelbalken x=\d+ y=\d+ w=\d+ h=\d+'
                     r' kx=(\d+) ky=(\d+) kw=(\d+) kh=(\d+)', tail):
    k = tuple(int(v) for v in m.groups())
    if k not in seen:
        seen.add(k)
        print(k[0] + ox, k[1] + oy, k[2], k[3])
PY
)
KN=$(printf '%s\n' "$KACHELN" | grep -c .)
# r1588: the Vorlagen page shows ONE preview tile (chooser + `wlib: kachelbalken` lines carry its rectangle); it was ten tiles before
num "die Vorschaukachel meldet ihr Rechteck" "$KN" ge 1
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
#
BALK=$(python3 - "$TMPD/setv/serial.txt" <<'PYB'
import re, sys
txt = open(sys.argv[1], 'rb').read().decode('latin1')
schnitt = txt.rfind("settings: rect name=waa ")
schwanz = txt[schnitt:] if schnitt >= 0 else txt
n = 0
schlecht = 0
for m in re.finditer(r"wlib: kachelbalken x=(\d+) y=(\d+) w=(\d+) h=(\d+)"
                     r" kx=(\d+) ky=(\d+) kw=(\d+) kh=(\d+) ein=(\d+)",
                     schwanz):
    x, y, w, h, kx, ky, kw, kh, ein = (int(v) for v in m.groups())
    n += 1
    if (x < kx + ein or x + w > kx + kw - ein
            or y < ky + 4 or y + h > ky + kh - 4):
        schlecht += 1
        print("        Balken %d,%d %dx%d schneidet die Kachel %d,%d %dx%d "
              "(ein=%d)" % (x, y, w, h, kx, ky, kw, kh, ein))
print("%d %d" % (n, schlecht))
PYB
)
printf '%s\n' "$BALK" | grep -a 'schneidet' || true
BALKZ=$(printf '%s\n' "$BALK" | tail -1)
num "die Vorschaukachel meldet ihre Balkenrechtecke" \
    "${BALKZ%% *}" ge 2
num "und kein Balken schneidet den Rahmen seiner Kachel" \
    "${BALKZ##* }" eq 0
BGEG=$(printf 'wlib: kachelbalken x=300 y=104 w=5 h=24 kx=12 ky=100 kw=293 kh=32 ein=12\n' \
       | python3 -c '
import re, sys
n = s = 0
for m in re.finditer(r"wlib: kachelbalken x=(\d+) y=(\d+) w=(\d+) h=(\d+)"
                     r" kx=(\d+) ky=(\d+) kw=(\d+) kh=(\d+) ein=(\d+)",
                     sys.stdin.read()):
    x, y, w, h, kx, ky, kw, kh, ein = (int(v) for v in m.groups())
    n += 1
    if (x < kx + ein or x + w > kx + kw - ein
            or y < ky + 4 or y + h > ky + kh - 4):
        s += 1
print(s)')
num "GEGENPROBE: ein Balken auf der Kachelkante wird gefunden" "$BGEG" eq 1

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
    gk=$(printf '%s' "$out" | grep -oE 'gekuerzt [0-9]+' | grep -oE '[0-9]+')
    #
    gr=$(printf '%s' "$out" | grep -oE 'reiterkurz [0-9]+' | grep -oE '[0-9]+')
    gf=$(printf '%s' "$out" | grep -oE 'fliesskurz [0-9]+' | grep -oE '[0-9]+')
    echo "        Seite $nm: gekuerzte Beschriftungen: ${gk:-0} (Reiter ${gr:-?}, Fliesstext ${gf:-?})"
    num "Seite $nm: gekuerzter Fliesstext" "${gf:-99}" eq 0
    num "Seite $nm: gekuerzte Reiter" "${gr:-99}" le 2
    num "Seite $nm: abgeschnittene (still gekuerzte eingerechnet)" "${c:-1}" eq 0
    num "Seite $nm: ueberlappende" "${o:-1}" eq 0
    [ "${e:-1}" = 0 ] && [ "${c:-1}" = 0 ] && [ "${o:-1}" = 0 ] || \
        printf '%s\n' "$out" | sed 's/^/        /' | head -12
done
#
TABNV=$(python3 - locale/de/messages "$SEF" <<'PY'
import re, sys
want = []
for zeile in open(sys.argv[1], 'rb').read().decode('utf-8').splitlines():
    if zeile.startswith('settings.tabs'):
        want = want + zeile.split('=', 1)[1].strip().split('\\n')
if not want:
    print(99)
    raise SystemExit
txt = open(sys.argv[2], 'rb').read().decode('utf-8', 'replace')
ist = {}
for m in re.finditer(r'wlib: tab i=(\d+) .* nq=(\d+) nv=(\d+) t=', txt):
    ist[int(m.group(1))] = (int(m.group(2)), int(m.group(3)))
n = 0
if len(ist) > len(want) or len(ist) < 8:
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
#
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
num "und hoechstens zwei der elf Reiter muessen gekuerzt werden" \
    "${TABKURZ:-99}" le 2
TABZEIL=$(python3 - "$SE" <<'PYZ'
import re, sys
txt = open(sys.argv[1], 'rb').read().decode('utf-8', 'replace')
ist = {}
for m in re.finditer(r'wlib: tab i=(\d+) x=\d+ y=(\d+) ', txt):
    ist[int(m.group(1))] = int(m.group(2))
print(len(set(ist.values())))
PYZ
)
echo "        verschiedene Zeilen der Reiterleiste: ${TABZEIL:-?}"
# two rows at the width of this window in English, three in German (the rows are
# filled by MEASURED width now): what is asserted is that the bar wrapped
num "und die Reiterleiste hat dafuer mehrere Zeilen (sie bricht um, sie schneidet nicht)" "${TABZEIL:-0}" ge 2
BARBAD=0
for p in $PRESETS; do
    f="$TMPD/s-$p/serial.txt"
    [ -s "$f" ] || { BARBAD=$((BARBAD+1)); continue; }
    want=$(grep -aE '^edge=' "assets/themes/$p.preset" | cut -d= -f2)
    got=$(grep -a 'taskbar: conf ' "$f" | grep -aE 'ename=[a-z]+' | tail -1 | grep -oE 'ename=[a-z]+' | cut -d= -f2)
    [ "$want" = "$got" ] || { echo "        $p: Leiste $got statt $want"; BARBAD=$((BARBAD+1)); }
done
num "in jeder Aufnahme sitzt die Leiste an der Kante, die die Vorlage nennt" "$BARBAD" eq 0
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

for r in 0 12 24; do
    bash tools/themestore/build.sh "$TMPD/rad$r" extra='einst' uitrace=yes \
        keep=yes radius="$r" > "$TMPD/rad$r.log" 2>&1
    f="$TMPD/rad$r/serial.txt"
    g=$(grep -a 'settings: glas radius=' "$f" | tail -1 \
        | grep -oE 'radius=[0-9]+' | cut -d= -f2)
    if [ -z "${g:-}" ]; then
        echo "        (Leitung verschraenkt, rad$r wird einmal wiederholt)"
        bash tools/themestore/build.sh "$TMPD/rad$r" extra='einst' \
            uitrace=yes keep=yes radius="$r" > "$TMPD/rad$r.log" 2>&1
        g=$(grep -a 'settings: glas radius=' "$f" | tail -1 \
            | grep -oE 'radius=[0-9]+' | cut -d= -f2)
    fi
    same "Radius $r kommt in der laufenden Darstellung an" "$r" "${g:-}"
    MAXR=$(grep -aoE 'wlib: radius rolle=[0-3] r=[0-9]+' "$f" \
        | grep -oE 'r=[0-9]+$' | cut -d= -f2 | sort -n | tail -1)
    TYPEN=$(grep -aoE 'wlib: radius .*typ=[a-z]+' "$f" \
        | grep -oE 'typ=[a-z]+' | sort -u | wc -l)
    num "und $TYPEN Widgetarten melden, mit welchem Radius sie gemalt haben" \
        "$TYPEN" ge 8
    #
    MINR=$(grep -aoE 'wlib: radius rolle=[0-3] r=[0-9]+' "$f" \
        | grep -oE 'r=[0-9]+$' | cut -d= -f2 | sort -n | head -1)
    ECKIG=$(grep -aoE 'wlib: radius rolle=[0-3] r=0 typ=[a-z]+' "$f" \
        | grep -oE 'typ=[a-z]+' | sort -u | wc -l)
    if [ "$r" = 0 ]; then
        num "bei Radius 0 malt KEIN Widget eine Rundung" "${MAXR:-99}" eq 0
        num "und auch das kleinste gemalte Mass ist 0" "${MINR:-99}" eq 0
        R0MAX=${MAXR:-0}
    else
        num "bei Radius $r ist der groesste gemalte Radius groesser als bei 0" \
            "${MAXR:-0}" gt "${R0MAX:-0}"
        num "und bei Radius $r rundet auch das KLEINSTE Widget (Rollen 0..3)" \
            "${MINR:-0}" gt 0
        num "und bei Radius $r ist kein gemeldeter Widgettyp eckig geblieben" \
            "${ECKIG:-99}" eq 0
    fi
    cp "$TMPD/rad$r/desktop.png" "$SHOTS/glas-radius-$r.png" 2>/dev/null
done
R12MAX=$(grep -aoE 'wlib: radius rolle=[0-3] r=[0-9]+' "$TMPD/rad12/serial.txt" \
    | grep -oE 'r=[0-9]+$' | cut -d= -f2 | sort -n | tail -1)
R24MAX=$(grep -aoE 'wlib: radius rolle=[0-3] r=[0-9]+' "$TMPD/rad24/serial.txt" \
    | grep -oE 'r=[0-9]+$' | cut -d= -f2 | sort -n | tail -1)
GRIFF=$(grep -aoE 'wlib: radius rolle=4 r=[0-9]+' "$TMPD/rad0/serial.txt" \
    | grep -oE 'r=[0-9]+$' | cut -d= -f2 | sort -n | tail -1)
num "der Griff des Reglers bleibt auch bei Radius 0 ein Kreis" "${GRIFF:-0}" gt 0
num "und 24 rundet staerker als 12 (Bildpunkte)" "${R24MAX:-0}" gt "${R12MAX:-0}"
lastbatch() { python3 - "$1" <<'PYL'
import re, sys
t = open(sys.argv[1], 'rb').read().decode('latin1')
i = t.rfind('settings: rect name=waa ')
for m in re.finditer(r'settings: rect name=[a-z]* x=\d+ y=\d+ w=\d+ h=\d+', t[i if i >= 0 else 0:]):
    print(m.group(0))
PYL
}
lastbatch "$TMPD/rad0/serial.txt" | sort -u > "$TMPD/rect0.txt"
lastbatch "$TMPD/rad24/serial.txt" | sort -u > "$TMPD/rect24.txt"
RDIFF=$(diff "$TMPD/rect0.txt" "$TMPD/rect24.txt" | grep -c '^[<>]' || true)
if [ "${RDIFF:-0}" != 0 ]; then diff "$TMPD/rect0.txt" "$TMPD/rect24.txt" | head -12 | sed 's/^/        /'; fi
num "und kein einziges Rechteck der Seite wandert zwischen Radius 0 und 24" \
    "$RDIFF" eq 0
num "und es sind ueberhaupt Rechtecke gemessen worden" \
    "$(grep -c . "$TMPD/rect0.txt")" ge 20
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
# 12 -> 8 (03.10.2026, r120): `surface-sunken` -- the top of the desktop
# gradient behind the window -- moved one ramp step (it was the fill of the
# fields), the ground behind the corner has another tint and the tool counts
# 11 rows with a blend tone instead of 14. A staircase still measures 0
# (the counter-check above at radius 0), so 8 still separates smoothing
# from none.
num "die Rundung bei 24 ist kantengeglaettet (Zeilen mit Mischton)" "${W24:-0}" ge 8
num "und die bei 12 auch" "${W12:-0}" ge 3
num "GEGENPROBE: bei Radius 0 ist die Ecke ein rechter Winkel" "${T0:-99}" eq 0
num "und hat keinen einzigen Mischton -- da ist nichts zu glaetten" "${W0:-99}" eq 0

RH=$(grep -ao 'wm: rahmen x=[0-9]* y=[0-9]* w=[0-9]* h=[0-9]* r=[0-9]*' \
     "$TMPD/rad24/serial.txt" | awk -F'[= ]' '$8 >= 400' | tail -1)
if [ -z "${RH:-}" ]; then
    echo "        (keine Rahmenzeile, rad24 wird einmal wiederholt)"
    bash tools/themestore/build.sh "$TMPD/rad24" extra='einst' uitrace=yes \
        keep=yes radius=24 > "$TMPD/rad24.log" 2>&1
    RH=$(grep -ao 'wm: rahmen x=[0-9]* y=[0-9]* w=[0-9]* h=[0-9]* r=[0-9]*' \
         "$TMPD/rad24/serial.txt" | awk -F'[= ]' '$8 >= 400' | tail -1)
fi
echo "        ${RH:-KEINE Rahmenzeile}"
RHX=$(printf '%s' "$RH" | grep -oE ' x=[0-9]+' | cut -d= -f2)
RHY=$(printf '%s' "$RH" | grep -oE ' y=[0-9]+' | cut -d= -f2)
RHW=$(printf '%s' "$RH" | grep -oE ' w=[0-9]+' | cut -d= -f2)
RHH=$(printf '%s' "$RH" | grep -oE ' h=[0-9]+' | cut -d= -f2)
RHR=$(printf '%s' "$RH" | grep -oE ' r=[0-9]+' | cut -d= -f2)
same "der Server meldet das Rechteck, das er mit Radius 24 gemalt hat" \
    "24" "${RHR:-}"
ECKBAD=0; ECKWEICH=99; ECKTIEF=99
for wo in ol or ul ur; do
    ex=${RHX:-20}; ey=${RHY:-3}
    [ "$wo" = or ] || [ "$wo" = ur ] && ex=$(( ${RHX:-20} + ${RHW:-760} - 24 ))
    [ "$wo" = ul ] || [ "$wo" = ur ] && ey=$(( ${RHY:-3} + ${RHH:-566} - 24 ))
    E=$(python3 tools/themestore/glascheck.py ecke \
        "$SHOTS/glas-radius-24.png" "$ex" "$ey" 24 "$wo" 2>&1)
    echo "        $E"
    t=$(printf '%s' "$E" | grep -oE 'tiefe=[0-9]+' | cut -d= -f2)
    wq=$(printf '%s' "$E" | grep -oE 'weich=[0-9]+' | cut -d= -f2)
    [ -n "${t:-}" ] && [ -n "${wq:-}" ] || { ECKBAD=$((ECKBAD+1)); continue; }
    [ "$t" -lt "$ECKTIEF" ] && ECKTIEF=$t
    [ "$wq" -lt "$ECKWEICH" ] && ECKWEICH=$wq
done
num "alle vier Fensterecken sind gemessen worden" "$ECKBAD" eq 0
num "und die FLACHSTE der vier ist bei Radius 24 immer noch rund (tiefe)" \
    "$ECKTIEF" gt 0
num "und die HAERTESTE der vier ist kantengeglaettet (Zeilen mit Mischton)" \
    "$ECKWEICH" ge 6
ECK0=0
for wo in ol or ul ur; do
    ex=${RHX:-20}; ey=${RHY:-3}
    [ "$wo" = or ] || [ "$wo" = ur ] && ex=$(( ${RHX:-20} + ${RHW:-760} - 24 ))
    [ "$wo" = ul ] || [ "$wo" = ur ] && ey=$(( ${RHY:-3} + ${RHH:-566} - 24 ))
    t=$(python3 tools/themestore/glascheck.py ecke \
        "$SHOTS/glas-radius-0.png" "$ex" "$ey" 24 "$wo" 2>&1 \
        | grep -oE 'tiefe=[0-9]+' | cut -d= -f2)
    [ "${t:-99}" = 0 ] || ECK0=$((ECK0+1))
done
num "GEGENPROBE: bei Radius 0 ist keine der vier Ecken rund" "$ECK0" eq 0

KART=$(python3 - "$TMPD/rad0/serial.txt" <<'PYK2'
import re, sys
roh = open(sys.argv[1], 'rb').read().decode('latin1')
w = re.findall(r'settings: rect name=win x=(\d+) y=(\d+)', roh)
rects = re.findall(r'settings: rect name=(kart[a-z]*) x=(\d+) y=(\d+)'
                   r' w=(\d+) h=(\d+)', roh)
gesehen = {}
for nm, x, y, bw, bh in rects:
    gesehen[nm] = (int(x), int(y), int(bw), int(bh))
for nm in sorted(gesehen):
    x, y, bw, bh = gesehen[nm]
    if not w:
        break
    # dieselbe Umrechnung wie in Abschnitt 10: Rahmen und Titelzeile
    print(nm, int(w[-1][0]) + 2 + x, int(w[-1][1]) + 22 + y, bw, bh)
PYK2
)
KARTN=0
while read -r nm kx ky kw kh; do
    [ -n "${nm:-}" ] || continue
    KARTN=$((KARTN+1))
    L0=$(python3 tools/themestore/glascheck.py linien \
         "$SHOTS/glas-radius-0.png" "$kx" "$ky" "$kw" "$kh" 2>&1 | tail -1)
    L24=$(python3 tools/themestore/glascheck.py linien \
          "$SHOTS/glas-radius-24.png" "$kx" "$ky" "$kw" "$kh" 2>&1 | tail -1)
    echo "        $nm  Radius 0: $L0   Radius 24: $L24"
    N0=$(printf '%s' "$L0" | grep -oE 'linien=[0-9]+' | cut -d= -f2)
    N24=$(printf '%s' "$L24" | grep -oE 'linien=[0-9]+' | cut -d= -f2)
    num "in der Karte $nm stehen waagerechte Linien" "${N0:-0}" ge 1
    same "und bei Radius 24 sind es in $nm genauso viele (keine doppelte Kante)" \
        "${N0:-x}" "${N24:-y}"
done <<EOF
$KART
EOF
num "und es sind ueberhaupt Karten gemessen worden" "$KARTN" ge 2

python3 - "$TMPD/bunt.osym" <<'BUNTPY'
import struct, sys
# Dasselbe Format und dieselbe Groesse wie `wallpaper=hell` in
# tools/themestore/build.sh (OSYM, 120x90, BGRA), nur mit zwei
# kraeftigen Farben gleicher Helligkeit. Ein Schachbrett von zwoelf
# Bildpunkten, das der Schreibtisch auf rund achtzig dehnt.
w, h = 120, 90
a, b = (255, 178, 104), (200, 245, 255)
px = bytearray()
for y in range(h):
    for x in range(w):
        c = a if ((x // 12) + (y // 12)) % 2 == 0 else b
        px += bytes((c[2], c[1], c[0], 0xFF))
open(sys.argv[1], "wb").write(b"OSYM" + struct.pack("<II", w, h) + bytes(px))
BUNTPY
for a in 100 70 40; do
    bash tools/themestore/build.sh "$TMPD/al$a" tbalpha="$a" blur=0 \
        wallpaper="$TMPD/bunt.osym" uitrace=yes keep=yes \
        > "$TMPD/al$a.log" 2>&1
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
V100=$(python3 tools/themestore/glascheck.py var "$SHOTS/glas-alpha-100.png" \
       | grep -oE '^var [0-9]+' | cut -d' ' -f2)
V70=$(python3 tools/themestore/glascheck.py var "$SHOTS/glas-alpha-70.png" \
      | grep -oE '^var [0-9]+' | cut -d' ' -f2)
V40=$(python3 tools/themestore/glascheck.py var "$SHOTS/glas-alpha-40.png" \
      | grep -oE '^var [0-9]+' | cut -d' ' -f2)
num "voll deckend streut der Leistengrund nicht" "${V100:-1}" eq 0
num "bei 70 %% streut er" "${V70:-0}" gt 0
num "und bei 40 %% mehr als bei 70 %%" "${V40:-0}" gt "${V70:-0}"
#
VQ=$(( ${V40:-0} * 100 / (${V70:-1} + 1) ))
echo "        Streuung 40 %% gegen 70 %%: ${VQ} von Hundert (Deckel 400)"
num "die Streuung bei 40 %% ist mindestens das 3,5-fache der bei 70 %% (x100)" \
    "$VQ" ge 350
num "und sie ueberschreitet den Deckel der Blendgleichung nicht (x100)" \
    "$VQ" le 420
FABST=$(python3 - "$SHOTS/glas-alpha-70.png" "$SHOTS/glas-alpha-40.png" <<'PYF'
import sys
sys.path.insert(0, 'tools/themestore')
from PIL import Image
import glascheck as G
mit = []
for p in sys.argv[1:3]:
    im = Image.open(p).convert('RGB')
    pts = G.leiste(im, 28, 300, 1100)
    px = [im.getpixel(q) for q in pts]
    mit.append([sum(c[i] for c in px) / len(px) for i in range(3)])
print(int(sum(abs(mit[0][i] - mit[1][i]) for i in range(3)) / 3))
PYF
)
num "mittlerer Farbabstand des Leistengrundes zwischen 70 %% und 40 %% (Stufen)" \
    "${FABST:-0}" ge 12
GL40=$(grep -a 'wm: glas alpha_soll=' "$TMPD/al40/serial.txt" | tail -1)
echo "        $GL40"
num "bei Regler 40 hebt die Lesbarkeitsschranke keinen einzigen Bildpunkt an" \
    "$(printf '%s' "$GL40" | grep -oE 'hoch=[0-9]+' | cut -d= -f2)" eq 0
same "und der Server meldet genau die Reglerstellung als Soll" "40" \
    "$(printf '%s' "$GL40" | grep -oE 'alpha_soll=[0-9]+' | cut -d= -f2)"
#
echo
echo "== 11b2. der Textschild der Leiste =="
SCH=$(grep -a 'taskbar: schild ' "$TMPD/al40/serial.txt" | tail -1)
SCH100=$(grep -a 'taskbar: schild ' "$TMPD/al100/serial.txt" | tail -1)
echo "        40 %%: $SCH"
echo "        100 %%: $SCH100"
same "bei 40 %% ist der Schild an" "1" \
    "$(printf '%s' "$SCH" | grep -oE 'an=[0-9]+' | cut -d= -f2)"
num "und er hat wirklich Platten gemalt" \
    "$(printf '%s' "$SCH" | grep -oE ' n=[0-9]+' | cut -d= -f2)" ge 2
same "GEGENPROBE: bei voller Deckung ist er aus" "0" \
    "$(printf '%s' "$SCH100" | grep -oE 'an=[0-9]+' | cut -d= -f2)"
num "und dann malt er auch keine einzige Platte" \
    "$(printf '%s' "$SCH100" | grep -oE ' n=[0-9]+' | cut -d= -f2)" eq 0
SFARBE=$(printf '%s' "$SCH" | grep -oE 'farbe=[0-9a-f]+' | cut -d= -f2)
SGRUND=$(printf '%s' "$SCH" | grep -oE 'grund=[0-9a-f]+' | cut -d= -f2)
SABST=$(python3 -c "
import sys
a = int('${SFARBE:-0}', 16); b = int('${SGRUND:-0}', 16)
print(sum(abs(((a >> s) & 255) - ((b >> s) & 255)) for s in (0, 8, 16)))")
num "der Kanalabstand der Platte zur Schluesselfarbe (voll deckend ab 96)" \
    "${SABST:-0}" ge 96
TFG=$(grep -a 'taskbar: text clock ' "$TMPD/al40/serial.txt" | tail -1 \
      | grep -oE 'fg=[0-9]+' | cut -d= -f2)
TK=$(python3 tools/themestore/glascheck.py kontrast \
     "$SHOTS/glas-alpha-40.png" "$(printf '%06x' "${TFG:-0}")")
echo "        $TK"
num "die Leistenschrift haelt bei 40 %% ihre 4,5:1 (x100)" \
    "$(printf '%s' "$TK" | grep -oE '^kontrast [0-9]+' | cut -d' ' -f2)" ge 450

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
#
bash tools/themestore/build.sh "$TMPD/grob0" scheme=midnight mode=dark \
    tbalpha=40 blur=0 wallpaper=dunkelgrob uitrace=yes keep=yes \
    > "$TMPD/grob0.log" 2>&1
bash tools/themestore/build.sh "$TMPD/grob16" scheme=midnight mode=dark \
    tbalpha=40 blur=16 wallpaper=dunkelgrob uitrace=yes keep=yes \
    > "$TMPD/grob16.log" 2>&1
cp "$TMPD/grob16/desktop.png" "$SHOTS/glas-milchglas-grob.png" 2>/dev/null
VG0=$(python3 tools/themestore/glascheck.py var "$TMPD/grob0/desktop.png" \
      | grep -oE '^var [0-9]+' | cut -d' ' -f2)
VG16=$(python3 tools/themestore/glascheck.py var "$TMPD/grob16/desktop.png" \
       | grep -oE '^var [0-9]+' | cut -d' ' -f2)
FG0=$(python3 tools/themestore/glascheck.py var "$TMPD/grob0/desktop.png" \
      | grep -oE 'farben [0-9]+' | cut -d' ' -f2)
FG16=$(python3 tools/themestore/glascheck.py var "$TMPD/grob16/desktop.png" \
       | grep -oE 'farben [0-9]+' | cut -d' ' -f2)
echo "        grobes Muster, dunkles Schema: var $VG0 ($FG0 Farben) ohne," \
     "var $VG16 ($FG16 Farben) mit Milchglas 16"
num "grobes Muster: die Streuung sinkt auch dort (gegen $VG0 ohne)" \
    "${VG16:-999999}" lt "${VG0:-0}"
num "und aus dem Schachbrett ist ein Verlauf mit vielen Stufen geworden" \
    "${FG16:-0}" ge 12
num "GEGENPROBE: ohne Weichzeichner sind es genau die zwei des Musters" \
    "${FG0:-0}" eq 2
GFG=$(grep -a 'taskbar: text clock ' "$TMPD/grob16/serial.txt" | tail -1 \
      | grep -oE 'fg=[0-9]+' | cut -d= -f2)
GK=$(python3 tools/themestore/glascheck.py kontrast \
     "$TMPD/grob16/desktop.png" "$(printf '%06x' "${GFG:-0}")")
echo "        $GK"
num "und die Leistenschrift haelt auf dem Milchglas ihre 4,5:1 (x100)" \
    "$(printf '%s' "$GK" | grep -oE '^kontrast [0-9]+' | cut -d' ' -f2)" ge 450
#
python3 - "$TMPD/fein.osym" <<'FEINPY'
import struct, sys
w, h = 120, 90
a, b = (0x10, 0x12, 0x1A), (0x50, 0x30, 0x78)
px = bytearray()
for y in range(h):
    for x in range(w):
        c = a if ((x // 12) + (y // 12)) % 2 == 0 else b
        px += bytes((c[2], c[1], c[0], 0xFF))
open(sys.argv[1], "wb").write(b"OSYM" + struct.pack("<II", w, h) + bytes(px))
FEINPY
for v in 0 16; do
    bash tools/themestore/build.sh "$TMPD/fein$v" scheme=midnight mode=dark \
        tbalpha=40 blur="$v" wallpaper="$TMPD/fein.osym" uitrace=yes \
        keep=yes > "$TMPD/fein$v.log" 2>&1
done
cp "$TMPD/fein16/desktop.png" "$SHOTS/glas-milchglas-verlauf.png" 2>/dev/null
VF0=$(python3 tools/themestore/glascheck.py var "$TMPD/fein0/desktop.png" \
      | grep -oE '^var [0-9]+' | cut -d' ' -f2)
VF16=$(python3 tools/themestore/glascheck.py var "$TMPD/fein16/desktop.png" \
       | grep -oE '^var [0-9]+' | cut -d' ' -f2)
echo "        feines Muster: var $VF0 ohne, var $VF16 mit Milchglas 16"
num "feines Muster: die Streuung sinkt unter dem Weichzeichner" \
    "${VF16:-999999}" lt "${VF0:-0}"
VERL=$(python3 - "$TMPD/fein16/desktop.png" "$TMPD/fein0/desktop.png" <<'PYV2'
import sys
sys.path.insert(0, 'tools/themestore')
from PIL import Image
import glascheck as G
for p in sys.argv[1:3]:
    im = Image.open(p).convert('RGB')
    w, h = im.size
    y = h - 28 + 14                      # die Mitte des Leistenstreifens
    zeile = [G.hell(im.getpixel((x, y))) for x in range(300, 1100)]
    stufen = len(set(zeile))
    # WIE LANG DER VERLAUF IST: das laengste Stueck der Zeile, auf dem
    # sich die Helligkeit von Bildpunkt zu Bildpunkt um hoechstens acht
    # Stufen aendert (also kein harter Rand) und ueber das Ganze um
    # mindestens zehn (also nicht einfach eine flache Flaeche). Eine
    # Kachel mit weicher Naht hat kein solches Stueck: innen ist sie
    # flach, aussen springt sie.
    lang = 0
    i = 0
    for j in range(1, len(zeile) + 1):
        if j < len(zeile) and abs(zeile[j] - zeile[j - 1]) > 8:
            seg = zeile[i:j]
            if seg and max(seg) - min(seg) >= 10:
                lang = max(lang, j - i)
            i = j
    seg = zeile[i:]
    if seg and max(seg) - min(seg) >= 10:
        lang = max(lang, len(seg))
    print("%d %d" % (stufen, lang))
PYV2
)
echo "        Leistenzeile (Vollbild): mit/ohne Milchglas -> $(printf '%s' "$VERL" | tr '\n' '|')"
VSTUF=$(printf '%s\n' "$VERL" | sed -n 1p | cut -d' ' -f1)
VWEG=$(printf '%s\n' "$VERL" | sed -n 1p | cut -d' ' -f2)
VSTUF0=$(printf '%s\n' "$VERL" | sed -n 2p | cut -d' ' -f1)
num "quer ueber den Leistenstreifen stehen im VOLLBILD so viele Helligkeitsstufen" \
    "${VSTUF:-0}" ge 20
num "und der Verlauf laeuft ueber so viele Bildpunkte ohne harte Kante" \
    "${VWEG:-0}" ge 60
num "GEGENPROBE: ohne Weichzeichner sind es die zwei Stufen des Musters" \
    "${VSTUF0:-99}" le 3
VWEG0=$(printf '%s\n' "$VERL" | sed -n 2p | cut -d' ' -f2)
num "und ohne ihn gibt es kein einziges Stueck Verlauf" "${VWEG0:-99}" eq 0
FFG=$(grep -a 'taskbar: text clock ' "$TMPD/fein16/serial.txt" | tail -1 \
      | grep -oE 'fg=[0-9]+' | cut -d= -f2)
FK=$(python3 tools/themestore/glascheck.py kontrast \
     "$TMPD/fein16/desktop.png" "$(printf '%06x' "${FFG:-0}")")
echo "        $FK"
num "die Leistenschrift haelt auf dem Verlauf ihre 4,5:1 (x100)" \
    "$(printf '%s' "$FK" | grep -oE '^kontrast [0-9]+' | cut -d' ' -f2)" ge 450
#
mkdir -p "$GSHOTS"
LV=$(python3 tools/themestore/leistenvergleich.py \
     "$GSHOTS/12-leiste-vergleich-ausschnitt-2x.png" \
     "$SHOTS/glas-alpha-100.png=Taskleiste 100 % deckend" \
     "$SHOTS/glas-alpha-70.png=Taskleiste 70 %" \
     "$SHOTS/glas-alpha-40.png=Taskleiste 40 %" \
     "$SHOTS/glas-milchglas.png=Milchglas (blur=12, 70 %)" \
     "$TMPD/grob0/desktop.png=dunkles Schema, 40 %, grobes Muster, ohne Milchglas" \
     "$SHOTS/glas-milchglas-grob.png=dunkles Schema, 40 %, grobes Muster, Milchglas 16" 2>&1)
echo "        $LV"
num "der beschriftete Leistenvergleich (Bild 12) ist aus sechs Aufnahmen gebaut" \
    "$(printf '%s' "$LV" | grep -oE 'aus [0-9]+ Aufnahmen' | grep -oE '[0-9]+')" \
    eq 6
LVV=$(python3 - "$SHOTS/glas-alpha-100.png" "$SHOTS/glas-alpha-70.png" \
      "$SHOTS/glas-alpha-40.png" "$SHOTS/glas-milchglas.png" \
      "$TMPD/grob0/desktop.png" "$SHOTS/glas-milchglas-grob.png" <<'PYV'
import sys
sys.path.insert(0, 'tools/themestore')
from PIL import Image
import leistenvergleich as L
for p in sys.argv[1:]:
    var, farben = L.var_von(Image.open(p).convert('RGB'), 28, 300, 1100)
    print(var)
PYV
)
LVW=$(printf '%s\n' "$LVV" | tr '\n' ' ')
echo "        var im Bild 12: $LVW"
same "und die erste Zahl im Bild ist die gemessene Streuung bei 100 %" \
    "${V100:-x}" "$(printf '%s\n' "$LVV" | sed -n 1p)"
same "und die zweite die bei 70 %" \
    "${V70:-x}" "$(printf '%s\n' "$LVV" | sed -n 2p)"
same "und die dritte die bei 40 %" \
    "${V40:-x}" "$(printf '%s\n' "$LVV" | sed -n 3p)"
same "und die vierte die des Milchglases" \
    "${VB:-x}" "$(printf '%s\n' "$LVV" | sed -n 4p)"
same "und die fuenfte die des groben Musters ohne Milchglas" \
    "${VG0:-x}" "$(printf '%s\n' "$LVV" | sed -n 5p)"
same "und die sechste die desselben Musters mit Milchglas 16" \
    "${VG16:-x}" "$(printf '%s\n' "$LVV" | sed -n 6p)"
#
for paar in "glas-alpha-100:04-taskleiste-100-deckend" \
            "glas-alpha-70:05-taskleiste-70-prozent" \
            "glas-alpha-40:06-taskleiste-40-prozent" \
            "glas-milchglas-verlauf:23-milchglas-verlauf-feines-muster"; do
    cp "$SHOTS/${paar%%:*}.png" "$GSHOTS/${paar##*:}.png" 2>/dev/null
done
GFEHLT=0
for b in 04-taskleiste-100-deckend 05-taskleiste-70-prozent \
         06-taskleiste-40-prozent 23-milchglas-verlauf-feines-muster; do
    [ -s "$GSHOTS/$b.png" ] || GFEHLT=$((GFEHLT+1))
done
num "die vier Aufnahmen 04 bis 06 und 23 der Mappe stammen aus DIESEM Lauf" \
    "$GFEHLT" eq 0
GL=$(grep -a 'wm: glas r=' "$TMPD/blur/serial.txt" | tail -1)
BUS=$(printf '%s' "$GL" | grep -oE ' max=[0-9]+' | grep -oE '[0-9]+')
BPX=$(printf '%s' "$GL" | grep -oE ' px=[0-9]+' | grep -oE '[0-9]+')
echo "        Weichzeichner: $GL"
num "der Weichzeichner meldet seine Zeit je Vollbild (Mikrosekunden, QEMU/TCG)" \
    "${BUS:-0}" gt 0
num "und sie bleibt unter einer Drittelsekunde (QEMU/TCG, ohne KVM)" \
    "${BUS:-999999999}" lt 300000
num "und er hat wirklich Bildpunkte angefasst" "${BPX:-0}" ge 10000
GLC=$(printf '%s' "$GL" | grep -oE 'cache=[0-9]+/[0-9]+' | cut -d= -f2)
# The cache can only be measured when the run got far enough to need the strip
# twice. Under QEMU/TCG on a loaded host the whole run composes the bar ONCE
# (the comment above: "one blit of the bar in twenty seconds") and the only
# report line is the first strip's, cache=0/1. That is not a cache that does
# not work, it is a run that measured nothing: it is said so and not counted,
# neither as a pass nor as a failure. When the strip WAS needed twice, the
# reuse is asserted as before.
GLN=$(printf '%s' "$GLC" | cut -d/ -f2)
if [ "${GLN:-0}" -ge 2 ]; then
    num "der Streifen wurde mehr als einmal gebraucht (cache $GLC)" "$GLN" ge 2
    num "und dabei wiederverwendet statt neu gerechnet" \
        "$(printf '%s' "$GLC" | cut -d/ -f1)" ge 1
else
    echo "  ----  NICHT GEMESSEN: der Streifen wurde in diesem Lauf nur einmal gebraucht (cache $GLC) -- zu wenige Bilder unter QEMU/TCG"
fi

for b in 16 2; do
    bash tools/themestore/build.sh "$TMPD/wglas$b" extra='einst' \
        scheme=midnight mode=dark winalpha=25 blur="$b" \
        wallpaper=dunkelgrob uitrace=yes keep=yes \
        > "$TMPD/wglas$b.log" 2>&1
done
WR=$(grep -ao 'wlib: win id=[0-9]* x=[0-9]* y=[0-9]* w=[0-9]* h=[0-9]* cx=[0-9]* cy=[0-9]*' \
     "$TMPD/wglas16/serial.txt" \
     | awk '{ w=$0; sub(/.* w=/, "", w); sub(/ .*/, "", w)
              if (w+0 >= best+0) { best=w; line=$0 } } END { print line }')
WGX=$(printf '%s' "$WR" | grep -oE ' cx=[0-9]+' | cut -d= -f2)
WGY=$(printf '%s' "$WR" | grep -oE ' cy=[0-9]+' | cut -d= -f2)
WGW=$(printf '%s' "$WR" | grep -oE ' w=[0-9]+' | cut -d= -f2)
WGH=$(printf '%s' "$WR" | grep -oE ' h=[0-9]+' | cut -d= -f2)
# r381: the window now reaches down under the bar (its last rows show the
# bar, which blurs the same in both runs), so the strip sits 150 px higher,
# where a checkerboard edge crosses the free window body (measured: var
# 5792 vs 6050, 25 vs 19 colours; at the bottom it was 162242 twice).
FY1=$(( ${WGY:-3} + ${WGH:-566} - 150 ))
FY0=$(( FY1 - 18 ))
FX0=$(( ${WGX:-20} + 8 ))
FX1=$(( ${WGX:-20} + ${WGW:-760} - 8 ))
num "das durchsichtige Fenster ist breit genug fuer einen Verlauf" \
    "$(( FX1 - FX0 ))" ge 600
for b in 16 2; do
    eval "VF$b=\$(python3 tools/themestore/glascheck.py var \
        \"\$TMPD/wglas$b/desktop.png\" --x0=$FX0 --x1=$FX1 --y0=$FY0 \
        --y1=$FY1 | grep -oE '^var [0-9]+' | cut -d' ' -f2)"
    eval "FF$b=\$(python3 tools/themestore/glascheck.py var \
        \"\$TMPD/wglas$b/desktop.png\" --x0=$FX0 --x1=$FX1 --y0=$FY0 \
        --y1=$FY1 | grep -oE 'farben [0-9]+' | cut -d' ' -f2)"
done
echo "        Fensterausschnitt ($FX0..$FX1, $FY0..$FY1):" \
     "var $VF16 ($FF16 Farben) mit Milchglas 16," \
     "var $VF2 ($FF2 Farben) mit 2"
num "unter dem durchsichtigen Fenster SINKT die Streuung mit dem Radius" \
    "${VF16:-999999}" lt "${VF2:-0}"
num "und aus der Kante des Musters ist ein Verlauf mit vielen Stufen geworden" \
    "${FF16:-0}" ge 12
num "GEGENPROBE: mit Radius 2 sind es deutlich weniger Stufen" \
    "${FF2:-99}" lt "${FF16:-0}"
WGPX=$(grep -aoE 'wm: glas r=16 px=[0-9]+' "$TMPD/wglas16/serial.txt" \
       | grep -oE 'px=[0-9]+' | cut -d= -f2 | sort -n | tail -1)
num "der Weichzeichner hat die FLAECHE eines Fensters bearbeitet (Bildpunkte)" \
    "${WGPX:-0}" ge 100000
cp "$TMPD/wglas16/desktop.png" "$SHOTS/glas-milchglas-fenster.png" 2>/dev/null
mkdir -p "$GSHOTS"
cp "$TMPD/wglas16/desktop.png" \
   "$GSHOTS/07-milchglas-unter-durchsichtigem-fenster.png" 2>/dev/null
WGO=$(python3 tools/themestore/shotcheck.py "$TMPD/wglas16/desktop.ppm" \
      "$TMPD/wglas16/serial.txt" 2>&1 | head -1)
echo "        Bild 07: $WGO"
for feld in empty cut overlapping; do
    num "Bild 07 (Milchglas unterm Fenster): $feld" \
        "$(printf '%s' "$WGO" | grep -oE "$feld [0-9]+" | grep -oE '[0-9]+')" eq 0
done

bash tools/themestore/build.sh "$TMPD/dunkel" tbalpha=40 blur=0 \
    wallpaper=dunkel uitrace=yes keep=yes > "$TMPD/dunkel.log" 2>&1
for pair in "al40:hell" "dunkel:dunkel"; do
    d=${pair%%:*}; nm=${pair##*:}
    FG=$(grep -a 'taskbar: text clock ' "$TMPD/$d/serial.txt" | tail -1 \
         | grep -oE 'fg=[0-9]+' | cut -d= -f2)
    FGH=$(printf '%06x' "${FG:-0}")
    #
    FELDER=$(grep -aE 'taskbar: text (start|clock) ' "$TMPD/$d/serial.txt" \
        | sed -nE 's/.* x=([0-9]+) base=([0-9]+) fg=([0-9]+) .* tw=([0-9]+) .*/\1,\2,\4,\3/p' \
        | sort -u \
        | while IFS=, read -r fx fb ft ff; do printf '%s,%s,%s,%06x;' \
            "$fx" "$fb" "$ft" "$ff"; done)
    ASC=$(grep -a 'taskbar: ready ascent=' "$TMPD/$d/serial.txt" | tail -1 \
        | grep -oE 'ascent=[0-9]+' | cut -d= -f2)
    KZ=$(python3 tools/themestore/glascheck.py kontrast \
         "$TMPD/$d/desktop.png" "$FGH" \
         --felder="$FELDER" --ascent="${ASC:-12}")
    echo "        $nm: $KZ"
    K=$(printf '%s' "$KZ" | grep -oE '^kontrast [0-9]+' | cut -d' ' -f2)
    num "Leistenschrift gegen den SCHLECHTESTEN gemischten Grund ($nm, 40 %%), x100" \
        "${K:-0}" ge 450
    KK=$(printf '%s' "$KZ" | grep -oE 'anteil=[0-9]+' | cut -d= -f2)
    num "und die Schrift stand wirklich auf ihrer Platte ($nm, Anteil %%)" \
        "${KK:-0}" ge 40
done
#
bash tools/themestore/build.sh "$TMPD/dunkelmod" scheme=midnight mode=dark \
    tbalpha=40 blur=0 wallpaper=dunkel uitrace=yes keep=yes \
    > "$TMPD/dunkelmod.log" 2>&1
cp "$TMPD/dunkelmod/desktop.png" "$SHOTS/glas-dunkel-40.png" 2>/dev/null
DV=$(python3 tools/themestore/glascheck.py var "$SHOTS/glas-dunkel-40.png")
DA=$(grep -a 'wm: glas alpha_soll=' "$TMPD/dunkelmod/serial.txt" | tail -1)
echo "        dunkles Schema auf dunklem Bild: $DV"
echo "        $DA"
num "bei 40 %% ueber dem dunklen Bild traegt der Leistengrund das Muster (Farben)" \
    "$(printf '%s' "$DV" | grep -oE 'farben [0-9]+' | cut -d' ' -f2)" ge 2
num "und er streut wirklich (die deckende Leiste streut 0)" \
    "$(printf '%s' "$DV" | grep -oE '^var [0-9]+' | cut -d' ' -f2)" ge 100
DSOLL=$(printf '%s' "$DA" | grep -oE 'alpha_soll=[0-9]+' | cut -d= -f2)
DIST=$(printf '%s' "$DA" | grep -oE 'alpha_ist=[0-9]+' | cut -d= -f2)
num "der Regler sagt 40, und der Server malt hier fast dasselbe" \
    "$(( ${DIST:-99} - ${DSOLL:-0} ))" le 10
DFG=$(grep -a 'taskbar: text clock ' "$TMPD/dunkelmod/serial.txt" | tail -1 \
      | grep -oE 'fg=[0-9]+' | cut -d= -f2)
DK=$(python3 tools/themestore/glascheck.py kontrast \
     "$SHOTS/glas-dunkel-40.png" "$(printf '%06x' "${DFG:-0}")")
echo "        $DK"
num "und die Leistenschrift haelt dabei ihre 4,5:1 (x100)" \
    "$(printf '%s' "$DK" | grep -oE '^kontrast [0-9]+' | cut -d' ' -f2)" ge 450
HA=$(grep -a 'wm: glas alpha_soll=' "$TMPD/dunkel/serial.txt" | tail -1)
echo "        GEGENPROBE, helle Leiste auf demselben Bild: $HA"
num "GEGENPROBE: dort hebt der Schleier die Deckkraft ueber die Reglerstellung" \
    "$(printf '%s' "$HA" | grep -oE 'alpha_ist=[0-9]+' | cut -d= -f2)" gt \
    "$(printf '%s' "$HA" | grep -oE 'alpha_soll=[0-9]+' | cut -d= -f2)"
SGL=$(grep -a 'settings: glas ' "$SE" | tail -1)
echo "        $SGL"
num "die Einstellungsseite fuehrt das WIRKSAME Alpha neben dem Regler" \
    "$(printf '%s' "$SGL" | grep -oE 'ist=[0-9]+' | cut -d= -f2)" ge \
    "$(printf '%s' "$SGL" | grep -oE 'tba=[0-9]+' | cut -d= -f2)"

python3 - "$TMPD/dunkel2.osym" <<'WALL2'
import struct, sys
# Ein ZWEITES dunkles Muster, und absichtlich anders gebaut als das
# von build.sh: senkrechte Streifen von acht Bildpunkten statt eines
# Schachbretts von zwoelf, und zwei Farben, die nicht in dieselbe
# Richtung von Weiss weg liegen (ein tiefes Blaugruen und ein sehr
# dunkles Rot). Dasselbe Muster zweimal zu messen ist eine Messung,
# nicht zwei.
w, h = 120, 90
a, b = (0x08, 0x2A, 0x24), (0x2E, 0x0A, 0x12)
px = bytearray()
for y in range(h):
    for x in range(w):
        c = a if (x // 8) % 2 == 0 else b
        px += bytes((c[2], c[1], c[0], 0xFF))
open(sys.argv[1], "wb").write(b"OSYM" + struct.pack("<II", w, h) + bytes(px))
WALL2
bash tools/themestore/build.sh "$TMPD/dblur" tbalpha=40 blur=12 \
    wallpaper=dunkel uitrace=yes keep=yes > "$TMPD/dblur.log" 2>&1
bash tools/themestore/build.sh "$TMPD/dunkel2" tbalpha=40 blur=0 \
    wallpaper="$TMPD/dunkel2.osym" uitrace=yes keep=yes \
    > "$TMPD/dunkel2.log" 2>&1
for pair in "dblur:dunkel mit Milchglas 12" "dunkel2:zweites dunkles Muster"; do
    d=${pair%%:*}; nm=${pair##*:}
    FG=$(grep -a 'taskbar: text clock ' "$TMPD/$d/serial.txt" | tail -1 \
         | grep -oE 'fg=[0-9]+' | cut -d= -f2)
    FGH=$(printf '%06x' "${FG:-0}")
    FELDER=$(grep -aE 'taskbar: text (start|clock) ' "$TMPD/$d/serial.txt" \
        | sed -nE 's/.* x=([0-9]+) base=([0-9]+) fg=([0-9]+) .* tw=([0-9]+) .*/\1,\2,\4,\3/p' \
        | sort -u \
        | while IFS=, read -r fx fb ft ff; do printf '%s,%s,%s,%06x;' \
            "$fx" "$fb" "$ft" "$ff"; done)
    ASC=$(grep -a 'taskbar: ready ascent=' "$TMPD/$d/serial.txt" | tail -1 \
        | grep -oE 'ascent=[0-9]+' | cut -d= -f2)
    KZ=$(python3 tools/themestore/glascheck.py kontrast \
         "$TMPD/$d/desktop.png" "$FGH" \
         --felder="$FELDER" --ascent="${ASC:-12}")
    echo "        $nm: $KZ"
    num "Leistenschrift gegen den SCHLECHTESTEN Grund ($nm), x100" \
        "$(printf '%s' "$KZ" | grep -oE '^kontrast [0-9]+' | cut -d' ' -f2)" \
        ge 450
done
for d in dunkel dblur dunkel2; do
    AL=$(grep -a 'wm: glas alpha_soll=' "$TMPD/$d/serial.txt" | tail -1)
    SOLL=$(printf '%s' "$AL" | grep -oE 'alpha_soll=[0-9]+' | cut -d= -f2)
    IST=$(printf '%s' "$AL" | grep -oE 'alpha_ist=[0-9]+' | cut -d= -f2)
    VZ=$(python3 tools/themestore/glascheck.py var "$TMPD/$d/desktop.png")
    FAB=$(printf '%s' "$VZ" | grep -oE 'farben [0-9]+' | cut -d' ' -f2)
    VAR=$(printf '%s' "$VZ" | grep -oE '^var [0-9]+' | cut -d' ' -f2)
    echo "        $d: soll=${SOLL:-?} ist=${IST:-?} $VZ"
    same "$d: der Lauf meldet die Reglerstellung, die er bekommen hat" \
        "40" "${SOLL:-}"
    #
    if [ "${VAR:-0}" -gt 100 ] 2>/dev/null; then
        ok "$d: das Bild scheint unter der Leiste durch (var $VAR, $FAB Gruende)"
    else
        num "$d: die Leiste ist praktisch deckend, also ist die Anhebung gemeldet" \
            "${IST:-0}" gt "${SOLL:-100}"
    fi
    num "$d: und sie ist nie kleiner als die Reglerstellung" \
        "${IST:-0}" ge "${SOLL:-100}"
done
bash tools/themestore/build.sh "$TMPD/dunkelsett" extra='einst' tbalpha=40 \
    blur=0 wallpaper=dunkel uitrace=yes keep=yes > "$TMPD/dunkelsett.log" 2>&1
#
PAAR=$(python3 - "$TMPD/dunkelsett/serial.txt" <<'PY'
import re, sys
txt = open(sys.argv[1], 'rb').read().decode('latin1').splitlines()
seite = [(i, int(m.group(1))) for i, z in enumerate(txt)
         for m in [re.search(r'settings: glas .* ist=(\d+)', z)] if m]
server = [(i, int(m.group(1))) for i, z in enumerate(txt)
          for m in [re.search(r'wm: glas alpha_soll=\d+ alpha_ist=(\d+)', z)]
          if m]
if not seite or not server:
    print("0 0")
    raise SystemExit
i, s = seite[-1]
j, w = min(server, key=lambda p: abs(p[0] - i))
print("%d %d" % (s, w))
PY
)
SIST=${PAAR%% *}
WIST=${PAAR##* }
SABW=$(( ${SIST:-0} - ${WIST:-0} ))
[ "$SABW" -lt 0 ] && SABW=$(( -SABW ))
echo "        Seite: ${SIST:-?} %, Server: ${WIST:-?} % (benachbarte Meldungen)"
#
num "die Seite Darstellung nennt dasselbe wirksame Alpha wie der Server" \
    "$SABW" le 12
num "und es ist wirklich angehoben (Regler 40)" "${SIST:-0}" gt 40
cp "$TMPD/dunkelsett/desktop.png" "$SHOTS/glas-dunkel-alpha-40.png" 2>/dev/null

RR=$(grep -ac '^fn fill_round(' kernel/ui/wm/wmdraw.fi)
BL=$(grep -ac '^fn blend(' kernel/ui/wm/wmdraw.fi)
num "genau eine Stelle im Fensterserver malt ein rundes Rechteck" "$RR" eq 1
num "und genau eine mischt" "$BL" eq 1
GM=$(grep -ac '^fn glass_mix(' kernel/ui/wm/wmglass.fi)
num "und genau eine entscheidet, wie deckend ein Punkt ist" "$GM" eq 1
#
PM0=$(grep -aoE '^const PLATE_MARK: u64 = 0x[0-9A-Fa-f]+' kernel/ui/wm/wmglass.fi \
      | grep -oE '0x[0-9A-Fa-f]+')
PM3=$(grep -aoE '^const PLATTE: u64 = 0x[0-9A-Fa-f]+' kernel/user/wlibc.fi \
      | grep -oE '0x[0-9A-Fa-f]+')
same "die Marke der Textplatte ist in Ring 0 und Ring 3 dieselbe Zahl" \
    "${PM0:-0}" "${PM3:-1}"
num "und genau eine Stelle in Ring 3 setzt sie" \
    "$(grep -ac '^fn platte(' kernel/user/wlibc.fi)" eq 1
num "und genau eine in Ring 0 loest sie auf" \
    "$({ grep -ac '== (PLATE_MARK >> 24)' kernel/ui/wm/wmglass.fi || true; })" eq 1
#
CC=$(grep -rac '^fn corner_cov(' --include=*.fi kernel/ lib/ module/ pkg/ \
     2>/dev/null | awk -F: '{ n += $2 } END { print n+0 }')
num "der Eckenabtaster steht GENAU EINMAL im Baum (ausser vendor/)" "$CC" eq 1
same "und zwar in lib/ecke.fi, wo beide Ringe ihn uebersetzen" "lib/ecke.fi" \
    "$(grep -rla '^fn corner_cov(' --include=*.fi kernel/ lib/ module/ pkg/ \
       2>/dev/null | head -1)"
#
mkdir -p "$TMPD/gegen/lib"
printf 'fn corner_cov(dx: u64) -> u64 {\n    return 0\n}\n' \
    > "$TMPD/gegen/lib/.zweiter-abtaster-probe.fi"
CC2=$(grep -rac '^fn corner_cov(' --include=*.fi kernel/ lib/ module/ pkg/ \
      "$TMPD/gegen/lib/" \
      2>/dev/null | awk -F: '{ n += $2 } END { print n+0 }')
num "GEGENPROBE: ein zweiter Abtaster im Baum wird gefunden" "$CC2" eq 2
#
LISTE=tools/themestore/raster.liste
#
RASTERPAT='^fn [a-z_0-9]*(round|blend|mix8|rrect|rund|ecke|deckung|misch'
RASTERPAT="$RASTERPAT|mix|fill_a|fill_clip|fill_round|ring_round)[a-z_0-9]*\\("
grep -rEona "$RASTERPAT" kernel/ \
    --include=*.fi | sed 's/:[0-9]*:fn / /' | sed 's/($//' | sort -u \
    > "$TMPD/raster.gefunden"
grep -avE '^\s*(#|$)' "$LISTE" | awk '{ print $1, $2 }' | sort -u \
    > "$TMPD/raster.erlaubt"
RFEHLT=$(comm -23 "$TMPD/raster.gefunden" "$TMPD/raster.erlaubt" | wc -l)
RALT=$(comm -13 "$TMPD/raster.gefunden" "$TMPD/raster.erlaubt" | wc -l)
comm -3 "$TMPD/raster.gefunden" "$TMPD/raster.erlaubt" | sed 's/^/        /'
num "jeder Rasterer und Mischer im BAUM steht in $LISTE mit Begruendung" \
    "$RFEHLT" eq 0
num "und kein Eintrag der Liste ist verwaist" "$RALT" eq 0
num "es sind wirklich Funde gemessen worden" \
    "$(grep -c . "$TMPD/raster.gefunden")" ge 60
#
mkdir -p "$TMPD/gegen"
printf 'fn zweimischer(a: u64, b: u64) -> u64 {\n    return (a + b) / 2\n}\n' \
    > "$TMPD/gegen/zweimischer-probe.fi"
{ grep -rEona "$RASTERPAT" kernel/ --include=*.fi
  grep -Eona "$RASTERPAT" < "$TMPD/gegen/zweimischer-probe.fi" \
      | sed 's|^|kernel/user/.zweimischer-probe.fi:|'
} | sed 's/:[0-9]*:fn / /' | sed 's/($//' | sort -u \
    > "$TMPD/raster.gegenprobe"
RGEG=$(comm -23 "$TMPD/raster.gegenprobe" "$TMPD/raster.erlaubt" | wc -l)
num "GEGENPROBE: eine untergeschobene 'fn zweimischer(' faellt auf" \
    "$RGEG" eq 1
RKURZ=$(grep -avE '^\s*(#|$)' "$LISTE" | awk 'NF < 8 { n++ } END { print n+0 }')
num "und jeder Eintrag begruendet sich in einem ganzen Satz" "$RKURZ" eq 0
SELF=$(grep -a 'wm: glastest ' "$TMPD/blur/serial.txt" | tail -1)
SN=$(printf '%s' "$SELF" | grep -oE 'glastest [0-9]+' | grep -oE '[0-9]+')
SM=$(printf '%s' "$SELF" | grep -oE '/ [0-9]+' | grep -oE '[0-9]+')
same "der Selbsttest der Mischung und des Weichzeichners laeuft durch" \
    "${SM:-7}" "${SN:-0}"

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

bash tools/themestore/build.sh "$TMPD/zug1" extra='einst' tbalpha=70 blur=0 \
    wallpaper=hell uitrace=yes keep=yes click="400,10>400,210" \
    > "$TMPD/zug1.log" 2>&1
num "ein Griff in die Titelleiste ZIEHT das Fenster (Zahl der Groessenaenderungen)" \
    "$({ grep -ac 'wm: zieh ' "$TMPD/zug1/serial.txt" || true; })" eq 0
ZW=$(grep -ao 'wlib: win id=[0-9]* x=[0-9]* y=[0-9]* w=[0-9]* h=[0-9]*' \
     "$TMPD/zug1/serial.txt" \
     | awk '{ w=$0; sub(/.* w=/, "", w); sub(/ .*/, "", w)
              if (w+0 < 1200 && w+0 >= best+0) { best=w; line=$0 } } END { print line }')
# r381: the task bar is a `wlib` window now (scene window 0) and reports itself, 1280 wide:
# the widest window is the bar. Windows as wide as the screen are not the one that is dragged.
ZWY=$(printf '%s' "$ZW" | grep -oE ' y=[0-9]+' | grep -oE '[0-9]+')
ZWH=$(printf '%s' "$ZW" | grep -oE ' h=[0-9]+' | grep -oE '[0-9]+')
ZWW=$(printf '%s' "$ZW" | grep -oE ' w=[0-9]+' | grep -oE '[0-9]+')
num "und es steht danach woanders als vorher (y)" "${ZWY:-3}" gt 100
LEIY=$(grep -a 'taskbar: STEHT ' "$TMPD/zug1/serial.txt" | tail -1 \
       | grep -oE 'y=[0-9]+' | cut -d= -f2)
#
VORY=$(grep -a 'wm: geklemmt ' "$TMPD/zug1/serial.txt" | tail -1 \
       | grep -oE 'vory=[0-9]+' | cut -d= -f2)
LEIH=$(grep -a 'taskbar: geom ' "$TMPD/zug1/serial.txt" | tail -1 \
       | grep -oE ' h=[0-9]+' | grep -oE '[0-9]+')
OVH=$(( ${VORY:-${ZWY:-3}} + ${ZWH:-0} + 24 - ${LEIY:-772} ))
[ "$OVH" -gt "${LEIH:-28}" ] && OVH=${LEIH:-28}
UEB=$(( OVH * ${ZWW:-0} ))
[ "$UEB" -lt 0 ] && UEB=0
echo "        Fenster ${ZWW:-?}x${ZWH:-?} bei y=${ZWY:-?} (vor dem Klemmen y=${VORY:-${ZWY:-?}}), Leiste ab y=${LEIY:-?}"
num "das Fenster reicht wirklich unter die Leiste (Bildpunkte Ueberlappung)" \
    "$UEB" ge 1000
#
UPX=$(grep -a 'wm: schlieren ' "$TMPD/zug1/serial.txt" | tail -1 \
      | grep -oE 'unterpx=[0-9]+' | cut -d= -f2)
echo "        Wirt: $UEB Bildpunkte, Server: ${UPX:-0}"
num "der Server hat dieselbe Schnittflaeche gesehen" "${UPX:-0}" ge 1000
ABW=$(( ${UPX:-0} - UEB ))
[ "$ABW" -lt 0 ] && ABW=$(( -ABW ))
num "und beide Rechnungen weichen um weniger als ein Zehntel ab" \
    "$(( ABW * 10 ))" lt "$UEB"
num "GEGENPROBE: ohne Zug steht kein Fenster unter der Leiste" \
    "$(grep -a 'wm: schlieren ' "$TMPD/ruhe/serial.txt" | tail -1 \
       | grep -oE 'unterpx=[0-9]+' | cut -d= -f2)" eq 0
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
#
mkdir -p "$GSHOTS"
cp "$TMPD/zug/desktop.png" \
   "$GSHOTS/10-zug-hin-und-zurueck-keine-schlieren.png" 2>/dev/null
cp "$TMPD/zug1/desktop.png" \
   "$GSHOTS/19-zug-unter-die-leiste-neu.png" 2>/dev/null
[ -s "$GSHOTS/19-zug-unter-die-leiste-neu.png" ] \
    && ok "und der Zug ohne Rueckweg als eigene Aufnahme (19)" \
    || bad "die Aufnahme des Zuges ohne Rueckweg fehlt"

# ---- 11f3. (fix-r4-2, CHANGED 04.10.2026 for the Dell) THE END POSITION
#            KEEPS A HANDLE -- THE WINDOW MAY STICK OUT.
#
# Until 04.10.2026 `wm.drag_klemmen` put the WHOLE window back on the work
# area when the button went up (fix-r4-2: picture 15 showed a window whose
# body hung below the screen). Justin, Dell: "a window pushed a little over
# the edge jumps back at once" -- he wants it the way Windows and Linux do
# it. Since then the window may stick out left, right and below; what is
# kept is a handle: the title bar stays on the work area (above the bar),
# and at least 96 px stay in sight sideways (tools/fourbugs/run.sh measures
# the rule itself, with a counter-proof). So what is asked here changed with
# it: the title bar of the end position lies above the bar, the server says
# where the window ended (`wm: abgelegt`), and the labels that ARE on the
# screen are neither empty nor overlapping. "The slider block is fully
# visible" is no longer a promise of the window server.
#
echo
echo "== 11f3. die Endlage behaelt einen Griff (das Fenster darf ueberstehen) =="
bash tools/themestore/build.sh "$TMPD/zug2" extra='einst' tbalpha=70 blur=0 \
    wallpaper=hell uitrace=yes keep=yes click="400,10>600,600" \
    > "$TMPD/zug2.log" 2>&1
cp "$TMPD/zug2/desktop.png" \
   "$GSHOTS/22-zug-endlage-unter-der-leiste.png" 2>/dev/null
[ -s "$GSHOTS/22-zug-endlage-unter-der-leiste.png" ] \
    && ok "und die Endlage des weiten Zuges als eigene Aufnahme (22)" \
    || bad "die Aufnahme der Endlage unter der Leiste fehlt"
for z in zug1 zug2; do
    GA=$(grep -a 'wm: abgelegt ' "$TMPD/$z/serial.txt" | tail -1)
    echo "        $z: ${GA:-KEINE Endlage gemeldet}"
    KY=$(printf '%s' "$GA" | grep -oE ' y=[0-9]+' | grep -oE '[0-9]+')
    LY=$(grep -a 'taskbar: STEHT ' "$TMPD/$z/serial.txt" | tail -1 \
         | grep -oE 'y=[0-9]+' | cut -d= -f2)
    num "$z: der Server hat die Endlage gemeldet" "$(printf '%s' "$GA" | grep -c abgelegt)" eq 1
    num "$z: die Titelleiste liegt ueber der Leiste (Griff bleibt)" \
        "$(( ${KY:-9999} + 24 ))" le "${LY:-772}"
    SOUT=$(python3 tools/themestore/shotcheck.py "$TMPD/$z/desktop.ppm" \
           "$TMPD/$z/serial.txt" 2>&1 | head -1)
    echo "        $SOUT"
    for f in empty overlapping; do
        num "$z: $f" \
            "$(printf '%s' "$SOUT" | grep -oE "$f [0-9]+" | head -1 \
               | cut -d' ' -f2)" eq 0
    done
done

bash tools/themestore/build.sh "$TMPD/rvor" extra='einst' uitrace=yes \
    keep=yes radius=4 > "$TMPD/rvor.log" 2>&1
TABL=$(grep -a 'wlib: tab i=21 ' "$TMPD/rvor/serial.txt" | tail -1)
TABX=$(printf '%s' "$TABL" | grep -oE ' ax=[0-9]+' | grep -oE '[0-9]+')
TABY=$(printf '%s' "$TABL" | grep -oE ' ay=[0-9]+' | grep -oE '[0-9]+')
TABW=$(printf '%s' "$TABL" | grep -oE ' w=[0-9]+' | grep -oE '[0-9]+')
TABH=$(printf '%s' "$TABL" | grep -oE ' h=[0-9]+' | grep -oE '[0-9]+')
TCX=$(( ${TABX:-30} + ${TABW:-232} / 2 ))
TCY=$(( ${TABY:-191} + ${TABH:-30} / 2 ))
bash tools/themestore/build.sh "$TMPD/rtab" extra='einst' uitrace=yes \
    keep=yes radius=4 click="$TCX,$TCY" click="$TCX,$TCY" \
    > "$TMPD/rtab.log" 2>&1
SL=$(grep -ao 'settings: rect name=[a-z]* x=[0-9]* y=[0-9]* w=160 h=[0-9]*' \
     "$TMPD/rtab/serial.txt" | tail -2 | head -1)
SLX=$(printf '%s' "$SL" | grep -oE ' x=[0-9]+' | grep -oE '[0-9]+')
SLY=$(printf '%s' "$SL" | grep -oE ' y=[0-9]+' | grep -oE '[0-9]+')
SLW=$(printf '%s' "$SL" | grep -oE ' w=[0-9]+' | grep -oE '[0-9]+')
CX=$(( ${SLX:-747} + 22 + (${SLW:-160} * 2 / 3) ))
SLH=$(printf '%s' "$SL" | grep -oE ' h=[0-9]+' | grep -oE '[0-9]+')
CY=$(( ${SLY:-202} + 25 + ${SLH:-20} / 2 ))
bash tools/themestore/build.sh "$TMPD/rklick" extra='einst' uitrace=yes \
    keep=yes radius=4 click="$TCX,$TCY" click="$TCX,$TCY" click="$CX,$CY" click="$CX,$CY" \
    > "$TMPD/rklick.log" 2>&1
RNEU=$(grep -a 'settings: glas radius=' "$TMPD/rklick/serial.txt" | tail -1 \
       | grep -oE 'radius=[0-9]+' | cut -d= -f2)
num "ein Klick auf den Regler aendert die laufende Eckenrundung (von 4)" \
    "${RNEU:-4}" gt 4
RDAT=$(python3 tools/osum/mkfs.py cat "$TMPD/rklick/disk.img" /etc/theme.conf \
       2>/dev/null | grep -aE '^radius=' | tail -1 | cut -d= -f2)
same "und dieselbe Zahl steht danach in /etc/theme.conf auf der Platte" \
    "${RNEU:-4}" "${RDAT:-}"
RVOR=$(grep -a 'settings: glas radius=' "$TMPD/rvor/serial.txt" | tail -1 \
       | grep -oE 'radius=[0-9]+' | cut -d= -f2)
same "GEGENPROBE: ohne Klick bleibt die Eckenrundung, wo sie war" "4" "${RVOR:-}"
same "und die Datei auch" "4" \
    "$(python3 tools/osum/mkfs.py cat "$TMPD/rvor/disk.img" /etc/theme.conf \
       2>/dev/null | grep -aE '^radius=' | tail -1 | cut -d= -f2)"
num "Schmuck-Widgets sind von der Trefferpruefung ausgenommen" \
    "$(grep -ac 'fn only_decoration(' kernel/user/wlib.fi)" eq 1

GSHOT=0
for s in glas-radius-0 glas-radius-12 glas-radius-24 glas-alpha-100 \
         glas-alpha-70 glas-alpha-40 glas-milchglas \
         glas-milchglas-grob; do
    [ -s "$SHOTS/$s.png" ] && GSHOT=$((GSHOT+1)) || echo "        $s: kein Bild"
done
num "die acht Aufnahmen der Runde GLAS" "$GSHOT" eq 8
GBAD=0
for pair in "rad0:glas-radius-0" "rad12:glas-radius-12" "rad24:glas-radius-24" \
            "al100:glas-alpha-100" "al70:glas-alpha-70" "al40:glas-alpha-40" \
            "blur:glas-milchglas" "grob16:glas-milchglas-grob"; do
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

echo
echo "== 12. Nachtrag: der Umlaut im Terminal und die gemessene Leiste =="

TLOG="$TMPD/al100/serial.txt"
TPPM="$TMPD/al100/desktop.ppm"
has "$TLOG" "wm: termgitter win=" \
    "der Kern nennt das Zellenraster des Terminals (Lage, Zelle, Aufsteiger)"
UM=$(python3 tools/look/umlaut.py "$TLOG" "$TPPM" --gitter=1,1 \
     'KEIN EINZIGES GERÄT!' 2>&1 | head -1)
UF=$(printf '%s' "$UM" | grep -oE '[0-9]+ wrong' | grep -oE '^[0-9]+')
UT=$(printf '%s' "$UM" | grep -oE '[0-9]+ ink pixels' | grep -oE '^[0-9]+')
num "das Ä im Terminal ist bildpunktgenau gerastert (falsche Punkte)" \
    "${UF:-99}" eq 0
num "und es ist ueberhaupt Tinte gemessen worden" "${UT:-0}" ge 500
#
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
BT=$(grep -aE '^taskbar: btn i=0 ' "$TLOG" | tail -1 | sed -E 's/.* t=//')
if [ -n "$BT" ]; then
    ok "der Fensterknopf der Leiste traegt den Fenstertitel: $BT"
else
    bad "der Fensterknopf der Leiste ist titellos (nur Symbol)"
fi

echo
echo "== 11h. keine Beschriftung steht auf einer Rahmenlinie =="
for pair in "set:Darstellung" "setv:Vorlagen"; do
    d=${pair%%:*}; nm=${pair##*:}
    LO=$(python3 tools/themestore/shotcheck.py "$TMPD/$d/desktop.ppm" \
         "$TMPD/$d/serial.txt" --linien 2>&1)
    LN=$(printf '%s' "$LO" | grep -oE 'linie [0-9]+' | grep -oE '[0-9]+')
    num "Seite $nm: Beschriftungen auf einer Rahmenlinie" "${LN:-99}" eq 0
    [ "${LN:-99}" = 0 ] || printf '%s\n' "$LO" | grep -a LINIE \
        | sed 's/^/        /'
done
python3 - "$TMPD/set/desktop.ppm" "$TMPD/set/serial.txt" \
         "$TMPD/linie.ppm" <<'PYL'
import sys
sys.path.insert(0, 'tools/themestore')
import shotcheck as S
w, h, d = S.read_ppm(sys.argv[1])
d = bytearray(d)
texts, wins, font = S.parse(sys.argv[2])
# r368: a label with room to its left (the probe wants ten pixels of line on each
# side; the status line "bereit" stands only 8 points from the window's edge)
st = [t for t in texts if t["t"].strip() and t["x"] >= 24][-1]
# r368: a scene window numbers its windows from 0 and the `wlib: win` lines
# carry the window HANDLE, so `wins[st["win"]]` finds nothing; the text itself
# says where its client area is (`ax=`/`ay=`), as `shotcheck.py` does.
if st["win"] in wins:
    win = dict(cx=wins[st["win"]]["cx"], cy=wins[st["win"]]["cy"],
               w=wins[st["win"]]["w"])
else:
    win = dict(cx=st.get("ax") or 0, cy=st.get("ay") or 0, w=w)
y = win["cy"] + st["base"] - 3
for x in range(win["cx"], min(win["cx"] + win["w"], w)):
    o = (y * w + x) * 3
    d[o], d[o + 1], d[o + 2] = 180, 180, 190
open(sys.argv[3], "wb").write(b"P6\n%d %d\n255\n" % (w, h) + bytes(d))
PYL
GL=$(python3 tools/themestore/shotcheck.py "$TMPD/linie.ppm" \
     "$TMPD/set/serial.txt" --linien 2>&1 \
     | grep -oE 'linie [0-9]+' | grep -oE '[0-9]+')
num "GEGENPROBE: eine gemalte Linie durch die Schrift wird gefunden" \
    "${GL:-0}" ge 1

echo
echo "== 11i. der Strich unter dem Leistenknopf folgt der Schrift =="
PI=$(python3 - "$TLOG" <<'PYP'
import re
import sys
txt = open(sys.argv[1], 'rb').read().decode('latin1')
pil = {}
for m in re.finditer(r'taskbar: pille i=(\d+) x=(\d+) w=(\d+)'
                     r' tx=(\d+) tw=(\d+)', txt):
    pil[int(m.group(1))] = tuple(int(g) for g in m.groups()[1:])
txts = {}
for m in re.finditer(r'taskbar: text button x=(\d+) base=\d+ fg=\d+'
                     r' bg=\d+ tw=(\d+) t=', txt):
    txts[int(m.group(1))] = int(m.group(2))
# Der schmale Strich (10 Bildpunkte) sagt "laeuft" und gehoert keinem
# Wort; gemessen wird der BREITE unter dem vorderen Fenster.
breit = [(i, v) for i, v in pil.items() if v[1] != 10]
schlecht = []
for i, (px, pw, tx, tw) in breit:
    if (px, pw) != (tx, tw):
        schlecht.append('%d: Strich %d..%d, Wort %d..%d'
                        % (i, px, px + pw, tx, tx + tw))
    elif tx in txts and txts[tx] != tw:
        schlecht.append('%d: gemeldete Textbreite %d, Strich %d'
                        % (i, txts[tx], tw))
print(len(breit), len(schlecht), ';'.join(schlecht[:3]))
PYP
)
echo "        $PI"
num "Fensterknoepfe mit breitem Strich (der vordere)" \
    "$(printf '%s' "$PI" | cut -d' ' -f1)" ge 1
num "und Striche, die nicht auf der gemessenen Textbreite sitzen" \
    "$(printf '%s' "$PI" | cut -d' ' -f2)" eq 0

echo
echo "== 11j. das durchsichtige Fenster bleibt lesbar =="
bash tools/themestore/build.sh "$TMPD/winal" extra='einst' winalpha=55 \
    wallpaper=hell uitrace=yes keep=yes > "$TMPD/winal.log" 2>&1
WF=$(python3 tools/themestore/glascheck.py fenster \
     "$TMPD/winal/desktop.png" "$TMPD/winal/serial.txt")
printf '%s\n' "$WF" | sed 's/^/        /'
num "jede Fensterbeschriftung haelt 4,5:1 gegen den GEMISCHTEN Grund (x100)" \
    "$(printf '%s' "$WF" | grep -oE 'schlechteste [0-9]+' | cut -d' ' -f2)" \
    ge 450
num "und es waren wirklich Beschriftungen zu messen" \
    "$(printf '%s' "$WF" | grep -oE 'beschriftungen=[0-9]+' | cut -d= -f2)" \
    ge 20
bash tools/themestore/build.sh "$TMPD/winal100" extra='einst' winalpha=100 \
    wallpaper=hell uitrace=yes keep=yes > "$TMPD/winal100.log" 2>&1
WD=$(python3 - "$TMPD/winal/desktop.png" "$TMPD/winal100/desktop.png" <<'PYW'
import sys
from PIL import Image
a = Image.open(sys.argv[1]).convert("RGB")
b = Image.open(sys.argv[2]).convert("RGB")
# Nur die Flaeche des Einstellungsfensters, und nur jede dritte Zeile
# und Spalte: gezaehlt wird, OB sich die Mischung auswirkt, nicht wie
# schnell dieses Skript ist.
n = 0
for y in range(40, 560, 3):
    for x in range(30, 770, 3):
        if a.getpixel((x, y)) != b.getpixel((x, y)):
            n += 1
print(n)
PYW
)
num "GEGENPROBE: bei 55 Prozent ist das Fenster wirklich eine andere Flaeche" \
    "${WD:-0}" ge 2000
#
WR55=$(python3 tools/themestore/glascheck.py reiter \
       "$TMPD/winal/desktop.png" "$TMPD/winal/serial.txt")
WR100=$(python3 tools/themestore/glascheck.py reiter \
        "$TMPD/winal100/desktop.png" "$TMPD/winal100/serial.txt")
echo "        55 %: $WR55"
echo "        100 %: $WR100"
K55=$(printf '%s' "$WR55" | grep -oE 'kanten=[0-9]+' | cut -d= -f2)
K100=$(printf '%s' "$WR100" | grep -oE 'kanten=[0-9]+' | cut -d= -f2)
num "die Reiterzeile des DECKENDEN Laufs hat ueberhaupt Kanten" \
    "${K100:-0}" ge 500
num "und das durchsichtige Fenster hat dort keine einzige mehr" \
    "${K55:-99999}" le "${K100:-0}"
WRD=$(python3 - "$TMPD/winal/desktop.png" "$TMPD/winal100/desktop.png" \
      "$WR55" <<'PYB'
import re, sys
from PIL import Image
a = Image.open(sys.argv[1]).convert("RGB")
b = Image.open(sys.argv[2]).convert("RGB")
m = re.search(r"band=(\d+),(\d+),(\d+),(\d+)", sys.argv[3])
x0, y0, x1, y1 = (int(v) for v in m.groups())
n = sum(1 for y in range(y0, y1) for x in range(x0, x1)
        if a.getpixel((x, y)) != b.getpixel((x, y)))
print(n)
PYB
)
num "und die Reiterzeile ist Bildpunkt fuer Bildpunkt die des deckenden Laufs" \
    "${WRD:-9999}" eq 0
num "GEGENPROBE: derselbe Lauf mischt seinen Rumpf sehr wohl" \
    "${WD:-0}" ge 2000
SW=$(python3 tools/themestore/shotcheck.py "$TMPD/winal/desktop.ppm" \
     "$TMPD/winal/serial.txt" --leiste --knoepfe 2>&1)
printf '%s\n' "$SW" | head -2 | sed 's/^/        /'
for f in empty cut overlapping; do
    num "durchsichtiges Fenster, $f" \
        "$(printf '%s' "$SW" | grep -oE "$f [0-9]+" | head -1 \
           | cut -d' ' -f2)" eq 0
done

echo
echo "== 11j2. jeder gemeldete Knopf zeigt einen Umriss =="
#
for pair in "set:Darstellung" "winal:durchsichtig" "setv:Vorlagen"; do
    d=${pair%%:*}; nm=${pair##*:}
    KO=$(python3 tools/themestore/shotcheck.py "$TMPD/$d/desktop.ppm" \
         "$TMPD/$d/serial.txt" --knoepfe 2>&1)
    num "Seite $nm: gemessene Knoepfe" \
        "$(printf '%s' "$KO" | grep -oE 'knopf [0-9]+' | cut -d' ' -f2)" ge 1
    num "Seite $nm: Knoepfe ohne jede Umrisskante" \
        "$(printf '%s' "$KO" | grep -oE 'ohnekante [0-9]+' | cut -d' ' -f2)" \
        eq 0
    num "Seite $nm: Beschriftungen, die ueber ihren Knopf hinausragen" \
        "$(printf '%s' "$KO" | grep -oE 'ueberstand [0-9]+' | cut -d' ' -f2)" \
        eq 0
    printf '%s\n' "$KO" | grep -a KNOPF | sed 's/^/        /' || true
done
UEB=$(python3 - "$TMPD/setv/desktop.ppm" "$TMPD/setv/serial.txt" <<'PYU'
import re
import sys
sys.path.insert(0, 'tools/themestore')
import shotcheck as S
pic = S.Pic(sys.argv[1])
texts, wins, font = S.parse(sys.argv[2])
# Dasselbe Fenster wie in `main`: das mit den meisten Beschriftungen.
zaehl = {}
for t in texts:
    zaehl[t["win"]] = zaehl.get(t["win"], 0) + 1
win = max(zaehl, key=lambda k: zaehl[k])
texts = [t for t in texts if t["win"] == win and t["t"].strip()]
# r368: origin as in `shotcheck.py main` -- see the line counter-proof above
if win in wins:
    ox, oy = wins[win]["cx"], wins[win]["cy"]
else:
    ox, oy = texts[0].get("ax") or 0, texts[0].get("ay") or 0
roh = open(sys.argv[2], "rb").read().decode("latin1")
schnitt = roh.rfind("settings: rect name=waa ")
tail = roh[schnitt:] if schnitt >= 0 else roh
# Jeder Knopf, in dem eine Beschriftung steht, wird so schmal gerechnet, dass
# sie zehn Bildpunkte UEBERSTEHT (r368: die Knoepfe der Szenenseite sind breit
# und ihre Schrift steht in der Mitte -- zwanzig Bildpunkte weniger Breite
# liessen sie, wo sie war, im Knopf). Alles andere bleibt unveraendert.
def enger(m):
    x, y, w, h, r, ax, ay = (int(g) for g in m.groups())
    for t in texts:
        tb = oy + t["base"]
        tx = ox + t["x"]
        if t["tw"] > 24 and ay <= tb <= ay + h and ax <= tx < ax + w:
            return ("wlib: knopf x=%d y=%d w=%d h=%d r=%d ax=%d ay=%d"
                    % (x, y, t["tw"] - 10, h, r, tx, ay))
    return m.group(0)
eng = re.sub(r"wlib: knopf x=(\d+) y=(\d+) w=(\d+) h=(\d+) r=(\d+)"
             r" ax=(-?\d+) ay=(-?\d+)", enger, tail)
gem, ohne, ueber, bad = S.knoepfe_messen(
    pic, eng, ox, oy, pic.w, pic.h, None, texts)
print(ueber)
PYU
)
num "GEGENPROBE: schmaler gerechnete Knoepfe lassen ihre Beschriftung ueberstehen" \
    "${UEB:-0}" ge 1
python3 - "$TMPD/set/desktop.ppm" "$TMPD/set/serial.txt" \
         "$TMPD/flach.ppm" <<'PYK'
import sys
sys.path.insert(0, 'tools/themestore')
import shotcheck as S
w, h, d = S.read_ppm(sys.argv[1])
d = bytearray(d)
roh = open(sys.argv[2], "rb").read().decode("latin1")
schnitt = roh.rfind("settings: rect name=waa ")
tail = roh[schnitt:] if schnitt >= 0 else roh
pic = S.Pic(sys.argv[1])
for m in S.KNOPF.finditer(tail):
    x, y, bw, bh, r, ax, ay = (int(g) for g in m.groups())
    # Die Farbe der Karte daneben, und damit alles ausser der Schrift
    # uebermalen: uebrig bleibt ein Knopf ohne Flaeche und ohne Rand.
    grund = pic.at(ax - 8, ay + bh // 2)
    if grund is None:
        continue
    # DESIGN-REGEL 02.10.2026: ein Hauptknopf traegt die Akzentfarbe, und
    # die liegt mehr als 90 von der Karte entfernt -- nach der alten Regel
    # galt seine ganze Flaeche als "Schrift" und blieb stehen. Darum wird
    # auch die FLAECHENFARBE des Knopfes (die haeufigste Farbe in seinem
    # Rechteck) uebermalt; die Schrift bleibt.
    from collections import Counter
    cnt = Counter()
    for j in range(0, bh):
        for i in range(0, bw):
            if 0 <= ax + i < w and 0 <= ay + j < h:
                cnt[pic.at(ax + i, ay + j)] += 1
    flaeche = cnt.most_common(1)[0][0] if cnt else grund
    for j in range(-2, bh + 2):
        for i in range(-2, bw + 2):
            X, Y = ax + i, ay + j
            if not (0 <= X < w and 0 <= Y < h):
                continue
            p = pic.at(X, Y)
            if max(abs(p[k] - grund[k]) for k in range(3)) > 90 \
                    and max(abs(p[k] - flaeche[k]) for k in range(3)) > 40:
                continue          # das ist die Schrift, die bleibt
            o = (Y * w + X) * 3
            d[o], d[o + 1], d[o + 2] = grund
open(sys.argv[3], "wb").write(b"P6\n%d %d\n255\n" % (w, h) + bytes(d))
PYK
KG=$(python3 tools/themestore/shotcheck.py "$TMPD/flach.ppm" \
     "$TMPD/set/serial.txt" --knoepfe 2>&1 \
     | grep -oE 'ohnekante [0-9]+' | cut -d' ' -f2)
num "GEGENPROBE: ein flach uebermalter Knopf wird gefunden" "${KG:-0}" ge 1

echo
echo "== 11k. die Vorschaukachel: eine Form, und der Name ist ganz da =="
KINNEN=0
KZAHL=0
while read -r kx ky kw kh; do
    [ -n "$kx" ] || continue
    [ -s "$TMPD/setv/desktop.png" ] || continue
    O=$(python3 tools/themestore/glascheck.py kachel \
        "$TMPD/setv/desktop.png" "$kx" "$ky" "$kw" "$kh" \
        "${KACHR:-12}" 2>&1 | tail -1)
    ki=$(printf '%s' "$O" | grep -oE 'innen=[0-9]+' | cut -d= -f2)
    KINNEN=$((KINNEN + ${ki:-99}))
    KZAHL=$((KZAHL + 1))
    [ "${ki:-9}" = 0 ] || echo "        $ky: $O"
done <<EOF
$KACHELN
EOF
num "gemessene Kacheln (eine Vorschaukachel seit der Seitenumstellung)" "$KZAHL" ge 1
num "Bildpunkte, die in der Flaeche einer Kachel fehlen (Loecher)" \
    "$KINNEN" eq 0
KL1=$(printf '%s\n' "$KACHELN" | head -1)
set -- $KL1
python3 - "$TMPD/setv/desktop.png" "$TMPD/kachelloch.png" "$1" "$2" <<'PYL'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
x, y = int(sys.argv[3]), int(sys.argv[4])
grund = im.getpixel((x - 6, y + 16))
for j in range(14, 19):
    for i in range(1, 9):
        im.putpixel((x + i, y + j), grund)
im.save(sys.argv[2])
PYL
KLO=$(python3 tools/themestore/glascheck.py kachel "$TMPD/kachelloch.png" \
      "$1" "$2" "$3" "$4" "${KACHR:-12}" 2>&1 | tail -1)
echo "        GEGENPROBE: $KLO"
num "GEGENPROBE: ein gestanztes Loch wird gefunden" \
    "$(printf '%s' "$KLO" | grep -oE 'innen=[0-9]+' | cut -d= -f2)" ge 1
NC=$(python3 tools/themestore/namecheck.py "$TMPD/setv/desktop.png" \
     "$TMPD/setv/serial.txt" assets/themes "$TMPD/namenloch.png" 2>&1)
printf '%s\n' "$NC" | sed 's/^/        /'
num "gemalte Kachelnamen (genau die gewaehlte Vorlage)" \
    "$(printf '%s' "$NC" | grep -oE 'gemalt=[0-9]+' | cut -d= -f2)" \
    eq 1
num "Kachelnamen, die fehlen (alle anderen Vorlagen stehen nur im Auswahlfeld)" \
    "$(printf '%s' "$NC" | grep -oE "fehlt=[0-9]+" | cut -d= -f2)" \
    eq "$((NPRESET - 1))"
for z in gekuerzt ohnetinte; do
    num "Kachelnamen, die $z sind" \
        "$(printf '%s' "$NC" | grep -oE "$z=[0-9]+" | cut -d= -f2)" eq 0
done
NL=$(python3 tools/themestore/namecheck.py "$TMPD/namenloch.png" \
     "$TMPD/setv/serial.txt" assets/themes 2>&1)
echo "        GEGENPROBE: $(printf '%s' "$NL" | head -1)"
num "GEGENPROBE: ein uebermaltes 'r' wird gefunden" \
    "$(printf '%s' "$NL" | grep -oE 'ohnetinte=[0-9]+' | cut -d= -f2)" ge 1

echo
#
MINDEST=200
GESAMT=$((pass + fail))
echo "THEMESTORE: $pass passed, $fail failed ($GESAMT Zusagen geprueft," \
     "Mindestzahl $MINDEST)"
if [ "$GESAMT" -lt "$MINDEST" ]; then
    echo "THEMESTORE: ABGEBROCHEN -- nur $GESAMT Zusagen geprueft," \
         "das ist kein gruener Lauf"
    exit 1
fi
[ "$fail" -eq 0 ] || exit 1
exit 0
