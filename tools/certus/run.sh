#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/certus/run.sh -- CERTUS ALS ANWENDUNG VON OSUM, gemessen.
#
# Die Frage dieser Runde ist nicht, ob es einen Browser gibt -- den gibt
# es seit den Runden B1 bis B6 im Firn-Baum. Die Frage ist, ob er IN
# DIESEM BETRIEBSSYSTEM laeuft: mit dessen Fensterserver, dessen Netz,
# dessen Adressraum. Dieser Laeufer beantwortet sie mit Zahlen.
#
#   1. BAUEN. `/bin/certus` als eigenstaendige ELF64-Datei fuer Ring 3 --
#      derselbe Weg wie jedes andere Programm auf dieser Platte
#      (`kernel/user/user.ld`, IMAGE_BASE 0x40100000, drei Segmente mit
#      getrennten Rechten). Und die Gegenprobe dazu: keine undefinierte
#      Referenz, kein libc-Name.
#
#   2. DER ADRESSRAUM. Runde CERTUS hat die grosse Arena von 6 MiB auf
#      192 MiB vergroessert, weil ein Browser gemessen 47 MiB
#      Adressraum braucht (`tools/certus/speicher.py`). Hier wird
#      geprueft, dass die Zahlen im Kern stehen und dass ein Prozess sie
#      wirklich bekommt.
#
#   3. EINE ECHTE SEITE. Ein Webserver auf dem WIRT, QEMUs Benutzernetz
#      als Draht, und `/bin/certus http://10.0.2.2:<port>/…` im Gast.
#      Der Gast laedt, baut den Baum, kaskadiert, legt aus, malt -- und
#      schreibt die Leinwand als PPM auf seine eigene Platte. Was wir
#      messen, ist das BILD und nicht die Behauptung.
#
#   4. DAS FENSTER. Dasselbe noch einmal mit Fensterserver, und das Bild
#      kommt diesmal von der ANDEREN SEITE: `screendump` ueber QEMUs
#      Monitor, also aus der Bildflaeche der emulierten Grafikkarte.
#      Ein Browser, der behauptet gemalt zu haben, und ein Bildschirm,
#      der leer ist, fallen genau hier auf -- die Falle aus Runde K7B.
#
#   5. GEMESSEN WIRD TINTE. `tools/certus/pixel.py` zaehlt in dem
#      Ausschnitt, in dem das Fenster steht: Punkte, die nicht die
#      Hintergrundfarbe sind, dunkle Punkte (das ist der Text) und
#      waagrechte Baender mit dunklen Punkten (das sind die Zeilen).
#      Und die GEGENPROBE: derselbe Lauf gegen eine LEERE Seite muss
#      einbrechen. Ohne sie hiesse "es ist Tinte da" auch bei einem
#      Browser, der Rauschen malt.
#
# Aufruf:  bash tools/certus/run.sh [--schnell]
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

FIRNC=${FIRNC:-vendor/firn/bin/firnc}
# `import libc.io` findet ueber $FIRNLIB nach <repo>/lib; `import std.rt`
# findet der Uebersetzer selbst neben seiner Binaerdatei
# (vendor/firn/lib). Beide Wege gelten gleichzeitig, und certus braucht
# beide.
export FIRNLIB="$(pwd)/lib"
SANS=assets/osum-sans.ttf
MONO=assets/osum-mono.ttf
SHOTS=${CERTUS_SHOTS:-docs/shots/certus}
OSUM_IP=10.0.2.15
OSUM_GW=10.0.2.2

TMPD=$(mktemp -d)
WWW="$TMPD/www"
trap 'rm -rf "$TMPD"; [ -n "${SRVPID:-}" ] && kill $SRVPID 2>/dev/null' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { local n=$1 v=$2 op=$3 w=$4
    if [ -z "$v" ]; then bad "$n: keine Zahl (erwartet $op $w)"; return; fi
    if [ "$v" -"$op" "$w" ] 2>/dev/null; then ok "$n: $v"
    else bad "$n: $v, erwartet $op $w"; fi
}

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh fehlgeschlagen"; exit 1; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo "CERTUS: uebersprungen, qemu-system-x86_64 fehlt"; exit 0; }

echo "== 1. bauen: der Kern und /bin/certus =="
bash tools/build-kernel.sh "$TMPD/k0.mb" > "$TMPD/kbuild.log" 2>&1 \
    && ok "der Kern ist gebaut ($(stat -c%s "$TMPD/k0.mb") Oktette)" \
    || { bad "der Kern baut nicht"; sed 's/^/        /' "$TMPD/kbuild.log" | head -10; exit 1; }

PROGS="sh desktop taskbar launcher explorer dhcp echo ls cat edit widgetdemo"
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null \
    || bad "crt.s laesst sich nicht assemblieren"
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/e$p" 2>&1 \
        && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
            -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null \
        && strip --strip-all "$TMPD/$p.elf" \
        || bad "$p baut nicht"
done
ok "$(ls "$TMPD"/*.elf 2>/dev/null | wc -l) Programme des Userlands sind gebaut"

# CERTUS SELBST. Kein `profile kernel`, kein crt.o: der Browser ist ein
# gewoehnliches Firn-Programm mit Sammler, und `firnc -c` legt seinen
# EIGENEN `_start` hinein -- vier Befehle, die dieselben sind wie die in
# crt.s (rbp loeschen, rsp ausrichten, main rufen, exit). Deshalb wird
# hier NUR das Bindeskript benutzt und keine zweite Einsprungdatei; zwei
# `_start` waeren ein Binderfehler und keine Wahl.
CBUILD_OK=0
if "$FIRNC" -c -o "$TMPD/certus.o" \
        lib/certus/certus_main.fi > "$TMPD/ecertus" 2>&1; then
    if ld -T kernel/user/user.ld -o "$TMPD/certus.elf" "$TMPD/certus.o" \
            2> "$TMPD/ldcertus.err"; then
        cp "$TMPD/certus.elf" "$TMPD/certus.dbg"
        strip --strip-all "$TMPD/certus.elf"
        CBUILD_OK=1
        ok "/bin/certus ist gebaut ($(stat -c%s "$TMPD/certus.elf") Oktette)"
    else
        bad "ld scheitert an certus"
        grep -v 'GNU-stack\|RWX' "$TMPD/ldcertus.err" | sed 's/^/        /' | head -6
    fi
else
    bad "certus_main.fi uebersetzt nicht"
    sed 's/^/        /' "$TMPD/ecertus" | head -12
fi

if [ "$CBUILD_OK" = 1 ]; then
    kind=$(readelf -h "$TMPD/certus.elf" | awk -F: '/^  Type:/ {print $2}' | awk '{print $1}')
    [ "$kind" = "EXEC" ] && ok "certus ist ET_EXEC (statisch, kein Interpreter)" \
                         || bad "certus: ELF-Art '$kind'"
    u=$(nm -u "$TMPD/certus.dbg" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
    [ -z "$u" ] && ok "certus hat keinen einzigen undefinierten Namen (keine libc)" \
                || bad "undefinierte Namen: $u"
    seg=$(readelf -l "$TMPD/certus.elf" | grep -c '^  LOAD')
    num "certus: PT_LOAD-Segmente (Code / Konstanten / Daten getrennt)" "$seg" eq 3
    # W^X: kein Segment darf zugleich schreibbar UND ausfuehrbar sein.
    wx=$(readelf -lW "$TMPD/certus.elf" | awk '/^  LOAD/ {print $8 $9 $10}' | grep -c 'WE\|RWE')
    num "certus: Segmente, die zugleich schreib- und ausfuehrbar sind" "$wx" eq 0
    ende=$(readelf -lW "$TMPD/certus.elf" | python3 -c '
import sys
h = 0
for z in sys.stdin:
    t = z.split()
    if len(t) > 6 and t[0] == "LOAD":
        h = max(h, int(t[2], 16) + int(t[5], 16))
print(h)')
    num "certus endet unterhalb von proc.IMAGE_END (0x40400000)" "$ende" lt $((0x40400000))
    n=$(objdump -d "$TMPD/certus.elf" | grep -cE '^\s+[0-9a-f]+:.*\bsyscall\b')
    num "certus: syscall-Befehle (die einzige Tuer aus Ring 3)" "$n" ge 10
fi

echo
echo "== 2. der Adressraum: 192 MiB grosse Arena statt 6 =="
grep -qE '^const PRIV_SLOTS: u64 = 99$' kernel/proc.fi \
    && ok "kernel/proc.fi: PRIV_SLOTS = 99 (99 Kacheln zu 2 MiB)" \
    || bad "PRIV_SLOTS steht nicht auf 99"
grep -qE '^const BIG_TOP: u64 = 0x4C600000$' kernel/proc.fi \
    && ok "kernel/proc.fi: BIG_TOP = 0x4C600000" \
    || bad "BIG_TOP steht nicht auf 0x4C600000"
# Die Gegenprobe zur Gegenprobe: die private Gegend darf 0x50000000 NICHT
# erreichen, sonst waere das Programm, das tools/osum/run.sh dort bindet,
# ploetzlich gueltig und ein Abnahmefall waere still verschwunden.
python3 - <<'PY' && ok "die private Gegend endet vor 0x50000000 (tools/osum/run.sh bleibt gueltig)" \
                 || bad "die private Gegend erreicht 0x50000000"
import re, sys
s = open("kernel/proc.fi", encoding="utf-8").read()
slots = int(re.search(r"^const PRIV_SLOTS: u64 = (\d+)$", s, re.M).group(1))
span = int(re.search(r"^const USER_SPAN: u64 = (0x[0-9A-Fa-f]+)", s, re.M).group(1), 16)
base = int(re.search(r"^const USER_DATA: u64 = (0x[0-9A-Fa-f]+)", s, re.M).group(1), 16)
sys.exit(0 if base + span * slots <= 0x50000000 else 1)
PY

grep -q 'w_self' kernel/procfs.fi \
    && ok "kernel/procfs.fi kennt /proc/self (der Sammler fragt danach)" \
    || bad "/proc/self fehlt"
grep -q 'OSFXSR' kernel/arch/x86_64/boot.s \
    && ok "kernel/arch/x86_64/boot.s schaltet SSE ein (CR4.OSFXSR)" \
    || bad "SSE wird nicht eingeschaltet"
grep -q 'fxsave' kernel/arch/x86_64/switch.s \
    && ok "kernel/arch/x86_64/switch.s rettet die xmm-Register beim Umschalten" \
    || bad "die xmm-Register werden beim Umschalten nicht gerettet"

echo
echo "== 3. eine echte Seite, aus dem Netz, ins PPM =="
mkdir -p "$WWW"
cat > "$WWW/index.html" <<'HTML'
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
printf '<!doctype html><html><body></body></html>\n' > "$WWW/leer.html"
# example.com, so wie es am 28.08.2026 wirklich aussah -- damit der Lauf
# auch ohne Weg ins offene Netz eine ECHTE Seite misst und nicht eine,
# die fuer ihn geschrieben wurde.
cat > "$WWW/example.html" <<'HTML'
<!doctype html><html lang="en"><head><title>Example Domain</title><link rel="icon" href="data:,"><meta name="viewport" content="width=device-width, initial-scale=1"><style>body{background:#eee;width:60vw;margin:15vh auto;font-family:system-ui,sans-serif}h1{font-size:1.5em}div{opacity:0.8}a:link,a:visited{color:#348}</style></head><body><div><h1>Example Domain</h1><p>This domain is for use in documentation examples without needing permission. Avoid use in operations.</p><p><a href="https://iana.org/domains/example">Learn more</a></p></div></body></html>
HTML

PORT=$(python3 -c "import socket;s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1]);s.close()")
( cd "$WWW" && python3 -m http.server "$PORT" --bind 0.0.0.0 >/dev/null 2>&1 ) &
SRVPID=$!
sleep 1

python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
    && ok "der Verzeichnisbaum ist gebaut" || bad "tools/k15/tree.py scheitert"
printf '# taskbar.conf\nedge=bottom\nheight=32\nwidth=100\nautohide=0\nontop=1\n' \
    > "$TMPD/taskbar.conf"

mk_image() { # ziel
    local img=$1
    local ARGS=(build "$img" 32768 /lib/
        "/lib/mono.ttf=$MONO" "/lib/sans.ttf=$SANS" /bin/)
    local q
    for q in $PROGS; do
        [ -f "$TMPD/$q.elf" ] && ARGS+=("/bin/$q=$TMPD/$q.elf")
    done
    [ "$CBUILD_OK" = 1 ] && ARGS+=("/bin/certus=$TMPD/certus.elf")
    ARGS+=("/bin/files@/bin/explorer")
    ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme" "/etc/taskbar.conf=$TMPD/taskbar.conf")
    ARGS+=(/w/ /proc/ /dev/ /mnt/)
    while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py "$TMPD/apps" "$TMPD/buendel")
    while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
    python3 tools/osum/mkfs.py "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 || {
        sed 's/^/        /' "$TMPD/mkfs.txt" | head -6
        return 1
    }
    return 0
}

# DAS BUENDEL. `/apps/certus.osp/` ist das, was den Browser zu einer
# ANWENDUNG dieses Systems macht und nicht zu einer Datei unter /bin:
# Anzeigename, Beschreibung, Schluesselwoerter, Symbol -- und `start`,
# das auf dieselben Oktette zeigt wie /bin/certus (`<neu>@<vorhanden>`,
# kein zweiter Block).
cp -a assets/apps "$TMPD/apps"
# Ohne /bin/certus gibt es auch kein Buendel: `start` ist ein ZWEITER
# NAME auf die Datei unter /bin, und ein zweiter Name auf nichts ist ein
# Abbild, das mkfs zu Recht ablehnt.
[ "$CBUILD_OK" = 1 ] || rm -rf "$TMPD/apps/certus.osp"

TEXTRUN="$TMPD/text.txt"
run_text() { # url ppm-name ausgabe
    local url=$1 name=$2 out=$3
    mk_image "$TMPD/d-$name.img" || { bad "mkfs fuer $name"; return 1; }
    cp -f "$TMPD/d-$name.img" "$TMPD/l-$name.img"
    timeout 300 $QEMU_X86 -kernel "$TMPD/k0.mb" -m 512 \
        -append "osum vfs nokbd nosched noproc nofs noring3 nic nip=$OSUM_IP/24 ngw=$OSUM_GW script=certus $url /w/$name.ppm 1;exit" \
        -serial "file:$out" -display none -no-reboot \
        -drive "file=$TMPD/l-$name.img,format=raw,if=ide,index=0" \
        -netdev "user,id=n0" \
        -device "virtio-net-pci,netdev=n0,mac=52:54:00:aa:bb:cc" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/$name.qemu" 2>&1
    local rc=$?
    python3 tools/osum/mkfs.py cat "$TMPD/l-$name.img" "/w/$name.ppm" \
        > "$TMPD/$name.ppm" 2>"$TMPD/$name.caterr" || true
    return $rc
}

if [ "$CBUILD_OK" = 1 ]; then
    run_text "http://$OSUM_GW:$PORT/index.html" seite "$TEXTRUN"
    RC=$?
    if grep -qa 'CERTUS ' "$TEXTRUN"; then
        ok "certus hat im Gast gelaufen und seine Zahlen gemeldet"
        sed -n 's/.*\(CERTUS .*\)/        \1/p' "$TEXTRUN" | head -3
        B=$(grep -oaE 'body=[0-9]+' "$TEXTRUN" | head -1 | cut -d= -f2)
        F=$(grep -oaE 'font=[0-9]+' "$TEXTRUN" | head -1 | cut -d= -f2)
        R=$(grep -oaE 'render=[0-9]+' "$TEXTRUN" | head -1 | cut -d= -f2)
        D=$(grep -oaE 'dochigh=[0-9]+' "$TEXTRUN" | head -1 | cut -d= -f2)
        num "die Seite kam ueber TCP an (Oktette)" "$B" ge 300
        num "die Schrift wurde von /lib/sans.ttf gelesen (Oktette)" "$F" ge 10000
        num "der Aufbau lief durch (render=1)" "$R" eq 1
        num "das Dokument ist hoeher als eine Zeile (Bildpunkte)" "$D" ge 40
    else
        bad "certus hat im Gast nichts gemeldet (QEMU-Code $RC)"
        tail -12 "$TEXTRUN" 2>/dev/null | sed 's/^/        /'
    fi
    if [ -s "$TMPD/seite.ppm" ]; then
        python3 tools/certus/pixel.py "$TMPD/seite.ppm" --json "$TMPD/seite.json" \
            | sed 's/^/        /'
        mkdir -p "$SHOTS"
        python3 tools/gfx/ppm2png.py "$TMPD/seite.ppm" "$SHOTS/seite.png" 2>/dev/null \
            || python3 tools/certus/pixel.py "$TMPD/seite.ppm" --png "$SHOTS/seite.png"
        T=$(python3 -c "import json;print(json.load(open('$TMPD/seite.json'))['tintenpunkte'])")
        DK=$(python3 -c "import json;print(json.load(open('$TMPD/seite.json'))['dunkle_punkte'])")
        BD=$(python3 -c "import json;print(json.load(open('$TMPD/seite.json'))['textbaender'])")
        num "Tintenpunkte auf der Leinwand des Gastes" "$T" ge 5000
        num "dunkle Punkte -- das ist der TEXT, nicht die Kaesten" "$DK" ge 300
        num "waagrechte Textbaender" "$BD" ge 3
    else
        bad "der Gast hat kein PPM auf seine Platte geschrieben"
    fi

    echo
    echo "   -- DIE GEGENPROBE: dieselbe Maschine, eine LEERE Seite --"
    run_text "http://$OSUM_GW:$PORT/leer.html" leer "$TMPD/leer.txt"
    if [ -s "$TMPD/leer.ppm" ]; then
        python3 tools/certus/pixel.py "$TMPD/leer.ppm" --json "$TMPD/leer.json" \
            | sed 's/^/        /'
        LT=$(python3 -c "import json;print(json.load(open('$TMPD/leer.json'))['tintenpunkte'])")
        LD=$(python3 -c "import json;print(json.load(open('$TMPD/leer.json'))['dunkle_punkte'])")
        num "GEGENPROBE: Tintenpunkte einer leeren Seite" "$LT" eq 0
        num "GEGENPROBE: dunkle Punkte einer leeren Seite" "$LD" eq 0
    else
        bad "die Gegenprobe hat kein PPM geliefert"
    fi

    echo
    echo "   -- example.com, wie es wirklich aussieht --"
    run_text "http://$OSUM_GW:$PORT/example.html" example "$TMPD/example.txt"
    if [ -s "$TMPD/example.ppm" ]; then
        python3 tools/certus/pixel.py "$TMPD/example.ppm" --json "$TMPD/example.json" \
            | sed 's/^/        /'
        mkdir -p "$SHOTS"
        python3 tools/certus/pixel.py "$TMPD/example.ppm" --png "$SHOTS/example.png" >/dev/null
        ET=$(python3 -c "import json;print(json.load(open('$TMPD/example.json'))['tintenpunkte'])")
        ED=$(python3 -c "import json;print(json.load(open('$TMPD/example.json'))['dunkle_punkte'])")
        num "example.com: Tintenpunkte" "$ET" ge 2000
        num "example.com: dunkle Punkte (der Text)" "$ED" ge 200
    else
        bad "example.com hat kein PPM geliefert"
    fi
fi

echo
echo "== 4. das FENSTER, fotografiert von der anderen Seite =="
if [ "$CBUILD_OK" = 1 ]; then
    sock="$TMPD/mon.sock"; out="$TMPD/win.txt"; ppm="$TMPD/win.ppm"
    rm -f "$sock" "$out" "$ppm"
    mk_image "$TMPD/d-win.img" && cp -f "$TMPD/d-win.img" "$TMPD/l-win.img"
    timeout 420 $QEMU_X86 -kernel "$TMPD/k0.mb" -m 512 \
        -append "osum vfs gfx wm wig wmhold wmshell wiglong nokbd nosched noproc nofs noring3 nic nip=$OSUM_IP/24 ngw=$OSUM_GW script=certus http://$OSUM_GW:$PORT/index.html /w/win.ppm 0" \
        -serial "file:$out" -display none -no-reboot \
        -vga std -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/l-win.img,format=raw,if=ide,index=0" \
        -netdev "user,id=n0" \
        -device "virtio-net-pci,netdev=n0,mac=52:54:00:aa:bb:cc" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/win.qemu" 2>&1 &
    qpid=$!
    i=0
    while [ $i -lt 2400 ]; do
        grep -qa 'CERTUS ' "$out" 2>/dev/null && break
        kill -0 "$qpid" 2>/dev/null || break
        sleep 0.2
        i=$((i + 1))
    done
    sleep 4
    python3 tools/gfx/screenshot.py "$sock" "$ppm" 30 > "$TMPD/win.shot" 2>&1
    kill "$qpid" 2>/dev/null; wait "$qpid" 2>/dev/null
    if [ -s "$ppm" ]; then
        ok "der Bildschirm des Gastes ist fotografiert ($(stat -c%s "$ppm") Oktette)"
        mkdir -p "$SHOTS"
        python3 tools/certus/pixel.py "$ppm" --json "$TMPD/win.json" \
            --fenster | sed 's/^/        /'
        python3 tools/certus/pixel.py "$ppm" --png "$SHOTS/fenster.png" >/dev/null
        WT=$(python3 -c "import json;print(json.load(open('$TMPD/win.json'))['tintenpunkte'])")
        WD=$(python3 -c "import json;print(json.load(open('$TMPD/win.json'))['dunkle_punkte'])")
        WB=$(python3 -c "import json;print(json.load(open('$TMPD/win.json'))['textbaender'])")
        num "Bildschirm: Tintenpunkte" "$WT" ge 20000
        num "Bildschirm: dunkle Punkte" "$WD" ge 300
        num "Bildschirm: Textbaender" "$WB" ge 3
        # DIE FARBEN, DIE DIE SEITE VERLANGT HAT, auf dem Schirm der
        # emulierten Grafikkarte. Ein weisses Rechteck bestuende jede
        # Zaehlung darueber und hiesse nichts.
        BL=$(python3 tools/certus/farbe.py "$ppm" 0033aa)
        RD=$(python3 tools/certus/farbe.py "$ppm" cc0000)
        num "der blaue Kasten der Seite (#0033aa, 300x80 = 24000)" "$BL" ge 20000
        num "der rote Kasten der Seite (#cc0000, 200x40 = 8000)" "$RD" ge 6000
        BP=$(grep -oaE 'blitpx=[0-9]+' "$out" | head -1 | cut -d= -f2)
        num "Bildpunkte, die WIG_BLIT wirklich ins Fenster geschoben hat" "$BP" ge 400000
    else
        bad "kein Bildschirmfoto"
        tail -3 "$TMPD/win.qemu" 2>/dev/null | sed 's/^/        /'
        tail -2 "$TMPD/win.shot" 2>/dev/null | sed 's/^/        /'
    fi
fi

kill $SRVPID 2>/dev/null; SRVPID=""
echo
echo "CERTUS: $pass bestanden, $fail gefallen"
[ "$fail" -eq 0 ] || exit 1
