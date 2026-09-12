#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/systembus/run.sh -- DER SYSTEMBUS, GEMESSEN STATT BEHAUPTET.
#
#   bash tools/systembus/run.sh
#
# ======================================================================
# WARUM ES DIESEN LAEUFER GIBT
# ======================================================================
#
# Die Wegkarte (/root/osum-roadmap/ROADMAP.md, A3) nennt den Systembus
# den wichtigsten Einzelposten und begruendet das so: "Baust du ihn
# nicht, baust du ihn siebenmal." Zwischenablage, Drag-and-Drop,
# Benachrichtigungen, Energie und Sperrbildschirm haengen alle daran.
#
# Ein Bus ist die Art Sache, die sich SEHR leicht behaupten laesst: ein
# paar Systemrufe, ein Kommentar, und in einem Lauf mit einem Kern sieht
# alles gut aus. Was ihn wirklich ausmacht, ist:
#
#   -- traegt eine Nachricht die Kennung des ABSENDERS, und zwar die
#      echte aus der Aufgabentafel und nicht die behauptete,
#   -- wird ein Ruf ohne Recht ABGELEHNT, sichtbar und zaehlbar,
#   -- ueberlebt das Ganze VIER KERNE, die gleichzeitig hineinschreiben,
#   -- und wird ein Megabyte GETEILT oder heimlich kopiert.
#
# Jede dieser Fragen hat hier einen Abschnitt, und drei davon haben eine
# GEGENPROBE -- einen Lauf, in dem die Zusage brechen MUSS. Eine
# Messung, die auch ohne die Eigenschaft dasselbe sagt, misst nichts.
set -u
cd "$(dirname "$0")/../.."
TMPD=${SYSBUS_TMPD:-$(mktemp -d)}
[ -n "${SYSBUS_KEEP:-}" ] || trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { echo "  OK   $*"; pass=$((pass + 1)); }
bad() { echo "  FAIL $*"; fail=$((fail + 1)); }
QEMU=${QEMU:-qemu-system-x86_64}
export FIRNLIB="$PWD/lib"

echo "== 1. die Karte von kdata =="
kol=$(python3 tools/kernel/memmap.py kernel 2>&1 | tail -1)
echo "        $kol"
case "$kol" in
    *" 0 Kollisionen") ok "der Busbereich ueberschneidet nichts" ;;
    *) bad "die Karte hat Kollisionen" ;;
esac
grep -q 'BUS_OFF' tools/kernel/memmap.py \
    && ok "der Bereich steht in der Karte des Pruefers" \
    || bad "BUS_OFF fehlt in tools/kernel/memmap.py"

echo
echo "== 2. die Ein-Kern-Regel, an der Quelle =="
# EIN GLOBALER PUFFER IST DIE FORM DES FEHLERS, NICHT SEIN NAME.
# `static mut` in einer Kerneldatei ist genau das: ein Platz, den alle
# Kerne teilen und den niemand sperrt. STATUS-MERGE6.md haelt zwei
# davon fest (fs.inode_get, wig.glyph_into). In bus.fi darf es keinen
# geben.
n_static=$(grep -c '^static mut' kernel/bus.fi || true)
if [ "$n_static" = 0 ]; then
    ok "kernel/bus.fi hat keinen 'static mut'"
else
    bad "kernel/bus.fi hat $n_static globale Variablen"
fi
if sed -n '/^fn do_bus/,/^}/p' kernel/sys.fi | grep -q 'state + kstate\.'; then
    bad "sys.do_bus fasst einen kdata-Puffer an"
else
    ok "sys.do_bus kopiert in seinen eigenen Stapelrahmen"
fi
py=$(python3 - <<'PYEOF'
import re
s = open("kernel/bus.fi", encoding="utf-8", errors="surrogateescape").read()
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
# `init` laeuft vor dem ersten Nutzerprozess und vor dem zweiten Kern.
# Die reinen Leser einzelner Woerter lesen ein Wort atomar; eine Sperre
# dafuer waere teurer als der Zugriff. Wer diese Liste erweitert, muss
# den Grund danebenschreiben -- sonst ist der Pruefer eine Zierde.
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
    ok "$nfun Funktionen in bus.fi -- jeder Weg an die Tafel geht durch take()"
else
    bad "diese fassen die Tafel ohne Sperre an: $leck"
fi

echo
echo "== 3. der Kern und die Programme =="
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/k.log" 2>&1 \
    && ok "der Kern baut ($(stat -c%s "$TMPD/k.mb") Oktette)" \
    || { bad "der Kern baut nicht"; tail -12 "$TMPD/k.log" | sed 's/^/        /'
         echo "SYSTEMBUS: $pass bestanden, $fail gescheitert"; exit 1; }

PROGS="desktop taskbar settings launcher dhcp explorer widgetdemo locate sh echo ls cat edit"
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null \
    || bad "crt.s laesst sich nicht assemblieren"
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
    ok "die $(echo $PROGS | wc -w) Programme bauen"
else
    bad "die Programme bauen nicht"
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
echo "== 4. vier Kerne, zwei Prozesse, hundert Durchlaeufe =="
lauf vier 4 "busbench bus r3alle" 200
A="$TMPD/vier.txt"
if grep -qa '^panic:\|^\*\*\* EXCEPTION' "$A"; then
    bad "der Lauf ist gestorben: $(grep -am1 '^panic:\|^\*\*\* EXCEPTION' "$A")"
else
    ok "der Lauf mit vier Kernen lebt"
fi
run=$(wert "$A" 'busa: run=')
abw=$(wert "$A" 'busa: abw=')
got=$(wert "$A" 'busb: got=')
leer=$(wert "$A" 'busb: leer=')
echo "        busa run=$run abw=$abw   busb got=$got leer=$leer"
[ "${run:-0}" = 100 ] && ok "hundert Durchlaeufe gefahren" \
                      || bad "nicht hundert Durchlaeufe, sondern '${run:-nichts}'"
[ "${abw:-1}" = 0 ] && ok "NULL Abweichungen -- was A ablegte, las B Oktett fuer Oktett" \
                    || bad "$abw Abweichungen zwischen Schreiber und Leser"
[ "${leer:-1}" = 0 ] && ok "keine Runde ohne Nachricht beim Leser" \
                     || bad "$leer Runden ohne Nachricht"
drops=$(wert "$A" 'bus: drops=')
[ "${drops:-1}" = 0 ] && ok "keine Nachricht verloren (drops=0)" \
                      || bad "$drops Nachrichten verloren"
cs=$(wert "$A" 'bus: clipsets=')
cg=$(wert "$A" 'bus: clipgets=')
if [ "${cs:-0}" = 100 ] && [ "${cg:-0}" = 100 ]; then
    ok "hundertmal abgelegt, hundertmal gelesen"
else
    bad "clipsets=$cs clipgets=$cg"
fi
hist=$(wert "$A" 'bus: verlauf=')
[ "${hist:-0}" = 20 ] && ok "der Verlauf steht bei zwanzig und laeuft nicht ueber" \
                      || bad "der Verlauf zeigt '${hist:-nichts}' statt 20"

echo
echo "== 5. das Nein, das man sehen kann =="
ruf=$(wert "$A" 'busd: ruf=')
vor=$(wert "$A" 'busd: vor=')
uid=$(wert "$A" 'busd: uid=')
echo "        vor=$vor uid=$uid ruf=$ruf"
[ "${vor:-x}" = 0 ] && ok "als root geht derselbe Ruf durch (die Gegenprobe)" \
                    || bad "schon als root abgelehnt: '$vor'"
[ "${uid:-0}" = 1000 ] && ok "der Prozess hat seine Wurzelrechte wirklich abgelegt" \
                       || bad "uid ist '$uid' statt 1000"
[ "${ruf:-x}" = "-3" ] && ok "der unberechtigte Ruf wird abgelehnt (E_DENIED)" \
                       || bad "der Ruf gab '$ruf' statt -3"
z=$(grep -ac '^bus: ABGELEHNT' "$A" || true)
if [ "${z:-0}" -ge 1 ]; then
    ok "die Ablehnung steht auf der Leitung: $(grep -am1 '^bus: ABGELEHNT' "$A")"
else
    bad "abgelehnt wurde still -- keine Zeile 'bus: ABGELEHNT'"
fi
den=$(wert "$A" 'bus: denied=')
if [ "${den:-0}" -ge 1 ] 2>/dev/null; then
    ok "und sie ist gezaehlt (denied=$den)"
else
    bad "der Zaehler denied steht auf '${den:-nichts}'"
fi

echo
echo "== 6. ein Megabyte, geteilt und nicht kopiert =="
byt=$(wert "$A" 'buss: byt=')
us=$(wert "$A" 'buss: us=')
sum=$(wert "$A" 'buss: sum=')
sgp=$(wert "$A" 'bus: segseiten=')
echo "        byt=$byt us=$us sum=$sum seiten=$sgp"
[ "${byt:-0}" = 1048576 ] && ok "ein volles Megabyte" || bad "byt=$byt"
[ "${sgp:-0}" = 256 ] && ok "256 Seiten aus dem Rahmenverwalter" || bad "segseiten=$sgp"
if [ -n "${us:-}" ] && [ "$us" -lt 5000 ] 2>/dev/null; then
    ok "durch in ${us} us -- unter der Zusage von 5000 us"
else
    bad "die Uebergabe brauchte '${us:-nichts}' us"
fi
erw=$(python3 -c 'n=131072; print((sum(range(n)) + 7*n) & (2**64-1))')
[ "${sum:-0}" = "$erw" ] && ok "und der Inhalt stimmt (Summe $erw)" \
                         || bad "die Summe ist $sum statt $erw"

echo
echo "== 7. die Gegenproben =="
lauf ohne 4 "bus r3alle" 120
if grep -qa '^bus: skipped' "$TMPD/ohne.txt"; then
    ok "ohne 'busbench' laeuft kein Busprogramm"
else
    bad "die Programme laufen auch ohne 'busbench'"
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
echo "== 8. die Oberflaeche: die Meldungen in der Leiste =="
python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
    || bad "tools/k15/tree.py faellt"
printf '# taskbar.conf\nedge=0\nheight=40\nwidth=0\nautohide=0\nontop=1\n' > "$TMPD/tb.conf"
ARGS=(build "$TMPD/disk.img" 16384 /lib/
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$TMPD/$p.elf"); done
ARGS+=("/bin/files@/bin/explorer")
ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme" "/etc/taskbar.conf=$TMPD/tb.conf")
while read -r z; do ARGS+=("$z"); done \
    < <(python3 tools/k15/bundle.py assets/apps "$TMPD/buendel" "nur=$PROGS")
while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
if python3 tools/osum/mkfs.py "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1; then
    ok "die Platte steht ($(stat -c%s "$TMPD/disk.img") Oktette)"
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
    timeout 320 $QEMU -kernel "$TMPD/k.mb" -m 512 \
        -append "gfx fbres=1024x768 wm wig desk wmhold wighalt=300 nokbd nosched noproc nofs $extra" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -device "VGA,edid=on,xres=1024,yres=768,vgamem_mb=32" \
        -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/$name.qemu" 2>&1 &
    local pid=$! i=0
    while [ $i -lt 1500 ]; do
        grep -qa '^wm: hold' "$TMPD/$name.txt" 2>/dev/null && break
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
        ok "das Bild $1.png liegt vor"
    else
        bad "kein Bild $1"
    fi
}

cat > "$TMPD/dreh1" <<'DREH'
warteauf 'wm: hold' || 90
warte 5
foto 01-leiste-meldung
DREH
gui leiste "bus notidemo" "$TMPD/dreh1"
if grep -qa 'Meldg' "$TMPD/leiste.txt"; then
    ok "die Leiste zeigt die Meldungen des Busses: $(grep -aom1 'Meldg [0-9]*' "$TMPD/leiste.txt")"
else
    bad "in der Leiste steht keine Meldung"
fi
bild 01-leiste-meldung

echo
echo "== 9. die Oberflaeche: kopieren im Editor, einfuegen im Terminal =="
# DIE BEWEGUNG, UM DIE ES GEHT, und sie ist die Zusage d) der Runde:
# im Editor STRG-K (Zeile ausschneiden), Editor zu, dann in der
# Kommandozeile `clip` -- und dort steht dieselbe Zeile. ZWEI PROZESSE,
# EINE Ablage, und der Weg dazwischen ist der Bus und nichts sonst.
#
# Getippt wird ueber den QEMU-Monitor, Taste fuer Taste. `tipp` macht
# aus einem Wort die `taste`-Zeilen des Drehbuchs -- von Hand waeren es
# vierzig Zeilen, und vierzig Zeilen liest niemand nach.
tipp() {
    python3 - "$1" <<'PY'
import sys
karte = {" ": "spc", "-": "minus", "/": "slash", ".": "dot",
         "_": "shift-minus", "=": "equal", ",": "comma"}
for c in sys.argv[1]:
    print("taste " + karte.get(c, c))
PY
}
{
    echo "warteauf 'wm: hold' || 90"
    echo "warte 5"
    echo "foto 02-schreibtisch"
    # 1. in das Terminalfenster klicken, damit die Tasten dort landen
    echo "klickauf tbbtn0"
    echo "warte 2"
    # 2. den Editor auf eine Datei starten, die es gibt
    tipp "edit /etc/taskbar.conf"
    echo "taste ret"
    echo "warteauf 'edit: ready' || 40"
    echo "warte 3"
    echo "foto 03-editor"
    # 3. STRG-K schneidet die Zeile aus -- und legt sie auf den Bus
    echo "taste ctrl-k"
    echo "warte 2"
    echo "foto 04-editor-nach-strg-k"
    # 4. Editor zu, OHNE zu sichern
    echo "taste ctrl-x"
    echo "warte 2"
    echo "taste n"
    echo "warte 3"
    # 5. und im Terminal nachsehen, was auf dem Bus liegt
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
    ok "der Editor ist im Terminalfenster wirklich gestartet"
else
    bad "der Editor ist nie gestartet -- die Tasten kamen nicht an"
fi
bild 02-schreibtisch
bild 03-editor
bild 04-editor-nach-strg-k
bild 05-terminal-clip
bild 06-terminal-verlauf

echo
echo "SYSTEMBUS: $pass bestanden, $fail gescheitert"
[ "$fail" = 0 ]
