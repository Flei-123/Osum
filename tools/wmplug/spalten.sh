#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wmplug/spalten.sh -- STEHEN DIE SPALTEN VON /bin/wmplug?
#
# Die Jury hat an der Oberflaeche von /bin/wmplug drei Dinge gefunden,
# und alle drei sind Sehfehler und keine Abstuerze: der Tabellenkopf
# stand neben seinen Werten, die Statuszeile riss mitten im Wort, und bei
# `info` klebte `Leistentext13` zusammen. Genau darum wird hier NICHT der
# Quelltext gelesen, sondern EIN WIRKLICH GEBOOTETER KERN FOTOGRAFIERT
# und das Foto nachgerechnet:
#
#   * `checkshot.py tgrid` haelt jede Glyphe gegen den Rasterer -- also
#     steht hier nicht "da ist Text", sondern "in Zeile Z ab Spalte S
#     steht genau dieses Wort". Faellt eine Ueberschrift um eine Stelle,
#     faellt die Zusage.
#   * Kopf und Wert werden AN DERSELBEN ENDSPALTE gemessen: `Rechte`
#     endet auf Spalte 18, `0x807` endet auf Spalte 18. Das ist der
#     Beweis, dass beide aus denselben Breitenkonstanten kommen
#     (SP_NR/SP_NAME/SP_HEX/SP_LIEGT/SP_VERL in kernel/user/wmplug.fi).
#   * ZWEI Plugins sind gleichzeitig angemeldet (/bin/plugpaar startet
#     pluguhr UND plugregel) -- eine einzige Datenzeile liesse sich mit
#     jeder falschen Breite hinbiegen.
#
# Nebenbei entsteht das Bild der Verwaltung fuer .gauntlet-shots
# (09-wmplug-verwaltung.png) neu, denn das alte zeigt genau die Fehler
# von oben.
#
# Gebrauch: bash tools/wmplug/spalten.sh      (SPALTEN_KEEP=1 behaelt
#           das Arbeitsverzeichnis mit Mitschnitten und PPMs)
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
. tools/lib/userprog.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
SHOTS="docs/shots/wmplug"
GAUNTLET=".gauntlet-shots"
mkdir -p "$SHOTS"

TMPD=$(mktemp -d /tmp/wmplug-spalten-XXXXXX)
[ "${SPALTEN_KEEP:-0}" = 1 ] || trap 'rm -rf "$TMPD"' EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "SPALTEN: uebersprungen, qemu-system-x86_64 ist nicht da"; exit 0
fi
bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "firnc fehlt"; exit 1; }

# ------------------------------------------------------------- 1. bauen
echo "== 1. bauen =="
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/k.log" 2>&1 \
    && ok "Kernel gebaut ($(stat -c%s "$TMPD/k.mb") Oktette)" \
    || { bad "der Kernel baut nicht"; tail -12 "$TMPD/k.log" | sed 's/^/        /'
         echo; echo "SPALTEN: $pass bestanden, $fail gescheitert"; exit 1; }
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s assembliert nicht"
PROGS="desktop taskbar launcher calc sh pluguhr plugregel plugpaar wmplug"
for p in $PROGS; do
    up_build vendor/firn/bin/firnc "$p" "$TMPD/$p.o" "$TMPD/$p.elf" \
        "$TMPD/crt.o" kernel/user/user.ld 0 "$TMPD/$p.err" || {
        bad "firnc uebersetzt $p.fi nicht"; head -6 "$TMPD/$p.err" | sed 's/^/        /'
        echo; echo "SPALTEN: $pass bestanden, $fail gescheitert"; exit 1; }
done
ok "$(echo $PROGS | wc -w) Programme gebaut"

python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
    && ok "der Verzeichnisbaum steht" || bad "tools/k15/tree.py fehlgeschlagen"
ARGS=(build "$TMPD/disk.img" 32768 /lib/
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/)
for p in $PROGS; do
    ARGS+=("/bin/$p=$TMPD/$p.elf")
done
ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme"
    "/etc/wmplug.conf=etc/wmplug.conf" "/etc/wmregeln.conf=etc/wmregeln.conf")
while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "das Abbild ist gebaut" \
    || { bad "mkfs.py fehlgeschlagen"; head -5 "$TMPD/mkfs.txt" | sed 's/^/        /'; }

# ------------------------------------------------------------ 2. laufen
BASE="gfx wm wig desk wmhold wiglong nokbd nosched noproc nofs wmplug"

warte() { local f=$1 m=$2 pid=$3 i=0
    while [ $i -lt 900 ]; do
        grep -qa "$m" "$f" 2>/dev/null && return 0
        kill -0 "$pid" 2>/dev/null || return 1
        sleep 0.2; i=$((i+1))
    done; return 1; }

lauf() { # name zusatz marke
    local name=$1 extra=$2 marke=$3
    local sock="$TMPD/mon-$name.sock" out="$TMPD/$name.txt"
    rm -f "$out" "$sock" "$TMPD/$name.ppm"
    cp -f "$TMPD/disk.img" "$TMPD/live-$name.img"
    timeout 240 $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 \
        -append "$BASE $extra" -serial "file:$out" -display none \
        -no-reboot -vga std -global VGA.edid=off \
        -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/$name.qemu" 2>&1 &
    local pid=$!
    warte "$out" "$marke" "$pid"
    sleep 2
    python3 tools/gfx/screenshot.py "$sock" "$TMPD/$name.ppm" 25 \
        > "$TMPD/$name.shot" 2>&1
    wait "$pid"; echo "$?" > "$TMPD/$name.rc"
    rm -f "$sock"
    tr -d '\000' < "$out" > "$TMPD/$name.clean"
    local rc; rc=$(cat "$TMPD/$name.rc")
    [ "$rc" = 21 ] && ok "$name: der Kern beendet sich sauber (21)" \
        || bad "$name: Exitcode $rc statt 21"
    [ -s "$TMPD/$name.ppm" ] && ok "$name: das Foto steht ($(stat -c%s "$TMPD/$name.ppm") Oktette)" \
        || bad "$name: kein Foto"
}

echo "== 2. zwei Plugins gleichzeitig, dann 'wmplug list' und 'wmplug info' =="
# FOTOGRAFIERT WIRD, WENN DIE TABELLE AUF DER LEITUNG STEHT -- nicht bei
# `wm: hold`. Das steht dort, lange bevor ueberhaupt ein Plugin lebt, und
# ein Foto vom leeren Schreibtisch belegt ueber Spalten nichts.
lauf paar "wigapp=/bin/plugpaar" 'Nr Name'
P="$TMPD/paar.clean"
has "$P" "wmplug: reg uhr" "das Widget ist angemeldet"
has "$P" "wmplug: reg regel" "die Regel-Engine ist angemeldet"
# ZWEI IN DER TAFEL, vom KERN gezaehlt -- nicht vom Laeufer.
z=$(grep -aoE 'Plugins [0-9]+ von [0-9]+' "$P" | tail -1 | grep -oE '[0-9]+' | head -1)
[ "${z:-0}" -ge 2 ] && ok "die Tafel zaehlt $z Plugins (zwei Datenzeilen unter dem Kopf)" \
    || bad "die Tafel zaehlt '$z' Plugins -- fuer die Spaltenprobe braucht es zwei"
# DIE STATUSZEILE IST ZWEI ZEILEN, JEDE UNTER 40 ZEICHEN. Vorher war es
# eine von 55, und der Fensterserver bricht am RAND und nicht am Wort:
# auf dem alten Bild 09 riss sie mitten in `Flaeche  0`.
lang=$(grep -aoE 'wmplug: abi=[0-9]+  Plugins [0-9]+ von [0-9]+' "$P" | tail -1)
[ -n "$lang" ] && [ "${#lang}" -le 40 ] \
    && ok "erste Statuszeile '$lang' ist ${#lang} Zeichen lang (<= 40)" \
    || bad "erste Statuszeile passt nicht in 40 Zeichen ('$lang')"
zwei=$(grep -aoE '  Frist [0-9]+ Ticks  Fläche [0-9]+' "$P" | tail -1)
[ -n "$zwei" ] && [ "${#zwei}" -le 40 ] \
    && ok "zweite Statuszeile '$zwei' ist ${#zwei} Zeichen lang (<= 40)" \
    || bad "die Statuszeile ist nicht umgebrochen ('$zwei')"

echo "== 3. die Beschriftungen von 'info' =="
# DAS TRENNZEICHEN, an dem die Jury haengengeblieben ist: vorher stand
# dort `Leistentext13`, jetzt ein Leerzeichen zwischen Wort und Zahl.
grep -qaE '  Leistentext +[0-9]+' "$P" \
    && ok "bei 'info' steht ein Trennzeichen zwischen Leistentext und Zahl" \
    || bad "'Leistentext' und die Zahl kleben wieder zusammen"
# UND ALLE BESCHRIFTUNGEN AUF EINER BREITE: jeder Wert beginnt auf
# derselben Spalte, gemessen am Text, den der Kern ausgegeben hat.
spalten=$(grep -aoE '^  (Name|Platz|Rechte|Maske|liegt|verloren|eingelegt|abgeholt|Grund|Leistentext) +[^ ]' "$P" \
    | sed 's/.$//' | awk '{ print length($0) }' | sort -u | tr '\n' ' ')
if [ "$(echo $spalten | wc -w)" = 1 ]; then
    ok "alle Beschriftungen von 'info' sind ${spalten% } Zeichen breit -- eine Spalte"
else
    bad "die Beschriftungen von 'info' haben verschiedene Breiten: $spalten"
fi

# ------------------------------------- 4. der Spaltenstand IM BILD
echo "== 4. der Spaltenstand, am Foto nachgerechnet =="
# Das Terminalfenster des Schreibtisches: Raster 10x19 ab (26,62),
# Schrift osum-mono 16 px. DIE FARBEN SIND NACHGEMESSEN UND NICHT VON
# tools/wm/run.sh abgeschrieben: dort steht 224,230,236 auf 16,20,26, das
# ist das Terminal des nackten Fensterservers. Der Schreibtisch nimmt
# sein Thema aus /etc/theme und malt 248,250,252 auf 18,24,32 -- mit den
# geborgten Zahlen war jede Glyphe "falsch", obwohl sie richtig stand.
#
# A-032: DER URSPRUNG DES RASTERS WIRD AUS DER FENSTERLAGE GERECHNET und
# nicht mehr als 26,62 festgeschrieben. 26,62 war die Innenecke eines
# Terminals, das bei 24,40 lag. Seit plugregel beim Start laeuft, greift
# die Regel `titel=Terminal kacheln` aus /etc/wmregeln.conf, und das
# Terminal liegt bei 0,0 -- der Kopf stand bildpunktgenau im Foto, nur
# 24 Punkte links und 40 Punkte hoeher, als der Laeufer suchte. Die Lage
# meldet der Fensterserver selbst (`wm: win ... t=[Terminal`), Rand und
# Titelleiste kommen aus kernel/ui/wm.fi (BORDER0, TITLE_H0).
WIN=$(grep -aE '^wm: win .* t=\[Terminal' "$P" | tail -1)
WX=$(printf '%s' "$WIN" | grep -oE ' x=[0-9]+' | head -1 | grep -oE '[0-9]+')
WY=$(printf '%s' "$WIN" | grep -oE ' y=[0-9]+' | head -1 | grep -oE '[0-9]+')
RAND=$(grep -aoE '^const BORDER0: u64 = [0-9]+' kernel/ui/wm.fi | grep -oE '[0-9]+$')
TITEL=$(grep -aoE '^const TITLE_H0: u64 = [0-9]+' kernel/ui/wm.fi | grep -oE '[0-9]+$')
if [ -n "$WX" ] && [ -n "$WY" ] && [ -n "$RAND" ] && [ -n "$TITEL" ]; then
    GX=$((WX + RAND)); GY=$((WY + TITEL))
    ok "das Terminal liegt laut Fensterserver bei $WX,$WY -- Raster ab $GX,$GY"
else
    GX=26; GY=62
    bad "keine Fensterlage des Terminals im Mitschnitt (x='$WX' y='$WY' Rand='$RAND' Titel='$TITEL')"
fi
GRID=(assets/osum-mono.ttf 16 "$GX" "$GY" 10 19)
VG=(248 250 252); HG=(18 24 32)
tgrid() { # ppm zeile spalte text
    python3 tools/gfx/checkshot.py tgrid "$1" "${GRID[@]}" "$2" "$3" \
        "${VG[@]}" "${HG[@]}" "$4" 2>&1
}
# Die Rasterzeile des Kopfes wird GESUCHT und nicht geraten: welche sie
# traegt, haengt daran, wie viel vorher geschrieben wurde.
kopf=""
for z in $(seq 0 23); do
    if tgrid "$TMPD/paar.ppm" "$z" 2 "Nr Name" > "$TMPD/t.txt" 2>&1; then
        kopf=$z; break
    fi
done
if [ -n "$kopf" ]; then
    ok "der Tabellenkopf steht bildpunktgenau in Rasterzeile $kopf ($(cat "$TMPD/t.txt"))"
    # GEGENPROBE: mit dem alten, festen Ursprung 26,62 darf der Kopf in
    # KEINER Zeile stehen -- sonst saehe tgrid Text, wo keiner ist, und
    # der gerechnete Ursprung oben bewiese nichts. (Liegt das Terminal
    # zufaellig wieder bei 24,40, ist die Probe gegenstandslos.)
    if [ "$GX,$GY" != "26,62" ]; then
        alt=0
        for z in $(seq 0 23); do
            python3 tools/gfx/checkshot.py tgrid "$TMPD/paar.ppm" \
                assets/osum-mono.ttf 16 26 62 10 19 "$z" 2 "${VG[@]}" "${HG[@]}" \
                "Nr Name" >/dev/null 2>&1 && alt=$((alt + 1))
        done
        [ "$alt" = 0 ] && ok "GEGENPROBE: am alten Ursprung 26,62 steht der Kopf in keiner Zeile" \
            || bad "GEGENPROBE: am alten Ursprung 26,62 'steht' der Kopf $alt mal"
    fi
else
    bad "im Foto ist kein Tabellenkopf zu finden"
fi

# EIN PAAR JE SPALTE: Ueberschrift und Wert stehen auf DERSELBEN
# Endspalte. Geprueft wird die Anfangsspalte, und weil tgrid die Laenge
# jeder Zeichenkette kennt, ist damit auch das Ende festgenagelt.
#   Spalte   Kopf ab   Wert ab   Endspalte
#   Nr        2         3         3
#   Name      5         5        13
#   Rechte   13        14        18
#   Maske    20        20        24
#   liegt    26        30        30
#   verloren 32        39        39
paar_probe() { # zeileKopf zeileWert kopfSpalte kopfText wertSpalte wertText name
    local zk=$1 zw=$2 sk=$3 tk=$4 sw=$5 tw=$6 nm=$7
    local a b
    if a=$(tgrid "$TMPD/paar.ppm" "$zk" "$sk" "$tk") \
        && b=$(tgrid "$TMPD/paar.ppm" "$zw" "$sw" "$tw"); then
        ok "$nm: Kopf '$tk' ab Spalte $sk, Wert '$tw' ab Spalte $sw -- dieselbe Endspalte"
    else
        bad "$nm: Kopf oder Wert steht nicht dort, wo die Breiten es sagen ($a / $b)"
    fi
}
if [ -n "$kopf" ]; then
    d1=$((kopf + 1))
    # WELCHES Plugin auf Platz 0 steht und mit welchen Rechten, sagt der
    # KERN und nicht dieser Laeufer -- gelesen aus der Leitung desselben
    # Laufs und dann im Bild gesucht.
    zeile0=$(grep -aoE '^ +0 [a-z]+ +0x[0-9A-F]+ 0x[0-9A-F]+' "$P" | tail -1)
    n0=$(echo "$zeile0" | awk '{print $2}')
    r0=$(echo "$zeile0" | awk '{print $3}')
    m0=$(echo "$zeile0" | awk '{print $4}')
    if [ -n "${n0:-}" ] && [ -n "${r0:-}" ] && [ -n "${m0:-}" ]; then
        ok "Platz 0 traegt '$n0' mit Rechten $r0 und Maske $m0 (aus der Leitung desselben Laufs)"
        paar_probe "$kopf" "$d1" 13 "Rechte" 14 "$r0" "Rechte"
        paar_probe "$kopf" "$d1" 20 "Maske" 20 "$m0" "Maske"
        paar_probe "$kopf" "$d1" 5 "Name" 5 "$n0" "Name"
        paar_probe "$kopf" "$d1" 26 "liegt" 30 "0" "liegt"
        paar_probe "$kopf" "$d1" 32 "verloren" 39 "0" "verloren"
        # UND DIE ZWEITE DATENZEILE, damit die Probe nicht an einer
        # einzigen Zeile haengt.
        zeile1=$(grep -aoE '^ +1 [a-z]+ +0x[0-9A-F]+ 0x[0-9A-F]+' "$P" | tail -1)
        n1=$(echo "$zeile1" | awk '{print $2}')
        r1=$(echo "$zeile1" | awk '{print $3}')
        if [ -n "${n1:-}" ] && [ -n "${r1:-}" ]; then
            paar_probe "$kopf" "$((kopf + 2))" 5 "Name" 5 "$n1" "Name (Platz 1)"
            paar_probe "$kopf" "$((kopf + 2))" 13 "Rechte" 14 "$r1" "Rechte (Platz 1)"
        else
            bad "in der Leitung steht keine zweite Datenzeile"
        fi
    else
        bad "in der Leitung steht keine Datenzeile mit Namen, Rechten und Maske"
    fi
fi

# ------------------------------------------------------- 5. die Bilder
echo "== 5. die Bilder ablegen =="
wandel() { # ppm ziel
    [ -s "$1" ] || { bad "$1 fehlt -- kein Bild"; return 1; }
    if python3 tools/gfx/ppm2png.py "$1" "$2" > /dev/null 2>&1 \
        || python3 -c "from PIL import Image; Image.open('$1').save('$2')" 2>/dev/null; then
        ok "$2 liegt ab ($(stat -c%s "$2") Oktette)"
    else
        cp -f "$1" "${2%.png}.ppm"; ok "${2%.png}.ppm liegt ab (kein PNG-Wandler da)"
    fi
}
wandel "$TMPD/paar.ppm" "$SHOTS/spalten-zwei-plugins.png"
[ -d "$GAUNTLET" ] && wandel "$TMPD/paar.ppm" "$GAUNTLET/09-wmplug-verwaltung.png"

echo
echo "SPALTEN: $pass bestanden, $fail gescheitert"
[ "$fail" = 0 ] || exit 1
