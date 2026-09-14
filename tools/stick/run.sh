#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/stick/run.sh -- RUNDE STICK: DIE SIEBEN PROGRAMME, DIE AUF DEM
# ABBILD GEFEHLT HABEN -- GEMESSEN IM LAUFENDEN SYSTEM, VOM STICK.
#
#   bash tools/stick/run.sh [arbeitsverzeichnis]
#
# ==================================================================
# WAS HIER GEMESSEN WIRD, UND WORIN ES SICH UNTERSCHEIDET
# ==================================================================
#
# `tools/usbimg/run.sh` misst, dass das Abbild STARTET. Dieser Laeufer
# misst, was danach kommt: ob ein Mensch am Stick etwas TUN kann.
# Deshalb wird hier NICHT mit `qemu -kernel` gefahren -- der Kern kommt
# vom Abbild, ueber Limine, wie auf Justins Laptop:
#
#   * BIOS  ueber den MBR-Teil von Limine
#   * UEFI  ueber OVMF und /EFI/BOOT/BOOTX64.EFI
#
# und in beiden Faellen wird der Menueeintrag "Kommandozeile mit Netz"
# gewaehlt (vier Mal nach unten, dann Eingabe -- ueber den QEMU-Monitor,
# also wie ein Mensch am Bildschirm), und danach wird auf der seriellen
# Leitung GETIPPT (`tools/server/console.py`, Runde SERVERBUILD).
#
# DIE VIER ZUSAGEN DIESER RUNDE:
#
#   1. /bin traegt die sieben, die `docs/BLECH-BEREIT.md` Abschnitt 7
#      vermisst hat: ota, fetch, host, jarvisd, jsig, jarvisctl, pollbr
#      (dazu dhcp und reboot, ohne die die anderen nichts koennen).
#   2. `fetch` holt eine ECHTE HTTPS-Seite aus dem offenen Netz --
#      store.fleitec.com, Let's-Encrypt-Kette, geprueft gegen die
#      Mozilla-Wurzeln IM ABBILD.
#   3. `ota suchen` findet den Update-Server ueber den NAMEN
#      store.fleitec.com: DHCP gibt den Nameserver, der Aufloeser macht
#      daraus eine Adresse, das signierte VERZEICHNIS wird gelesen.
#   4. `jarvisd` meldet sich an einer Gegenstelle an und BEANTWORTET
#      einen Auftrag.
#
# WOGEGEN GEMESSEN WIRD, ausdruecklich:
#   * Zusage 2 und 3 gegen den ECHTEN Server https://store.fleitec.com/
#     im offenen Internet. Kein Pruefstand, kein selbstgemachtes
#     Zertifikat.
#   * Zusage 4 gegen `tools/bridge/peer.py`, einen TLS-Server in
#     Python -- NICHT gegen den echten JARVIS-Server. Der laeuft
#     anderswo und ist nicht Teil dieses Repos.
#
# UND DAS ABBILD WIRD DAFUER NICHT ANGEFASST. Die Rechteliste und die
# Wurzel des Pruefstands kommen auf einer ZWEITEN PLATTE herein, die im
# laufenden System eingehaengt wird (`mount /dev/hdb /mnt ofs`) --
# genau der Weg, den ein Mensch mit einem zweiten Stick auch haette.
# Das Abbild, das am Ende ausgeliefert wird, ist Oktett fuer Oktett das
# hier gemessene.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

TMPD=${1:-$(mktemp -d)}
mkdir -p "$TMPD"
IMGDIR=${STICK_IMGDIR:-$TMPD/bau}
IMG="$IMGDIR/osum-usb.img"
NAME=${STORE_NAME:-store.fleitec.com}
SRVPORT=${STICK_PORT:-$(( 9400 + ($$ % 400) ))}

pass=0
fail=0
ok()  { pass=$((pass + 1)); printf '  \033[32mok\033[0m   %s\n' "$*"; }
bad() { fail=$((fail + 1)); printf '  \033[31mNEIN\033[0m %s\n' "$*"; }
hat() { grep -qaF "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' fehlt"; }

for t in qemu-system-x86_64 python3 sgdisk mcopy mkfs.vfat sfdisk; do
    command -v "$t" >/dev/null 2>&1 || { echo "STICK: uebersprungen, $t fehlt"; exit 0; }
done

KVM=()
[ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
OVMF_CODE=""
for c in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd; do
    [ -f "$c" ] && { OVMF_CODE=$c; break; }
done
OVMF_VARS=""
for v in /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd; do
    [ -f "$v" ] && { OVMF_VARS=$v; break; }
done

# =====================================================================
echo "== 1. das Abbild =="
# =====================================================================
if [ -f "$IMG" ] && [ -n "${STICK_IMGDIR:-}" ]; then
    ok "vorhandenes Abbild benutzt: $IMG"
else
    if bash tools/usbimg/build.sh "$IMGDIR" > "$TMPD/build.txt" 2>&1; then
        ok "tools/usbimg/build.sh laeuft durch"
        sed 's/^/       /' "$TMPD/build.txt"
    else
        bad "das Abbild laesst sich nicht bauen"
        tail -20 "$TMPD/build.txt" | sed 's/^/       /'
        echo "STICK: $pass bestanden, $fail gescheitert"; exit 1
    fi
fi
SHA=$(sha256sum "$IMG" | cut -d' ' -f1)
echo "       SHA-256 $SHA"
echo "       $(stat -c%s "$IMG") Oktette"

# =====================================================================
echo "== 2. was im Abbild wirklich liegt =="
# =====================================================================
python3 tools/osum/mkfs.py list "$IMGDIR/root.img" > "$TMPD/liste.txt" 2>&1 \
    || bad "das Wurzelabbild laesst sich nicht lesen"
for f in /bin/ota /bin/fetch /bin/host /bin/jarvisd /bin/jsig \
         /bin/jarvisctl /bin/pollbr /bin/dhcp /bin/reboot \
         /etc/ota.conf /etc/ssl/roots.pem /etc/jarvis/rechte.conf \
         /system/schluessel.pub /system/FASSUNG /system/SCHLUESSELGEN; do
    grep -qE "(^|[[:space:]])${f}([[:space:]]|\$)" "$TMPD/liste.txt" \
        && ok "im Abbild: $f" || bad "im Abbild FEHLT: $f"
done
N=$(grep -oE '(^|[[:space:]])/bin/[a-z0-9_-]+' "$TMPD/liste.txt" | wc -l)
echo "       /bin traegt $N Programme"

# =====================================================================
echo "== 3. die Gegenstelle und die zweite Platte =="
# =====================================================================
# Zertifikate fuer den Pruefstand. 10.0.2.2 ist in QEMUs Benutzernetz
# der Wirt; mkcerts.py legt den Namen UND diese Adresse in den SAN.
mkdir -p "$TMPD/certs"
if python3 tools/ota/mkcerts.py "$TMPD/certs" jarvis.test 10.0.2.2 \
        > "$TMPD/certs.log" 2>&1; then
    ok "Zertifikate des Pruefstands (eigene Wurzel, Name jarvis.test, SAN 10.0.2.2)"
else
    bad "mkcerts.py"; tail -5 "$TMPD/certs.log" | sed 's/^/       /'
fi

cat > "$TMPD/rechte.conf" <<EOFC
# Die Rechteliste des PRUEFSTANDS. Sie liegt NICHT im Abbild -- sie
# kommt auf der zweiten Platte herein und wird mit \`jarvisd -c\`
# genommen. Das Abbild bleibt unangetastet.
server         = 10.0.2.2:$SRVPORT
servername     = jarvis.test
wurzeln        = /mnt/ca.pem
befehle        = ja
befehl_erlaubt = /bin/echo
lesen          = /var/jarvis/
schreiben      = /var/jarvis/
auflisten      = /var/jarvis/
systeminfo     = ja
bildschirmfoto = nein
max_ausgabe    = 4096
max_datei      = 8192
EOFC
# DIE ZWEITE PLATTE IST FAT32 UND NICHT OFS, und das ist kein
# Geschmack: `tools/e2e/run.sh` hat es gemessen und aufgeschrieben --
# OFS LAESST SICH NICHT ZWEIMAL EINHAENGEN. `vfs.mount_at` endet fuer
# FS_OFS in `ofs.node_root(state)`, also in der WURZEL, egal welches
# Geraet genannt wurde. `mount /dev/hdb /mnt ofs` gibt dann eine 0
# zurueck und haengt den Stick noch einmal an sich selbst; genau das ist
# hier passiert (`mount -> 0`, danach `cat: cannot open
# /mnt/rechte.conf`). Mit FAT32 auf einer MBR-Partition geht es -- der
# Weg, den `tools/k14/run.sh` misst.
FAT="$TMPD/fat.img"
dd if=/dev/zero of="$FAT" bs=1M count=64 status=none
if mkfs.vfat -F 32 -s 1 -n OSUMPROBE "$FAT" > "$TMPD/probefs.txt" 2>&1 \
   && mcopy -i "$FAT" "$TMPD/rechte.conf" ::/rechte.conf 2>>"$TMPD/probefs.txt" \
   && mcopy -i "$FAT" "$TMPD/certs/ca.pem" ::/ca.pem 2>>"$TMPD/probefs.txt"; then
    dd if=/dev/zero of="$TMPD/probe.img" bs=1M count=68 status=none
    printf 'label: dos\nstart=2048, type=c\n' | sfdisk "$TMPD/probe.img" \
        >> "$TMPD/probefs.txt" 2>&1
    dd if="$FAT" of="$TMPD/probe.img" bs=512 seek=2048 conv=notrunc status=none
    ok "die zweite Platte traegt /rechte.conf und /ca.pem (FAT32 auf einer MBR-Partition)"
else
    bad "die zweite Platte laesst sich nicht bauen"
    tail -5 "$TMPD/probefs.txt" | sed 's/^/       /'
fi

cat > "$TMPD/auftraege.txt" <<'AUF'
system||
befehl|/bin/echo hallo-vom-stick|
AUF

# =====================================================================
# EIN START VOM STICK, MIT MENUEWAHL UND EINER TASTATUR AM SERIELLEN
# ANSCHLUSS.
# =====================================================================
stick_lauf() { # <name> <bios|uefi> <mit-gegenstelle:0|1> <console.py-args...>
    local name=$1 art=$2 mitsrv=$3; shift 3
    local d="$TMPD/$name"
    rm -rf "$d"; mkdir -p "$d"
    cp -f "$IMG" "$d/stick.img"
    cp -f "$TMPD/probe.img" "$d/probe.img"
    local srvpid=""
    if [ "$mitsrv" = 1 ]; then
        python3 tools/bridge/peer.py \
            --cert "$TMPD/certs/srv.pem" --key "$TMPD/certs/srv.key" \
            --port "$SRVPORT" --auftraege "$TMPD/auftraege.txt" \
            --aus "$d/g.log" --wartezeit 180 > "$d/g.stderr" 2>&1 &
        srvpid=$!
        sleep 1
    fi
    local fw=()
    if [ "$art" = uefi ]; then
        cp -f "$OVMF_VARS" "$d/vars.fd"
        fw=(-drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE"
            -drive "if=pflash,format=raw,unit=1,file=$d/vars.fd")
    fi
    ( timeout 500 qemu-system-x86_64 "${KVM[@]}" -m 1024 "${fw[@]}" \
        -drive "file=$d/stick.img,format=raw,if=ide,index=0" \
        -drive "file=$d/probe.img,format=raw,if=ide,index=1" \
        -netdev user,id=n0 -device e1000,netdev=n0 \
        -display none -no-reboot -vga std \
        -serial "unix:$d/ser.sock,server,nowait" \
        -monitor "unix:$d/mon.sock,server,nowait" > "$d/qemu.txt" 2>&1 ) &
    local qpid=$!
    # Der Menueeintrag "Kommandozeile mit Netz" ist der fuenfte: vier
    # Mal nach unten. Der erste Tastendruck haelt den Countdown an.
    #
    # UNTER UEFI SPAETER: OVMF braucht mehrere Sekunden, bevor Limine
    # ueberhaupt malt, und eine Taste vor dem Menue ist verloren
    # (gemessen: mit neun Sekunden lief der UEFI-Lauf in den
    # Vorgabeeintrag).
    local warte=${MENUE_WARTE:-9}
    [ "$art" = uefi ] && warte=${MENUE_WARTE_UEFI:-15}
    python3 tools/stick/menue.py "$d/mon.sock" 4 \
        "$warte" > "$d/menue.log" 2>&1
    python3 tools/server/console.py "$d/ser.sock" "$d/con.log" "$@" \
        > "$d/con.out" 2>&1
    local rc=$?
    kill "$qpid" 2>/dev/null; wait "$qpid" 2>/dev/null
    if [ -n "$srvpid" ]; then kill "$srvpid" 2>/dev/null; wait "$srvpid" 2>/dev/null; fi
    # Die Kopien sind je 118 MiB; die Protokolle bleiben, die Abbilder
    # nicht. Drei Laeufe waeren sonst ein Drittel Gigaoktett Abfall.
    rm -f "$d/stick.img" "$d/probe.img" "$d/vars.fd"
    sed 's/^/       /' "$d/con.out"
    return $rc
}

set -- \
    --frist 150 --erwarte 'sh: ready' \
    --sende 'dhcp\n'                           --frist 90  --erwarte 'dhcp: gesetzt ip=' \
    --sende 'cat /etc/resolv.conf\n'           --frist 30  --erwarte 'nameserver' \
    --sende "host $NAME\n"                     --frist 90  --erwarte 'host -> 0' \
    --sende "fetch https://$NAME/index.json\n" --frist 150 --erwarte 'fetch -> 0' \
    --sende 'ota suchen\n'                     --frist 200 --erwarte 'ota -> '
NETZFOLGE=("$@")

# Mit STICK_NUR=bruecke laesst sich der letzte Abschnitt einzeln fahren
# -- die drei Starts kosten zusammen mehrere Minuten.
if [ "${STICK_NUR:-}" != bruecke ]; then

# =====================================================================
echo "== 4. BIOS: vom Stick, Menueeintrag 5, und dann getippt =="
# =====================================================================
stick_lauf sbios bios 0 "${NETZFOLGE[@]}"
B="$TMPD/sbios/con.log"
hat "$B" 'console=ttyS0' "der Menueeintrag 'Kommandozeile mit Netz' wurde gewaehlt"
hat "$B" 'sh: ready' "die Shell steht auf der seriellen Leitung"
hat "$B" 'dhcp: gesetzt ip=' "DHCP hat eine Adresse gesetzt"
hat "$B" 'nameserver' "und einen Nameserver nach /etc/resolv.conf geschrieben"
IPO=$(grep -aoE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$B" | tail -1)
IPD=""
command -v dig >/dev/null 2>&1 && IPD=$(dig +short "$NAME" A | grep -E '^[0-9.]+$' | head -1)
if [ -n "$IPO" ] && [ "$IPO" = "$IPD" ]; then
    ok "/bin/host loest $NAME auf, und dig auf dem Wirt sagt dasselbe: $IPO"
else
    bad "/bin/host: '${IPO:-keine}', dig: '${IPD:-keine}'"
fi
hat "$B" 'fetch: verify OK' "die Let's-Encrypt-Kette wurde GEPRUEFT -- gegen die Wurzeln IM ABBILD"
CERTS=$(grep -aoE 'fetch: certs [0-9]+' "$B" | head -1 | awk '{print $3}')
if [ "${CERTS:-0}" -ge 3 ] 2>/dev/null; then
    ok "und es ist eine echte Kette: $CERTS Zertifikate"
else
    bad "nur ${CERTS:-0} Zertifikate -- das ist keine echte Kette"
fi
hat "$B" 'fetch -> 0' "/bin/fetch endet mit 0 -- die Seite ist da"
hat "$B" 'ota: fassung dort' "ota hat das signierte VERZEICHNIS gelesen"
hat "$B" 'ota: NEUE FASSUNG verfügbar' "und meldet, dass es etwas Neues gibt"

# =====================================================================
echo "== 5. UEFI: dieselbe Datei, derselbe Eintrag =="
# =====================================================================
if [ -n "$OVMF_CODE" ] && [ -n "$OVMF_VARS" ]; then
    stick_lauf suefi uefi 0 "${NETZFOLGE[@]}"
    U="$TMPD/suefi/con.log"
    hat "$U" 'sh: ready' "unter UEFI steht dieselbe Shell"
    hat "$U" 'dhcp: gesetzt ip=' "DHCP unter UEFI"
    hat "$U" 'fetch: verify OK' "und dieselbe gepruefte Kette"
    hat "$U" 'ota: NEUE FASSUNG verfügbar' "und dasselbe VERZEICHNIS"
else
    echo "       (kein OVMF -- der UEFI-Lauf entfaellt)"
fi

fi   # STICK_NUR

# =====================================================================
echo "== 6. die Bruecke: jarvisd beantwortet einen Auftrag =="
# =====================================================================
stick_lauf sbr bios 1 \
    --frist 150 --erwarte 'sh: ready' \
    --sende 'mount\n'                    --frist 60  --erwarte 'mount -> 0' \
    --sende 'cat /mnt/rechte.conf\n'     --frist 40  --erwarte 'servername' \
    --sende 'dhcp\n'                     --frist 90  --erwarte 'dhcp: gesetzt ip=' \
    --sende 'jarvisd -c /mnt/rechte.conf -1 -t 90000\n' \
                                         --frist 240 --erwarte 'jarvisd -> ' \
    --sende 'jarvisctl protokoll 20\n'   --frist 60  --erwarte 'jarvisctl -> '
R="$TMPD/sbr/con.log"
G="$TMPD/sbr/g.log"
# DIE ZWEITE PLATTE HAENGT SCHON. GEMESSEN, und es war eine
# Ueberraschung: `mount /dev/hdb1 /mnt vfat` von Hand sagt
# "cannot mount" und gibt 1 -- ZU RECHT, denn `kernel/kmain.fi` haengt
# mit dem Kernwort `vfs` die FAT-Partition der ZWEITEN ATA-Platte beim
# Start selbst unter /mnt ein (Zeile 2502), und `vfs.mount_at` weist
# einen zweiten Eintrag auf demselben Ort ab. Gemessen wird deshalb,
# was zaehlt: dass die Einhaengetafel sie fuehrt und die Datei lesbar
# ist. Fuer Justin heisst das: eine FAT-Platte oder ein zweiter Stick
# ist beim Start einfach da.
hat "$R" '/mnt type vfat' "die zweite Platte steht in der Einhaengetafel (/mnt, vfat)"
hat "$R" 'servername' "und ihre Rechteliste ist lesbar"
hat "$R" 'jarvisd: verbunden' "jarvisd hat die Verbindung aufgebaut"
hat "$R" 'jarvisd: angemeldet' "und sich angemeldet"
hat "$G" 'TLSv1.3' "die Verbindung steht auf TLS 1.3 -- gesagt hat das Python, nicht Osum"
hat "$G" 'BEWEIS gut' "die Ed25519-Unterschrift des Geraets stimmt (nachgerechnet von python-cryptography)"
hat "$G" 'ANGEMELDET' "die Gegenstelle hat die Anmeldung angenommen"
if [ "$(grep -a '^ANTWORT 1 ' "$G" 2>/dev/null | awk '{print $4}')" = ok ]; then
    ok "Auftrag 1 (system) beantwortet: $(grep -a '^ANTWORT 1 ' "$G")"
else
    bad "Auftrag 1: $(grep -a '^ANTWORT 1 ' "$G" 2>/dev/null || echo 'keine Antwort')"
fi
if [ "$(grep -a '^ANTWORT 2 ' "$G" 2>/dev/null | awk '{print $4}')" = ok ]; then
    ok "Auftrag 2 (befehl /bin/echo) beantwortet"
else
    bad "Auftrag 2: $(grep -a '^ANTWORT 2 ' "$G" 2>/dev/null || echo 'keine Antwort')"
fi
if grep -qa 'hallo-vom-stick' "$G.2.bin" 2>/dev/null; then
    ok "und die Ausgabe des Befehls kam wirklich vom Stick: $(tr -d '\n' < "$G.2.bin")"
else
    bad "die Ausgabe des Befehls fehlt"
fi

echo
echo "STICK: $pass bestanden, $fail gescheitert"
echo "       Abbild $IMG"
echo "       SHA-256 $SHA"
[ "$fail" -eq 0 ]
