#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bruecke/https443.sh -- RUNDE MERGE-11: OSUM SPRICHT SELBST
# HTTPS MIT store.fleitec.com.
#
# ====================================================================
# WAS DIESER LAEUFER BEWEIST, UND WARUM ES IHN BRAUCHT
# ====================================================================
#
# `tools/bruecke/kette.sh` stellt einen Anschluss in einen NETZRAUM auf
# demselben Rechner. Das misst das Protokoll -- aber nicht den Weg, den
# Justins Rechner wirklich nehmen muss. Der steht in einem FREMDEN
# Heimnetz hinter NAT; dorthin gibt es keine Portfreigabe, und deshalb
# hat sich sein Geraet nie gemeldet: im Koppelbuch standen am
# 10.09.2026 nur zwei Pruefstaende aus dem Hausnetz, beide gesperrt.
#
# Dieser Laeufer nimmt den ECHTEN Weg:
#
#   Osum in QEMU (Benutzernetz, also NAT wie bei Justin)
#     -> DNS auf store.fleitec.com
#     -> TLS 1.3 mit dem ECHTEN Zertifikat, gegen /etc/ssl/roots.pem
#     -> POST /bruecke/draht auf Port 443
#     -> openresty (.51) -> diagnose_server.py -> bruecke_server.py
#
# Nichts davon ist gestellt. Faellt irgendein Glied aus, faellt der
# Lauf durch.
#
# WAS ER MISST:
#   1. der Name loest auf                    (DNS aus lib/libc/dns.fi)
#   2. der Handschlag steht                  (echtes Zertifikat)
#   3. der Server antwortet 200
#   4. ein unbekanntes Geraet bekommt einen KOPPLUNGSCODE
#   5. der Code steht im Protokoll des Dienstes -- die Zeile, die
#      Justin vorlesen wird
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
W=${HTTPS_W:-/tmp/bruecke-https443}
rm -rf "$W"; mkdir -p "$W"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }

command -v qemu-system-x86_64 >/dev/null || { echo "kein qemu"; exit 0; }

echo "== 1. bauen =="
bash vendor/firn/fetch-firnc.sh > "$W/fetch.log" 2>&1 || {
    echo "fetch-firnc.sh gescheitert"; exit 1; }
./tools/build-kernel.sh "$W/k0.mb" > "$W/k.log" 2>&1 || {
    echo "der Kern baut nicht"; tail -20 "$W/k.log"; exit 1; }
note "kernel $(stat -c%s "$W/k0.mb") Oktette"

as --64 -o "$W/crt.o" kernel/user/crt.s 2>"$W/as.err" || {
    echo "crt.s"; cat "$W/as.err"; exit 1; }
for p in sh ls cat echo jsig jarvisctl dhcp host ping; do
    vendor/firn/bin/firnc "kernel/user/$p.fi" -o "$W/$p.o" \
        > "$W/e-$p" 2>&1 || { echo "$p baut nicht"; head -20 "$W/e-$p"; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
        -o "$W/$p.elf" "$W/crt.o" "$W/$p.o" 2>"$W/ld-$p" || {
        echo "$p bindet nicht"; cat "$W/ld-$p"; exit 1; }
    strip --strip-all "$W/$p.elf"
done
# jarvisd ist eine `app`: anderes Profil, FIRNLIB aus DIESEM Baum.
FIRNLIB="$ROOT/lib" vendor/firn/bin/firnc -c --profile=app \
    -o "$W/jarvisd.o" kernel/app/jarvisd.fi > "$W/e-jarvisd" 2>&1 || {
    echo "jarvisd baut nicht"; head -30 "$W/e-jarvisd"; exit 1; }
ld -T kernel/user/user.ld -o "$W/jarvisd.elf" "$W/jarvisd.o" \
    2>"$W/ld-jarvisd" || { echo "jarvisd bindet nicht"; cat "$W/ld-jarvisd"; exit 1; }
strip --strip-all "$W/jarvisd.elf"
ok "jarvisd gebaut ($(stat -c%s "$W/jarvisd.elf") Oktette)"

# ------------------------------------------------ die Rechteliste
# GENAU DIE, DIE AUCH AUF JUSTINS STICK LIEGT -- `weg = https`, ein
# NAME statt einer Zahl, und nichts von Hand einzutragen.
cat > "$W/rechte.conf" <<'CONF'
weg            = https
servername     = store.fleitec.com
pfad           = /bruecke/draht
wurzeln        = /etc/ssl/roots.pem
befehle        = nein
bildschirmfoto = ja
systeminfo     = ja
eingabe        = nein
max_ausgabe    = 65536
max_datei      = 4194304
protokoll       = /var/log/jarvisd.log
arbeitsdatei    = /var/jarvis/ausgabe.txt
fotoscheindatei = /var/jarvis/fotoschein
CONF

# Der ECHTE Wurzelspeicher -- ohne ihn wird nichts vertraut.
for c in /etc/ssl/certs/ca-certificates.crt \
         /etc/pki/tls/certs/ca-bundle.crt; do
    [ -r "$c" ] && { cp "$c" "$W/roots.pem"; break; }
done
[ -s "$W/roots.pem" ] || { echo "kein Wurzelspeicher auf dem Wirt"; exit 1; }
note "wurzeln $(stat -c%s "$W/roots.pem") Oktette"

# ------------------------------------------------ /etc/resolv.conf
# OHNE DIESE DATEI GIBT ES KEINE NAMENSAUFLOESUNG, und der Fehler sieht
# aus wie ein Netzfehler: `jarvisd: der Name laesst sich nicht
# aufloesen`, obwohl Karte, Verbindung und Stapel stehen. Gemessen in
# genau diesem Laeufer, erster Anlauf.
#
# 10.0.2.3 ist der Namensdienst von QEMUs Benutzernetz (10.0.2.2 ist
# der Router, 10.0.2.15 der Gast). Auf Justins Stick schreibt `/bin/dhcp`
# diese Datei aus dem Lease -- hier steht sie fest, weil dieser Lauf
# das DNS misst und nicht den DHCP.
printf 'nameserver 10.0.2.3\n' > "$W/resolv.conf"

SPEC="/bin/ /etc/ /etc/ssl/ /etc/jarvis/ /var/ /var/log/ /var/jarvis/"
for p in sh ls cat echo jsig jarvisctl dhcp host ping jarvisd; do
    SPEC="$SPEC /bin/$p=$W/$p.elf"
done
SPEC="$SPEC /etc/jarvis/rechte.conf=$W/rechte.conf"
SPEC="$SPEC /etc/ssl/roots.pem=$W/roots.pem"
SPEC="$SPEC /etc/resolv.conf=$W/resolv.conf"
python3 tools/osum/mkfs.py build "$W/probe.img" 32768 $SPEC \
    > "$W/mkfs.txt" 2>&1 || { echo "mkfs"; tail -5 "$W/mkfs.txt"; exit 1; }
ok "Platte gebaut"

echo "== 2. Osum faehrt und spricht mit store.fleitec.com =="
# QEMUs Benutzernetz ist NAT -- dieselbe Lage wie bei Justin: der Gast
# kommt hinaus, von aussen kommt niemand herein.
timeout 300 qemu-system-x86_64 -kernel "$W/k0.mb" -m 512 \
    -append "osum nokbd nosched noproc nofs modfs nic nip=169.254.10.1/16 nsvc=0 nwait=0 dhcp script=dhcp;jarvisd -v -1" \
    -serial "file:$W/serial.txt" -display none -no-reboot \
    -drive "file=$W/probe.img,format=raw,if=ide,index=0" \
    -netdev user,id=n0 -device e1000,netdev=n0 \
    > "$W/qemu.log" 2>&1 &
QPID=$!
i=0
while [ $i -lt 900 ]; do
    grep -qa 'jarvisd:' "$W/serial.txt" 2>/dev/null && break
    kill -0 "$QPID" 2>/dev/null || break
    sleep 0.2; i=$((i+1))
done
sleep 60
kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null

echo "== 3. was auf der Leitung stand =="
grep -a 'jarvisd:' "$W/serial.txt" | head -20 | sed 's/^/        /'

grep -qa 'jarvisd:.*[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' "$W/serial.txt" \
    && ok "der Name store.fleitec.com ist aufgeloest" \
    || bad "der Name loest nicht auf"
grep -qa 'Handschlag ist gescheitert' "$W/serial.txt" \
    && bad "der TLS-Handschlag ist gescheitert" \
    || ok "der Handschlag mit dem ECHTEN Zertifikat steht"
grep -qa 'der Server antwortet' "$W/serial.txt" \
    && bad "der Server hat nicht 200 geantwortet" \
    || ok "der Server antwortet 200"
grep -qa 'KOPPLUNGSCODE' "$W/serial.txt" \
    && ok "das Geraet ist beim Dienst angekommen und zeigt einen Code" \
    || bad "das Geraet ist NICHT angekommen"
# Der Code, den Justin vorlesen wird -- als Klartext, nicht als Hex.
HEX=$(grep -a 'KOPPLUNGSCODE' "$W/serial.txt" | tail -1 | awk '{print $NF}')
if [ -n "$HEX" ]; then
    note "Code auf dem Bildschirm: $(python3 -c "import sys;print(bytes.fromhex(sys.argv[1]).decode())" "$HEX" 2>/dev/null)"
fi

echo "== 4. und was der Dienst dazu sagt =="
journalctl -u bruecke --since '-3 min' --no-pager 2>/dev/null \
    | grep -iE 'KOPPLUNG NOETIG|ANGEMELDET|ABGELEHNT' | tail -5 | sed 's/^/        /'
journalctl -u bruecke --since '-3 min' --no-pager 2>/dev/null \
    | grep -qi 'KOPPLUNG NOETIG' \
    && ok "der Dienst hat einen KOPPLUNGSCODE ausgestellt" \
    || bad "im Protokoll des Dienstes steht nichts"

echo
echo "HTTPS443: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ]
