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
touch true false sleep kill sort uniq rmdir tar"}

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
/bin/desktop /bin/taskbar /bin/netview /bin/explorer /boot/osum.mb"
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

/Osum -- nur der Schreibtisch (deutsch)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum gfx wm wig desk wmshell nosched noproc nofs

/Osum -- Vektoreinheit pruefen (bleibt stehen)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: hwdiag hwdiagstop vecproc gfx nokbd nosched noproc nofs noring3

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
