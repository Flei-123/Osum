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
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/sperre.sh" && osum_sperre "$OUT"   # A-024
export OUT
mkdir -p "$OUT"
SHOTS=${CERTUS_SHOTS:-docs/shots/certus}
CERTUS_REPO=${CERTUS_REPO:-/root/certus-sammeln}
SOAK=${CERTUS_SOAK:-20}
[ "$SCHNELL" = 1 ] && SOAK=3
OPK=${OPK:-$(python3 "$(dirname "${BASH_SOURCE[0]}")/../lib/opkpfad.py")}   # A-025: der alte Ordner war ein Arbeitsbaum
NETZ="nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0"
WM="osum vfs gfx wm wig wmhold wiglong nokbd nosched noproc nofs noring3"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { local n=$1 v=$2 op=$3 w=$4
    if [ -z "$v" ]; then bad "$n: keine Zahl (erwartet $op $w)"; return; fi
    if [ "$v" -"$op" "$w" ] 2>/dev/null; then ok "$n: $v"
    else bad "$n: $v, erwartet $op $w"; fi
}
hat() { grep -qaF "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' fehlt"; }

for t in qemu-system-x86_64 python3; do
    command -v "$t" >/dev/null 2>&1 || { echo "CERTUS: uebersprungen, $t fehlt"; exit 0; }
done
[ -d "$CERTUS_REPO/lib/browser" ] || {
    echo "CERTUS: uebersprungen, kein Certus-Baum in $CERTUS_REPO"; exit 0; }
[ -x "$CERTUS_REPO/compiler/target/release/firnc" ] || {
    echo "CERTUS: uebersprungen, $CERTUS_REPO/compiler/target/release/firnc fehlt"
    echo "        (cd $CERTUS_REPO/compiler && cargo build --release)"; exit 0; }

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

echo "== 1. bauen: /bin/certus, mit dem Uebersetzer des Certus-Baumes =="
bash tools/loader/build.sh "$OUT" > "$OUT/build.log" 2>&1 \
    && ok "Kern und $(wc -l < "$OUT/proglist") Programme uebersetzt" \
    || { bad "build.sh"; tail -20 "$OUT/build.log"; exit 1; }
grep -q '^   browser' "$OUT/build.log" \
    && ok "der Browser ist gebaut ($(stat -c%s "$OUT/bin/certus") Oktette)" \
    || { bad "certus wurde nicht gebaut"; tail -12 "$OUT/certus.log"; }

if [ -x "$OUT/bin/certus" ]; then
    kind=$(readelf -h "$OUT/bin/certus" | awk -F: '/^  Type:/ {print $2}' | awk '{print $1}')
    [ "$kind" = EXEC ] && ok "certus ist ET_EXEC (statisch, kein Interpreter)" \
                       || bad "certus: ELF-Art '$kind'"
    u=$(nm -u "$OUT/.certus-bau/certus.dbg" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
    [ -z "$u" ] && ok "certus hat keinen einzigen undefinierten Namen (keine libc)" \
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
    num "certus endet unterhalb von proc.IMAGE_END (0x40C00000)" "$ende" lt $((0x40C00000))
    n=$(objdump -d "$OUT/bin/certus" | grep -cE '^\s+[0-9a-f]+:.*\bsyscall\b')
    num "certus: syscall-Befehle (die einzige Tuer aus Ring 3)" "$n" ge 10
fi

echo
echo "== 2. was der Kern dafuer gelernt hat =="
grep -qE '^const IMAGE_END: u64 = 0x40C00000' kernel/sched/proc.fi \
    && ok "kernel/sched/proc.fi: IMAGE_END = 0x40C00000 (das Abbildfenster ist 11 MiB)" \
    || bad "IMAGE_END steht nicht auf 0x40C00000"
grep -qE '^const BIG_FLOOR: u64 = 0x40C00000' kernel/sched/proc.fi \
    && ok "kernel/sched/proc.fi: BIG_FLOOR = 0x40C00000 (die Arena beginnt darueber)" \
    || bad "BIG_FLOOR passt nicht zu IMAGE_END"
grep -qE '^const PRIV_SLOTS: u64 = 475' kernel/sched/proc.fi \
    && ok "kernel/sched/proc.fi: PRIV_SLOTS = 475 Kacheln (155 + 320 Arena fuer sparse SHM) zu 2 MiB" \
    || bad "PRIV_SLOTS steht nicht auf 475"
grep -qE '^const BIG_TOP: u64 = 0x52C00000' kernel/sched/proc.fi \
    && ok "kernel/sched/proc.fi: BIG_TOP = 0x52C00000" || bad "BIG_TOP fehlt"
python3 - <<'PY' && ok "die private Gegend endet vor 0x7C000000 (tools/osum/run.sh bleibt gueltig)" \
                 || bad "die private Gegend erreicht 0x7C000000"
import re, sys
s = open("kernel/sched/proc.fi", encoding="utf-8").read()
slots = int(re.search(r"^const PRIV_SLOTS: u64 = (\d+)$", s, re.M).group(1))
span = int(re.search(r"^const USER_SPAN: u64 = (0x[0-9A-Fa-f]+)", s, re.M).group(1), 16)
base = int(re.search(r"^const USER_DATA: u64 = (0x[0-9A-Fa-f]+)", s, re.M).group(1), 16)
sys.exit(0 if base + span * slots <= 0x7C000000 else 1)
PY
grep -q 'w_self' kernel/fs/procfs.fi \
    && ok "kernel/fs/procfs.fi kennt /proc/self (der Sammler fragt danach)" \
    || bad "/proc/self fehlt"
grep -q 'CR4_OSFXSR' kernel/arch/x86_64/fpu.fi \
    && ok "kernel/arch/x86_64/fpu.fi schaltet SSE fuer Ring 3 ein (CR4.OSFXSR)" \
    || bad "SSE wird nicht eingeschaltet"
grep -q 'fpu.apply_here' kernel/kmain.fi \
    && ok "und jeder weitere Kern auch (fpu.apply_here in ap_main)" \
    || bad "die APs bekommen kein SSE"
grep -q 'fpu.switch' kernel/sched/sched.fi \
    && ok "sched.fi rettet die Vektorregister beim Umschalten (fpu.switch)" \
    || bad "die Vektorregister werden beim Umschalten nicht gerettet"

echo
echo "== 3. die Leinwand und die Ein-Kern-Regel =="
grep -q 'const K_CANVAS' kernel/user/wlib.fi \
    && ok "kernel/user/wlib.fi hat das Widget K_CANVAS" || bad "K_CANVAS fehlt"
grep -q 'fn canvas_event' kernel/user/wlib.fi \
    && ok "die Leinwand hat einen Ereignisring (canvas_event)" \
    || bad "canvas_event fehlt"
grep -q 'import libc.mem' kernel/user/wlibc.fi \
    && bad 'wlibc bindet libc.mem -- zwei Module mem in einem Programm (Ein-Kern-Regel)' \
    || ok 'wlibc kommt ohne libc.mem aus (kein zweites Modul mem neben html.mem)'
grep -q 'fn gmem' kernel/user/wlibc.fi \
    && ok "der Glyphenspeicher kommt aus eigenen 64-KiB-Stuecken (gmem)" \
    || bad "gmem fehlt"
grep -q 'wlib.leinwand(' "$CERTUS_REPO/lib/fenster/osum.fi" \
    && ok "die vierte Rueckwand (lib/fenster/osum.fi) legt eine wlib-Leinwand an" \
    || bad "lib/fenster/osum.fi legt keine Leinwand an"
for f in b_zurueck b_vor b_neu e_adr; do
    grep -q "$f" "$CERTUS_REPO/lib/fenster/osum.fi" || bad "Widget $f fehlt in der Rueckwand"
done
grep -q 'wlib.button' "$CERTUS_REPO/lib/fenster/osum.fi" \
    && grep -q 'wlib.entry' "$CERTUS_REPO/lib/fenster/osum.fi" \
    && ok "Zurueck/Vor/Neu sind wlib.button, die Adresse ist wlib.entry" \
    || bad "die Leiste ist nicht aus wlib-Widgets"

echo
echo "== 4. die Platte, die Pakete und der Laden =="
python3 "$OPK" schluessel "$OUT" > "$OUT/key.log" 2>&1
cp -f "$OUT/oeffentlich.key" "$OUT/schluessel.pub"
bash tools/loader/pakete.sh "$OUT" > "$OUT/pakete.log" 2>&1 \
    && ok "$(ls "$OUT"/stand/*.opk | wc -l) Pakete gebaut" \
    || { bad "pakete.sh"; tail -12 "$OUT/pakete.log"; }
[ -s "$OUT/stand/certus-1.opk" ] \
    && ok "certus-1.opk liegt im Stand ($(stat -c%s "$OUT/stand/certus-1.opk") Oktette)" \
    || bad "certus-1.opk fehlt"
python3 tools/update/signpak.py "$OUT/geheim.key" "$OUT"/stand/*.opk > /dev/null 2>&1 \
    && ok "jedes Paket ist signiert" || bad "signpak.py"
grep -q '^certus|' tools/loader/apps.tab \
    && ok "der Browser steht im Katalog des Ladens (tools/loader/apps.tab)" \
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
echo "== 5. eine echte Seite, im Fenster =="
lauf_wig seite "http://10.0.2.2:$PORT/i.htm" ",--dump=/tmp/s.ppm" 18
hat "$OUT/seite.txt" "k15: start /bin/certus" "der Kern hat /bin/certus im Fensterserver gestartet"
BP=$(grep -oaE 'wig: blits=[0-9]+' "$OUT/seite.txt" | tail -1 | cut -d= -f2)
PX=$(grep -oaE 'pixels=[0-9]+' "$OUT/seite.txt" | tail -1 | cut -d= -f2)
num "WIG_BLIT: Aufrufe aus Ring 3" "$BP" ge 1
num "Bildpunkte, die wirklich ins Fenster geschoben wurden" "$PX" ge 300000
python3 tools/osum/mkfs.py cat "$OUT/seite.img" /tmp/s.ppm > "$OUT/seite.ppm" 2>/dev/null
if [ -s "$OUT/seite.ppm" ]; then
    ok "Certus hat seinen Abzug auf die Platte des Gastes geschrieben ($(stat -c%s "$OUT/seite.ppm") Oktette)"
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
    bad "kein Abzug auf der Platte"
fi
if [ -s "$OUT/seite.png" ]; then
    mkdir -p "$SHOTS"; cp -f "$OUT/seite.png" "$SHOTS/fenster.png"
    FARBEN=$(python3 -c "
from PIL import Image
im = Image.open('$OUT/seite.png').convert('RGB')
print(len(im.getcolors(1 << 24) or []))")
    num "Bildschirmfoto: verschiedene Farben (ein leerer Schirm hat zwei)" "$FARBEN" ge 50
else
    bad "kein Bildschirmfoto der Seite"
fi

echo
echo "== 6. eine Seite mit JavaScript =="
lauf_wig js "http://10.0.2.2:$PORT/j.htm" ",--dump=/tmp/j.ppm" 18
python3 tools/osum/mkfs.py cat "$OUT/js.img" /tmp/j.ppm > "$OUT/js.ppm" 2>/dev/null
if [ -s "$OUT/js.ppm" ]; then
    python3 tools/certus/pixel.py "$OUT/js.ppm" --json "$OUT/js.json" | sed 's/^/        /'
    JT=$(python3 -c "import json;print(json.load(open('$OUT/js.json'))['tintenpunkte'])")
    num "JS-Seite: Tintenpunkte" "$JT" ge 3000
    ROT=$(python3 tools/certus/farbe.py "$OUT/js.ppm" cc0000)
    BLAU=$(python3 tools/certus/farbe.py "$OUT/js.ppm" 0033aa)
    num "der Kasten ist ROT -- das Skript hat style.backgroundColor gesetzt" "$ROT" ge 5000
    num "und NICHT mehr blau (die Farbe aus dem Quelltext)" "$BLAU" eq 0
    mkdir -p "$SHOTS"
    python3 tools/certus/pixel.py "$OUT/js.ppm" --png "$SHOTS/javascript.png" >/dev/null
else
    bad "die JS-Seite hat keinen Abzug geliefert"
fi

echo
echo "== 7. Zeit bis Bild =="
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
    ok "Zeit vom Programmstart bis zum fertigen Bild: ${MS} ms"
    echo "$MS" > "$OUT/zeit-ms.txt"
    num "das Bild kam ueberhaupt (ms)" "$MS" gt 0
else
    bad "kein Bild -- Start gefunden: $t_start, Bild: $t_bild"
fi
HOEHE=$(grep -oaE '^HOEHE [0-9]+' "$OUT/zeit.txt" | head -1 | awk '{print $2}')
num "die Dokumenthoehe, die Certus ausgerechnet hat (Bildpunkte)" "$HOEHE" ge 100
rm -f "$OUT/zeit.img"

echo
echo "== 8. $SOAK Laeufe ohne Panik =="
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
        ohne=$((ohne + 1)); echo "        Lauf $i: certus kam nicht hoch"; }
    rm -f "$OUT/$n.img" "$OUT/$n.ppm"
    i=$((i + 1))
done
num "Laeufe insgesamt" "$lief" eq "$SOAK"
num "Laeufe mit Panik" "$panik" eq 0
num "Laeufe, in denen der Browser nicht hochkam" "$ohne" eq 0

echo
echo "== 9. aus dem Laden installiert =="
cp --sparse=always -f "$OUT/platte/disk.img" "$OUT/store.img"
LADEN_PLATTE="$OUT/store.img" bash tools/loader/lauf.sh store \
    "osum vfs nokbd nosched noproc nofs noring3 script=opk install /store/certus-1.opk;opk list;exit" \
    900 > "$OUT/store.lauf" 2>&1
hat "$OUT/store.txt" "installiert certus" "opk hat das signierte Paket angenommen"
hat "$OUT/store.txt" "certus" "certus steht danach in der Paketliste"

echo
echo "CERTUS: $pass bestanden, $fail gefallen"
[ "$fail" -eq 0 ] || exit 1
