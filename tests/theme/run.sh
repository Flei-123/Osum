#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tests/theme/run.sh -- DIE ABNAHME DER RUNDE THEME.
#
# Zehn Abschnitte. Der rote Faden ist derselbe wie in den Runden davor:
# zu jeder Zusage gehoert eine GEGENPROBE, und eine Zahl, die nur die
# gepruefte Sache selbst erzeugt, ist keine Messung.
#
#   1. BAUEN. Kernel und Programme aus dem festgenagelten Uebersetzer.
#   2. KEINE FARBE IM ZEICHENCODE (tests/theme/rawcolour.py). Die
#      Zusage der Runde als Eigenschaft des QUELLTEXTS, mechanisch
#      geprueft -- und mit der Zahl von vorher daneben, sonst ist die
#      Null nichts wert.
#   3. DIE sRGB-KENNLINIE. Der Kernel rechnet 256 Werte in ganzen
#      Zahlen aus; `tools/theme/model.py` rechnet dieselben 256 aus,
#      und ein drittes Mal wird gegen die FLIESSKOMMA-Formel von WCAG
#      gerechnet. Zwei Umsetzungen koennen sich einig und beide falsch
#      sein; gegen die Formel geht das nicht.
#   4. DIE DREI EBENEN, fuer jedes der fuenf Schemata, hell und dunkel:
#      Rampen, Rollen, Komponenten -- Marke fuer Marke gegen das
#      Modell. UND JEDE KOMPONENTE MIT IHRER ROLLE: eine Komponente,
#      deren Farbe zu keiner Rolle gehoert, faellt hier auf.
#   5. DIE KONTRASTTABELLE. Jede Text-auf-Flaeche-Paarung, die das
#      System erzeugt, gegen 4,5:1 -- in HELL und in DUNKEL, fuer alle
#      fuenf Schemata.
#   6. DIE AKZENTFARBE. Drei Farben, die durchgehen, und drei, die es
#      nicht tun. Gegenprobe zur Zusage "die Oberflaeche zeigt es an":
#      bei einer Farbe, die den Kontrast bricht, MUSS `accent_exact`
#      falsch werden und die Farbe sich bewegen.
#   7. KEIN HALBES FENSTER. Bank einrasten, mittendrin umschalten, und
#      die Farbe MUSS dieselbe bleiben -- die Gegenprobe steht in
#      derselben Ausgabe: die LIVE-Bank hat sich sehr wohl geaendert.
#   8. DIE ZEITEN. Aufloesen, Nachsehen, Neuladen -- und dann dasselbe
#      im laufenden Schreibtisch, mit einem Fenster, das wirklich neu
#      gemalt wird, samt der Flaeche.
#   9. DIE BILDER. Sieben Abbilder, die sich in drei Zeilen von
#      /etc/theme.conf unterscheiden, sieben Bildschirmfotos --
#      und nachgerechnet, dass die Farben darin die aufgeloesten
#      Marken SIND.
#  10. DIE GEGENPROBEN. Ohne /etc/theme.conf faellt das System auf die
#      eingebaute Rampe zurueck; eine Schemadatei mit falschen
#      Schluesseln wird GEZAEHLT und nicht verschluckt.
#
# Verwendung:  bash tests/theme/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { local name=$1 wert=$2 op=$3 want=$4
    if [ -z "$wert" ]; then bad "$name: keine Zahl (erwartet $op $want)"; return; fi
    if [ "$wert" -"$op" "$want" ] 2>/dev/null; then ok "$name: $wert"
    else bad "$name: $wert, erwartet $op $want"; fi
}
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
feld() { grep -a "^$2 " "$1" | head -1 | awk "{print \$$3}"; }

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || {
    echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "THEME: uebersprungen, qemu-system-x86_64 ist nicht da"
    exit 0
fi

SCHEMES="day paper night midnight contrast"

# ---------------------------------------------------------------- 1. bauen
echo "== 1. bauen"
if bash tests/theme/build.sh "$TMPD" > "$TMPD/build.log" 2>&1; then
    ok "Kernel und Programme gebaut ($(grep -c Oktette "$TMPD/build.log") Stueck)"
else
    bad "tests/theme/build.sh fehlgeschlagen"
    tail -20 "$TMPD/build.log"
    exit 1
fi

lauf() { # name kommandozeile [zeitlimit]
    local name=$1 zeile=$2 tl=${3:-300}
    cp -f "$TMPD/disk.img" "$TMPD/live-$name.img"
    timeout "$tl" qemu-system-x86_64 -kernel "$TMPD/k.mb" -m 256 \
        -append "$zeile" -serial "file:$TMPD/$name.txt" -display none \
        -no-reboot -vga std \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}

foto() { # name abbild kommandozeile
    local name=$1 img=$2 zeile=$3
    local sock="$TMPD/s-$name.sock"
    rm -f "$sock" "$TMPD/$name.ppm" "$TMPD/$name.txt"
    cp -f "$img" "$TMPD/l-$name.img"
    timeout 400 qemu-system-x86_64 -kernel "$TMPD/k.mb" -m 256 \
        -append "$zeile" -serial "file:$TMPD/$name.txt" -display none \
        -no-reboot -vga std -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/l-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$! i=0
    while [ $i -lt 2000 ]; do
        grep -qa '^wm: hold' "$TMPD/$name.txt" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.15; i=$((i+1))
    done
    python3 tools/gfx/screenshot.py "$sock" "$TMPD/$name.ppm" 25 >/dev/null 2>&1
    wait "$pid"
    rm -f "$sock"
}

# ------------------------------------------------- 2. keine Farbe im Code
echo
echo "== 2. keine Farbe im Zeichencode"
aus=$(python3 tests/theme/rawcolour.py . 2>&1)
# Die Zeile lautet: rawcolour: files N tokens N raw N
roh=$(echo "$aus" | awk '/^rawcolour:/ {print $7}')
mrk=$(echo "$aus" | awk '/^rawcolour:/ {print $5}')
num "rohe Farbwerte im Zeichencode" "$roh" eq 0
num "Marken, die statt dessen benutzt werden" "$mrk" ge 100
# DIE GEGENPROBE ZUR NULL: derselbe Pruefer auf den Stand VOR dieser
# Runde. Findet er dort auch nichts, prueft er nichts.
#
# RUNDE MERGE: DER STAND "VOR DER RUNDE" WIRD JETZT AM PRUEFER SELBST
# FESTGEMACHT. Vorher war es "der juengste Commit, dessen Meldung nicht
# mit THEME anfaengt" -- solange die Runde die Spitze des Zweiges war,
# stimmte das, und in dem Augenblick, in dem irgendein anderer Commit
# obendrauf kam, zeigte es auf einen Baum, der die Null laengst hatte.
# Der Lauf meldete dann, der Pruefer pruefe nichts, und der Pruefer war
# in Ordnung. Der Commit, der `rawcolour.py` ANGELEGT hat, ist der
# Anfang dieser Runde; sein Elternteil ist der Stand davor, und das
# bleibt richtig, egal was seither obendrauf liegt.
VOR=$(git rev-parse --verify \
    "$(git log --diff-filter=A --format=%H -- tests/theme/rawcolour.py | tail -1)^" \
    2>/dev/null)
if [ -n "$VOR" ]; then
    rm -rf "$TMPD/vor"; mkdir -p "$TMPD/vor"
    git archive "$VOR" kernel/user kernel/wm.fi 2>/dev/null \
        | tar -x -C "$TMPD/vor" 2>/dev/null
    vorn=$(python3 tests/theme/rawcolour.py "$TMPD/vor" 2>&1 \
        | awk '/^rawcolour:/ {print $7}')
    num "derselbe Pruefer auf dem Stand vor der Runde" "$vorn" ge 1
else
    bad "der Stand vor der Runde liess sich nicht finden"
fi

# ------------------------------------------------ 3. die sRGB-Kennlinie
echo
echo "== 3. die sRGB-Kennlinie, drei Mal gerechnet"
lauf srgb "osum nokbd nosched noproc nofs script=themetest srgb"
grep -a '^SRGB ' "$TMPD/srgb.txt" | awk '{print $2, $3}' > "$TMPD/srgb.os"
python3 tools/theme/model.py srgb > "$TMPD/srgb.py"
num "der Kernel meldet 256 Werte" "$(wc -l < "$TMPD/srgb.os")" eq 256
if diff -q "$TMPD/srgb.os" "$TMPD/srgb.py" >/dev/null; then
    ok "alle 256 stimmen mit tools/theme/model.py ueberein"
else
    bad "Osum und model.py sind sich uneinig: $(diff "$TMPD/srgb.os" "$TMPD/srgb.py" | head -4 | tr '\n' ' ')"
fi
# und beide gegen die Formel selbst
python3 - "$TMPD/srgb.os" <<'PYEOF' > "$TMPD/srgb.err"
import sys
S = 1 << 24
worst = 0.0
wc = -1
for line in open(sys.argv[1]):
    c, v = line.split()
    c, v = int(c), int(v)
    x = c / 255.0
    ref = x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4
    d = abs(v / S - ref)
    if d > worst:
        worst, wc = d, c
print("%.10f %d" % (worst, wc))
PYEOF
werr=$(awk '{print $1}' "$TMPD/srgb.err")
wat=$(awk '{print $2}' "$TMPD/srgb.err")
if python3 -c "import sys; sys.exit(0 if float('$werr') < 1e-5 else 1)"; then
    ok "groesster Abstand zur WCAG-Formel: $werr (bei c=$wat)"
else
    bad "groesster Abstand zur WCAG-Formel: $werr (bei c=$wat)"
fi

# ------------------------------------------- 4. + 5. Marken und Kontraste
echo
echo "== 4. die drei Ebenen, fuenf Schemata, hell und dunkel"
for s in $SCHEMES; do
    lauf "s-$s" "osum nokbd nosched noproc nofs script=themetest scheme $s" 400
    for m in light dark; do
        # den Block dieses Modus herausschneiden
        awk -v want="MODE_$m" '
            /^MODE_/ { on = ($0 == want) }
            on { print }' "$TMPD/s-$s.txt" > "$TMPD/blk-$s-$m.txt"
        python3 tools/theme/model.py tokens "assets/schemes/$s.scheme" $m \
            > "$TMPD/mdl-$s-$m.txt" 2>/dev/null
        grep -a '^COMP ' "$TMPD/blk-$s-$m.txt" \
            | awk '{print $2, $3, $4, $5}' > "$TMPD/os-$s-$m.txt"
        awk '{print $1, $2, $3, $4}' "$TMPD/mdl-$s-$m.txt" \
            | grep -v '^accent' > "$TMPD/py-$s-$m.txt"
        n=$(wc -l < "$TMPD/os-$s-$m.txt")
        if [ "$n" -ne 41 ]; then
            bad "$s/$m: $n Komponentenmarken statt 41"
        elif diff -q "$TMPD/os-$s-$m.txt" "$TMPD/py-$s-$m.txt" >/dev/null; then
            ok "$s/$m: 41 Komponentenmarken und ihre Rollen stimmen"
        else
            bad "$s/$m: $(diff "$TMPD/os-$s-$m.txt" "$TMPD/py-$s-$m.txt" | head -4 | tr '\n' ' ')"
        fi
        # die semantische Ebene
        grep -a '^SEM ' "$TMPD/blk-$s-$m.txt" | awk '{print $2, $3, $4}' \
            > "$TMPD/oss-$s-$m.txt"
        python3 tools/theme/model.py semantic "assets/schemes/$s.scheme" $m \
            > "$TMPD/pys-$s-$m.txt" 2>/dev/null
        if diff -q "$TMPD/oss-$s-$m.txt" "$TMPD/pys-$s-$m.txt" >/dev/null; then
            ok "$s/$m: 23 Rollen stimmen"
        else
            bad "$s/$m Rollen: $(diff "$TMPD/oss-$s-$m.txt" "$TMPD/pys-$s-$m.txt" | head -4 | tr '\n' ' ')"
        fi
    done
done

echo
echo "== 5. die Kontrasttabelle"
for s in $SCHEMES; do
    for m in light dark; do
        python3 tools/theme/model.py contrast "assets/schemes/$s.scheme" $m \
            > "$TMPD/con-$s-$m.txt" 2>/dev/null
        # a) Osum und das Modell rechnen dieselben Verhaeltnisse aus
        grep -a '^PAIR ' "$TMPD/blk-$s-$m.txt" | awk '{print $2, $3, $6}' \
            > "$TMPD/conos-$s-$m.txt"
        awk '{print $1, $2, $6}' "$TMPD/con-$s-$m.txt" \
            > "$TMPD/conpy-$s-$m.txt"
        if diff -q "$TMPD/conos-$s-$m.txt" "$TMPD/conpy-$s-$m.txt" >/dev/null; then
            ok "$s/$m: 21 Kontrastverhaeltnisse stimmen mit dem Modell"
        else
            bad "$s/$m Kontrast: $(diff "$TMPD/conos-$s-$m.txt" "$TMPD/conpy-$s-$m.txt" | head -3 | tr '\n' ' ')"
        fi
        # b) und sie erfuellen die Schwelle
        durch=$(awk '$7 == 0' "$TMPD/con-$s-$m.txt" | wc -l)
        schlecht=$(awk '$7 == 0 {printf "%s auf %s (%.2f) ", $1, $2, $6/100}' \
            "$TMPD/con-$s-$m.txt")
        if [ "$durch" -eq 0 ]; then
            kl=$(awk '$3 == "normal" {if (min == "" || $6 < min) min = $6} END {print min}' \
                "$TMPD/con-$s-$m.txt")
            ok "$s/$m: jede Paarung erfuellt WCAG, schlechteste $kl"
        else
            bad "$s/$m: $durch Paarungen unter der Schwelle -- $schlecht"
        fi
    done
done

# ---------------------------------------------------- 6. die Akzentfarbe
echo
echo "== 6. die Akzentfarbe und was die Oberflaeche darueber sagt"
GUT="2563eb 7c3aed a16207"
SCHLECHT="ffff00 22c55e ffffff"
# ZWEI LAEUFE UND NICHT EINER. Sechs Farben auf einer Zeile kamen leer
# zurueck: die Kommandozeile geht ueber `script=` durch die Shell im
# Kernel, und die hat eine Grenze, die sie nicht meldet. Ein Test, der
# an einer stillschweigenden Grenze scheitert, sieht aus wie ein
# kaputtes Programm und ist keins.
lauf accgut "osum nokbd nosched noproc nofs script=themetest accent day $GUT" 500
lauf accbad "osum nokbd nosched noproc nofs script=themetest accent day $SCHLECHT" 500
# Reihenfolge in der Ausgabe: je Farbe erst hell, dann dunkel.
i=0
for a in $GUT; do
    zeile=$(grep -a '^ACCENT ' "$TMPD/accgut.txt" | sed -n "$((i*2+1))p")
    exakt=$(echo "$zeile" | awk '{print $5}')
    verschoben=$(echo "$zeile" | awk '{print $6}')
    rt=$(echo "$zeile" | awk '{print $7}')
    ru=$(echo "$zeile" | awk '{print $8}')
    if [ "$exakt" = "1" ] && [ "$verschoben" = "0" ]; then
        ok "#$a hell: unveraendert uebernommen, Text $rt, Flaeche $ru"
    else
        bad "#$a hell: haette durchgehen muessen (exakt=$exakt bewegt=$verschoben)"
    fi
    i=$((i+1))
done
i=0
for a in $SCHLECHT; do
    zeile=$(grep -a '^ACCENT ' "$TMPD/accbad.txt" | sed -n "$((i*2+1))p")
    gewuenscht=$(echo "$zeile" | awk '{print $2}')
    wirklich=$(echo "$zeile" | awk '{print $3}')
    exakt=$(echo "$zeile" | awk '{print $5}')
    verschoben=$(echo "$zeile" | awk '{print $6}')
    rt=$(echo "$zeile" | awk '{print $7}')
    ru=$(echo "$zeile" | awk '{print $8}')
    if [ "$exakt" = "0" ] && [ "$verschoben" -ge 1 ] 2>/dev/null; then
        ok "#$gewuenscht hell: verschoben auf #$wirklich ($verschoben Stufen), danach $rt / $ru"
    else
        bad "#$gewuenscht hell: haette anschlagen muessen (exakt=$exakt bewegt=$verschoben)"
    fi
    # und danach erfuellt es die Schwelle wirklich
    num "  ... Text auf #$wirklich" "$rt" ge 450
    num "  ... #$wirklich auf der Flaeche" "$ru" ge 300
    i=$((i+1))
done

# ------------------------------------------------- 7. kein halbes Fenster
echo
echo "== 7. kein Fenster halb hell und halb dunkel"
lauf latch "osum nokbd nosched noproc nofs script=themetest latch"
vor=$(feld "$TMPD/latch.txt" L_BEFORE 2)
innen=$(feld "$TMPD/latch.txt" L_INNER 2)
danach=$(feld "$TMPD/latch.txt" L_AFTER 2)
stale=$(feld "$TMPD/latch.txt" L_STALE 2)
frisch=$(feld "$TMPD/latch.txt" L_FRESH 2)
fstale=$(grep -a '^L_FRESH ' "$TMPD/latch.txt" | awk '{print $3}')
if [ "$vor" = "$innen" ]; then
    ok "die Farbe bleibt im laufenden Bild dieselbe ($vor)"
else
    bad "das Bild hat mitten drin die Farbe gewechselt: $vor -> $innen"
fi
if [ "$danach" != "$vor" ]; then
    ok "GEGENPROBE: die lebende Bank hat sich sehr wohl geaendert ($danach)"
else
    bad "die lebende Bank hat sich nicht geaendert -- der Test prueft nichts"
fi
num "das Bild meldet sich danach als veraltet" "$stale" eq 1
if [ "$frisch" = "$danach" ] && [ "$fstale" = "0" ]; then
    ok "das naechste Bild rastet frisch ein ($frisch, nicht veraltet)"
else
    bad "das naechste Bild rastet nicht frisch ein ($frisch/$fstale)"
fi

# ------------------------------------------------------------ 8. Zeiten
echo
echo "== 8. die Zeiten"
lauf zeit "osum nokbd nosched noproc nofs script=themetest time" 600
tres=$(feld "$TMPD/zeit.txt" T_RESOLVE 2)
tload=$(feld "$TMPD/zeit.txt" T_RELOAD 2)
tpoll=$(feld "$TMPD/zeit.txt" T_POLL 2)
ok "aufloesen (Rampen, Bindung, Kontrastsuche, veroeffentlichen): $((tres / 1000)) us"
ok "nachsehen im Ruhezustand (eine Datei lesen und vergleichen): $((tpoll / 1000)) us"
ok "vollstaendig neu laden (drei Dateien und aufloesen): $((tload / 1000)) us"
num "aufloesen bleibt unter einer Millisekunde" "$tres" lt 1000000

foto gui "$TMPD/disk.img" \
    "gfx wm wmhold desk themegui nokbd nosched noproc nofs"
gsw=$(grep -a '^G_AVG ' "$TMPD/gui.txt" | awk '{print $2}')
gdet=$(grep -a '^G_AVG ' "$TMPD/gui.txt" | awk '{print $4}')
gpnt=$(grep -a '^G_AVG ' "$TMPD/gui.txt" | awk '{print $6}')
gpx=$(grep -a '^G_PX ' "$TMPD/gui.txt" | awk '{print $2}')
gall=$(grep -a '^G_PX ' "$TMPD/gui.txt" | awk '{print $3}')
gbase=$(grep -a '^G_BASE ' "$TMPD/gui.txt" | awk '{print $3}')
num "Umschaltvorgaenge im laufenden Schreibtisch" "$gsw" ge 15
ok "erkennen, schnellster Lauf: $((gdet / 1000)) us"
ok "neu malen, schnellster Lauf: $((gpnt / 1000)) us fuer $gpx von $gall Bildpunkten"
ok "GEGENPROBE: ein gewoehnliches Vollbild ohne Themenwechsel: $((gbase / 1000)) us"
# Ein Umschalten darf nicht mehr kosten als ein Vollbild -- es IST eines.
# Der Faktor ist 3 und nicht 2, und der Grund steht in
# docs/ROUNDTHEME.md: auf diesem Bildschirm laufen fuenf Prozesse auf
# EINEM Prozessor, und der Schreibtisch und die Taskleiste malen
# waehrend des Umschaltens ihre eigenen Flaechen. Der Mittelwert
# schwankt darum um mehr als den Faktor zwei; die Aussage, die
# tragfaehig ist, lautet "dieselbe Groessenordnung wie ein Vollbild",
# und nicht "gleich".
if [ "$gpnt" -lt $((gbase * 3)) ]; then
    ok "das Umschalten liegt in der Groessenordnung eines Vollbilds"
else
    bad "das Umschalten kostet $gpnt ns gegen $gbase ns fuer ein Vollbild"
fi

# ------------------------------------------------------------ 9. Bilder
echo
echo "== 9. sieben Bildschirme, drei Zeilen Unterschied"
# WAS HIER GEPRUEFT WIRD, und warum nicht "die haeufigste Farbe ist X":
# welche der drei Flaechenmarken den Schirm anfuehrt, haengt daran, wie
# gross die Fenster gerade stehen -- bei `dark` waren es in einem Lauf
# 30 % `surface-sunken` und im naechsten 26 % `surface`, und beides ist
# richtig. Die tragfaehige Zusage lautet: die Marke `surface` DIESES
# Schemas in DIESEM Modus gehoert zu den drei haeufigsten Farben des
# Bildes. Was sie ist, sagt das Modell und nicht dieses Skript.
marke_von() { # schema modus rolle [akzent]
    python3 tools/theme/model.py semantic "assets/schemes/$1.scheme" "$2" \
        ${4:+"$4"} | awk -v r="$3" '$2 == r {print $3}'
}
shot() { # name schema modus akzent
    local name=$1 sch=$2 mod=$3 akz=$4
    bash tests/theme/image.sh "$TMPD" "$sch" "$mod" "$akz" \
        "$TMPD/img-$name.img" > /dev/null 2>&1 || {
        bad "$name: das Abbild liess sich nicht bauen"; return; }
    foto "shot-$name" "$TMPD/img-$name.img" \
        "gfx wm wmhold desk einst themeshot nokbd nosched noproc nofs"
    local got want
    got=$(python3 tests/theme/pixel.py "$TMPD/shot-$name.ppm" --top 3 2>/dev/null)
    want=$(marke_von "$sch" "$mod" surface "$akz")
    if [ -z "$got" ]; then
        bad "$name: kein Bildschirmfoto"
        return
    fi
    if echo "$got" | grep -qi "$want"; then
        ok "$name: surface (#$want) ist unter den drei haeufigsten ($got)"
    else
        bad "$name: #$want fehlt unter den drei haeufigsten -- $got"
    fi
}
shot light    day      light ""
shot dark     day      dark  ""
shot green    day      light 22c55e
shot violet   day      light 7c3aed
shot gold     paper    light a16207
shot contrast contrast light ""
shot midnight midnight dark  ""

# DIE ZUSAGE HINTER DEN BILDERN: die Farben darin SIND die aufgeloesten
# Marken. Nicht aehnlich -- dieselben. Die erwartete Akzentfarbe kommt
# aus dem MODELL und nicht aus diesem Skript; bei `green` ist sie die
# VERSCHOBENE (#1ca54e und nicht #22c55e), und genau das ist die
# Aussage: was die Kontrastpruefung entschieden hat, steht im Bild.
akzent_von() { # schema modus [akzent]
    python3 tools/theme/model.py semantic "assets/schemes/$1.scheme" "$2" \
        ${3:+"$3"} | awk '$2 == "accent" {print $3}'
}
for v in "light day light" "green day light 22c55e" \
         "violet day light 7c3aed" "dark day dark" \
         "gold paper light a16207" "midnight midnight dark"; do
    set -- $v
    name=$1
    erwartet=$(akzent_von "$2" "$3" "${4:-}")
    if python3 tests/theme/pixel.py "$TMPD/shot-$name.ppm" --has "$erwartet" \
        >/dev/null 2>&1; then
        ok "$name: die aufgeloeste Akzentmarke #$erwartet steht im Bild"
    else
        bad "$name: #$erwartet steht NICHT im Bild"
    fi
done

# ------------------------------------------------------- 10. Gegenproben
echo
echo "== 10. die Gegenproben"
# a) ohne /etc/theme.conf bleibt die eingebaute Rampe stehen
python3 tools/osum/mkfs.py build "$TMPD/leer.img" 4096 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ "/bin/themetest=$TMPD/themetest.elf" "/bin/sh=$TMPD/sh.elf" \
    "/bin/echo=$TMPD/echo.elf" "/bin/ls=$TMPD/ls.elf" \
    > "$TMPD/mkfs-leer.log" 2>&1 || bad "das leere Abbild liess sich nicht bauen"
cp -f "$TMPD/leer.img" "$TMPD/live-leer.img"
timeout 200 qemu-system-x86_64 -kernel "$TMPD/k.mb" -m 256 \
    -append "osum nokbd nosched noproc nofs script=themetest" \
    -serial "file:$TMPD/leer.txt" -display none -no-reboot -vga std \
    -drive "file=$TMPD/live-leer.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
lk=$(grep -a '^SCHEME ' "$TMPD/leer.txt" | head -1 | awk '{print $3}')
lb=$(grep -a '^PRIM 0 ' "$TMPD/leer.txt" | head -1 | awk '{print $3}')
num "ohne /etc/theme.conf werden 0 Schemaschluessel gelesen" "$lk" eq 0
if [ "$lb" = "ffffff" ]; then
    ok "und die eingebaute Rampe steht (neutral0 = ffffff)"
else
    bad "die eingebaute Rampe fehlt: neutral0 = $lb"
fi

# b) eine Schemadatei mit falschen Schluesseln wird GEZAEHLT
mkdir -p "$TMPD/kaputt"
cat > "$TMPD/kaputt/broken" <<'EOF'
name=Kaputt
mode=light
neutral0=ffffff
neutrl50=f8fafc
neutral999=112233
accent=zzzzzz
kein_gleichheitszeichen
EOF
cp -f "$TMPD/theme.conf" "$TMPD/theme-broken.conf"
sed -i 's/^scheme=.*/scheme=broken/' "$TMPD/theme-broken.conf"
ARGS=(build "$TMPD/kaputt.img" 4096 /lib/
      "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
      /bin/ "/bin/themetest=$TMPD/themetest.elf" "/bin/sh=$TMPD/sh.elf"
      "/bin/echo=$TMPD/echo.elf" "/bin/ls=$TMPD/ls.elf"
      /etc/ "/etc/theme.conf=$TMPD/theme-broken.conf@0644"
      /etc/schemas/ "/etc/schemas/broken=$TMPD/kaputt/broken@0644")
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$TMPD/mkfs-kaputt.log" 2>&1 \
    || bad "das kaputte Abbild liess sich nicht bauen"
cp -f "$TMPD/kaputt.img" "$TMPD/live-kaputt.img"
timeout 200 qemu-system-x86_64 -kernel "$TMPD/k.mb" -m 256 \
    -append "osum nokbd nosched noproc nofs script=themetest" \
    -serial "file:$TMPD/kaputt.txt" -display none -no-reboot -vga std \
    -drive "file=$TMPD/live-kaputt.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
kk=$(grep -a '^SCHEME ' "$TMPD/kaputt.txt" | head -1 | awk '{print $3}')
kb=$(grep -a '^SCHEME ' "$TMPD/kaputt.txt" | head -1 | awk '{print $4}')
num "aus der kaputten Datei werden 3 Schluessel gelesen" "$kk" eq 3
num "und 4 werden als unverstanden GEZAEHLT" "$kb" eq 4
n0=$(grep -a '^PRIM 0 ' "$TMPD/kaputt.txt" | head -1 | awk '{print $3}')
n1=$(grep -a '^PRIM 1 ' "$TMPD/kaputt.txt" | head -1 | awk '{print $3}')
if [ "$n0" = "ffffff" ] && [ "$n1" = "f8fafc" ]; then
    ok "was die Datei nicht setzt, behaelt den eingebauten Wert"
else
    bad "die eingebauten Werte wurden zerstoert: $n0 / $n1"
fi

# c) das Umschalten ohne Themenwechsel meldet KEINEN
p1=$(grep -a '^G_STALE ' "$TMPD/gui.txt" | awk '{print $3}')
num "Nachsehen im laufenden Betrieb (ohne Aenderung ohne Wirkung)" "$p1" ge 20

echo
echo "=================================================================="
printf "THEME: %d bestanden, %d durchgefallen\n" "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
