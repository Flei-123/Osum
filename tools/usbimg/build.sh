#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/usbimg/build.sh -- RUNDE USBIMG: EIN ABBILD, DAS AUF ECHTEM BLECH
# STARTET.
#
#   bash tools/usbimg/build.sh [ausgabeverzeichnis]
#   -> <ausgabeverzeichnis>/osum-usb.img, mit dd auf einen Stick zu schreiben
#
# ==================================================================
# WARUM ES SO UND NICHT ANDERS GEBAUT IST
# ==================================================================
#
# 1. MULTIBOOT MIT RAHMENPUFFER, UNTER BIOS UND UNTER UEFI.
#    Der Multiboot-Kopf in `kernel/arch/x86_64/boot.s` hat Bit 2 gesetzt
#    (Video), und der Kommentar dort sagt auch warum: ohne dieses Bit
#    verlangt ein Multiboot-Lader unter UEFI einen Textmodus, den es dort
#    nicht gibt, und bricht mit "Cannot use text mode with UEFI" ab. Mit
#    dem Bit setzt die Firmware einen LINEAREN Rahmenpuffer, und DASSELBE
#    Abbild startet ueber beide Wege. Genau das misst tools/usbimg/run.sh.
#
# 2. DIE WURZEL IST EIN BOOT-MODUL UND KEINE PARTITION.
#    Das ist die wichtigste Entscheidung dieses Skripts, und sie folgt
#    direkt aus dem Zweck des Sticks. Der Stick soll auf einem Rechner
#    starten, von dem wir NICHT WISSEN, was fuer ein Plattencontroller
#    darin steckt -- das herauszufinden ist ja der Grund, warum es ihn
#    gibt. Laege die Wurzel auf einer Partition, muesste der Kern dieses
#    Geraet lesen koennen, um ueberhaupt bis zu der Meldung zu kommen,
#    die sagt, dass er es nicht kann. Als Modul laedt der LADER die
#    Wurzel -- ueber die Firmware, die ihr eigenes Geraet immer lesen
#    kann --, und der Kern findet sie fertig im Arbeitsspeicher. Er
#    braucht dafuer keinen einzigen Treiber.
#
#    `kernel/bootmod.fi` kann das seit Runde K10, und `kmain.osum` nimmt
#    das Modul seit derselben Runde als Wurzelplatte. Was diese Runde
#    hinzugefuegt hat, ist die gleiche Moeglichkeit fuer den WEG UEBER
#    DEN FENSTERSERVER (`kmain.surface`, Abschnitt 2) -- der lud seine
#    Schriften bis dahin nur von einer ATA-Platte.
#
# 3. TROTZDEM GPT MIT EFI-PARTITION UND WURZELPARTITION.
#    Was `install.fi` aus Runde INSTALL kann, wird hier benutzt und nicht
#    nachgebaut: die Tafel ist GPT, Partition 1 ist eine EFI-Partition
#    (FAT32, Typ EF00), Partition 2 traegt DASSELBE OFS-Dateisystem noch
#    einmal, diesmal als Partition. Der Start benutzt sie nicht -- aber
#    ein Rechner, dessen Controller sich als lesbar herausstellt, hat
#    damit sofort eine Wurzel auf dem Stick, und `/bin/install` findet
#    die Lage vor, fuer die es gebaut wurde.
#
# 4. BIOS UND UEFI AUS EINER DATEI.
#    Limine legt seinen BIOS-Ladeteil in den MBR-Bereich und nach
#    `limine-bios.sys` auf der EFI-Partition; unter UEFI startet die
#    Firmware `/EFI/BOOT/BOOTX64.EFI` von derselben Partition. Eine
#    Datei, zwei Startwege, dieselbe `limine.conf`.
#
# 5. UND DIE DATEIEN, DIE IN DER LETZTEN RUNDE GEFEHLT HABEN, WERDEN
#    GEZAEHLT UND NICHT GEHOFFT.
#    Das vorige Bootabbild enthielt weder locale/de noch locale/en noch
#    die Symbole unter /etc/netview/ -- deshalb fiel die Oberflaeche auf
#    englische Ersatztexte und Textmarken zurueck, und der Fehler sah wie
#    einer des Zeichenwerks aus, obwohl er im Abbildbau lag. Deshalb
#    liest dieses Skript das FERTIGE Dateisystem mit `mkfs.py list`
#    zurueck und bricht ab, wenn auch nur einer der Pflichtpfade fehlt.
#    Die Liste steht unten unter PFLICHT.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

OUT=${1:-/tmp/usbimg}
STUFE=${STUFE:-0}
CC=${FIRNC:-vendor/firn/bin/firnc}
LIMINE=${LIMINE_DIR:-/root/jarvis/projects/u_DiS4in7esMF1/orientos/vendor/limine}
ESP_MIB=${ESP_MIB:-96}
FS_BLOCKS=${FS_BLOCKS:-40960}
FS_INODES=${FS_INODES:-1024}
FS_KARTEN=${FS_KARTEN:-128}

mkdir -p "$OUT"
IMG="$OUT/osum-usb.img"

sagen() { printf '   %s\n' "$*"; }
fehler() { printf '== %s\n' "$*" >&2; exit 1; }

for w in sgdisk mkfs.vfat mmd mcopy python3; do
    command -v "$w" >/dev/null 2>&1 || fehler "$w fehlt"
done
[ -x "$LIMINE/limine" ] || fehler "limine fehlt: $LIMINE/limine (LIMINE_DIR setzen)"
[ -f "$LIMINE/BOOTX64.EFI" ] || fehler "BOOTX64.EFI fehlt in $LIMINE"
[ -f "$LIMINE/limine-bios.sys" ] || fehler "limine-bios.sys fehlt in $LIMINE"

# ============================================================ 1. Kern
bash vendor/firn/fetch-firnc.sh > "$OUT/firnc.log" 2>&1 \
    || fehler "der Uebersetzer laesst sich nicht bauen"
bash tools/build-kernel.sh "$OUT/osum.mb" --stufe "$STUFE" > "$OUT/k.log" 2>&1 \
    || { tail -20 "$OUT/k.log" >&2; fehler "der Kern laesst sich nicht bauen"; }
sagen "kern        $(stat -c%s "$OUT/osum.mb") Oktette"

# ====================================================== 2. Ring 3
# RUNDE MERGE-2: DIE DREI NAMEN SIND ENGLISCH. Der Zweig USBIMG ist von
# einem Stand vor der Runde RENAME-EN abgezweigt; dort hiessen die
# Programme noch `schreibtisch`, `leiste` und `einstellungen`. Die
# Dateien heissen seit RENAME-EN desktop.fi, taskbar.fi, settings.fi --
# und weil die Schleife unten fehlende Quellen still ueberspringt, sind
# die drei Programme sonst einfach nicht im Abbild, und erst die
# Pflichtliste in Abschnitt 5 faellt darueber ("FEHLT IM ABBILD:
# /bin/schreibtisch").
PROGS=${PROGS:-"desktop taskbar settings launcher explorer netview \
widgetdemo locate edit sh echo ls cat ps uname date df mkdir rm cp mv \
grep head tail wc find du chmod id whoami install opk mount umount sync \
touch true false sleep kill sort uniq rmdir tar \
dhcp host ota jsig jarvisctl pollbr reboot"}

# RUNDE STICK: DIE SIEBEN, DIE GEFEHLT HABEN -- UND WARUM AUSGERECHNET
# DIESE.
#
# `docs/BLECH-BEREIT.md` Abschnitt 7 hat die Liste selbst geschrieben:
# `ota`, `fetch`, `host`, `jarvisd`, `jsig`, `jarvisctl`, `pollbr` lagen
# in keinem Stick-Abbild. Der Kern konnte das Netz, die Programme waren
# gebaut und gemessen -- sie standen nur nicht in dieser Zeile. Also:
#
#   ota         das Update holen, pruefen, einspielen (profile kernel)
#   host        einen Namen aufloesen -- ohne ihn ist `store.fleitec.com`
#               eine Zeichenkette und keine Adresse
#   dhcp        die Adresse UND den Nameserver aus dem Netz. Ohne ihn
#               gibt es kein /etc/resolv.conf, und ohne das keinen Namen
#   jsig        der Ed25519-Ausweis des Geraets fuer die Bruecke
#   jarvisctl   die Bruecke bedienen (koppeln, Protokoll, Fotoschein)
#   pollbr      der Wartedienst der Runde POLL (hiess bis BLECH-ECHT
#               ebenfalls jarvisd, siehe docs/RUNDE-BLECH-ECHT.md 2.4)
#   reboot      nach `ota einspielen` will jemand neu starten
#
# UND ZWEI, DIE ANDERS GEBAUT WERDEN MUESSEN:
#
#   fetch       HTTPS mit TLS 1.3
#   jarvisd     die JARVIS-Bruecke, TLS 1.3 hinaus
#
# Beide sind `--profile=app` und binden gegen die VOLLE Firn-Bibliothek
# aus `vendor/firn/lib`, nicht gegen die libc dieses Repos. Der Grund
# steht in `tools/bridge/build.sh`: `crypto.sha512` dieses Repos und
# `std.crypto.sha512` von Firn heissen beide `sha512`, und der
# Uebersetzer fuehrt Module unter ihrem letzten Namen. Deshalb ZWEI
# Uebersetzungslaeufe in EINEM Abbild -- der Weg ist woertlich der aus
# `tools/install/build.sh` und `tools/bridge/build.sh`.
APPS=${APPS:-"fetch jarvisd"}

as --64 -o "$OUT/crt.o" kernel/user/crt.s || fehler "crt.s laesst sich nicht assemblieren"
gebaut=""
rc=0
for p in $PROGS; do
    [ -f "kernel/user/$p.fi" ] || continue
    if ! "$CC" "kernel/user/$p.fi" -o "$OUT/$p.o" > "$OUT/$p.err" 2>&1; then
        echo "== $p: der Uebersetzer sagt nein" >&2; head -20 "$OUT/$p.err" >&2
        rc=1; continue
    fi
    if ! ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F$STUFE.u_start" \
            -o "$OUT/$p.elf" "$OUT/crt.o" "$OUT/$p.o" 2> "$OUT/$p.lderr"; then
        echo "== $p: der Binder sagt nein" >&2; head -12 "$OUT/$p.lderr" >&2
        rc=1; continue
    fi
    strip --strip-all "$OUT/$p.elf"
    gebaut="$gebaut $p"
done
[ "$rc" = 0 ] || fehler "die Programme lassen sich nicht bauen"
sagen "programme   $(echo $gebaut | wc -w) Stueck"

# ------------------------------------------------ 2b. die zwei Apps
#
# KEIN crt.o: Firns eigenes `_start` ist der Eintrittspunkt, und es tut
# schon das, was Osums Lader erwartet.
#
# UND FIRNLIB BLEIBT AUF lib/ -- das ist der Weg aus tools/install/build.sh
# und er ist nicht willkuerlich. `fetch` braucht BEIDE Haelften:
# `std.io`, `std.net`, `tls.tls` von Firn und `libc.dns` aus diesem
# Repo. Der Uebersetzer sucht ein Modul erst in $FIRNLIB und danach in
# `<Verzeichnis des Uebersetzers>/../lib` -- und weil `firnc` unter
# vendor/firn/bin liegt, ist das genau vendor/firn/lib. Mit
# FIRNLIB=lib/ sind damit beide Haelften erreichbar; mit
# FIRNLIB=vendor/firn/lib faellt `libc.dns` heraus, und das sieht dann
# so aus:
#     error: cannot read 'kernel/app/libc/dns.fi'  --> fetch.fi:88
gebaut_app=""
for p in $APPS; do
    [ -f "kernel/app/$p.fi" ] || continue
    if ! FIRNLIB="$ROOT/lib" "$CC" -c --profile=app \
            -o "$OUT/app-$p.o" "kernel/app/$p.fi" > "$OUT/app-$p.err" 2>&1; then
        echo "== $p (app): der Uebersetzer sagt nein" >&2
        head -20 "$OUT/app-$p.err" >&2
        fehler "die Apps lassen sich nicht bauen"
    fi
    if ! ld -T kernel/user/user.ld -o "$OUT/$p.elf" "$OUT/app-$p.o" \
            2> "$OUT/app-$p.lderr"; then
        echo "== $p (app): der Binder sagt nein" >&2
        head -12 "$OUT/app-$p.lderr" >&2
        fehler "die Apps lassen sich nicht binden"
    fi
    strip --strip-all "$OUT/$p.elf"
    gebaut="$gebaut $p"
    gebaut_app="$gebaut_app $p"
done
if [ -n "$gebaut_app" ]; then
    asz=0
    for a in $gebaut_app; do asz=$((asz + $(stat -c%s "$OUT/$a.elf"))); done
    sagen "apps        $(echo $gebaut_app | wc -w) Stueck ($asz Oktette, TLS 1.3)"
fi
export FIRNLIB="$ROOT/lib"

# ================================================ 3. was sonst auf die Platte
python3 tools/netview/icons.py bauen "$OUT/icons" > "$OUT/icons.log" 2>&1 \
    || { tail -10 "$OUT/icons.log" >&2; fehler "die Symbole lassen sich nicht bauen"; }
SYMBOLE="state-nocarrier state-noip state-noroute state-online \
mark-filtered mark-faked mark-none sys-faking tile-fake tile-net tile-hide"
sagen "symbole     $(echo $SYMBOLE | wc -w) Stueck nach /etc/netview/"

python3 tools/k15/tree.py "$OUT/baum" > "$OUT/baum.log" 2>&1 \
    || fehler "tools/k15/tree.py fehlgeschlagen"

cat > "$OUT/passwd" <<'EOF'
root:x:0:0:root:/:/bin/sh
justin:x:1000:1000:Justin:/users/justin:/bin/sh
EOF
printf '# taskbar.conf\nedge=bottom\nheight=28\nwidth=104\nautohide=0\nontop=1\n' \
    > "$OUT/taskbar.conf"
# DIE SPRACHE DES STICKS IST DEUTSCH. Das ist die Wahl des Benutzers und
# steht deshalb unter /users/root/config/ und NICHT unter /etc/ -- die
# Regel aus docs/I18N.md, die tools/i18n/run.sh nachprueft.
printf 'de\n' > "$OUT/locale-de"

# ---------------------------------------------- RUNDE STICK: DAS NETZ
#
# Drei Dateien, und ohne sie sind die neuen Programme Zierde:
#
#   /etc/ssl/roots.pem   ohne Wurzelspeicher vertraut `fetch` NICHTS und
#                        sagt "no trust store". Genommen werden die
#                        Mozilla-Wurzeln des Wirts (tools/hwnet/mkroots.py) --
#                        dieselben, gegen die Runde MERGE-5 die echte
#                        Let's-Encrypt-Kette von store.fleitec.com
#                        geprueft hat. $OTA_ROOTS ueberschreibt.
#   /etc/ota.conf        WOHER. Ein NAME und keine Adresse: das Geraet
#                        loest ihn selbst auf (Runde BETRIEB). `auto=nein`
#                        bleibt -- ein Stick, der ab Werk von selbst
#                        nachfragt, waere eine Entscheidung, die niemand
#                        getroffen hat. Der Mensch tippt `ota suchen`.
#   /system/schluessel.pub  WEM. Ohne den vertrauten Schluessel nimmt
#                        `ota` kein Verzeichnis und `opk` kein Paket an.
#
# Fehlt der Schluessel, wird er NICHT erfunden: dann steht er nicht im
# Abbild, `ota` sagt es beim ersten Versuch, und das ist besser als eine
# Datei, die wie Vertrauen aussieht.
ROOTS=${OTA_ROOTS:-}
if [ -z "$ROOTS" ]; then
    if python3 tools/hwnet/mkroots.py "$OUT/roots.pem" > "$OUT/roots.log" 2>&1; then
        ROOTS="$OUT/roots.pem"
    fi
fi
if [ -n "$ROOTS" ] && [ -s "$ROOTS" ]; then
    sagen "wurzeln     $(stat -c%s "$ROOTS") Oktette, $(grep -c 'BEGIN CERT' "$ROOTS") Wurzeln"
else
    sagen "wurzeln     KEINE -- /bin/fetch wird nichts vertrauen"
fi

STORE=${STORE_URL:-https://store.fleitec.com/osum}
if [ -n "${OTA_CONF:-}" ] && [ -s "${OTA_CONF}" ]; then
    [ "$OTA_CONF" -ef "$OUT/ota.conf" ] || cp -f "$OTA_CONF" "$OUT/ota.conf"
else
    cat > "$OUT/ota.conf" <<EOFOTA
# /etc/ota.conf -- woher dieses Geraet seine Updates holt.
#
# quelle   ein NAME und keine Adresse. Das Geraet loest ihn ueber den
#          Nameserver auf, den ihm DHCP gegeben hat (Runde BETRIEB), und
#          prueft das Zertifikat gegen /etc/ssl/roots.pem.
# abstand  Sekunden zwischen zwei automatischen Suchen.
# auto     ja/nein. Vorgabe NEIN: gesucht wird, wenn jemand es sagt.
# frist    Sekunden, die der Wachhund auf den Erfolgsvermerk wartet.
quelle=$STORE/aktuell
abstand=3600
auto=nein
frist=120
EOFOTA
fi
sagen "ota.conf    quelle=$(grep -a '^quelle=' "$OUT/ota.conf" | head -1 | cut -d= -f2-)"

KEY=${OTA_KEY:-}
if [ -z "$KEY" ] && [ -s "${STORE_DIR:-/srv/store}/osum/aktuell/schluessel.pub" ]; then
    KEY="${STORE_DIR:-/srv/store}/osum/aktuell/schluessel.pub"
fi
printf '%08d\n' "${OTA_KGEN:-0}" > "$OUT/SCHLUESSELGEN"
# Die Fassung, mit der dieser Stick ausgeliefert wird. Neun Oktette
# fester Breite, wie /system/SCHLUESSELGEN -- `ota` vergleicht sie mit
# der Fassung im signierten VERZEICHNIS und lehnt alles ab, was nicht
# groesser ist (Rueckschrittsschutz).
printf '%08d\n' "${OTA_FASSUNG:-0}" > "$OUT/FASSUNG"

# ------------------------------------------- RUNDE STICK: DIE BRUECKE
#
# `/etc/jarvis/rechte.conf` MUSS da sein -- ohne Rechteliste sagt
# `jarvisd` "ohne Rechteliste ist nichts erlaubt" und hoert auf. Was
# drinsteht, ist die Vorgabe eines Geraets, das noch niemandem gehoert:
# KEIN Server, KEINE Befehle, KEIN Bildschirmfoto, KEINE Pfade. So
# gestartet meldet sich der Dienst nirgends an und fuehrt nichts aus.
# Wer ihn benutzen will, traegt Server und Rechte ein -- von Hand oder
# mit `jarvisd -c <eigene datei>`.
if [ -n "${JARVIS_CONF:-}" ] && [ -s "${JARVIS_CONF}" ]; then
    cp -f "$JARVIS_CONF" "$OUT/rechte.conf"
else
    cat > "$OUT/rechte.conf" <<'EOFJ'
# /etc/jarvis/rechte.conf -- was der JARVIS-Helfer auf DIESEM Geraet darf.
#
# Diese Datei wird VOR JEDEM AUFTRAG neu gelesen. Was hier nicht steht,
# ist nicht erlaubt; eine leere Liste heisst "nichts".
#
# server         = <adresse>:<port>   wo sich der Dienst MELDET (hinaus,
#                                     er macht keinen Anschluss auf)
# servername     = <name>             der Name, den das Zertifikat
#                                     tragen muss
# wurzeln        = /etc/ssl/roots.pem gegen welche Wurzeln geprueft wird
# befehle        = ja|nein            duerfen Programme laufen
# befehl_erlaubt = /bin/echo          und WELCHE (eine Zeile je Programm)
# bildschirmfoto = ja|nein
# systeminfo     = ja|nein
# lesen          = /var/jarvis/       welche Pfade gelesen werden duerfen
# schreiben      = /var/jarvis/
# auflisten      = /var/jarvis/
# max_ausgabe    = 4096
# max_datei      = 8192
#
# AB WERK IST ALLES AUS. Ein Stick, der sich beim ersten Start irgendwo
# meldet, waere eine Entscheidung, die niemand getroffen hat.
befehle        = nein
bildschirmfoto = nein
systeminfo     = nein
wurzeln        = /etc/ssl/roots.pem
EOFJ
fi

# ================================================== 4. das Dateisystem
ARGS=(build "$OUT/root.img" "$FS_BLOCKS" --v3
      "--inodes=$FS_INODES" "--karten=$FS_KARTEN")
ARGS+=(/lib/
       "/lib/mono.ttf=assets/osum-mono.ttf"
       "/lib/sans.ttf=assets/osum-sans.ttf"
       "/lib/icons.ttf=assets/osum-icons.ttf")
ARGS+=(/bin/)
for p in $gebaut; do ARGS+=("/bin/$p=$OUT/$p.elf"); done
ARGS+=("/bin/files@/bin/explorer")
ARGS+=(/etc/ "/etc/theme=$OUT/baum/theme" "/etc/passwd=$OUT/passwd"
       "/etc/taskbar.conf=$OUT/taskbar.conf")
ARGS+=(/etc/netview/)
for q in $SYMBOLE; do ARGS+=("/etc/netview/$q=$OUT/icons/$q"); done
ARGS+=(/usr/ /usr/share/ /usr/share/locale/
       /usr/share/locale/en/ "/usr/share/locale/en/messages=locale/en/messages"
       /usr/share/locale/de/ "/usr/share/locale/de/messages=locale/de/messages")
ARGS+=(/users/ /users/root/ /users/root/config/
       "/users/root/config/locale=$OUT/locale-de")
ARGS+=(/boot/ "/boot/osum.mb=$OUT/osum.mb"
       "/boot/BOOTX64.EFI=$LIMINE/BOOTX64.EFI")
ARGS+=(/dev/ /proc/ /mnt/ /tmp/ /store/ /apps/ /system/)
# RUNDE STICK: die Verzeichnisse, in denen die neuen Programme leben.
ARGS+=(/etc/ssl/ /etc/jarvis/ /var/ /var/log/ /var/jarvis/)
if [ -n "$ROOTS" ] && [ -s "$ROOTS" ]; then
    ARGS+=("/etc/ssl/roots.pem=$ROOTS")
fi
ARGS+=("/etc/ota.conf=$OUT/ota.conf")
ARGS+=("/etc/jarvis/rechte.conf=$OUT/rechte.conf")
ARGS+=("/system/SCHLUESSELGEN=$OUT/SCHLUESSELGEN")
ARGS+=("/system/FASSUNG=$OUT/FASSUNG")
if [ -n "$KEY" ] && [ -s "$KEY" ]; then
    ARGS+=("/system/schluessel.pub=$KEY")
    sagen "schluessel  $(stat -c%s "$KEY") Oktette aus $KEY"
else
    sagen "schluessel  KEINER -- ota nimmt kein Verzeichnis an"
fi
if [ -n "${OTA_ERSATZ:-}" ] && [ -s "${OTA_ERSATZ}" ]; then
    ARGS+=("/system/ersatz.pub=$OTA_ERSATZ")
fi
while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py assets/apps "$OUT/buendel")
while read -r z; do ARGS+=("$z"); done < "$OUT/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$OUT/mkfs.log" 2>&1 \
    || { tail -20 "$OUT/mkfs.log" >&2; fehler "mkfs.py fehlgeschlagen"; }
sagen "wurzel      $(stat -c%s "$OUT/root.img") Oktette OFS v3"

# ============================================ 5. NACHZAEHLEN, NICHT HOFFEN
PFLICHT="/usr/share/locale/de/messages /usr/share/locale/en/messages \
/lib/sans.ttf /lib/mono.ttf /lib/icons.ttf /users/root/config/locale \
/etc/netview/state-online /etc/netview/state-nocarrier \
/etc/netview/state-noip /etc/netview/state-noroute \
/etc/netview/mark-filtered /etc/netview/mark-faked /etc/netview/mark-none \
/etc/netview/sys-faking /etc/netview/tile-fake /etc/netview/tile-net \
/etc/netview/tile-hide /etc/theme /etc/taskbar.conf \
/bin/desktop /bin/taskbar /bin/netview /bin/explorer /boot/osum.mb \
/bin/ota /bin/fetch /bin/host /bin/dhcp /bin/jarvisd /bin/jsig \
/bin/jarvisctl /bin/pollbr /etc/ota.conf /etc/jarvis/rechte.conf \
/system/FASSUNG /system/SCHLUESSELGEN"
python3 tools/osum/mkfs.py list "$OUT/root.img" > "$OUT/liste.txt" 2>&1 \
    || fehler "das fertige Dateisystem laesst sich nicht lesen"
fehlt=0
for f in $PFLICHT; do
    grep -qE "(^|[[:space:]])${f}([[:space:]]|\$)" "$OUT/liste.txt" || {
        echo "== FEHLT IM ABBILD: $f" >&2; fehlt=$((fehlt + 1)); }
done
[ "$fehlt" = 0 ] || fehler "$fehlt Pflichtdatei(en) fehlen im Abbild"
sagen "geprueft    $(echo $PFLICHT | wc -w) Pflichtpfade im fertigen Dateisystem"

# DIE UMLAUTE. Sie stehen in locale/de/messages, sie muessen im ABBILD
# stehen, und ein 'ü' sind ZWEI Oktette -- was jede Feldbreitenrechnung
# angeht. Hier wird nur gezaehlt, dass sie ueberhaupt angekommen sind;
# gemessen wird es im Bild (tools/usbimg/run.sh).
UML=$(python3 -c '
import sys
d = open(sys.argv[1], "rb").read()
print(sum(d.count(c.encode("utf-8")) for c in "äöüßÄÖÜ"))
' "$OUT/root.img")
if [ "${UML:-0}" -lt 1 ]; then
    fehler "im Abbild steht kein einziger UTF-8-Umlaut"
fi
sagen "umlaute     $UML UTF-8-Umlautfolgen im fertigen Wurzelabbild"

# ================================================== 6. limine.conf
#
# VIER EINTRAEGE, UND DER ERSTE IST DER, DEN JUSTIN BRAUCHT.
#
#   1. DIAGNOSE, ANGEHALTEN. Kein Fensterserver, keine Shell, kein
#      Netz -- nur der Bericht, und danach bleibt der Bildschirm stehen
#      (`hwdiagstop`, kernel/hwdiag.fi). Das ist der Eintrag fuer einen
#      Rechner OHNE serielles Kabel: ablesen oder fotografieren, fertig.
#   2. DIAGNOSE UND SCHREIBTISCH. Derselbe Bericht, danach faehrt die
#      Oberflaeche hoch. Der Bericht steht dann auf der seriellen
#      Leitung; auf dem Schirm ueberzeichnet ihn der Fensterserver.
#   3. NUR SCHREIBTISCH.
#   4. VEKTOREINHEIT PRUEFEN (RUNDE MERGE-5, BLEIBT STEHEN). Derselbe
#      Bericht wie 1, aber mit dem Kernwort `vecproc`: vier Prozesse
#      schreiben ein nur zu ihnen passendes Muster in ALLE
#      Vektorregister, geben den Prozessor ab und sehen nach, ob sie
#      ihre eigenen Werte wiederfinden. Danach bleibt der Bildschirm
#      stehen. Das ist der EINE Punkt aus `docs/RUNDE-AVX.md`,
#      Abschnitt 8, der auf diesem Wirt nicht zu messen war -- Zen 1 hat
#      kein AVX-512 und QEMUs TCG kennt es nicht --, und er ist auf
#      echtem Blech in zwei Zeilen ablesbar:
#
#          fpu: mode=3  cr4=0x340620  xcr0=0xe7  size=2696  lazy=0
#          vec: width=3   ...   vec: bad=0   vec: clean=1
#
#      Die Anleitung dazu steht in `docs/AUFSETZEN.md`, Abschnitt 5.
#
# IN DEN BEIDEN SCHREIBTISCH-EINTRAEGEN STEHT KEIN `nokbd`: die Runden
# messen ohne Tastatur, weil ein Testlauf keine hat -- ein Mensch vor
# einem echten Rechner schon. `wmshell` startet /bin/sh in einem
# Terminalfenster, und `kmain.surface` wartet auf diese Shell; solange
# sie laeuft, laeuft der Schreibtisch. Ohne sie kaeme der Kern nach dem
# Zeichnen zurueck und schaltete ab.
cat > "$OUT/limine.conf" <<'EOF'
# limine.conf -- Osum auf dem Stick (Runde USBIMG)
timeout: 10
default_entry: 1
verbose: yes

/Osum -- Hardware-Diagnose (bleibt stehen)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: hwdiag hwdiagstop gfx nokbd nosched noproc nofs noring3

/Osum -- Diagnose und danach der Schreibtisch
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: hwdiag modfs osum gfx wm wig desk wmshell nosched noproc nofs

# RUNDE STICK: DIESER EINTRAG HAT JETZT AUCH EINE NETZKARTE. Ohne
# `nic` blieb der Schreibtisch fuer immer bei "kein Netz", und das
# Terminal darin konnte `dhcp` nicht fahren -- der Stapel stand gar
# nicht. Die Adresse ist dieselbe verbindungslokale Platzhalteradresse
# wie im Kommandozeilen-Eintrag; `dhcp` ersetzt sie.
/Osum -- nur der Schreibtisch (deutsch)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum gfx wm wig desk wmshell nic nip=169.254.10.1/16 nsvc=0 nwait=0 nosched noproc nofs

/Osum -- Vektoreinheit pruefen (bleibt stehen)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: hwdiag hwdiagstop vecproc gfx nokbd nosched noproc nofs noring3

# RUNDE STICK: DIE KOMMANDOZEILE MIT NETZ.
#
# Bis hierher konnte man auf dem Stick nur ZUSEHEN: Diagnose oder
# Schreibtisch. Es gab keinen Eintrag, in dem ein Mensch `dhcp`,
# `host`, `fetch`, `ota` oder `jarvisd` tippen kann -- und das waren
# genau die Programme, die auch nicht drauf waren.
#
# `nic` schaltet die Karte ein. WARUM DA TROTZDEM EINE ADRESSE STEHT,
# obwohl `dhcp` sie holen soll: `netsvc` startet den Stapel nur, wenn
# `nip=` etwas nennt -- ohne sagt der Kern "kein Netz im Kernel" und
# `/bin/dhcp` hat nichts, worauf es einen Socket aufmachen koennte
# (gemessen, 03.09.2026). 169.254.10.1/16 ist eine
# VERBINDUNGSLOKALE Adresse (RFC 3927): sie kollidiert per Definition
# mit keinem Heim- oder Firmennetz, und der erste `dhcp` ersetzt sie.
# `console=ttyS0` macht COM1 zu einem richtigen Terminal (Runde
# SERVERBUILD, kernel/sercon.fi): auf einem Server ohne Tastatur ist das
# der einzige Weg herein, und das Warten auf eine Zeile wird damit
# unbegrenzt statt vier Sekunden. Die PS/2- und USB-Tastatur laufen
# daneben weiter.
#
#     osum$ dhcp
#     osum$ host store.fleitec.com
#     osum$ fetch https://store.fleitec.com/index.json
#     osum$ ota suchen
#     osum$ jarvisd -n
/Osum -- Kommandozeile mit Netz (dhcp, host, fetch, ota, jarvisd)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum vfs nic nip=169.254.10.1/16 nsvc=0 nwait=0 console=ttyS0 nosched noproc nofs

# RUNDE SCHIRM: ZWEI EINTRAEGE FUER GROSSE SCHIRME.
#
# GEMESSEN: auf einem 3840x2160-Schirm gibt der Lader dem Kern von sich
# aus 1280x800 (docs/SCHIRM.md, Abschnitt "Unter dem Lader"). Der Kern
# kann das NICHT nachbessern -- nach ExitBootServices gibt es kein GOP
# mehr, und der Bochs-Weg, ueber den er ohne Lader den Modus setzt, ist
# auf echter Hardware nicht da. Wer den Modus will, muss ihn den LADER
# waehlen lassen, und genau das tun diese zwei Eintraege.
#
# Passt die Aufloesung dem Bildschirm nicht, faellt Limine auf seine
# Vorgabe zurueck; es bleibt also immer ein Bild.
/Osum -- Schreibtisch auf einem WQHD-Schirm (2560x1440)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    resolution: 2560x1440
    cmdline: modfs osum gfx wm wig desk wmshell nosched noproc nofs

/Osum -- Schreibtisch auf einem 4K-Schirm (3840x2160)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    resolution: 3840x2160
    cmdline: modfs osum gfx wm wig desk wmshell nosched noproc nofs
EOF

# ================================================== 7. das Abbild
FS_MIB=$(( ( $(stat -c%s "$OUT/root.img") + 1048575 ) / 1048576 ))
GES_MIB=$(( ESP_MIB + FS_MIB + 2 ))
rm -f "$IMG"
truncate -s "${GES_MIB}M" "$IMG"

sgdisk --clear \
    --new=1:2048:+${ESP_MIB}M --typecode=1:EF00 --change-name=1:"OSUM-EFI" \
    --new=2:0:0              --typecode=2:8300 --change-name=2:"OSUM-ROOT" \
    "$IMG" > "$OUT/sgdisk.log" 2>&1 || {
    cat "$OUT/sgdisk.log" >&2; fehler "sgdisk fehlgeschlagen"; }

P1_ANF=$(sgdisk --info=1 "$IMG" | grep -oE 'First sector: [0-9]+' | grep -oE '[0-9]+')
P2_ANF=$(sgdisk --info=2 "$IMG" | grep -oE 'First sector: [0-9]+' | grep -oE '[0-9]+')

# Die EFI-Partition wird EINZELN gebaut und dann hineingelegt: mkfs.vfat
# und mtools auf einen Bereich MITTEN in einer Datei zu richten geht nur
# ueber Schleifengeraete, und die braucht dieses Skript sonst nirgends.
dd if=/dev/zero of="$OUT/esp.img" bs=1M count="$ESP_MIB" status=none
mkfs.vfat -F 32 -n OSUMEFI "$OUT/esp.img" > "$OUT/vfat.log" 2>&1 \
    || { cat "$OUT/vfat.log" >&2; fehler "mkfs.vfat fehlgeschlagen"; }

mmd -i "$OUT/esp.img" ::/EFI ::/EFI/BOOT ::/boot 2>/dev/null
mcopy -i "$OUT/esp.img" "$LIMINE/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI || fehler "mcopy BOOTX64"
mcopy -i "$OUT/esp.img" "$LIMINE/limine-bios.sys" ::/limine-bios.sys || fehler "mcopy bios.sys"
mcopy -i "$OUT/esp.img" "$OUT/limine.conf" ::/limine.conf || fehler "mcopy conf"
mcopy -i "$OUT/esp.img" "$OUT/limine.conf" ::/boot/limine.conf || fehler "mcopy conf2"
mcopy -i "$OUT/esp.img" "$OUT/osum.mb" ::/osum.mb || fehler "mcopy kern"
mcopy -i "$OUT/esp.img" "$OUT/root.img" ::/root.img || fehler "mcopy wurzel"

dd if="$OUT/esp.img" of="$IMG" bs=512 seek="$P1_ANF" conv=notrunc status=none
dd if="$OUT/root.img" of="$IMG" bs=512 seek="$P2_ANF" conv=notrunc status=none

# UND DER BIOS-TEIL. `limine bios-install` schreibt seinen ersten Teil in
# den MBR-Bereich der Datei und traegt ein, wo `limine-bios.sys` liegt.
# Unter UEFI wird davon nichts angefasst; unter BIOS ist es der ganze
# Startweg.
"$LIMINE/limine" bios-install "$IMG" > "$OUT/limine.log" 2>&1 \
    || { cat "$OUT/limine.log" >&2; fehler "limine bios-install fehlgeschlagen"; }

sagen "abbild      $IMG"
sagen "            $(stat -c%s "$IMG") Oktette (${GES_MIB} MiB), GPT, EFI ${ESP_MIB} MiB + Wurzel ${FS_MIB} MiB"
sagen "            auf den Stick:  sudo dd if=$IMG of=/dev/sdX bs=4M conv=fsync status=progress"
exit 0
