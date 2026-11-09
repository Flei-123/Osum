#!/usr/bin/env bash
#
# Aufruf:  bash tools/certus/run.sh [--schnell] [arbeitsverzeichnis]
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
. tools/lib/qemu.sh

SCHNELL=0
if [ "${1:-}" = "--schnell" ]; then SCHNELL=1; shift; fi
OUT=${1:-/tmp/certus}
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/lock.sh" && osum_sperre "$OUT"   # A-024
export OUT
mkdir -p "$OUT"
SHOTS=${CERTUS_SHOTS:-docs/shots/certus}
CERTUS_REPO=${CERTUS_REPO:-/root/certus-ui}
SOAK=${CERTUS_SOAK:-20}
[ "$SCHNELL" = 1 ] && SOAK=3
OPK=${OPK:-$(python3 "$(dirname "${BASH_SOURCE[0]}")/../lib/opkpfad.py")}   # A-025: der alte Ordner war ein Arbeitsbaum
NETZ="nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0"
WM="osum vfs gfx wm wig wmhold wiglong nokbd nosched noproc nofs noring3"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { local n=$1 v=$2 op=$3 w=$4
    if [ -z "$v" ]; then bad "$n: no number (expected $op $w)"; return; fi
    if [ "$v" -"$op" "$w" ] 2>/dev/null; then ok "$n: $v"
    else bad "$n: $v, erwartet $op $w"; fi
}
hat() { grep -qaF "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' fehlt"; }

for t in qemu-system-x86_64 python3; do
    command -v "$t" >/dev/null 2>&1 || { echo "CERTUS: uebersprungen, $t fehlt"; exit 0; }
done
[ -d "$CERTUS_REPO/lib/browser" ] || {
    echo "CERTUS: skipped, no Certus tree in $CERTUS_REPO"; exit 0; }
[ -x "$ROOT/vendor/firn/bin/firnc" ] || {
    echo "CERTUS: skipped, vendor/firn/bin/firnc missing (run vendor/firn/fetch-firnc.sh)"; exit 0; }

# ------------------------------------------------------------ der Server
WWW="$OUT/www"
mkdir -p "$WWW"
cat > "$WWW/i.htm" <<'HTML'
<!doctype html><html><head><title>Certus auf Osum</title></head><body>
<h1>Certus laeuft auf Osum</h1>
<p>Diese Seite kommt ueber TCP aus dem Netz, wird von lib/browser
gelesen, von lib/css kaskadiert, von lib/layout ausgelegt und von
lib/paint gemalt -- alles in einem Prozess in Ring 3.</p>
<p>Der zweite Absatz steht hier, damit es mehr als ein Textband gibt.</p>
<div style="background:#0033aa;width:300px;height:80px"></div>
<div style="background:#cc0000;width:200px;height:40px"></div>
</body></html>
HTML
cat > "$WWW/j.htm" <<'HTML'
<!doctype html><html><head><title>JS auf Osum</title></head><body>
<h1>JavaScript</h1>
<div id="z" style="background:#0033aa;width:300px;height:80px"></div>
<p id="t">ohne Skript</p>
<script>
var z = document.getElementById("z");
z.style.backgroundColor = "#cc0000";
var a = []; for (var i = 0; i < 5; i++) { a.push(i*i); }
document.getElementById("t").textContent = "Quadrate: " + a.join(", ") + " und 6*7 = " + (6*7);
var p = document.createElement("p");
p.textContent = "Dieser Absatz wurde von JavaScript gebaut.";
document.body.appendChild(p);
</script>
</body></html>
HTML
printf '<!doctype html><html><body></body></html>\n' > "$WWW/l.htm"

PORT=$(python3 -c "import socket;s=socket.socket();s.bind(('0.0.0.0',0));print(s.getsockname()[1]);s.close()")
( cd "$WWW" && python3 -m http.server "$PORT" --bind 0.0.0.0 >/dev/null 2>&1 ) &
SRVPID=$!
trap 'kill $SRVPID 2>/dev/null' EXIT
sleep 1

echo "== 1. build: /bin/certus, with the compiler of the Certus tree =="
bash tools/loader/build.sh "$OUT" > "$OUT/build.log" 2>&1 \
    && ok "Kern und $(wc -l < "$OUT/proglist") Programme uebersetzt" \
    || { bad "build.sh"; tail -20 "$OUT/build.log"; exit 1; }
grep -q '^   browser' "$OUT/build.log" \
    && ok "the browser is built ($(stat -c%s "$OUT/bin/certus") Oktette)" \
    || { bad "certus was not built"; tail -12 "$OUT/certus.log"; }

if [ -x "$OUT/bin/certus" ]; then
    kind=$(readelf -h "$OUT/bin/certus" | awk -F: '/^  Type:/ {print $2}' | awk '{print $1}')
    [ "$kind" = EXEC ] && ok "certus is ET_EXEC (static, no interpreter)" \
                       || bad "certus: ELF-Art '$kind'"
    u=$(nm -u "$OUT/.certus-bau/certus.dbg" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
    [ -z "$u" ] && ok "certus has not a single undefined name (no libc)" \
                || bad "undefinierte Namen: $u"
    seg=$(readelf -l "$OUT/bin/certus" | grep -c '^  LOAD')
    num "certus: PT_LOAD-Segmente (Code / Konstanten / Daten getrennt)" "$seg" eq 3
    wx=$(readelf -lW "$OUT/bin/certus" | awk '/^  LOAD/ {print $8 $9 $10}' | grep -c 'WE\|RWE')
    num "certus: Segmente, die zugleich schreib- und ausfuehrbar sind" "$wx" eq 0
    ende=$(readelf -lW "$OUT/bin/certus" | python3 -c '
import sys
h = 0
for z in sys.stdin:
    t = z.split()
    if len(t) > 6 and t[0] == "LOAD":
        h = max(h, int(t[2], 16) + int(t[5], 16))
print(h)')
    num "certus endet unterhalb von proc.IMAGE_END (0x44400000)" "$ende" lt $((0x44400000))
    n=$(objdump -d "$OUT/bin/certus" | grep -cE '^\s+[0-9a-f]+:.*\bsyscall\b')
    num "certus: syscall-Befehle (die einzige Tuer aus Ring 3)" "$n" ge 10
fi

echo
echo "== 2. what the kernel learned for it =="
grep -qE '^const IMAGE_END: u64 = 0x44400000' kernel/sched/proc.fi \
    && ok "kernel/sched/proc.fi: IMAGE_END = 0x44400000 (the image window is 67 MiB)" \
    || bad "IMAGE_END is not at 0x44400000"
grep -qE '^const BIG_FLOOR: u64 = 0x44400000' kernel/sched/proc.fi \
    && ok "kernel/sched/proc.fi: BIG_FLOOR = 0x44400000 (the arena starts above)" \
    || bad "BIG_FLOOR does not match IMAGE_END"
grep -qE '^const PRIV_SLOTS: u64 = 475' kernel/sched/proc.fi \
    && ok "kernel/sched/proc.fi: PRIV_SLOTS = 475 tiles (155 + 320 arena for sparse SHM) of 2 MiB" \
    || bad "PRIV_SLOTS is not at 475"
grep -qE '^const BIG_TOP: u64 = 0x52C00000' kernel/sched/proc.fi \
    && ok "kernel/sched/proc.fi: BIG_TOP = 0x52C00000" || bad "BIG_TOP fehlt"
python3 - <<'PY' && ok "the private region ends before 0x7C000000 (tools/osum/run.sh stays valid)" \
                 || bad "die private Gegend erreicht 0x7C000000"
import re, sys
s = open("kernel/sched/proc.fi", encoding="utf-8").read()
slots = int(re.search(r"^const PRIV_SLOTS: u64 = (\d+)$", s, re.M).group(1))
span = int(re.search(r"^const USER_SPAN: u64 = (0x[0-9A-Fa-f]+)", s, re.M).group(1), 16)
base = int(re.search(r"^const USER_DATA: u64 = (0x[0-9A-Fa-f]+)", s, re.M).group(1), 16)
sys.exit(0 if base + span * slots <= 0x7C000000 else 1)
PY
grep -q 'w_self' kernel/fs/procfs/pfnode.fi \
    && ok "kernel/fs/procfs.fi kennt /proc/self (der Sammler fragt danach)" \
    || bad "/proc/self fehlt"
grep -q 'CR4_OSFXSR' kernel/arch/x86_64/fpu.fi \
    && ok "kernel/arch/x86_64/fpu.fi enables SSE for ring 3 (CR4.OSFXSR)" \
    || bad "SSE is not enabled"
grep -q 'fpu.apply_here' kernel/kmain.fi \
    && ok "and every further core too (fpu.apply_here in ap_main)" \
    || bad "the APs get no SSE"
grep -q 'fpu.switch' kernel/sched/sched.fi \
    && ok "sched.fi rettet die Vektorregister beim Umschalten (fpu.switch)" \
    || bad "the vector registers are not saved on switching"

echo
echo "== 3. the canvas and the single-core rule =="
grep -q 'const K_CANVAS' <(bash tools/structure/catprog.sh kernel/user/fuiapp/wlib.fi) \
    && ok "kernel/user/fuiapp/wlib.fi has the widget K_CANVAS" || bad "K_CANVAS fehlt"
grep -q 'fn canvas_event' <(bash tools/structure/catprog.sh kernel/user/fuiapp/wlib.fi) \
    && ok "the canvas has an event ring (canvas_event)" \
    || bad "canvas_event fehlt"
grep -q 'import libc.mem' <(bash tools/structure/catprog.sh kernel/user/wlibc.fi) \
    && bad 'wlibc binds libc.mem -- two modules mem in one program (single-core rule)' \
    || ok 'wlibc gets by without libc.mem (no second module mem next to html.mem)'
grep -q 'fn gmem' <(bash tools/structure/catprog.sh kernel/user/wlibc.fi) \
    && ok "the glyph memory comes from its own 64 KiB pieces (gmem)" \
    || bad "gmem fehlt"
grep -q 'wlib.leinwand(' "$CERTUS_REPO/lib/fenster/osum.fi" \
    && ok "the fourth back wall (lib/fenster/osum.fi) creates a wlib canvas" \
    || bad "lib/fenster/osum.fi creates no canvas"
for f in b_zurueck b_vor b_neu e_adr; do
    grep -q "$f" "$CERTUS_REPO/lib/fenster/osum.fi" || bad "widget $f is missing from the back wall"
done
grep -q 'wlib.button' "$CERTUS_REPO/lib/fenster/osum.fi" \
    && grep -q 'wlib.entry' "$CERTUS_REPO/lib/fenster/osum.fi" \
    && ok "Back/Forward/New are wlib.button, the address is wlib.entry" \
    || bad "the bar is not made of wlib widgets"

echo
echo "== 4. the disk, the packages and the store =="
python3 "$OPK" schluessel "$OUT" > "$OUT/key.log" 2>&1
cp -f "$OUT/oeffentlich.key" "$OUT/schluessel.pub"
bash tools/loader/pakete.sh "$OUT" > "$OUT/pakete.log" 2>&1 \
    && ok "$(ls "$OUT"/stand/*.opk | wc -l) Pakete gebaut" \
    || { bad "pakete.sh"; tail -12 "$OUT/pakete.log"; }
[ -s "$OUT/stand/certus-1.opk" ] \
    && ok "certus-1.opk is in the stand ($(stat -c%s "$OUT/stand/certus-1.opk") Oktette)" \
    || bad "certus-1.opk fehlt"
python3 tools/update/signpak.py "$OUT/geheim.key" "$OUT"/stand/*.opk > /dev/null 2>&1 \
    && ok "every package is signed" || bad "signpak.py"
grep -q '^certus|' tools/loader/apps.tab \
    && ok "the browser is in the store catalog (tools/loader/apps.tab)" \
    || bad "certus fehlt in apps.tab"
LADEN_STAND="$OUT/stand" bash tools/loader/abbild.sh "$OUT" > "$OUT/abbild.log" 2>&1 \
    && ok "Abbild gebaut" || { bad "abbild.sh"; tail -10 "$OUT/abbild.log"; exit 1; }

# ---------------------------------------------------------------- Laeufe
#
lauf_wig() { # <name> <url> <extraargs,mit,komma> <warte>
    local name=$1 url=$2 extra=$3 warte=$4
    cp --sparse=always -f "$OUT/platte/disk.img" "$OUT/$name.img"
    LADEN_PLATTE="$OUT/$name.img" LADEN_KILL=nein LADEN_WARTE="$warte" \
        bash tools/loader/lauf.sh "$name" \
        "$WM $NETZ wigapp=/bin/certus,$url,-,1$extra" \
        "${CERTUS_LIMIT:-1500}" "k15: start" > "$OUT/$name.lauf" 2>&1
}

echo
echo "== 5. a real page, in the window =="
lauf_wig seite "http://10.0.2.2:$PORT/i.htm" ",--dump=/tmp/s.ppm" 18
hat "$OUT/seite.txt" "k15: start /bin/certus" "der Kern hat /bin/certus im Fensterserver gestartet"
BP=$(grep -oaE 'wig: blits=[0-9]+' "$OUT/seite.txt" | tail -1 | cut -d= -f2)
PX=$(grep -oaE 'pixels=[0-9]+' "$OUT/seite.txt" | tail -1 | cut -d= -f2)
num "WIG_BLIT: Aufrufe aus Ring 3" "$BP" ge 1
num "Bildpunkte, die wirklich ins Fenster geschoben wurden" "$PX" ge 300000
bash tools/mkfsfi/mkfs.sh cat "$OUT/seite.img" /tmp/s.ppm > "$OUT/seite.ppm" 2>/dev/null
if [ -s "$OUT/seite.ppm" ]; then
    ok "Certus wrote its dump to the guest's disk ($(stat -c%s "$OUT/seite.ppm") Oktette)"
    python3 tools/certus/pixel.py "$OUT/seite.ppm" --json "$OUT/seite.json" | sed 's/^/        /'
    T=$(python3 -c "import json;print(json.load(open('$OUT/seite.json'))['tintenpunkte'])")
    D=$(python3 -c "import json;print(json.load(open('$OUT/seite.json'))['dunkle_punkte'])")
    B=$(python3 -c "import json;print(json.load(open('$OUT/seite.json'))['textbaender'])")
    num "Tintenpunkte auf der Leinwand" "$T" ge 5000
    num "dunkle Punkte -- das ist der TEXT" "$D" ge 300
    num "waagrechte Textbaender" "$B" ge 3
    mkdir -p "$SHOTS"
    python3 tools/certus/pixel.py "$OUT/seite.ppm" --png "$SHOTS/leinwand.png" >/dev/null
else
    bad "no dump on the disk"
fi
if [ -s "$OUT/seite.png" ]; then
    mkdir -p "$SHOTS"; cp -f "$OUT/seite.png" "$SHOTS/fenster.png"
    FARBEN=$(python3 -c "
from PIL import Image
im = Image.open('$OUT/seite.png').convert('RGB')
print(len(im.getcolors(1 << 24) or []))")
    num "Bildschirmfoto: verschiedene Farben (ein leerer Schirm hat zwei)" "$FARBEN" ge 50
else
    bad "no screenshot of the page"
fi

echo
echo "== 6. a page with JavaScript =="
lauf_wig js "http://10.0.2.2:$PORT/j.htm" ",--dump=/tmp/j.ppm" 18
bash tools/mkfsfi/mkfs.sh cat "$OUT/js.img" /tmp/j.ppm > "$OUT/js.ppm" 2>/dev/null
if [ -s "$OUT/js.ppm" ]; then
    python3 tools/certus/pixel.py "$OUT/js.ppm" --json "$OUT/js.json" | sed 's/^/        /'
    JT=$(python3 -c "import json;print(json.load(open('$OUT/js.json'))['tintenpunkte'])")
    num "JS-Seite: Tintenpunkte" "$JT" ge 3000
    ROT=$(python3 tools/certus/color.py "$OUT/js.ppm" cc0000)
    BLAU=$(python3 tools/certus/color.py "$OUT/js.ppm" 0033aa)
    num "der Kasten ist ROT -- das Skript hat style.backgroundColor gesetzt" "$ROT" ge 5000
    num "und NICHT mehr blau (die Farbe aus dem Quelltext)" "$BLAU" eq 0
    mkdir -p "$SHOTS"
    python3 tools/certus/pixel.py "$OUT/js.ppm" --png "$SHOTS/javascript.png" >/dev/null
else
    bad "the JS page delivered no dump"
fi

echo
echo "== 7. time to picture =="
#
cp --sparse=always -f "$OUT/platte/disk.img" "$OUT/zeit.img"
LADEN_PLATTE="$OUT/zeit.img" LADEN_KILL=ja LADEN_WARTE=15 \
    bash tools/loader/lauf.sh zeit \
    "$WM $NETZ wigapp=/bin/certus,http://10.0.2.2:$PORT/i.htm,-,1,--laut=1" \
    "${CERTUS_LIMIT:-1500}" "HOEHE" > "$OUT/zeit.lauf" 2>&1 &
zpid=$!
t_start=0; t_bild=0
i=0
while [ $i -lt 6000 ]; do
    if [ "$t_start" = 0 ] && grep -qa 'k15: start /bin/certus' "$OUT/zeit.txt" 2>/dev/null; then
        t_start=$(date +%s%3N)
    fi
    if [ "$t_start" != 0 ] && grep -qa '^HOEHE ' "$OUT/zeit.txt" 2>/dev/null; then
        t_bild=$(date +%s%3N); break
    fi
    kill -0 "$zpid" 2>/dev/null || break
    sleep 0.2
    i=$((i + 1))
done
wait "$zpid" 2>/dev/null
if [ "$t_start" != 0 ] && [ "$t_bild" != 0 ]; then
    MS=$((t_bild - t_start))
    ok "time from program start to finished picture: ${MS} ms"
    echo "$MS" > "$OUT/zeit-ms.txt"
    num "das Bild kam ueberhaupt (ms)" "$MS" gt 0
else
    bad "no picture -- start found: $t_start, picture: $t_bild"
fi
HOEHE=$(grep -oaE '^HOEHE [0-9]+' "$OUT/zeit.txt" | head -1 | awk '{print $2}')
num "die Dokumenthoehe, die Certus ausgerechnet hat (Bildpunkte)" "$HOEHE" ge 100
rm -f "$OUT/zeit.img"

echo
echo "== 8. $SOAK runs without panic =="
#
PAR=${CERTUS_PAR:-4}
panik=0; lief=0; ohne=0
i=1
while [ "$i" -le "$SOAK" ]; do
    j=0
    pids=""
    while [ "$j" -lt "$PAR" ] && [ "$i" -le "$SOAK" ]; do
        n="s$i"
        cp --sparse=always -f "$OUT/platte/disk.img" "$OUT/$n.img"
        LADEN_PLATTE="$OUT/$n.img" LADEN_KILL=ja LADEN_WARTE=5 \
            bash tools/loader/lauf.sh "$n" \
            "$WM $NETZ wigapp=/bin/certus,http://10.0.2.2:$PORT/i.htm,-,1" \
            "${CERTUS_LIMIT:-1500}" "k15: start" > "$OUT/$n.lauf" 2>&1 &
        pids="$pids $!"
        i=$((i + 1)); j=$((j + 1))
    done
    for q in $pids; do wait "$q"; done
done
i=1
while [ "$i" -le "$SOAK" ]; do
    n="s$i"
    lief=$((lief + 1))
    if grep -qaE 'panic|PANIK|user fault|kernel fault|#PF|#GP|#UD' "$OUT/$n.txt" 2>/dev/null; then
        panik=$((panik + 1))
        echo "        Lauf $i: PANIK"
        grep -aE 'panic|PANIK|user fault|kernel fault' "$OUT/$n.txt" | head -2 | sed 's/^/          /'
    fi
    grep -qa 'k15: start /bin/certus' "$OUT/$n.txt" 2>/dev/null || {
        ohne=$((ohne + 1)); echo "        run $i: certus did not come up"; }
    rm -f "$OUT/$n.img" "$OUT/$n.ppm"
    i=$((i + 1))
done
num "Laeufe insgesamt" "$lief" eq "$SOAK"
num "Laeufe mit Panik" "$panik" eq 0
num "Laeufe, in denen der Browser nicht hochkam" "$ohne" eq 0

echo
echo "== 9. installed from the store =="
cp --sparse=always -f "$OUT/platte/disk.img" "$OUT/store.img"
LADEN_PLATTE="$OUT/store.img" bash tools/loader/lauf.sh store \
    "osum vfs nokbd nosched noproc nofs noring3 script=opk install /store/certus-1.opk;opk list;exit" \
    900 > "$OUT/store.lauf" 2>&1
hat "$OUT/store.txt" "installiert certus" "opk hat das signierte Paket angenommen"
hat "$OUT/store.txt" "certus" "certus steht danach in der Paketliste"

echo
echo "CERTUS: $pass bestanden, $fail gefallen"
[ "$fail" -eq 0 ] || exit 1
