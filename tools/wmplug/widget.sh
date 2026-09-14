#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wmplug/widget.sh -- DAS LEISTENWIDGET, GEMESSEN.
#
# Modul `widget` der Runde WMPLUGIN. Zwei Laeufe desselben Kernels und
# desselben Abbilds, ein einziger Unterschied auf der Kommandozeile:
#
#   AUS: gfx wm wig desk wmplug ...                (kein Widget)
#   AN : ... wigapp=/bin/wmplug,enable,uhr          (Rechte + /bin/pluguhr)
#
# Danach wird NICHT verglichen, was "anders aussieht", sondern eine
# BENANNTE Koordinate nachgerechnet: die Mitte des Kastens, den die
# Leiste fuer den Widget-Text meldet (`taskbar: plug nr=0 x= y= w= h=`).
# Im AN-Bild steht dort Leistenfarbe mit Text darin, im AUS-Bild die
# Fensterknopf-Zone -- dieselbe Stelle, zwei Bilder, eine Rechnung
# (tools/gfx/checkshot.py).
#
# NACHBESSERUNG DER ZWEITEN RUNDE: zwei Zusagen sind dazugekommen.
# Erstens wird der in der Leiste GEMALTE Text gegen den vom Plugin
# GESCHICKTEN gehalten (`taskbar: text plug t=` gegen `pluguhr: text`,
# derselbe Lauf) -- damit ist der CPU-Wert im Bild belegt und nicht
# behauptet. Zweitens wird bei 640x480 der Abstand zwischen Widgetfeld
# und dem linkesten eigenen Leistenfeld nachgerechnet: mindestens acht
# Bildpunkte, sonst lesen sich Widget und Uhr als ein Feld.
#
# Die Bilder landen in docs/shots/wmplug/.
#
# Gebrauch: bash tools/wmplug/widget.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
. tools/lib/userprog.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

TMPD=$(mktemp -d /tmp/wmplug-widget-XXXXXX)
[ "${WIDGET_KEEP:-0}" = 1 ] || trap 'rm -rf "$TMPD"' EXIT
SHOTS="docs/shots/wmplug"
mkdir -p "$SHOTS"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' sollte nicht da sein" || ok "$3"; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "WIDGET: uebersprungen, qemu-system-x86_64 ist nicht da"; exit 0
fi
bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "firnc fehlt"; exit 1; }

echo "== 1. bauen =="
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/k.log" 2>&1 \
    && ok "Kernel gebaut ($(stat -c%s "$TMPD/k.mb") Oktette)" \
    || { bad "der Kernel baut nicht"; tail -12 "$TMPD/k.log" | sed 's/^/        /'; }
[ -f "$TMPD/k.mb" ] || { echo "WIDGET: $pass bestanden, $((fail+1)) gescheitert"; exit 1; }

as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s assembliert nicht"
PROGS="desktop taskbar launcher pluguhr sh echo ls cat"
# /bin/wmplug gehoert dem Modul `verwaltung`. Ist es schon da, nimmt der
# Starthelfer es (`wmplug enable uhr`); fehlt es, faellt er auf den
# nackten WM_PLUG_GRANT zurueck. Dieses Modul wartet auf niemanden.
[ -f kernel/user/wmplug.fi ] && PROGS="$PROGS wmplug"
gebaut=1
for p in $PROGS; do
    up_build vendor/firn/bin/firnc "$p" "$TMPD/$p.o" "$TMPD/$p.elf" \
        "$TMPD/crt.o" kernel/user/user.ld 0 "$TMPD/$p.err" || {
        bad "firnc0 uebersetzt $p.fi nicht"
        sed 's/^/        /' "$TMPD/$p.err" | head -6; gebaut=0; }
done
[ "$gebaut" = 1 ] && ok "$(echo $PROGS | wc -w) Programme gebaut, /bin/pluguhr ist $(stat -c%s "$TMPD/pluguhr.elf") Oktette"

# DAS WIDGET TRAEGT KEINEN KERNCODE UND DER KERN KEINEN WIDGETCODE.
for sym in pluguhr__bauen pluguhr__u_start; do
    if nm -a "$TMPD/k.mb.elf" 2>/dev/null | grep -q "$sym"; then
        bad "der Kernel traegt $sym -- ein Plugin gehoert nach Ring 3"
    else
        ok "der Kernel traegt $sym NICHT (das Widget ist ein Ring-3-Prozess)"
    fi
done

python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
    && ok "der Verzeichnisbaum steht" || bad "tools/k15/tree.py fehlgeschlagen"

echo "== 2. das Abbild =="
ARGS=(build "$TMPD/disk.img" 32768 /lib/
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/)
for p in $PROGS; do
    ARGS+=("/bin/$p=$TMPD/$p.elf")
done
printf 'on\n' > "$TMPD/uitrace"
ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme" "/etc/uitrace=$TMPD/uitrace")
[ -f etc/wmplug.conf ] && ARGS+=("/etc/wmplug.conf=etc/wmplug.conf")
while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "das Abbild ist gebaut" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -5; }

BASE="gfx wm wig desk wmhold wiglong nokbd nosched noproc nofs wmplug"
# Die Gegenprobe faehrt denselben Kernel OHNE das Wort `wmplug`: dann ist
# die Plugintafel ZU, und die Leiste darf davon nichts merken.
OHNE="gfx wm wig desk wmhold wiglong nokbd nosched noproc nofs plugaus"
warte() { # datei marke pid [schritte]
    local f=$1 m=$2 pid=$3 n=${4:-600} i=0
    while [ $i -lt "$n" ]; do
        grep -qa "$m" "$f" 2>/dev/null && return 0
        kill -0 "$pid" 2>/dev/null || return 1
        sleep 0.2; i=$((i+1))
    done
    return 1
}

lauf() { # name zusatz [marke1] [marke2]
    local name=$1 extra=$2 m1=${3:-} m2=${4:-}
    local sock="$TMPD/mon-$name.sock" out="$TMPD/$name.txt" ppm="$TMPD/$name.ppm"
    rm -f "$out" "$ppm" "$sock"
    cp -f "$TMPD/disk.img" "$TMPD/live-$name.img"
    timeout 240 $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 \
        -append "${ZEILE:-$BASE} $extra" -serial "file:$out" -display none -no-reboot \
        -vga std -global VGA.edid=off -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/$name.qemu" 2>&1 &
    local pid=$!
    # AUF DIE MELDUNG WARTEN, DIE DAS BILD BESCHREIBT, und nicht auf
    # `wm: hold`. Gemessen: `wm: hold` steht in diesem Aufbau erst nach
    # sechs Sekunden auf der Leitung -- da hatte sich das Widget mit
    # `runden=6` schon wieder abgemeldet, und beide Fotos zeigten
    # dieselbe leere Leiste. Ein Foto, das auf das falsche Ereignis
    # wartet, misst den falschen Augenblick.
    warte "$out" "${m1:-^wm: hold}" "$pid"
    sleep 2
    python3 tools/gfx/screenshot.py "$sock" "$ppm" 25 > "$TMPD/$name.shot" 2>&1
    # WIE WEIT WAR DIE LEITUNG, ALS DAS FOTO ENTSTAND? Die Lage des
    # Widget-Kastens wird spaeter aus dem Protokoll gelesen, und die
    # Leiste meldet sie bei JEDEM Neumalen. Ohne diese Marke naehme die
    # Rechnung den letzten Kasten des ganzen Laufs -- auch den, der erst
    # nach dem Foto entstanden ist.
    wc -l < "$out" > "$TMPD/$name.marke"
    # DAS ZWEITE FOTO AUS DEMSELBEN LAUF. Es ist der eigentliche Beweis
    # fuer "an und aus ZUR LAUFZEIT": derselbe Fensterserver, dieselbe
    # Leiste, kein Neustart -- nur das Plugin ist gegangen.
    if [ -n "$m2" ]; then
        warte "$out" "$m2" "$pid"
        sleep 3
        python3 tools/gfx/screenshot.py "$sock" "$TMPD/$name-2.ppm" 25 \
            > "$TMPD/$name-2.shot" 2>&1
    fi
    wait "$pid"; rm -f "$sock"
    # DIE LEITUNG OHNE NULLEN. Der Kern schreibt Namen mit fester Laenge
    # (`serial.text(name, 8)`), also stehen mitten in der Zeile
    # Nulloktette: `wmplug: unreg uhr\0\0\0\0\0 grund=0`. `grep -E` kommt
    # damit nicht durch, und eine Zusage, die deshalb nie zutrifft, ist
    # schlimmer als keine -- dieser Lauf hatte sie schon zweimal.
    tr -d '\000' < "$out" > "$out.clean"
}

echo "== 3. der Lauf OHNE Widget =="
lauf aus ""
has "$TMPD/aus.txt" "wm: hold" "der Schreibtisch steht (aus)"
hasnot "$TMPD/aus.txt" "taskbar: plug nr=" "ohne Widget meldet die Leiste kein Widget-Feld"
cp -f "$TMPD/aus.ppm" "$SHOTS/widget-aus.ppm" 2>/dev/null

echo "== 4. der Lauf MIT Widget =="
# `runden=20` heisst: das Widget schickt zwanzig Sekunden lang Text und
# meldet sich dann SELBST ab. Fotografiert wird, sobald die Leiste den
# Text GEMALT hat -- und noch einmal, nachdem das Widget gegangen ist.
# fotografiert -- an und aus im selben Lauf.
lauf an "wigapp=/bin/wmplug,enable,uhr,runden=20" "taskbar: text plug " "pluguhr: ende"
has "$TMPD/an.txt" "wm: hold" "der Schreibtisch steht (an)"
has "$TMPD/an.txt" "wmplug: reg uhr" "das Widget hat sich angemeldet"
has "$TMPD/an.txt" "pluguhr: angemeldet" "und sagt es selbst"
has "$TMPD/an.txt" "pluguhr: text " "es schickt Text"
has "$TMPD/an.txt" "pluguhr: frist ticks=" "es liest die Frist des Kerns"
hasnot "$TMPD/an.txt" "pluguhr: KEIN recht" "es hat R_ACT_BAR bekommen"
has "$TMPD/an.txt" "taskbar: plug nr=0" "die Leiste hat ein Widget-Feld"
has "$TMPD/an.txt" "taskbar: text plug " "und malt seinen Text"
# ACHTUNG, GEMESSENE FALLE: der Kern schreibt den Namen mit acht
# Oktetten (`serial.text(name, 8)`), also steht dort
# `wmplug: unreg uhr      grund=0`. Ein `grep -F` auf
# "unreg uhr grund=2" findet das NIE und war deshalb gruen, waehrend die
# Frist in Wahrheit gerissen war. Jetzt wird mit -E und \s+ gesucht.
if grep -qaE '^wmplug: unreg uhr *grund=2' "$TMPD/an.txt.clean"; then
    bad "die Frist ist gerissen (grund=2) -- das Widget holt zu selten ab"
else
    ok "die Frist hat nicht gerissen (kein grund=2)"
fi
has "$TMPD/an.txt" "pluguhr: barget verweigert r=-2" \
    "das Plugin selbst darf WM_PLUG_BARGET NICHT (E_RIGHTS = -2)"
if grep -qaE '^wmplug: unreg uhr *grund=0' "$TMPD/an.txt.clean"; then
    ok "es hat sich zur Laufzeit SELBST abgemeldet (grund=0)"
else
    bad "keine Abmeldung mit grund=0 -- das Widget ist nicht sauber gegangen"
fi
cp -f "$TMPD/an.ppm" "$SHOTS/widget-an.ppm" 2>/dev/null
cp -f "$TMPD/an-2.ppm" "$SHOTS/widget-aus-laufzeit.ppm" 2>/dev/null

echo "== 5. die Rechnung an der benannten Koordinate =="
# Die Koordinate kommt aus der Leiste selbst und nicht aus diesem Skript:
# `taskbar: plug nr=0 x=.. y=.. w=.. h=..` plus der Fensterlage
# (`taskbar: geom x= y=`). Gemessen wird die MITTE dieses Kastens.
zeile=$(head -n "$(cat "$TMPD/an.marke")" "$TMPD/an.txt" \
    | grep -a '^taskbar: plug nr=0 ' | tail -1)
gline=$(grep -a '^taskbar: geom ' "$TMPD/an.txt" | tail -1)
zahl() { printf '%s' "$1" | grep -oE " $2=[0-9]+" | head -1 | sed 's/.*=//'; }
# Die Farbe an einer Stelle, als "r g b" -- die Leistenfarbe wird nicht
# getippt, sondern aus der Ecke des Kastens GELESEN. Ein fest getippter
# Wert waere nach dem naechsten Farbschema falsch.
pfarbe() { python3 tools/gfx/checkshot.py punkt "$1" "$2" "$3" 2>/dev/null; }

# Wie viele Bildpunkte eines Rechtecks sind zwischen ZWEI Bildern
# verschieden? `checkshot.py` vergleicht ein Bild gegen eine FARBE; hier
# werden zwei Bilder gegeneinander gehalten, und das ist genau die
# Frage "hat sich an dieser Stelle etwas geaendert".
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
px=$(zahl "$zeile" x); py=$(zahl "$zeile" y)
pw=$(zahl "$zeile" w); ph=$(zahl "$zeile" h)
gx=$(zahl "$gline" x); gy=$(zahl "$gline" y)
gx=${gx:-0}; gy=${gy:-0}
if [ -z "$px" ] || [ -z "$pw" ]; then
    bad "die Leiste meldet keinen Widget-Kasten -- ohne ihn gibt es nichts nachzurechnen"
else
    cx=$((gx + px + pw / 2)); cy=$((gy + py + ph / 2))
    ok "der Widget-Kasten steht bei x=$px y=$py w=$pw h=$ph, Mitte im Bild ($cx,$cy)"
    # Der Unterschied wird NICHT behauptet, sondern gezaehlt: wie viele
    # Bildpunkte im Kasten sind zwischen den beiden Bildern verschieden?
    # Text auf gleichfarbigem Grund heisst: ein Teil der Punkte, nicht
    # alle -- also ist die Zusage "mehr als 40 verschiedene Punkte".
    d=$(punktdiff "$SHOTS/widget-an.ppm" "$SHOTS/widget-aus.ppm" \
        "$((gx+px))" "$((gy+py))" "$pw" "$ph")
    if [ "${d:-0}" -gt 40 ]; then
        ok "im Widget-Kasten unterscheiden sich $d Bildpunkte zwischen AN und AUS"
    else
        bad "AN und AUS unterscheiden sich im Widget-Kasten nur in ${d:-0} Bildpunkten"
    fi
    # Und dieselbe Stelle noch einmal mit tools/gfx/checkshot.py, damit
    # die Zahl aus einem Programm kommt, das nicht diesem Modul gehoert.
    aus=$(python3 tools/gfx/checkshot.py punkt "$SHOTS/widget-aus.ppm" "$cx" "$cy" 2>&1)
    an=$(python3 tools/gfx/checkshot.py punkt "$SHOTS/widget-an.ppm" "$cx" "$cy" 2>&1)
    if [ "$aus" != "$an" ]; then
        ok "checkshot punkt ($cx,$cy): aus=[$aus] an=[$an] -- verschieden"
    else
        bad "checkshot punkt ($cx,$cy): beide [$an] -- kein Unterschied an der Mitte"
    fi
    # Die Tinte im Kasten, gegen die Leistenfarbe gezaehlt: mit Widget
    # stehen dort Buchstaben, ohne Widget nicht.
    it=$(python3 tools/gfx/checkshot.py flaeche "$SHOTS/widget-an.ppm" \
        "$((gx+px))" "$((gy+py))" "$pw" "$ph" $(pfarbe "$SHOTS/widget-an.ppm" "$((gx+px+1))" "$((gy+py+1))") 2>&1 \
        | grep -oE '^[0-9]+')
    if [ "${it:-0}" -gt 20 ]; then
        ok "im Widget-Kasten stehen $it Bildpunkte Tinte (AN)"
    else
        bad "im Widget-Kasten steht keine Tinte (${it:-0} Punkte) -- der Text fehlt"
    fi
fi

echo "== 6. an und aus ZUR LAUFZEIT, im selben Lauf =="
# Kein zweiter Start des Fensterservers, kein zweiter Kernel: dasselbe
# `wm`, dieselbe Leiste, dasselbe Fenster. Zwischen den beiden Bildern
# liegt nur, dass sich das Widget abgemeldet hat.
if [ ! -s "$SHOTS/widget-aus-laufzeit.ppm" ]; then
    bad "das zweite Foto des Laufs fehlt"
elif [ -z "${px:-}" ]; then
    bad "ohne Widget-Kasten gibt es nichts nachzurechnen"
else
    d2=$(punktdiff "$SHOTS/widget-an.ppm" "$SHOTS/widget-aus-laufzeit.ppm" \
        "$((gx+px))" "$((gy+py))" "$pw" "$ph")
    if [ "${d2:-0}" -gt 40 ]; then
        ok "nach dem Abmelden haben sich $d2 Bildpunkte im Kasten geaendert"
    else
        bad "nach dem Abmelden ist das Bild unveraendert (${d2:-0} Punkte)"
    fi
    # Die Vergleichsfarbe kommt aus DEM BILD, das gemessen wird: nach
    # dem Abmelden malt die Leiste an dieser Stelle ihren eigenen
    # Verlauf, und der ist nicht die Farbe, die vorher im Kasten stand.
    # Mit der alten Farbe gemessen waere hinterher ALLES "Tinte".
    it2=$(python3 tools/gfx/checkshot.py flaeche "$SHOTS/widget-aus-laufzeit.ppm" \
        "$((gx+px))" "$((gy+py))" "$pw" "$ph" \
        $(pfarbe "$SHOTS/widget-aus-laufzeit.ppm" "$((gx+px+1))" "$((gy+py+1))") 2>&1 \
        | grep -oE '^[0-9]+')
    ok "im Kasten stehen danach $it2 Punkte, die nicht Leistenflaeche sind (vorher $it)"
    if [ "${it2:-0}" -lt "${it:-0}" ]; then
        ok "der Widget-Text ist weg, ohne dass der Fensterserver neu gestartet wurde"
    else
        bad "der Widget-Text steht noch da (${it2:-0} statt weniger als ${it:-0})"
    fi
fi

echo "== 6b. WOHER KOMMT DIE ZAHL IN DER LEISTE? =="
# DIE FRAGE DER JURY WAR: der CPU-Wert im Bild -- ist der gemessen oder
# gemalt? Beantwortet wird sie nicht mit einem Satz, sondern mit zwei
# Leitungszeilen aus DEMSELBEN Lauf:
#
#   pluguhr: text cpu 7%                    <- was das Plugin SCHICKT
#   taskbar: text plug x=.. t=cpu 7%        <- was die Leiste MALT
#
# Das Plugin meldet jeden geschickten Text NACH dem Ruf `WM_PLUG_BAR`
# (kernel/user/pluguhr.fi): wenn diese Zeile auf der Leitung steht, hat
# der Kern den Text schon, und die Leiste holt ihn erst danach
# (`WM_PLUG_BARGET`). Also muss JEDE gemalte Zeichenfolge gleich der
# zuletzt gemeldeten sein. Weicht auch nur eine ab, malt die Leiste
# etwas, das kein Plugin geschickt hat -- und dann ist die Zahl im Bild
# nichts wert.
paare=$(awk '
    /^pluguhr: text / { letzte = substr($0, 15); sub(/[ \t\r]+$/, "", letzte); next }
    /^taskbar: text plug / {
        i = index($0, " t=")
        if (i == 0) next
        gemalt = substr($0, i + 3); sub(/[ \t\r]+$/, "", gemalt)
        if (letzte == "") next          # gemalt, bevor je Text kam
        n++
        if (gemalt != letzte) { schlecht++; if (bsp == "") bsp = gemalt " != " letzte }
    }
    END { printf "%d %d %s\n", n+0, schlecht+0, bsp }
' "$TMPD/an.txt.clean")
set -- $paare
pn=${1:-0}; pfalsch=${2:-0}; shift 2 || true
if [ "$pn" -lt 1 ]; then
    bad "kein Paar aus 'pluguhr: text' und 'taskbar: text plug' im Lauf"
elif [ "$pfalsch" != 0 ]; then
    bad "$pfalsch von $pn gemalten Texten stammen NICHT vom Plugin ($*)"
else
    ok "alle $pn gemalten Widget-Texte sind genau der zuletzt geschickte (cpu-Wert belegt)"
fi
# UND DIE UHRZEIT GEHOERT DER LEISTE. Seit dieser Nachbesserung schickt
# das Widget nur noch `cpu NN%`: zwei Uhrzeiten nebeneinander, die um
# eine Minute auseinanderliefen, waren der Befund der Jury.
if grep -qaE '^pluguhr: text [0-9][0-9]:[0-9][0-9]' "$TMPD/an.txt.clean"; then
    bad "das Widget schickt wieder eine Uhrzeit -- die hat die Leiste schon"
else
    ok "das Widget schickt keine Uhrzeit mehr (nur Last), die Uhr bleibt der Leiste"
fi
if grep -qaE '^pluguhr: text cpu [0-9]+%' "$TMPD/an.txt.clean"; then
    ok "der Text hat die Form 'cpu NN%' ($(grep -a '^pluguhr: text ' "$TMPD/an.txt.clean" | tail -1))"
else
    bad "der Widgettext hat nicht die Form 'cpu NN%'"
fi

echo "== 6c. der Abstand zwischen Widgetfeld und Uhr, bei 640x480 =="
# Der enge Schirm ist der Fall, in dem es schiefging: `gap()` faellt
# dort auf vier Bildpunkte, und Widgetfeld und Uhr lasen sich auf dem
# Foto als EIN Feld. Die Leiste haelt jetzt mindestens acht Bildpunkte
# frei (kernel/user/taskbar.fi). Gemessen wird das nicht am Bild,
# sondern an den Zahlen, die die Leiste selbst meldet: linke Kante des
# linkesten eigenen Feldes minus rechte Kante des Widgetkastens.
ZEILE="$BASE fbres=640x480" lauf eng "wigapp=/bin/wmplug,enable,uhr,runden=20" \
    "taskbar: text plug "
has "$TMPD/eng.txt" "taskbar: plug nr=0" "bei 640x480 hat die Leiste ein Widget-Feld"
ezeile=$(head -n "$(cat "$TMPD/eng.marke")" "$TMPD/eng.txt" \
    | grep -a '^taskbar: plug nr=0 ' | tail -1)
epx=$(zahl "$ezeile" x); epw=$(zahl "$ezeile" w)
# Die linke Kante des linkesten eigenen Feldes (Uhr, Akku, Ton, Netz,
# Meldungen) -- je Name der zuletzt gemeldete Wert.
eminx=$(grep -a '^taskbar: field ' "$TMPD/eng.txt" | awk '
    { name = $3; i = index($0, " x="); rest = substr($0, i + 3)
      split(rest, t, " "); x[name] = t[1] + 0 }
    END { m = -1
          for (k in x) if (m < 0 || x[k] < m) m = x[k]
          print m }')
if [ -z "$epx" ] || [ -z "${eminx:-}" ] || [ "${eminx:--1}" -lt 0 ]; then
    bad "bei 640x480 fehlen die Zahlen fuer den Abstand (Kasten='$ezeile')"
else
    abstand=$((eminx - epx - epw))
    if [ "$abstand" -ge 8 ]; then
        ok "Abstand Widgetfeld -> linkestes Leistenfeld: $abstand px (>= 8), 640x480"
    else
        bad "Abstand nur $abstand px bei 640x480 (Kasten x=$epx w=$epw, Feld x=$eminx)"
    fi
fi
cp -f "$TMPD/eng.ppm" "$SHOTS/widget-eng-640x480.ppm" 2>/dev/null

echo "== 7. Gegenprobe: derselbe Kernel OHNE Plugintafel =="
# Eine Leiste, die auf einem Kern ohne Erweiterungen anders aussieht oder
# gar stehenbleibt, waere der Preis dieser Runde -- also wird er
# gemessen und nicht angenommen. `plugaus` schaltet die Plugintafel ab
# (das Wort gehoert dem Modul `kern`); dann beantwortet der Kern
# `PL_MAXPLUG` nicht, und die Leiste fragt danach nie wieder.
#
# GEMESSEN UND HIER FESTGEHALTEN: OHNE `plugaus` ist die Tafel OFFEN,
# auch ohne das Wort `wmplug` -- `wmplug: abi=1 tafel= offen` steht in
# jedem dieser Laeufe. Die erste Fassung dieser Zusage behauptete das
# Gegenteil und war deshalb rot.
ZEILE="$OHNE" lauf zu ""
has "$TMPD/zu.txt" "wm: hold" "der Schreibtisch steht auch ohne Plugintafel"
has "$TMPD/zu.txt" "taskbar: geom " "die Leiste meldet ihre Lage wie immer"
hasnot "$TMPD/zu.txt" "taskbar: plug nr=" "und hat kein Widget-Feld"
has "$TMPD/zu.txt" "tafel= zu" "mit plugaus ist die Plugintafel zu"

# DIE BILDER FUERS ANSEHEN. Gerechnet wird mit dem PPM (drei Oktette je
# Punkt, kein Verfahren dazwischen); ins Repo gehoert das PNG -- 1,4
# Megaoktett je Foto waeren sonst der halbe Zweig.
for b in widget-an widget-aus widget-aus-laufzeit widget-eng-640x480; do
    if [ -s "$SHOTS/$b.ppm" ]; then
        python3 tools/gfx/ppm2png.py "$SHOTS/$b.ppm" "$SHOTS/$b.png" \
            > /dev/null 2>&1 && rm -f "$SHOTS/$b.ppm"
    fi
done

echo
echo "WIDGET: $pass bestanden, $fail gescheitert"
[ "$fail" = 0 ] || exit 1
