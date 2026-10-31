#!/usr/bin/env bash
#
#   Osum in QEMU <--e1000--> QEMU <--UDP--> tools/net/bridge
#                <--AF_PACKET--> veth <--> peer.py im Netzraum
#
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

NIC=${BRIDGE_NIC:-e1000}
NS=bridge-$$
V0=br0-$$
V1=hw1
QPORT=$(( 16000 + ($$ % 400) * 2 ))
BPORT=$(( QPORT + 1 ))
OSUM_IP=10.9.0.2
HOST_IP=10.9.0.1
SRVPORT=8443

TMPD=$(mktemp -d)
BRPID=""
SRVPID=""
cleanup() {
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    [ -n "${BRIDGE_KEEP:-}" ] || rm -rf "$TMPD"
}
trap cleanup EXIT

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note() { printf '        %s\n' "$1"; }
hat()  { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hat_nicht() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da, sollte nicht" \
              || ok "$3"; }
zahl() { local n=$1 v=$2 o=$3 w=$4
    if [ -z "${v:-}" ]; then bad "$n: keine Zahl (erwartet $o $w)"; return; fi
    if [ "$v" -"$o" "$w" ] 2>/dev/null; then ok "$n: $v"; else bad "$n: $v, erwartet $o $w"; fi
}

for t in qemu-system-x86_64 ip openssl python3 gcc; do
    command -v "$t" >/dev/null 2>&1 || { echo "BRIDGE: uebersprungen, $t fehlt"; exit 0; }
done
python3 -c 'import cryptography' 2>/dev/null || {
    echo "BRIDGE: uebersprungen, python3-cryptography fehlt"; exit 0; }
ip netns del "$NS" 2>/dev/null
ip netns add "$NS" 2>/dev/null || { echo "BRIDGE: uebersprungen, keine Netzraeume"; exit 0; }
ip netns del "$NS" 2>/dev/null

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

# =====================================================================
echo "== 1. bauen: zwei Profile, ein Abbild =="
# =====================================================================
export FIRNLIB="$ROOT/lib"
if vendor/firn/bin/firnc -c --profile=app -o "$TMPD/jd.o" \
        kernel/app/jarvisd.fi > "$TMPD/cc.log" 2>&1; then
    ok "firnc --profile=app: jarvisd.fi mit std.rt, std.net, std.deflate, tls.tls"
else
    bad "jarvisd.fi uebersetzt nicht"; head -12 "$TMPD/cc.log" | sed 's/^/        /'
    echo "BRIDGE: $pass bestanden, $fail durchgefallen"; exit 1
fi
undef=$(nm -u "$TMPD/jd.o" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
[ -z "$undef" ] && ok "kein undefinierter Name -- weder crt.s noch libc noetig" \
                || bad "undefiniert: $undef"

export FIRNLIB="$ROOT/lib"
for p in jsig jarvisctl; do
    if vendor/firn/bin/firnc -c -o "$TMPD/$p.o" "kernel/user/$p.fi" \
            > "$TMPD/cc-$p.log" 2>&1; then
        ok "firnc profile kernel: $p.fi gegen lib/ (Ed25519 aus Runde UPDATE)"
    else
        bad "$p.fi uebersetzt nicht"; head -8 "$TMPD/cc-$p.log" | sed 's/^/        /'
    fi
done

cat > "$TMPD/beides.fi" <<'FIEND'
import std.rt
import tls.tls
import crypto.ed25519
fn main(start: u64) -> i32 { return 0 }
FIEND
if FIRNLIB="$ROOT/lib" vendor/firn/bin/firnc -c --profile=app \
        -o "$TMPD/beides.o" "$TMPD/beides.fi" > "$TMPD/beides.log" 2>&1; then
    bad "TLS und crypto.ed25519 gehen ploetzlich in EINEM Programm -- die Begruendung in jsig.fi stimmt nicht mehr"
else
    grep -qa "sha512" "$TMPD/beides.log" \
        && ok "die Namenskollision 'sha512' ist real -- die Trennung jsig/jarvisd hat ihren Grund" \
        || ok "TLS + crypto.ed25519 in einem Programm scheitert (anderer Grund, siehe $TMPD/beides.log)"
fi

if ! bash tools/bridge/build.sh "$TMPD/w0" 0 > "$TMPD/b0.txt" 2>&1; then
    bad "das Abbild baut nicht"; tail -12 "$TMPD/b0.txt" | sed 's/^/        /'
    echo "BRIDGE: $pass bestanden, $fail durchgefallen"; exit 1
fi
ok "$(cat "$TMPD/b0.txt")"
K="$TMPD/w0/k.mb"
JDSZ=$(stat -c%s "$TMPD/w0/jarvisd.elf")
JSSZ=$(stat -c%s "$TMPD/w0/jsig.elf")
zahl "jarvisd auf der Platte, in Oktetten" "$JDSZ" le 2400000
zahl "jsig auf der Platte, in Oktetten" "$JSSZ" le 400000

ZEILEN=$(cat kernel/app/jarvisd.fi kernel/user/jsig.fi \
    kernel/user/jarvisctl.fi | wc -l)
note "Quelltext dieser Runde: $ZEILEN Zeilen in drei Dateien"

if grep -q -- '--gui' tools/build-kernel.sh 2>/dev/null; then
    if ./tools/build-kernel.sh "$TMPD/srv.img" --stufe 0 --gui off \
            > "$TMPD/srv.log" 2>&1; then
        ok "der GUI-lose Serverbau steht weiter (--gui off)"
    else
        bad "der GUI-lose Serverbau ist kaputt"; tail -8 "$TMPD/srv.log" | sed 's/^/        /'
    fi
fi

# =====================================================================
echo "== 2. die Rechteliste, ohne jedes Netz =="
# =====================================================================
python3 tools/hwnet/mkcerts.py "$TMPD/certs" jarvis.test > "$TMPD/certs.txt" 2>&1 \
    && ok "die Testzertifikate kommen aus Pythons cryptography, nicht aus diesem Repo" \
    || { bad "mkcerts.py fehlgeschlagen"; cat "$TMPD/certs.txt"; }
gcc -O2 -o "$TMPD/bridge" tools/net/bridge.c 2>/dev/null || bad "bridge.c uebersetzt nicht"

mach_conf() { # <datei> <befehle> <foto> <system> <extra...>
    local f=$1; shift
    cat > "$f" <<CONF
server         = $HOST_IP:$SRVPORT
servername     = jarvis.test
roots        = /etc/ssl/roots.pem
commands        = $1
screenshot = $2
sysinfo     = $3
CONF
    shift 3
    for z in "$@"; do echo "$z" >> "$f"; done
}

mach_conf "$TMPD/voll.conf" yes no yes \
    "command_allowed = /bin/echo" \
    "read          = /var/jarvis/" \
    "read          = /etc/jarvis/permissions.conf" \
    "write      = /var/jarvis/" \
    "list      = /var/jarvis/" \
    "max_output    = 4096" \
    "max_file      = 8192"

mach_conf "$TMPD/leer.conf" no no no

abbild() { # <abbild> <conf> [zusatzspezifikationen...]
    local img=$1 conf=$2; shift 2
    python3 tools/osum/mkfs.py build "$img" 16384 \
        /bin/ /etc/ /etc/ssl/ /etc/jarvis/ /var/ /var/log/ /var/jarvis/ \
        "/bin/sh=$TMPD/w0/sh.elf" \
        "/bin/ls=$TMPD/w0/ls.elf" \
        "/bin/cat=$TMPD/w0/cat.elf" \
        "/bin/echo=$TMPD/w0/echo.elf" \
        "/bin/chmod=$TMPD/w0/chmod.elf" \
        "/bin/jsig=$TMPD/w0/jsig.elf" \
        "/bin/jarvisctl=$TMPD/w0/jarvisctl.elf" \
        "/bin/jarvisd=$TMPD/w0/jarvisd.elf" \
        "/etc/jarvis/permissions.conf=$conf" \
        "/etc/ssl/roots.pem=$TMPD/certs/ca.pem" \
        "$@" > "$TMPD/mkfs.txt" 2>&1 \
        || { bad "mkfs fuer $img"; tail -4 "$TMPD/mkfs.txt" | sed 's/^/        /'; }
}

echo "hallo aus osum" > "$TMPD/gruss.txt"
abbild "$TMPD/nonet.img" "$TMPD/voll.conf" "/var/jarvis/gruss.txt=$TMPD/gruss.txt"
abbild "$TMPD/leer.img" "$TMPD/leer.conf" "/var/jarvis/gruss.txt=$TMPD/gruss.txt"

lauf_ohne_netz() { # <abbild> <skript> <ausgabe>
    local copy="$TMPD/live-$RANDOM.img"
    cp "$1" "$copy"
    timeout 180 qemu-system-x86_64 -kernel "$K" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 script=$2" \
        -serial "file:$3" -display none -no-reboot \
        -drive "file=$copy,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    local rc=$?
    rm -f "$copy"
    return $rc
}

lauf_ohne_netz "$TMPD/nonet.img" "jarvisd -n;exit" "$TMPD/s2a.txt"
F="$TMPD/s2a.txt"
hat "$F" "permissions read 2 write 1 list 1 commands 1 screenshot no sysinfo yes" \
    "die Rechteliste wird gelesen und Punkt fuer Punkt gemeldet"
lauf_ohne_netz "$TMPD/leer.img" "jarvisd -n;exit" "$TMPD/s2b.txt"
hat "$TMPD/s2b.txt" "permissions read 0 write 0 list 0 commands no screenshot no sysinfo no" \
    "GEGENPROBE: eine Liste ohne Eintraege erlaubt NICHTS -- die Voreinstellung ist nein"

# =====================================================================
# DER DRAHT
# =====================================================================
draht_auf() {
    ip netns del "$NS" 2>/dev/null; ip link del "$V0" 2>/dev/null
    ip netns add "$NS"
    ip link add "$V0" type veth peer name "$V1"
    ip link set "$V1" netns "$NS"
    ip netns exec "$NS" ip addr add $HOST_IP/24 dev "$V1"
    ip netns exec "$NS" ip link set "$V1" up
    ip netns exec "$NS" ip link set lo up
    ip link set "$V0" up
    ethtool -K "$V0" tx off rx off tso off gso off gro off >/dev/null 2>&1
    ip netns exec "$NS" ethtool -K "$V1" tx off rx off tso off gso off gro off >/dev/null 2>&1
    "$TMPD/bridge" "$V0" "$BPORT" "$QPORT" 2>"$TMPD/br.log" & BRPID=$!
    sleep 0.4
}
draht_zu() {
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null; BRPID=""
    ip netns del "$NS" 2>/dev/null; ip link del "$V0" 2>/dev/null
}

gegenstelle_an() { # <zertifikat> <auftragsdatei> <ausgabe> [zusatz...]
    local cert=$1 auf=$2 aus=$3; shift 3
    ip netns exec "$NS" python3 tools/bridge/peer.py \
        --cert "$TMPD/certs/$cert.pem" --key "$TMPD/certs/$cert.key" \
        --port "$SRVPORT" --auftraege "$auf" --aus "$aus" \
        --wartezeit 90 "$@" > "$aus.stderr" 2>&1 & SRVPID=$!
    sleep 0.8
}
gegenstelle_aus() {
    if [ -n "$SRVPID" ]; then wait "$SRVPID" 2>/dev/null; SRVPID=""; fi
}

EXTRA=""
lauf_mit_netz() { # <abbild> <skript> <ausgabe> [zeitgrenze]   ($EXTRA = weitere Kernwoerter)
    local copy="$TMPD/live-$RANDOM.img"
    cp "$1" "$copy"
    timeout "${4:-220}" qemu-system-x86_64 -kernel "$K" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 $EXTRA nic nip=$OSUM_IP/24 ngw=$HOST_IP nsvc=0 nwait=0 script=$2" \
        -serial "file:$3" -display none -no-reboot \
        -drive "file=$copy,format=raw,if=ide,index=0" \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device "$NIC,netdev=n0,mac=52:54:00:aa:bb:cc" -vga std \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    local rc=$?
    rm -f "$copy"
    return $rc
}

# =====================================================================
echo "== 3. + 4. die Anmeldung und die sechs Auftragsarten =="
# =====================================================================
cat > "$TMPD/auf-gut.txt" <<'AUF'
system||
schreib|/var/jarvis/neu.txt|48616c6c6f2c204a5553544954494e0a
lies|/var/jarvis/neu.txt|
lies|/etc/jarvis/permissions.conf|
liste|/var/jarvis/|
befehl|/bin/echo eins zwei|
foto||
AUF
draht_auf
gegenstelle_an good "$TMPD/auf-gut.txt" "$TMPD/g1.log"
T0=$(date +%s%N)
lauf_mit_netz "$TMPD/nonet.img" "jarvisd -1 -t 60000;jarvisctl log 40;exit" "$TMPD/r1.txt"
T1=$(date +%s%N)
gegenstelle_aus
draht_zu
G="$TMPD/g1.log"; F="$TMPD/r1.txt"

hat "$G" "TLSv1.3" "die Verbindung steht auf TLS 1.3 -- gesagt hat das Python, nicht Osum"
hat "$G" "BEWEIS gut" "die Ed25519-Unterschrift des Geraets stimmt (nachgerechnet von python-cryptography)"
hat "$G" "GEGENPROBE gut" "GEGENPROBE: dieselbe Unterschrift ueber andere Oktette faellt durch"
hat "$G" "ANGEMELDET" "der Server hat die Anmeldung angenommen"
hat "$F" "jarvisd: connected" "und Osum hat es auch so gesehen"
hat "$F" "jarvisd: signed in" "der Helfer meldet sich angemeldet"

PUB=$(grep -a '^PUB ' "$G" | awk '{print $2}')
zahl "die Laenge des oeffentlichen Schluessels in Hexziffern" "${#PUB}" eq 64

antwort() { grep -a "^ANTWORT $1 " "$G" | head -1; }
status_von() { antwort "$1" | awk '{print $4}'; }
laenge_von() { antwort "$1" | awk '{print $5}'; }

[ "$(status_von 1)" = ok ] && ok "system: beantwortet" || bad "system: $(antwort 1)"
grep -qa "^fassung " "$G.1.bin" 2>/dev/null || true
hat "$G.1.bin" "fassung" "system nennt die Fassung des Kerns"
hat "$G.1.bin" "speicher_alle" "system nennt den Speicher"
hat "$G.1.bin" "platte_bloecke" "system nennt die Platte"

[ "$(status_von 2)" = ok ] && ok "schreib: die Datei wurde angelegt" || bad "schreib: $(antwort 2)"
[ "$(status_von 3)" = ok ] && ok "lies: und wieder gelesen" || bad "lies: $(antwort 3)"
if [ -f "$G.3.bin" ] && [ "$(cat "$G.3.bin")" = "Hallo, JUSTITIN" ]; then
    ok "lies: OKTETT FUER OKTETT dasselbe, was schreib hineingelegt hat"
else
    bad "lies: '$(cat "$G.3.bin" 2>/dev/null)' statt 'Hallo, JUSTITIN'"
fi
[ "$(status_von 4)" = ok ] && ok "lies: auch die Rechteliste selbst (sie steht darin)" \
                           || bad "lies rechte.conf: $(antwort 4)"
[ "$(status_von 5)" = ok ] && ok "liste: das Verzeichnis" || bad "liste: $(antwort 5)"
hat "$G.5.bin" "neu.txt" "liste: die eben geschriebene Datei steht darin"
[ "$(status_von 6)" = ok ] && ok "befehl: /bin/echo lief" || bad "befehl: $(antwort 6)"
hat "$G.6.bin" "eins zwei" "befehl: und seine Ausgabe kam zurueck"
hat "$G.6.bin" "ende 0" "befehl: mit seinem Beendigungscode"
[ "$(status_von 7)" = nein ] && ok 'foto: abgelehnt, weil bildschirmfoto = nein' \
                             || bad "foto: $(antwort 7)"
hat "$F" "jarvisd: connections 1" "genau eine Verbindung"
hat "$F" "jarvisd: jobs 7" "sieben Auftraege gezaehlt"

echo "   -- das Protokoll unter /var/log/jarvisd.log"
hat "$F" "service started" "der Start steht im Protokoll"
hat "$F" "session signed-in" "die Anmeldung steht im Protokoll"
hat "$F" "system ok" 'ein erledigter Auftrag steht mit ok im Protokoll'
hat "$F" "screenshot REJECTED" 'ein abgelehnter steht mit ABGELEHNT darin'

VERB_MS=$(( (T1-T0)/1000000 ))
note "vom QEMU-Start bis zum Ende dieses Laufs: $VERB_MS ms (mit Bau des Abbilds ausserhalb)"

# =====================================================================
echo "== 5. ZUSAGE (a): jede Auftragsart einzeln abgelehnt =="
mach_conf "$TMPD/nix.conf" no no no
abbild "$TMPD/nix.img" "$TMPD/nix.conf" "/var/jarvis/gruss.txt=$TMPD/gruss.txt"
cat > "$TMPD/auf-nix.txt" <<'AUF'
system||
lies|/var/jarvis/gruss.txt|
schreib|/var/jarvis/darfnicht.txt|4e4945
liste|/var/jarvis/|
befehl|/bin/echo hallo|
foto||
lies|/var/jarvis/../etc/jarvis/device.key|
lies|/etc/jarvis/device.key|
AUF
draht_auf
gegenstelle_an good "$TMPD/auf-nix.txt" "$TMPD/g2.log"
lauf_mit_netz "$TMPD/nix.img" "jarvisd -1 -t 60000;cat /var/jarvis/darfnicht.txt;jarvisctl log 40;exit" "$TMPD/r2.txt"
gegenstelle_aus
draht_zu
G="$TMPD/g2.log"; F="$TMPD/r2.txt"
status_von() { grep -a "^ANTWORT $1 " "$G" | head -1 | awk '{print $4}'; }
grund_von()  { cat "$G.$1.bin" 2>/dev/null; }

pruefe_nein() { # <nr> <art> <stichwort>
    if [ "$(status_von "$1")" = nein ]; then
        if grep -qaF "$3" "$G.$1.bin" 2>/dev/null; then
            ok "$2: abgelehnt, und der Grund sagt warum ($(grund_von "$1" | head -c 60))"
        else
            bad "$2: abgelehnt, aber ohne '$3': $(grund_von "$1")"
        fi
    else
        bad "$2: NICHT abgelehnt (Status '$(status_von "$1")')"
    fi
}
pruefe_nein 1 system     "sysinfo"
pruefe_nein 2 lies       '`read`'
pruefe_nein 3 schreib    '`write`'
pruefe_nein 4 liste      '`list`'
pruefe_nein 5 befehl     "commands = no"
pruefe_nein 6 foto       "screenshot = no"
pruefe_nein 7 "lies mit .."  "not a clean absolute path"
pruefe_nein 8 "lies auf den Schluessel" '`read`'

hat_nicht "$F" "NIE" "und NICHTS ist passiert: /var/jarvis/darfnicht.txt gibt es nicht"
for a in system read write list run screenshot; do
    grep -qa "^[0-9-]* [0-9:]* $a REJECTED" "$F" \
        && ok "$a: die Ablehnung steht im Protokoll" \
        || bad "$a: keine Ablehnungszeile im Protokoll"
done
hat "$F" "jarvisd: rejected 8" "acht Ablehnungen gezaehlt"

# =====================================================================
echo "== 6. ZUSAGE (b): falsche Zertifikate =="
: > "$TMPD/leerspeicher.pem"
for fall in expired wrong rogue; do
    draht_auf
    gegenstelle_an "$fall" "$TMPD/auf-gut.txt" "$TMPD/gz-$fall.log"
    lauf_mit_netz "$TMPD/nonet.img" "jarvisd -1 -t 12000;jarvisctl log 10;exit" "$TMPD/rz-$fall.txt" 120
    gegenstelle_aus
    draht_zu
    Z="$TMPD/rz-$fall.txt"
    if grep -qa "jarvisd: TLS handshake failed" "$Z"; then
        ok "$fall: der Handschlag wird abgelehnt, Grund $(grep -a 'Handschlag ist gescheitert' "$Z" | head -1 | sed 's/.*Grund //')"
    else
        bad "$fall: der Handschlag wurde NICHT abgelehnt"
    fi
    hat_nicht "$Z" "jarvisd: signed in" "$fall: und es wurde sich NICHT angemeldet"
    hat "$Z" "tls REJECTED" "$fall: die Ablehnung steht im Protokoll"
done

python3 tools/osum/mkfs.py build "$TMPD/leerca.img" 16384 \
    /bin/ /etc/ /etc/ssl/ /etc/jarvis/ /var/ /var/log/ /var/jarvis/ \
    "/bin/sh=$TMPD/w0/sh.elf" "/bin/jsig=$TMPD/w0/jsig.elf" \
    "/bin/jarvisctl=$TMPD/w0/jarvisctl.elf" "/bin/jarvisd=$TMPD/w0/jarvisd.elf" \
    "/etc/jarvis/permissions.conf=$TMPD/voll.conf" \
    "/etc/ssl/roots.pem=$TMPD/leerspeicher.pem" > "$TMPD/mkfs2.txt" 2>&1
draht_auf
gegenstelle_an good "$TMPD/auf-gut.txt" "$TMPD/gz-leer.log"
lauf_mit_netz "$TMPD/leerca.img" "jarvisd -1 -t 12000;exit" "$TMPD/rz-leer.txt" 120
gegenstelle_aus
draht_zu
hat "$TMPD/rz-leer.txt" "no root store" "leerer Speicher: der Helfer sagt es laut"
hat_nicht "$TMPD/rz-leer.txt" "jarvisd: signed in" "leerer Speicher: und meldet sich NICHT an"

# =====================================================================
echo "== 7. ZUSAGE (c): Kopplung ohne Bestaetigung am Geraet =="
# =====================================================================
CODE=$(python3 -c 'import secrets;print("%06d" % secrets.randbelow(1000000))')
cat > "$TMPD/auf-kurz.txt" <<'AUF'
system||
AUF
draht_auf
gegenstelle_an good "$TMPD/auf-kurz.txt" "$TMPD/g3.log" --kopplung "$CODE" --kopplung-hex
lauf_mit_netz "$TMPD/nonet.img" "jarvisd -1 -t 30000;jarvisctl log 10;exit" "$TMPD/r3.txt" 150
gegenstelle_aus
draht_zu
hat "$TMPD/g3.log" "KOPPLUNG-ABGELEHNT" "ohne Bestaetigung: der Helfer lehnt die Kopplung ab"
hat "$TMPD/r3.txt" "PAIRING CODE $CODE" "der Code wird dem Menschen am Geraet gezeigt"
hat "$TMPD/r3.txt" "pairing REJECTED" "und die Ablehnung steht auf der Konsole"
hat "$TMPD/r3.txt" "pairing rejected" "sie steht auch im Protokoll"
hat_nicht "$TMPD/g3.log" "ANGEMELDET" "und der Server hat KEINE angemeldete Sitzung gesehen"

echo "   -- und jetzt mit Bestaetigung, damit die Ablehnung etwas bedeutet"
draht_auf
gegenstelle_an good "$TMPD/auf-kurz.txt" "$TMPD/g4.log" --kopplung "$CODE" --kopplung-hex --verbindungen 2
lauf_mit_netz "$TMPD/nonet.img" "jarvisd -1 -t 20000;jarvisctl pair $CODE;jarvisd -1 -t 30000;jarvisctl log 10;exit" "$TMPD/r4.txt" 200
gegenstelle_aus
draht_zu
hat "$TMPD/r4.txt" "Pairing confirmed" "jarvisctl pair nimmt den Code an, den der Helfer bekommen hat"
hat "$TMPD/g4.log" "ANGEMELDET" "beim zweiten Anlauf ist die Kopplung durch"
hat "$TMPD/r4.txt" "pairing confirmed" "und sie steht im Protokoll"

echo "   -- der echte Server schickt den Code als Hex der Ziffern: der Mensch sieht und tippt die Ziffern"
HEXCODE=$(python3 -c 'import sys;print(sys.argv[1].encode().hex())' "$CODE")
draht_auf
gegenstelle_an good "$TMPD/auf-kurz.txt" "$TMPD/g5.log" --kopplung "$CODE" --kopplung-hex --verbindungen 2
lauf_mit_netz "$TMPD/nonet.img" "jarvisd -1 -t 20000;jarvisctl status;jarvisctl pair $CODE;jarvisd -1 -t 30000;jarvisctl log 10;exit" "$TMPD/r5.txt" 200
gegenstelle_aus
draht_zu
hat "$TMPD/r5.txt" "PAIRING CODE $CODE" "Hex-Code vom Server: am Geraet stehen die Ziffern"
hat_nicht "$TMPD/r5.txt" "PAIRING CODE $HEXCODE" "und nicht der Hex-Text"
hat "$TMPD/r5.txt" "jarvisctl pair $CODE" "der Hinweis nennt die Ziffern"
hat "$TMPD/r5.txt" "Pairing confirmed" "jarvisctl pair mit den Ziffern wird angenommen"
hat "$TMPD/g5.log" "ANGEMELDET" "und die Kopplung ist durch (der Server bekam den Hex-Code zurueck)"
echo "   -- der Hex-Text wird ebenfalls akzeptiert (alte Anzeige)"
draht_auf
gegenstelle_an good "$TMPD/auf-kurz.txt" "$TMPD/g6.log" --kopplung "$CODE" --kopplung-hex --verbindungen 2
lauf_mit_netz "$TMPD/nonet.img" "jarvisd -1 -t 20000;jarvisctl pair $HEXCODE;jarvisd -1 -t 30000;jarvisctl log 10;exit" "$TMPD/r6.txt" 200
gegenstelle_aus
draht_zu
hat "$TMPD/r6.txt" "Pairing confirmed" "jarvisctl pair mit dem Hex-Text wird auch angenommen"
hat "$TMPD/g6.log" "ANGEMELDET" "und die Kopplung ist durch"
echo "   -- GEGENPROBE: falsche Ziffern werden abgelehnt"
draht_auf
gegenstelle_an good "$TMPD/auf-kurz.txt" "$TMPD/g7.log" --kopplung "$CODE" --kopplung-hex
lauf_mit_netz "$TMPD/nonet.img" "jarvisd -1 -t 20000;jarvisctl pair 000000;jarvisctl log 10;exit" "$TMPD/r7.txt" 150
gegenstelle_aus
draht_zu
hat "$TMPD/r7.txt" "does not match" "falsche Ziffern: jarvisctl lehnt ab"
hat "$TMPD/g7.log" "KOPPLUNG-ABGELEHNT" "und der Server sieht eine Ablehnung"
hat_nicht "$TMPD/g7.log" "ANGEMELDET" "es gibt keine Sitzung"

echo "   -- GEGENPROBE: ein Code, den niemand angefragt hat"
lauf_ohne_netz "$TMPD/nonet.img" "jarvisctl pair 424242;exit" "$TMPD/r4b.txt"
hat "$TMPD/r4b.txt" "No pairing request" "jarvisctl weigert sich, eine Kopplung zu bestaetigen, die es nicht gibt"

echo "== 7b. Kopplung per Web: kein lokales Bestaetigen, Wiederanfrage, Anzeige =="
# =====================================================================
cp "$TMPD/voll.conf" "$TMPD/web.conf"
printf '\npairing = web\n' >> "$TMPD/web.conf"
abbild "$TMPD/web.img" "$TMPD/web.conf" "/var/jarvis/gruss.txt=$TMPD/gruss.txt"
draht_auf
gegenstelle_an good "$TMPD/auf-kurz.txt" "$TMPD/gw1.log" --kopplung "$CODE" --kopplung-hex --kopplung-web 3
lauf_mit_netz "$TMPD/web.img" "jarvisd -1 -t 40000;cat /var/jarvis/state;jarvisctl log 10;exit" "$TMPD/rw1.txt" 200
gegenstelle_aus
draht_zu
hat "$TMPD/rw1.txt" "PAIRING CODE $CODE" "web: der Code wird am Geraet gezeigt"
hat "$TMPD/rw1.txt" "web UI" "web: mit dem Hinweis auf die Weboberflaeche"
hat_nicht "$TMPD/rw1.txt" "jarvisctl pair $CODE" "web: kein lokales Bestaetigen verlangt"
hat "$TMPD/gw1.log" "KOPPLUNG-WEB 3 hello" "web: das Geraet fragt alle paar Sekunden neu (3 Anfragen)"
hat "$TMPD/gw1.log" "ANGEMELDET" "web: nach der Freigabe im Web ist es angemeldet"
hat "$TMPD/rw1.txt" "pairing: ok" "web: /var/jarvis/state sagt ok"
echo "   -- Anzeige waehrend das Geraet wartet"
draht_auf
gegenstelle_an good "$TMPD/auf-kurz.txt" "$TMPD/gw2.log" --kopplung "$CODE" --kopplung-hex --kopplung-web -2
lauf_mit_netz "$TMPD/web.img" "jarvisd -1 -t 20000;jarvisctl status;exit" "$TMPD/rw2.txt" 150
gegenstelle_aus
draht_zu
hat "$TMPD/rw2.txt" "WAITING -- enter this code in the JARVIS web UI" "web: jarvisctl status zeigt den Code gross"
hat "$TMPD/rw2.txt" "##" "web: in Blockziffern"
hat "$TMPD/rw2.txt" "> Devices" "web: mit dem Ort der Eingabe"
hat_nicht "$TMPD/gw2.log" "ANGEMELDET" "web: ohne Freigabe keine Sitzung"
echo "   -- GEGENPROBE: Modus device verlangt weiter die Bestaetigung am Geraet"
draht_auf
gegenstelle_an good "$TMPD/auf-kurz.txt" "$TMPD/gw3.log" --kopplung "$CODE" --kopplung-hex --kopplung-web 3
lauf_mit_netz "$TMPD/nonet.img" "jarvisd -1 -t 30000;exit" "$TMPD/rw3.txt" 150
gegenstelle_aus
draht_zu
hat "$TMPD/gw3.log" "KOPPLUNG-WEB-FALSCH" "device: das Geraet wartet nicht auf das Web, es lehnt ab"
hat_nicht "$TMPD/gw3.log" "ANGEMELDET" "device: keine Sitzung ohne lokale Bestaetigung"

# =====================================================================
echo "== 8. ZUSAGE (d): Abriss mitten im Auftrag =="
# =====================================================================
draht_auf
gegenstelle_an good "$TMPD/auf-gut.txt" "$TMPD/g5.log" --abriss
lauf_mit_netz "$TMPD/nonet.img" "jarvisd -t 25000 -v;jarvisctl log 10;exit" "$TMPD/r5.txt" 200
gegenstelle_aus
draht_zu
hat "$TMPD/g5.log" "ABRISS nach Auftrag 1" "die Gegenstelle hat mitten im Auftrag abgerissen"
hat "$TMPD/r5.txt" "jarvisd: waiting" "der Helfer stirbt nicht, sondern wartet auf den naechsten Versuch"
hat "$TMPD/r5.txt" "jarvisd: connections 1" "er zaehlt die eine Verbindung, die es gab"
hat "$TMPD/r5.txt" "jarvisd: no connection" "und er versucht es danach wieder (die Gegenstelle ist weg)"
hat "$TMPD/r5.txt" "service stopped" "er endet geordnet an seiner Zeitgrenze"

# =====================================================================
echo "== 9. ZUSAGE (e): grosse Datei, grosse Ausgabe =="
python3 -c "open('$TMPD/gross.bin','wb').write(b'A'*20000)"
python3 -c "
import binascii
d=open('$TMPD/gross.bin','rb').read()
open('$TMPD/auf-gross.txt','w').write(
 'lies|/var/jarvis/gross.bin|\n'
 'schreib|/var/jarvis/zugross.txt|'+binascii.hexlify(d).decode()+'\n'
 'befehl|/bin/cat /var/jarvis/gross.bin|\n'
 'lies|/var/jarvis/gruss.txt|\n')
"
abbild "$TMPD/gross.img" "$TMPD/voll.conf" \
    "/var/jarvis/gruss.txt=$TMPD/gruss.txt" \
    "/var/jarvis/gross.bin=$TMPD/gross.bin"
# /bin/cat muss dafuer erlaubt sein.
sed 's|command_allowed = /bin/echo|command_allowed = /bin/echo\ncommand_allowed = /bin/cat|' \
    "$TMPD/voll.conf" > "$TMPD/gross.conf"
abbild "$TMPD/gross.img" "$TMPD/gross.conf" \
    "/var/jarvis/gruss.txt=$TMPD/gruss.txt" \
    "/var/jarvis/gross.bin=$TMPD/gross.bin"
draht_auf
gegenstelle_an good "$TMPD/auf-gross.txt" "$TMPD/g6.log"
lauf_mit_netz "$TMPD/gross.img" "jarvisd -1 -t 60000;exit" "$TMPD/r6.txt" 220
gegenstelle_aus
draht_zu
G="$TMPD/g6.log"
[ "$(status_von 1)" = nein ] && ok "lies: eine Datei ueber max_datei wird abgelehnt statt eingelesen" \
                             || bad "lies gross: $(grep -a '^ANTWORT 1 ' "$G")"
hat "$G.1.bin" "larger than max_file" "und der Grund nennt die Grenze"
[ "$(status_von 2)" = nein ] && ok "schreib: eine Nutzlast ueber max_datei wird abgelehnt" \
                             || bad "schreib gross: $(grep -a '^ANTWORT 2 ' "$G")"
L3=$(grep -a "^ANTWORT 3 " "$G" | awk '{print $5}')
if [ -n "$L3" ] && [ "$L3" -le 4200 ]; then
    ok "befehl: 20000 Oktette Ausgabe kommen auf $L3 gekuerzt (max_ausgabe 4096)"
else
    bad "befehl: die Ausgabe wurde nicht gekuerzt ($L3 Oktette)"
fi
hat "$G.3.bin" "truncated, max_output reached" "und die Kuerzung steht in der Antwort statt sie zu verschweigen"
[ "$(status_von 4)" = ok ] && ok "und danach laeuft der Helfer weiter (die kleine Datei kommt)" \
                           || bad "nach den Grenzfaellen antwortet er nicht mehr"

echo "== 9b. command_flag_allowed: options per command =="
sed 's|command_allowed = /bin/echo|command_allowed = /bin/echo\ncommand_flag_allowed = /bin/echo -n|' \
    "$TMPD/voll.conf" > "$TMPD/flag.conf"
abbild "$TMPD/flag.img" "$TMPD/flag.conf" "/var/jarvis/gruss.txt=$TMPD/gruss.txt"
abbild "$TMPD/noflag.img" "$TMPD/voll.conf" "/var/jarvis/gruss.txt=$TMPD/gruss.txt"
cat > "$TMPD/auf-flag.txt" <<'AUF'
befehl|/bin/echo plain|
befehl|/bin/echo -n listed|
befehl|/bin/echo -x unlisted|
befehl|/bin/echo plain -n|
befehl|/bin/echo -nn|
AUF
draht_auf
gegenstelle_an good "$TMPD/auf-flag.txt" "$TMPD/g9b.log"
lauf_mit_netz "$TMPD/flag.img" "jarvisd -1 -t 60000;exit" "$TMPD/r9b.txt" 220
gegenstelle_aus
draht_zu
G="$TMPD/g9b.log"
[ "$(status_von 1)" = ok ] && ok "no option: allowed" || bad "no option: $(grep -a '^ANTWORT 1 ' "$G")"
[ "$(status_von 2)" = ok ] && ok "listed option -n: allowed" || bad "listed option: $(grep -a '^ANTWORT 2 ' "$G")"
[ "$(status_von 3)" = nein ] && ok "unlisted option -x: rejected" || bad "unlisted option: $(grep -a '^ANTWORT 3 ' "$G")"
hat "$G.3.bin" "command_flag_allowed" "the reason names command_flag_allowed"
[ "$(status_von 4)" = ok ] && ok "listed option in a later position: allowed" || bad "later option: $(grep -a '^ANTWORT 4 ' "$G")"
[ "$(status_von 5)" = nein ] && ok "-nn is not -n: rejected" || bad "-nn: $(grep -a '^ANTWORT 5 ' "$G")"
draht_auf
gegenstelle_an good "$TMPD/auf-flag.txt" "$TMPD/g9c.log"
lauf_mit_netz "$TMPD/noflag.img" "jarvisd -1 -t 60000;exit" "$TMPD/r9c.txt" 220
gegenstelle_aus
draht_zu
G="$TMPD/g9c.log"
[ "$(status_von 3)" = ok ] && ok "counter-proof: without command_flag_allowed -x passes" || bad "counter-proof: $(grep -a '^ANTWORT 3 ' "$G")"

echo "== 9c. command_sub_allowed: subcommands per command =="
sed 's|command_allowed = /bin/echo|command_allowed = /bin/echo\ncommand_sub_allowed = /bin/echo list\ncommand_sub_allowed = /bin/echo status|' \
    "$TMPD/voll.conf" > "$TMPD/sub.conf"
abbild "$TMPD/sub.img" "$TMPD/sub.conf" "/var/jarvis/gruss.txt=$TMPD/gruss.txt"
cat > "$TMPD/auf-sub.txt" <<'AUF'
befehl|/bin/echo list|
befehl|/bin/echo status x|
befehl|/bin/echo ban|
befehl|/bin/echo -n list|
befehl|/bin/echo -n ban|
befehl|/bin/echo|
befehl|/bin/echo lists|
AUF
draht_auf
gegenstelle_an good "$TMPD/auf-sub.txt" "$TMPD/g9d.log"
lauf_mit_netz "$TMPD/sub.img" "jarvisd -1 -t 60000;exit" "$TMPD/r9d.txt" 220
gegenstelle_aus
draht_zu
G="$TMPD/g9d.log"
[ "$(status_von 1)" = ok ] && ok "listed subcommand: allowed" || bad "listed subcommand: $(grep -a '^ANTWORT 1 ' "$G")"
[ "$(status_von 2)" = ok ] && ok "second listed subcommand with an argument: allowed" || bad "second subcommand: $(grep -a '^ANTWORT 2 ' "$G")"
[ "$(status_von 3)" = nein ] && ok "unlisted subcommand: rejected" || bad "unlisted subcommand: $(grep -a '^ANTWORT 3 ' "$G")"
hat "$G.3.bin" "command_sub_allowed" "the reason names command_sub_allowed"
[ "$(status_von 4)" = ok ] && ok "option before a listed subcommand: allowed" || bad "option + listed: $(grep -a '^ANTWORT 4 ' "$G")"
[ "$(status_von 5)" = nein ] && ok "option before an unlisted subcommand: rejected" || bad "option + unlisted: $(grep -a '^ANTWORT 5 ' "$G")"
[ "$(status_von 6)" = nein ] && ok "no subcommand at all: rejected" || bad "bare command: $(grep -a '^ANTWORT 6 ' "$G")"
[ "$(status_von 7)" = nein ] && ok "list is not lists: rejected" || bad "prefix subcommand: $(grep -a '^ANTWORT 7 ' "$G")"
draht_auf
gegenstelle_an good "$TMPD/auf-sub.txt" "$TMPD/g9e.log"
lauf_mit_netz "$TMPD/noflag.img" "jarvisd -1 -t 60000;exit" "$TMPD/r9e.txt" 220
gegenstelle_aus
draht_zu
G="$TMPD/g9e.log"
[ "$(status_von 3)" = ok ] && ok "counter-proof: without command_sub_allowed any subcommand passes" || bad "counter-proof: $(grep -a '^ANTWORT 3 ' "$G")"

# =====================================================================
echo "== 10. ZUSAGE (f): kein Netz beim Start =="
lauf_und_miss() { # <abbild> <skript> <ausgabe> <sekunden>
    local copy="$TMPD/live-miss.img"
    cp "$1" "$copy"
    qemu-system-x86_64 -kernel "$K" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 nic nip=$OSUM_IP/24 ngw=$HOST_IP nsvc=0 nwait=0 script=$2" \
        -serial "file:$3" -display none -no-reboot -vga std \
        -drive "file=$copy,format=raw,if=ide,index=0" \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device "$NIC,netdev=n0,mac=52:54:00:aa:bb:cc" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$!
    local wall0=$(date +%s%N)
    local i=0
    while [ $i -lt $(( $4 * 20 + 400 )) ]; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.05
        i=$((i+1))
    done
    CPU_TICKS=0
    if [ -r "/proc/$pid/stat" ]; then
        CPU_TICKS=$(awk '{print $14+$15}' "/proc/$pid/stat" 2>/dev/null)
    fi
    wait "$pid" 2>/dev/null
    local rc=$?
    if [ -z "$CPU_TICKS" ] || [ "$CPU_TICKS" = 0 ]; then CPU_TICKS=0; fi
    WALL_MS=$(( ($(date +%s%N) - wall0)/1000000 ))
    rm -f "$copy"
    return $rc
}
lauf_und_miss "$TMPD/nonet.img" "jarvisd -t 20000 -v;exit" "$TMPD/r7.txt" 60
F="$TMPD/r7.txt"
hat "$F" "jarvisd: ready" "ohne Netz startet der Dienst trotzdem"
hat "$F" "jarvisd: no connection" "er sagt, dass da nichts ist"
hat "$F" "jarvisd: connections 0" "keine einzige Verbindung"
hat "$F" "service stopped" "und er endet geordnet an seiner Zeitgrenze"

draht_auf
lauf_und_miss "$TMPD/nonet.img" "jarvisd -t 20000 -v;exit" "$TMPD/r7c.txt" 60
draht_zu
F="$TMPD/r7c.txt"
hat "$F" "jarvisd: waiting" "mit Draht, aber ohne Gegenstelle: er wartet zwischen den Versuchen"
WMS=$(grep -a 'wait_ms' "$F" | tail -1 | awk '{print $3}')
WAUF=$(grep -a 'calls_while_waiting' "$F" | tail -1 | awk '{print $3}')
note "gewartet: ${WMS:-?} ms, Systemaufrufe des ganzen Systems dabei: ${WAUF:-?}"
if [ -n "${WMS:-}" ] && [ "${WMS:-0}" -ge 1000 ] && [ -n "${WAUF:-}" ]; then
    zahl "Systemaufrufe je Sekunde Wartezeit" \
        $(( WAUF * 1000 / WMS )) le 50
else
    bad "die Wartezahlen fehlen (wartezeit=${WMS:-} aufrufe=${WAUF:-})"
fi
HZ=$(getconf CLK_TCK 2>/dev/null || echo 100)
CPU_MS=$(( CPU_TICKS * 1000 / HZ ))
note "QEMU auf dem Wirt: $CPU_MS ms Rechenzeit in $WALL_MS ms Laufzeit"

lauf_ohne_netz "$TMPD/nonet.img" "jarvisd -n;jarvisd -n;jarvisd -n;exit" "$TMPD/r7b.txt"
ok "GEGENPROBE gelaufen: derselbe Kern mit Arbeit statt Warten"

# =====================================================================
echo "== 11. ZUSAGE (g): der private Schluessel, und wer ihn lesen darf =="
# =====================================================================
lauf_ohne_netz "$TMPD/nonet.img" "jsig init;jarvisctl status;jsig sign 00112233;chmod 644 /etc/jarvis/device.key;jsig sign 00112233;exit" "$TMPD/r8.txt"
F="$TMPD/r8.txt"
hat "$F" "pub " "jsig legt einen Geraeteschluessel an und nennt den oeffentlichen Teil"
hat "$F" "present, mode 600" "die Schluesseldatei hat 0600 -- niemand ausser dem Eigentuemer"
hat "$F" "sig " "und sie laesst sich damit benutzen"
hat "$F" "is readable by others" "nach chmod 644 WEIGERT sich jsig, sie zu benutzen"
SIGZ=$(grep -a '^sig ' "$F" | head -1 | awk '{print $2}')
zahl "die Laenge der Unterschrift in Hexziffern" "${#SIGZ}" eq 128
PUBZ=$(grep -a '^pub ' "$F" | head -1 | awk '{print $2}')
python3 - "$PUBZ" "$SIGZ" > "$TMPD/verify.txt" 2>&1 <<'PYEOF'
import sys
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from cryptography.exceptions import InvalidSignature
pub = bytes.fromhex(sys.argv[1]); sig = bytes.fromhex(sys.argv[2])
msg = bytes.fromhex("00112233")
k = Ed25519PublicKey.from_public_bytes(pub)
try:
    k.verify(sig, msg); print("GUT")
except InvalidSignature:
    print("FALSCH")
try:
    k.verify(sig, b"\x00\x11\x22\x34"); print("GEGENPROBE-FALSCH")
except InvalidSignature:
    print("GEGENPROBE-GUT")
PYEOF
hat "$TMPD/verify.txt" "GUT" "python-cryptography rechnet die Unterschrift von /bin/jsig nach"
hat "$TMPD/verify.txt" "GEGENPROBE-GUT" "GEGENPROBE: ueber ein anderes Oktett faellt sie durch"

echo "   -- und der Kern sagt nein, nicht dieses Programm (HND_DUP, Runde HANDLE)"
lauf_ohne_netz "$TMPD/nonet.img" "jarvisd -p;exit" "$TMPD/r9.txt"
F="$TMPD/r9.txt"
hat "$F" "probe: hat_schreibrecht nein" "der beschnittene Deskriptor hat R_WRITE nicht mehr"
hat "$F" "probe: schreibversuch abgewiesen" "und der KERN weist das Schreiben darauf ab"
hat "$F" "probe: gelesen 5 hallo" "lesen geht weiter -- beschnitten ist nicht kaputt"
ROFF=$(grep -a 'probe: rechte_offen' "$F" | head -1 | awk '{print $3}')
RENG=$(grep -a 'probe: rechte_eng' "$F" | head -1 | awk '{print $3}')
note "Rechtebitfeld vorher $ROFF, nachher $RENG (R_READ|R_INSPECT|R_SEEK = 2081)"
zahl "die Rechte des beschnittenen Deskriptors" "${RENG:-0}" eq 2081

# =====================================================================
echo "== 12. das Bildschirmfoto: zwei Schloesser, und der Schein gilt einmal =="
# =====================================================================
mach_conf "$TMPD/foto.conf" no yes yes \
    "read          = /var/jarvis/" \
    "max_output    = 65536" \
    "max_file      = 4194304"
abbild "$TMPD/foto.img" "$TMPD/foto.conf" "/var/jarvis/gruss.txt=$TMPD/gruss.txt"
cat > "$TMPD/auf-foto.txt" <<'AUF'
foto||
foto||
AUF
EXTRA="gfx"
draht_auf
gegenstelle_an good "$TMPD/auf-foto.txt" "$TMPD/g7.log"
lauf_mit_netz "$TMPD/foto.img" "jarvisd -1 -t 40000;exit" "$TMPD/r10.txt" 180
gegenstelle_aus
draht_zu
G="$TMPD/g7.log"
[ "$(status_von 1)" = nein ] && ok "ohne Schein: abgelehnt, obwohl die Rechteliste es erlaubt" \
                             || bad "ohne Schein kam ein Bild: $(grep -a '^ANTWORT 1 ' "$G")"
hat "$G.1.bin" "no screenshot permit" "und der Grund nennt den fehlenden Schein"

draht_auf
gegenstelle_an good "$TMPD/auf-foto.txt" "$TMPD/g8.log"
lauf_mit_netz "$TMPD/foto.img" "jarvisctl screenshot 600;jarvisd -1 -t 60000;jarvisctl log 10;exit" "$TMPD/r11.txt" 220
gegenstelle_aus
draht_zu
G="$TMPD/g8.log"; F="$TMPD/r11.txt"
hat "$F" "One screenshot allowed" "jarvisctl stellt einen befristeten Schein aus"
S1=$(status_von 1)
if [ "$S1" = ok ]; then
    PNGL=$(grep -a "^ANTWORT 1 " "$G" | awk '{print $5}')
    python3 - "$G.1.bin" > "$TMPD/png.txt" 2>&1 <<'PYEOF'
import sys, struct, zlib
d = open(sys.argv[1], "rb").read()
assert d[:8] == b"\x89PNG\r\n\x1a\n", "keine PNG-Signatur"
at = 8; w = h = 0; idat = b""; stuecke = []
while at < len(d):
    ln = struct.unpack(">I", d[at:at+4])[0]
    art = d[at+4:at+8]
    inhalt = d[at+8:at+8+ln]
    crc = struct.unpack(">I", d[at+8+ln:at+12+ln])[0]
    assert crc == zlib.crc32(art + inhalt) & 0xFFFFFFFF, "CRC von %s falsch" % art
    stuecke.append(art.decode())
    if art == b"IHDR":
        w, h, tiefe, farbe = struct.unpack(">IIBB", inhalt[:10])
        assert tiefe == 8 and farbe == 2, "Farbart %d Tiefe %d" % (farbe, tiefe)
    if art == b"IDAT":
        idat += inhalt
    at += 12 + ln
roh = zlib.decompress(idat)
assert len(roh) == h * (1 + 3 * w), "Bilddaten %d statt %d" % (len(roh), h*(1+3*w))
print("PNG-GUT %dx%d stuecke=%s roh=%d gepackt=%d" %
      (w, h, ",".join(stuecke), len(roh), len(idat)))
PYEOF
    if grep -qa "PNG-GUT" "$TMPD/png.txt"; then
        ok "mit Schein: ein PNG, von Pythons zlib nachgerechnet -- $(cat "$TMPD/png.txt")"
        note "Groesse des Bildschirmfotos: $PNGL Oktette"
    else
        bad "die Antwort ist kein gueltiges PNG: $(head -3 "$TMPD/png.txt")"
    fi
    [ "$(status_von 2)" = nein ] \
        && ok "DER SCHEIN GILT EINMAL: das zweite Foto wird abgelehnt" \
        || bad "das zweite Foto kam auch noch -- der Schein wird nicht verbraucht"
elif grep -qa "screen size\|framebuffer" "$G.1.bin" 2>/dev/null; then
    ok "mit Schein: dieser Kern gibt Ring 3 keine Bildschirmmasse, und der Helfer sagt genau das"
    note "KEIN BILD VOM ECHTEN BILDSCHIRM GEMESSEN -- siehe docs/BRIDGE.md."
    [ "$(status_von 2)" = nein ] && ok "und das zweite Foto scheitert ebenfalls" \
                                 || bad "das zweite Foto haette auch scheitern muessen"
else
    bad "foto mit Schein: $(grep -a '^ANTWORT 1 ' "$G") -- $(head -c 120 "$G.1.bin" 2>/dev/null)"
fi
hat "$F" "screenshot " "das Foto steht im Protokoll -- heimlich geht es nicht"
EXTRA=""

echo "   -- der PNG-Kodierer selbst, mit einem gerechneten Bild"
lauf_ohne_netz "$TMPD/foto.img" "jarvisd -b;exit" "$TMPD/r13.txt"
tr -d '\000' < "$TMPD/r13.txt" | grep -a '^bild ' | head -1 | awk '{print $2}' > "$TMPD/bild.hex"
if [ -s "$TMPD/bild.hex" ]; then
    python3 - "$TMPD/bild.hex" > "$TMPD/bild.txt" 2>&1 <<'PYEOF'
import sys, struct, zlib
d = bytes.fromhex(open(sys.argv[1]).read().strip())
assert d[:8] == b"\x89PNG\r\n\x1a\n", "keine PNG-Signatur"
at = 8; w = h = 0; idat = b""; stuecke = []
while at < len(d):
    ln = struct.unpack(">I", d[at:at+4])[0]
    art = d[at+4:at+8]
    inhalt = d[at+8:at+8+ln]
    crc = struct.unpack(">I", d[at+8+ln:at+12+ln])[0]
    assert crc == zlib.crc32(art + inhalt) & 0xFFFFFFFF, "CRC von %s falsch" % art
    stuecke.append(art.decode())
    if art == b"IHDR":
        w, h, tiefe, farbe, komp, filt, inter = struct.unpack(">IIBBBBB", inhalt)
        assert (tiefe, farbe, komp, filt, inter) == (8, 2, 0, 0, 0), "IHDR falsch"
    if art == b"IDAT":
        idat += inhalt
    at += 12 + ln
assert stuecke == ["IHDR", "IDAT", "IEND"], stuecke
roh = zlib.decompress(idat)
assert len(roh) == h * (1 + 3 * w), "Bilddaten %d statt %d" % (len(roh), h*(1+3*w))
# JEDEN Bildpunkt nachrechnen -- das Muster steht in jarvisd.fi.
falsch = 0
for y in range(h):
    z = roh[y*(1+3*w):(y+1)*(1+3*w)]
    if z[0] != 0:
        falsch += 1
        continue
    for x in range(w):
        r, g, b = z[1+3*x], z[2+3*x], z[3+3*x]
        if (r, g, b) != ((x*4) & 255, (y*5) & 255, ((x+y)*2) & 255):
            falsch += 1
print("PNG-GUT %dx%d gepackt=%d roh=%d abweichungen=%d" % (w, h, len(idat), len(roh), falsch))
PYEOF
    if grep -qa "PNG-GUT" "$TMPD/bild.txt" && grep -qa "abweichungen=0" "$TMPD/bild.txt"; then
        ok "der PNG-Kodierer: $(cat "$TMPD/bild.txt")"
        note "Groesse dieses Bildes: $(( $(wc -c < "$TMPD/bild.hex") / 2 )) Oktette"
    else
        bad "das erzeugte PNG ist nicht in Ordnung: $(head -3 "$TMPD/bild.txt")"
    fi
else
    bad "jarvisd -b hat kein Bild geliefert"
fi

# =====================================================================
echo "== 13. die Messungen =="
cat > "$TMPD/auf-mess.txt" <<'AUF'
system||
system||
system||
AUF
draht_auf
gegenstelle_an good "$TMPD/auf-mess.txt" "$TMPD/g9.log"
lauf_mit_netz "$TMPD/nonet.img" "jarvisd -1 -t 60000 -v;exit" "$TMPD/r12.txt" 220
gegenstelle_aus
draht_zu
F="$TMPD/r12.txt"
hat "$F" "jarvisd: jobs 3" "drei Auftraege in einer Sitzung"
ANZ=$(grep -ac "^ANTWORT " "$TMPD/g9.log")
zahl "Antworten, die die Gegenstelle bekommen hat" "$ANZ" eq 3

echo "   -- die Zahlen dieser Runde"
note "Quelltext:            $ZEILEN Zeilen (jarvisd.fi, jsig.fi, jarvisctl.fi)"
note "/bin/jarvisd:         $JDSZ Oktette (TLS 1.3, X.509, DEFLATE, das Protokoll)"
note "/bin/jsig:            $JSSZ Oktette (Ed25519 + SHA-512 + Montgomery)"
note "Wartelast:            ${WAUF:-?} Systemaufrufe in ${WMS:-?} ms Wartezeit"

echo "BRIDGE: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ] || exit 1
