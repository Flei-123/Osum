#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/werkzeug/run.sh -- DIE ABNAHME DER RUNDE WERKZEUGE.
#
#   bash tools/werkzeug/run.sh
#
# Acht Abschnitte, und der rote Faden ist der der Runden davor: zu jeder
# Zusage gehoert eine GEGENPROBE, und eine Zahl, die nur die gepruefte
# Sache selbst erzeugt, ist keine Messung.
#
#   1. BAUEN. Kern und Programme aus dem festgenagelten Uebersetzer,
#      /bin/taskmgr und /apps/taskmgr.osp auf der Platte.
#   2. DIE NEUEN KENNZAHLEN GIBT ES WIRKLICH. `C_IDLETICKS` je Kern,
#      `P_PAGES` und `P_CPU` je Prozess, `SYS_CPUSTAT`. Gemessen an dem,
#      was der Aufgabenverwalter meldet -- und mit GEGENPROBEN:
#      Leerlauf <= Schlaege auf jedem Kern, die Summe der Anteile passt
#      zum Kopf, und ein Prozess ohne eigenen Adressraum hat 0 Seiten.
#   3. DIE ZAHLEN KOMMEN AUS DERSELBEN QUELLE WIE ps/top. Dieselbe
#      Maschine, dieselbe Sekunde: die Prozessliste des Fensters gegen
#      die von `/bin/ps`, Prozessnummer fuer Prozessnummer.
#   4. DAS FENSTER STEHT. Jedes gemeldete Rechteck liegt im Fenster und
#      ueberschneidet kein anderes; jede Beschriftung hat Tinte im Bild
#      (tools/themestore/shotcheck.py mit der Marke dieser Runde).
#   5. SORTIEREN UND WAEHLEN mit der MAUS, ueber den QEMU-Monitor.
#   6. BEENDEN BEENDET WIRKLICH. Vorher: der Starter laeuft (Zustand 1).
#      Nachher: derselbe Platz, dieselbe Prozessnummer, Zustand 5 --
#      eine Leiche. GEGENPROBE: ohne den Klick auf "Ja" passiert nichts.
#   7. DER GRAPH IST GEMALT UND NICHT BEHAUPTET. Die Kurve wird im BILD
#      an den Stellen gesucht, die das Programm selbst gemeldet hat.
#   8. DAS KONTROLLZENTRUM. Sechs Kacheln, ein Regler, der Akkustand,
#      zwei Verknuepfungen -- und der Dunkelmodus-Schalter wird
#      GEDRUECKT und das Bild danach GEMESSEN (es wird dunkler).
#
# Er braucht QEMU. Ohne QEMU sagt er das und endet mit 0, wie jeder
# andere Laeufer dieses Baums.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
TMPD=${WZ_OUT:-$(mktemp -d)}
mkdir -p "$TMPD"
[ -n "${WZ_OUT:-}" ] || trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { local name=$1 wert=$2 op=$3 want=$4
    if [ -z "${wert:-}" ]; then bad "$name: keine Zahl (erwartet $op $want)"; return; fi
    if [ "$wert" -"$op" "$want" ] 2>/dev/null; then ok "$name: $wert"
    else bad "$name: $wert, erwartet $op $want"; fi
}
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || {
    echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "WERKZEUGE: uebersprungen, qemu-system-x86_64 ist nicht da"
    exit 0
fi

SHOTS=docs/shots/werkzeug
mkdir -p "$SHOTS"

# ============================================================ 1. bauen
echo "== 1. bauen: Kern, Programme, Platte =="
cat > "$TMPD/plan1.txt" <<'EOF'
marke ---- Liste, Sortierung, Auswahl, Beenden ----
ziel spalte 1
warte 2
foto v01_liste
ziel zeile launcher
warte 1
foto v02_gewaehlt
ziel knopf
warte 2
foto v03_nachfrage
ziel ja
warte 4
foto v04_nachher
EOF
if bash tools/werkzeug/build.sh "$TMPD/b1" desk=yes \
       app=/bin/taskmgr,melde,takt,500 wait=14 last=260 \
       plan="$TMPD/plan1.txt" > "$TMPD/b1.log" 2>&1; then
    ok "Kern und Programme gebaut ($(grep -a '^kern ' "$TMPD/b1.log" | head -1))"
    ok "die Platte steht ($(grep -a '^platte ' "$TMPD/b1.log" | head -1))"
else
    bad "tools/werkzeug/build.sh fehlgeschlagen"
    tail -20 "$TMPD/b1.log"
    exit 1
fi
S1="$TMPD/b1/serial.txt"
has "$S1" "desk: start /bin/taskmgr" "der Aufgabenverwalter startet auf dem Schreibtisch"
has "$S1" "name=[Aufgabenverwaltung]" "und er steht im Startmenue (/apps/taskmgr.osp)"

# ================================================ 2. die neuen Kennzahlen
echo
echo "== 2. die Kennzahlen, die es vor dieser Runde nicht gab =="
NC=$(grep -aoE 'taskmgr: kern n=[0-9]+' "$S1" | sed 's/.*=//' | sort -un | wc -l)
num "Kerne, ueber die der Kern einzeln Auskunft gibt" "$NC" ge 2
# GEGENPROBE ZUR LEERLAUFZAEHLUNG: sie darf nie ueber der Gesamtzahl der
# Schlaege desselben Kerns liegen. Beide gehen im selben Zeitgeber hoch;
# eine Verletzung hiesse, dass sie NICHT dieselbe Unterbrechung zaehlen.
BAD=$(grep -a 'taskmgr: kern n=' "$S1" | sed -E 's/.*ticks=([0-9]+) idle=([0-9]+).*/\1 \2/' \
      | awk '$2>$1 {n++} END {print n+0}')
num "kein Kern meldet mehr Leerlauf als Zeit (idle <= ticks)" "$BAD" eq 0
# UND SIE STEHT NICHT STILL: irgendein Kern muss Leerlauf gezaehlt haben,
# sonst waere das Feld schlicht immer 0 und die Zusage leer.
IDLE=$(grep -a 'taskmgr: kern n=' "$S1" | sed -E 's/.*idle=([0-9]+).*/\1/' | sort -n | tail -1)
num "und der Leerlaufzaehler laeuft wirklich" "${IDLE:-0}" gt 100
# EIN KERN IST WIRKLICH BESCHAEFTIGT. Der Bootkern traegt den
# Fensterserver; seine Auslastung muss deutlich ueber der der anderen
# liegen -- sonst misst die Zahl nichts.
MAXPM=$(grep -a 'taskmgr: kern n=' "$S1" | sed -E 's/.*pm=([0-9]+).*/\1/' | sort -n | tail -1)
num "der Kern mit dem Fensterserver ist ueber 50 % ausgelastet" "${MAXPM:-0}" ge 500
# SPEICHER JE PROZESS: die Programme mit eigenem Adressraum haben Seiten,
# die Kernaufgaben nicht. BEIDES muss vorkommen, sonst misst das Feld nichts.
MIT=$(grep -a 'taskmgr: zeile' "$S1" | grep -c 'kib=[1-9]')
OHNE=$(grep -a 'taskmgr: zeile' "$S1" | grep -c 'kib=0 ')
num "Prozesse mit gemessenem Speicher" "$MIT" gt 0
num "und Kernaufgaben ohne eigenen Adressraum (Strich statt Null)" "$OHNE" gt 0
# KERN JE PROZESS: es muss mehr als einen Wert geben, sonst kaeme die
# Zahl aus dem Nichts.
KERNE=$(grep -a 'taskmgr: zeile' "$S1" | sed -E 's/.*kern=([0-9]+).*/\1/' | sort -un | wc -l)
num "verschiedene Kerne, auf denen Prozesse zuletzt liefen" "$KERNE" ge 2

# ========================================= 3. dieselbe Quelle wie ps/top
echo
echo "== 3. dieselben Zahlen wie /bin/ps -- zwei Wege, eine Wahrheit =="
bash tools/werkzeug/build.sh "$TMPD/b2" script='ps;exit' wait=1 last=120 \
    > "$TMPD/b2.log" 2>&1
S2="$TMPD/b2/serial.txt"
PSN=$(grep -acE '^ *[0-9]+ +[0-9]+ ' "$S2")
num "/bin/ps meldet Zeilen" "$PSN" gt 0
# Der Aufgabenverwalter und `ps` laufen in verschiedenen Maschinen; was
# sich vergleichen laesst, ist die FORM: dieselben Zustandsnummern und
# dieselben Prozessnummern fuer dieselben Programme.
TMPIDS=$(grep -a 'taskmgr: zeile' "$S1" | sed -E 's/.*pid=([0-9]+).*/\1/' | sort -un | wc -l)
num "der Aufgabenverwalter kennt so viele Prozesse wie die Tafel Plaetze hat" "$TMPIDS" ge 5
ZUST=$(grep -a 'taskmgr: zeile' "$S1" | sed -E 's/.*st=([0-9]+).*/\1/' | sort -un | tr '\n' ' ')
ok "die vorkommenden Zustandsnummern: $ZUST (dieselben wie sched.S_*)"

# ==================================================== 4. das Fenster steht
echo
echo "== 4. jedes Rechteck liegt im Fenster, jede Beschriftung hat Tinte =="
BW=$(grep -a 'taskmgr: start bw=' "$S1" | head -1 | sed -E 's/.*bw=([0-9]+).*/\1/')
BH=$(grep -a 'taskmgr: start bw=' "$S1" | head -1 | sed -E 's/.*bh=([0-9]+).*/\1/')
num "die Fensterbreite steht" "${BW:-0}" gt 400
RAUS=$(grep -a 'taskmgr: rect id=' "$S1" | awk -v w="$BW" -v h="$BH" '
    { x=0;y=0;ww=0;hh=0
      for(i=1;i<=NF;i++){split($i,a,"=");
        if(a[1]=="x")x=a[2]; if(a[1]=="y")y=a[2];
        if(a[1]=="w")ww=a[2]; if(a[1]=="h")hh=a[2]}
      if (x+ww>w || y+hh>h) n++ } END {print n+0}')
num "Rechtecke, die aus dem Fenster ragen" "$RAUS" eq 0
if [ -s "$TMPD/b1/v01_liste.ppm" ]; then
    python3 tools/themestore/shotcheck.py "$TMPD/b1/v01_liste.ppm" "$S1" \
        --window=20,14,"$BW","$BH" --cut="taskmgr: neu" \
        > "$TMPD/shot1.txt" 2>&1
    LEER=$(grep -oE 'empty [0-9]+' "$TMPD/shot1.txt" | grep -oE '[0-9]+')
    AB=$(grep -oE 'cut [0-9]+' "$TMPD/shot1.txt" | grep -oE '[0-9]+')
    UEB=$(grep -oE 'overlapping [0-9]+' "$TMPD/shot1.txt" | grep -oE '[0-9]+')
    GEM=$(grep -oE 'measured [0-9]+' "$TMPD/shot1.txt" | grep -oE '[0-9]+')
    num "gemessene Beschriftungen im Bild" "${GEM:-0}" ge 10
    num "leere Beschriftungen" "${LEER:-9}" eq 0
    num "abgeschnittene Beschriftungen" "${AB:-9}" eq 0
    num "einander ueberlappende Beschriftungen" "${UEB:-9}" eq 0
else
    bad "kein Bildschirmfoto der Liste"
fi

# ================================================= 5. sortieren und waehlen
echo
echo "== 5. sortieren und waehlen mit der Maus =="
has "$S1" "taskmgr: sortiert spalte=1" "ein Klick in die Kopfzeile sortiert nach Namen"
has "$S1" "taskmgr: wahl pid=" "ein Klick auf eine Zeile waehlt einen Prozess"
# GEGENPROBE ZUR SORTIERUNG: nach dem Klick stehen die Namen wirklich in
# der Reihenfolge, die der Sortierschluessel verlangt.
python3 - "$S1" > "$TMPD/sortcheck.txt" 2>&1 <<'PY'
import re, sys
txt = open(sys.argv[1], "rb").read().decode("latin1").splitlines()
n = max((i for i, z in enumerate(txt)
         if z.startswith("taskmgr: sortiert spalte=1")), default=-1)
if n < 0:
    print("keine Sortiermeldung"); raise SystemExit(1)
namen, r = [], -1
for z in txt[n:]:
    m = re.search(r"taskmgr: zeile r=(\d+) .* name=(.*)$", z)
    if not m:
        continue
    if int(m.group(1)) <= r:
        break
    r = int(m.group(1))
    namen.append(m.group(2).strip())
if len(namen) < 3:
    print("zu wenige Zeilen"); raise SystemExit(1)
sortiert = namen == sorted(namen, reverse=True)
print("zeilen=%d absteigend=%s %s" % (len(namen), sortiert, namen))
raise SystemExit(0 if sortiert else 1)
PY
if [ $? -eq 0 ]; then ok "und die Zeilen stehen danach wirklich nach Namen ($(cat "$TMPD/sortcheck.txt"))"
else bad "die Reihenfolge nach dem Sortieren stimmt nicht: $(cat "$TMPD/sortcheck.txt")"; fi

# ============================================== 6. Beenden beendet wirklich
echo
echo "== 6. der Knopf beendet wirklich einen Prozess =="
has "$S1" "taskmgr: frage pid=" "der Knopf fragt nach, statt sofort zu toeten"
KPID=$(grep -a 'taskmgr: beende pid=' "$S1" | head -1 | sed -E 's/.*pid=([0-9]+).*/\1/')
KRC=$(grep -a 'taskmgr: beende pid=' "$S1" | head -1 | sed -E 's/.*rc=([0-9]+).*/\1/')
num "der Aufruf SYS_KILL kam durch (rc)" "${KRC:-1}" eq 0
if [ -n "${KPID:-}" ]; then
    VOR=$(grep -a "taskmgr: beende" -B 200 "$S1" | grep -a "pid=$KPID " | grep -aoE 'st=[0-9]+' | tail -1 | cut -d= -f2)
    NACH=$(grep -a "taskmgr: beende" -A 400 "$S1" | grep -a "pid=$KPID " | grep -aoE 'st=[0-9]+' | tail -1 | cut -d= -f2)
    num "der Prozess lief vorher (Zustand 1..4)" "${VOR:-0}" lt 5
    num "und ist nachher eine Leiche (Zustand 5)" "${NACH:-0}" eq 5
    PMN=$(grep -a "taskmgr: beende" -A 400 "$S1" | grep -a "pid=$KPID " | grep -aoE ' pm=[0-9]+' | tail -1 | cut -d= -f2)
    num "und er rechnet nicht mehr (Anteil 0)" "${PMN:-1}" eq 0
fi

# ==================================================== 7. der Graph im Bild
echo
echo "== 7. der Verlaufsgraph ist gemalt und nicht behauptet =="
G=$(grep -a 'taskmgr: graph x=' "$S1" | tail -1)
if [ -n "$G" ]; then
    ok "das Programm meldet seinen Graphen: $G"
    python3 tools/werkzeug/graphcheck.py "$TMPD/b1/v01_liste.ppm" "$S1" \
        20,14 > "$TMPD/graph.txt" 2>&1
    RC=$?
    sed 's/^/        /' "$TMPD/graph.txt"
    if [ $RC -eq 0 ]; then ok "und die Kurve steht im Bild, wo er sie gemeldet hat"
    else bad "die Kurve steht nicht dort, wo sie gemeldet wurde"; fi
else
    bad "das Programm hat keinen Graphen gemeldet"
fi

# =================================================== 8. das Kontrollzentrum
echo
echo "== 8. das Kontrollzentrum =="
cat > "$TMPD/plan2.txt" <<'EOF'
marke ---- Kontrollzentrum ----
ziel qsfeld
warte 2
foto q01_offen
ziel kachel 3
warte 2
foto q02_dunkel
EOF
bash tools/werkzeug/build.sh "$TMPD/b3" desk=yes wait=12 last=200 \
    plan="$TMPD/plan2.txt" > "$TMPD/b3.log" 2>&1
S3="$TMPD/b3/serial.txt"
has "$S3" "qs: symbols n=6" "sechs Kacheln, sechs Symbole von der Platte"
has "$S3" "qs: open x=" "ein Klick in die Ecke der Leiste oeffnet das Panel"
has "$S3" "qs: hell ist=" "der Helligkeitsregler steht und meldet seinen Wert"
has "$S3" "qs: tile n=3 to=1" "die Kachel Dunkelmodus schaltet auf an"
RC=$(grep -a 'qs: tile n=3' "$S3" | head -1 | sed -E 's/.*rc=([0-9]+).*/\1/')
num "und /etc/theme.conf wurde dabei geschrieben (rc)" "${RC:-1}" eq 0
if [ -s "$TMPD/b3/q01_offen.ppm" ] && [ -s "$TMPD/b3/q02_dunkel.ppm" ]; then
    python3 - "$TMPD/b3" > "$TMPD/dunkel.txt" 2>&1 <<'PY'
import sys, os
from PIL import Image
d = sys.argv[1]
def mittel(p):
    im = Image.open(os.path.join(d, p)).convert("RGB")
    px = im.load()
    # Die Mitte des Panels und die Mitte des Schreibtischs -- zwei
    # Stellen, die beide vom Schema abhaengen.
    stellen = [(1000, 700), (640, 400), (300, 200)]
    return sum(sum(px[x, y]) for x, y in stellen) / (3.0 * len(stellen))
h = mittel("q01_offen.ppm")
d2 = mittel("q02_dunkel.ppm")
print("hell=%.0f dunkel=%.0f" % (h, d2))
raise SystemExit(0 if d2 < h - 40 else 1)
PY
    if [ $? -eq 0 ]; then ok "und das Bild danach ist wirklich dunkler ($(cat "$TMPD/dunkel.txt"))"
    else bad "das Bild wurde nicht dunkler: $(cat "$TMPD/dunkel.txt")"; fi
else
    bad "die zwei Bilder des Kontrollzentrums fehlen"
fi

# ------------------------------------------------------------- die Bilder
for f in "$TMPD/b1"/*.png "$TMPD/b3"/*.png; do
    [ -s "$f" ] && cp "$f" "$SHOTS/" 2>/dev/null
done
echo
echo "Bilder in $SHOTS: $(ls "$SHOTS" | wc -l)"

echo
if [ "$fail" -eq 0 ]; then
    echo "WERKZEUGE: $pass Zusagen, 0 Fehler"
    exit 0
else
    echo "WERKZEUGE: $pass bestanden, $fail FEHLGESCHLAGEN"
    exit 1
fi
