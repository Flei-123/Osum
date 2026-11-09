#!/usr/bin/env bash
#
# Verwendung:  bash tools/i18n/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
export FIRNLIB="$(pwd)/lib"

TMPD=${TMPD:-$(mktemp -d)}
KEEP=${KEEP:-0}
[ "$KEEP" = 1 ] || trap 'rm -rf "$TMPD"' EXIT
mkdir -p "$TMPD"

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', erwartet '$3'"; fi; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }

schau() { local was=$1; shift
    local aus; aus=$(python3 tools/gfx/checkshot.py "$@" 2>&1)
    if [ $? = 0 ]; then ok "$was: $aus"; else bad "$was: $aus"; fi; }
schau_nicht() { local was=$1; shift
    local aus; aus=$(python3 tools/gfx/checkshot.py "$@" 2>&1)
    if [ $? = 0 ]; then bad "$was -- it is there after all"; else ok "$was"; fi; }

command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo "I18N: uebersprungen, qemu-system-x86_64 fehlt"; exit 0; }

SANS=assets/osum-sans.ttf
# ROUND FUI-TEXT: Ring 3 text is drawn by fUi (kernel/user/fuiglyph.fi),
# so its ink is checked against fUi's second version
# (tools/ttf/fuiraster.py). `fui:` selects it in tools/gfx/checkshot.py.
SANS_INK="fui:$SANS"
MONO=assets/osum-mono.ttf
WX=140; WY=60; BORDER=2; TITLE=22
CX=$((WX + BORDER)); CY=$((WY + TITLE))
ZEILE="bootbench gfx wm wig desk einst nostart wmhold wiglong nokbd nosched noproc nofs"

# ===================================================== 1. die Schriften

echo "== 1. the fonts: more than ASCII, and still reproducible =="

python3 tools/i18n/coverage.py "$SANS" "$MONO" > "$TMPD/deckung.txt" 2>&1
cov() { grep -a "i18n-coverage: file=assets/osum-$1.ttf" "$TMPD/deckung.txt" \
        | tail -1 | grep -oE " $2=[0-9]+" | sed 's/.*=//'; }
for f in sans mono; do
    is "osum-$f.ttf bildet Codepunkte ab" "$(cov $f mapped)" "339"
    is "osum-$f.ttf: Latin-1-Ergaenzung vollstaendig (Umlaute, ss)" \
        "$(cov $f latin1)" "96"
    is "osum-$f.ttf: Latin Extended-A vollstaendig" "$(cov $f latin_a)" "128"
    is "osum-$f.ttf traegt U+FFFD, das Fehlerbild des Dekodierers" \
        "$(cov $f fffd)" "1"
    is "osum-$f.ttf: Zeichen, die eine deutsche Oberflaeche braucht und die FEHLEN" \
        "$(cov $f missing)" "0"
done
DEJAVU=${DEJAVU:-/usr/share/fonts/truetype/dejavu}
if [ -f "$DEJAVU/DejaVuSans.ttf" ]; then
    python3 tools/ttf/subset.py "$DEJAVU/DejaVuSans.ttf" "$TMPD/alt.ttf" \
        --set ascii > "$TMPD/alt.txt" 2>&1
    python3 tools/i18n/coverage.py "$TMPD/alt.ttf" > "$TMPD/altd.txt" 2>&1
    az=$(grep -a 'i18n-coverage' "$TMPD/altd.txt" | grep -oE ' mapped=[0-9]+' | sed 's/.*=//')
    am=$(grep -a 'i18n-coverage' "$TMPD/altd.txt" | grep -oE ' missing=[0-9]+' | sed 's/.*=//')
    is "GEGENPROBE: der alte Ausschnitt (--set ascii) bildet nur ab" "$az" "95"
    if [ "${am:-0}" -gt 0 ]; then
        ok "CONTROL: and it lacks $am of the characters a German UI needs"
    else
        bad "CONTROL: the old subset allegedly lacks nothing"
    fi
    python3 tools/ttf/subset.py "$DEJAVU/DejaVuSans.ttf" "$TMPD/neu.ttf" \
        >/dev/null 2>&1
    python3 tools/ttf/subset.py "$DEJAVU/DejaVuSansMono.ttf" "$TMPD/neum.ttf" \
        >/dev/null 2>&1
    # r399 (design audit): the proportional face is Inter now (tools/design/mkfont.py);
    # the DejaVu cut above stays as the counter-proof that the old set is a different file
    if [ -f assets/src/Inter-Regular.ttf ] && python3 -c "import fontTools, uharfbuzz" 2>/dev/null; then
        python3 tools/design/mkfont.py assets/src/Inter-Regular.ttf "$TMPD/inter.ttf" assets/src/osum-sans.cps \
            >/dev/null 2>&1
        cmp -s "$TMPD/inter.ttf" "$SANS" \
            && ok "osum-sans.ttf is rebuilt octet by octet from Inter Regular" \
            || bad "osum-sans.ttf cannot be reproduced"
    else
        echo "        (Inter source or fontTools/uharfbuzz missing -- cut not recomputed)"
    fi
    cmp -s "$TMPD/neum.ttf" "$MONO" \
        && ok "osum-mono.ttf is rebuilt octet by octet from DejaVu Sans Mono" \
        || bad "osum-mono.ttf cannot be reproduced"
else
    echo "        (DejaVu is not under $DEJAVU -- cut not recomputed)"
fi

# ============================================== 2. kein deutscher Text

echo "== 2. no German UI text left in the source =="

python3 tools/i18n/scan.py > "$TMPD/scan.txt" 2>&1
rc=$?
n=$(grep -oE 'gefunden: [0-9]+' "$TMPD/scan.txt" | grep -oE '[0-9]+$')
is "fest eingebaute deutsche Oberflaechentexte" "${n:-?}" "0"
[ "$rc" = 0 ] || sed 's/^/        /' "$TMPD/scan.txt" | head -20
mkdir -p "$TMPD/schlecht/kernel/user"
cp kernel/user/desktop.fi "$TMPD/schlecht/kernel/user/"
printf 'static mut x: [u8; 12] = "Uebernehmen\\0"\n' \
    >> "$TMPD/schlecht/kernel/user/desktop.fi"
if python3 tools/i18n/scan.py "$TMPD/schlecht" > "$TMPD/scanbad.txt" 2>&1; then
    bad "CONTROL: the checker overlooks a built-in German text"
else
    ok "CONTROL: a built-in German text IS NOTICED ($(grep -oE 'gefunden: [0-9]+' "$TMPD/scanbad.txt"))"
fi

# ==================================================== 3. der Katalog

echo "== 3. die Sprachdateien =="

for l in en de; do
    [ -f "locale/$l/messages" ] && ok "locale/$l/messages is in the tree" \
        || bad "locale/$l/messages fehlt"
done
python3 tools/i18n/quota.py > "$TMPD/quota.txt" 2>&1 \
    && ok "$(head -1 "$TMPD/quota.txt")" \
    || { bad "the coverage cannot be computed"; cat "$TMPD/quota.txt"; }
sed 's/^/        /' "$TMPD/quota.txt" | tail -n +2

python3 tools/i18n/translit.py --zaehle > "$TMPD/translit.txt" 2>&1
TRC=$?
sed 's/^/        /' "$TMPD/translit.txt"
if [ "$TRC" = 0 ]; then
    ok "no transliteration in locale/de and in the bundle labels"
elif [ "$TRC" = 2 ]; then
    bad "a text no longer fits its buffer (see ZU ENG)"
else
    bad "Umschrift gefunden, wo ein Umlaut hingehoert"
fi
TU=$(grep -oE 'umlaute=[0-9]+' "$TMPD/translit.txt" | tail -1 | cut -d= -f2)
if [ "${TU:-0}" -ge 50 ]; then
    ok "echte Umlautzeichen in den deutschen Texten: $TU"
else
    bad "only $TU real umlaut characters -- too few for German"
fi

rm -rf "$TMPD/tw"
mkdir -p "$TMPD/tw/locale/de" "$TMPD/tw/kernel/user" "$TMPD/tw/assets/apps/x.osp"
cp kernel/user/msg.fi kernel/user/appdir.fi "$TMPD/tw/kernel/user/"
sed 's/Übernehmen/Uebernehmen/' locale/de/messages > "$TMPD/tw/locale/de/messages"
printf 'name=Editor\ninfo=Text schreiben und aendern\n' \
    > "$TMPD/tw/assets/apps/x.osp/INFO"
if OSUM_ROOT="$TMPD/tw" python3 tools/i18n/translit.py \
        > "$TMPD/translit-neg.txt" 2>&1; then
    bad "the transliteration check stays green when the transliteration returns"
else
    NF=$(grep -oE 'umschrift=[0-9]+' "$TMPD/translit-neg.txt" | cut -d= -f2)
    if [ "${NF:-0}" -ge 2 ]; then
        ok "Gegenprobe: zurueckgeschriebene Umschrift wird rot ($NF Funde)"
    else
        bad "control: only $NF findings, expected at least 2"
    fi
fi

echo "== 4. build: kernel, six programs, two images =="

bash tools/i18n/build.sh "$TMPD/en" > "$TMPD/build-en.txt" 2>&1 \
    && ok "the English image is ready" \
    || { bad "the image cannot be built"; tail -20 "$TMPD/build-en.txt"; exit 1; }
sed 's/^/        /' "$TMPD/build-en.txt"
LANG_SET=de bash tools/i18n/build.sh "$TMPD/de" > "$TMPD/build-de.txt" 2>&1 \
    && ok "the German image is ready" \
    || { bad "the German image cannot be built"; exit 1; }

echo "== 5. ring 3: the decoder, the catalog, the keyboard =="

cp "$TMPD/en/disk.img" "$TMPD/t.img"
timeout 180 $QEMU_X86 -kernel "$TMPD/en/k.mb" -m 256 \
    -append "osum nokbd nosched noproc nofs noring3 script=i18nt;exit" \
    -serial "file:$TMPD/i18nt.txt" -display none -no-reboot \
    -drive "file=$TMPD/t.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
p=$(grep -aoE 'i18n: pass=[0-9]+' "$TMPD/i18nt.txt" | tail -1 | sed 's/.*=//')
f=$(grep -aoE 'fail=[0-9]+' "$TMPD/i18nt.txt" | tail -1 | sed 's/.*=//')
is "Zusagen in Ring 3, gescheitert" "${f:-?}" "0"
ok "Zusagen in Ring 3, erfuellt: ${p:-0}"
grep -a '^i18n: bad' "$TMPD/i18nt.txt" | sed 's/^/        /'

# ================================================ 6. der Bildschirm

echo "== 6. the same screen in English and in German =="

lauf() { # verzeichnis name [monitordatei]
    local d=$1 n=$2 mon=${3:-}
    local sock="$d/mon-$n.sock"
    rm -f "$sock" "$d/$n.txt" "$d/$n.ppm"
    cp -f "$d/disk.img" "$d/live-$n.img"
    timeout 240 $QEMU_X86 -kernel "$d/k.mb" -m 256 -append "$ZEILE" \
        -serial "file:$d/$n.txt" -display none -no-reboot -vga std \
        -monitor "unix:$sock,server,nowait" \
        -drive "file=$d/live-$n.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$! i=0
    while [ $i -lt 1500 ]; do
        grep -qaE '^wm: hold' "$d/$n.txt" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.15; i=$((i + 1))
    done
    sleep 1
    [ -n "$mon" ] && python3 tools/wm/monitor.py "$sock" "$mon" \
        > "$d/$n.monlog" 2>&1
    python3 tools/gfx/screenshot.py "$sock" "$d/$n.ppm" 25 > "$d/$n.shot" 2>&1
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    rm -f "$sock"
}

lauf "$TMPD/en" en
lauf "$TMPD/de" de
[ -s "$TMPD/en/en.ppm" ] && ok "the English screenshot is ready ($(stat -c%s "$TMPD/en/en.ppm") Oktette)" \
    || { bad "kein englisches Bildschirmfoto"; }
[ -s "$TMPD/de/de.ppm" ] && ok "the German screenshot is ready" \
    || bad "kein deutsches Bildschirmfoto"

SCENE="python3 tools/i18n/scene.py"

scene_has() {
    $SCENE find "$1" "$2" ${4:-wlib} >/dev/null 2>&1 && ok "$3" \
        || bad "$3 -- '$2' missing in the scene trace"
}

scene_pixels() {
    local trace=$1 shot=$2 text=$3 size=$4 source=${5:-wlib}
    local x y w fr fg fb r g b
    read -r x y w < <($SCENE find "$trace" "$text" "$source") \
        || { bad "'$text' missing in the scene trace"; return; }
    read -r fr fg fb < <($SCENE colors "$trace" "$text" "$source")
    read -r r g b < <($SCENE ground "$shot" "$x" "$y")
    schau "'$text' stands on the screen pixel-exact" \
        tchain "$shot" "$SANS_INK" "$size" "$x" "$y" "$fr" "$fg" "$fb" \
        "$r" "$g" "$b" "$text" 8
}

scene_ink() {
    local trace=$1 shot=$2 text=$3 source=${4:-wlib}
    local x y w
    read -r x y w < <($SCENE find "$trace" "$text" "$source") \
        || { bad "'$text' missing in the scene trace"; return; }
    local n; n=$($SCENE ink "$shot" "$x" "$y" "$w") \
        && ok "'$text' has ink at its reported place ($n pixels)" \
        || bad "'$text' is reported but nothing is painted there ($n pixels)"
}

EF="$TMPD/en/en.txt"; DF="$TMPD/de/de.txt"
scene_has "$EF" "Time & language" "English: the navigation names 'Time & language'"
scene_has "$DF" "Zeit & Sprache" "German: the navigation names 'Zeit & Sprache'"
scene_has "$EF" "ready" "English: the status field says 'ready'"
scene_has "$DF" "bereit" "German: the status field says 'bereit'"
hasnot "$DF" "/etc/schemata" "and no path was translated into German"

scene_pixels "$EF" "$TMPD/en/en.ppm" "Time & language" 14
scene_pixels "$DF" "$TMPD/de/de.ppm" "Zeit & Sprache" 14
scene_pixels "$EF" "$TMPD/en/en.ppm" "Settings" 15 taskbar
scene_pixels "$DF" "$TMPD/de/de.ppm" "Einstellungen" 15 taskbar

d=$(python3 tools/i18n/diff.py "$TMPD/en/en.ppm" "$TMPD/de/de.ppm" 2>&1)
case "$d" in
    0*) bad "the two screenshots are IDENTICAL" ;;
    *)  ok "the two screenshots differ: $d" ;;
esac

echo "== 7. switching the language -- with the mouse, in ONE run =="

abs_point() { # trace text -> "x y" of the middle of the text
    local x y w
    read -r x y w < <($SCENE find "$1" "$2") || return 1
    echo "$((x + w / 2)) $((y - 5))"
}
menu_field() { grep -a 'settings: menu open' "$1" | tail -1 \
               | grep -oE " $2=[0-9]+" | grep -oE '[0-9]+$'; }

NAV1=$(abs_point "$EF" "Time & language")
if [ -z "$NAV1" ]; then
    bad "the settings window does not report its navigation entry 'Time & language'"
else
    ok "navigation entry 'Time & language' is at $NAV1"
    python3 tools/i18n/mouse.py $NAV1 > "$TMPD/click1.mon"
    lauf "$TMPD/en" tab "$TMPD/click1.mon"
    scene_has "$TMPD/en/tab.txt" "Language" "one click on the category lists the Language page"
    NAV2=$(abs_point "$TMPD/en/tab.txt" "Language")
    python3 tools/i18n/mouse.py $NAV1 $NAV2 > "$TMPD/click2.mon"
    lauf "$TMPD/en" page "$TMPD/click2.mon"
    scene_has "$TMPD/en/page.txt" "Language of the surface:" \
        "a second click opens the language page"
    COMBO=$(abs_point "$TMPD/en/page.txt" "English")
    if [ -z "$COMBO" ]; then
        bad "the language page reports no selection field"
    else
        python3 tools/i18n/mouse.py $NAV1 $NAV2 $COMBO > "$TMPD/click3.mon"
        lauf "$TMPD/en" menu "$TMPD/click3.mon"
        M="$TMPD/en/menu.txt"
        mx=$(menu_field "$M" x); my=$(menu_field "$M" y)
        mrh=$(menu_field "$M" rh); mrows=$(menu_field "$M" rows)
        APPLY=$(abs_point "$M" "Apply")
        if [ -z "${mx:-}" ] || [ -z "${mrh:-}" ] || [ -z "$APPLY" ]; then
            bad "the selection list or the button is not reported"
        else
            ok "the list has ${mrows:-?} rows of $mrh pixels, the button is at $APPLY"
            DEUTSCH="$((mx + 100)) $((my + mrh + mrh / 2))"
            python3 tools/i18n/mouse.py $NAV1 $NAV2 $COMBO $DEUTSCH $APPLY \
                --park 600 650 > "$TMPD/click4.mon"
            lauf "$TMPD/en" switch "$TMPD/click4.mon"
            W="$TMPD/en/switch.txt"
            if grep -qa 't=Übernehmen' "$W"; then
                ok "AFTER THE CLICKS THE UI IS IN GERMAN -- without a restart"
            else
                bad "the UI is not German after the click"
                grep -a 'wlib: text' "$W" | tail -8 | cut -c1-150 | sed 's/^/        /'
            fi
            scene_has "$W" "Sprache gewechselt: de" "and the status field says so"
            scene_has "$W" "Zeit & Sprache" "the navigation follows: 'Zeit & Sprache'"
            scene_ink "$W" "$TMPD/en/switch.ppm" "Übernehmen"
            scene_pixels "$W" "$TMPD/en/switch.ppm" "Zeit & Sprache" 14
            hasnot "$W" "t=Uebernehmen" "and the ersatz spelling 'Uebernehmen' is NOT used"
            bash tools/mkfsfi/mkfs.sh cat "$TMPD/en/live-switch.img" \
                /users/root/config/locale > "$TMPD/chosen.txt" 2>/dev/null
            is "/users/root/config/locale holds" \
                "$(tr -d '\n' < "$TMPD/chosen.txt")" "de"
            bash tools/mkfsfi/mkfs.sh list "$TMPD/en/live-switch.img" \
                > "$TMPD/list.txt" 2>/dev/null
            grep -q '^/etc/locale' "$TMPD/list.txt" \
                && bad "the language is under /etc/ -- it belongs to the user" \
                || ok "and NOT under /etc/ -- the language belongs to the user"
        fi
    fi
fi

# ================================================= 8. was es kostet

echo "== 8. what UTF-8 decoding costs when drawing =="

grep -a '^i18n: draw' "$TMPD/en/en.txt" | sed 's/^/        /'
alt=$(grep -aoE 'i18n: draw ascii us=[0-9]+' "$TMPD/en/en.txt" | tail -1 \
      | grep -oE '[0-9]+$')
neu=$(grep -aoE 'i18n: draw utf8 us=[0-9]+' "$TMPD/en/en.txt" | tail -1 \
      | grep -oE '[0-9]+$')
gl=$(grep -aoE 'i18n: draw glyphs us=[0-9]+' "$TMPD/en/en.txt" | tail -1 \
     | grep -oE '[0-9]+$')
if [ -n "${alt:-}" ] && [ -n "${neu:-}" ] && [ "$alt" -gt 0 ]; then
    d=$(( neu - alt ))
    ad=${d#-}
    proz=$(( ad * 100 / alt ))
    vz="+"; [ "$d" -lt 0 ] && vz="-"
    if [ "$d" -le 0 ] || [ "$proz" -lt 15 ]; then
        ok "1000 lines of 40 characters: ${alt} us octet by octet, ${neu} us character by character (${vz}${proz}%, in the noise)"
        ok "per line: $(( alt / 1000 )) us against $(( neu / 1000 )) us -- and fetching the 40 glyphs costs $(( gl / 1000 )) us"
    else
        bad "decoding costs ${vz}${proz}% -- that is noticeable"
    fi
else
    bad "the kernel does not report the cost"
fi

# ============================================ 9. die alten Messungen

echo "== 9. what was green before still is =="

#     tools/wm/run.sh    99 erfuellt, 4 gescheitert
#     tools/k15/run.sh  249 erfuellt, 2 gescheitert
#
BASIS_WM=${BASIS_WM:-4}
BASIS_K15=${BASIS_K15:-2}

for r in wm k15; do
    [ -f "tools/$r/run.sh" ] || continue
    bash "tools/$r/run.sh" > "$TMPD/alt-$r.txt" 2>&1
    z=$(grep -cE '^  OK ' "$TMPD/alt-$r.txt")
    n=$(grep -cE '^  FAIL' "$TMPD/alt-$r.txt")
    basis=$BASIS_WM; [ "$r" = k15 ] && basis=$BASIS_K15
    if [ "${n:-0}" -le "$basis" ]; then
        ok "tools/$r/run.sh: $z erfuellt, $n gescheitert (Ausgangslage: $basis)"
    else
        bad "tools/$r/run.sh: $z erfuellt, $n gescheitert -- Ausgangslage war $basis"
        grep -E '^  FAIL' "$TMPD/alt-$r.txt" | head -10 | sed 's/^/        /'
    fi
done

echo ""
echo "I18N: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
