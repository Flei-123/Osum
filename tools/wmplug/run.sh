#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
#
#
#
# Die Bilder landen in docs/shots/wmplug/.
#
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
. tools/lib/userprog.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

TMPD=$(mktemp -d /tmp/wmplug-run-XXXXXX)
[ "${WMPLUG_KEEP:-0}" = 1 ] || trap 'rm -rf "$TMPD"' EXIT
SHOTS="docs/shots/wmplug"
mkdir -p "$SHOTS"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasre() { grep -qaE "$2" "$1" && ok "$3" || bad "$3 -- /$2/ trifft nicht"; }
hasnotre() { grep -qaE "$2" "$1" && bad "$3 -- /$2/ sollte nicht zutreffen" || ok "$3"; }
zahl() { grep -aE "$2" "$1" | tail -1 | grep -oE "$3=-?[0-9]+" | head -1 | sed 's/.*=//'; }

#
#
#     wmplug: tot slot=0 pid=6
#     wmplwm: fokus id=7 vor=0
#     ug: unreg boese grund=1 holte=0 verlor=0
#
flach() { tr -d '\n' < "$1" > "$1.flat"; }
hasflat() { grep -qaE "$2" "$1.flat" && ok "$3" \
    || bad "$3 -- /$2/ does not match in the continuous stream either"; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "WMPLUG: skipped, qemu-system-x86_64 is missing"; exit 0
fi
bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "firnc fehlt"; exit 1; }

# ====================================================== 1. bauen
echo "== 1. bauen =="
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/k.log" 2>&1 \
    && ok "Kernel gebaut ($(stat -c%s "$TMPD/k.mb") Oktette)" \
    || { bad "the kernel does not build"; tail -12 "$TMPD/k.log" | sed 's/^/        /'; }
[ -f "$TMPD/k.mb" ] || { echo; echo "WMPLUG: $pass bestanden, $((fail+1)) gescheitert"; exit 1; }

as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s assembliert nicht"
PROGS="desktop taskbar launcher calc sh
       plugboese plugprobe plugregel pluguhr wmplug
       plugtempo plugspaet"
gebaut=1
for p in $PROGS; do
    up_build vendor/firn/bin/firnc "$p" "$TMPD/$p.o" "$TMPD/$p.elf" \
        "$TMPD/crt.o" kernel/user/user.ld 0 "$TMPD/$p.err" || {
        bad "firnc uebersetzt $p.fi nicht"
        sed 's/^/        /' "$TMPD/$p.err" | head -6; gebaut=0; }
done
[ "$gebaut" = 1 ] && ok "$(echo $PROGS | wc -w) Programme gebaut" \
    || { echo; echo "WMPLUG: $pass bestanden, $fail gescheitert"; exit 1; }

echo "== 2. Ring 3, am Kernabbild nachgesehen =="
nm -a "$TMPD/k.mb.elf" > "$TMPD/sym.txt" 2>/dev/null \
    && ok "the symbol table of the kernel is readable ($(wc -l < "$TMPD/sym.txt") Symbole)" \
    || bad "nm cannot reach $TMPD/k.mb.elf -- without it section 2 measures nothing"
for sym in plugregel__ pluguhr__ plugboese__ plugprobe__ plugtempo__ plugspaet__; do
    if grep -qF "$sym" "$TMPD/sym.txt"; then
        bad "the kernel carries symbols of $sym -- foreign code in ring 0"
    else
        ok "no symbol of $sym in the kernel image"
    fi
done
grep -qF 'wmplug__reg' "$TMPD/sym.txt" \
    && ok "kernel/ui/wmplug.fi itself is in the image (the probe above really measures)" \
    || bad "wmplug__reg is missing from the image -- then the symbol probe says nothing"

# ====================================================== 3. das Abbild
echo "== 3. das Abbild =="
python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
    && ok "the directory tree is ready" || bad "tools/k15/tree.py fehlgeschlagen"
for f in etc/wmplug.conf etc/wmregeln.conf; do
    [ -f "$f" ] && ok "$f is in the tree" || bad "$f fehlt"
done
grep -qE '^boese[[:space:]]+rechte=0x0*1([[:space:]]|$)' etc/wmplug.conf \
    && ok "/etc/wmplug.conf gibt 'boese' genau R_EV_WIN (0x001)" \
    || bad "'boese rechte=0x001' steht nicht mehr in /etc/wmplug.conf"
grep -qE '^uhr[[:space:]].*frist=100([[:space:]]|$)' etc/wmplug.conf \
    && ok "/etc/wmplug.conf gives the widget deadline=100 ticks (1 s)" \
    || bad "'uhr ... frist=100' steht nicht in /etc/wmplug.conf"
grep -qE '^regel[[:space:]].*frist=500([[:space:]]|$)' etc/wmplug.conf \
    && ok "/etc/wmplug.conf gives the rule engine deadline=500 ticks (5 s)" \
    || bad "'regel ... frist=500' steht nicht in /etc/wmplug.conf"
[ -f etc/wmplug.autostart ] \
    && ok "etc/wmplug.autostart is in the tree (the autostart list)" \
    || bad "etc/wmplug.autostart fehlt"

#
printf 'on\n' > "$TMPD/uitrace"
abbild() { # name  [autostart-zeile ...]
    local nm=$1; shift
    : > "$TMPD/auto-$nm.txt"
    local z
    for z in "$@"; do printf '%s\n' "$z" >> "$TMPD/auto-$nm.txt"; done
    local A=(build "$TMPD/disk-$nm.img" 32768 /lib/
        "/lib/mono.ttf=assets/osum-mono.ttf"
        "/lib/sans.ttf=assets/osum-sans.ttf" /bin/)
    local p n
    for p in $PROGS; do
        n=$p; [ "$p" = plugspaet ] && n=uhrspaet
        A+=("/bin/$n=$TMPD/$p.elf")
    done
    A+=(/etc/ "/etc/theme=$TMPD/baum/theme" "/etc/uitrace=$TMPD/uitrace"
        "/etc/wmplug.conf=etc/wmplug.conf"
        "/etc/wmregeln.conf=etc/wmregeln.conf"
        "/etc/wmplug.autostart=$TMPD/auto-$nm.txt")
    while read -r z; do A+=("$z"); done < "$TMPD/baum/liste"
    bash tools/mkfsfi/mkfs.sh "${A[@]}" > "$TMPD/mkfs-$nm.txt" 2>&1
}

abbild basis \
    && ok "the image is built" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs-basis.txt" | head -5; }
cp -f "$TMPD/disk-basis.img" "$TMPD/disk.img" 2>/dev/null

# ====================================================== der Laufhelfer
BASE="gfx wm wig desk wmhold wiglong nokbd nosched noproc nofs wmplug"

warte() { # datei marke pid schritte
    local f=$1 m=$2 pid=$3 n=${4:-900} i=0
    while [ $i -lt "$n" ]; do
        grep -qa "$m" "$f" 2>/dev/null && return 0
        kill -0 "$pid" 2>/dev/null || return 1
        sleep 0.2; i=$((i+1))
    done
    return 1
}

lauf() {
    local name=$1 extra=$2 marke=${3:-} marke2=${4:-}
    local sock="$TMPD/mon-$name.sock" out="$TMPD/$name.txt"
    rm -f "$out" "$sock" "$TMPD/$name.ppm"
    local img="$TMPD/disk.img"
    [ -s "$TMPD/disk-$name.img" ] && img="$TMPD/disk-$name.img"
    cp -f "$img" "$TMPD/live-$name.img"
    timeout 240 $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 \
        -append "$BASE $extra" -serial "file:$out" -display none \
        -no-reboot -vga std -global VGA.edid=off \
        -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        > "$TMPD/$name.qemu" 2>&1 &
    local pid=$!
    if [ -n "$marke" ]; then
        warte "$out" "$marke" "$pid"
        sleep 2
        python3 tools/gfx/screenshot.py "$sock" "$TMPD/$name.ppm" 25 \
            > "$TMPD/$name.shot" 2>&1
        wc -l < "$out" > "$TMPD/$name.marke"
    fi
    if [ -n "$marke2" ]; then
        warte "$out" "$marke2" "$pid"
        sleep 2
        python3 tools/gfx/screenshot.py "$sock" "$TMPD/$name-2.ppm" 25 \
            > "$TMPD/$name-2.shot" 2>&1
    fi
    wait "$pid"; echo "$?" > "$TMPD/$name.rc"
    rm -f "$sock"
    tr -d '\000' < "$out" > "$TMPD/$name.clean"
    flach "$TMPD/$name.clean"
}

sauber() { # name
    local rc; rc=$(cat "$TMPD/$1.rc" 2>/dev/null)
    [ "$rc" = 21 ] && ok "$1: the kernel exits cleanly (21)" \
        || bad "$1: Exitcode $rc statt 21"
}

echo "== 4. Crash: a plugin crashes (SIGSEGV) =="
abbild segv 'boesebar segv' || bad "segv: the image is not built"
lauf segv "" '^plugboese: leiste gesetzt' 'wmplug: tot slot='
S=$TMPD/segv.clean
sauber segv
has "$S" "plugboese: abi=1" "das Plugin hat die Fassung erfragt"
hasre "$S" '^plugboese: slot=[0-9]+ rechte=2049$' \
    "es hat genau die Rechte aus /etc/wmplug.conf (0x801 = 2049: sehen + Leiste)"
has "$S" "plugboese: leiste gesetzt, rc=0" \
    "es hat VOR dem Absturz ein Feld in der Leiste besetzt (WM_PLUG_BAR)"
has "$S" "plugboese: gleich stuerze ich ab" "es sagt an, dass es gleich abstuerzt"
hasre "$S" 'wmplug: tot slot=[0-9]+ pid=[0-9]+' \
    "der Kern hat den Toten selbst abgeholt (reap)"
hasflat "$S" 'unreg boesebar *grund=1' \
    "und abgemeldet mit grund=1 (G_CRASH) -- der Grund steht auf der Leitung"
has "$S" "wm: hold" "der Fensterserver steht noch"
hasnotre "$S" '^(panic|PANIC|kernel panic)' "kein Panik im Kern"
fr_tot=$(zahl "$S" '^wm: vsync=' 'comp')
if [ -n "${fr_tot:-}" ] && [ "$fr_tot" -gt 0 ] 2>/dev/null; then
    ok "the compositor ran $fr_tot rounds despite the crash (wm: comp=)"
else
    bad "keine Zahl 'comp=' -- ohne sie ist 'laeuft weiter' nur Meinung"
fi
has "$S" "wmplug: bilanz" "und der Kern zieht am Ende seine Bilanz"
n_tot=$(grep -ca 'wmplug: tot slot=' "$S")
[ "${n_tot:-0}" = 1 ] \
    && ok "the dead one was collected EXACTLY ONCE (one line 'wmplug: tot')" \
    || bad "'wmplug: tot' steht ${n_tot}x da -- der Kehrbesen laeuft in sich selbst"
k_segv=$(zahl "$S" '^wmplug: bilanz' 'kicks')
[ "${k_segv:-0}" = 1 ] \
    && ok "and counted exactly once (kicks=1 for one crash)" \
    || bad "the balance counts kicks=${k_segv} for ONE crash"
if [ -s "$TMPD/segv-2.ppm" ]; then
    cp -f "$TMPD/segv-2.ppm" "$SHOTS/after-crash.ppm"
    masse=$(python3 tools/gfx/checkshot.py size "$TMPD/segv-2.ppm" 2>/dev/null)
    [ "$masse" = "800 600" ] \
        && ok "photo after the crash: 800x600, the display mode is still set" \
        || bad "the photo after the crash measures '$masse' statt '800 600'"
    nl=$(python3 tools/gfx/checkshot.py nonblank "$TMPD/segv-2.ppm" 0 0 800 600 2>/dev/null \
         | grep -oE '[0-9]+' | head -1)
    if [ -n "${nl:-}" ] && [ "$nl" -gt 100000 ] 2>/dev/null; then
        ok "and $nl of 480000 pixels are not black -- the desktop paints"
    else
        bad "nur '$nl' nichtschwarze Bildpunkte -- der Schirm ist nach dem Absturz leer"
    fi
    python3 -c "from PIL import Image; Image.open('$SHOTS/after-crash.ppm').save('$SHOTS/after-crash.png')" \
        2>/dev/null && rm -f "$SHOTS/after-crash.ppm"
    [ -s "$SHOTS/after-crash.png" ] \
        && ok "the photo is at docs/shots/wmplug/after-crash.png" \
        || bad "after-crash.png was not stored"
else
    bad "no photo after the crash"
fi

#
pzeile=$(grep -a '^taskbar: plug nr=0 ' "$S" | tail -1)
pgeom=$(grep -a '^taskbar: geom ' "$S" | tail -1)
pfeld() { printf '%s' "$1" | grep -oE " $2=[0-9]+" | head -1 | sed 's/.*=//'; }
bx=$(pfeld "$pzeile" x); by=$(pfeld "$pzeile" y)
bw=$(pfeld "$pzeile" w); bh=$(pfeld "$pzeile" h)
tgx=$(pfeld "$pgeom" x); tgy=$(pfeld "$pgeom" y)
tgx=${tgx:-0}; tgy=${tgy:-0}
if [ -n "${bx:-}" ] && [ -n "${bw:-}" ] && [ -s "$TMPD/segv.ppm" ] \
    && [ -s "$TMPD/segv-2.ppm" ]; then
    cx=$((tgx + bx + bw / 2)); cy=$((tgy + by + bh / 2))
    ok "the plugin field of the bar is at x=$bx y=$by w=$bw h=$bh, centre ($cx,$cy)"
    cp -f "$TMPD/segv.ppm" "$SHOTS/before-crash.ppm"
    f1=$(python3 tools/gfx/checkshot.py pixel "$TMPD/segv.ppm" "$cx" "$cy" 2>&1)
    f2=$(python3 tools/gfx/checkshot.py pixel "$TMPD/segv-2.ppm" "$cx" "$cy" 2>&1)
    if [ "$f1" != "$f2" ]; then
        ok "checkshot pixel ($cx,$cy): before [$f1], after the crash [$f2] -- different"
    else
        bad "checkshot pixel ($cx,$cy): vorher und nachher beide [$f1]"
    fi
    python3 -c "from PIL import Image; Image.open('$SHOTS/before-crash.ppm').save('$SHOTS/before-crash.png')" \
        2>/dev/null && rm -f "$SHOTS/before-crash.ppm"
    [ -s "$SHOTS/before-crash.png" ] \
        && ok "the photo BEFORE the crash is at docs/shots/wmplug/before-crash.png" \
        || bad "before-crash.png was not stored"
else
    bad "no two photos or no bar coordinate -- the visible evidence is missing"
fi

# ============================================ 5. die Haenger-Gegenprobe
echo "== 5. Deadline: a plugin hangs in an endless loop =="
abbild hang 'boese hang' || bad "hang: the image is not built"
lauf hang "plugfrist" '^wm: hold'
H=$TMPD/hang.clean
sauber hang
has "$H" "plugboese: ab jetzt hole ich nichts" "das Plugin hoert auf abzuholen"
hasflat "$H" 'unreg boese *grund=2' \
    "die Frist hat gegriffen: abgemeldet mit grund=2 (G_FRIST)"
has "$H" "wm: hold" "der Schreibtisch steht auch danach"
hasnotre "$H" '^(panic|PANIC|kernel panic)' "kein Panik im Kern"
fr_hang=$(zahl "$H" '^wm: vsync=' 'comp')
if [ -n "${fr_hang:-}" ] && [ "$fr_hang" -gt 0 ] 2>/dev/null; then
    ok "even with the hanger the compositor ran $fr_hang rounds"
else
    bad "keine Zahl 'comp=' im Haengerlauf"
fi
if [ -n "${fr_hang:-}" ] && [ -n "${fr_tot:-}" ]; then
    if [ "$fr_hang" -ge $((fr_tot / 2)) ]; then
        ok "frame rounds crash run $fr_tot against hang run $fr_hang -- no collapse"
    else
        bad "frame rounds collapse: $fr_tot against $fr_hang"
    fi
fi

# ============================================= 6. die Rechte-Gegenprobe
echo "== 6. Rights: a plugin reaches for a foreign window =="
abbild greif 'boese greif' || bad "grab: the image is not built"
lauf greif "" '^wm: hold'
G=$TMPD/greif.clean
sauber greif
hasre "$G" '^plugboese: slot=[0-9]+ rechte=1$' \
    "das Plugin hat GENAU R_EV_WIN (0x001) und ausdruecklich KEIN R_ACT_WIN (0x100)"
hasnotre "$G" 'plugboese-lese' \
    "es legt KEIN verborgenes Hilfsfenster mehr an (der Titel kommt nicht vor)"
hasre "$G" 'plugboese: vorher id=[0-9]+ x=[0-9]+ y=[0-9]+' \
    "es hat den Ort des fremden Fensters VORHER gelesen"
hasre "$G" 'plugboese: griff nach fremdem id=[0-9]+ errors=2' \
    "der Griff wird mit -E_RIGHTS (cap.E_RIGHTS = 2) abgewiesen"
hasre "$G" 'plugboese: griff .* deny=1' \
    "und der Kern zaehlt die Abweisung mit (PL_DENY + 1)"
hasre "$G" 'plugboese: nachher id=[0-9]+ x=[0-9]+ y=[0-9]+' \
    "es hat den Ort NACHHER noch einmal gelesen"
has "$G" "plugboese: rights probe: rejected AND nothing moved" \
    "vorher und nachher sind gleich -- die Handlung ist NICHT passiert"
vx=$(zahl "$G" '^plugboese: vorher' 'x'); vy=$(zahl "$G" '^plugboese: vorher' 'y')
nx=$(zahl "$G" '^plugboese: nachher' 'x'); ny=$(zahl "$G" '^plugboese: nachher' 'y')
if [ -n "${vx:-}" ] && [ "$vx" = "${nx:-}" ] && [ "$vy" = "${ny:-}" ]; then
    ok "nachgerechnet: ($vx,$vy) vorher = ($nx,$ny) nachher"
else
    bad "the position has changed: ($vx,$vy) -> ($nx,$ny)"
fi
if [ "${nx:-x}" = 7 ] && [ "${ny:-y}" = 7 ]; then
    bad "the window is at (7,7) -- the grab worked"
else
    ok "the window is NOT at (7,7), the target of the grab"
fi
#
hasre "$G" 'plugboese: schwelle: griffe=[0-9]+ letzte=[0-9]+ deny=[0-9]+' \
    "das Plugin hat in einer Schleife weitergegriffen"
hasflat "$G" 'unreg boese *grund=3' \
    "der Kern meldet es mit grund=3 (G_RIGHTS) ab -- die Schwelle hat gegriffen"
d_ges=$(zahl "$G" '^wmplug: bilanz' 'deny')
if [ "${d_ges:-0}" = 8 ]; then
    ok "the balance counts deny=8 -- exactly the threshold, no more"
else
    bad "die Bilanz zaehlt deny='${d_ges}' statt 8 (wmplug.DENY_MAX)"
fi
l_rc=$(grep -aoE 'schwelle: griffe=[0-9]+ letzte=[0-9]+' "$G" | tail -1 \
    | grep -oE 'letzte=[0-9]+' | sed 's/.*=//')
if [ "${l_rc:-0}" = 3 ]; then
    ok "the last grabs get -E_NOTFOUND (3): the slot is gone, not just blocked"
else
    bad "the last grab reports '${l_rc}' statt 3 (E_NOTFOUND)"
fi
has "$G" "wm: hold" "und der Schreibtisch steht auch nach der Abmeldung noch"

echo "== 7. the interface once all the way through, and the speed =="
lauf probe "wigapp=/bin/plugprobe,plugprobe,zkey" '^wm: hold'
P=$TMPD/probe.clean
sauber probe
has "$P" "probe: abi=1" "PL_ABI meldet die Fassung 1 -- die Schnittstelle ist versioniert"
hasre "$P" '^probe: slot=[0-9]+' "der Prueflauf hat einen Tafelplatz"
hasre "$P" '^probe: key without rc=-[0-9]+' \
    "ein Kuerzel OHNE R_ACT_KEY wird abgewiesen"
hasre "$P" '^probe: key mit rc=[0-9]+' \
    "und MIT Gewaehrung (WM_PLUG_GRANT) angenommen"
hasre "$P" '^probe: ev typ=[0-9]+ dat=[0-9]+' \
    "es sind wirklich Ereignisse durch den Ring gelaufen"
f1=$(grep -aE '^probe: frames=' "$P" | head -1 | sed 's/.*=//')
f2=$(grep -aE '^probe: frames=' "$P" | tail -1 | sed 's/.*=//')
l1=$(grep -aE '^probe: latus=' "$P" | head -1 | sed 's/.*=//')
l2=$(grep -aE '^probe: latus=' "$P" | tail -1 | sed 's/.*=//')
if [ -n "${f1:-}" ] && [ -n "${f2:-}" ] && [ "$f2" -gt "$f1" ] 2>/dev/null; then
    ok "frames before the load: $f1, after the load: $f2 (the server kept painting)"
else
    bad "no two frame counts from the same run ($f1 / $f2)"
fi
if [ -n "${l1:-}" ] && [ -n "${l2:-}" ]; then
    ok "latency per frame before ${l1} us, after ${l2} us -- both numbers are in the report"
else
    bad "no two latency numbers ($l1 / $l2)"
fi
hasre "$P" '^probe: ende, ?rc=|^probe: ende' "der Prueflauf meldet sich sauber ab"

echo "== 7b. frame rate and latency: 60 frames before, 60 frames after loading =="
lauf tempo "wighalt=50 wigapp=/bin/plugtempo,plugtempo,bilder=60" 'tempo: ende'
T=$TMPD/tempo.clean
sauber tempo
hasre "$T" '^tempo: vor bilder=[0-9]+' "das Messfenster VOR dem Laden steht auf der Leitung"
hasre "$T" '^tempo: nach bilder=[0-9]+' "und das Messfenster NACH dem Laden auch"
has "$T" "wmplug: reg uhr" "zwischen den beiden Fenstern wurde wirklich ein Plugin geladen"
tv_b=$(zahl "$T" '^tempo: vor '  'bilder'); tn_b=$(zahl "$T" '^tempo: nach ' 'bilder')
tv_u=$(zahl "$T" '^tempo: vor '  'us');     tn_u=$(zahl "$T" '^tempo: nach ' 'us')
tv_f=$(zahl "$T" '^tempo: vor '  'fps10');  tn_f=$(zahl "$T" '^tempo: nach ' 'fps10')
tv_mi=$(zahl "$T" '^tempo: vor ' 'min');    tn_mi=$(zahl "$T" '^tempo: nach ' 'min')
tv_ma=$(zahl "$T" '^tempo: vor ' 'max');    tn_ma=$(zahl "$T" '^tempo: nach ' 'max')
if [ "${tv_b:-0}" -ge 60 ] 2>/dev/null && [ "${tn_b:-0}" -ge 60 ] 2>/dev/null; then
    ok "both windows really have 60 frames (before $tv_b, after $tn_b)"
else
    bad "the measuring windows are too small: before '$tv_b', nach '$tn_b' Bilder"
fi
if [ -n "${tv_u:-}" ] && [ -n "${tn_u:-}" ]; then
    ok "frame time before loading ${tv_u} us (min ${tv_mi}, max ${tv_ma}), after loading ${tn_u} us (min ${tn_mi}, max ${tn_ma})"
    ok "frame rate before loading ${tv_f} (x10), after loading ${tn_f} (x10) -- both numbers go into the report"
else
    bad "no two frame times from the same run ('$tv_u' / '$tn_u')"
fi
if [ -n "${tv_u:-}" ] && [ -n "${tn_u:-}" ] && [ "${tv_u:-0}" -gt 0 ] 2>/dev/null; then
    if [ "$tn_u" -le $(( tv_u * 2 )) ]; then
        ok "the frame time stays in the same order of magnitude: ${tv_u} us -> ${tn_u} us"
    else
        bad "the frame time more than doubles: ${tv_u} us -> ${tn_u} us"
    fi
fi
if [ -n "${tv_f:-}" ] && [ -n "${tn_f:-}" ] && [ "${tv_f:-0}" -gt 0 ] 2>/dev/null; then
    if [ "$tn_f" -ge $(( tv_f * 2 / 3 )) ]; then
        ok "no speed drop: ${tn_f} is at least two thirds of ${tv_f} (frame rate x10)"
    else
        bad "speed drop after loading: ${tv_f} -> ${tn_f} (frame rate x10)"
    fi
fi

echo "== 7c. wmplug enable an einem LAUFENDEN Plugin =="
lauf spaet "wigapp=/bin/uhrspaet,uhrspaet,wartems=3000,rounds=40" \
    'uhrspaet: before enable' 'taskbar: text plug '
SP=$TMPD/spaet.clean
sauber spaet
has "$SP" "pluguhr: KEIN recht R_ACT_BAR" \
    "das Widget startet OHNE R_ACT_BAR -- der Text wird abgewiesen"
hasre "$SP" 'uhrspaet: (grant|enable) r=' \
    "danach wird gewaehrt (WM_PLUG_GRANT -- derselbe Ruf wie 'wmplug enable uhr')"
has "$SP" "taskbar: text plug " "und die Leiste malt den Widget-Text"
n_reg=$(grep -ca 'wmplug: reg uhr' "$SP")
[ "${n_reg:-0}" = 1 ] \
    && ok "exactly ONE registration (wmplug: reg uhr) -- no process restart" \
    || bad "'wmplug: reg uhr' steht ${n_reg}x da -- da hat sich etwas neu angemeldet"
n_hold_sp=$(grep -ca '^wm: hold' "$SP")
[ "${n_hold_sp:-0}" = 1 ] \
    && ok "and the window server ran through (exactly one 'wm: hold')" \
    || bad "'wm: hold' steht ${n_hold_sp}x da"
zl=$(grep -a '^taskbar: plug nr=0 ' "$TMPD/spaet.clean" | tail -1)
gl=$(grep -a '^taskbar: geom ' "$TMPD/spaet.clean" | tail -1)
feld() { printf '%s' "$1" | grep -oE " $2=[0-9]+" | head -1 | sed 's/.*=//'; }
px=$(feld "$zl" x); py=$(feld "$zl" y); pw=$(feld "$zl" w); ph=$(feld "$zl" h)
gx=$(feld "$gl" x); gy=$(feld "$gl" y); gx=${gx:-0}; gy=${gy:-0}
if [ -z "${px:-}" ] || [ ! -s "$TMPD/spaet.ppm" ] || [ ! -s "$TMPD/spaet-2.ppm" ]; then
    bad "without widget box or without two photos there is nothing to recompute (box '$zl')"
else
    read -r dz dx dy <<<"$(python3 - "$TMPD/spaet.ppm" "$TMPD/spaet-2.ppm" \
        "$((gx+px))" "$((gy+py))" "$pw" "$ph" <<'PYD'
import sys
def load(p):
    d = open(p, 'rb').read(); t = []; i = 2
    while len(t) < 3:
        while i < len(d) and d[i:i+1].isspace(): i += 1
        if d[i:i+1] == b'#':
            while d[i:i+1] != b'\n': i += 1
            continue
        j = i
        while j < len(d) and not d[j:j+1].isspace(): j += 1
        t.append(int(d[i:j])); i = j
    return t[0], t[1], d[i+1:]
a = load(sys.argv[1]); b = load(sys.argv[2])
x0, y0, w, h = (int(v) for v in sys.argv[3:7])
n = 0; erst = (-1, -1)
for y in range(y0, min(y0 + h, a[1], b[1])):
    for x in range(x0, min(x0 + w, a[0], b[0])):
        o = (y * a[0] + x) * 3
        if a[2][o:o+3] != b[2][o:o+3]:
            n += 1
            if erst == (-1, -1): erst = (x, y)
print(n, erst[0], erst[1])
PYD
)"
    if [ "${dz:-0}" -gt 40 ]; then
        ok "in the widget box $dz pixels differ between before and after"
    else
        bad "before and after differ in the box in only ${dz:-0} pixels"
    fi
    if [ "${dx:-0}" -ge 0 ] && [ "${dx:--1}" != "-1" ]; then
        v1=$(python3 tools/gfx/checkshot.py pixel "$TMPD/spaet.ppm" "$dx" "$dy" 2>&1)
        v2=$(python3 tools/gfx/checkshot.py pixel "$TMPD/spaet-2.ppm" "$dx" "$dy" 2>&1)
        if [ "$v1" != "$v2" ]; then
            ok "checkshot pixel ($dx,$dy): before granting [$v1], after [$v2] -- different"
        else
            bad "checkshot pixel ($dx,$dy): beide [$v1]"
        fi
    else
        bad "not a single different pixel in the box -- enabling had no effect"
    fi
    ecke2=$(python3 tools/gfx/checkshot.py pixel "$TMPD/spaet-2.ppm" \
        "$((gx+px+1))" "$((gy+py+1))" 2>/dev/null)
    tinte=$(python3 tools/gfx/checkshot.py area "$TMPD/spaet-2.ppm" \
        "$((gx+px))" "$((gy+py))" "$pw" "$ph" $ecke2 2>&1 | grep -oE '^[0-9]+')
    if [ "${tinte:-0}" -gt 20 ]; then
        ok "in the widget box there are $tinte ink pixels after enabling"
    else
        bad "after enabling there is no text in the box (${tinte:-0} points)"
    fi
    cp -f "$TMPD/spaet.ppm" "$TMPD/enable-vorher.ppm"
    cp -f "$TMPD/spaet-2.ppm" "$TMPD/enable-nachher.ppm"
    for b in enable-vorher enable-nachher; do
        python3 tools/gfx/ppm2png.py "$TMPD/$b.ppm" "$SHOTS/$b.png" >/dev/null 2>&1
    done
    [ -s "$SHOTS/enable-nachher.png" ] \
        && ok "the two photos are at docs/shots/wmplug/enable-vorher.png and -nachher.png" \
        || bad "the two photos of enabling were not stored"
fi

# ===================================================== 8. die Verwaltung
echo "== 8. /bin/wmplug: list, info, disable, list =="
abbild verw 'uhr rounds=40' || bad "revoke: the image is not built"
lauf verw "wigapp=/bin/wmplug,probe,uhr" '^wm: hold'
V=$TMPD/verw.clean
sauber verw
has "$V" "wmplug: reg uhr" "das Widget ist angemeldet -- es gibt etwas zu verwalten"
has "$V" "wmplug: abi=" "wmplug list nennt die Fassung der Schnittstelle"
hasre "$V" 'Plugins [0-9]+ von [0-9]+' "und sagt, wie viele Plaetze belegt sind"
has "$V" "desktop: autostart [uhr" \
    "der Schreibtisch hat die Autostart-Liste gelesen und die Zeile ausgefuehrt"
hasre "$V" 'wmplug: start /bin/pluguhr rc=[0-9]+' \
    "und wmplug enable hat das Plugin WIRKLICH gestartet (SYS_EXEC)"
has "$V" "wmprobe: list vorher" "list lief vor dem Abschalten"
has "$V" "wmprobe: info" "info lief"
has "$V" "wmprobe: disable" "disable lief"
has "$V" "wmprobe: list nachher" "und list noch einmal danach"
hasflat "$V" 'unreg uhr *grund=4' \
    "der Kern meldet die Abmeldung mit grund=4 (G_USER) -- nicht Absturz, nicht Frist"
v1=$(grep -a 'Plugins [0-9]* von' "$V" | head -1 | grep -oE 'Plugins [0-9]+' | grep -oE '[0-9]+')
v2=$(grep -a 'Plugins [0-9]* von' "$V" | tail -1 | grep -oE 'Plugins [0-9]+' | grep -oE '[0-9]+')
if [ "${v1:-x}" = 1 ] && [ "${v2:-x}" = 0 ]; then
    ok "the table counts $v1 plugin before disabling, $v2 after -- measured by state"
else
    bad "the table counts '$v1' vorher und '$v2' nachher (erwartet 1 und 0)"
fi
has "$V" "pluguhr: end" "und das Widget selbst ist wirklich gegangen"
n_hold=$(grep -ca '^wm: hold' "$V")
[ "${n_hold:-0}" = 1 ] \
    && ok "the window server was NOT restarted in the process (exactly one 'wm: hold')" \
    || bad "'wm: hold' steht ${n_hold}x da -- da ist etwas neu gestartet"

echo "== 8b. two plugins, two deadlines, one run =="
abbild frist 'regel demo laut' 'uhr rounds=40' || bad "deadline: the image is not built"
lauf frist "" '^wm: hold'
F=$TMPD/frist.clean
sauber frist
hasflat "$F" 'reg uhr *slot=[0-9]+ rechte=0x807 frist=100' \
    "das Widget ist mit SEINER Frist angetreten: 100 Ticks (1 s)"
hasflat "$F" 'reg regel *slot=[0-9]+ rechte=0x301 frist=500' \
    "die Regel-Engine mit IHRER: 500 Ticks (5 s)"
k_frist=$(zahl "$F" '^wmplug: bilanz' 'kicks')
p_frist=$(zahl "$F" '^wmplug: bilanz' 'plugs')
if [ "${k_frist:-x}" = 0 ]; then
    ok "not a single ejection in this run (kicks=0) -- both deadlines hold"
else
    bad "the balance counts kicks=${k_frist} -- one of the two was thrown out"
fi
if [ "${p_frist:-0}" -ge 2 ] 2>/dev/null; then
    ok "at the end $p_frist plugins are on the table at the same time"
else
    bad "am Ende stehen '${p_frist}' Plugins auf der Tafel (erwartet 2)"
fi
hasnotre "$F" 'unreg uhr.*grund=2' "das Widget ist NICHT an der Frist gestorben"
hasre "$F" 'plugregel: nachgemessen id=[0-9]+ x=[0-9]+ y=[0-9]+' \
    "die Regel-Engine hat ein Fenster gesetzt und NACHGEMESSEN"
hasre "$F" '^pluguhr: text ' "und das Widget hat Text in die Leiste geschickt"

# ================================================== 9. tools/check-ui.sh
echo "== 9. der Zeichenweg =="
if bash tools/check-ui.sh > "$TMPD/ui.txt" 2>&1; then
    grep -qa PASSED "$TMPD/ui.txt" \
        && ok "tools/check-ui.sh reports PASSED (no new drawing path around fUi)" \
        || bad "check-ui.sh is green, but does not say PASSED"
else
    bad "tools/check-ui.sh reports an error"
    tail -8 "$TMPD/ui.txt" | sed 's/^/        /'
fi

if [ "${WMPLUG_SCHNELL:-0}" = 1 ]; then
    echo "== 10. the two module runners -- SKIPPED (WMPLUG_SCHNELL=1) =="
else
    for m in rule widget; do
        echo "== 10.$m: tools/wmplug/$m.sh =="
        bash "tools/wmplug/$m.sh" > "$TMPD/$m.log" 2>&1
        z=$(grep -aiE '^[A-Z]+: [0-9]+ bestanden, [0-9]+ gescheitert' "$TMPD/$m.log" | tail -1)
        mp=$(printf '%s' "$z" | grep -oE '[0-9]+ bestanden' | grep -oE '[0-9]+')
        mf=$(printf '%s' "$z" | grep -oE '[0-9]+ gescheitert' | grep -oE '[0-9]+')
        if [ -n "${mp:-}" ] && [ -n "${mf:-}" ]; then
            printf '  ....  %s.sh: %s bestanden, %s gescheitert (geht in die Summe ein)\n' \
                "$m" "$mp" "$mf"
            pass=$((pass + mp)); fail=$((fail + mf))
            [ "$mf" = 0 ] || sed -n 's/^  FAIL/        FAIL/p' "$TMPD/$m.log" | head -8
        else
            bad "$m.sh delivered no final line"
            tail -8 "$TMPD/$m.log" | sed 's/^/        /'
        fi
    done
fi

# ================================================= 11. die Fotos liegen da
echo "== 11. die Fotos =="
for b in regel-mit-recht regel-ohne-recht widget-an widget-aus-laufzeit after-crash \
         enable-vorher enable-nachher; do
    if [ -s "$SHOTS/$b.png" ] || [ -s "$SHOTS/$b.ppm" ]; then
        ok "docs/shots/wmplug/$b liegt da"
    else
        if [ "${WMPLUG_SCHNELL:-0}" = 1 ]; then
            printf '  ....  %s -- nicht geprueft (WMPLUG_SCHNELL=1)\n' "$b"
        else
            bad "docs/shots/wmplug/$b fehlt"
        fi
    fi
done

echo "== 12. the two images of the window rule, point by point =="
regel_ppm() { # png ppm
    python3 - "$1" "$2" <<'PYX'
import sys
try:
    from PIL import Image
except Exception:
    sys.exit(2)
try:
    Image.open(sys.argv[1]).convert('RGB').save(sys.argv[2])
except Exception:
    sys.exit(3)
PYX
}
if [ "${WMPLUG_SCHNELL:-0}" = 1 ]; then
    printf '  ....  die Regelbilder -- nicht geprueft (WMPLUG_SCHNELL=1)\n'
elif [ -s "$SHOTS/regel-mit-recht.png" ] && [ -s "$SHOTS/regel-ohne-recht.png" ] \
     && regel_ppm "$SHOTS/regel-mit-recht.png" "$TMPD/rmit.ppm" \
     && regel_ppm "$SHOTS/regel-ohne-recht.png" "$TMPD/rohne.ppm"; then
    a=$(python3 tools/gfx/checkshot.py pixel "$TMPD/rmit.ppm" 500 300 2>&1)
    b=$(python3 tools/gfx/checkshot.py pixel "$TMPD/rohne.ppm" 500 300 2>&1)
    c=$(python3 tools/gfx/checkshot.py pixel "$TMPD/rohne.ppm" 120 300 2>&1)
    d=$(python3 tools/gfx/checkshot.py pixel "$TMPD/rmit.ppm" 120 300 2>&1)
    [ "$a" != "$b" ] \
        && ok "checkshot pixel (500,300): with right [$a], without right [$b] -- different" \
        || bad "checkshot pixel (500,300): both [$a] -- the rule cannot be seen in the image"
    e=$(python3 tools/gfx/checkshot.py pixel "$TMPD/rmit.ppm" 252 310 2>&1)
    [ "$e" = "$c" ] \
        && ok "and the window colour of (120,300) without the right sits at the shifted point (252,310) with it: [$e] -- the window moved" \
        || bad "the window colour did not move along: [$e] against [$c]"
    [ "$d" != "$c" ] \
        && ok "checkshot pixel (120,300): with right [$d], without right [$c] -- different" \
        || bad "checkshot pixel (120,300): beide [$c]"
else
    bad "the two rule images are not PNGs in $SHOTS (or PIL is missing)"
fi

echo
echo "WMPLUG: $pass bestanden, $fail gescheitert"
[ "$fail" = 0 ] || exit 1
