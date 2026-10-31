#!/usr/bin/env bash
#
#   bash tools/softui/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRN_REPO=${FIRN_REPO:-/root/jarvis/projects/u_DiS4in7esMF1/firn}
export FIRNLIB="$(pwd)/lib"
TMPD=${SOFTUITMP:-/tmp/softui-run}
mkdir -p "$TMPD"
export LOOKBUILD="$TMPD/build"

P=0; F=0
ok()  { P=$((P+1)); printf '   OK    %s\n' "$*"; }
bad() { F=$((F+1)); printf '   FAIL  %s\n' "$*"; }
is()  { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: $2, erwartet $3"; fi; }
ge()  { if [ "${2:-0}" -ge "$3" ] 2>/dev/null; then ok "$1: $2 (>= $3)"; else bad "$1: ${2:-?}, erwartet >= $3"; fi; }
le()  { if [ "${2:-999999}" -le "$3" ] 2>/dev/null; then ok "$1: $2 (<= $3)"; else bad "$1: ${2:-?}, erwartet <= $3"; fi; }

shot() { # dir args...
    local d=$1; shift
    bash tools/look/shot.sh "$TMPD/$d" "$@" > "$TMPD/$d.log" 2>&1
    grep -qa 'qemu exit 21' "$TMPD/$d.log"
}
val() { grep -aoE "$2" "$1" 2>/dev/null | tail -1 | grep -oE '[0-9]+$'; }

echo "== A. classic ist unveraendert =="
#
#   git worktree add --detach /root/mgline2-base 54bf135
#   cd /root/mgline2-base && FIRNLIB=$(pwd)/lib bash tools/look/shot.sh \
#       /tmp/softui/base-classic shape=classic scheme=day mode=light \
#       keep=yes accel=tcg
#
REF=${SOFTUIBASEPPM:-/tmp/softui/base-classic/desktop.ppm}
if shot A shape=classic scheme=day mode=light keep=yes accel=tcg; then
    ok "classic bootet (QEMU exit 21)"
    if [ -s "$REF" ]; then
        #
        G=$(python3 tools/softui/gleich.py "$REF" "$TMPD/A/desktop.ppm" \
            --zeit --ausser 26,62,560,380 2>&1)
        echo "$G" | sed 's/^/        /'
        D=$(echo "$G" | grep -oE 'unterschiedlich [0-9]+' | grep -oE '[0-9]+')
        is "classic: abweichende Bildpunkte gegen die Grundlinie" "${D:-x}" "0"
    else
        #
        printf '   --    Abschnitt A uebersprungen: keine Grundlinie unter %s\n' "$REF"
        printf '         Herstellen:\n'
        printf '           git worktree add --detach /root/mgline2-base <commit-vor-softui>\n'
        printf '           cd /root/mgline2-base && FIRNLIB=$(pwd)/lib bash tools/look/shot.sh \\\n'
        printf '               /tmp/softui/base-classic shape=classic scheme=day mode=light keep=yes accel=tcg\n'
    fi
else
    bad "classic bootet nicht"
fi

echo "== B. die Formdatei wird GANZ gelesen =="
if shot B shape=modern scheme=day mode=light keep=yes shadow=on extra='einst nostart wigapp=/bin/explorer'; then
    K=$(val "$TMPD/B/serial.txt" 'shape file=modern name=Modern id=1 keys=[0-9]+')
    is "Marken aus modern.shape" "${K:-0}" "24"
    CH=$(grep -aoE 'ctrl_h=[0-9]+' "$TMPD/B/serial.txt" | tail -1 | grep -oE '[0-9]+')
    is "ctrl_h aus der Datei" "${CH:-0}" "32"
    N=$(grep -aoE 'form n=[0-9]+' "$TMPD/B/serial.txt" | tail -1 | grep -oE '[0-9]+')
    # r402: three words more (WF_TITLE_BAR, WF_CAP_W, WF_FRAME): 17 -> 20
    # W-S: WF_BLURRIM (edge highlight of blurred surfaces) joined: 20 -> 21
    is "Formwoerter an den Server" "${N:-0}" "21"
    S=$(stat -c%s assets/shapes/modern.shape)
    ge "und die Datei ist groesser als der alte Puffer" "$S" "4097"
else
    bad "modern bootet nicht"
fi

echo "== C. der Schatten: Maske gegen Ringe gegen keinen =="
if [ -s "$TMPD/B/serial.txt" ]; then
    L=$(grep -a 'wmbench2: maske' "$TMPD/B/serial.txt" | tail -1)
    R=$(grep -a 'wmbench2: ringe' "$TMPD/B/serial.txt" | tail -1)
    O=$(grep -a 'wmbench2: ohne' "$TMPD/B/serial.txt" | tail -1)
    echo "        $O"
    echo "        $L"
    echo "        $R"
    MU=$(echo "$L" | grep -oE 'full=[0-9]+' | grep -oE '[0-9]+')
    RU=$(echo "$R" | grep -oE 'full=[0-9]+' | grep -oE '[0-9]+')
    OU=$(echo "$O" | grep -oE 'full=[0-9]+' | grep -oE '[0-9]+')
    MA=$(echo "$L" | grep -oE 'aapx=[0-9]+' | grep -oE '[0-9]+')
    RA=$(echo "$R" | grep -oE 'aapx=[0-9]+' | grep -oE '[0-9]+')
    if [ -n "$MU" ] && [ -n "$RU" ] && [ -n "$OU" ]; then
        MK=$((MU - OU)); RK=$((RU - OU))
        echo "        Schatten kostet: Maske ${MK} us, Ringe ${RK} us"
        if [ "$MK" -lt "$RK" ]; then
            ok "die Maske ist billiger als die Ringe ($MK < $RK us)"
        else
            bad "die Maske ist NICHT billiger ($MK gegen $RK us)"
        fi
    else
        bad "keine Zeitmessung im Mitschnitt"
    fi
    if [ -n "$MA" ] && [ -n "$RA" ]; then
        le "Eckabtastungen je Bild mit der Maske" "$MA" "$((RA / 4))"
    fi
    SB=$(val "$TMPD/B/serial.txt" 'shbuild=[0-9]+')
    le "die Maske wurde je Lauf gebaut" "${SB:-99}" "1"
    ge "und sie wurde ueberhaupt gebaut" "${SB:-0}" "1"
fi

echo "== D. die drei Schaltflaechen, und der rote Knopf =="
# TWO PICTURES, because the pointer cannot be on the close button and off it at
# once: D0 has no pointer on the bar (the three SHAPES: stroke, square, cross),
# D has it on the close button (the HOVER state: red face, white cross).
# The close button of the 1004 px wide Settings window at x=20: centre 1007,14 (was 767,14 for the old 764 px window).
if shot D0 shape=modern scheme=day mode=light keep=yes extra='einst nostart'; then
    python3 tools/softui/knoepfe.py "$TMPD/D0/desktop.ppm" \
        "$TMPD/D0/serial.txt" > "$TMPD/D0.knopf" 2>&1
else
    : > "$TMPD/D0.knopf"
fi
if shot D shape=modern scheme=day mode=light keep=yes extra='einst nostart' hover=1007,14; then
    python3 tools/softui/knoepfe.py "$TMPD/D/desktop.ppm" \
        "$TMPD/D/serial.txt" > "$TMPD/D.hover" 2>&1
    { cat "$TMPD/D0.knopf"; grep -a '^hover:' "$TMPD/D.hover"; } > "$TMPD/D.knopf"
    cat "$TMPD/D.knopf" | sed 's/^/        /'
    grep -q 'min: strich ok' "$TMPD/D.knopf" \
        && ok "Minimieren ist ein waagerechter Strich" \
        || bad "Minimieren ist kein Strich"
    grep -q 'max: quadrat ok' "$TMPD/D.knopf" \
        && ok "Maximieren ist ein Quadrat" || bad "Maximieren ist kein Quadrat"
    grep -q 'close: kreuz ok' "$TMPD/D.knopf" \
        && ok "Schliessen ist ein Kreuz" || bad "Schliessen ist kein Kreuz"
    grep -q 'hover: rot ok' "$TMPD/D.knopf" \
        && ok "der ueberfahrene Schliessen-Knopf ist rot mit weissem Kreuz" \
        || bad "der Ueberfahr-Zustand fehlt"
    grep -q 'macos: keine kreise' "$TMPD/D.knopf" \
        && ok "und es sind KEINE drei bunten Kreise" \
        || bad "da sind bunte Kreise"
fi

echo "== E. der Fokus, ohne eine knallige Farbe =="
# The focused window has to stand far enough from the screen edge for its shadow
# to be measured (fokus.py skips x < 24): the Settings window opens at x=20, so
# this picture has the file manager as the only extra window (it gets the focus).
if shot E0 shape=modern scheme=day mode=light keep=yes shadow=on extra='nostart wigapp=/bin/explorer'; then
    python3 tools/softui/fokus.py "$TMPD/E0/desktop.ppm" \
        "$TMPD/E0/serial.txt" > "$TMPD/E.txt" 2>&1
    cat "$TMPD/E.txt" | sed 's/^/        /'
    AT=$(grep -E '^aktiv ' "$TMPD/E.txt" | grep -oE 'tiefe=[0-9]+' | grep -oE '[0-9]+')
    IT=$(grep -E '^inaktiv ' "$TMPD/E.txt" | grep -oE 'tiefe=[0-9]+' | grep -oE '[0-9]+')
    if [ -n "$AT" ] && [ -n "$IT" ] && [ "$IT" -gt 0 ]; then
        if [ "$AT" -gt "$((IT * 3 / 2))" ]; then
            ok "der Schatten des scharfen Fensters ist mindestens 1,5-mal so tief ($AT gegen $IT)"
        else
            bad "die beiden Schatten sind zu aehnlich ($AT gegen $IT)"
        fi
    else
        bad "keine zwei Schatten gemessen"
    fi
    grep -q 'titel: kein akzent' "$TMPD/E.txt" \
        && ok "und keine Titelleiste traegt den Akzent" \
        || bad "eine Titelleiste ist immer noch akzentfarben"
fi

echo "== F. der Kontrast =="
#
for v in "day light 516" "night dark 1236"; do
    set -- $v
    if shot "F-$1" shape=modern scheme=$1 mode=$2 keep=yes extra='einst nostart'; then
        M=$(python3 tools/theme/model.py contrast "assets/schemes/$1.scheme" $2 \
            | awk '$1=="on-accent"&&$2=="accent"{print $6}')
        is "$1/$2: Text/Akzent im Modell (x100), unveraendert" "${M:-0}" "$3"
        W=$(python3 tools/theme/model.py contrast "assets/schemes/$1.scheme" $2 \
            | awk '$3=="normal"{print $6}' | sort -n | head -1)
        echo "        kleinstes Textpaar im Modell: $W"
        K=$(python3 tools/softui/titel.py "$TMPD/F-$1/desktop.ppm" \
            "$TMPD/F-$1/serial.txt" 2>&1 | tail -1)
        echo "        $K"
        R=$(echo "$K" | grep -oE 'ratio [0-9]+' | grep -oE '[0-9]+')
        ge "$1/$2: Titelschrift im BILD, gemessen" "${R:-0}" "$(( $3 / 100 ))"
    fi
done

echo "== G. die Bilder werden gemessen =="
for d in B D F-day F-night; do
    if [ -s "$TMPD/$d/desktop.ppm" ]; then
        python3 tools/softui/check.py "$TMPD/$d/desktop.ppm" \
            "$TMPD/$d/serial.txt" > "$TMPD/$d.pruef" 2>&1
        R=$?
        tail -1 "$TMPD/$d.pruef" | sed 's/^/        /'
        if [ $R -eq 0 ]; then
            ok "$d: keine leere, abgeschnittene oder ueberlappende Beschriftung"
        else
            bad "$d: Beanstandungen"
            head -8 "$TMPD/$d.pruef" | sed 's/^/          /'
        fi
    fi
done

echo
echo "SOFTUI: $P bestanden, $F gefallen"
[ "$F" -eq 0 ]
