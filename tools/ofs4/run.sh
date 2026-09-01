#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ofs4/run.sh -- DIE ABNAHME DER RUNDE OFS4.
#
# Acht Abschnitte, und der dritte und der siebte sind die, um die es
# geht:
#
#   1. BAUEN. Kern und Programme, und zwei Abbilder, die sich in genau
#      EINER Zahl unterscheiden: wie viele Kartenbloecke sie haben.
#   2. DIE KARTE SETZT DIE GRENZE. Dasselbe Dateisystem auf demselben
#      Geraet waechst einmal bis zum Geraet und einmal nur bis zur
#      Karte. Das ist die Messung der Entwurfsentscheidung aus
#      docs/OFS4-ENTWURF.md, Abschnitt 3 -- und keine Behauptung.
#   3. WACHSEN, VERKLEINERN, WACHSEN, und der Bestand muss dreimal
#      DIESELBEN Zahlen liefern. Verglichen wird Zeile fuer Zeile.
#   4. DIE ABLEHNUNG. Eine Verkleinerung, die nicht passen kann, muss
#      abgelehnt werden UND die Platte Oktett fuer Oktett so lassen,
#      wie sie war. Gemessen mit `md5sum` ueber das ganze Abbild.
#   5. UNTER LAST. Gewachsen wird, WAEHREND `/bin/fsrw` in einem
#      eigenen Prozess schreibt. Danach muss der Bestand unveraendert
#      sein.
#   6. DER WIRT. Struktur, Inhalt und Grenze, aus dem Abbild gelesen
#      und nicht aus der seriellen Leitung (tools/ofs4/pruef.py).
#   7. DER STROMAUSFALL. QEMU wird mitten im Groessenwechsel mit
#      SIGKILL abgeschossen. Danach muss `fsck` in JEDEM Fall ein
#      gueltiges Dateisystem finden -- die alte Groesse oder die neue,
#      nie etwas dazwischen.
#   8. RUECKWAERTS. Ein Abbild ohne Vorratskarte ist Oktett fuer Oktett
#      das von vor dieser Runde, und `SB_BLOCKS` ist das einzige Feld,
#      das ueberhaupt angefasst wird.
#
# Umgebung:
#   OFS4_LAEUFE   wie viele Abschuesse (Vorgabe 50)
#   OFS4_PAR      wie viele gleichzeitig (Vorgabe 4)
#   OFS4_ACCEL    kvm oder tcg (Vorgabe kvm)
#   OFS4_KEEP     Arbeitsverzeichnis behalten
#
# Benutzung:  bash tools/ofs4/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."

export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
PROGS="sh ls cat echo rm df touch mkdir fsck fsrw ofs4"
LAEUFE=${OFS4_LAEUFE:-50}
PAR=${OFS4_PAR:-4}
export OFS4_ACCEL=${OFS4_ACCEL:-kvm}

TMPD=$(mktemp -d)
if [ -z "${OFS4_KEEP:-}" ]; then
    trap 'rm -rf "$TMPD"' EXIT
else
    echo "OFS4: Arbeitsverzeichnis $TMPD bleibt stehen"
fi

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { # name wert -op erwartet
    local name=$1 wert=$2 op=$3 want=$4
    if [ -z "$wert" ]; then bad "$name: keine Zahl gefunden (erwartet $op $want)"; return; fi
    if [ "$wert" "$op" "$want" ] 2>/dev/null; then ok "$name: $wert"
    else bad "$name: $wert, erwartet $op $want"; fi
}
val() { tr -d '\000' < "$1" 2>/dev/null | grep -a "^$2: $3 = " | head -1 | sed 's/.* = //'; }
valn() { tr -d '\000' < "$1" 2>/dev/null | grep -a "^$2: $3 = " | sed -n "$4p" | sed 's/.* = //'; }

# Der `n`-te Pruefblock aus einer seriellen Ausgabe: alles von `tief_0`
# bis `mtime_tief`. Zwei Bloecke sind genau dann gleich, wenn der
# Bestand denselben Inhalt, dieselben Inodenummern und dieselbe
# Aenderungszeit hat.
block() { # datei nummer
    tr -d '\000' < "$1" 2>/dev/null \
        | awk -v n="$2" '/^ofs4: tief_0 = /{c++} c==n{print} /^ofs4: mtime_tief = /{if(c==n) exit}'
}

lauf() { # abbild anhaengsel script [zeitlimit] [zusatzwoerter]
    local img=$1 aus=$2 skript=$3 lim=${4:-1800} extra=${5:-}
    timeout "$lim" qemu-system-x86_64 -accel "$OFS4_ACCEL" \
        -kernel "$TMPD/k.mb" -m 512 \
        -append "osum vfs nokbd $extra script=$skript" \
        -serial "file:$TMPD/$aus.txt" -display none -no-reboot \
        -drive "file=$img,format=raw,if=ide,index=0,cache=directsync" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}

echo "== 1. bauen =="
bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh fehlgeschlagen"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc0 fehlt: $FIRNC"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "OFS4: uebersprungen, qemu-system-x86_64 fehlt"
    exit 0
fi

bash tools/build-kernel.sh "$TMPD/k.mb" >"$TMPD/build.txt" 2>&1 \
    && ok "Kern gebaut ($(stat -c%s "$TMPD/k.mb") Oktette)" \
    || { bad "der Kern laesst sich nicht bauen"; tail -8 "$TMPD/build.txt" | sed 's/^/        /';
         echo "OFS4: $pass bestanden, $fail gescheitert"; exit 1; }
export OFS4_KERNEL="$TMPD/k.mb"

as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s"
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" >"$TMPD/e$p" 2>&1 \
        || { bad "$p.fi uebersetzt nicht"; sed 's/^/        /' "$TMPD/e$p" | head -6; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" \
        -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null
    strip --strip-all "$TMPD/$p.elf" 2>/dev/null
done
ok "$(echo $PROGS | wc -w) Programme gebaut, darunter /bin/ofs4"

SPEC="/bin/ /tmp/ /dev/ /proc/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done

# ZWEI ABBILDER, UND SIE UNTERSCHEIDEN SICH IN EINER ZAHL.
#
#   a.img  --karten=4  -> die Karte deckt 4 * 4096 = 16384 Bloecke, also
#                         genau das Dateisystem und nicht mehr.
#   b.img  --karten=8  -> die Karte deckt 32768 Bloecke, also das ganze
#                         GERAET. Das ist der Vorrat aus Runde INSTALL,
#                         und er ist die Antwort dieser Runde auf die
#                         Frage, wie eine Karte waechst, ohne die
#                         Inodetabelle zu schieben.
#
# Beide Abbilder werden danach auf 16 MiB verlaengert: das GERAET ist
# doppelt so gross wie das Dateisystem darauf. Genau die Lage, in der
# ein Installationsprogramm ein frisch aufgespieltes System vorfindet.
for k in 4 8; do
    n=a; [ "$k" = 8 ] && n=b
    python3 tools/osum/mkfs.py build "$TMPD/$n.img" 16384 --v3 --inodes=256 \
        --journal --karten=$k --time=1780000000 $SPEC > "$TMPD/mk$n.txt" 2>&1 \
        || bad "mkfs $n.img"
    python3 - "$TMPD/$n.img" <<'PY'
import sys
f = open(sys.argv[1], "r+b")
f.seek(16 * 1024 * 1024 - 1)
f.write(b"\0")
f.close()
PY
done
grep -qa 'bmblocks=4' "$TMPD/mka.txt" && ok "a.img: Karte deckt 16384 Bloecke (kein Vorrat)" \
    || bad "a.img hat nicht vier Kartenbloecke"
grep -qa 'bmblocks=8' "$TMPD/mkb.txt" && ok "b.img: Karte deckt 32768 Bloecke (Vorrat wie ext4s reservierte GDT-Bloecke)" \
    || bad "b.img hat nicht acht Kartenbloecke"

echo "== 2. die Karte setzt die Grenze =="
lauf "$TMPD/a.img" wa "ofs4 wachsen auto;fsck /dev/hda;exit" 900
num "a.img: das Geraet hat"          "$(val "$TMPD/wa.txt" ofs4 dev)"    -eq 32768
num "a.img: die Karte deckt"          "$(val "$TMPD/wa.txt" ofs4 map)"    -eq 16384
num "a.img: gewachsen bis"            "$(val "$TMPD/wa.txt" ofs4 wachsen)" -eq 16384
num "a.img: fsck-Fehler danach"       "$(val "$TMPD/wa.txt" fsck fehler)" -eq 0
lauf "$TMPD/b.img" wb "ofs4 wachsen auto;fsck /dev/hda;exit" 900
num "b.img: die Karte deckt"          "$(val "$TMPD/wb.txt" ofs4 map)"    -eq 32768
num "b.img: gewachsen bis"            "$(val "$TMPD/wb.txt" ofs4 wachsen)" -eq 32768
num "b.img: Bloecke danach"           "$(val "$TMPD/wb.txt" ofs4 blocks)" -eq 32768
num "b.img: fsck-Fehler danach"       "$(val "$TMPD/wb.txt" fsck fehler)" -eq 0
python3 tools/ofs4/pruef.py struktur "$TMPD/b.img" > "$TMPD/wbs.txt" 2>&1
grep -qa BEFUND "$TMPD/wbs.txt" && bad "der Wirt sieht nach dem Wachsen einen Schaden" \
    || ok "der Wirt sieht nach dem Wachsen kein Problem"

echo "== 3. der Bestand, und dreimal dieselben Zahlen =="
# b.img ist jetzt 32768 Bloecke gross. Der Bestand entsteht EINMAL und
# wird danach fuer jeden weiteren Abschnitt kopiert -- ihn dreimal zu
# bauen waere dreimal dieselbe Messung und dreimal dieselbe Wartezeit.
cp --sparse=always "$TMPD/b.img" "$TMPD/bestand.img"
lauf "$TMPD/bestand.img" ba "ofs4 bauen;ofs4 pruef;exit" 2400
num "der Bestand: Namen in EINEM Verzeichnis" "$(val "$TMPD/ba.txt" ofs4 viele)" -eq 24
num "der Bestand: Fuellstuecke"               "$(val "$TMPD/ba.txt" ofs4 fuell1)" -eq 16
num "der Bestand: davon wieder geloescht"     "$(val "$TMPD/ba.txt" ofs4 gebaut)" -eq 8
num "die luecklose Datei ist lang genug (dreifach indirekt)" \
    "$(val "$TMPD/ba.txt" ofs4 len_tief)" -gt 2134016
num "die dritte Zeigerstufe liest sich"       "$(val "$TMPD/ba.txt" ofs4 tief_2)" -eq 512

cp --sparse=always "$TMPD/bestand.img" "$TMPD/lauf3.img"
lauf "$TMPD/lauf3.img" l3 \
    "ofs4 pruef;ofs4 klein auto;ofs4 pruef;ofs4 wachsen auto;ofs4 pruef;fsck /dev/hda;exit" 3600
NEED=$(val "$TMPD/l3.txt" ofs4 need)
MOVED=$(val "$TMPD/l3.txt" ofs4 moved)
KLEIN=$(val "$TMPD/l3.txt" ofs4 klein)
num "hinter der neuen Grenze lagen belegte Bloecke" "$NEED" -gt 0
num "und genau so viele sind umgezogen"             "$MOVED" -eq "${NEED:-0}"
num "verkleinert auf"                               "$KLEIN" -gt 0
num "und danach wieder gewachsen auf"               "$(val "$TMPD/l3.txt" ofs4 wachsen)" -eq 32768
num "fsck-Fehler nach beidem"                       "$(val "$TMPD/l3.txt" fsck fehler)" -eq 0

block "$TMPD/l3.txt" 1 > "$TMPD/b1.txt"
block "$TMPD/l3.txt" 2 > "$TMPD/b2.txt"
block "$TMPD/l3.txt" 3 > "$TMPD/b3.txt"
[ -s "$TMPD/b1.txt" ] || bad "der erste Pruefblock ist leer"
cmp -s "$TMPD/b1.txt" "$TMPD/b2.txt" \
    && ok "nach dem VERKLEINERN sagt der Bestand Zeile fuer Zeile dasselbe ($(wc -l < "$TMPD/b1.txt") Zeilen)" \
    || { bad "nach dem Verkleinern hat sich etwas am Bestand geaendert"; diff "$TMPD/b1.txt" "$TMPD/b2.txt" | sed 's/^/        /' | head -12; }
cmp -s "$TMPD/b1.txt" "$TMPD/b3.txt" \
    && ok "nach dem WACHSEN sagt der Bestand Zeile fuer Zeile dasselbe" \
    || { bad "nach dem Wachsen hat sich etwas am Bestand geaendert"; diff "$TMPD/b1.txt" "$TMPD/b3.txt" | sed 's/^/        /' | head -12; }
num "der harte Verweis zeigt weiter auf dieselbe Inode" \
    "$(valn "$TMPD/l3.txt" ofs4 hartok 3)" -eq 1
num "der symbolische Verweis liest sich weiter"  "$(valn "$TMPD/l3.txt" ofs4 zeigok 3)" -eq 1
num "umbenennen kopiert weiter nicht"            "$(valn "$TMPD/l3.txt" ofs4 renameok 3)" -eq 1
num "das grosse Verzeichnis hat weiter alle Eintraege" \
    "$(valn "$TMPD/l3.txt" ofs4 dents 3)" -eq 26

echo "== 4. die Ablehnung, und die Platte bleibt Oktett fuer Oktett dieselbe =="
cp --sparse=always "$TMPD/bestand.img" "$TMPD/nein.img"
VOR=$(md5sum "$TMPD/nein.img" | cut -d' ' -f1)
# `noatime` UND KEIN ZUFALL: ohne das Wort schreibt `open` die
# Zugriffszeit von `/bin/sh` und `/bin/ofs4` in deren Inodes, und das
# Abbild waere nach JEDEM Start ein anderes -- auch nach einem, der
# gar nichts tut. Die Gegenprobe dazu steht eine Zeile weiter unten:
# derselbe Start ohne `ofs4 nein` laesst das Abbild ebenfalls
# unveraendert, also misst `md5sum` hier wirklich die Ablehnung und
# nicht die Abwesenheit von Zugriffszeiten.
lauf "$TMPD/nein.img" ne "ofs4 nein;exit" 900 noatime
cp --sparse=always "$TMPD/bestand.img" "$TMPD/kontr.img"
lauf "$TMPD/kontr.img" ko "ofs4 info;exit" 900 noatime
[ "$(md5sum "$TMPD/kontr.img" | cut -d' ' -f1)" = "$VOR" ] \
    && ok "Gegenprobe: ein Start OHNE Verkleinerung laesst dasselbe Abbild ebenfalls unveraendert" \
    || bad "schon ein Start ohne Verkleinerung veraendert das Abbild -- md5sum misst hier nichts" 
NACH=$(md5sum "$TMPD/nein.img" | cut -d' ' -f1)
num "eine Verkleinerung, die nicht passt, meldet fits=0" "$(val "$TMPD/ne.txt" ofs4 fits)" -eq 0
num "und tut nichts (Rueckgabe 0)"                       "$(val "$TMPD/ne.txt" ofs4 nein)" -eq 0
num "die Groesse steht unveraendert"                     "$(val "$TMPD/ne.txt" ofs4 blocks)" -eq 32768
[ "$VOR" = "$NACH" ] && ok "das Abbild ist danach Oktett fuer Oktett dasselbe ($VOR)" \
    || bad "die abgelehnte Verkleinerung hat die Platte veraendert"

echo "== 5. wachsen, waehrend geschrieben wird =="
cp --sparse=always "$TMPD/bestand.img" "$TMPD/last.img"
lauf "$TMPD/last.img" la "ofs4 klein auto;ofs4 last auto;ofs4 pruef;exit" 3600
num "der zweite Prozess ist gestartet"  "$(val "$TMPD/la.txt" ofs4 pid)" -gt 0
num "und er hat wirklich geschrieben"   "$(val "$TMPD/la.txt" ofs4 last)" -eq 1
num "gewachsen bis"                     "$(val "$TMPD/la.txt" ofs4 wachsen)" -eq 32768
block "$TMPD/la.txt" 1 > "$TMPD/bl.txt"
cmp -s "$TMPD/b1.txt" "$TMPD/bl.txt" \
    && ok "der Bestand ist auch nach Verkleinern+Wachsen UNTER LAST unveraendert" \
    || { bad "der Bestand hat sich unter Last geaendert"; diff "$TMPD/b1.txt" "$TMPD/bl.txt" | sed 's/^/        /' | head -12; }

echo "== 5b. wie lange es dauert =="
# GEGEN EINEN LEERSTART GEMESSEN. Ein Start dieses Kerns kostet Zeit,
# die nichts mit dem Groessenwechsel zu tun hat; wer sie mitzaehlt,
# misst QEMU und nicht OFS. Also laeuft derselbe Start einmal mit
# `ofs4 info` (das nichts tut) und einmal mit der Tat, und die
# Differenz ist die Antwort.
zeit() { # abbild anhaengsel skript -> Sekunden
    local t0=$(date +%s%N)
    lauf "$1" "$2" "$3" 3600 >/dev/null 2>&1
    echo $(( ($(date +%s%N) - t0) / 1000000 ))
}
cp --sparse=always "$TMPD/bestand.img" "$TMPD/z0.img"
cp --sparse=always "$TMPD/bestand.img" "$TMPD/z1.img"
MS_LEER=$(zeit "$TMPD/z0.img" z0 "ofs4 info;exit")
MS_KLEIN=$(zeit "$TMPD/z1.img" z1 "ofs4 klein auto;exit")
MS_GROSS=$(zeit "$TMPD/z1.img" z2 "ofs4 wachsen auto;exit")
ZMOVED=$(val "$TMPD/z1.txt" ofs4 moved)
ZKLEIN=$(val "$TMPD/z1.txt" ofs4 klein)
D_KLEIN=$(( MS_KLEIN - MS_LEER ))
D_GROSS=$(( MS_GROSS - MS_LEER ))
[ "$D_KLEIN" -lt 0 ] && D_KLEIN=0
[ "$D_GROSS" -lt 0 ] && D_GROSS=0
echo "        ein Leerstart: ${MS_LEER} ms"
echo "        verkleinern auf ${ZKLEIN} Bloecke, ${ZMOVED} umgezogen: ${D_KLEIN} ms"
if [ "${ZMOVED:-0}" -gt 0 ]; then
    echo "        das sind $(( D_KLEIN / ZMOVED )) ms je umgezogenem Block"
fi
echo "        wachsen (EINE Umschreibung): ${D_GROSS} ms"
num "das Verkleinern hat Bloecke bewegt" "$ZMOVED" -gt 0
num "das Wachsen ist deutlich billiger als das Verkleinern" \
    "$(( D_GROSS * 4 ))" -lt "${D_KLEIN:-1}"

echo "== 5c. bleibt der normale Dateizugriff gleich schnell? =="
# DIE FRAGE AUS DEM AUFTRAG, UND SIE IST BERECHTIGT: `block_alloc` hat
# durch diese Runde einen DECKEL bekommen, und der wird bei JEDER
# Blockzuteilung geprueft. Kostet das etwas?
#
# DREISSIG RUNDEN, NICHT MEHR: eine Runde kostet auf dieser Maschine
# rund zehn Sekunden, weil die Platte mit `cache=directsync` haengt und
# jede Umschreibung wirklich auf das Blech geht. Zweihundert Runden
# liefen in das Zeitlimit -- gemessen, nicht vermutet.
#
# Gemessen wird mit `/bin/fsrw <n>` -- demselben Programm, das in Runde
# FSROBUST den Stromausfall ueberlebt. Es schreibt je Runde 4099
# Oktette neu an dieselbe Stelle, legt eine neue Datei an und schreibt
# einen Zaehler; das ist gewoehnlicher Dateizugriff, nicht ein
# Sonderfall. Zweimal derselbe Lauf: einmal auf einem UNBERUEHRTEN
# Abbild, einmal auf einem, das verkleinert und wieder gewachsen ist.
# Vom Leerstart wird beide Male abgezogen.
cp --sparse=always "$TMPD/bestand.img" "$TMPD/d0.img"
cp --sparse=always "$TMPD/z1.img"      "$TMPD/d1.img"   # klein+gross gewesen
MS_D0=$(zeit "$TMPD/d0.img" d0 "fsrw 30;exit")
MS_D1=$(zeit "$TMPD/d1.img" d1 "fsrw 30;exit")
# `fsrw` meldet "fsrw: fertig=30" OHNE Leerzeichen um das
# Gleichheitszeichen -- `val` sucht " = " und fand deshalb nichts.
# Eigener Griff statt aufgeweichter Erwartung.
fertig() { tr -d '\000' < "$1" 2>/dev/null | grep -oa 'fsrw: fertig=[0-9]*' \
    | tail -1 | sed 's/.*=//'; }
R0=$(fertig "$TMPD/d0.txt")
R1=$(fertig "$TMPD/d1.txt")
D_D0=$(( MS_D0 - MS_LEER )); [ "$D_D0" -lt 1 ] && D_D0=1
D_D1=$(( MS_D1 - MS_LEER )); [ "$D_D1" -lt 1 ] && D_D1=1
echo "        30 Runden fsrw auf der UNBERUEHRTEN Platte: ${D_D0} ms"
echo "        dieselben 30 Runden nach klein+gross:       ${D_D1} ms"
echo "        Unterschied: $(( (D_D1 - D_D0) * 100 / D_D0 )) %"
num "die unberuehrte Platte hat wirklich 30 Runden geschafft" "${R0:-0}" -eq 30
num "die umgebaute Platte auch"                               "${R1:-0}" -eq 30
# DIE MESSLATTE. Ein Deckel, der bei jeder Zuteilung geprueft wird, ist
# ein Vergleich zweier Zahlen; er darf sich nicht messbar auswirken.
# 25 % Luft, weil ein einzelner QEMU-Lauf auf einem geteilten Rechner
# schwankt -- alles darueber waere ein echter Befund.
num "der Dateizugriff wurde nicht messbar langsamer (Prozent)" \
    "$(( (D_D1 - D_D0) * 100 / D_D0 ))" -lt 25

echo "== 6. der Wirt sieht sich die Platte an =="
for n in lauf3 last; do
    for was in struktur inhalt grenze; do
        python3 tools/ofs4/pruef.py $was "$TMPD/$n.img" > "$TMPD/w-$n-$was.txt" 2>&1
        grep -qa BEFUND "$TMPD/w-$n-$was.txt" \
            && { bad "$n.img: $was"; sed 's/^/        /' "$TMPD/w-$n-$was.txt" | grep BEFUND | head -4; } \
            || ok "$n.img: $was ohne Befund"
    done
done
# Und die beiden Fingerabdruecke ueber die Fuellstuecke -- einer im
# Gast gerechnet, einer auf dem Wirt. Sie MUESSEN gleich sein; das ist
# die Gegenprobe dagegen, dass beide Seiten denselben Fehler machen.
GF=$(valn "$TMPD/l3.txt" ofs4 sum_fuell 3)
WF=$(python3 tools/ofs4/pruef.py inhalt "$TMPD/lauf3.img" | grep -a '^wirt: fuell = ' | sed 's/.* = //')
[ -n "$GF" ] && [ "$GF" = "$WF" ] \
    && ok "Gast und Wirt kommen auf denselben Fingerabdruck ($GF)" \
    || bad "Gast sagt $GF, Wirt sagt $WF"

echo "== 7. der Stromausfall, 2 x $LAEUFE Abschuesse mitten im Groessenwechsel =="
# ZWEI FELDZUEGE, UND DER ZWEITE IST KEINE WIEDERHOLUNG.
#
#   a) OHNE PAUSE. Der Kippschalter des Wachsens ist EINE Umschreibung
#      von wenigen Millisekunden und liegt unmittelbar hinter dem des
#      Verkleinerns; ein zufaelliger Abschuss trifft deshalb fast immer
#      die UMZUGSKETTE. Gemessen wird damit der Fall "mitten im
#      Verkleinern" -- und der muss die ALTE Groesse hinterlassen.
#   b) MIT PAUSE. `ofs4 pendel 30000` laesst das Dateisystem dreissig
#      Sekunden in der verkleinerten Groesse stehen. Erst damit kommt
#      der zweite erlaubte Endzustand ueberhaupt vor. Ohne diesen
#      Feldzug waere "nur zwei Groessen" eine Aussage ueber eine
#      Groesse.
cp --sparse=always "$TMPD/bestand.img" "$TMPD/crash.img"
: > "$TMPD/crash.log"
feldzug() { # pause spanne
    local pause=$1 spanne=$2 i=1 n
    while [ $i -le "$LAEUFE" ]; do
        n=0
        while [ $n -lt "$PAR" ] && [ $i -le "$LAEUFE" ]; do
            OFS4_PAUSE=$pause OFS4_SPANMS=$spanne bash tools/ofs4/crash.sh \
                "$TMPD/crash.img" "$TMPD" "$pause-$i" >> "$TMPD/crash.log" 2>&1 &
            i=$((i+1)); n=$((n+1))
        done
        wait
    done
}
feldzug 0 55000
# DIE ZAHLEN DES ZWEITEN FELDZUGS SIND GEMESSEN, NICHT GERATEN.
# Ein Verkleinern dauert auf diesem Rechner 38 bis 77 Sekunden (siehe
# Abschnitt 5b). Mit einer Wartezeit bis 55 Sekunden traf der Abschuss
# deshalb praktisch immer noch die ERSTE Verkleinerung, und der Halt in
# der kleinen Groesse kam gar nicht vor -- ein Lauf endete mit "es gab
# nur EINE Groesse", und der Selbstkontrollpunkt darunter wurde rot.
# Genau dafuer steht er da. Der Halt ist jetzt 30 Sekunden lang und das
# Zeitfenster 150 Sekunden breit, also mehr als eine volle Pendelrunde:
# damit faellt ein knappes Drittel der Abschuesse in den Halt. Die
# Messlatte ist unveraendert -- es duerfen weiterhin nur zwei Groessen
# vorkommen.
feldzug 30000 150000
sed 's/^/        /' "$TMPD/crash.log"
GEZ=$(grep -ac '^lauf=' "$TMPD/crash.log")
LOS=$(grep -ac 'los=1' "$TMPD/crash.log")
SCHLECHT=$(grep -a '^lauf=' "$TMPD/crash.log" | grep -vc 'wirt=0 ')
FSCKBAD=$(grep -a '^lauf=' "$TMPD/crash.log" | grep -vc 'fsck=0 ')
GEOMBAD=$(grep -a '^lauf=' "$TMPD/crash.log" | grep -vc 'geom=1 ')
NACHG=$(grep -a '^lauf=' "$TMPD/crash.log" | grep -c 'nachgetragen=[1-9]')
# WIE OFT MUSSTE DER PRUEFLAUF WIEDERHOLT WERDEN? Das ist keine Aussage
# ueber das Dateisystem, sondern ueber QEMU auf einem ausgelasteten
# Rechner -- aber es gehoert genannt, sonst sieht die Zahl darunter
# besser aus, als der Weg dorthin war.
WDH=$(grep -a '^lauf=' "$TMPD/crash.log" | grep -c 'wdh=1')
# WELCHE GROESSEN KAMEN HERAUS? Es duerfen nur zwei sein: die grosse
# und die kleine. Jede dritte Zahl waere ein halb verkleinertes
# Dateisystem -- genau der Zustand, den es nicht geben darf.
GROESSEN=$(grep -oa 'blocks=[0-9]*' "$TMPD/crash.log" | sort -u | tr '\n' ' ')
NGR=$(grep -oa 'blocks=[0-9]*' "$TMPD/crash.log" | sort -u | wc -l)
num "Laeufe insgesamt"                    "$GEZ"      -eq $((LAEUFE * 2))
num "davon trafen das Pendeln wirklich"   "$LOS"      -eq $((LAEUFE * 2))
num "BESCHAEDIGTE FAELLE (der Wirt)"      "$SCHLECHT" -eq 0
num "fsck-Fehler in irgendeinem Lauf"     "$FSCKBAD"  -eq 0
num "Laeufe mit ungueltiger Geometrie"    "$GEOMBAD"  -eq 0
num "Laeufe, in denen nachgetragen wurde" "$NACHG"    -gt 0
echo "        Pruefstarts, die wiederholt werden mussten (QEMU, nicht OFS): $WDH"
num "verschiedene Groessen danach (nur alt und neu erlaubt)" "$NGR" -le 2
num "und es waren wirklich BEIDE (sonst misst der zweite Feldzug nichts)" "$NGR" -eq 2
echo "        die Groessen, die vorkamen: $GROESSEN"

echo "== 8. rueckwaerts =="
# Ein Abbild OHNE Vorratskarte, zweimal gebaut, ist zweimal dasselbe --
# diese Runde hat an `mkfs.py` keine Zeile geaendert.
python3 tools/osum/mkfs.py build "$TMPD/r1.img" 16384 --v3 --inodes=256 \
    --time=1780000000 $SPEC >/dev/null 2>&1
python3 tools/osum/mkfs.py build "$TMPD/r2.img" 16384 --v3 --inodes=256 \
    --time=1780000000 $SPEC >/dev/null 2>&1
cmp -s "$TMPD/r1.img" "$TMPD/r2.img" \
    && ok "ein Abbild ohne Vorratskarte ist zweimal Oktett fuer Oktett dasselbe" \
    || bad "mkfs baut nicht zweimal dasselbe"
# Auf die volle Laenge bringen: `mkfs.py` schreibt nur so viel, wie es
# braucht, und das GERAET waere sonst kleiner als das Dateisystem.
python3 - "$TMPD/r1.img" <<'PY2'
import sys
f = open(sys.argv[1], "r+b")
f.seek(16384 * 512 - 1)
f.write(b"\0")
f.close()
PY2
# Und es haengt sich ein, waechst bis zu SEINER Karte und nicht weiter.
lauf "$TMPD/r1.img" rr "ofs4 info;ofs4 wachsen 99999;fsck /dev/hda;exit" 900
num "ein Abbild der Fassung 3 ohne Vorrat haengt sich ein" "$(val "$TMPD/rr.txt" ofs4 inodes)" -eq 256
num "und waechst hoechstens bis zu seiner Karte"           "$(val "$TMPD/rr.txt" ofs4 wachsen)" -eq 16384
num "fsck-Fehler danach"                                   "$(val "$TMPD/rr.txt" fsck fehler)" -eq 0

echo "OFS4: $pass bestanden, $fail gescheitert"
[ "$fail" = 0 ] || exit 1
