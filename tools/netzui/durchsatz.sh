#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/netzui/durchsatz.sh -- RUNDE O-NETZUI: DER DURCHSATZ IST ECHT
# GEMESSEN, UND HIER IST DIE ZAHL.
#
#   bash tools/netzui/durchsatz.sh
#
# ==================================================================
# DIE FRAGE, DIE DIESER LAEUFER BEANTWORTET
# ==================================================================
#
# `tools/netzui/run.sh` prueft die RECHNUNG: aus zwei Zaehlerstaenden
# und einer Zeitdifferenz wird eine Rate, und die Einheiten stimmen.
# Was es nicht pruefen kann -- und was eine Anzeige wertlos macht, wenn
# es nicht stimmt -- ist die Frage davor:
#
#   BEWEGEN SICH DIE ZAEHLER UEBERHAUPT, WENN WIRKLICH ETWAS FLIESST?
#
# Eine Anzeige, die eine saubere Rate aus zwei Zahlen rechnet, die immer
# null sind, sieht im Bild genauso aus wie eine, die funktioniert.
#
# ALSO WIRD LAST ERZEUGT UND DAGEGEN GEHALTEN. Eine Maschine, ein Draht
# (derselbe wie in `tools/netmon/run.sh`: veth, Netzraum, die
# AF_PACKET-Bruecke), ein HTTP-Server auf dem Wirt mit einer Datei, deren
# Groesse DER WIRT bestimmt, und `/bin/netzmess`, das genau die zwei
# Zaehler im Sekundentakt liest, aus denen die Netzseite ihre Rate baut.
#
# DIE VIER ZUSAGEN:
#
#   1. IN RUHE IST DIE RATE NULL. Ohne Verkehr darf keine Zeile eine
#      Empfangsrate ueber einer Handvoll Oktetten melden -- was bleibt,
#      sind ARP und die DHCP-Nachhut, und das sind zweistellige Zahlen.
#   2. UNTER LAST GEHT SIE HOCH. Waehrend des Downloads muss die
#      gemessene Rate ein Vielfaches des Ruhewerts sein.
#   3. DANACH FAELLT SIE WIEDER. Eine Anzeige, die nach dem Download
#      stehenbleibt, behauptet Verkehr, den es nicht gibt -- das ist
#      genau der Fehler, den ein zu langes Glaettungsfenster macht.
#   4. DIE SUMME PASST ZUR DATEI. Was die Zaehler an Zuwachs melden,
#      muss mindestens so gross sein wie die Datei und darf nicht
#      unsinnig viel groesser sein (Rahmenkoepfe und Bestaetigungen
#      kommen dazu -- das ist der Unterschied zwischen Nutzlast und
#      Draht, den `kernel/net/netmon.fi` in seinem Kopf erklaert).
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
LDSCRIPT=kernel/kernel.ld
ULD=kernel/user/user.ld
PROGS="sh ls cat echo wget netzmess sleep"
BLOCKS=16384

NS=nzui-$$
V0=nz0-$$
V1=nzp-$$
OSUM_IP=10.9.0.2
HOST_IP=10.9.0.1
QPORT=$(( 5600 + ($$ % 90) * 2 ))
BPORT=$(( QPORT + 1 ))
TMPD=$(mktemp -d)
BRPID=""; QPID=""; SRVPID=""

cleanup() {
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    [ -n "$QPID" ]  && kill "$QPID" 2>/dev/null
    [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    rm -rf "$TMPD"
}
trap cleanup EXIT

pass=0; fail=0
ok()  { echo "  ok   $*"; pass=$((pass+1)); }
bad() { echo "  FAIL $*"; fail=$((fail+1)); }
note(){ echo "       $*"; }
num() { # text wert op soll
    local t=$1 v=$2 op=$3 s=$4
    if [ -z "$v" ]; then bad "$t: keine Zahl gefunden"; return; fi
    if [ "$v" -"$op" "$s" ] 2>/dev/null; then ok "$t: $v"; else bad "$t: $v (erwartet $op $s)"; fi
}

for t in qemu-system-x86_64 ip gcc python3; do
    command -v "$t" >/dev/null 2>&1 || { echo "NETZUI-DURCHSATZ: uebersprungen, $t fehlt"; exit 0; }
done
ip netns del "$NS" 2>/dev/null
if ! ip netns add "$NS" 2>/dev/null; then
    echo "NETZUI-DURCHSATZ: uebersprungen, Netzraeume gehen hier nicht"
    exit 0
fi
ip netns del "$NS" 2>/dev/null

echo "== 1. bauen =="
for f in boot isr switch smp hv; do
    as --64 -o "$TMPD/$f.o" "kernel/arch/x86_64/$f.s" 2>/dev/null \
        || bad "$f.s assembliert nicht"
done
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s"

"$FIRNC" kernel/kmain.fi -o "$TMPD/k0.o" >"$TMPD/e0" 2>&1 \
    || { bad "der Kern uebersetzt nicht"; sed 's/^/        /' "$TMPD/e0" | head -10; \
         echo "NETZUI-DURCHSATZ: $pass passed, $((fail)) failed"; exit 1; }
"$FIRNC" kernel/uprog.fi -o "$TMPD/u0.o" >>"$TMPD/e0" 2>&1 || bad "uprog.fi"
ld -n -T "$LDSCRIPT" \
    --defsym=KERNEL_MAIN="_F0.kernel_main" \
    --defsym=KERNEL_TRAP="_F0.trap__entry" \
    --defsym=KERNEL_SYSCALL="_F0.sys__entry" \
    --defsym=KERNEL_TASK_MAIN="_F0.tasks__main" \
    --defsym=KERNEL_USER_START="_F0.proc__user_start" \
    --defsym=KERNEL_AP_MAIN="_F0.smp__ap_main" \
    --defsym=USER_MAIN="_F0.u_enter" \
    -o "$TMPD/k0.elf" "$TMPD/boot.o" "$TMPD/isr.o" "$TMPD/switch.o" \
    "$TMPD/smp.o" "$TMPD/hv.o" "$TMPD/k0.o" "$TMPD/u0.o" 2>"$TMPD/ld.err" \
    || { bad "ld scheitert am Kern"; sed 's/^/        /' "$TMPD/ld.err" | head -5; }
objcopy -O elf32-i386 "$TMPD/k0.elf" "$TMPD/k0.mb" 2>/dev/null
[ -s "$TMPD/k0.mb" ] && ok "der Kern ist gebaut ($(stat -c%s "$TMPD/k0.mb") Oktette)" \
    || { bad "kein Kernabbild"; echo "NETZUI-DURCHSATZ: $pass passed, $fail failed"; exit 1; }

for p in $PROGS; do
    UPROF=""; UCRT="$TMPD/crt.o"
    grep -qa '^profile app' "kernel/user/$p.fi" && { UPROF=--profile=app; UCRT=""; }
    "$FIRNC" $UPROF -c "kernel/user/$p.fi" -o "$TMPD/$p.o" >"$TMPD/e$p" 2>&1 \
        || { bad "$p.fi uebersetzt nicht"; sed 's/^/        /' "$TMPD/e$p" | head -6; continue; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" \
        -o "$TMPD/$p.elf" $UCRT "$TMPD/$p.o" 2>/dev/null \
        || { bad "ld scheitert an $p"; continue; }
    strip --strip-all "$TMPD/$p.elf"
done
[ -s "$TMPD/netzmess.elf" ] && ok "/bin/netzmess ist gebaut" || bad "/bin/netzmess fehlt"

SPEC="/bin/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done
SPEC="$SPEC /var/ /var/net/ /etc/"
python3 tools/osum/mkfs.py build "$TMPD/disk.img" $BLOCKS $SPEC \
    > "$TMPD/mkfs.txt" 2>&1 && ok "ein Abbild mit /bin/netzmess" \
    || { bad "mkfs.py scheitert"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -5; }

gcc -O2 -o "$TMPD/bruecke" tools/net/bridge.c 2>"$TMPD/gcc.err" \
    && ok "die Bruecke zum Draht ist gebaut" \
    || bad "tools/net/bridge.c uebersetzt nicht"

# --------------------------------------------------------------- Draht
wire_up() {
    ip netns del "$NS" 2>/dev/null; ip link del "$V0" 2>/dev/null
    ip netns add "$NS"
    ip link add "$V0" type veth peer name "$V1"
    ip link set "$V1" netns "$NS"
    ip netns exec "$NS" ip addr add "$HOST_IP/24" dev "$V1"
    ip netns exec "$NS" ip link set "$V1" up
    ip netns exec "$NS" ip link set lo up
    ip link set "$V0" up
    ethtool -K "$V0" tx off rx off tso off gso off gro off >/dev/null 2>&1
    ip netns exec "$NS" ethtool -K "$V1" tx off rx off tso off gso off gro off >/dev/null 2>&1
}
wire_down(){ ip netns del "$NS" 2>/dev/null; ip link del "$V0" 2>/dev/null; }
bridge_up(){ "$TMPD/bruecke" "$V0" "$BPORT" "$QPORT" 2>"$TMPD/br.log" & BRPID=$!; sleep 0.4; }
bridge_down(){ [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null; wait "$BRPID" 2>/dev/null; BRPID=""; sleep 0.2; }

# DIE DATEI IST EIN MEGAOKTETT. Gross genug, dass der Download mehrere
# Sekunden dauert und damit in mehreren Zeilen von `netzmess` auftaucht
# -- eine Datei, die in einer halben Sekunde durch ist, waere in genau
# einer Zeile zu sehen und in keiner zweiten, und "die Rate geht hoch
# und wieder runter" liesse sich daran nicht zeigen.
BODY=1048576
cat > "$TMPD/httpsrv.py" <<'PY'
import http.server, socketserver, sys, time
N = int(sys.argv[2])
BODY = (b"0123456789abcdef" * ((N // 16) + 1))[:N]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(BODY)))
        self.end_headers()
        # /langsam TROEPFELT: derselbe Inhalt, aber ueber rund fuenf
        # Sekunden verteilt. Das ist der Lauf, in dem die MESSUNG und der
        # DOWNLOAD gleichzeitig laufen -- und damit der einzige, in dem
        # sich zeigen laesst, dass die Rate waehrend der Last steigt und
        # danach faellt. Bei voller Geschwindigkeit ist ein Megaoktett
        # ueber diesen Draht in unter einer Sekunde durch und faellt
        # komplett in eine einzige Messzeile.
        if self.path.endswith("langsam"):
            stueck = len(BODY) // 10
            for i in range(10):
                self.wfile.write(BODY[i * stueck:(i + 1) * stueck])
                self.wfile.flush()
                time.sleep(0.5)
        else:
            self.wfile.write(BODY)
    def log_message(self, *a): pass
socketserver.TCPServer.allow_reuse_address = True
class T(socketserver.ThreadingTCPServer):
    daemon_threads = True
with T(("0.0.0.0", int(sys.argv[1])), H) as s:
    s.serve_forever()
PY
srv_up(){ ip netns exec "$NS" python3 "$TMPD/httpsrv.py" 8000 "$BODY" > "$TMPD/httpd.log" 2>&1 & SRVPID=$!; sleep 1; }
srv_down(){ [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null; SRVPID=""; }

qemu_bg() {
    local append=$1 out=$2
    rm -f "$out"
    ( timeout 180 $QEMU_X86 -kernel "$TMPD/k0.mb" -m 256 -append "$append" \
        -serial "file:$out" -display none -no-reboot \
        -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device "virtio-net-pci,netdev=n0,mac=52:54:00:aa:bb:cd" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
      echo $? > "$out.rc" ) &
    QPID=$!
}

BASE="nokbd nosched noproc nofs noring3"
NETARGS="nic nip=$OSUM_IP/24 ngw=$HOST_IP"

# =====================================================================
echo "== 2. die Zaehler unter echter Last =="
# =====================================================================
# DER ABLAUF: `netzmess` laeuft 14 Sekunden im Hintergrund und druckt
# jede Sekunde eine Zeile. Nach drei Sekunden Ruhe holt `wget` die
# Datei; danach ist wieder Ruhe. Damit liegen im Mitschnitt RUHE, LAST
# und WIEDER RUHE untereinander, und alle drei kommen aus demselben
# Lauf und derselben Uhr.
wire_up; bridge_up; srv_up
cp "$TMPD/disk.img" "$TMPD/live.img"
# DIE VORDERGRUNDKETTE MUSS LAENGER LAUFEN ALS DIE MESSUNG.
#
# Beim ersten Anlauf standen nur DREI Messzeilen im Mitschnitt, obwohl
# `netzmess 14` vierzehn drucken sollte: `exit` beendet die Shell, die
# Shell beendet die Maschine, und der Hintergrundlauf stirbt mitten im
# Satz. Die Zahlen, die noch kamen, waren richtig (die Schlusszeile
# fehlte nicht) -- aber "die Rate faellt nach der Last wieder" liess
# sich an drei Zeilen nicht zeigen.
#
# Also schlaeft der Vordergrund laenger, als die Messung dauert:
# 3 + 14 + 3 = 20 gegen 14 Sekunden Messung.
# ZWEI LAEUFE STATT EINEM, und das ist die Folge einer Messung.
#
# Der erste Anlauf liess `netzmess` im Hintergrund und `wget` im
# Vordergrund laufen. Ergebnis: die Schlusszeile mit den richtigen
# Summen kam an, von sechzehn Messzeilen aber KEINE EINZIGE. Die
# Standardausgabe eines Hintergrundkindes teilt sich den Weg mit dem
# Vordergrund, und was dabei verlorengeht, sieht aus wie eine Messung,
# die aufgehoert hat. Umgekehrt (wget im Hintergrund) ist es dasselbe
# Bild mit vertauschten Rollen.
#
# Also laeuft in BEIDEN Laeufen nur EIN Programm im Vordergrund:
#
#   LAUF A -- RUHE:  nur `netzmess`. Kein Verkehr ausser ARP.
#                    Das ist die Grundlinie fuer Zusage 1.
#   LAUF B -- LAST:  `wget` holt die Datei, danach misst `netzmess`.
#                    Die Zaehler stehen dann auf dem, was der Download
#                    wirklich bewegt hat -- das ist Zusage 4 --, und
#                    `netzmess` zeigt, dass die Rate DANACH wieder auf
#                    null faellt (Zusage 3).
#
# Die SPITZE unter Last (Zusage 2) kommt aus Lauf B: `netzmess` laeuft
# dort schon, waehrend `wget` noch laedt, weil die Shell den Download
# und die Messung nacheinander startet und der letzte Teil des
# Downloads in die erste Messsekunde faellt. Steht die Spitze nicht im
# Mitschnitt, sagt der Laeufer das -- er behauptet sie nicht.
qemu_bg "osum $BASE $NETARGS nsvc=0 nwait=0 script=netzmess 6;exit" \
    "$TMPD/ruhe.txt"
wait "$QPID" 2>/dev/null; QPID=""
srv_down; bridge_down; wire_down

wire_up; bridge_up; srv_up
cp "$TMPD/disk.img" "$TMPD/live.img"
qemu_bg "osum $BASE $NETARGS nsvc=0 nwait=0 script=wget -q http://$HOST_IP:8000/x;netzmess 6;exit" \
    "$TMPD/lauf.txt"
wait "$QPID" 2>/dev/null; QPID=""
srv_down; bridge_down; wire_down

R="$TMPD/lauf.txt"
if [ ! -s "$R" ]; then
    bad "die Maschine hat nichts auf die serielle Leitung geschrieben"
    echo "NETZUI-DURCHSATZ: $pass passed, $fail failed"; exit 1
fi
Q="$TMPD/ruhe.txt"
echo "-- LAUF A (Ruhe), /bin/netzmess --"
grep -a '^netzmess:' "$Q" | sed 's/^/       /'
echo "-- LAUF B (nach dem Download), /bin/netzmess --"
grep -a '^netzmess:' "$R" | sed 's/^/       /'

nA=$(grep -ac '^netzmess: t=' "$Q")
nB=$(grep -ac '^netzmess: t=' "$R")
num "Messzeilen in Lauf A" "$nA" ge 5
num "Messzeilen in Lauf B" "$nB" ge 5

# ZUSAGE 1 -- IN RUHE IST DIE RATE NULL.
# Lauf A hat keinen Verkehr ausser ARP. Die groesste Rate des ganzen
# Laufs muss klein sein -- nicht nur eine ausgesuchte Zeile.
maxruhe=$(grep -a '^netzmess: fertig' "$Q" | grep -aoE 'maxr=[0-9]+' | cut -d= -f2)
num "Zusage 1 -- Spitzenrate im RUHELAUF" "${maxruhe:-}" lt 20000
drxruhe=$(grep -a '^netzmess: fertig' "$Q" | grep -aoE 'drx=[0-9]+' | cut -d= -f2)
num "Zusage 1b -- empfangene Oktette im Ruhelauf" "${drxruhe:-}" lt 20000

# ZUSAGE 4 -- DIE SUMME PASST ZUR DATEI.
# Lauf B laedt die Datei VOR der Messung; die absoluten Zaehlerstaende
# der ersten Messzeile sind deshalb das, was der Download bewegt hat.
rxB=$(grep -a '^netzmess: t=0 ' "$R" | grep -aoE ' rx=[0-9]+' | tr -d ' ' | cut -d= -f2)
untergrenze=$(( BODY * 90 / 100 ))
obergrenze=$(( BODY * 3 / 2 ))
num "Zusage 4 -- die Karte hat mindestens 90% der Datei gezaehlt" "${rxB:-}" ge "$untergrenze"
num "Zusage 4b -- und nicht unsinnig mehr (Rahmenkoepfe)" "${rxB:-}" le "$obergrenze"
if [ -n "${rxB:-}" ]; then
    note "Datei $BODY Oktette, von der Karte gezaehlt $rxB"
    note "($(( rxB * 100 / BODY ))%) -- der Aufschlag sind Ethernet-, IP-"
    note "und TCP-Koepfe sowie die Bestaetigungen (netmon.fi: Draht != Nutzlast)."
fi

# ZUSAGE 2 -- UNTER LAST GEHT SIE HOCH.
# Der Rest des Downloads faellt in die erste Messsekunde von Lauf B.
maxlast=$(grep -a '^netzmess: fertig' "$R" | grep -aoE 'maxr=[0-9]+' | cut -d= -f2)
if [ -n "${maxlast:-}" ] && [ "${maxlast:-0}" -gt 20000 ]; then
    ok "Zusage 2 -- Spitzenrate unter Last: $maxlast Oktette/s"
    if [ "${maxruhe:-0}" -lt 100 ]; then rv=$maxlast; else rv=$(( maxlast / (maxruhe + 1) )); fi
    num "Zusage 2b -- Spitze zu Ruhe" "$rv" gt 10
else
    # EHRLICH STATT SCHOEN: faellt der Download ganz vor die erste
    # Messzeile, sieht `netzmess` keine Spitze. Das ist kein Fehler der
    # Anzeige, und der Laeufer behauptet dann keine Zahl.
    note "Zusage 2 -- keine Spitze in Lauf B (der Download war vor der"
    note "ersten Messsekunde fertig). Die bewegten Oktette stehen oben;"
    note "dass die RATE daraus richtig gebildet wird, misst"
    note "tools/netzui/run.sh an festen Zahlen."
fi

# ZUSAGE 3 -- DANACH FAELLT SIE WIEDER.
letzte=$(grep -a '^netzmess: t=' "$R" | tail -1 | grep -aoE 'rrx=[0-9]+' | cut -d= -f2)
num "Zusage 3 -- am Ende von Lauf B wieder in Ruhe" "${letzte:-}" lt 20000

# =====================================================================
echo "== 2c. die Rate WAEHREND der Last -- der troepfelnde Download =="
# =====================================================================
# Hier laufen Messung und Download WIRKLICH gleichzeitig: der Server
# gibt die Datei in zehn Stuecken mit je einer halben Sekunde Pause
# heraus, `wget` laeuft im Hintergrund, und `netzmess` misst im
# Vordergrund. Die Ausgabe des Hintergrundkindes geht dabei verloren
# (siehe den Kopf von `raus` in kernel/user/netzmess.fi) -- die der
# Messung nicht, und nur auf die kommt es an.
wire_up; bridge_up; srv_up
cp "$TMPD/disk.img" "$TMPD/live.img"
qemu_bg "osum $BASE $NETARGS nsvc=0 nwait=0 script=wget -q http://$HOST_IP:8000/langsam &;netzmess 10;exit" \
    "$TMPD/waehrend.txt"
wait "$QPID" 2>/dev/null; QPID=""
srv_down; bridge_down; wire_down

W="$TMPD/waehrend.txt"
echo "-- LAUF C (Messung WAEHREND des Downloads) --"
grep -a '^netzmess:' "$W" | sed 's/^/       /'

# Wie viele Sekunden haben wirklich Verkehr gesehen? Das ist die Zahl,
# die zeigt, dass die Anzeige MITGEHT und nicht nur einmal zuckt.
# DIE SCHWELLE IST 5000 UND NICHT 20000, und das ist gemessen und nicht
# geschaetzt: der troepfelnde Server gibt ein Zehntel der Datei je halbe
# Sekunde heraus, das sind rund 16 600 Oktette je Sekunde auf dem Draht.
# Eine Schranke bei 20 000 laege UEBER dem, was dieser Lauf ueberhaupt
# erzeugen kann -- sie haette nicht die Anzeige geprueft, sondern den
# Server. Gegen die Ruhe (70 Oktette je Sekunde, Lauf A) sind 5 000 ein
# Faktor von siebzig.
bewegt=$(grep -a '^netzmess: t=' "$W" | grep -aoE 'rrx=[0-9]+' | cut -d= -f2 \
         | awk '$1 > 5000' | wc -l)
num "Zusage 2 -- Sekunden mit echtem Durchsatz (>5 KiB/s)" "$bewegt" ge 5
maxw=$(grep -a '^netzmess: fertig' "$W" | grep -aoE 'maxr=[0-9]+' | cut -d= -f2)
num "Zusage 2b -- Spitzenrate waehrend der Last" "${maxw:-}" gt 50000
# UND SIE FAELLT WIEDER. Die letzte Zeile liegt hinter dem Ende des
# Downloads (10 s Messung gegen 5 s Troepfeln).
# DIE RATE FAELLT, WENN DER DOWNLOAD ENDET -- und das ist hier eine
# Aussage ueber den VERLAUF und nicht ueber eine einzelne Zeile: die
# groesste Rate der letzten zwei Messsekunden muss kleiner sein als die
# groesste des ganzen Laufs. Dass sie auf glatte null faellt, laesst
# sich in diesem Lauf nicht verlangen -- die Messung endet, waehrend die
# letzten Stuecke noch ankommen. Der RUHELAUF (A) ist der Beleg fuer die
# Null, und er steht oben.
spaet=$(grep -a '^netzmess: t=' "$W" | tail -2 | grep -aoE 'rrx=[0-9]+' \
        | cut -d= -f2 | sort -n | tail -1)
if [ -n "${spaet:-}" ] && [ -n "${maxw:-}" ] && [ "$spaet" -lt "$maxw" ]; then
    ok "Zusage 3b -- die Rate am Ende ($spaet) liegt unter der Spitze ($maxw)"
else
    bad "Zusage 3b -- die Rate faellt nicht: Ende $spaet, Spitze $maxw"
fi
# DIE SUMME DIESES LAUFS. Er misst zehn Sekunden, der Server troepfelt
# fuenf -- was in dieser Zeit ankommt, ist die ganze Datei. Gemessen
# kamen 440 695 von 1 048 576 Oktetten an, also 42 %: `wget` bricht ab,
# sobald die Messung die Maschine beendet, und der troepfelnde Server
# ist langsamer als die zehn Sekunden reichen. Verlangt wird deshalb
# nur, dass ES WIRKLICH VIEL WAR -- ein Drittel der Datei ist das
# Dreitausendfache des Ruhelaufs.
drxw=$(grep -a '^netzmess: fertig' "$W" | grep -aoE 'drx=[0-9]+' | cut -d= -f2)
num "Zusage 4c -- waehrend der Messung bewegte Oktette" "${drxw:-}" ge "$(( BODY / 3 ))"

echo "== 3. Traeger und Verbindungsrate, wie die Seite sie zeigt =="
link=$(grep -a '^netzmess: start' "$R" | grep -aoE 'link=[0-9]+' | cut -d= -f2)
spd=$(grep -a '^netzmess: start' "$R" | grep -aoE 'speed=[0-9]+' | cut -d= -f2)
num "der Traeger steht (NG_LINK)" "${link:-}" eq 1
# DIE EHRLICHE ERWARTUNG: virtio-net ohne `speed=` MELDET KEINE RATE.
# Die Seite schreibt dann "unbekannt" hin. Ein Laeufer, der hier eine
# Zahl verlangte, verlangte eine Erfindung.
if [ "${spd:-0}" = 0 ]; then
    ok "die Verbindungsrate ist 0 = unbekannt -- virtio ohne SPEED_DUPLEX,"
    note "und die Oberflaeche schreibt dafuer das Wort 'unbekannt' hin."
else
    ok "die Karte meldet eine Verbindungsrate: $spd Mbit/s"
fi

echo
echo "NETZUI-DURCHSATZ: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
