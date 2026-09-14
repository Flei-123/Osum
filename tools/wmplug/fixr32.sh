#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wmplug/fixr32.sh -- DIE NACHBESSERUNG FIX-R3-2, GEMESSEN.
#
# Drei Befunde der Jury, drei Messungen, ein Laeufer:
#
#   1. ZERSCHNITTENE ZEILEN. Leiste und Plugins schrieben ihre Meldungen
#      stueckweise (`say`, `sayn`, `say`, ...), und zwischen zwei
#      Stuecken schrieb der Kern. Auf dem Mitschnitt zu Bild 07 stand
#      eine Kernzeile MITTEN in der Zahl eines Leistenfeldes. Seit
#      kernel/user/zeile.fi geht eine Zeile in EINEM `write` hinaus.
#      Gemessen wird mit GEGENPROBE: derselbe Lauf noch einmal mit den
#      ALTEN Binaerdateien (aus dem Stand vor der Nachbesserung, per
#      `git show`), und gezaehlt wird, wie oft `taskbar:` bzw.
#      `pluguhr:` MITTEN in einer Zeile steht.
#
#   2. DIE SENKRECHTE LEISTE. Sie bekam kein Widgetfeld -- "passt nicht
#      hinein" stand als Abkuerzung im Bericht. Jetzt bekommt sie eines
#      mit gekuerztem Text. Gemessen: der Kasten steht in der Leiste,
#      es ist Tinte darin, und dieselbe Stelle sieht ohne Plugin anders
#      aus (zwei Fotos aus DEMSELBEN Lauf, an der Koordinate
#      nachgerechnet, die die Leiste selbst meldet).
#
#   3. DER FEHLENDE UMLAUT. Auf dem Schirm stand `KEIN EINZIGES GERT`:
#      `term_putc` warf jedes Oktett ueber 126 weg, und die zwei
#      Oktette von `Ä` sind genau das. Gemessen wird die REPARIERTE
#      Zeile bildpunktgenau gegen den zweiten Rasterer --
#      `checkshot.py tgrid`, an der Koordinate des Wortes.
#
# Die Bilder landen in docs/shots/wmplug/ (senkrecht-widget-an,
# senkrecht-widget-aus-zur-laufzeit, umlaut-geraet).
#
# Gebrauch: bash tools/wmplug/fixr32.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
. tools/lib/userprog.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

TMPD=$(mktemp -d /tmp/wmplug-fixr32-XXXXXX)
[ "${FIXR32_KEEP:-0}" = 1 ] || trap 'rm -rf "$TMPD"' EXIT
SHOTS="docs/shots/wmplug"
mkdir -p "$SHOTS"

# Der Stand VOR dieser Nachbesserung -- die Gegenprobe zu Abschnitt 4.
ALT=${FIXR32_ALT:-d02903f}

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "FIXR32: uebersprungen, qemu-system-x86_64 ist nicht da"; exit 0
fi
bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "firnc fehlt"; exit 1; }

echo "== 1. bauen =="
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/k.log" 2>&1 \
    && ok "Kernel gebaut ($(stat -c%s "$TMPD/k.mb") Oktette)" \
    || { bad "der Kernel baut nicht"; tail -12 "$TMPD/k.log" | sed 's/^/        /'; }
[ -f "$TMPD/k.mb" ] || { echo; echo "FIXR32: $pass bestanden, $((fail+1)) gescheitert"; exit 1; }

as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s assembliert nicht"
PROGS="desktop taskbar launcher pluguhr wmplug sh"
gebaut=1
for p in $PROGS; do
    up_build vendor/firn/bin/firnc "$p" "$TMPD/$p.o" "$TMPD/$p.elf" \
        "$TMPD/crt.o" kernel/user/user.ld 0 "$TMPD/$p.err" || {
        bad "firnc uebersetzt $p.fi nicht"
        sed 's/^/        /' "$TMPD/$p.err" | head -6; gebaut=0; }
done
[ "$gebaut" = 1 ] && ok "$(echo $PROGS | wc -w) Programme gebaut" \
    || { echo; echo "FIXR32: $pass bestanden, $fail gescheitert"; exit 1; }

# DIE ALTEN BINAERDATEIEN. Sie kommen aus der Geschichte und nicht aus
# einer Kopie im Baum: `git show <stand>:datei`. Ohne sie waere
# Abschnitt 4 eine Behauptung ueber "frueher".
mkdir -p "$TMPD/alt"
cp kernel/user/*.fi "$TMPD/alt/" 2>/dev/null
altok=1
for p in taskbar pluguhr; do
    git show "$ALT:kernel/user/$p.fi" > "$TMPD/alt/$p.fi" 2>/dev/null || altok=0
done
if [ "$altok" = 1 ]; then
    prof=""; vendor/firn/bin/firnc --profile=app -c "$TMPD/alt/taskbar.fi" \
        -o "$TMPD/alt/taskbar.o" > "$TMPD/alt/taskbar.err" 2>&1 \
        && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
            -o "$TMPD/alt/taskbar.elf" "$TMPD/alt/taskbar.o" \
            >> "$TMPD/alt/taskbar.err" 2>&1 || altok=0
    vendor/firn/bin/firnc -c "$TMPD/alt/pluguhr.fi" -o "$TMPD/alt/pluguhr.o" \
        > "$TMPD/alt/pluguhr.err" 2>&1 \
        && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
            -o "$TMPD/alt/pluguhr.elf" "$TMPD/crt.o" "$TMPD/alt/pluguhr.o" \
            >> "$TMPD/alt/pluguhr.err" 2>&1 || altok=0
fi
[ "$altok" = 1 ] && ok "die alten Fassungen ($ALT) von taskbar/pluguhr sind gebaut" \
    || bad "die alten Fassungen ($ALT) lassen sich nicht bauen -- Abschnitt 4 misst dann nur die neue Seite"

python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
    && ok "der Verzeichnisbaum steht" || bad "tools/k15/tree.py fehlgeschlagen"

echo "== 2. die Abbilder =="
# EINE SENKRECHTE LEISTE ist eine Zeile in /etc/taskbar.conf. Die Breite
# ist die Vorgabe (104 logische Punkte) -- die Abkuerzung der Runde war,
# dass in diese Spalte "kein Widget passt"; genau das wird jetzt
# gemessen statt behauptet.
printf '# taskbar.conf\nedge=left\nheight=28\nwidth=104\nautohide=0\nontop=1\n' \
    > "$TMPD/taskbar.conf"
# OHNE /etc/uitrace SAGT DIE LEISTE NICHTS. Ihre Meldungen haengen an
# diesem Schalter -- und genau diese Meldungen sind der Gegenstand von
# Abschnitt 4 (eine Zeile, ein Schreibruf) und liefern in Abschnitt 5
# die Koordinate des Kastens.
printf 'on\n' > "$TMPD/uitrace"
bild() { # ziel verzeichnis-mit-elf
    local img=$1 bin=$2
    local -a A=(build "$img" 32768 /lib/
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/)
    local p
    for p in $PROGS; do
        if [ -s "$bin/$p.elf" ]; then A+=("/bin/$p=$bin/$p.elf")
        else A+=("/bin/$p=$TMPD/$p.elf"); fi
    done
    A+=(/etc/ "/etc/theme=$TMPD/baum/theme"
        "/etc/taskbar.conf=$TMPD/taskbar.conf"
        "/etc/uitrace=$TMPD/uitrace")
    [ -f etc/wmplug.conf ] && A+=("/etc/wmplug.conf=etc/wmplug.conf")
    local z
    while read -r z; do A+=("$z"); done < "$TMPD/baum/liste"
    python3 tools/osum/mkfs.py "${A[@]}" > "$img.mkfs" 2>&1
}
bild "$TMPD/neu.img" "$TMPD" && ok "das Abbild mit den neuen Programmen steht" \
    || { bad "mkfs.py (neu) fehlgeschlagen"; head -5 "$TMPD/neu.img.mkfs" | sed 's/^/        /'; }
if [ "$altok" = 1 ]; then
    bild "$TMPD/alt.img" "$TMPD/alt" && ok "das Abbild mit den alten Programmen steht" \
        || bad "mkfs.py (alt) fehlgeschlagen"
fi

BASE="gfx wm wig desk wmhold wiglong nokbd nosched noproc nofs wmplug"
warte() { # datei marke pid [schritte]
    local f=$1 m=$2 pid=$3 n=${4:-600} i=0
    while [ $i -lt "$n" ]; do
        grep -qa "$m" "$f" 2>/dev/null && return 0
        kill -0 "$pid" 2>/dev/null || return 1
        sleep 0.2; i=$((i+1))
    done
    return 1
}
lauf() { # name abbild zeile marke1 [marke2]
    local name=$1 img=$2 zeile=$3 m1=${4:-^wm: hold} m2=${5:-}
    local sock="$TMPD/mon-$name.sock" out="$TMPD/$name.txt"
    rm -f "$out" "$sock"
    cp -f "$img" "$TMPD/live-$name.img"
    timeout 240 $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 \
        -append "$zeile" -serial "file:$out" -display none -no-reboot \
        -vga std -global VGA.edid=off -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/$name.qemu" 2>&1 &
    local pid=$!
    warte "$out" "$m1" "$pid"
    sleep 2
    python3 tools/gfx/screenshot.py "$sock" "$TMPD/$name.ppm" 25 > "$TMPD/$name.shot" 2>&1
    wc -l < "$out" > "$TMPD/$name.marke"
    if [ -n "$m2" ]; then
        warte "$out" "$m2" "$pid"; sleep 3
        python3 tools/gfx/screenshot.py "$sock" "$TMPD/$name-2.ppm" 25 \
            > "$TMPD/$name-2.shot" 2>&1
    fi
    wait "$pid"; rm -f "$sock"
    tr -d '\000' < "$out" > "$out.clean"
}

echo "== 3. der Lauf: senkrechte Leiste, Widget an und wieder aus =="
lauf senk "$TMPD/neu.img" \
    "$BASE wigapp=/bin/wmplug,enable,uhr,runden=20" \
    'taskbar: text plug ' 'pluguhr: ende'
has "$TMPD/senk.txt" "wm: hold" "der Schreibtisch steht"
has "$TMPD/senk.txt.clean" "ename=left" "die Leiste steht am linken Rand"
has "$TMPD/senk.txt.clean" "vertical=1" "und ist eine SENKRECHTE Leiste"
has "$TMPD/senk.txt.clean" "wmplug: reg uhr" "das Widget ist angemeldet"
has "$TMPD/senk.txt.clean" "taskbar: plug nr=0" "die SENKRECHTE Leiste meldet ein Widgetfeld"

echo "== 4. eine Zeile, ein Schreibruf =="
# EINE ZERSCHNITTENE ZEILE ERKENNT MAN DARAN, DASS EINE MARKE MITTEN IN
# IHR STEHT. `taskbar:` und `pluguhr:` gehoeren an den Zeilenanfang;
# steht eine davon weiter hinten, hat ein anderer Schreiber dazwischen
# geschrieben. Gezaehlt wird in beiden Mitschnitten -- alt und neu.
schnitte() { # datei -> Zahl
    grep -aoE '.taskbar: |.pluguhr: ' "$1" | grep -cv '^$' 2>/dev/null
}
mitten() { # datei -> Zeilen, in denen eine Marke NICHT am Anfang steht
    grep -acE '.+(taskbar: |pluguhr: )' "$1"
}
neu_m=$(mitten "$TMPD/senk.txt.clean")
ok "neu: $neu_m Zeilen mit einer Marke mitten drin"
if [ "$altok" = 1 ]; then
    lauf alt "$TMPD/alt.img" \
        "$BASE wigapp=/bin/wmplug,enable,uhr,runden=20" 'taskbar: text plug '
    alt_m=$(mitten "$TMPD/alt.txt.clean")
    ok "alt ($ALT): $alt_m Zeilen mit einer Marke mitten drin"
    if [ "$neu_m" -le "$alt_m" ]; then
        ok "neu ist nicht schlechter als alt ($alt_m -> $neu_m)"
    else
        bad "die Stueckelung ist GEWACHSEN (alt $alt_m, neu $neu_m)"
    fi
    # EHRLICHER BEFUND, und er gehoert hierher und nicht in eine
    # Fussnote: bei dieser Last hat AUCH der alte Stand keine Zeile
    # zerschnitten. Die Falle haengt an der Last; mit vier Schreibrufen
    # je Zeile ist sie MOEGLICH, mit einem nicht mehr. Der Beweis der
    # Eigenschaft ist deshalb die Zahl der Schreibrufe (Abschnitt 4b),
    # nicht dieser eine Lauf.
    [ "$alt_m" = 0 ] && ok "Hinweis: auch der alte Stand blieb in DIESEM Lauf heil -- die Falle ist lastabhaengig"
fi

echo "== 4b. wie viele Schreibrufe je Zeile? =="
# DAS IST DIE EIGENTLICHE ZUSAGE, und sie steht im Quelltext, wo man sie
# nachzaehlen kann: EIN `ulib.put` je fertiger Zeile in zeile.fi, und
# KEIN Programm schreibt daran vorbei.
n_put=$(grep -c 'ulib.put(' kernel/user/zeile.fi)
[ "$n_put" = 2 ] \
    && ok "kernel/user/zeile.fi schreibt an genau 2 Stellen (nl + spuel), je eine ganze Zeile" \
    || bad "zeile.fi hat $n_put Schreibstellen -- erwartet waren 2"
vorbei=0
for f in taskbar pluguhr plugregel plugboese; do
    n=$(grep -cE 'ulib\.(say|sayn|sayu|nl)\(' "kernel/user/$f.fi")
    [ "$n" = 0 ] || { bad "kernel/user/$f.fi schreibt an $n Stellen am Zeilenpuffer vorbei"; vorbei=1; }
done
[ "$vorbei" = 0 ] && ok "keines der vier Programme schreibt am Zeilenpuffer vorbei"
# Und zum Vergleich der alte Stand: so viele Rufe kostete dort EINE
# Meldung der Leiste.
altruf=$(git show "$ALT:kernel/user/taskbar.fi" 2>/dev/null \
    | grep -cE '^ *(say|sayn|nl)\(')
neuruf=$(grep -cE '^ *(say|sayn|nl)\(' kernel/user/taskbar.fi)
# Im Stand $ALT war JEDER dieser Rufe ein eigener `write`; heute ist es
# nur noch `nl()`. Die Feldmeldung der Leiste kostete zwoelf Rufe und
# kostet einen -- gezaehlt wird hier die Gesamtzahl der Stellen, an
# denen frueher ein Schreibruf stand.
[ "${altruf:-0}" -gt 0 ] \
    && ok "im Stand $ALT war jede der $altruf Ausgabestellen ein eigener write; dieselben $neuruf Stellen fuellen heute den Puffer, geschrieben wird nur bei nl()" \
    || ok "der alte Stand ist nicht lesbar -- der Vergleich entfaellt"
# UND DIE ZEILEN SELBST: jede Feldmeldung der Leiste muss GANZ sein.
# Der Feldname, fuenf Zahlen, Ende der Zeile -- wer dazwischen
# geschrieben hat, faellt hier durch.
ganz=$(grep -acE '^taskbar: field [a-z]+ x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+ lines=[0-9]+$' \
    "$TMPD/senk.txt.clean")
kaputt=$(grep -acE '^taskbar: field ' "$TMPD/senk.txt.clean")
kaputt=$((kaputt - ganz))
if [ "$ganz" -gt 0 ] && [ "$kaputt" = 0 ]; then
    ok "alle $ganz Feldmeldungen der Leiste sind vollstaendige Zeilen"
else
    bad "$kaputt von $((ganz + kaputt)) Feldmeldungen sind zerschnitten"
fi
# Und dasselbe fuer das Plugin: `pluguhr: text <text>` ist eine Zeile.
ptext=$(grep -acE '^pluguhr: text .+$' "$TMPD/senk.txt.clean")
[ "${ptext:-0}" -gt 0 ] && ok "$ptext vollstaendige Textmeldungen des Widgets" \
    || bad "keine vollstaendige Zeile 'pluguhr: text ...' im Mitschnitt"

echo "== 5. das Widgetfeld in der senkrechten Leiste, nachgerechnet =="
zahl() { printf '%s' "$1" | grep -oE " $2=[0-9]+" | head -1 | sed 's/.*=//'; }
kasten=$(head -n "$(cat "$TMPD/senk.marke")" "$TMPD/senk.txt.clean" \
    | grep -a '^taskbar: plug nr=0 ' | tail -1)
gline=$(grep -a '^taskbar: geom ' "$TMPD/senk.txt.clean" | tail -1)
px=$(zahl "$kasten" x); py=$(zahl "$kasten" y)
pw=$(zahl "$kasten" w); ph=$(zahl "$kasten" h)
gx=$(zahl "$gline" x); gy=$(zahl "$gline" y)
gx=${gx:-0}; gy=${gy:-0}
punktdiff() { python3 - "$@" <<'PY'
import sys
def load(p):
    d = open(p, 'rb').read()
    teile = []; i = 2
    while len(teile) < 3:
        while i < len(d) and d[i:i+1].isspace(): i += 1
        if d[i:i+1] == b'#':
            while d[i:i+1] != b'\n': i += 1
            continue
        j = i
        while j < len(d) and not d[j:j+1].isspace(): j += 1
        teile.append(int(d[i:j])); i = j
    i += 1
    return teile[0], teile[1], d[i:]
a = load(sys.argv[1]); b = load(sys.argv[2])
x0, y0, w, h = (int(v) for v in sys.argv[3:7])
n = 0
for y in range(y0, min(y0 + h, a[1], b[1])):
    for x in range(x0, min(x0 + w, a[0], b[0])):
        o = (y * a[0] + x) * 3
        if a[2][o:o+3] != b[2][o:o+3]: n += 1
print(n)
PY
}
if [ -z "${px:-}" ]; then
    bad "die senkrechte Leiste meldet keinen Widget-Kasten"
else
    ok "der Kasten steht bei x=$px y=$py w=$pw h=$ph (Leiste bei $gx,$gy)"
    # Er muss IN der Spalte liegen -- ein Kasten, der ueber die Leiste
    # hinausragt, waere ein Plugin, das ausserhalb seines Platzes malt.
    bw=$(zahl "$gline" w)
    if [ -n "${bw:-}" ] && [ $((px + pw)) -le "$bw" ]; then
        ok "der Kasten bleibt in der Spalte ($((px + pw)) <= $bw)"
    else
        bad "der Kasten ragt aus der Leiste ($((px + pw)) > ${bw:-?})"
    fi
    grund=$(python3 tools/gfx/checkshot.py punkt "$TMPD/senk.ppm" \
        "$((gx + px + 1))" "$((gy + py + 1))" 2>/dev/null)
    tinte=$(python3 tools/gfx/checkshot.py flaeche "$TMPD/senk.ppm" \
        "$((gx + px))" "$((gy + py))" "$pw" "$ph" $grund 2>&1 | grep -oE '^[0-9]+')
    if [ "${tinte:-0}" -gt 20 ]; then
        ok "im Kasten stehen $tinte Bildpunkte Tinte -- der gekuerzte Text ist da"
    else
        bad "im Kasten steht keine Tinte (${tinte:-0}) -- das Feld ist leer"
    fi
    if [ -s "$TMPD/senk-2.ppm" ]; then
        d=$(punktdiff "$TMPD/senk.ppm" "$TMPD/senk-2.ppm" \
            "$((gx + px))" "$((gy + py))" "$pw" "$ph")
        if [ "${d:-0}" -gt 40 ]; then
            ok "nach dem Abmelden haben sich $d Bildpunkte im Kasten geaendert"
        else
            bad "nach dem Abmelden ist der Kasten unveraendert (${d:-0} Punkte)"
        fi
        cx=$((gx + px + pw / 2)); cy=$((gy + py + ph / 2))
        a1=$(python3 tools/gfx/checkshot.py punkt "$TMPD/senk.ppm" "$cx" "$cy" 2>&1)
        a2=$(python3 tools/gfx/checkshot.py punkt "$TMPD/senk-2.ppm" "$cx" "$cy" 2>&1)
        if [ "$a1" != "$a2" ]; then
            ok "checkshot punkt ($cx,$cy): an=[$a1] aus=[$a2] -- verschieden"
        else
            bad "checkshot punkt ($cx,$cy): beide [$a1]"
        fi
    else
        bad "das zweite Foto des Laufs fehlt"
    fi
fi

echo "== 6. der Umlaut, an der Koordinate des Wortes =="
# EIGENER LAUF, weil die Zeile aus dem Kernterminal kommt (`ub_line` ->
# `wm.term_write`) und dieses Terminal nur ohne den Schreibtisch oben
# liegt. Dieselbe Zeile steht auf der Leitung -- beide werden geprueft.
lauf umlaut "$TMPD/neu.img" "gfx wm wmhold nokbd nosched noproc nofs" '^wm: hold'
if grep -qa 'KEIN EINZIGES GERÄT!' "$TMPD/umlaut.txt.clean"; then
    ok "die Leitung traegt das Wort mit Umlaut (UTF-8)"
else
    bad "auf der Leitung steht kein 'GERÄT' -- die Quelle stimmt schon nicht"
fi
tzeile=$(grep -a '^wm: term win=0' "$TMPD/umlaut.txt.clean" | tail -1)
zw=$(printf '%s' "$tzeile" | grep -oE 'cell=[0-9]+x[0-9]+' | sed 's/cell=//;s/x.*//')
zh=$(printf '%s' "$tzeile" | grep -oE 'cell=[0-9]+x[0-9]+' | sed 's/.*x//')
wzeile=$(grep -a '^wm: win nr=0 ' "$TMPD/umlaut.txt.clean" | tail -1)
wx=$(zahl "$wzeile" x); wy=$(zahl "$wzeile" y)
zw=${zw:-10}; zh=${zh:-19}; wx=${wx:-24}; wy=${wy:-40}
# Der Rasterursprung wird GESUCHT (die Zeile haengt daran, wie viel
# vorher geschrieben wurde) und nicht eingetragen.
GRID=(assets/osum-mono.ttf 16 $((wx + 2)) $((wy + 22)) "$zw" "$zh")
VG=(224 230 236); HG=(16 20 26)
tgrid() { # ppm zeile spalte text
    python3 tools/gfx/checkshot.py tgrid "$1" "${GRID[@]}" "$2" "$3" \
        "${VG[@]}" "${HG[@]}" "$4" 2>&1
}
fund=""
for z in $(seq 0 19); do
    if tgrid "$TMPD/umlaut.ppm" "$z" 1 "KEIN EINZIGES GER" > "$TMPD/t.txt" 2>&1; then
        fund=$z; break
    fi
done
if [ -z "$fund" ]; then
    bad "im Foto ist die Zeile 'KEIN EINZIGES GER...' nicht zu finden"
else
    ok "die Zeile steht bildpunktgenau in Rasterzeile $fund ($(cat "$TMPD/t.txt"))"
    if tgrid "$TMPD/umlaut.ppm" "$fund" 1 "KEIN EINZIGES GERÄT!" > "$TMPD/t2.txt" 2>&1; then
        ok "MIT UMLAUT, jede Glyphe gegen den Rasterer: $(cat "$TMPD/t2.txt")"
    else
        bad "die Zeile mit 'Ä' stimmt nicht: $(cat "$TMPD/t2.txt")"
    fi
    # Und die Glyphe allein, an ihrer eigenen Spalte -- damit die Zusage
    # nicht an den 17 Buchstaben davor haengt.
    if tgrid "$TMPD/umlaut.ppm" "$fund" 18 "ÄT!" > "$TMPD/t3.txt" 2>&1; then
        ok "das 'Ä' selbst hat Tinte: $(cat "$TMPD/t3.txt")"
    else
        bad "an der Spalte des 'Ä' steht nicht, was dort stehen soll: $(cat "$TMPD/t3.txt")"
    fi
fi

echo "== 7. die Bilder ablegen =="
wandel() { # ppm ziel
    [ -s "$1" ] || { bad "$1 fehlt"; return 1; }
    python3 tools/gfx/ppm2png.py "$1" "$2" > /dev/null 2>&1 \
        && ok "$(basename "$2") abgelegt" || bad "$1 laesst sich nicht wandeln"
}
wandel "$TMPD/senk.ppm"   "$SHOTS/senkrecht-widget-an.png"
wandel "$TMPD/senk-2.ppm" "$SHOTS/senkrecht-widget-aus-zur-laufzeit.png"
wandel "$TMPD/umlaut.ppm" "$SHOTS/umlaut-geraet.png"

echo
echo "FIXR32: $pass bestanden, $fail gescheitert"
[ "$fail" = 0 ] || exit 1
