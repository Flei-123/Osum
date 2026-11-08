#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/systembus/run.sh -- DER SYSTEMBUS, GEMESSEN STATT BEHAUPTET.
#
#   bash tools/systembus/run.sh
#
set -u
cd "$(dirname "$0")/../.."
TMPD=${SYSBUS_TMPD:-$(mktemp -d)}
. tools/lib/summary.sh; summary_begin SYSTEMBUS
trap 'summary_guard; [ -n "${SYSBUS_KEEP:-}" ] || rm -rf "$TMPD"; summary_exit_status || exit 1' EXIT
trap 'exit 1' HUP INT TERM
pass=0; fail=0
ok()  { echo "  OK   $*"; pass=$((pass + 1)); }
bad() { echo "  FAIL $*"; fail=$((fail + 1)); }
QEMU=${QEMU:-qemu-system-x86_64}
export FIRNLIB="$PWD/lib"

echo "== 1. the map of kdata =="
kol=$(python3 tools/kernel/memmap.py kernel 2>&1 | tail -1)
echo "        $kol"
case "$kol" in
    *" 0 collisions") ok "der Busbereich ueberschneidet nichts" ;;
    *) bad "the map has collisions" ;;
esac
grep -q 'BUS_OFF' tools/kernel/memmap.py \
    && ok "the range is in the checker's map" \
    || bad "BUS_OFF fehlt in tools/kernel/memmap.py"

echo
echo "== 2. the single-core rule, at the source =="
n_static=$(grep -c '^static mut' kernel/bus/bus.fi || true)
if [ "$n_static" = 0 ]; then
    ok "kernel/bus/bus.fi hat keinen 'static mut'"
else
    bad "kernel/bus/bus.fi hat $n_static globale Variablen"
fi
if sed -n '/^fn do_bus/,/^}/p' kernel/sys/sysbus.fi | grep -q 'state + kstate\.'; then
    bad "sys.do_bus touches a kdata buffer"
else
    ok "sys.do_bus kopiert in seinen eigenen Stapelrahmen"
fi
py=$(python3 - <<'PYEOF'
import re
s = open("kernel/bus/bus.fi", encoding="utf-8", errors="surrogateescape").read()
funcs = {}
name = None
for line in s.split("\n"):
    m = re.match(r"^fn (\w+)\(", line)
    if m:
        name = m.group(1)
        funcs[name] = []
    elif name:
        funcs[name].append(line)
body = lambda f: "\n".join(funcs.get(f, []))
def fasst(f):
    return bool(re.search(r"(svc_at|svc_set|msg_at|msg_set|box_at|box_set|"
                          r"seg_at|seg_set|hist_addr|noti_addr)\(", body(f)))
def nimmt(f):
    return "take(state)" in body(f)
def rufer(f):
    return [n for n, b in funcs.items()
            if n != f and re.search(r"(?<![\w.])" + f + r"\(", "\n".join(b))]
bekannt = {"init", "stat", "clip_count", "noti_count", "seg_pages",
           "seg_frame", "seg_owner", "drag_types", "drag_active",
           "noti_len", "noti_prio", "noti_idx", "idx_of", "noti_seen",
           "put_item", "item_get", "item_set", "queue_put", "deliver",
           "slot_free", "may_call", "say_denied", "forget_task",
           "b", "sb", "bump", "svc_at", "svc_set", "msg_at", "msg_set",
           "box_at", "box_set", "seg_at", "seg_set", "hist_addr",
           "noti_addr", "offer_types", "err", "seq_next"}
offen = [f for f in funcs if fasst(f) and not nimmt(f) and f not in bekannt]
leck = []
for f in offen:
    rs = rufer(f)
    if not rs:
        leck.append(f + "(ohne-Aufrufer)")
    elif not all(nimmt(r) or r in bekannt for r in rs):
        leck.append(f)
print(len(funcs), len(offen), ",".join(sorted(set(leck))) or "-")
PYEOF
)
nfun=$(echo "$py" | awk '{print $1}')
leck=$(echo "$py" | awk '{print $3}')
if [ "$leck" = "-" ]; then
    ok "$nfun functions in bus.fi -- every path to the table goes through take()"
else
    bad "these touch the table without a lock: $leck"
fi

echo
echo "== 3. the kernel and the programs =="
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/k.log" 2>&1 \
    && ok "der Kern baut ($(stat -c%s "$TMPD/k.mb") Oktette)" \
    || { bad "the kernel does not build"; tail -12 "$TMPD/k.log" | sed 's/^/        /'
         summary_emit "$pass" "$fail" 0; exit 1; }

PROGS="desktop taskbar settings launcher dhcp explorer widgetdemo locate sh echo ls cat edit"
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null \
    || bad "crt.s cannot be assembled"
bauen_ok=1
for p in $PROGS; do
    UPROF=""; UCRT="$TMPD/crt.o"
    grep -qa '^profile app' "kernel/user/$p.fi" && { UPROF=--profile=app; UCRT=""; }
    vendor/firn/bin/firnc $UPROF -c "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/e$p" 2>&1 \
        || { bauen_ok=0; echo "        $p:"; head -6 "$TMPD/e$p" | sed 's/^/        /'; break; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
        -o "$TMPD/$p.elf" $UCRT "$TMPD/$p.o" 2>/dev/null || { bauen_ok=0; break; }
    strip --strip-all "$TMPD/$p.elf"
done
if [ "$bauen_ok" = 1 ]; then
    ok "the $(echo $PROGS | wc -w) programs build"
else
    bad "the programs do not build"
fi

lauf() { # name smp extra [limit]
    local name=$1 smp=$2 extra=$3 limit=${4:-140}
    local out="$TMPD/$name.txt"
    rm -f "$out"; : > "$out"
    timeout "$limit" $QEMU -kernel "$TMPD/k.mb" -m 512 -smp "$smp" \
        -append "nokbd nosched noproc nofs $extra" \
        -serial "file:$out" -display none -no-reboot -vga std \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/$name.qemu" 2>&1 &
    local pid=$! i=0
    while [ $i -lt 700 ]; do
        grep -qa '^kernel: done\|^panic:\|^\*\*\* EXCEPTION' "$out" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2; i=$((i + 1))
    done
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    return 0
}

wert() { grep -a "^$2" "$1" 2>/dev/null | tail -1 | sed "s/^$2//"; }

echo
echo "== 4. four cores, two processes, a hundred iterations =="
lauf vier 4 "busbench bus r3alle" 200
A="$TMPD/vier.txt"
if grep -qa '^panic:\|^\*\*\* EXCEPTION' "$A"; then
    bad "the run died: $(grep -am1 '^panic:\|^\*\*\* EXCEPTION' "$A")"
else
    ok "the run with four cores is alive"
fi
run=$(wert "$A" 'busa: run=')
abw=$(wert "$A" 'busa: abw=')
got=$(wert "$A" 'busb: got=')
leer=$(wert "$A" 'busb: empty=')
echo "        busa run=$run abw=$abw   busb got=$got empty=$leer"
[ "${run:-0}" = 100 ] && ok "hundert Durchlaeufe gefahren" \
                      || bad "nicht hundert Durchlaeufe, sondern '${run:-nichts}'"
[ "${abw:-1}" = 0 ] && ok "ZERO deviations -- what A put down, B read octet for octet" \
                    || bad "$abw deviations between writer and reader"
[ "${leer:-1}" = 0 ] && ok "no round without a message at the reader" \
                     || bad "$leer rounds without a message"
drops=$(wert "$A" 'bus: drops=')
[ "${drops:-1}" = 0 ] && ok "no message lost (drops=0)" \
                      || bad "$drops Nachrichten verloren"
cs=$(wert "$A" 'bus: clipsets=')
cg=$(wert "$A" 'bus: clipgets=')
if [ "${cs:-0}" = 100 ] && [ "${cg:-0}" = 100 ]; then
    ok "hundertmal abgelegt, hundertmal gelesen"
else
    bad "clipsets=$cs clipgets=$cg"
fi
hist=$(wert "$A" 'bus: history=')
[ "${hist:-0}" = 20 ] && ok "the history stands at twenty and does not overflow" \
                      || bad "the history shows '${hist:-nichts}' statt 20"

echo
echo "== 5. the no that can be seen =="
ruf=$(wert "$A" 'busd: ruf=')
vor=$(wert "$A" 'busd: vor=')
uid=$(wert "$A" 'busd: uid=')
echo "        before=$vor uid=$uid call=$ruf"
[ "${vor:-x}" = 0 ] && ok "as root the same call goes through (the control)" \
                    || bad "already rejected as root: '$vor'"
[ "${uid:-0}" = 1000 ] && ok "the process really dropped its root rights" \
                       || bad "uid ist '$uid' statt 1000"
[ "${ruf:-x}" = "-3" ] && ok "the unauthorised call is rejected (E_DENIED)" \
                       || bad "der Ruf gab '$ruf' statt -3"
z=$(grep -ac '^bus: ABGELEHNT' "$A" || true)
if [ "${z:-0}" -ge 1 ]; then
    ok "the rejection is on the line: $(grep -am1 '^bus: ABGELEHNT' "$A")"
else
    bad "rejection was silent -- no line 'bus: ABGELEHNT'"
fi
den=$(wert "$A" 'bus: denied=')
if [ "${den:-0}" -ge 1 ] 2>/dev/null; then
    ok "and it is counted (denied=$den)"
else
    bad "the counter denied is at '${den:-nichts}'"
fi

echo
echo "== 6. one megabyte, shared and not copied =="
byt=$(wert "$A" 'buss: byt=')
us=$(wert "$A" 'buss: us=')
sum=$(wert "$A" 'buss: sum=')
sgp=$(wert "$A" 'bus: segseiten=')
echo "        byt=$byt us=$us sum=$sum seiten=$sgp"
[ "${byt:-0}" = 1048576 ] && ok "ein volles Megabyte" || bad "byt=$byt"
[ "${sgp:-0}" = 256 ] && ok "256 pages from the frame manager" || bad "segseiten=$sgp"
if [ -n "${us:-}" ] && [ "$us" -lt 5000 ] 2>/dev/null; then
    ok "through in ${us} us -- under the promise of 5000 us"
else
    bad "the handover needed '${us:-nichts}' us"
fi
erw=$(python3 -c 'n=131072; print((sum(range(n)) + 7*n) & (2**64-1))')
[ "${sum:-0}" = "$erw" ] && ok "and the content matches (sum $erw)" \
                         || bad "the sum is $sum instead of $erw"

echo
echo "== 7. die Gegenproben =="
lauf ohne 4 "bus r3alle" 120
if grep -qa '^bus: skipped' "$TMPD/ohne.txt"; then
    ok "ohne 'busbench' laeuft kein Busprogramm"
else
    bad "the programs also run without 'busbench'"
fi
lauf nobus 4 "busbench bus nobus r3alle" 150
B="$TMPD/nobus.txt"
nreg=$(wert "$B" 'busa: reg=')
echo "        mit nobus: busa reg=$nreg"
if [ -n "${nreg:-}" ] && [ "${nreg#-}" != "$nreg" ]; then
    ok "mit 'nobus' scheitert die Anmeldung mit einem FEHLER ($nreg), nicht still"
else
    bad "mit 'nobus' kam '$nreg' zurueck -- der Bus antwortet, obwohl es ihn nicht gibt"
fi
if grep -qa '^bus: 64 Dienste' "$B"; then
    bad "'nobus' hat den Bus trotzdem aufgesetzt"
else
    ok "'nobus' setzt den Bus wirklich nicht auf"
fi

echo
echo "== 8. the surface: the messages in the bar =="
python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
    || bad "tools/k15/tree.py faellt"
printf '# taskbar.conf\nedge=0\nheight=40\nwidth=0\nautohide=0\nontop=1\n' > "$TMPD/tb.conf"
ARGS=(build "$TMPD/disk.img" 65536 --v3 /lib/
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$TMPD/$p.elf"); done
ARGS+=("/bin/files@/bin/explorer")
printf 'on\n' > "$TMPD/uitrace"
ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme" "/etc/taskbar.conf=$TMPD/tb.conf"
    "/etc/uitrace=$TMPD/uitrace")
while read -r z; do ARGS+=("$z"); done \
    < <(python3 tools/k15/bundle.py assets/apps "$TMPD/buendel" "nur=$PROGS")
while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
if bash tools/mkfsfi/mkfs.sh "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1; then
    ok "the disk is there ($(stat -c%s "$TMPD/disk.img") Oktette)"
else
    bad "mkfs.py faellt"; tail -4 "$TMPD/mkfs.txt" | sed 's/^/        /'
fi

SHOTS=${SHOTS:-.systembus-shots}
mkdir -p "$SHOTS"
gui() { # name extra drehbuch
    local name=$1 extra=$2 dreh=$3
    local sock="$TMPD/$name.sock"
    rm -f "$sock"
    cp -f "$TMPD/disk.img" "$TMPD/$name.img"
    #
    timeout 320 $QEMU -kernel "$TMPD/k.mb" -m 512 \
        -append "gfx fbres=1024x768 wm wig desk wmshell wmdauer wighalt=300 nosched noproc nofs $extra" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -device "VGA,edid=on,xres=1024,yres=768,vgamem_mb=32" \
        -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/$name.qemu" 2>&1 &
    local pid=$! i=0
    while [ $i -lt 1500 ]; do
        grep -qa '^launcher: ready' "$TMPD/$name.txt" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2; i=$((i + 1))
    done
    python3 -u tools/design/drive.py "$sock" "$TMPD/$name.txt" "$SHOTS" "$dreh" \
        > "$TMPD/$name.fahren" 2>&1
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    rm -f "$sock"
}
bild() { # name
    if [ -s "$SHOTS/$1.ppm" ]; then
        python3 - "$SHOTS/$1" <<'PY'
import sys
from PIL import Image
p = sys.argv[1]
im = Image.open(p + ".ppm").convert("RGB")
im.save(p + ".png")
print("        bild %dx%d farben=%d"
      % (im.size[0], im.size[1], len(im.getcolors(maxcolors=1 << 24) or [])))
PY
        ok "the picture $1.png is there"
    else
        bad "kein Bild $1"
    fi
}

cat > "$TMPD/dreh1" <<'DREH'
warteauf 'launcher: ready' || 90
warteauf 'taskbar: text noti' || 90
foto 01-leiste-meldung
DREH
gui leiste "bus notidemo" "$TMPD/dreh1"
if grep -qa 'taskbar: icon field=noti id=' "$TMPD/leiste.txt" && grep -qaE 'taskbar: text noti .* t=[0-9]+' "$TMPD/leiste.txt"; then
    ok "the bar shows the bell with the message count of the bus: $(grep -aom1 'taskbar: text noti .* t=[0-9]*' "$TMPD/leiste.txt" | grep -aom1 ' t=[0-9]*')"
else
    bad "no bell and count in the bar"
fi
if grep -qa 'Meldg' "$TMPD/leiste.txt"; then
    bad "the bar still shows the text Meldg"
else
    ok "no Meldg text in the bar (counter-probe)"
fi
bild 01-leiste-meldung

echo
echo "== 9. the surface: copy in the editor, paste in the terminal =="
#
tipp() {
    python3 - "$1" <<'PY'
import sys
karte = {" ": "spc", "-": "slash", "/": "shift-7", ".": "dot",
         "_": "shift-minus", "=": "equal", ",": "comma"}
for c in sys.argv[1]:
    print("taste " + karte.get(c, c))
PY
}
{
    echo "warteauf 'launcher: ready' || 90"
    echo "warte 5"
    echo "foto 02-schreibtisch"
    tipp "edit /etc/taskbar.conf"
    echo "taste ret"
    echo "warteauf 'edit: ready' || 40"
    echo "warte 3"
    echo "foto 03-editor"
    echo "taste ctrl-k"
    echo "warte 2"
    echo "foto 04-editor-after-ctrl-k"
    echo "taste ctrl-x"
    echo "warte 2"
    echo "taste n"
    echo "warte 3"
    tipp "clip"
    echo "taste ret"
    echo "warte 3"
    echo "foto 05-terminal-clip"
    tipp "clip -l"
    echo "taste ret"
    echo "warte 3"
    echo "foto 06-terminal-verlauf"
} > "$TMPD/dreh2"
gui schreibtisch "bus notidemo" "$TMPD/dreh2"
if grep -qa '^edit: ready' "$TMPD/schreibtisch.txt"; then
    ok "the editor really started in the terminal window"
else
    bad "the editor never started -- the keys did not arrive"
fi
bild 02-schreibtisch
bild 03-editor
bild 04-editor-after-ctrl-k
bild 05-terminal-clip
bild 06-terminal-verlauf

echo
summary_emit "$pass" "$fail" 30 || exit 1
[ "$fail" = 0 ]
