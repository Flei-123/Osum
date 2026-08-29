#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/feedback/run.sh -- RUNDE FEEDBACK: eine Meldung aus dem
# laufenden System, mit Bild.
#
# WAS HIER GEMESSEN WIRD, in der Reihenfolge, in der es schiefgehen kann:
#
#   1. DIE KARTE UND DIE NUMMERN. Eine neue Seite in `kdata` und eine
#      neue Aufrufnummer sind die zwei Stellen, an denen dieses Projekt
#      viermal denselben Fehler gemacht hat.
#   2. DAS BILD IST ECHT. Nicht "die Datei ist da" und nicht "PIL sagt
#      PNG", sondern: das PNG, das INNEN entstanden ist, wird auf dem
#      WIRT geoeffnet und Bildpunkt fuer Bildpunkt gegen QEMUs eigenen
#      `screendump` gehalten. 480 000 Bildpunkte, null Unterschiede --
#      alles andere waere ein Bild, das etwas anderes zeigt als der
#      Bildschirm.
#   3. DAS SCHLOSS IST ZU. `SH_GRAB` ohne Schein, `SH_KEY` ohne
#      Tastendruck, `SH_DROP` ohne eigenen Schein: alle drei muessen
#      abgelehnt werden. Ein Schutz, dessen Umgehung nicht gemessen
#      wird, ist eine Behauptung.
#   4. EINE MELDUNG OHNE BILD GEHT HINAUS -- ueber TLS 1.3 aus Ring 3,
#      an einen Server, den dieses Repo nicht geschrieben hat.
#   5. EINE MELDUNG MIT BILD GEHT HINAUS, und was ankommt, ist wieder
#      ein gueltiges PNG in der richtigen Groesse.
#   6. OHNE NETZ GEHT NICHTS VERLOREN. Der erste Lauf hat kein Netz und
#      legt die Meldung in die Warteschlange, der zweite hat Netz und
#      schickt SIE -- dieselbe, mit demselben Text.
#   7. DER ALTE VERTRAG. Die Felder, die FleiLauncher und FreeViewer
#      seit dem 10.07.2026 senden, sind alle da und heissen alle gleich.
#
# DIE LEITUNG ist die aus Runde K8/HWNET: QEMUs UDP-Rueckseite, die
# Bruecke aus `tools/net/bridge.c`, ein veth-Paar und ein eigener
# Netzraum. `/dev/net/tun` gibt es in dem Behaelter nicht, in dem dieses
# Repo gemessen wird.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}

NS=fb-$$
V0=fb0-$$
V1=fb1
OSUM_IP=10.9.0.2
HOST_IP=10.9.0.1
HOSTNAME_TLS=osum.test
QPORT=$(( 13000 + ($$ % 400) * 2 ))
BPORT=$(( QPORT + 1 ))
SRVPORT=8443

TMPD=$(mktemp -d)
BRPID=""; SRVPID=""
cleanup() {
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    if [ -n "${FBKEEP:-}" ]; then echo "TMPD behalten: $TMPD"; else rm -rf "$TMPD"; fi
}
trap cleanup EXIT

pass=0; fail=0; skip=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
sk()  { skip=$((skip+1)); printf '  --    %s\n' "$1"; }
num() { local name=$1 value=$2 op=$3 want=$4
    if [ -z "${value:-}" ]; then bad "$name: keine Zahl gefunden (erwartet $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, erwartet $op $want"; fi; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }

echo "== RUNDE FEEDBACK =="

command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo "FEEDBACK: uebersprungen, kein qemu-system-x86_64"; exit 0; }
python3 -c 'import PIL' 2>/dev/null || {
    echo "FEEDBACK: uebersprungen, python3-pil fehlt"; exit 0; }
python3 -c 'import cryptography' 2>/dev/null || {
    echo "FEEDBACK: uebersprungen, python3-cryptography fehlt"; exit 0; }
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || {
    echo "FEEDBACK: uebersprungen, kein firnc"; exit 0; }

ACCEL=()
[ -w /dev/kvm ] && ACCEL=(-accel kvm -cpu host)

# =====================================================================
echo "== 1. die Karte, die Nummern und wo der Code liegt =="
# =====================================================================
kart=$(python3 tools/kernel/memmap.py kernel 2>&1 | tail -1)
case "$kart" in *"0 Kollisionen"*) ok "kdata ohne Kollision -- $kart" ;;
                *) bad "kdata kollidiert: $kart" ;; esac
grep -q 'const SHOT_OFF: u64 = 0x7B000' kernel/kstate.fi \
    && ok "die Seite des Bildschirmfotos steht in kstate.fi (0x7B000)" \
    || bad "SHOT_OFF fehlt in kstate.fi"
grep -qa 'const SYS_OSUM_SHOT: u64 = 1840' kernel/sys.fi \
    && ok "die Aufrufnummer 1840 steht in kernel/sys.fi" \
    || bad "SYS_OSUM_SHOT fehlt"
grep -qa 'const WM_MAXNR: u64 = 2114' kernel/sys.fi \
    && ok "der Fensterserver hat KEINE neue Nummer bekommen (WM_MAXNR bleibt 2114)" \
    || bad "WM_MAXNR hat sich geaendert -- diese Runde fasst den Fensterserver nicht an"
for f in kernel/shot.fi kernel/app/png.fi kernel/app/shot.fi kernel/user/feedback.fi kernel/sse.fi; do
    [ -f "$f" ] && ok "$f liegt da" || bad "$f fehlt"
done
# DER PACKER IST NICHT NEU GESCHRIEBEN. Der Auftrag verlangt, erst
# nachzusehen; hier steht, dass wirklich der vorhandene benutzt wird.
grep -q 'import std.deflate' kernel/app/png.fi \
    && ok "der PNG-Schreiber benutzt vendor/firn/lib/std/deflate.fi und keinen eigenen Packer" \
    || bad "kernel/app/png.fi packt selbst"
grep -q 'zlib_compress' kernel/app/png.fi \
    && ok "und zwar ueber zlib_compress (RFC 1950), nicht ueber 'stored'-Bloecke" \
    || bad "kein zlib_compress in png.fi"

echo "== 1b. bauen =="
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/k.log" 2>&1 \
    && ok "der Kern baut ($(stat -c%s "$TMPD/k.mb") Oktette)" \
    || { bad "der Kern baut nicht"; tail -12 "$TMPD/k.log" | sed 's/^/        /';
         echo "FEEDBACK: $pass gruen, $fail rot"; exit 1; }
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s"
PROGS="sh ls cat echo sleep feedback"
rc=0
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/$p.err" 2>&1 || {
        bad "$p.fi uebersetzt nicht"; head -8 "$TMPD/$p.err" | sed 's/^/        /'; rc=1; continue; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
        -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null || { bad "ld $p"; rc=1; continue; }
    strip --strip-all "$TMPD/$p.elf"
done
[ $rc = 0 ] && ok "die Programme mit 'profile kernel' bauen (feedback: $(stat -c%s "$TMPD/feedback.elf" 2>/dev/null) Oktette)"
for a in shot fetch; do
    FIRNLIB="$ROOT/vendor/firn/lib" "$FIRNC" -c --profile=app -o "$TMPD/$a.o" \
        "kernel/app/$a.fi" > "$TMPD/$a.err" 2>&1 || {
        bad "kernel/app/$a.fi uebersetzt nicht"; head -8 "$TMPD/$a.err" | sed 's/^/        /'; rc=1; continue; }
    u=$(nm -u "$TMPD/$a.o" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
    [ -z "$u" ] && ok "$a.o hat keinen offenen Namen -- es braucht weder crt.s noch libc" \
                || bad "$a.o: offene Namen: $u"
    ld -T kernel/user/user.ld -o "$TMPD/$a.elf" "$TMPD/$a.o" 2>/dev/null && strip --strip-all "$TMPD/$a.elf" \
        || { bad "ld $a"; rc=1; }
done
[ -f "$TMPD/shot.elf" ] && ok "/bin/shot: $(stat -c%s "$TMPD/shot.elf") Oktette (mit DEFLATE und dem PNG-Kopf)"
[ -f "$TMPD/fetch.elf" ] && ok "/bin/fetch: $(stat -c%s "$TMPD/fetch.elf") Oktette (TLS 1.3, X.509, jetzt auch POST)"
# DER KERN TRAEGT DEN PACKER NICHT.
if nm -a "$TMPD/k.mb.elf" 2>/dev/null | grep -q 'png__write_png_rgb'; then
    bad "der Kern traegt den PNG-Schreiber -- der gehoert in Ring 3"
else
    ok "der Kern traegt den PNG-Schreiber NICHT (er liegt in Ring 3)"
fi

python3 tools/hwnet/mkcerts.py "$TMPD/certs" "$HOSTNAME_TLS" > "$TMPD/certs.txt" 2>&1 \
    && ok "die Zertifikate kommen aus pythons cryptography und nicht aus diesem Repo" \
    || bad "mkcerts.py"
gcc -O2 -o "$TMPD/bridge" tools/net/bridge.c 2>/dev/null || bad "bridge.c baut nicht"

conf() { # <host>
    printf 'host=%s\nname=%s\npath=/feedback.php\nprojekt=Osum\n' "$1" "$HOSTNAME_TLS"
}
mk_image() { # <image> <conf>
    python3 tools/osum/mkfs.py build "$1" 16384 /bin/ /etc/ /etc/ssl/ /var/ /w/ \
        "/bin/sh=$TMPD/sh.elf" "/bin/ls=$TMPD/ls.elf" "/bin/cat=$TMPD/cat.elf" \
        "/bin/echo=$TMPD/echo.elf" "/bin/sleep=$TMPD/sleep.elf" \
        "/bin/shot=$TMPD/shot.elf" "/bin/fetch=$TMPD/fetch.elf" \
        "/bin/feedback=$TMPD/feedback.elf" \
        "/etc/feedback.conf=$2" "/etc/ssl/roots.pem=$TMPD/certs/ca.pem" \
        > "$TMPD/mkfs.txt" 2>&1
}
conf "$HOST_IP:$SRVPORT" > "$TMPD/feedback.conf"
mk_image "$TMPD/disk.img" "$TMPD/feedback.conf" \
    && ok "das Plattenabbild steht ($(stat -c%s "$TMPD/disk.img") Oktette)" \
    || { bad "mkfs"; tail -4 "$TMPD/mkfs.txt" | sed 's/^/        /'; }

# =====================================================================
echo "== 2. das Bildschirmfoto: dasselbe Bild von innen und von aussen =="
# =====================================================================
SOCK="$TMPD/mon.sock"; rm -f "$SOCK"
cp "$TMPD/disk.img" "$TMPD/bild.img"
timeout 240 qemu-system-x86_64 "${ACCEL[@]}" -kernel "$TMPD/k.mb" -m 512 \
    -append "osum gfx nocursor nokbd nosched noproc nofs script=sleep 4;shot -n -t /w/klein.raw /w/a.png;sleep 20;ls -l /w;exit" \
    -serial "file:$TMPD/bild.txt" -display none -no-reboot -vga std \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$TMPD/bild.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/bild.qemu" 2>&1 &
QP=$!
# DER AUGENBLICK. Der Kern sagt den SCHEIN an (`shot: pid=`), und ZWISCHEN
# dieser Zeile und dem Ende des Lesens gibt niemand etwas aus -- der
# Bildschirm steht also still. Genau dort wird von aussen fotografiert.
for i in $(seq 1 3000); do
    grep -qa 'shot: pid=' "$TMPD/bild.txt" 2>/dev/null && break
    kill -0 $QP 2>/dev/null || break
    sleep 0.02
done
python3 tools/gfx/screenshot.py "$SOCK" "$TMPD/host.ppm" 25 > "$TMPD/dump.log" 2>&1
wait $QP
[ -s "$TMPD/host.ppm" ] && ok "der Wirt hat sein eigenes Bild ueber den QEMU-Monitor geholt" \
    || bad "screendump misslungen"
has "$TMPD/bild.txt" "shot: pid=" "der Kern hat den Schein angesagt (er geht nicht unbemerkt)"
python3 tools/osum/mkfs.py cat "$TMPD/bild.img" /w/a.png > "$TMPD/a.png" 2>/dev/null
python3 tools/osum/mkfs.py cat "$TMPD/bild.img" /w/klein.raw > "$TMPD/klein.raw" 2>/dev/null
PNGSZ=$(stat -c%s "$TMPD/a.png" 2>/dev/null || echo 0)
num "das PNG auf der Platte, in Oktetten" "$PNGSZ" gt 2000
python3 - "$TMPD/a.png" "$TMPD/host.ppm" "$TMPD/klein.raw" > "$TMPD/vergleich.txt" 2>&1 <<'PY'
import sys
from PIL import Image
a = Image.open(sys.argv[1]); fmt = a.format
a = a.convert("RGB"); b = Image.open(sys.argv[2]).convert("RGB")
print("format", fmt)
print("innen", a.size[0], a.size[1])
print("aussen", b.size[0], b.size[1])
if a.size != b.size:
    print("diff -1"); sys.exit(0)
pa, pb = a.load(), b.load(); w, h = a.size
d = sum(1 for y in range(h) for x in range(w) if pa[x, y] != pb[x, y])
print("pixel", w * h)
print("diff", d)
# das Vorschaubild: derselbe Ausschnitt, nur kleiner
raw = open(sys.argv[3], "rb").read()
if len(raw) > 8 and raw[:4] == b"OTH1":
    tw = raw[4] | (raw[5] << 8); th = raw[6] | (raw[7] << 8)
    print("thumb", tw, th, len(raw))
    sc = w // tw
    schlecht = 0
    for ty in range(0, th, 7):
        for tx in range(0, tw, 7):
            o = 8 + (ty * tw + tx) * 3
            if (raw[o], raw[o + 1], raw[o + 2]) != pa[tx * sc, ty * sc]:
                schlecht += 1
    print("thumbbad", schlecht)
else:
    print("thumb 0 0 0"); print("thumbbad -1")
PY
sed 's/^/        /' "$TMPD/vergleich.txt"
FMT=$(awk '/^format/{print $2}' "$TMPD/vergleich.txt")
[ "$FMT" = PNG ] && ok "ein echter PNG-Leser auf dem Wirt (Pillow) oeffnet die Datei als PNG" \
                 || bad "Pillow haelt die Datei nicht fuer ein PNG"
IW=$(awk '/^innen/{print $2}' "$TMPD/vergleich.txt")
IH=$(awk '/^innen/{print $3}' "$TMPD/vergleich.txt")
num "die Breite im PNG" "$IW" eq 800
num "die Hoehe im PNG" "$IH" eq 600
PIX=$(awk '/^pixel/{print $2}' "$TMPD/vergleich.txt")
DIF=$(awk '/^diff/{print $2}' "$TMPD/vergleich.txt")
num "Bildpunkte verglichen" "$PIX" eq 480000
if [ "${DIF:-1}" = 0 ]; then
    ok "NULL Unterschiede zum screendump des Wirtes -- das Bild von innen IST der Bildschirm"
else
    bad "$DIF Bildpunkte weichen vom screendump ab"
fi
TB=$(awk '/^thumbbad/{print $2}' "$TMPD/vergleich.txt")
TW1=$(awk '/^thumb /{print $2}' "$TMPD/vergleich.txt")
TH1=$(awk '/^thumb /{print $3}' "$TMPD/vergleich.txt")
num "das Vorschaubild ist $TW1 x $TH1 -- abweichende Stichproben" "${TB:-1}" eq 0
# DIE KOMPRIMIERUNG IST ECHT. Roh sind es (800*3+1)*600 = 1 440 600 Oktette.
num "das PNG ist kleiner als der Rohstrom (1440600 Oktette)" "$PNGSZ" lt 1440600
VERH=$(( 1440600 / (PNGSZ > 0 ? PNGSZ : 1) ))
ok "  Verhaeltnis roh:gepackt = ${VERH}:1 -- es ist wirklich komprimiert und nicht 'stored'"

# =====================================================================
echo "== 2b. die 128-Bit-Register (der Fehler, an dem diese Runde haengenblieb) =="
# =====================================================================
# WARUM DAS HIER STEHT. `/bin/fetch` rechnet SHA-256 fuer TLS 1.3. Meldet
# CPUID SHA-NI -- unter `-accel kvm -cpu host` auf einem Zen tut es das --,
# nimmt vendor/firn/lib/std/crypto/accel.fi den Weg ueber xmm0..xmm5. Ohne
# CR4.OSFXSR ist das erste `movdqu` ein UNGUELTIGER BEFEHL, und der Lauf
# endete mit `user fault: vector=6`. Unter TCG faellt das nie auf.
grep -q 'CR4_OSFXSR' kernel/sse.fi \
    && ok "kernel/sse.fi setzt CR4.OSFXSR" || bad "kein OSFXSR in sse.fi"
grep -q 'fxsave' kernel/arch/x86_64/switch.s \
    && ok "der Aufgabenwechsel hebt die xmm-Register auf (fxsave in switch.s)" \
    || bad "switch.s hebt xmm nicht auf -- xmm ohne Aufheben ist schlimmer als kein xmm"
grep -q 'fxrstor' kernel/arch/x86_64/switch.s \
    && ok "und laedt sie zurueck (fxrstor)" || bad "kein fxrstor in switch.s"
grep -q '0x037F' kernel/sched.fi \
    && ok "eine Aufgabe, die noch nie lief, bekommt eine gueltige Anfangsablage (FCW 0x037F)" \
    || bad "frame_build legt keine fxrstor-Ablage an"
SSEL=$(grep -a '^sse: ' "$TMPD/bild.txt" | tail -1)
[ -n "$SSEL" ] && ok "der Kern meldet es: $SSEL" || bad "keine 'sse:'-Zeile im Lauf"
case "$SSEL" in *"sse=1"*) ok "  SSE ist auf dieser Maschine WIRKLICH an (CR4 zurueckgelesen)" ;;
                *) sk "  diese Maschine hat kein FXSR -- SSE bleibt aus, der skalare Weg gilt" ;; esac
case "$SSEL" in *"cr4=0x"*) V=${SSEL##*cr4=}; V=${V%%  *}
    ok "  und zwar im Register: $V" ;; esac

# =====================================================================
echo "== 3. das Schloss: ohne Schein kommt nichts heraus =="
# =====================================================================
cp "$TMPD/disk.img" "$TMPD/probe.img"
timeout 120 qemu-system-x86_64 "${ACCEL[@]}" -kernel "$TMPD/k.mb" -m 512 \
    -append "osum gfx nokbd nosched noproc nofs script=shot -x /w/nichts.png;echo rc=\$?;exit" \
    -serial "file:$TMPD/probe.txt" -display none -no-reboot -vga std \
    -drive "file=$TMPD/probe.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
has "$TMPD/probe.txt" "shot: probe abgelehnt" "SH_GRAB, SH_KEY und SH_DROP ohne Schein werden ALLE DREI abgelehnt"
hasnot "$TMPD/probe.txt" "DURCHGEKOMMEN" "keiner der drei Wege kommt durch"
G=$(grep -a 'shot: probe grab' "$TMPD/probe.txt" | tail -1 | awk '{print $4}')
K=$(grep -a 'shot: probe key' "$TMPD/probe.txt" | tail -1 | awk '{print $4}')
num "SH_GRAB ohne Schein antwortet -EPERM (1)" "$G" eq 1
num "SH_KEY ohne Tastendruck antwortet -EPERM (1)" "$K" eq 1
D=$(grep -a 'shot: probe denied' "$TMPD/probe.txt" | tail -1 | awk '{print $4}')
num "und jeder Versuch wurde GEZAEHLT (denied)" "$D" ge 3

# =====================================================================
echo "== 4/5/6. die Meldung geht hinaus -- ohne Bild, mit Bild, ohne Netz =="
# =====================================================================
wire_up() {
    ip netns del "$NS" 2>/dev/null; ip link del "$V0" 2>/dev/null
    ip netns add "$NS" 2>/dev/null || return 1
    ip link add "$V0" type veth peer name "$V1" || return 1
    ip link set "$V1" netns "$NS"
    ip netns exec "$NS" ip addr add "$HOST_IP/24" dev "$V1"
    ip netns exec "$NS" ip link set "$V1" up
    ip netns exec "$NS" ip link set lo up
    ip link set "$V0" up
    ethtool -K "$V0" tx off rx off tso off gso off gro off >/dev/null 2>&1
    ip netns exec "$NS" ethtool -K "$V1" tx off rx off tso off gso off gro off >/dev/null 2>&1
    "$TMPD/bridge" "$V0" "$BPORT" "$QPORT" 2>"$TMPD/br.log" & BRPID=$!
    ip netns exec "$NS" python3 tools/feedback/server.py \
        "$TMPD/certs/good.pem" "$TMPD/certs/good.key" "$SRVPORT" "$TMPD/eingang" \
        > "$TMPD/srv.log" 2>&1 & SRVPID=$!
    sleep 1.2
    return 0
}
wire_down() {
    [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null; SRVPID=""
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null; BRPID=""
    ip netns del "$NS" 2>/dev/null; ip link del "$V0" 2>/dev/null
}
lauf() { # <name> <image> <script> <netz 0|1>
    local name=$1 img=$2 skript=$3 netz=$4
    local NET=()
    if [ "$netz" = 1 ]; then
        NET=(-netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT"
             -device "virtio-net-pci,netdev=n0,mac=52:54:00:fe:ed:ba")
    fi
    timeout 240 qemu-system-x86_64 "${ACCEL[@]}" -kernel "$TMPD/k.mb" -m 512 \
        -append "osum gfx nocursor nokbd nosched noproc nofs nic nip=$OSUM_IP/24 ngw=$HOST_IP nsvc=0 nwait=0 script=$skript" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot -vga std \
        "${NET[@]}" \
        -drive "file=$img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
}

if ! wire_up; then
    sk "kein Netzraum -- die Abschnitte 4 bis 6 werden uebersprungen"
else
    ok "die Leitung steht: veth, Bruecke und ein HTTPS-Server, den dieses Repo nicht geschrieben hat"

    # ---- 4. ohne Bild
    cp "$TMPD/disk.img" "$TMPD/m1.img"
    lauf m1 "$TMPD/m1.img" "feedback -f 'Abnahme der Runde FEEDBACK: eine Meldung ohne Bild' -k jarvis@fleitec.com -ja;echo rc=\$?;exit" 1
    has "$TMPD/m1.txt" "feedback: gesendet" "die Meldung OHNE Bild ist hinausgegangen"
    has "$TMPD/m1.txt" "feedback: fetch rc 0" "  und /bin/fetch kam mit 0 zurueck (nicht 127 -- siehe MAX_ARGS)"
    hasnot "$TMPD/m1.txt" "warteschlange bleibt liegen" "  auf einem frischen Datentraeger meldet niemand eine Warteschlange"
    if [ -s "$TMPD/eingang/1.json" ]; then
        ok "der Server hat sie: $(python3 -c "import json;d=json.load(open('$TMPD/eingang/1.json'));print(len(d),'Felder')")"
        python3 - "$TMPD/eingang/1.json" > "$TMPD/f1.txt" 2>&1 <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for k in ("project","type","message","contact","version","os","user"):
    print(k, "=", repr(d.get(k)))
print("hasimage", "image" in d)
PY
        sed 's/^/        /' "$TMPD/f1.txt"
        has "$TMPD/f1.txt" "project = 'Osum'" "  project ist 'Osum' -- der Endpunkt gruppiert danach"
        has "$TMPD/f1.txt" "type = 'bug'" "  type ist 'bug' (aus -f)"
        has "$TMPD/f1.txt" "hasimage False" "  und OHNE Bild ist wirklich kein image-Feld dabei"
        grep -qa 'contact.*jarvis@fleitec.com' "$TMPD/f1.txt" && ok "  der Kontakt kam mit" || bad "  der Kontakt fehlt"
        has "$TMPD/eingang/1.head" "POST /feedback.php" "  es war ein POST auf /feedback.php"
        has "$TMPD/eingang/1.head" "Content-Type: application/json" "  mit Content-Type application/json"
    else
        bad "beim Server ist nichts angekommen"; tail -5 "$TMPD/m1.txt" | sed 's/^/        /'
    fi

    # ---- 5. mit Bild
    cp "$TMPD/disk.img" "$TMPD/m2.img"
    lauf m2 "$TMPD/m2.img" "feedback -f 'Abnahme der Runde FEEDBACK: eine Meldung MIT Bild' -b -ja;echo rc=\$?;exit" 1
    has "$TMPD/m2.txt" "feedback: gesendet" "die Meldung MIT Bild ist hinausgegangen"
    if [ -s "$TMPD/eingang/2.png" ]; then
        python3 - "$TMPD/eingang/2.png" > "$TMPD/p2.txt" 2>&1 <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1])
print("format", im.format, "mode", im.mode, "size", im.size[0], im.size[1])
im.load()
print("dekodiert ok")
PY
        sed 's/^/        /' "$TMPD/p2.txt"
        has "$TMPD/p2.txt" "format PNG" "  was ankam, ist ein PNG -- geoeffnet mit Pillow, nicht mit diesem Repo"
        has "$TMPD/p2.txt" "size 800 600" "  und es ist 800 x 600, also der ganze Bildschirm"
        has "$TMPD/p2.txt" "dekodiert ok" "  jede Bildzeile laesst sich auspacken (der Filter stimmt)"
        num "  das Bild beim Server, in Oktetten" "$(stat -c%s "$TMPD/eingang/2.png")" gt 2000
        num "  und es ist kleiner als die 4-MiB-Grenze des Endpunktes" \
            "$(stat -c%s "$TMPD/eingang/2.png")" lt 4194304
    else
        bad "beim Server ist kein Bild angekommen"; tail -6 "$TMPD/m2.txt" | sed 's/^/        /'
    fi

    # ---- 6. ohne Netz: erst warten, dann senden
    wire_down
    cp "$TMPD/disk.img" "$TMPD/m3.img"
    lauf m3 "$TMPD/m3.img" "feedback -w 'Abnahme der Runde FEEDBACK: dieser Wunsch hatte kein Netz' -ja;echo rc=\$?;exit" 0
    has "$TMPD/m3.txt" "feedback: kein netz, die meldung wartet" "ohne Netz wird die Meldung NICHT verworfen"
    python3 tools/osum/mkfs.py cat "$TMPD/m3.img" /var/feedback/warten.json > "$TMPD/warten.json" 2>/dev/null
    if [ -s "$TMPD/warten.json" ]; then
        ok "sie liegt als /var/feedback/warten.json auf der Platte ($(stat -c%s "$TMPD/warten.json") Oktette)"
        grep -qa 'dieser Wunsch hatte kein Netz' "$TMPD/warten.json" \
            && ok "  und der Text darin ist der, den der Mensch geschrieben hat" \
            || bad "  der Text in der Warteschlange stimmt nicht"
    else
        bad "auf der Platte liegt keine Warteschlange"
    fi
    # derselbe Datentraeger, jetzt MIT Netz -- und ohne neue Meldung
    wire_up > /dev/null 2>&1
    lauf m4 "$TMPD/m3.img" "feedback -warten;echo rc=\$?;exit" 1
    has "$TMPD/m4.txt" "feedback: warteschlange gesendet" "der naechste Lauf mit Netz schickt SIE nach"
    LETZT=$(ls -1 "$TMPD/eingang"/*.json 2>/dev/null | sort -V | tail -1)
    if [ -n "$LETZT" ] && grep -qa 'dieser Wunsch hatte kein Netz' "$LETZT"; then
        ok "und beim Server steht genau dieser Wunsch (type=feature)"
        grep -qa '"feature"' "$LETZT" && ok "  -w ist wirklich als 'feature' angekommen" \
                                      || bad "  die Art stimmt nicht"
    else
        bad "die nachgereichte Meldung ist nicht angekommen"
    fi

    # ---- 7. der alte Vertrag
    echo "== 7. der Vertrag, den FleiLauncher und FreeViewer seit dem 10.07.2026 nutzen =="
    python3 - "$TMPD/eingang" > "$TMPD/vertrag.txt" 2>&1 <<'PY'
import glob, json, os, sys
noetig = {"project","type","message","contact","version","os","user"}
alle = sorted(glob.glob(os.path.join(sys.argv[1], "*.json")))
fehlt = set()
for f in alle:
    d = json.load(open(f))
    fehlt |= (noetig - set(d))
    if d.get("type") not in ("bug","feature","other"):
        print("BADTYPE", f, d.get("type"))
print("meldungen", len(alle))
print("fehlend", ",".join(sorted(fehlt)) if fehlt else "keine")
PY
    sed 's/^/        /' "$TMPD/vertrag.txt"
    has "$TMPD/vertrag.txt" "fehlend keine" "jede Meldung traegt alle sieben Felder des alten Vertrags"
    hasnot "$TMPD/vertrag.txt" "BADTYPE" "und 'type' ist immer eines der drei erlaubten Woerter"
    wire_down
fi

# =====================================================================
echo "== 8. der ECHTE Endpunkt (uebersprungen, wenn er nicht erreichbar ist) =="
# =====================================================================
ECHT=${FEEDBACK_HOST:-fleilauncher.fleitec.com}
IP=$(getent ahostsv4 "$ECHT" 2>/dev/null | awk '{print $1; exit}')
if [ -z "$IP" ] || ! curl -s -m 8 -o /dev/null -w '%{http_code}' "https://$ECHT/feedback.php" 2>/dev/null | grep -q 405; then
    sk "$ECHT ist von hier nicht erreichbar -- der Abschnitt entfaellt"
else
    ok "$ECHT antwortet auf GET mit 405 (POST only) -- der Endpunkt lebt, $IP"
    A=$(curl -s -m 15 -X POST -H 'Content-Type: application/json' \
        -d '{"project":"__abnahme__","type":"other","message":"tools/feedback/run.sh, alter Vertrag ohne Bild"}' \
        "https://$ECHT/feedback.php")
    case "$A" in *'"ok":true'*) ok "eine Meldung OHNE Bild wird angenommen wie vorher: $A" ;;
                 *) bad "der alte Vertrag antwortet: $A" ;; esac
fi

# =====================================================================
# DIE BILDER, die diese Runde belegen. Nicht gerendert, sondern die,
# die im Lauf wirklich entstanden sind: das Bildschirmfoto VON INNEN
# und das, was beim Server ankam.
mkdir -p docs/shots/feedback
[ -s "$TMPD/a.png" ] && cp "$TMPD/a.png" docs/shots/feedback/01-von-innen.png
[ -s "$TMPD/host.ppm" ] && python3 -c "
from PIL import Image; import sys
Image.open('$TMPD/host.ppm').save('docs/shots/feedback/02-screendump-des-wirtes.png')" 2>/dev/null
[ -s "$TMPD/eingang/2.png" ] && cp "$TMPD/eingang/2.png" docs/shots/feedback/03-beim-server-angekommen.png
ls docs/shots/feedback/*.png >/dev/null 2>&1 \
    && ok "die Bilder liegen in docs/shots/feedback/ ($(ls docs/shots/feedback/*.png | wc -l) Stueck)" \
    || sk "keine Bilder abgelegt"

echo
echo "FEEDBACK: $pass gruen, $fail rot, $skip uebersprungen"
[ "$fail" = 0 ]
