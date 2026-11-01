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
ZEILE="gfx wm wig desk einst nostart wmhold wiglong nokbd nosched noproc nofs"

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

feld() { # datei id was
    grep -a "settings: feld id=$2 " "$1" | tail -1 \
        | grep -oE " $3=[0-9]+" | tail -1 | grep -oE '[0-9]+$'
}
text_von() { grep -a "settings: feld id=$2 " "$1" | tail -1 | sed 's/.* t=//'; }

EF="$TMPD/en/en.txt"; DF="$TMPD/de/de.txt"
is "der Knopf heisst auf Englisch"  "$(text_von "$EF" 5)" "Apply"
is "und auf Deutsch"                "$(text_von "$DF" 5)" "Übernehmen"
is "das Statusfeld auf Englisch"    "$(text_von "$EF" 42)" "ready"
is "und auf Deutsch"                "$(text_von "$DF" 42)" "bereit"

case "$(text_von "$DF" 1)" in
    *"/etc/schemas"*) ok "the German text names the path UNCHANGED: $(text_von "$DF" 1)" ;;
    *) bad "the path was translated: $(text_von "$DF" 1)" ;;
esac
hasnot "$DF" "/etc/schemata" "und kein Pfad wurde eingedeutscht"

ex=$(feld "$EF" 5 x); eb=$(feld "$EF" 5 base)
dx=$(feld "$DF" 5 x); db=$(feld "$DF" 5 base)
schau "der englische Knopf steht bildpunktgenau da" \
    tchain "$TMPD/en/en.ppm" "$SANS_INK" 15 $((CX + ex)) $((CY + eb)) \
    230 230 230 57 64 74 "Apply" 8
schau "DER DEUTSCHE KNOPF AUCH -- MIT ECHTEM UMLAUT" \
    tchain "$TMPD/de/de.ppm" "$SANS_INK" 15 $((CX + dx)) $((CY + db)) \
    230 230 230 57 64 74 "Übernehmen" 8
schau_nicht "und die Ersatzschreibung 'Uebernehmen' steht dort NICHT" \
    tchain "$TMPD/de/de.ppm" "$SANS_INK" 15 $((CX + dx)) $((CY + db)) \
    230 230 230 57 64 74 "Uebernehmen" 8
lx=$(feld "$DF" 1 x); lb=$(feld "$DF" 1 base)
schau "der uebersetzte Satz mit dem unuebersetzten Pfad steht auf dem Schirm" \
    tchain "$TMPD/de/de.ppm" "$SANS_INK" 15 $((CX + lx)) $((CY + lb)) \
    230 230 230 30 34 40 "Farbschema (aus /etc/schemas):" 8

has "$EF" "taskbar: text net" "die Taskleiste meldet ihr Netzfeld"
grep -a 'taskbar: text net' "$EF" | tail -1 | grep -q 'no network' \
    && ok "auf Englisch: no network" || bad "the taskbar is not English"
grep -a 'taskbar: text net' "$DF" | tail -1 | grep -q 'kein Netz' \
    && ok "in German: kein Netz" || bad "the taskbar is not German"

d=$(python3 tools/i18n/diff.py "$TMPD/en/en.ppm" "$TMPD/de/de.ppm" 2>&1)
case "$d" in
    0*) bad "the two screenshots are IDENTICAL" ;;
    *)  ok "the two screenshots differ: $d" ;;
esac

echo "== 7. switching the language -- with the mouse, in ONE run =="

lauf "$TMPD/en" vor
rfeld() { grep -a "settings: reiter nr=$1" "$2" | tail -1 \
          | grep -oE " $3=[0-9]+" | grep -oE '[0-9]+$'; }
rx=$(rfeld 5 "$TMPD/en/vor.txt" x)
ry=$(rfeld 5 "$TMPD/en/vor.txt" y)
rw=$(rfeld 5 "$TMPD/en/vor.txt" w)
rh=$(rfeld 5 "$TMPD/en/vor.txt" h)
if [ -z "${rx:-}" ]; then
    bad "the program does not report the position of its tabs"
else
    ok "der Reiter 'Language' liegt bei x=$rx y=$ry w=$rw h=$rh"
    TX=$((CX + rx + rw / 2)); TY=$((CY + ry + rh / 2))
    python3 tools/i18n/mouse.py "$TX" "$TY" > "$TMPD/klick1.mon"
    lauf "$TMPD/en" tab "$TMPD/klick1.mon"
    has "$TMPD/en/tab.txt" "t=Language of the surface:" \
        "ein Klick auf den Reiter oeffnet die Sprachseite"
    zeile_von() { grep -a 'settings: feld' "$1" | grep " kind=$2 " \
                  | tail -1; }
    cx=$(grep -a 'settings: feld' "$TMPD/en/tab.txt" | grep ' kind=9 ' \
         | head -1 | grep -oE ' x=[0-9]+' | grep -oE '[0-9]+')
    cb=$(grep -a 'settings: feld' "$TMPD/en/tab.txt" | grep ' kind=9 ' \
         | head -1 | grep -oE ' base=[0-9]+' | grep -oE '[0-9]+')
    bx=$(zeile_von "$TMPD/en/tab.txt" 2 | grep -oE ' x=[0-9]+' | grep -oE '[0-9]+')
    bb=$(zeile_von "$TMPD/en/tab.txt" 2 | grep -oE ' base=[0-9]+' | grep -oE '[0-9]+')
    if [ -z "${cx:-}" ] || [ -z "${bx:-}" ]; then
        bad "the language page reports no selection field or no button"
    else
        ok "the selection field is at x=$cx base=$cb, the button at x=$bx base=$bb"
        python3 tools/i18n/mouse.py "$TX" "$TY" \
            $((CX + cx + 30)) $((CY + cb - 6)) \
            $((CX + bx + 10)) $((CY + bb - 6)) \
            --park $((WX + 500)) $((WY + 380)) > "$TMPD/klick3.mon"
        lauf "$TMPD/en" wechsel "$TMPD/klick3.mon"
        W="$TMPD/en/wechsel.txt"
        if grep -qa 't=Übernehmen' "$W"; then
            ok "AFTER THE THREE CLICKS THE UI IS IN GERMAN -- without a restart"
        else
            bad "the UI is not German after the click"
            grep -a 'settings: feld' "$W" | tail -8 | sed 's/^/        /'
        fi
        has "$W" "t=Sprache gewechselt: de" "und das Statusfeld sagt es"
        if grep -a 'taskbar: text net' "$W" | tail -1 | grep -q 'kein Netz'; then
            ok "and the TASKBAR, a DIFFERENT process, follows: 'kein Netz' instead of 'no network'"
        else
            bad "the taskbar stays English: $(grep -a 'taskbar: text net' "$W" | tail -1)"
        fi
        # BILDPUNKTGENAU, in DEMSELBEN Lauf, in dem vorher Englisch stand.
        wx=$(zeile_von "$W" 2 | grep -oE ' x=[0-9]+' | grep -oE '[0-9]+')
        wb=$(zeile_von "$W" 2 | grep -oE ' base=[0-9]+' | grep -oE '[0-9]+')
        schau "der umgestellte Knopf steht bildpunktgenau auf dem Schirm" \
            tchain "$TMPD/en/wechsel.ppm" "$SANS_INK" 15 $((CX + wx)) $((CY + wb)) \
            230 230 230 57 64 74 "Übernehmen" 8
        nx=$(grep -a 'taskbar: text net' "$W" | tail -1 | grep -oE ' x=[0-9]+' | grep -oE '[0-9]+')
        nb=$(grep -a 'taskbar: text net' "$W" | tail -1 | grep -oE ' base=[0-9]+' | grep -oE '[0-9]+')
        schau "und die umgestellte Taskleiste auch" \
            tchain "$TMPD/en/wechsel.ppm" "$SANS_INK" 15 "$nx" $((572 + nb)) \
            230 230 230 42 47 55 "kein Netz" 8
        python3 tools/osum/mkfs.py cat "$TMPD/en/live-wechsel.img" \
            /users/root/config/locale > "$TMPD/gewaehlt.txt" 2>/dev/null
        is "in /users/root/config/locale steht" \
            "$(tr -d '\n' < "$TMPD/gewaehlt.txt")" "de"
        python3 tools/osum/mkfs.py list "$TMPD/en/live-wechsel.img" \
            > "$TMPD/liste.txt" 2>/dev/null
        grep -q '^/etc/locale' "$TMPD/liste.txt" \
            && bad "the language is under /etc/ -- it belongs to the user" \
            || ok "and NOT under /etc/ -- the language belongs to the user"
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
    if [ "$proz" -lt 15 ]; then
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
