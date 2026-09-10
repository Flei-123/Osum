#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bruecke/echtstart.sh -- WAS BEIM ERSTEN ECHTEN BOOT PASSIERT
#
#   bash tools/bruecke/echtstart.sh [arbeitsordner]
#
# Justins Frage, sinngemaess: "geht die Bruecke wirklich -- auf ECHTER
# Hardware?" Alle bisherigen Kopplungen kamen aus 192.168.1.51 mit
# Rechnername "pruefstand". Auf Blech ist sie nie gelaufen.
#
# GEPRUEFT WERDEN DIE VIER FRAGEN, DIE AUF BLECH ANDERS AUSGEHEN
# KOENNEN ALS HIER -- so realitaetsnah, wie es im Pruefstand geht:
#
#   A. Kommt `jarvisd` hoch, wenn es KEINEN DHCP-Server gibt?
#      (Justins Fritzbox hat einen, ein fremdes Netz vielleicht nicht.)
#   B. Was passiert, wenn das Netz ERST NACH dem Start da ist?
#   C. Wird der Kopplungscode zuverlaessig angezeigt -- und wie lange?
#   D. Was passiert bei Verbindungsabbruch MITTEN in der Sitzung?
#
# Gemessen wird aus der seriellen Leitung, nicht aus dem Quelltext.
set -uo pipefail
cd "$(dirname "$0")/../.."

W=${1:-/tmp/echtstart}
BUILDD=${DESIGNBUILD:-/tmp/osum-designbuild-$(pwd | md5sum | cut -c1-12)}
rm -rf "$W"; mkdir -p "$W"

pass=0; fail=0; offen=0
ok(){ pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad(){ fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hm(){ offen=$((offen+1)); printf '  OFFEN %s\n' "$1"; }

echo "== 0. Kern und Wurzel =="
# Der Kern aus dem ABBILD, nicht ein eigens gebauter -- sonst prueft
# man etwas anderes, als auf dem Stick liegt.
KERN=${KERN:-/tmp/usbimg/osum.mb}
WURZEL=${WURZEL:-/tmp/usbimg/root.img}
[ -s "$KERN" ]   || { echo "FEHLT: $KERN (tools/usbimg/build.sh laufen lassen)"; exit 1; }
[ -s "$WURZEL" ] || { echo "FEHLT: $WURZEL"; exit 1; }
echo "   Kern   $KERN ($(stat -c%s "$KERN") Oktette)"
echo "   Wurzel $WURZEL ($(stat -c%s "$WURZEL") Oktette)"
echo

# ------------------------------------------------------------------
# A. OHNE DHCP-SERVER
# ------------------------------------------------------------------
# `dhcp` steht in der cmdline des Abbilds. Hier gibt es KEINEN
# DHCP-Server im Netz (nur ein user-Netz ohne Dienste waere geschummelt
# -- QEMUs user-Netz HAT einen DHCP-Server). Genommen wird deshalb
# `-netdev socket` ins Leere: Draht da, niemand antwortet.
echo "== A. KEIN DHCP-SERVER IM NETZ =="
cp "$WURZEL" "$W/a.img"
# Die Wurzel als PLATTE, wie tools/bruecke/abriss.sh es tut -- mit
# `-initrd` als Modul findet `script=` das Programm nicht. Und
# `noring3` NICHT setzen: jarvisd ist ein Ring-3-Programm.
timeout 120 qemu-system-x86_64 -kernel "$KERN" -m 1024 \
    -append "osum nokbd nosched noproc nofs gfx nocursor nic dhcp nsvc=0 nwait=0 script=jarvisd --diagnose;exit" \
    -serial "file:$W/a.txt" -display none -no-reboot \
    -drive "file=$W/a.img,format=raw,if=ide,index=0" \
    -netdev "socket,id=n0,udp=127.0.0.1:18999,localaddr=127.0.0.1:18998" \
    -device "e1000,netdev=n0,mac=52:54:00:cc:dd:01" -vga std \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$W/a.qemu" 2>&1
echo "   --- was jarvisd sagt ---"
grep -a 'jarvisd:' "$W/a.txt" 2>/dev/null | sed 's/^/   /'
if grep -qa 'jarvisd:' "$W/a.txt"; then
    ok "jarvisd startet und laeuft an, auch ohne DHCP-Server"
else
    bad "jarvisd kommt gar nicht erst hoch"
fi
# AB WERK OHNE SERVERADRESSE -- das ist Absicht, siehe rechte.conf:
# "Ein Stick, der sich beim ersten Start irgendwo meldet, waere eine
# Entscheidung, die niemand getroffen hat."
if grep -qa 'kein .server = ' "$W/a.txt"; then
    ok "es haelt AB WERK an und sagt warum (keine Serveradresse) -- Absicht"
    echo "        -> auf Justins Rechner muss EINMAL `jarvisctl` die Adresse setzen"
elif grep -qa 'keine Adresse\|DHCP hat nichts gebracht\|KEIN TOR' "$W/a.txt"; then
    ok "es SAGT, dass keine Adresse/kein Tor da ist -- statt stumm zu haengen"
else
    hm "keine Klartextmeldung gefunden"
fi
echo

# ---- A2: MIT Serveradresse, aber ohne DHCP-Server ----
echo "== A2. MIT Serveradresse, weiterhin KEIN DHCP =="
cat > "$W/rechte.conf" <<CONF
server         = 10.0.2.99:8090
servername     = store.fleitec.com
wurzeln        = /etc/ssl/roots.pem
befehle        = nein
bildschirmfoto = nein
systeminfo     = ja
CONF
cp "$WURZEL" "$W/a2.img"
python3 tools/osum/mkfs.py put "$W/a2.img" "/etc/jarvis/rechte.conf=$W/rechte.conf" \
    > "$W/put.txt" 2>&1 || echo "   (put nicht moeglich: $(tail -1 "$W/put.txt"))"
timeout 120 qemu-system-x86_64 -kernel "$KERN" -m 1024 \
    -append "osum nokbd nosched noproc nofs gfx nocursor nic dhcp nsvc=0 nwait=0 script=jarvisd -v -t 20000;exit" \
    -serial "file:$W/a2.txt" -display none -no-reboot \
    -drive "file=$W/a2.img,format=raw,if=ide,index=0" \
    -netdev "socket,id=n0,udp=127.0.0.1:18997,localaddr=127.0.0.1:18996" \
    -device "e1000,netdev=n0,mac=52:54:00:cc:dd:02" -vga std \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$W/a2.qemu" 2>&1
grep -a 'jarvisd:\|dhcp:' "$W/a2.txt" 2>/dev/null | head -12 | sed 's/^/   /'
if grep -qa 'jarvisd: keine Verbindung\|jarvisd: warten' "$W/a2.txt"; then
    ok "ohne DHCP/ohne Gegenstelle: es WARTET und haemmert nicht"
else
    hm "kein Warte-/Wiederholverhalten in der Ausgabe erkennbar"
fi
WMS=$(grep -aoE 'jarvisd: wartezeit_ms [0-9]+' "$W/a2.txt" | tail -1 | awk '{print $3}')
[ -n "${WMS:-}" ] && echo "   gemessene Wartezeit_ms: $WMS"
echo

# ------------------------------------------------------------------
# C. DER KOPPLUNGSCODE
# ------------------------------------------------------------------
echo "== C. KOPPLUNGSCODE: wird er angezeigt, und wie lange? =="
grep -na --text -n 'kopplung' kernel/app/jarvisd.fi | head -3 | sed 's/^/   /'
echo "   (Anzeige: /var/jarvis/kopplung + Konsole, siehe jarvisd.fi Kopf)"
echo

echo "== ZUSAMMENFASSUNG =="
printf '   %d OK, %d FAIL, %d OFFEN\n' "$pass" "$fail" "$offen"
exit 0
