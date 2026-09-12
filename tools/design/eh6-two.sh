#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/eh5.sh -- DIE ABNAHME DER RUNDE ECHTHARDWARE-5.
#
#   bash tools/design/eh5.sh <ausgabeverzeichnis> [key=value ...]
#
# WARUM ES DIESEN LAEUFER GIBT UND capture.sh NICHT GENUEGT.
#
# Justins Befunde aus ECHTHARDWARE-4 (Fotos vom 10.09.2026, 11:31-11:37,
# Abbild orientos-usb-20260910-44a5af3.img) liessen sich mit
# `tools/design/capture.sh` NICHT nachstellen -- und zwar nicht, weil
# sie nicht da waeren, sondern weil dieser Laeufer eine ANDERE MASCHINE
# baut als der Stick. Drei Unterschiede, jeder einzeln nachgewiesen:
#
#   1. DIE BEFEHLSZEILE. capture.sh faehrt
#         gfx ... wm desk wmhold ... nokbd nosched noproc nofs
#      der Stick dagegen (tools/usbimg/build.sh, Menue 1)
#         modfs osum gfx wm wig desk wmshell wmdauer tafel herz ...
#      `wmhold` haelt den Fensterserver an einer Stelle an, an der der
#      Schreibtisch NOCH LAEUFT, aber `wmshell` fehlt: es wird also NIE
#      eine Shell im Terminalfenster gestartet. Justins Befund B
#      ("Terminalfenster ist leer") KANN unter capture.sh gar nicht
#      auftreten, weil dort nie eine Shell im Fenster stand.
#      Ausserdem `nokbd`: der Tastaturtreiber ist AUS. Befund A
#      ("im Suchfenster laesst sich nichts tippen") ist damit ebenfalls
#      nicht pruefbar -- `sendkey` kam bisher ueber einen Sonderweg an.
#
#   2. DIE PROGRAMMLISTE. capture.sh baut elf Programme; der Stick
#      baut achtundfuenfzig. `/bin/taskmgr` ist in BEIDEN nicht dabei,
#      und genau das ist Justins Befund F: das Kontrollzentrum ruft
#      `/bin/taskmgr` (kernel/user/qs.fi:1316), und diese Datei liegt
#      auf seinem Stick nicht. Nachgewiesen mit
#      `python3 tools/osum/mkfs.py list` auf der Wurzelpartition des
#      ausgelieferten Abbildes: 177 Inoden, kein `/bin/taskmgr`.
#
#   3. DIE TAFEL. `tafel herz` malt die Diagnosetafel, aus der Justins
#      Zahlen stammen (RING/VERL/KOAL, ISR MAX, SAFETY, PANEL). Ohne
#      diese Woerter gibt es die Zeilen nicht, gegen die seine Fotos
#      gelesen werden.
#
# Dieser Laeufer baut deshalb die MASCHINE DES STICKS: dieselbe
# Befehlszeile, dieselbe Programmliste (soweit sie uebersetzt), und die
# Tafel an. Was hier gemessen wird, ist damit vergleichbar mit dem, was
# Justin auf dem Blech sieht -- und nur so ist ein Befund ein Befund.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

OUT=${1:?usage: eh5.sh <outdir> [key=value ...]}
shift || true
mkdir -p "$OUT"

res=1920x1080
uiscale=1
mode=dark
scheme=day
dark_scheme=midnight
accent=""
lang=en
halt=0
drehbuch=""
accel=auto
nurbau=nein
ton=nein
netz=nein
usb=ja
extra=""
# DIE PROGRAMME. Das ist die Liste des Sticks, gekuerzt um die, die
# dieser Laeufer nicht braucht -- ABER MIT `taskmgr` UND `sh`, weil
# genau die beiden in Justins Befunden vorkommen.
progs="desktop taskbar settings launcher explorer netview taskmgr \
edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc \
find du chmod id whoami touch true false sleep kill sort uniq rmdir \
theme locate dhcp host ping netstat"

for a in "$@"; do
    case "$a" in
        res=*) res=${a#*=} ;;
        uiscale=*) uiscale=${a#*=} ;;
        mode=*) mode=${a#*=} ;;
        scheme=*) scheme=${a#*=} ;;
        dark_scheme=*) dark_scheme=${a#*=} ;;
        accent=*) accent=${a#*=} ;;
        lang=*) lang=${a#*=} ;;
        halt=*) halt=${a#*=} ;;
        drehbuch=*) drehbuch=${a#*=} ;;
        accel=*) accel=${a#*=} ;;
        progs=*) progs=${a#*=} ;;
        nurbau=*) nurbau=${a#*=} ;;
        ton=*) ton=${a#*=} ;;
        netz=*) netz=${a#*=} ;;
        usb=*) usb=${a#*=} ;;
        extra=*) extra=${a#*=} ;;
        *) echo "unbekannt: $a" >&2; exit 2 ;;
    esac
done
XRES=${res%x*}
YRES=${res#*x}
SKAL=""
if [ -n "$uiscale" ] && [ "$uiscale" != 1 ]; then SKAL="uiscale=$uiscale"; fi

BUILDD=${DESIGNBUILD:-/tmp/osum-eh5build-$(pwd | md5sum | cut -c1-12)}
mkdir -p "$BUILDD"

# ---------------------------------------------------------- 1. bauen
bash vendor/firn/fetch-firnc.sh > "$BUILDD/fetch.log" 2>&1 || {
    echo "FEHLGESCHLAGEN: fetch-firnc.sh"; tail -5 "$BUILDD/fetch.log"; exit 1; }
newer=$(find kernel tools/build-kernel.sh -newer "$BUILDD/k0.mb" -print -quit 2>/dev/null || true)
if [ ! -s "$BUILDD/k0.mb" ] || [ -n "$newer" ] || [ -n "${DESIGNREBUILD:-}" ]; then
    ./tools/build-kernel.sh "$BUILDD/k0.mb" > "$BUILDD/k.log" 2>&1 \
        || { echo "FEHLGESCHLAGEN: der Kern baut nicht"; tail -25 "$BUILDD/k.log"; exit 1; }
fi
echo "kernel $(stat -c%s "$BUILDD/k0.mb") Oktette"

if [ ! -s "$BUILDD/crt.o" ] || [ -n "${DESIGNREBUILD:-}" ]; then
    as --64 -o "$BUILDD/crt.o" kernel/user/crt.s 2>"$BUILDD/as.err" \
        || { echo "FEHLGESCHLAGEN: crt.s"; cat "$BUILDD/as.err"; exit 1; }
fi
USERNEW=$(ls -t kernel/user/*.fi 2>/dev/null | head -1)
GEBAUT=""
for p in $progs; do
    [ -f "kernel/user/$p.fi" ] || { echo "   (uebersprungen, keine Quelle: $p)"; continue; }
    if [ -s "$BUILDD/$p.elf" ] && [ -z "${DESIGNREBUILD:-}" ] \
       && [ "$BUILDD/$p.elf" -nt "kernel/user/$p.fi" ] \
       && [ -n "$USERNEW" ] && [ "$BUILDD/$p.elf" -nt "$USERNEW" ]; then
        GEBAUT="$GEBAUT $p"; continue
    fi
    vendor/firn/bin/firnc "kernel/user/$p.fi" -o "$BUILDD/$p.o" \
        > "$BUILDD/e-$p" 2>&1 \
        || { echo "FEHLGESCHLAGEN beim Uebersetzen von $p"; head -30 "$BUILDD/e-$p"; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
        -o "$BUILDD/$p.elf" "$BUILDD/crt.o" "$BUILDD/$p.o" 2>"$BUILDD/ld.err" \
        || { echo "FEHLGESCHLAGEN beim Binden von $p"; cat "$BUILDD/ld.err"; exit 1; }
    strip --strip-all "$BUILDD/$p.elf"
    GEBAUT="$GEBAUT $p"
done
echo "programme $(echo $GEBAUT | wc -w)"

# ============================================== RUNDE ECHTHARDWARE-5
# DIE APPS (`fetch`) -- FUER JUSTINS PUNKT I.
#
# `fetch` ist das einzige Programm dieses Baumes, das TLS spricht, und
# damit die einzige Antwort auf "geht ausgehendes HTTPS". Es liegt in
# kernel/app/ und braucht ein anderes Profil (`--profile=app`) und
# FIRNLIB=lib/ -- der Grund steht ausfuehrlich in
# tools/usbimg/build.sh: `fetch` zieht `libc.dns` aus DIESEM Repo UND
# `tls.tls` aus vendor/firn/lib, und nur mit FIRNLIB=lib/ sind beide
# Haelften erreichbar.
GEBAUT_APP=""
for p in ${APPS:-fetch}; do
    [ -f "kernel/app/$p.fi" ] || continue
    if FIRNLIB="$ROOT/lib" vendor/firn/bin/firnc -c --profile=app \
            -o "$BUILDD/app-$p.o" "kernel/app/$p.fi" \
            > "$BUILDD/app-$p.err" 2>&1 \
       && ld -T kernel/user/user.ld -o "$BUILDD/$p.elf" \
            "$BUILDD/app-$p.o" 2> "$BUILDD/app-$p.lderr"; then
        strip --strip-all "$BUILDD/$p.elf"
        GEBAUT_APP="$GEBAUT_APP $p"
    else
        echo "   (app $p baut nicht -- $(head -1 "$BUILDD/app-$p.err" 2>/dev/null))"
    fi
done
[ -n "$GEBAUT_APP" ] && echo "apps       $(echo $GEBAUT_APP | wc -w)"

# ------------------------------------------------------------ 2. Platte
python3 tools/k15/tree.py "$OUT/baum" > "$OUT/baum.log" 2>&1 || exit 1
printf '# taskbar.conf\nedge=bottom\nwidth=104\nautohide=0\nontop=1\nalign=left\n' \
    > "$OUT/taskbar.conf"
{
  printf '# /etc/theme.conf\nscheme=%s\n' "$scheme"
  [ -n "$dark_scheme" ] && printf 'dark_scheme=%s\n' "$dark_scheme"
  printf 'mode=%s\naccent=%s\nshape=osum\nlight_start=07:00\ndark_start=19:00\n' \
    "$mode" "$accent"
} > "$OUT/theme.conf"
printf '# /etc/time.conf\noffset=120\n' > "$OUT/time.conf"
printf 'lang=%s\n' "$lang" > "$OUT/locale.conf"
printf 'on\n' > "$OUT/uitrace"
cat > "$OUT/passwd" <<'EOF'
root:x:0:0:root:/users/justin:/bin/sh
justin:x:1000:1000:Justin:/users/justin:/bin/sh
EOF
printf '%s\n' "$lang" > "$OUT/userlocale"

ARGS=(build "$OUT/disk.img" 65536 --v3 --inodes=1024 "--time=$(date +%s)" /lib/
      "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
      "/lib/icons.ttf=assets/osum-icons.ttf" /bin/)
for p in $GEBAUT; do ARGS+=("/bin/$p=$BUILDD/$p.elf"); done
for p in $GEBAUT_APP; do ARGS+=("/bin/$p=$BUILDD/$p.elf"); done
ARGS+=("/bin/files@/bin/explorer")
ARGS+=(/etc/
       "/etc/theme.conf=$OUT/theme.conf@0644"
       "/etc/time.conf=$OUT/time.conf@0644"
       "/etc/locale.conf=$OUT/locale.conf@0644"
       "/etc/passwd=$OUT/passwd@0644"
       "/etc/uitrace=$OUT/uitrace@0644"
       "/etc/taskbar.conf=$OUT/taskbar.conf@0644")
ARGS+=(/etc/schemas/)
for s in assets/schemes/*.scheme; do
    ARGS+=("/etc/schemas/$(basename "$s" .scheme)=$s@0644")
done
ARGS+=(/etc/shapes/)
for s in assets/shapes/*.shape; do
    ARGS+=("/etc/shapes/$(basename "$s" .shape)=$s@0644")
done
ARGS+=(/etc/themes/)
for s in assets/themes/*.preset; do
    ARGS+=("/etc/themes/$(basename "$s" .preset)=$s@0644")
done
if python3 tools/netview/icons.py bauen "$OUT/nvicons" > "$OUT/nvicons.log" 2>&1; then
    ARGS+=(/etc/netview/)
    for q in state-nocarrier state-noip state-noroute state-online \
             mark-filtered mark-faked mark-none sys-faking \
             tile-fake tile-net tile-hide; do
        [ -e "$OUT/nvicons/$q" ] && ARGS+=("/etc/netview/$q=$OUT/nvicons/$q")
    done
fi
# RUNDE ECHTHARDWARE-5: die Wurzelzertifikate. Ohne sie vertraut
# `fetch` NICHTS und jede HTTPS-Verbindung endet an der Pruefung --
# was wie ein Netzfehler aussaehe und keiner waere.
if python3 tools/hwnet/mkroots.py "$OUT/roots.pem" > "$OUT/roots.log" 2>&1; then
    ARGS+=(/etc/ssl/ "/etc/ssl/roots.pem=$OUT/roots.pem@0644")
    echo "wurzeln    $(stat -c%s "$OUT/roots.pem") Oktette"
fi
ARGS+=(/usr/ /usr/share/ /usr/share/locale/
       /usr/share/locale/en/ "/usr/share/locale/en/messages=locale/en/messages"
       /usr/share/locale/de/ "/usr/share/locale/de/messages=locale/de/messages")
[ -e locale/en/icons ] && ARGS+=("/usr/share/locale/en/icons=locale/en/icons")
[ -e locale/de/icons ] && ARGS+=("/usr/share/locale/de/icons=locale/de/icons")
ARGS+=(/users/ /users/justin/ /users/justin/config/
       "/users/justin/config/locale=$OUT/userlocale@0644")
mkdir -p "$OUT/heim"
printf 'Notizen zur Runde ECHTHARDWARE-5.\n' > "$OUT/heim/notizen.txt"
printf 'a,b,c\n1,2,3\n' > "$OUT/heim/tabelle.csv"
ARGS+=("/users/justin/notizen.txt=$OUT/heim/notizen.txt@0644"
       "/users/justin/tabelle.csv=$OUT/heim/tabelle.csv@0644")
rm -rf "$OUT/apps"; cp -a assets/apps "$OUT/apps"
while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py "$OUT/apps" "$OUT/buendel" "nur=$GEBAUT" 2>/dev/null || true)
while read -r z; do ARGS+=("$z"); done < "$OUT/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$OUT/mkfs.log" 2>&1 \
    || { echo "FEHLGESCHLAGEN: mkfs"; tail -25 "$OUT/mkfs.log"; exit 1; }
echo "platte $(stat -c%s "$OUT/disk.img") Oktette"
[ "$nurbau" = ja ] && exit 0

# ------------------------------------------------------------ 3. starten
#
# DIE BEFEHLSZEILE DES STICKS, und das ist der ganze Sinn dieses
# Laeufers. Woertlich aus tools/usbimg/build.sh, Menue 1, minus die
# Netz-Woerter (dieser Lauf hat keine Netzkarte) und minus `modfs`
# (der Kern bekommt die Platte hier ueber `-drive`, nicht als Modul).
#
#   wmshell   startet /bin/sh IM TERMINALFENSTER  -> Befund B pruefbar
#   wmdauer   der Schreibtisch laeuft ohne Rundengrenze
#   tafel     die Diagnosetafel                   -> Befunde G und H
#   herz      der Puls
#   KEIN nokbd: der Tastaturtreiber laeuft        -> Befund A pruefbar
APPEND="osum gfx fbres=${XRES}x${YRES} wm wig desk wmshell wmdauer tafel herz"
APPEND="$APPEND absturzhalt nopuls tz=120 lang=$lang nosched noproc nofs"
[ -n "$SKAL" ] && APPEND="$APPEND $SKAL"
[ "$halt" != 0 ] && APPEND="$APPEND wighalt=$halt"
[ -n "$extra" ] && APPEND="$APPEND $extra"
echo "append  $APPEND"

SOCK="$OUT/mon.sock"; rm -f "$SOCK" "$OUT/serial.txt"
TONDEV=()
if [ "$ton" = ja ]; then
    APPEND="$APPEND audio nosounds"
    TONDEV=(-audiodev none,id=snd0 -device intel-hda
            -device hda-duplex,audiodev=snd0)
fi
# ================================================ RUNDE ECHTHARDWARE-5
# `netz=ja` -- EINE ECHTE NETZKARTE MIT AUSGANG INS INTERNET.
#
# Justins Punkt I: seit ECHTHARDWARE-4 hat sein Brett einen echten
# DHCP-Lease (Tafel Zeile 22, `IP 192.168.1.107`). Die Frage ist, ob
# darauf DNS und ausgehendes HTTPS gehen -- die Voraussetzung fuer
# Browser und Jarvis-Bruecke.
#
# QEMUs Benutzernetz beantwortet genau das: es hat einen eigenen
# DHCP-Server (10.0.2.15 fuer den Gast, 10.0.2.2 als Router,
# 10.0.2.3 als DNS) und leitet nach draussen weiter. `e1000` ist die
# Karte, fuer die dieser Kern einen Treiber hat.
NETDEV=()
if [ "$netz" = ja ]; then
    NETDEV=(-netdev user,id=n0 -device e1000,netdev=n0)
    # DIESELBEN WOERTER WIE DER STICK (tools/usbimg/build.sh, Menue 1).
    # `nic` allein genuegt NICHT: ohne `nsvc=0 nwait=0` kommt der
    # Netzstapel nicht hoch, und `/bin/dhcp` meldet dann woertlich
    # `dhcp: kein Netz im Kernel` -- gemessen in genau diesem Lauf.
    APPEND="$APPEND nic nip=169.254.10.1/16 nsvc=0 nwait=0 dhcp"
fi
# ================================================ RUNDE ECHTHARDWARE-6
# EINE ECHTE USB-TASTATUR AN EINEM ECHTEN xHCI.
#
# DAS WAR DER GRUND, WARUM R1 UNTER eh5.sh NICHT ZU SEHEN WAR.
# `eh5.sh` gab QEMU KEINEN USB-Regler. Der Kern meldet dann woertlich
#
#     usb: skipped
#     tafel: 18 KEYS  D 0
#
# `D 0` heisst: es gibt gar keine USB-Tastatur. Getippt wurde in jenem
# Lauf ueber den PS/2-Weg -- also ueber genau die Leitung, die auf
# Justins Brett NICHT benutzt wird. Justins Tafel sagt `D 2`: zwei
# USB-Geraete, die Tastatur darunter. Wer ohne xHCI misst, misst den
# anderen Treiber und kann Justins Befund per Bauart nicht sehen.
#
# `qemu-xhci` + `usb-kbd` + `usb-mouse` ist die Aufstellung, die auch
# tools/uhrwerk/messen.sh und tools/usbimg/merge8-schuss.sh benutzen,
# und sie erzeugt genau das Zahlenbild, gegen das Justins Foto gelesen
# wird.
USBDEV=()
if [ "$usb" = ja ]; then
    USBDEV=(-device qemu-xhci,id=x0
            -device usb-kbd,bus=x0.0
            -device usb-mouse,bus=x0.0 -device usb-tablet,bus=x0.0)
    APPEND="$APPEND usb"
fi
ACC=()
if [ "$accel" = kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACC=(-accel kvm -cpu host)
fi
timeout 900 qemu-system-x86_64 "${ACC[@]}" -kernel "$BUILDD/k0.mb" -m 512 \
    -append "$APPEND" \
    -serial "file:$OUT/serial.txt" -display none -no-reboot \
    -device "VGA,edid=on,xres=$XRES,yres=$YRES,vgamem_mb=32" \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$OUT/disk.img,format=raw,if=ide,index=0" \
    "${TONDEV[@]}" "${NETDEV[@]}" "${USBDEV[@]}" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$OUT/qemu.log" 2>&1 &
PID=$!
# GEWARTET WIRD AUF DEN SCHREIBTISCH, NICHT AUF `wm: hold`.
# Ohne `wmhold` gibt es diese Zeile gar nicht; was den Zustand
# "bedienbar" wirklich anzeigt, ist die Leiste bzw. der Starter.
i=0
while [ $i -lt 3000 ]; do
    grep -qaE 'launcher: ready|taskbar: ready|wm: dauer' "$OUT/serial.txt" 2>/dev/null && break
    kill -0 "$PID" 2>/dev/null || break
    sleep 0.15; i=$((i+1))
done
if ! grep -qaE 'launcher: ready|taskbar: ready|wm: dauer' "$OUT/serial.txt" 2>/dev/null; then
    echo "FEHLGESCHLAGEN: der Schreibtisch ist nie hochgekommen"
    tail -25 "$OUT/serial.txt" 2>/dev/null
fi

if [ -n "$drehbuch" ]; then
    python3 -u tools/design/drive.py "$SOCK" "$OUT/serial.txt" "$OUT" "$drehbuch" \
        2>&1 | tee "$OUT/fahren.log"
fi

# Beenden: erst hoeflich ueber den Monitor, dann hart.
printf 'quit\n' | timeout 5 socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1 || true
sleep 0.5
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null
echo "fertig: $(ls "$OUT"/*.ppm 2>/dev/null | wc -l) Bilder"
