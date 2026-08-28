#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/sshd/run.sh -- RUNDE SSHD: DER FERNZUGANG, GEGEN DEN ECHTEN
# OPENSSH-KLIENTEN.
#
# EHRLICHER AUSGANGSPUNKT, gemessen und nicht behauptet: vor dieser Runde
# fand `grep -ril ssh --include=*.fi` im ganzen Baum NULL Dateien. Es gab
# TLS 1.3 (Runde HWNET), Ed25519 (Runde UPDATE), X25519 und
# ChaCha20-Poly1305 (Runde TUNNEL) und seit Runde POLL den Aufruf, ohne
# den ein Dienst nicht zwei Dinge gleichzeitig bedienen kann -- aber kein
# SSH.
#
# ===================================================================
# WAS HIER DER BEWEIS IST, UND WAS NICHT
#
# NICHT der Beweis: ein selbstgeschriebener Klient. Zwei Enden, die
# dasselbe Missverstaendnis teilen, sind sich perfekt einig -- das ist
# die Versagensart jedes selbstgebauten Protokolls, und `tools/net/run.sh`
# hat aus demselben Grund gegen den Linux-Kernel gemessen und nicht gegen
# sich selbst.
#
# DER BEWEIS: `ssh` aus OpenSSH, unveraendert, von diesem Wirt aus, durch
# QEMUs Anschlussweiterleitung, gegen den Kernel unter `-accel kvm`. Was
# dieser Klient annimmt, ist SSH; was er ablehnt, ist keines. Dazu
# `ssh-keyscan` und `ssh-keygen -lf` als zweite Meinung ueber den
# Wirtsschluessel.
#
# ZEHN ZUSAGEN, jede mit einer Gegenprobe:
#
#   1. Die Bausteine stimmen mit den RFCs ueberein (Abschnitt 1, gegen
#      Python). Gegenprobe: ein gekipptes Bit wird abgelehnt.
#   2. Der Wirtsschluessel entsteht beim ersten Start und BLEIBT.
#      Gegenprobe: derselbe Datentraeger, zweiter Start, gleicher
#      Fingerabdruck -- und `ssh-keygen -lf` rechnet denselben aus.
#   3. Anmeldung mit SCHLUESSEL aus `~/.ssh/authorized_keys`.
#      Gegenprobe: ein anderer Schluessel wird abgelehnt, und derselbe
#      Schluessel wird auf einem Abbild OHNE `authorized_keys` ebenfalls
#      abgelehnt.
#   4. Anmeldung mit PASSWORT gegen `/etc/shadow` (Runde K13).
#      Gegenprobe: ein falsches Passwort und ein unbekannter Name.
#   5. Ein Befehl aus der Ferne, mit VERGLICHENER Ausgabe.
#   6. Der Beendigungscode des Befehls kommt beim Klienten an.
#   7. Eine Datei durch die Verbindung, SHA-256 auf beiden Seiten.
#   8. Eine Shell -- interaktiv ueber Rohre und an einem echten
#      Pseudoterminal.
#   9. ZWEI Verbindungen GLEICHZEITIG.
#  10. Als Dienst aus `/etc/inittab`, sichtbar in `/run/svc.state`.
#
# Aufruf:  bash tools/sshd/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
FC1=${FIRNC1:-vendor/firn/bin/firnc1}
LDSCRIPT=kernel/kernel.ld
ULD=kernel/user/user.ld
PROGS="sh ls cat echo id whoami sleep wc true false seq svc init sshd"
BLOCKS=4096
OSUM_IP=10.0.2.15
OSUM_GW=10.0.2.2
FWPORT=${FWPORT:-$(( 46000 + ($$ % 900) ))}

TMPD=$(mktemp -d)
cleanup() {
    pkill -f "file=$TMPD/live" 2>/dev/null
    rm -rf "$TMPD"
}
trap cleanup EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }

is() { # name ist soll
    if [ "$2" = "$3" ]; then ok "$1 ($2)"
    else bad "$1: '$2', erwartet '$3'"; fi
}

num() { # name wert op erwartet
    local name=$1 value=$2 op=$3 want=$4
    if [ -z "$value" ]; then bad "$name: keine Zahl (erwartet $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, erwartet $op $want"; fi
}

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh fehlgeschlagen"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc0 fehlt: $FIRNC"; exit 1; }
for t in qemu-system-x86_64 ssh ssh-keygen ssh-keyscan python3; do
    command -v "$t" >/dev/null 2>&1 || { echo "SSHD: uebersprungen, $t fehlt"; exit 0; }
done

# Seit Runde KVMFIX laeuft der Kern unter KVM (zwei echte Hardwarefehler,
# siehe KVMFIX-STATUS.md). Wo /dev/kvm da ist, wird es benutzt -- und wo
# nicht, sagt es der Laeufer, statt still langsamer zu messen.
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACCEL="-accel kvm"; ACCELNAME="kvm"
else
    ACCEL="-accel tcg"; ACCELNAME="tcg (kein /dev/kvm)"
fi

# =====================================================================
echo "== 1. die Bausteine gegen ihre RFCs (auf dem Wirt) =="
# =====================================================================
mkdir -p .probe
if $FIRNC tools/sshd/oracle.fi -o .probe/sshoracle 2>"$TMPD/e"; then
    ok "tools/sshd/oracle.fi baut gegen lib/crypto/ und lib/ssh/"
else
    bad "das Orakel baut nicht"; head -8 "$TMPD/e" | sed 's/^/        /'
fi
if [ -x .probe/sshoracle ]; then
    if python3 tools/sshd/vectors.py > "$TMPD/vec.txt" 2>&1; then
        ok "$(tail -1 "$TMPD/vec.txt")"
        grep -E '^  ' "$TMPD/vec.txt" | sed 's/^/     /'
    else
        bad "die Testvektoren sind durchgefallen"
        tail -25 "$TMPD/vec.txt" | sed 's/^/        /'
    fi
fi

# =====================================================================
echo "== 2. bauen: der Kern, $(echo $PROGS | wc -w) Programme, drei Abbilder =="
# =====================================================================
for f in boot isr switch smp hv; do
    as --64 -o "$TMPD/$f.o" "kernel/arch/x86_64/$f.s" 2>/dev/null \
        || bad "$f.s laesst sich nicht assemblieren"
done
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s"

build_stage() { # 0 = firnc0, 1 = firnc1
    local s=$1 cc p
    if [ "$s" = 0 ]; then cc="$FIRNC"; else cc="$FC1"; fi
    [ -x "$cc" ] || return 1
    "$cc" kernel/kmain.fi -o "$TMPD/k$s.o" >"$TMPD/e$s" 2>&1 \
        || { bad "firnc$s uebersetzt den Kern nicht"
             sed 's/^/        /' "$TMPD/e$s" | head -8; return 1; }
    "$cc" kernel/uprog.fi -o "$TMPD/u$s.o" >>"$TMPD/e$s" 2>&1 \
        || { bad "firnc$s uebersetzt uprog.fi nicht"; return 1; }
    ld -n -T "$LDSCRIPT" \
        --defsym=KERNEL_MAIN="_F$s.kernel_main" \
        --defsym=KERNEL_TRAP="_F$s.trap__entry" \
        --defsym=KERNEL_SYSCALL="_F$s.sys__entry" \
        --defsym=KERNEL_TASK_MAIN="_F$s.tasks__main" \
        --defsym=KERNEL_USER_START="_F$s.proc__user_start" \
        --defsym=KERNEL_AP_MAIN="_F$s.smp__ap_main" \
        --defsym=USER_MAIN="_F$s.u_enter" \
        -o "$TMPD/k$s.elf" "$TMPD/boot.o" "$TMPD/isr.o" "$TMPD/switch.o" \
        "$TMPD/smp.o" "$TMPD/hv.o" "$TMPD/k$s.o" "$TMPD/u$s.o" \
        2>"$TMPD/ld$s.err" \
        || { bad "firnc$s: ld ist am Kern gescheitert"; return 1; }
    objcopy -O elf32-i386 "$TMPD/k$s.elf" "$TMPD/k$s.mb" 2>/dev/null
    for p in $PROGS; do
        "$cc" "kernel/user/$p.fi" -o "$TMPD/$p$s.o" >"$TMPD/e$p$s" 2>&1 \
            || { bad "firnc$s uebersetzt $p.fi nicht"
                 sed 's/^/        /' "$TMPD/e$p$s" | head -6; return 1; }
        ld -T "$ULD" --defsym=USER_ENTRY="_F$s.u_start" \
            -o "$TMPD/$p$s.elf" "$TMPD/crt.o" "$TMPD/$p$s.o" 2>/dev/null \
            || { bad "firnc$s: ld ist an $p gescheitert"; return 1; }
        strip --strip-all "$TMPD/$p$s.elf"
    done
    return 0
}
build_stage 0 || { echo "SSHD: $pass passed, $fail failed"; exit 1; }
ok "firnc0: Kern + $(echo $PROGS | wc -w) Programme"
if build_stage 1; then
    ok "firnc1: dasselbe, aus dem in Firn geschriebenen Uebersetzer"
else
    note "firnc1 hat nicht gebaut -- gemessen wird mit firnc0"
fi

undef=$(nm -u "$TMPD/sshd0.elf" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
[ -z "$undef" ] && ok "/sbin/sshd hat keinen undefinierten Namen" \
                || bad "undefinierte Namen in sshd: $undef"
note "/sbin/sshd: $(stat -c%s "$TMPD/sshd0.elf") Oktette"

# --- die Benutzer, die Schluessel, die Daten
python3 - "$TMPD" <<'PY'
import binascii, hashlib, sys
d = sys.argv[1]
def rec(pw, salt):
    dk = hashlib.pbkdf2_hmac('sha256', pw, salt, 2048, 32)
    return "$osum1$2048$%s$%s" % (binascii.hexlify(salt).decode(),
                                  binascii.hexlify(dk).decode())
open(d + "/passwd", "w").write(
    "root:x:0:0:root:/:/bin/sh\n"
    "justin:x:1000:1000:Justin:/home/justin:/bin/sh\n")
open(d + "/shadow", "w").write(
    "root:%s:0:0:99999:7:::\n" % rec(b"rootpass", bytes(range(8))) +
    "justin:%s:0:0:99999:7:::\n" % rec(b"geheim12", bytes(range(8, 16))))
PY
ssh-keygen -q -t ed25519 -N '' -f "$TMPD/id_ed25519" -C sshdtest
ssh-keygen -q -t ed25519 -N '' -f "$TMPD/wrong_ed25519" -C wrongkey
cp "$TMPD/id_ed25519.pub" "$TMPD/authorized_keys"
head -c 20000 /dev/urandom > "$TMPD/blob.bin"
BLOBSUM=$(sha256sum "$TMPD/blob.bin" | cut -d' ' -f1)
printf 'zeile eins\nzeile zwei\nzeile drei\n' > "$TMPD/data.txt"
printf '# name:art:befehl\nsshd:respawn:/sbin/sshd -v\nende:ctrl:/bin/sleep 600\n' \
    > "$TMPD/inittab"
cat > "$TMPD/askpass.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$OSUM_PW"
EOF
chmod +x "$TMPD/askpass.sh"

DIRS="/bin/ /sbin/ /etc/ /etc/ssh/@700:0:0 /run/@755:0:0 /home/@755:0:0
      /home/justin/@755:1000:1000 /home/justin/.ssh/@700:1000:1000 /d/"
SPEC=""
for p in $PROGS; do
    case $p in
        init) SPEC="$SPEC /sbin/init=$TMPD/${p}0.elf@755:0:0" ;;
        sshd) SPEC="$SPEC /sbin/sshd=$TMPD/${p}0.elf@755:0:0" ;;
        *)    SPEC="$SPEC /bin/$p=$TMPD/${p}0.elf" ;;
    esac
done
ETC="/etc/passwd=$TMPD/passwd@644:0:0 /etc/shadow=$TMPD/shadow@600:0:0
     /etc/inittab=$TMPD/inittab@644:0:0"
AK="/home/justin/.ssh/authorized_keys=$TMPD/authorized_keys@600:1000:1000"
DATA="/d/data.txt=$TMPD/data.txt@644:0:0 /d/blob.bin=$TMPD/blob.bin@644:0:0"

python3 tools/osum/mkfs.py build "$TMPD/disk.img" $BLOCKS \
    $DIRS $SPEC $ETC $AK $DATA > "$TMPD/mkfs.txt" 2>&1 \
    && ok "mkfs.py baut das Abbild MIT ~/.ssh/authorized_keys" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt"; }
# DAS GEGENSTUECK: dasselbe Abbild OHNE die Schluesseldatei. Ohne dieses
# zweite Abbild waere „der Schluessel wird angenommen" keine Aussage --
# ein Server, der JEDEN Schluessel annimmt, bestuende den ersten Test
# ebenso.
python3 tools/osum/mkfs.py build "$TMPD/nokeys.img" $BLOCKS \
    $DIRS $SPEC $ETC $DATA >/dev/null 2>&1 \
    && ok "und ein zweites OHNE sie (die Gegenprobe zu Abschnitt 4)" \
    || bad "das zweite Abbild ist nicht entstanden"

# =====================================================================
# Der Draht: QEMUs Benutzernetz mit einer Weiterleitung. Das braucht
# keine Netzwerknamensraeume und keine Rechte -- anders als
# tools/net/run.sh, das den Stapel auf einem veth-Paar misst. Hier geht
# es nicht um den Stapel, sondern um das Protokoll darueber.
# =====================================================================
QPID=""
SER=""
start_osum() { # abbild serielldatei port
    local img=$1 ser=$2 port=$3
    rm -f "$ser"
    SER="$ser"
    timeout 900 qemu-system-x86_64 $ACCEL -kernel "$TMPD/k0.mb" -m 512 \
        -append "osum nokbd nic nip=$OSUM_IP/24 ngw=$OSUM_GW" \
        -serial "file:$ser" -display none -no-reboot \
        -drive "file=$img,format=raw,if=ide,index=0" \
        -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$port-$OSUM_IP:22" \
        -device "virtio-net-pci,netdev=n0,mac=52:54:00:5b:1d:01" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    QPID=$!
    local i=0
    while [ $i -lt 600 ]; do
        [ -f "$ser" ] && grep -qa 'sshd: listening' "$ser" && return 0
        kill -0 "$QPID" 2>/dev/null || return 1
        sleep 0.2; i=$((i+1))
    done
    return 1
}
stop_osum() {
    [ -n "$QPID" ] && kill "$QPID" 2>/dev/null
    wait "$QPID" 2>/dev/null
    QPID=""
}

SSHO="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
      -o GlobalKnownHostsFile=/dev/null -o ConnectTimeout=30
      -o LogLevel=ERROR -o BatchMode=no"
KEYOPT="-o IdentitiesOnly=yes -i $TMPD/id_ed25519"
BADKEY="-o IdentitiesOnly=yes -i $TMPD/wrong_ed25519"

as_key() { # befehl...
    timeout 300 ssh -p "$FWPORT" $SSHO $KEYOPT -o PasswordAuthentication=no \
        justin@127.0.0.1 "$@"
}
as_pw() { # benutzer passwort befehl...
    local u=$1 p=$2; shift 2
    OSUM_PW="$p" SSH_ASKPASS="$TMPD/askpass.sh" SSH_ASKPASS_REQUIRE=force \
    timeout 300 ssh -p "$FWPORT" $SSHO -o PubkeyAuthentication=no \
        -o PreferredAuthentications=password -o NumberOfPasswordPrompts=1 \
        "$u@127.0.0.1" "$@"
}

# =====================================================================
echo "== 3. der Wirtsschluessel: erzeugt, dauerhaft, und was OpenSSH dazu sagt ($ACCELNAME) =="
# =====================================================================
cp "$TMPD/disk.img" "$TMPD/live.img"
T0=$(date +%s%N)
if start_osum "$TMPD/live.img" "$TMPD/run1.txt" "$FWPORT"; then
    T1=$(date +%s%N)
    ok "der Dienst lauscht auf Anschluss 22 (nach $(( (T1-T0)/1000000 )) ms, mit $ACCELNAME)"
else
    bad "sshd hat nicht angefangen zu lauschen"
    tr -d '\000' < "$TMPD/run1.txt" 2>/dev/null | tail -12 | sed 's/^/        /'
    stop_osum
    echo "SSHD: $pass passed, $fail failed"
    exit 1
fi
F="$TMPD/run1.txt"
grep -qa 'sshd: generating a host key' "$F" \
    && ok "es gab noch keinen Wirtsschluessel -- er wurde beim ersten Start erzeugt" \
    || bad "die Zeile ueber die Erzeugung fehlt"
FP1=$(grep -a -m1 'sshd: host key SHA256:' "$F" | sed 's/.*SHA256://')
[ -n "$FP1" ] && ok "sshd nennt seinen Fingerabdruck: SHA256:$FP1" \
              || bad "kein Fingerabdruck auf der Konsole"

# ZWEITE MEINUNG NUMMER EINS: `ssh-keyscan` holt den Schluessel ueber das
# Protokoll, `ssh-keygen -lf` rechnet den Fingerabdruck. Beide Programme
# gehoeren OpenSSH und nicht diesem Repo.
# `-t ed25519`: ohne die Angabe fragt ssh-keyscan NACHEINANDER nach
# rsa, ecdsa und ed25519 -- drei Verbindungen, von denen dieser Server
# zwei richtigerweise beim Schluesselaustausch abweist, weil er nur
# ssh-ed25519 hat. Das ist kein Fehler, kostet aber drei Zeitlimits.
ssh-keyscan -t ed25519 -T 45 -p "$FWPORT" 127.0.0.1 \
    > "$TMPD/scan.txt" 2>"$TMPD/scan.err"
if [ -s "$TMPD/scan.txt" ]; then
    ok "ssh-keyscan holt den Wirtsschluessel ueber das Protokoll"
    FP2=$(ssh-keygen -lf "$TMPD/scan.txt" 2>/dev/null | awk '{print $2}' \
          | sed 's/^SHA256://')
    is "ssh-keygen rechnet denselben Fingerabdruck" "$FP2" "$FP1"
    is "und der Schluesseltyp ist der zugesagte" \
       "$(ssh-keygen -lf "$TMPD/scan.txt" 2>/dev/null | awk '{print $NF}' | tr -d '()')" \
       "ED25519"
else
    bad "ssh-keyscan hat nichts bekommen"
    head -3 "$TMPD/scan.err" | sed 's/^/        /'
fi

# =====================================================================
echo "== 4. der ECHTE ssh-Klient: anmelden, arbeiten, Daten =="
# =====================================================================
echo "   -- Anmeldung mit Schluessel aus ~/.ssh/authorized_keys"
out=$(as_key 'echo HALLO; whoami; id' 2>"$TMPD/e1"); rc=$?
num "ssh mit Schluessel kommt durch (Beendigungscode)" "$rc" eq 0
is "die Ausgabe des Fernbefehls, Zeile 1" "$(echo "$out" | sed -n 1p)" "HALLO"
is "...Zeile 2: der Server hat wirklich setuid gemacht" \
   "$(echo "$out" | sed -n 2p)" "justin"
is "...Zeile 3: die Kennungen aus /etc/passwd" \
   "$(echo "$out" | sed -n 3p)" \
   "uid=1000(justin) gid=1000 euid=1000(justin) egid=1000"
grep -qa 'sshd: publickey accepted' "$F" \
    && ok "und der Server hat es als publickey-Anmeldung verbucht" \
    || bad "die Zeile 'publickey accepted' fehlt"

echo "   -- die ausgehandelten Verfahren, aus der Sicht des Klienten"
timeout 300 ssh -vv -p "$FWPORT" $SSHO $KEYOPT -o PasswordAuthentication=no \
    justin@127.0.0.1 true > /dev/null 2>"$TMPD/verb.txt"
# `tr -d '\r'`: ssh schreibt seine Debugzeilen mit CRLF, und ein
# unsichtbares CR am Ende macht aus zwei gleichen Zeichenketten zwei
# verschiedene. GEMESSEN -- der erste Abnahmelauf meldete woertlich
# 'curve25519-sha256' != 'curve25519-sha256'.
kexline=$(grep -a -m1 'debug1: kex: algorithm:' "$TMPD/verb.txt" \
          | tr -d '\r' | sed 's/.*: //')
hostline=$(grep -a -m1 'debug1: kex: host key algorithm:' "$TMPD/verb.txt" \
          | tr -d '\r' | sed 's/.*: //')
encline=$(grep -a -m1 'debug1: kex: server->client cipher:' "$TMPD/verb.txt" \
          | tr -d '\r' | sed 's/.*cipher: //;s/ MAC.*//')
is "der Klient sagt: Schluesselaustausch" "$kexline" "curve25519-sha256"
is "der Klient sagt: Wirtsschluessel" "$hostline" "ssh-ed25519"
is "der Klient sagt: Chiffre server->client" "$encline" \
   "chacha20-poly1305@openssh.com"
if grep -qa 'resetting send seqnr' "$TMPD/verb.txt"; then
    ok "strict kex (die Gegenmassnahme gegen Terrapin) wurde ausgehandelt"
else
    note "dieser Klient bietet kein strict kex an -- dann bleibt es aus"
fi

echo "   -- Anmeldung mit Passwort gegen /etc/shadow"
out=$(as_pw justin geheim12 'echo PWOK; whoami' 2>"$TMPD/e2"); rc=$?
num "ssh mit Passwort kommt durch" "$rc" eq 0
is "die Ausgabe" "$(echo "$out" | sed -n 1p)" "PWOK"
is "und es ist derselbe Benutzer" "$(echo "$out" | sed -n 2p)" "justin"
out=$(as_pw root rootpass 'whoami' 2>/dev/null)
is "auch root meldet sich mit seinem Passwort an" "$out" "root"

echo "   -- der Beendigungscode kommt beim Klienten an"
as_key 'exit 7' >/dev/null 2>&1
num "ssh gibt den Code des Fernbefehls zurueck" "$?" eq 7
as_key 'true' >/dev/null 2>&1
num "und 0 fuer einen Befehl, der gelingt" "$?" eq 0

echo "   -- eine Datei durch die Verbindung, SHA-256 auf beiden Seiten"
# ZUERST die LEERE Sitzung messen. Was ein `ssh host cat datei` braucht,
# ist Sitzungsaufbau PLUS Uebertragung; ohne die erste Zahl waere die
# zweite nicht zu haben, und „20000 Oktette in 16 Sekunden" waere eine
# Aussage ueber X25519 und nicht ueber den Durchsatz.
TL0=$(date +%s%N)
as_key 'true' >/dev/null 2>&1
TL1=$(date +%s%N)
LEER=$(( (TL1-TL0)/1000000 ))
TB0=$(date +%s%N)
as_key 'cat /d/blob.bin' > "$TMPD/got.bin" 2>"$TMPD/e3"; rc=$?
TB1=$(date +%s%N)
num "der Fernbefehl cat kommt durch" "$rc" eq 0
is "die Zahl der Oktette" "$(stat -c%s "$TMPD/got.bin")" \
   "$(stat -c%s "$TMPD/blob.bin")"
GOTSUM=$(sha256sum "$TMPD/got.bin" | cut -d' ' -f1)
is "der SHA-256 der durchgereichten Datei" "$GOTSUM" "$BLOBSUM"
MS=$(( (TB1-TB0)/1000000 ))
NETTO=$(( MS - LEER ))
[ "$NETTO" -lt 1 ] && NETTO=1
note "eine LEERE Sitzung (Anmeldung, ein Befehl, Schluss): $LEER ms"
note "$(stat -c%s "$TMPD/blob.bin") Oktette in $MS ms -- abzueglich der leeren Sitzung"
note "$NETTO ms fuer die Nutzdaten, also rund $(( $(stat -c%s "$TMPD/blob.bin") * 1000 / NETTO )) Oktette/s"
num "die Uebertragung ist schneller als 1000 Oktette/s" \
    "$(( $(stat -c%s "$TMPD/blob.bin") * 1000 / NETTO ))" ge 1000

echo "   -- eine Shell: ueber Rohre und an einem Pseudoterminal"
printf 'echo S1\nls /d\nexit\n' | timeout 300 ssh -p "$FWPORT" $SSHO -T \
    $KEYOPT justin@127.0.0.1 > "$TMPD/shell.txt" 2>&1
num "die Shell-Sitzung (ssh -T) endet ordentlich" "$?" eq 0
grep -qa '^S1' "$TMPD/shell.txt" && ok "die Shell hat den ersten Befehl ausgefuehrt" \
                                || bad "'S1' fehlt in der Shell-Sitzung"
grep -qa 'blob.bin' "$TMPD/shell.txt" && ok "und den zweiten (ls /d)" \
                                      || bad "'ls /d' hat nichts geliefert"
grep -qa 'sh: ready' "$TMPD/shell.txt" && ok "es war wirklich /bin/sh und kein Nachbau" \
                                       || bad "die Begruessung von /bin/sh fehlt"
printf 'echo P1\nexit\n' | timeout 300 ssh -p "$FWPORT" $SSHO -tt \
    $KEYOPT justin@127.0.0.1 > "$TMPD/pty.txt" 2>&1
num "die Sitzung am Pseudoterminal (ssh -tt) endet ordentlich" "$?" eq 0
grep -qa 'P1' "$TMPD/pty.txt" && ok "sie hat den Befehl ausgefuehrt" \
                             || bad "'P1' fehlt in der pty-Sitzung"
# DER UNTERSCHIED, an dem man sieht, dass es WIRKLICH ein Terminal war:
# die Zeilendisziplin haengt vor jedes \n ein \r (ONLCR), und sie hat
# das Getippte zurueckgeworfen (ECHO). Ueber ein Rohr passiert beides
# nicht.
if grep -qa $'\r' "$TMPD/pty.txt"; then
    ok "die Zeilenenden tragen CR -- die Zeilendisziplin des Terminals war dran"
else
    bad "kein CR in der pty-Sitzung: da war kein Pseudoterminal"
fi
if grep -qa $'\r' "$TMPD/shell.txt"; then
    bad "die Rohr-Sitzung hat CR -- dann war die Unterscheidung keine"
else
    ok "und die Rohr-Sitzung hat keines (der Gegenbeweis zum vorigen)"
fi

echo "   -- zwei Verbindungen GLEICHZEITIG"
( as_key 'echo EINS; sleep 2; echo EINSB' > "$TMPD/p1.txt" 2>&1
  echo $? > "$TMPD/p1.rc" ) &
P1=$!
( as_key 'echo ZWEI; sleep 2; echo ZWEIB' > "$TMPD/p2.txt" 2>&1
  echo $? > "$TMPD/p2.rc" ) &
P2=$!
wait $P1 $P2
num "die erste Sitzung" "$(cat "$TMPD/p1.rc" 2>/dev/null)" eq 0
num "die zweite Sitzung" "$(cat "$TMPD/p2.rc" 2>/dev/null)" eq 0
is "und beide haben ihre eigene Ausgabe bekommen" \
   "$(tr '\n' ' ' < "$TMPD/p1.txt")$(tr '\n' ' ' < "$TMPD/p2.txt")" \
   "EINS EINSB ZWEI ZWEIB "

# =====================================================================
echo "== 5. die Gegenproben: was ABGELEHNT werden muss =="
# =====================================================================
timeout 120 ssh -p "$FWPORT" $SSHO $BADKEY -o PasswordAuthentication=no \
    -o PreferredAuthentications=publickey justin@127.0.0.1 'echo DARFNICHT' \
    > "$TMPD/bad1.txt" 2>&1
rc=$?
num "ein FREMDER Schluessel wird abgelehnt (ssh-Code)" "$rc" ne 0
grep -qa 'DARFNICHT' "$TMPD/bad1.txt" \
    && bad "der Befehl lief TROTZDEM -- das waere ein offener Server" \
    || ok "und der Befehl ist nicht gelaufen"
grep -qa 'Permission denied' "$TMPD/bad1.txt" \
    && ok "ssh nennt den Grund: Permission denied" \
    || note "ssh sagt: $(tail -1 "$TMPD/bad1.txt")"

as_pw justin falsch99 'echo DARFNICHT' > "$TMPD/bad2.txt" 2>&1
rc=$?
num "ein falsches PASSWORT wird abgelehnt" "$rc" ne 0
grep -qa 'DARFNICHT' "$TMPD/bad2.txt" \
    && bad "der Befehl lief trotz falschem Passwort" \
    || ok "und der Befehl ist nicht gelaufen"

as_pw niemand egal 'echo DARFNICHT' > "$TMPD/bad3.txt" 2>&1
rc=$?
num "ein unbekannter Benutzername wird abgelehnt" "$rc" ne 0
grep -qa 'DARFNICHT' "$TMPD/bad3.txt" \
    && bad "ein Name, den /etc/passwd nicht kennt, kam durch" \
    || ok "ein Name, den /etc/passwd nicht kennt, kommt nicht durch"

timeout 120 ssh -p "$FWPORT" $SSHO $KEYOPT -o Ciphers=aes128-ctr \
    justin@127.0.0.1 true > "$TMPD/bad4.txt" 2>&1
num "ein Klient ohne gemeinsame Chiffre wird abgewiesen" "$?" ne 0
timeout 120 ssh -p "$FWPORT" $SSHO $KEYOPT \
    -o KexAlgorithms=diffie-hellman-group14-sha256 \
    justin@127.0.0.1 true > "$TMPD/bad5.txt" 2>&1
num "ein Klient ohne gemeinsamen Schluesselaustausch ebenso" "$?" ne 0

# =====================================================================
echo "== 6. als DIENST, und der Weg ueber init =="
# =====================================================================
grep -qa 'init: dienste=2' "$F" \
    && ok "init hat /etc/inittab gelesen und zwei Dienste gefunden" \
    || bad "init hat die Dienste nicht gefunden"
out=$(as_pw root rootpass 'cat /run/svc.state' 2>/dev/null)
if echo "$out" | grep -qa '^sshd running'; then
    ok "und /run/svc.state fuehrt sshd als laufenden Dienst"
    note "$(echo "$out" | tr '\n' ' ')"
else
    bad "sshd steht nicht als laufender Dienst in /run/svc.state"
    note "$(echo "$out" | tr '\n' ' ')"
fi
# WIE OFT WURDE ER NEU GESTARTET? Ein Dienst, der bei jeder Verbindung
# stirbt und von `init` wieder hochgezogen wird, sieht von aussen aus wie
# einer, der laeuft. Die Zahl hinter dem Zustand ist die der Starts, und
# sie muss 1 sein.
starts=$(echo "$out" | awk '/^sshd /{print $4}')
is "Zahl der Starts des Dienstes (1 = er ist nie gestorben)" "${starts:-?}" "1"
conns=$(grep -ac 'sshd: accepted from' "$F")
num "angenommene Verbindungen in diesem Lauf" "$conns" ge 12
polls=$(grep -a 'sshd: polls =' "$F" | sed 's/.*= //' | sort -n | tail -1)
num "die groesste Zahl von poll-Durchlaeufen EINER Sitzung (eine Warteschleife haette Tausende)" \
    "${polls:-99999}" le 400
# Die Zeile lautet:  sshd: ms vkx a <version> <kex> <auth>
kexms=$(grep -a 'sshd: ms vkx a' "$F" | awk '{print $6}' | sort -n | tail -1)
authms=$(grep -a 'sshd: ms vkx a' "$F" | awk '{print $7}' | sort -n | tail -1)
note "langsamster Schluesselaustausch: ${kexms:-?} ms, langsamste Anmeldung: ${authms:-?} ms"

# =====================================================================
echo "== 7. das Herunterfahren, und der Kern lebt noch =="
# =====================================================================
as_pw root rootpass 'svc shutdown' > "$TMPD/down.txt" 2>&1
i=0
while [ $i -lt 100 ]; do
    kill -0 "$QPID" 2>/dev/null || break
    sleep 0.2; i=$((i+1))
done
if kill -0 "$QPID" 2>/dev/null; then
    bad "'svc shutdown' ueber ssh hat das System nicht heruntergefahren"
    stop_osum
else
    wait "$QPID" 2>/dev/null
    QRC=$?
    QPID=""
    ok "'svc shutdown' aus der Ferne hat das System heruntergefahren (QEMU-Code $QRC)"
fi
if grep -qa 'EXCEPTION' "$F"; then
    bad "im Lauf steht eine Ausnahme"
    grep -a -m3 'EXCEPTION' "$F" | sed 's/^/        /'
else
    ok "kein einziger Prozessorfehler im ganzen Lauf"
fi

# =====================================================================
echo "== 8. der ZWEITE Start: derselbe Wirtsschluessel =="
# =====================================================================
# Derselbe Datentraeger, nicht noch einmal aus disk.img kopiert -- sonst
# waere der Schluessel wieder weg und der Test bewiese nichts.
if start_osum "$TMPD/live.img" "$TMPD/run2.txt" "$FWPORT"; then
    ok "der Dienst laeuft wieder"
    G="$TMPD/run2.txt"
    grep -qa 'sshd: generating a host key' "$G" \
        && bad "er hat einen NEUEN Schluessel erzeugt -- dann war er nicht dauerhaft" \
        || ok "und hat KEINEN neuen Schluessel erzeugt"
    FP3=$(grep -a -m1 'sshd: host key SHA256:' "$G" | sed 's/.*SHA256://')
    is "derselbe Fingerabdruck wie beim ersten Start" "$FP3" "$FP1"
    out=$(as_key 'echo ZWEITERSTART' 2>/dev/null)
    is "und derselbe Schluessel meldet sich weiter an" "$out" "ZWEITERSTART"
    # Die dritte Meinung: die Datei auf der Platte, gelesen vom WIRT.
    python3 tools/osum/mkfs.py cat "$TMPD/live.img" \
        /etc/ssh/ssh_host_ed25519.pub > "$TMPD/hostpub.txt" 2>/dev/null
    if [ -s "$TMPD/hostpub.txt" ]; then
        FP4=$(ssh-keygen -lf "$TMPD/hostpub.txt" 2>/dev/null | awk '{print $2}' \
              | sed 's/^SHA256://')
        is "ssh-keygen -lf auf der .pub-Datei AUF DER PLATTE" "$FP4" "$FP1"
    else
        bad "/etc/ssh/ssh_host_ed25519.pub steht nicht auf der Platte"
    fi
    as_pw root rootpass 'svc shutdown' >/dev/null 2>&1
    i=0
    while [ $i -lt 100 ]; do kill -0 "$QPID" 2>/dev/null || break; sleep 0.2; i=$((i+1)); done
    stop_osum
else
    bad "der zweite Start ist nicht hochgekommen"
    stop_osum
fi

# =====================================================================
echo "== 9. OHNE authorized_keys: derselbe Schluessel wird abgelehnt =="
# =====================================================================
# Das ist die Gegenprobe, die aus „der Schluessel wurde angenommen" eine
# Aussage macht. Gleicher Kern, gleiches Passwort, gleicher Schluessel --
# nur die Datei fehlt.
cp "$TMPD/nokeys.img" "$TMPD/live2.img"
if start_osum "$TMPD/live2.img" "$TMPD/run3.txt" "$FWPORT"; then
    timeout 120 ssh -p "$FWPORT" $SSHO $KEYOPT -o PasswordAuthentication=no \
        -o PreferredAuthentications=publickey justin@127.0.0.1 'echo DARFNICHT' \
        > "$TMPD/nk.txt" 2>&1
    num "derselbe Schluessel OHNE authorized_keys: abgelehnt" "$?" ne 0
    grep -qa 'DARFNICHT' "$TMPD/nk.txt" \
        && bad "er kam trotzdem durch -- dann wird die Datei gar nicht gelesen" \
        || ok "und der Befehl ist nicht gelaufen"
    out=$(as_pw justin geheim12 'echo NURPASSWORT' 2>/dev/null)
    is "das Passwort geht auf demselben Abbild weiter" "$out" "NURPASSWORT"
    as_pw root rootpass 'svc shutdown' >/dev/null 2>&1
    i=0
    while [ $i -lt 100 ]; do kill -0 "$QPID" 2>/dev/null || break; sleep 0.2; i=$((i+1)); done
    stop_osum
else
    bad "das Abbild ohne Schluesseldatei ist nicht hochgekommen"
    stop_osum
fi

echo
# Die Schlusszeile in der Form, die `zusagen()` in ./test.sh liest --
# sonst faellt die Zahl dieser Runde still unter den Tisch.
echo "SSHD: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
