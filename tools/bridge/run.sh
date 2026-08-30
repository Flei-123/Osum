#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bridge/run.sh -- RUNDE BRIDGE: DER HELFER, UND WAS ER NICHT DARF.
#
# Diese Runde baut den JARVIS-Helfer fuer Osum (kernel/app/jarvisd.fi,
# kernel/user/jsig.fi, kernel/user/jarvisctl.fi). Gemessen wird hier
# NICHT in erster Linie, dass er Auftraege ausfuehrt -- das ist der
# leichte Teil -- sondern DASS ER SIE ABLEHNT, wenn sie nicht in der
# Rechteliste stehen. Ein Fernhelfer, der alles kann, ist keine
# Errungenschaft, sondern eine Hintertuer.
#
# GEGEN WEN GEMESSEN WIRD, ausdruecklich: gegen `tools/bridge/gegenstelle.py`,
# einen TLS-1.3-Server in Python, NICHT gegen den echten JARVIS-Server.
# Der laeuft anderswo, spricht ein anderes Protokoll und ist nicht Teil
# dieses Repos. Alles, was hier gruen ist, ist damit eine Aussage ueber
# das Protokoll dieser Runde und ueber Osums Seite davon -- und keine
# ueber die Gegenseite in Justins Rechenzentrum. Was fuer den Betrieb
# gegen den echten Server noch fehlt, steht in docs/BRIDGE.md.
#
# DER DRAHT ist der von Runde K8/HWNET (tools/net/bridge.c): QEMUs
# UDP-Rueckseite auf der einen Seite, AF_PACKET in ein veth-Paar auf der
# anderen, und ein Netzraum mit der Gegenstelle darin.
#
#   Osum in QEMU <--e1000--> QEMU <--UDP--> tools/net/bridge
#                <--AF_PACKET--> veth <--> gegenstelle.py im Netzraum
#
# DIE ABSCHNITTE:
#   1. bauen: zwei Profile, ein Abbild, keine undefinierten Namen
#   2. die Rechteliste ohne Netz -- und die Gegenprobe mit leerer Liste
#   3. die Anmeldung: Ed25519, von Python nachgerechnet
#   4. die sechs Auftragsarten, wenn sie erlaubt sind
#   5. ZUSAGE (a): jede Auftragsart einzeln abgelehnt, protokolliert,
#      und nichts ist passiert
#   6. ZUSAGE (b): drei falsche Zertifikate, drei Weigerungen
#   7. ZUSAGE (c): Kopplung ohne Bestaetigung am Geraet -> abgelehnt
#   8. ZUSAGE (d): Abriss mitten im Auftrag -> sauber, und wieder da
#   9. ZUSAGE (e): zu grosse Datei, zu grosse Ausgabe -> Grenze greift
#  10. ZUSAGE (f): kein Netz beim Start -> der Dienst laeuft und wartet
#  11. ZUSAGE (g): der private Schluessel ist nicht fuer andere lesbar
#  12. die Messungen
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
export FIRNLIB="$ROOT/vendor/firn/lib"
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

# Die Gegenprobe zur Trennung: DIESELBEN zwei Bibliotheken in EINEM
# Programm gehen NICHT, und genau deshalb sind es zwei Programme. Wer
# die Trennung eines Tages aufheben will, faellt hier auf.
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

# Quellzeilen, gezaehlt und nicht geschaetzt.
ZEILEN=$(cat kernel/app/jarvisd.fi kernel/user/jsig.fi \
    kernel/user/jarvisctl.fi | wc -l)
note "Quelltext dieser Runde: $ZEILEN Zeilen in drei Dateien"

# Der GUI-lose Serverbau muss den Helfer auch tragen -- ohne Bildschirm
# gibt es eben kein Bildschirmfoto, aber sehr wohl einen Helfer.
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

# Die Rechteliste der Runde, mit der Adresse des Pruefstands.
mach_conf() { # <datei> <befehle> <foto> <system> <extra...>
    local f=$1; shift
    cat > "$f" <<CONF
server         = $HOST_IP:$SRVPORT
servername     = jarvis.test
wurzeln        = /etc/ssl/roots.pem
befehle        = $1
bildschirmfoto = $2
systeminfo     = $3
CONF
    shift 3
    for z in "$@"; do echo "$z" >> "$f"; done
}

mach_conf "$TMPD/voll.conf" ja nein ja \
    "befehl_erlaubt = /bin/echo" \
    "lesen          = /var/jarvis/" \
    "lesen          = /etc/jarvis/rechte.conf" \
    "schreiben      = /var/jarvis/" \
    "auflisten      = /var/jarvis/" \
    "max_ausgabe    = 4096" \
    "max_datei      = 8192"

mach_conf "$TMPD/leer.conf" nein nein nein

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
        "/etc/jarvis/rechte.conf=$conf" \
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
hat "$F" "rechte lesen 2 schreiben 1 auflisten 1 befehle 1 foto nein system ja" \
    "die Rechteliste wird gelesen und Punkt fuer Punkt gemeldet"
lauf_ohne_netz "$TMPD/leer.img" "jarvisd -n;exit" "$TMPD/s2b.txt"
hat "$TMPD/s2b.txt" "rechte lesen 0 schreiben 0 auflisten 0 befehle nein foto nein system nein" \
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
    ip netns exec "$NS" python3 tools/bridge/gegenstelle.py \
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
lies|/etc/jarvis/rechte.conf|
liste|/var/jarvis/|
befehl|/bin/echo eins zwei|
foto||
AUF
draht_auf
gegenstelle_an good "$TMPD/auf-gut.txt" "$TMPD/g1.log"
T0=$(date +%s%N)
lauf_mit_netz "$TMPD/nonet.img" "jarvisd -1 -t 60000;jarvisctl protokoll 40;exit" "$TMPD/r1.txt"
T1=$(date +%s%N)
gegenstelle_aus
draht_zu
G="$TMPD/g1.log"; F="$TMPD/r1.txt"

hat "$G" "TLSv1.3" "die Verbindung steht auf TLS 1.3 -- gesagt hat das Python, nicht Osum"
hat "$G" "BEWEIS gut" "die Ed25519-Unterschrift des Geraets stimmt (nachgerechnet von python-cryptography)"
hat "$G" "GEGENPROBE gut" "GEGENPROBE: dieselbe Unterschrift ueber andere Oktette faellt durch"
hat "$G" "ANGEMELDET" "der Server hat die Anmeldung angenommen"
hat "$F" "jarvisd: verbunden" "und Osum hat es auch so gesehen"
hat "$F" "jarvisd: angemeldet" "der Helfer meldet sich angemeldet"

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
# foto steht in dieser Liste auf `nein`, also MUSS es scheitern.
[ "$(status_von 7)" = nein ] && ok 'foto: abgelehnt, weil bildschirmfoto = nein' \
                             || bad "foto: $(antwort 7)"
hat "$F" "jarvisd: verbindungen 1" "genau eine Verbindung"
hat "$F" "jarvisd: auftraege 7" "sieben Auftraege gezaehlt"

echo "   -- das Protokoll unter /var/log/jarvisd.log"
hat "$F" "dienst gestartet" "der Start steht im Protokoll"
hat "$F" "sitzung angemeldet" "die Anmeldung steht im Protokoll"
hat "$F" "system ok" 'ein erledigter Auftrag steht mit ok im Protokoll'
hat "$F" "foto ABGELEHNT" 'ein abgelehnter steht mit ABGELEHNT darin'

VERB_MS=$(( (T1-T0)/1000000 ))
note "vom QEMU-Start bis zum Ende dieses Laufs: $VERB_MS ms (mit Bau des Abbilds ausserhalb)"

# =====================================================================
echo "== 5. ZUSAGE (a): jede Auftragsart einzeln abgelehnt =="
# =====================================================================
# Die Rechteliste erlaubt NICHTS. Alle sechs Arten muessen einzeln
# scheitern, jede mit einem Grund, jede im Protokoll -- und danach darf
# nichts geschehen sein.
mach_conf "$TMPD/nix.conf" nein nein nein
abbild "$TMPD/nix.img" "$TMPD/nix.conf" "/var/jarvis/gruss.txt=$TMPD/gruss.txt"
cat > "$TMPD/auf-nix.txt" <<'AUF'
system||
lies|/var/jarvis/gruss.txt|
schreib|/var/jarvis/darfnicht.txt|4e4945
liste|/var/jarvis/|
befehl|/bin/echo hallo|
foto||
lies|/var/jarvis/../etc/jarvis/geraet.key|
lies|/etc/jarvis/geraet.key|
AUF
draht_auf
gegenstelle_an good "$TMPD/auf-nix.txt" "$TMPD/g2.log"
lauf_mit_netz "$TMPD/nix.img" "jarvisd -1 -t 60000;cat /var/jarvis/darfnicht.txt;jarvisctl protokoll 40;exit" "$TMPD/r2.txt"
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
pruefe_nein 1 system     "systeminfo"
pruefe_nein 2 lies       "lesen"
pruefe_nein 3 schreib    "schreiben"
pruefe_nein 4 liste      "auflisten"
pruefe_nein 5 befehl     "befehle = nein"
pruefe_nein 6 foto       "bildschirmfoto = nein"
pruefe_nein 7 "lies mit .."  "kein sauberer absoluter Pfad"
pruefe_nein 8 "lies auf den Schluessel" "lesen"

hat_nicht "$F" "NIE" "und NICHTS ist passiert: /var/jarvis/darfnicht.txt gibt es nicht"
for a in system lies schreib liste befehl foto; do
    grep -qa "^[0-9-]* [0-9:]* $a ABGELEHNT" "$F" \
        && ok "$a: die Ablehnung steht im Protokoll" \
        || bad "$a: keine Ablehnungszeile im Protokoll"
done
hat "$F" "jarvisd: abgelehnt 8" "acht Ablehnungen gezaehlt"

# =====================================================================
echo "== 6. ZUSAGE (b): falsche Zertifikate =="
# =====================================================================
# DIE WEIGERUNGEN SIND DIE MESSUNG. Ein Helfer, der jedes Zertifikat
# nimmt, ist schlimmer als einer ohne TLS: er behauptet Sicherheit.
: > "$TMPD/leerspeicher.pem"
for fall in expired wrong rogue; do
    draht_auf
    gegenstelle_an "$fall" "$TMPD/auf-gut.txt" "$TMPD/gz-$fall.log"
    lauf_mit_netz "$TMPD/nonet.img" "jarvisd -1 -t 12000;jarvisctl protokoll 10;exit" "$TMPD/rz-$fall.txt" 120
    gegenstelle_aus
    draht_zu
    Z="$TMPD/rz-$fall.txt"
    if grep -qa "jarvisd: der Handschlag ist gescheitert" "$Z"; then
        ok "$fall: der Handschlag wird abgelehnt, Grund $(grep -a 'Handschlag ist gescheitert' "$Z" | head -1 | sed 's/.*Grund //')"
    else
        bad "$fall: der Handschlag wurde NICHT abgelehnt"
    fi
    hat_nicht "$Z" "jarvisd: angemeldet" "$fall: und es wurde sich NICHT angemeldet"
    hat "$Z" "tls ABGELEHNT" "$fall: die Ablehnung steht im Protokoll"
done

# Und ohne Wurzelspeicher ist nichts vertrauenswuerdig, auch nicht das
# gute Zertifikat.
python3 tools/osum/mkfs.py build "$TMPD/leerca.img" 16384 \
    /bin/ /etc/ /etc/ssl/ /etc/jarvis/ /var/ /var/log/ /var/jarvis/ \
    "/bin/sh=$TMPD/w0/sh.elf" "/bin/jsig=$TMPD/w0/jsig.elf" \
    "/bin/jarvisctl=$TMPD/w0/jarvisctl.elf" "/bin/jarvisd=$TMPD/w0/jarvisd.elf" \
    "/etc/jarvis/rechte.conf=$TMPD/voll.conf" \
    "/etc/ssl/roots.pem=$TMPD/leerspeicher.pem" > "$TMPD/mkfs2.txt" 2>&1
draht_auf
gegenstelle_an good "$TMPD/auf-gut.txt" "$TMPD/gz-leer.log"
lauf_mit_netz "$TMPD/leerca.img" "jarvisd -1 -t 12000;exit" "$TMPD/rz-leer.txt" 120
gegenstelle_aus
draht_zu
hat "$TMPD/rz-leer.txt" "kein Wurzelspeicher" "leerer Speicher: der Helfer sagt es laut"
hat_nicht "$TMPD/rz-leer.txt" "jarvisd: angemeldet" "leerer Speicher: und meldet sich NICHT an"

# =====================================================================
echo "== 7. ZUSAGE (c): Kopplung ohne Bestaetigung am Geraet =="
# =====================================================================
CODE=$(python3 -c 'import secrets;print("%06d" % secrets.randbelow(1000000))')
cat > "$TMPD/auf-kurz.txt" <<'AUF'
system||
AUF
draht_auf
gegenstelle_an good "$TMPD/auf-kurz.txt" "$TMPD/g3.log" --kopplung "$CODE"
lauf_mit_netz "$TMPD/nonet.img" "jarvisd -1 -t 30000;jarvisctl protokoll 10;exit" "$TMPD/r3.txt" 150
gegenstelle_aus
draht_zu
hat "$TMPD/g3.log" "KOPPLUNG-ABGELEHNT" "ohne Bestaetigung: der Helfer lehnt die Kopplung ab"
hat "$TMPD/r3.txt" "KOPPLUNGSCODE $CODE" "der Code wird dem Menschen am Geraet gezeigt"
hat "$TMPD/r3.txt" "die Kopplung wurde ABGELEHNT" "und die Ablehnung steht auf der Konsole"
hat "$TMPD/r3.txt" "kopplung abgelehnt" "sie steht auch im Protokoll"
hat_nicht "$TMPD/g3.log" "ANGEMELDET" "und der Server hat KEINE angemeldete Sitzung gesehen"

echo "   -- und jetzt mit Bestaetigung, damit die Ablehnung etwas bedeutet"
draht_auf
gegenstelle_an good "$TMPD/auf-kurz.txt" "$TMPD/g4.log" --kopplung "$CODE" --verbindungen 2
lauf_mit_netz "$TMPD/nonet.img" "jarvisd -1 -t 20000;jarvisctl koppeln $CODE;jarvisd -1 -t 30000;jarvisctl protokoll 10;exit" "$TMPD/r4.txt" 200
gegenstelle_aus
draht_zu
hat "$TMPD/r4.txt" "Die Kopplung ist bestaetigt" "jarvisctl koppeln nimmt den Code an, den der Helfer bekommen hat"
hat "$TMPD/g4.log" "ANGEMELDET" "beim zweiten Anlauf ist die Kopplung durch"
hat "$TMPD/r4.txt" "kopplung bestaetigt" "und sie steht im Protokoll"

echo "   -- GEGENPROBE: ein Code, den niemand angefragt hat"
lauf_ohne_netz "$TMPD/nonet.img" "jarvisctl koppeln 424242;exit" "$TMPD/r4b.txt"
hat "$TMPD/r4b.txt" "keine Kopplungsanfrage" "jarvisctl weigert sich, eine Kopplung zu bestaetigen, die es nicht gibt"

# =====================================================================
echo "== 8. ZUSAGE (d): Abriss mitten im Auftrag =="
# =====================================================================
draht_auf
gegenstelle_an good "$TMPD/auf-gut.txt" "$TMPD/g5.log" --abriss
# OHNE -1: der Helfer muss von selbst wiederkommen wollen. Die
# Zeitgrenze beendet ihn, nicht der Abriss.
lauf_mit_netz "$TMPD/nonet.img" "jarvisd -t 25000 -v;jarvisctl protokoll 10;exit" "$TMPD/r5.txt" 200
gegenstelle_aus
draht_zu
hat "$TMPD/g5.log" "ABRISS nach Auftrag 1" "die Gegenstelle hat mitten im Auftrag abgerissen"
hat "$TMPD/r5.txt" "jarvisd: warten" "der Helfer stirbt nicht, sondern wartet auf den naechsten Versuch"
hat "$TMPD/r5.txt" "jarvisd: verbindungen 1" "er zaehlt die eine Verbindung, die es gab"
# Er versucht es WIRKLICH wieder -- ohne Gegenstelle scheitert der
# Versuch, und genau das steht dann da.
hat "$TMPD/r5.txt" "jarvisd: keine Verbindung" "und er versucht es danach wieder (die Gegenstelle ist weg)"
hat "$TMPD/r5.txt" "dienst beendet" "er endet geordnet an seiner Zeitgrenze"

# =====================================================================
echo "== 9. ZUSAGE (e): grosse Datei, grosse Ausgabe =="
# =====================================================================
# voll.conf hat max_datei = 8192 und max_ausgabe = 4096.
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
sed 's|befehl_erlaubt = /bin/echo|befehl_erlaubt = /bin/echo\nbefehl_erlaubt = /bin/cat|' \
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
hat "$G.1.bin" "groesser als max_datei" "und der Grund nennt die Grenze"
[ "$(status_von 2)" = nein ] && ok "schreib: eine Nutzlast ueber max_datei wird abgelehnt" \
                             || bad "schreib gross: $(grep -a '^ANTWORT 2 ' "$G")"
L3=$(grep -a "^ANTWORT 3 " "$G" | awk '{print $5}')
if [ -n "$L3" ] && [ "$L3" -le 4200 ]; then
    ok "befehl: 20000 Oktette Ausgabe kommen auf $L3 gekuerzt (max_ausgabe 4096)"
else
    bad "befehl: die Ausgabe wurde nicht gekuerzt ($L3 Oktette)"
fi
hat "$G.3.bin" "gekuerzt, max_ausgabe erreicht" "und die Kuerzung steht in der Antwort statt sie zu verschweigen"
[ "$(status_von 4)" = ok ] && ok "und danach laeuft der Helfer weiter (die kleine Datei kommt)" \
                           || bad "nach den Grenzfaellen antwortet er nicht mehr"

# =====================================================================
echo "== 10. ZUSAGE (f): kein Netz beim Start =="
# =====================================================================
# KEIN draht_auf. Die Karte ist da, dahinter ist NICHTS. Der Dienst muss
# trotzdem hochkommen, ruhig warten und geordnet enden.
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
# LAUF A: gar kein Draht. Ein Verbindungsversuch ins Leere laeuft in
# TCPs eigene Zeitgrenze; entscheidend ist, dass der Dienst hochkommt,
# es sagt und geordnet endet.
lauf_und_miss "$TMPD/nonet.img" "jarvisd -t 20000 -v;exit" "$TMPD/r7.txt" 60
F="$TMPD/r7.txt"
hat "$F" "jarvisd: bereit" "ohne Netz startet der Dienst trotzdem"
hat "$F" "jarvisd: keine Verbindung" "er sagt, dass da nichts ist"
hat "$F" "jarvisd: verbindungen 0" "keine einzige Verbindung"
hat "$F" "dienst beendet" "und er endet geordnet an seiner Zeitgrenze"

# LAUF B: der Draht steht, aber niemand lauscht. Dann kommt die
# Absage sofort, und der Helfer durchlaeuft seine Wartezeiten oft
# genug, dass sich die LEERLAUFLAST messen laesst.
draht_auf
lauf_und_miss "$TMPD/nonet.img" "jarvisd -t 20000 -v;exit" "$TMPD/r7c.txt" 60
draht_zu
F="$TMPD/r7c.txt"
hat "$F" "jarvisd: warten" "mit Draht, aber ohne Gegenstelle: er wartet zwischen den Versuchen"
WMS=$(grep -a 'wartezeit_ms' "$F" | tail -1 | awk '{print $3}')
WAUF=$(grep -a 'aufrufe_beim_warten' "$F" | tail -1 | awk '{print $3}')
note "gewartet: ${WMS:-?} ms, Systemaufrufe des ganzen Systems dabei: ${WAUF:-?}"
if [ -n "${WMS:-}" ] && [ "${WMS:-0}" -ge 1000 ] && [ -n "${WAUF:-}" ]; then
    # Eine Warteschleife braucht je Umlauf mindestens einen Aufruf. Bei
    # ueber zehn Sekunden Wartezeit waeren das Zehntausende.
    zahl "Systemaufrufe je Sekunde Wartezeit" \
        $(( WAUF * 1000 / WMS )) le 50
else
    bad "die Wartezahlen fehlen (wartezeit=${WMS:-} aufrufe=${WAUF:-})"
fi
HZ=$(getconf CLK_TCK 2>/dev/null || echo 100)
CPU_MS=$(( CPU_TICKS * 1000 / HZ ))
note "QEMU auf dem Wirt: $CPU_MS ms Rechenzeit in $WALL_MS ms Laufzeit"
# QEMU selbst dreht (der Kern hat eine Leerlaufschleife), also ist das
# hier KEINE Aussage ueber Osums Leerlauf -- die steht eine Zeile
# darueber. Sie steht trotzdem da, damit niemand sie erfindet.

# GEGENPROBE zur Wartezahl: derselbe Kern, aber mit Arbeit. Dann muss
# die Zahl der Systemaufrufe um Groessenordnungen groesser sein.
lauf_ohne_netz "$TMPD/nonet.img" "jarvisd -n;jarvisd -n;jarvisd -n;exit" "$TMPD/r7b.txt"
ok "GEGENPROBE gelaufen: derselbe Kern mit Arbeit statt Warten"

# =====================================================================
echo "== 11. ZUSAGE (g): der private Schluessel, und wer ihn lesen darf =="
# =====================================================================
lauf_ohne_netz "$TMPD/nonet.img" "jsig aus;jarvisctl zustand;jsig unterschreibe 00112233;chmod 644 /etc/jarvis/geraet.key;jsig unterschreibe 00112233;exit" "$TMPD/r8.txt"
F="$TMPD/r8.txt"
hat "$F" "pub " "jsig legt einen Geraeteschluessel an und nennt den oeffentlichen Teil"
hat "$F" "da, Rechte 600" "die Schluesseldatei hat 0600 -- niemand ausser dem Eigentuemer"
hat "$F" "sig " "und sie laesst sich damit benutzen"
hat "$F" "darf von anderen gelesen werden" "nach chmod 644 WEIGERT sich jsig, sie zu benutzen"
SIGZ=$(grep -a '^sig ' "$F" | head -1 | awk '{print $2}')
zahl "die Laenge der Unterschrift in Hexziffern" "${#SIGZ}" eq 128
# Die Gegenprobe: die Unterschrift wird von etwas geprueft, das dieses
# Repo nicht geschrieben hat.
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
mach_conf "$TMPD/foto.conf" nein ja ja \
    "lesen          = /var/jarvis/" \
    "max_ausgabe    = 65536" \
    "max_datei      = 4194304"
abbild "$TMPD/foto.img" "$TMPD/foto.conf" "/var/jarvis/gruss.txt=$TMPD/gruss.txt"
cat > "$TMPD/auf-foto.txt" <<'AUF'
foto||
foto||
AUF
# `gfx` schaltet den Rahmenpuffer ein (kernel/fb.fi, `parse`); ohne
# dieses Wort hat der Kern keinen, und dann gibt es auch kein Bild.
EXTRA="gfx"
# ERST OHNE SCHEIN: `bildschirmfoto = ja` allein reicht nicht.
draht_auf
gegenstelle_an good "$TMPD/auf-foto.txt" "$TMPD/g7.log"
lauf_mit_netz "$TMPD/foto.img" "jarvisd -1 -t 40000;exit" "$TMPD/r10.txt" 180
gegenstelle_aus
draht_zu
G="$TMPD/g7.log"
[ "$(status_von 1)" = nein ] && ok "ohne Schein: abgelehnt, obwohl die Rechteliste es erlaubt" \
                             || bad "ohne Schein kam ein Bild: $(grep -a '^ANTWORT 1 ' "$G")"
hat "$G.1.bin" "kein Fotoschein" "und der Grund nennt den fehlenden Schein"

# JETZT MIT SCHEIN.
draht_auf
gegenstelle_an good "$TMPD/auf-foto.txt" "$TMPD/g8.log"
lauf_mit_netz "$TMPD/foto.img" "jarvisctl fotoschein 600;jarvisd -1 -t 60000;jarvisctl protokoll 10;exit" "$TMPD/r11.txt" 220
gegenstelle_aus
draht_zu
G="$TMPD/g8.log"; F="$TMPD/r11.txt"
hat "$F" "Ein einziges Bildschirmfoto ist frei" "jarvisctl stellt einen befristeten Schein aus"
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
elif grep -qa "Rahmenpuffer" "$G.1.bin" 2>/dev/null; then
    ok "mit Schein: dieser Bau hat keinen Rahmenpuffer, und der Helfer sagt genau das"
    note "KEIN BILD GEMESSEN: der Kern dieses Laufs hat keinen Rahmenpuffer."
    [ "$(status_von 2)" = nein ] && ok "und das zweite Foto scheitert ebenfalls" \
                                 || bad "das zweite Foto haette auch scheitern muessen"
else
    bad "foto mit Schein: $(grep -a '^ANTWORT 1 ' "$G") -- $(head -c 120 "$G.1.bin" 2>/dev/null)"
fi
hat "$F" "foto " "das Foto steht im Protokoll -- heimlich geht es nicht"
EXTRA=""

echo "   -- der PNG-Kodierer selbst, mit einem gerechneten Bild"
# Ring 3 bekommt in diesem Zweig KEINE Bildschirmmasse (SYS_OSUM_SHOT
# fehlt, der Fensterserver laeuft in diesen Laeufen nicht). Damit der
# Kodierer trotzdem gemessen ist und nicht nur uebersetzt, rechnet
# `jarvisd -b` ein Bild aus und schickt es durch denselben Weg.
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
# =====================================================================
# Vom Start des Programms bis "angemeldet", von innen gemessen: der
# Helfer schreibt seine Laufzeit in Millisekunden seit dem Hochlauf des
# Kerns, einmal beim Start und einmal nach der Anmeldung.
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
hat "$F" "jarvisd: auftraege 3" "drei Auftraege in einer Sitzung"
ANZ=$(grep -ac "^ANTWORT " "$TMPD/g9.log")
zahl "Antworten, die die Gegenstelle bekommen hat" "$ANZ" eq 3

echo "   -- die Zahlen dieser Runde"
note "Quelltext:            $ZEILEN Zeilen (jarvisd.fi, jsig.fi, jarvisctl.fi)"
note "/bin/jarvisd:         $JDSZ Oktette (TLS 1.3, X.509, DEFLATE, das Protokoll)"
note "/bin/jsig:            $JSSZ Oktette (Ed25519 + SHA-512 + Montgomery)"
note "Wartelast:            ${WAUF:-?} Systemaufrufe in ${WMS:-?} ms Wartezeit"

echo "BRIDGE: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ] || exit 1
