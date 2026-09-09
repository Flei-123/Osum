#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/usbimg/build.sh -- RUNDE USBIMG: EIN ABBILD, DAS AUF ECHTEM BLECH
# STARTET.
#
#   bash tools/usbimg/build.sh [ausgabeverzeichnis]
#   -> <ausgabeverzeichnis>/orientos-usb.img, mit dd auf einen Stick zu
#      schreiben. Der alte Name osum-usb.img liegt als VERWEIS daneben,
#      damit Lesezeichen und Skripte nicht brechen (Runde MESSTAFEL:
#      das Abbild ist das SYSTEM, also OrientOS -- der Kern darin
#      heisst weiter osum.mb).
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
#
#    RUNDE TUERSCHLOSS: UND DIE BUENDEL STEHEN JETZT AUCH DARIN.
#    `/bin/settings` war gebaut, 635 600 Oktette gross und im Abbild --
#    aber ohne `/apps/settings.osp/` stand es in keinem Menue und war
#    ueber die Oberflaeche nicht erreichbar (Runde DURCHKLICK, 3.9).
#    Die Pflichtliste hat das nicht gemerkt, weil sie nur nach `/bin`
#    gesehen hat: ein Programm ist auf diesem System aber erst dann
#    da, wenn es auch sein Buendel hat. Also stehen die sechs Buendel
#    hier, und ein siebtes, das jemand vergisst, faellt beim naechsten
#    Bau auf und nicht erst beim Durchklicken.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

OUT=${1:-/tmp/usbimg}
STUFE=${STUFE:-0}
CC=${FIRNC:-vendor/firn/bin/firnc}
LIMINE=${LIMINE_DIR:-/root/jarvis/projects/u_DiS4in7esMF1/orientos/vendor/limine}
ESP_MIB=${ESP_MIB:-96}
# RUNDE MERGE9: 65536 Bloecke (32 MiB) statt 40960 (20 MiB).
# GEMESSEN: das Abbild der Runde MERGE-8 hatte bei 40960 Bloecken noch
# free=8945, also 4,4 MiB frei. Certus ist 6 493 760 Oktette (6,19 MiB)
# und passte damit NICHT. Mit 65536 bleiben nach Certus noch rund 10 MiB
# fuer busybox, lua und sqlite.
# WARUM DAS GEHT: seit OFS v3 ist die Blockkarte MEHRBLOCKIG
# (SB_BMBLOCKS, kernel/fs.fi). FS_KARTEN=128 traegt 128*4096 = 524 288
# Bloecke = 256 MiB; 65536 Bloecke brauchen davon 16. Der Satz in
# STATUS-FREMDLAND.md ("4096 Bloecke = 2 MB je Platte") und der
# Kommentar in fs.fi:236 stammen aus der Zeit VOR OFS v3 und gelten
# nicht mehr -- das gebaute Abbild meldet bmblocks=128.
FS_BLOCKS=${FS_BLOCKS:-65536}
FS_INODES=${FS_INODES:-1024}
FS_KARTEN=${FS_KARTEN:-128}

mkdir -p "$OUT"
# ============================== RUNDE MARKE: DER NAME AUS EINER QUELLE
#
# Bis hierher stand "orientos" in dieser Zeile. Jetzt kommt er aus
# `marke.conf`, geschlagen von `OSUM_MARKE_*` aus der Umgebung -- genau
# wie im Kern und wie in der Vorlage
# /root/projects/freeviewer/src/brand.rs. Eine Umbenennung ist damit
# ein Bauaufruf:
#
#   OSUM_MARKE_PRODUKT="Xoffi OS" bash tools/usbimg/build.sh /tmp/bau
#
# `MARKE_DATEI` ist der abgeleitete Dateiname (PRODUKT kleingeschrieben,
# ohne Leerzeichen) -- die Entsprechung zu `reg_key()` in der Vorlage:
# abgeleitet, nicht gespeichert.
. tools/lib/marke.sh
marke_laden . || fehler "marke.conf laesst sich nicht lesen"

IMG="$OUT/${MARKE_DATEI}-usb.img"
# DER ALTE NAME BLEIBT ERREICHBAR. Er haengt am KURZnamen und nicht am
# Produktnamen -- Justins Lesezeichen zeigt auf osum-usb.img, und ein
# Verweis, der bei jeder Umbenennung mitwandert, waere kein Verweis.
IMG_ALT="$OUT/${MARKE_KURZ}-usb.img"

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
dhcp host ota jsig jarvisctl pollbr reboot shutdown power fas"}

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
# RUNDE TUERSCHLOSS: UND VIER, DIE GEBAUT WAREN UND TROTZDEM GEFEHLT HABEN.
#
#   shutdown    die Maschine AUSSCHALTEN. `kernel/user/shutdown.fi`
#               gibt es seit Runde K18 und es kann genau das, was ein
#               Herunterfahren ist (ueber init: SIGTERM an die Dienste,
#               warten, SIGKILL, sync, aushaengen, ACPI S5; ohne init
#               wenigstens sync und der Aufruf). Es stand nur nicht in
#               dieser Zeile -- Runde DURCHKLICK 7.4 hat daraus zu
#               Recht "kein Herunterfahren ueber die Oberflaeche"
#               gemacht: der einzige Weg aus dem System war der
#               Netzschalter, und der riskiert bei jedem Mal das
#               Dateisystem.
#   power       das Bedienprogramm der Energieverwaltung (Runde K18).
#               Gehoert daneben: wer ausschalten kann, will auch die
#               Helligkeit und den Akkustand sehen.
#   firnc, fas  DER UEBERSETZER UND SEIN ASSEMBLER -- der Punkt, an dem
#               dieses System aufhoert, ein Vorfuehrstueck zu sein.
#               `tools/k16/run.sh` ist mit 64/0 gruen: firnc laeuft AUF
#               Osum, liest eine .fi von der Platte, schreibt eine .s,
#               und `fas` macht daraus ein laufendes Programm. Beides
#               war im Abbild bisher nicht enthalten (DURCHKLICK 8.1:
#               "auf dem Stick laesst sich kein Firn-Programm
#               uebersetzen"). Ein selbsttragendes System, das sich
#               selbst nicht fortsetzen kann, ist keines.
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

# ======================================== 2c. DER UEBERSETZER SELBST
#
# RUNDE TUERSCHLOSS: `firnc` KOMMT MIT AUF DEN STICK.
#
# WARUM DAS DER WICHTIGSTE NACHTRAG DIESER RUNDE IST. Runde DURCHKLICK
# hat die vollstaendige Dateiliste des Abbilds gelesen und festgestellt
# (8.1): kein `firnc`, kein `fas` -- "auf dem Stick laesst sich kein
# Firn-Programm uebersetzen". Ein System, das sich selbst nicht
# fortsetzen kann, ist ein Vorfuehrstueck. `tools/k16/run.sh` ist dabei
# mit 64/0 gruen: der Uebersetzer LAEUFT auf Osum, er lag nur nicht
# darauf.
#
# WOHER DIE QUELLE KOMMT. `firnc` ist nicht Teil dieses Baums; es ist
# `bin/firnc1.fi` aus dem Firn-Baum, uebersetzt vom festgenagelten
# `firnc0` und gegen `kernel/user/user.ld` gebunden -- Abbild ab
# 0x40100000 statt 0x400000. Das ist woertlich der Weg aus
# `tools/k16/run.sh` Abschnitt 4, und er steht hier nicht noch einmal
# anders: dieselben zwei Befehle, damit nicht zwei Wege entstehen, aus
# derselben Quelle zwei verschiedene Uebersetzer zu machen.
#
# KEIN crt.o: `firnc1.fi` hat ein `fn main`, und dafuer erzeugt der
# Uebersetzer sein `_start` selbst (genau deshalb legt `kernel/elf.fi`
# den Argumentblock auf den Stapelzeiger).
#
# WENN DIE QUELLE FEHLT, ist das kein Abbruch: der Stick ist ohne
# Uebersetzer schlechter, aber nicht kaputt. Dann sagt diese Stelle,
# dass er fehlt, und der Rest laeuft weiter.
FIRNQ=""
for k in "${FIRN_REPO:-}" "$ROOT/../firn" "$ROOT/../../firn"; do
    [ -n "$k" ] && [ -f "$k/bin/firnc1.fi" ] && FIRNQ=$(cd "$k" && pwd) && break
done
if [ -n "$FIRNQ" ]; then
    if ( cd "$FIRNQ" && FIRNLIB="$FIRNQ/lib" "$ROOT/$CC" -c \
            -o "$OUT/firnc-osum.o" bin/firnc1.fi ) > "$OUT/firnc-osum.err" 2>&1 \
       && ld -T kernel/user/user.ld -o "$OUT/firnc.elf" "$OUT/firnc-osum.o" \
            2>> "$OUT/firnc-osum.err"; then
        strip --strip-all "$OUT/firnc.elf"
        gebaut="$gebaut firnc"
        sagen "uebersetzer $(stat -c%s "$OUT/firnc.elf") Oktette (firnc aus $FIRNQ)"
    else
        echo "== firnc laesst sich nicht fuer Osum bauen" >&2
        head -8 "$OUT/firnc-osum.err" >&2
        fehler "der Uebersetzer laesst sich nicht fuer den Stick bauen"
    fi
else
    echo "== HINWEIS: kein Firn-Baum gefunden, /bin/firnc fehlt im Abbild" >&2
fi

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
# ============================================== RUNDE STARTKNOPF
# Die Vorgaben der Leiste, nach Justins Vorlage (Windows 11):
#   labels=never    Programmknoepfe nur als Symbol -- ein Symbol wird
#                   nie abgeschnitten ("St", "Termina" waren die Folge
#                   einer festen Hoechstbreite, nicht von Platzmangel).
#   clock_seconds=1 Die Uhr tickt SICHTBAR. Ohne Sekunden wird die
#                   Leiste hoechstens einmal je Minute neu gemalt, und
#                   das ist von "eingefroren" nicht zu unterscheiden --
#                   genau der Befund, den Justin gemeldet hat.
#   clock_date=1    Datum daneben; die Feldbreite waechst mit.
#   hide_missing=1  Kein Symbol und kein Text fuer Hardware, die es
#                   nicht gibt. Das "kein Akku" auf einem Tischrechner
#                   war keine Auskunft.
#   height=40       28 war auf 3440x1440 ein Strich.
printf '# taskbar.conf\nedge=bottom\nheight=40\nwidth=104\nautohide=0\nontop=1\nalign=left\nlabels=never\nclock_seconds=1\nclock_date=1\nclock_weekday=0\nclock_lines=1\nhide_missing=1\n' \
    > "$OUT/taskbar.conf"

# ============================================ RUNDE ECHTHARDWARE-1
# DAS ABBILD BEKOMMT DAS AUSSEHEN, DAS DIE DEMO HATTE.
#
# Justin, vor den Fotos vom 09.09.: "alles komplett eckig -- nicht die
# Demo, die du mir damals gezeigt hast". Er hat recht, und der Grund
# stand nicht im Kernel, sondern in DIESER Datei.
#
# Die Demo (.design-shots/nachher/*.png) entstand mit
# tools/design/aufnahme.sh, und dieses Skript legt VIER Dinge ins
# Abbild, die hier bis heute fehlten:
#
#     /etc/theme.conf   scheme=, mode=, shape=
#     /etc/schemas/     die Farbschemata
#     /etc/shapes/      die Formsaetze (osum.shape: radius_window=12)
#     /etc/themes/      die fertigen Voreinstellungen
#
# OHNE /etc/shapes/ UND OHNE `shape=` BLEIBT `wlibc.met` AUF `classic`,
# und classic ist radius_window=0. Die Taskleiste ruft `form_push()`
# treu bei jedem Start -- sie schickt dann eben lauter Nullen an
# `wm.FM_RADIUS`, und der Server malt gehorsam rechteckig. Es war also
# nie ein fehlender Zeichenweg, es war eine fehlende Datei.
#
# Und die Farben: bis hierher kam /etc/theme aus tools/k15/tree.py --
# zwoelf DUNKLE Flaechenfarben aus Runde K15, ohne Schriftfarbe. Die
# Demo lief auf `scheme=day mode=light`. Das ist der zweite Teil von
# "die Farben passen nicht zusammen".
#
# GEWAEHLT IST `tageslicht`, weil dessen Preset Zeile fuer Zeile die
# Kombination der Demo ist (scheme=day, mode=light, shape=osum).
THEMA=${THEMA:-tageslicht}
lies_preset() {
    grep -a "^$1=" "assets/themes/$THEMA.preset" 2>/dev/null \
        | head -1 | cut -d= -f2-
}
T_SCHEME=$(lies_preset scheme); T_SCHEME=${T_SCHEME:-day}
T_MODE=$(lies_preset mode);     T_MODE=${T_MODE:-light}
T_SHAPE=$(lies_preset shape);   T_SHAPE=${T_SHAPE:-osum}
printf '# /etc/theme.conf -- Runde ECHTHARDWARE-1\nscheme=%s\nmode=%s\naccent=\nshape=%s\nlight_start=07:00\ndark_start=19:00\n' \
    "$T_SCHEME" "$T_MODE" "$T_SHAPE" > "$OUT/theme.conf"
sagen "thema       $THEMA (scheme=$T_SCHEME mode=$T_MODE shape=$T_SHAPE)"

# ==================== RUNDE BLECH-HID: DER NOTAUSGANG OHNE TASTATUR
#
# Justins erster Blech-Lauf hat den Stick gestartet und ein Bild
# gezeigt -- und keine Taste und keine Maus angenommen. Damit war jeder
# Befehl unerreichbar; `dhcp`, `host`, `fetch` und `ota` liegen auf dem
# Abbild und waren nicht zu tippen.
#
# Dieses Skript ist die Antwort darauf: der Menueeintrag "Netz-Selbstlauf"
# gibt es der Shell als Argument mit (Kernwort `netlauf`), sie faehrt es
# von oben nach unten, und danach bleibt der Bildschirm stehen. Ein Foto
# davon ist die erste Messung des Netzwegs auf echter Hardware -- ohne
# eine einzige Taste.
cat > "$OUT/netlauf.sh" <<'EOFNL'
echo "=================================================="
echo "  OSUM NETZ-SELBSTLAUF -- ohne Tastatur, ohne Maus"
echo "=================================================="
echo "-- 1. Adresse holen (dhcp)"
dhcp
echo "-- 2. was dabei herausgekommen ist"
cat /etc/resolv.conf
echo "-- 3. Namen aufloesen: store.fleitec.com"
host store.fleitec.com
echo "-- 4. holen: https://store.fleitec.com/index.json"
fetch https://store.fleitec.com/index.json
echo "-- 5. nach einer neuen Fassung sehen"
ota suchen
echo "=================================================="
echo "  ENDE DES NETZ-SELBSTLAUFS"
echo "=================================================="
EOFNL
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

# RUNDE MARKE, zweite Entwurfsentscheidung der Vorlage: "Ein
# Xoffi-Build darf sich nie zum FreeViewer aktualisieren." Der Feed
# gehoert zur MARKE. Ein umbenannter Bau holt damit nie die Pakete der
# anderen Marke. STORE_URL schlaegt beides -- das ist der Weg fuer
# einen Testspeicher und aendert an der Regel nichts.
STORE=${STORE_URL:-$MARKE_FEED}
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
# ============================================ RUNDE ECHTHARDWARE-1
# /etc/theme WIRD NICHT MEHR MITGELIEFERT -- UND DAS IST DER ZWEITE
# TEIL VON "DIE FARBEN PASSEN NICHT ZUSAMMEN".
#
# `wlibc.reload_inner` liest die Dateien in dieser Reihenfolge:
#   1. /etc/theme.conf   (scheme=, mode=, shape=)
#   2. /etc/schemas/<scheme>
#   3. /etc/shapes/<shape>
#   4. /etc/theme        -- ZULETZT, und es ueberschreibt alles davor
#
# Punkt 4 ist Absicht (eine Maschine aus Runde K15 soll aussehen wie
# vorher), aber die Datei, die dieser Stick bisher mitgab, kam aus
# tools/k15/tree.py und traegt ZWOELF DUNKLE FLAECHENFARBEN ohne eine
# einzige Schriftfarbe. Sie hat also das helle Tagschema wieder
# zugeschuettet -- gemessen am 09.09.: Schreibtisch hell (#f1f5f9),
# Panel dunkel (#26303c), weisse Schrift auf hellem Cyan. Genau das
# Bild, das Justin fotografiert hat.
#
# Ein Abbild, das ein Schema mitbringt, darf keine Ueberschreibungsdatei
# mitbringen. Wer eine eigene will, legt sie selbst an.
ARGS+=(/etc/ "/etc/passwd=$OUT/passwd"
       "/etc/taskbar.conf=$OUT/taskbar.conf"
       "/etc/theme.conf=$OUT/theme.conf"
       "/etc/netlauf.sh=$OUT/netlauf.sh")
# RUNDE ECHTHARDWARE-1: die drei Verzeichnisse, ohne die `shape=` und
# `scheme=` ins Leere zeigen. Derselbe Weg wie in
# tools/design/aufnahme.sh -- dieselben Dateien, damit der Stick zeigt,
# was die Demo gezeigt hat.
ARGS+=(/etc/schemas/)
for s_ in assets/schemes/*.scheme; do
    ARGS+=("/etc/schemas/$(basename "$s_" .scheme)=$s_")
done
ARGS+=(/etc/shapes/)
for s_ in assets/shapes/*.shape; do
    ARGS+=("/etc/shapes/$(basename "$s_" .shape)=$s_")
done
ARGS+=(/etc/themes/)
for s_ in assets/themes/*.preset; do
    ARGS+=("/etc/themes/$(basename "$s_" .preset)=$s_")
done
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
# RUNDE TUERSCHLOSS: EIN BEISPIEL ZUM UEBERSETZEN.
#
# Seit dieser Runde liegen `firnc` und `fas` auf dem Stick. Eine Quelle
# daneben zu legen kostet 591 Oktette und erspart dem, der es
# ausprobieren will, das Tippen einer Datei in einem Editor, den er
# gerade erst kennenlernt.
#
# Und es ist der Pruefstein fuer den Uebersetzer AUF dem System:
#     firnc /beispiel/hallo.fi -o /tmp/hallo.s
#     fas /tmp/hallo.s -o /tmp/hallo
#     /tmp/hallo ; echo $?     -> 42
ARGS+=(/beispiel/ "/beispiel/hallo.fi=assets/beispiel/hallo.fi")
# RUNDE STICK: die Verzeichnisse, in denen die neuen Programme leben.
ARGS+=(/etc/ssl/ /etc/jarvis/ /var/ /var/log/ /var/jarvis/)
if [ -n "$ROOTS" ] && [ -s "$ROOTS" ]; then
    ARGS+=("/etc/ssl/roots.pem=$ROOTS")
fi
# ================================ RUNDE MERGE9: DIE GROSSEN MITBRINGSEL
#
# Certus, busybox, lua und sqlite liegen NICHT in diesem Baum -- sie
# werden anderswo gebaut (Certus im eigenen Repo, die drei Fremdlinge
# nach tools/fremd/README.md). Wer sie hat, gibt ihren Pfad an; wer
# nicht, bekommt einen Stick ohne sie und keinen Abbruch. Genau so
# haelt es die Stelle oben mit `firnc`.
#
#   CERTUS=/pfad/certus  BUSYBOX=...  LUA=...  SQLITE=...
#
# WARUM SIE HIER STEHEN: das Wurzelabbild fasst seit dieser Runde
# 65536 Bloecke (32 MiB) statt 40960; Certus allein ist 6,19 MiB und
# passte vorher nicht (free war 4,4 MiB).
for mit in "CERTUS:/bin/certus" "BUSYBOX:/bin/busybox" \
           "LUA:/bin/lua" "SQLITE:/bin/sqlite3"; do
    mvar=${mit%%:*}; mziel=${mit##*:}
    mpfad=$(eval "printf '%s' \"\${$mvar:-}\"")
    if [ -n "$mpfad" ] && [ -s "$mpfad" ]; then
        ARGS+=("$mziel=$mpfad")
        gebaut="$gebaut ${mziel##*/}"
        sagen "mitbringsel $(stat -c%s "$mpfad") Oktette  $mziel aus $mpfad"
    elif [ -n "$mpfad" ]; then
        echo "== HINWEIS: $mvar=$mpfad ist leer oder fehlt -- $mziel bleibt weg" >&2
    fi
done
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
while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py assets/apps "$OUT/buendel" nur="$PROGS")
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
/etc/netview/tile-hide /etc/taskbar.conf /etc/netlauf.sh \
/etc/theme.conf /etc/shapes/osum /etc/shapes/classic \
/etc/schemas/day /etc/schemas/night /etc/themes/tageslicht \
/bin/desktop /bin/taskbar /bin/netview /bin/explorer /boot/osum.mb \
/bin/ota /bin/fetch /bin/host /bin/dhcp /bin/jarvisd /bin/jsig \
/bin/jarvisctl /bin/pollbr /etc/ota.conf /etc/jarvis/rechte.conf \
/system/FASSUNG /system/SCHLUESSELGEN \
/apps/explorer.osp/start /apps/editor.osp/start /apps/terminal.osp/start \
/apps/launcher.osp/start /apps/widgets.osp/start /apps/settings.osp/start \
/apps/settings.osp/INFO /apps/settings.osp/symbol \
/bin/shutdown /bin/power /bin/firnc /bin/fas /beispiel/hallo.fi"
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
# DAS HEREDOC BLEIBT ZITIERT ('EOF'), und der Name kommt ueber einen
# PLATZHALTER hinein, der danach ersetzt wird.
#
# Der erste Versuch war ein unzitiertes Heredoc mit ${MARKE_PRODUKT}
# darin -- und das waere ein echter Fehler gewesen: in einem
# unzitierten Heredoc fuehrt die Schale auch das aus, was in
# KOMMENTARZEILEN steht. In diesem Text stehen siebzehn Rueckwaerts-
# Anfuehrungszeichen (`Linux`, `dhcp`, `usbstop` ...), und jedes davon
# waere ein Befehlsaufruf beim Bauen geworden. Ein Platzhalter mit
# einem sed danach kann das nicht.
cat > "$OUT/limine.conf" <<'EOF'
# limine.conf -- @MARKE_PRODUKT@ auf dem Stick (Runde USBIMG)
#
# DIE NAMEN, UND WARUM SIE HIER AUSEINANDERGEHEN (Runde MESSTAFEL).
# docs/ROADMAP-UPDATE.md:28 sagt es seit langem: der KERN und das
# SYSTEM darum sind zwei Namen. Auf dem Schirm stand trotzdem ueberall
# der des Kerns. Justins Vergleich trifft: der Kern heisst Linux, der
# Startschirm sagt Ubuntu -- niemand nennt seine Verteilung "Linux 6.8".
#
# Ab hier: was der BENUTZER liest, traegt den PRODUKTnamen aus
# marke.conf. Was den KERN meint, traegt den KERNnamen -- die Datei
# /osum.mb, das Startprotokoll, die Fassungszeile, die Panikmeldungen.
# Genau wie `Linux` im dmesg steht und nicht im Startbildschirm.
#
# RUNDE MARKE: in dieser Datei steht deshalb KEIN Produktname mehr,
# auch nicht im Kommentar. Ein Kommentar, der den alten Namen nennt,
# ist nach der ersten Umbenennung schlicht falsch -- und er stuende
# ausgerechnet in der Datei, die der Bau fuer jede Marke neu schreibt.
# `docs/NAMING.md` steht dem nicht
# entgegen: jenes Dokument regelt DEUTSCH GEGEN ENGLISCH in Pfaden und
# Anzeigetexten, nicht den Produktnamen.
timeout: 20
default_entry: 1
verbose: yes

# ================== RUNDE MENUE: VIER EINTRAEGE FUER MENSCHEN, DER REST
# EINE ETAGE TIEFER.
#
# Hier standen zehn gleichwertige Eintraege untereinander. Das war eine
# gewachsene TESTLISTE, keine Auswahl: wer den Stick in einen fremden
# Rechner steckt, will den Schreibtisch, und musste ihn zwischen
# Vektoreinheit, USB-Diagnose und zwei Aufloesungsvarianten suchen.
#
# Oben stehen jetzt die vier, die ein Mensch wirklich waehlt. Alles
# uebrige liegt unter "Werkzeuge und Diagnose" -- ein Baumeintrag, den
# Limine seit Fassung 8 kann (ein Eintrag OHNE `protocol`, dessen Kinder
# einen Schraegstrich mehr haben). Nichts ist weg, nichts hat eine
# andere `cmdline`; es ist reine Ordnung.
#
# WARTEZEIT 20 SEKUNDEN, und danach startet der Standardeintrag von
# selbst -- ein echter Countdown, kein Warten auf eine Taste. Das ist
# genau der Fall, um den es die ganze Runde geht: auf einem Brett, auf
# dem die Tastatur nicht antwortet, MUSS das Menue von allein
# weiterlaufen, sonst kommt man nie bis zum Schreibtisch.
#
# `default_entry: 1` zeigt jetzt auf den Schreibtisch. Vorher war es
# ebenfalls die 1 -- nur stand dort die Hardware-Diagnose, und die
# BLEIBT ABSICHTLICH STEHEN. Der Stick lief also nach zehn Sekunden von
# selbst in einen Bericht, der nie weitergeht.

# ==================================================== RUNDE LEISTE
# `dhcp` STEHT JETZT IM HAUPTEINTRAG.
#
# Justin will den JARVIS-Helfer auf dem Blech. Der braucht eine Route
# ins Internet, und `nip=169.254.10.1/16` ist eine
# VERBINDUNGSLOS-Adresse: kein Tor, kein Nameserver, kein Weg hinaus.
# `dhcp` startet /bin/dhcp in Ring 3, sobald der Schreibtisch steht.
#
# DIE FESTE ADRESSE BLEIBT TROTZDEM STEHEN, und das ist Absicht: sie
# gilt, bis der Klient etwas Besseres bekommt. Kommt kein Angebot
# (kein Kabel, kein Server, kein Treiber fuer den Chip), bleibt der
# Rechner genau so bedienbar wie vorher -- nur eben ohne Netz. Ein
# Schreibtisch, der auf ein DHCP-Angebot WARTET, waere ein Rueckschritt.
#
# Was danach auf der Tafel steht, beantwortet die Frage ohne serielle
# Leitung: Zeile 22 (NETZ) zeigt Treiber, Bus, Verbindung und die
# Adresse, die der Stapel wirklich fuehrt.
/@MARKE_PRODUKT@ -- Schreibtisch
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum gfx wm wig desk wmshell wmdauer tafel herz absturzhalt nopuls tz=120 usb hidgen nic nip=169.254.10.1/16 nsvc=0 nwait=0 dhcp nosched noproc nofs

# ================== RUNDE MESSTAFEL: DERSELBE EINTRAG AUF ENGLISCH
#
# Beide Textkataloge liegen im Abbild (`/usr/share/locale/de/messages`
# und `.../en/messages`, beide in der PFLICHT-Liste weiter oben). Was
# fehlte, war der Schalter: die Sprache stand fest in
# /users/root/config/locale, und das Einstellungsprogramm, das sie
# umstellen kann, braucht Maus oder Tastatur -- also genau das, was bei
# Justin klemmt. `lang=en` setzt die Datei VOR dem ersten
# Ring-3-Programm; sonst aendert sich an diesem Eintrag nichts.

# ================== RUNDE ZWISCHENSPEICHER: DER EINE EINTRAG, DER DIE
# FRAGE MIT EINEM FOTO ENTSCHEIDET
#
# Justins Rechner hat KEINE eingebaute Grafik: der Rahmenpuffer ist ein
# PCIe-Fenster der RTX 3060. Er war bis zu dieser Runde WRITE-BACK
# abgebildet -- kleine Aenderungen (Taskleiste, Messtafel, ein Fenster)
# bleiben dann in der Zwischenspeicherhierarchie der CPU liegen und
# gehen nie ueber PCIe zur Karte. Nur das erste Vollbild (19,8 MB, mehr
# als jeder L3) verdraengt sich selbst und wird sichtbar. Genau das
# zeigt sein Foto: blauer Grund und Zeiger, sonst nichts.
#
# Der Kern bildet den Puffer seit dieser Runde write-combining ab. DIESER
# Eintrag ist die GEGENPROBE mit dem groebsten Mittel: `fbuc` schaltet
# den Zwischenspeicher fuer das Fenster ganz ab (PCD|PWT). Das ist
# langsam -- jeder Bildpunkt geht einzeln auf den Bus --, aber es kann
# per Bauart nichts liegenbleiben.
#
# ERSCHEINEN HIER TASKLEISTE, TERMINALFENSTER UND MESSTAFEL, waehrend
# sie im ersten Eintrag fehlen, dann ist die Ursache bewiesen und es
# war die Abbildungsart. Erscheinen sie auch hier nicht, ist sie
# widerlegt und der Fehler liegt woanders.
/@MARKE_PRODUKT@ -- Schreibtisch (Rahmenpuffer uncached, Test)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum gfx fbuc wm wig desk wmshell wmdauer tafel herz absturzhalt nopuls tz=120 usb hidgen nic nip=169.254.10.1/16 nsvc=0 nwait=0 nosched noproc nofs

# ============ RUNDE BLECHEINGABE: DER ZWEITE, UNABHAENGIGE BEWEIS
#
# `fbuc` bildet den Rahmenpuffer ohne Zwischenspeicher ab -- eine andere
# ABBILDUNG. `fbflush` laesst die Abbildung, wie sie ist (write-combining
# seit der Vorrunde), und raeumt nach jedem Blit den ganzen
# Zwischenspeicher mit `wbinvd` hinaus. Zwei verschiedene Mittel gegen
# DIESELBE Ursache: hilft eines von beiden und das erste nicht, lag es am
# Zwischenspeicher. Hilft keines, lag es woanders -- und dann sagen die
# zwei Herzschlagfelder am rechten Bildrand, wo.
/@MARKE_PRODUKT@ -- Schreibtisch (Cache leeren je Bild, Test)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum gfx fbflush wm wig desk wmshell wmdauer tafel herz absturzhalt nopuls tz=120 usb hidgen nic nip=169.254.10.1/16 nsvc=0 nwait=0 nosched noproc nofs

# ============ RUNDE BLECHZWEI: DER DRITTE VERGLEICHSFALL
#
# GEMESSEN, Vollbild-Blit in QEMU, alle drei Betriebsarten mit
# demselben Kern und derselben Aufloesung:
#
#   write-combining (Vorgabe)   1 751 us   PDE 10E3
#   write-back      (`fbwb`)    3 402 us   PDE 00E3
#   uncached        (`fbuc`)  396 531 us   PDE 00FB
#
# UC ist 226-mal langsamer als WC. Der Eintrag ist deshalb AUSDRUECKLICH
# ein Messeintrag und kein Betriebsmodus -- er macht das Bild sichtbar,
# aber der Rechner verbringt seine Zeit im Bildspeicher. `fbwb` ist die
# dritte Ecke des Dreiecks: schnell, aber es kann liegenbleiben.
/@MARKE_PRODUKT@ -- Schreibtisch (Rahmenpuffer write-back, Test)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum gfx fbwb wm wig desk wmshell wmdauer tafel herz absturzhalt nopuls tz=120 usb hidgen nic nip=169.254.10.1/16 nsvc=0 nwait=0 nosched noproc nofs

# ============================================ RUNDE BLECHFUENF
# DER DIAGNOSE-EINTRAG, UND WARUM ER EIN EIGENER IST.
#
# Justin hat gemeldet, dass an seiner Tastatur die Lampen DAUERND
# blinken und Nummernfeststell sich nicht mehr schalten laesst. Das war
# der LED-Herzschlag aus der Runde BLECHVIER: er legt zweimal je Sekunde
# die Rollen-Lampe ueber den Tastenzustand. Als Messgeraet hat er seine
# Frage beantwortet (der Zeitgeber laeuft, HZ 99); als Dauerzustand
# macht er die Feststelltasten unbrauchbar. Dasselbe gilt fuer die zwei
# blinkenden Kaestchen am rechten Bildrand, die er fuer einen
# Zeichenfehler gehalten hat.
#
# Beides haengt jetzt an `pulsled` und ist in den Schreibtisch-
# Eintraegen AUS. Hier ist es an -- fuer den Fall, dass wieder einmal
# ohne Bild und ohne serielle Leitung entschieden werden muss, ob
# ueberhaupt noch etwas laeuft.
/@MARKE_PRODUKT@ -- Schreibtisch (Diagnose: Lampe und Blinkfelder)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum gfx wm wig desk wmshell wmdauer tafel herz pulsled absturzhalt tz=120 usb hidgen nic nip=169.254.10.1/16 nsvc=0 nwait=0 nosched noproc nofs

/@MARKE_PRODUKT@ -- Desktop (English)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum gfx wm wig desk wmshell wmdauer tafel herz absturzhalt nopuls tz=120 usb hidgen nic nip=169.254.10.1/16 nsvc=0 nwait=0 nosched noproc nofs lang=en

/@MARKE_PRODUKT@ -- Kommandozeile mit Netz
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum vfs usb hidgen nic nip=169.254.10.1/16 nsvc=0 nwait=0 console=ttyS0 nosched noproc nofs

# ============ RUNDE BLECH-HID: DER NETZ-SELBSTLAUF, OHNE EINE TASTE
#
# Der Eintrag, den Justin am 03.09.2026 gebraucht haette und nicht
# hatte. Der Stick startete, zeigte ein Bild -- und nahm keine Eingabe
# an; damit war jeder der 52 Befehle auf dem Abbild unerreichbar.
#
# `netlauf` gibt der Shell `/etc/netlauf.sh` als Argument mit
# (`kernel/kmain.fi`, Abschnitt `osum`), sie faehrt es von oben nach
# unten -- `dhcp`, `resolv.conf`, `host store.fleitec.com`,
# `fetch https://store.fleitec.com/index.json`, `ota suchen` -- und
# danach BLEIBT DER BILDSCHIRM STEHEN (`hwdiag.park_after_shell`). Ein
# Foto davon ist die erste Messung des Netzwegs auf echtem Blech.
#
# `usb hidgen` steht mit drin, obwohl niemand tippen muss: findet der
# Baum Tastatur und Maus, sagt der Bericht das mit -- und dann weiss
# Justin im selben Foto, ob die Uebernahme dieser Runde greift.

/@MARKE_PRODUKT@ -- Hardware-Diagnose (bleibt stehen)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: hwdiag hwdiagstop gfx nokbd nosched noproc nofs noring3

# ================== RUNDE BLECH-HID: DIE USB-DIAGNOSE, DIE ANFASST
#
# Eintrag 1 darueber bleibt Oktett fuer Oktett, wie er war -- er haelt
# VOR jedem Treiber an und ist damit der Eintrag, der auf JEDER Maschine
# bis zum Bericht kommt. Er hat seit dieser Runde eine LESENDE
# USB-Uebersicht am Ende (`usb: regler=`, je Regler eine Zeile mit
# `besitz=BIOS|OS|frei`, `strom=`, `verbunden=`).
#
# DIESER Eintrag hier geht weiter: er nimmt der Firmware die Regler ab
# (`usb`), zaehlt auf, prueft die Uebernahme an einer gebauten
# Faehigkeitsliste (`usbleg`) und haelt danach an (`usbstop`). Was dabei
# gedruckt wird, ist der volle Bericht -- je Regler die
# Halbleiter-Semaphore vor und nach der Uebernahme, HCRST, und dann
# jeder Anschluss einzeln mit PP, CCS, PED, PR und Tempo.
#
# WARUM ZWEI EINTRAEGE UND NICHT EINER: der erste fasst nichts an und
# kann deshalb nicht haengen. Wenn dieser hier auf einem fremden Brett
# stehenbleibt, ist der andere immer noch da.

# ------------------------------------------------------------------
# DER BAUMEINTRAG. Er hat selbst KEIN `protocol` -- genau daran
# erkennt Limine ein Untermenue statt eines Starteintrags.
#
# ZU DEN ZWEI AUFLOESUNGSEINTRAEGEN, und warum sie NICHT verschwinden:
# Justins Vorschlag war, die Aufloesung einfach von der Firmware
# uebernehmen zu lassen. Das tut der Lader bereits -- alle Eintraege
# ohne `resolution:` bekommen, was die Firmware anbietet, und auf
# Justins 3440x1440 ist das richtig. Es ist nur NICHT verlaesslich:
# gemessen (docs/SCHIRM.md, "Unter dem Lader") gibt derselbe Lader auf
# einem 3840x2160-Schirm von sich aus 1280x800. Nach
# ExitBootServices gibt es kein GOP mehr, der Kern kann das also nicht
# nachbessern. Wer auf so einem Schirm ein scharfes Bild will, muss den
# LADER waehlen lassen -- deshalb bleiben die zwei Eintraege. Sie
# gehoeren nur nicht ins Hauptmenue.
/Werkzeuge und Diagnose

//@MARKE_PRODUKT@ -- Diagnose und danach der Schreibtisch
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: hwdiag modfs osum gfx wm wig desk wmshell wmdauer tafel herz usb hidgen nosched noproc nofs

# RUNDE STICK: DIESER EINTRAG HAT JETZT AUCH EINE NETZKARTE. Ohne
# `nic` blieb der Schreibtisch fuer immer bei "kein Netz", und das
# Terminal darin konnte `dhcp` nicht fahren -- der Stapel stand gar
# nicht. Die Adresse ist dieselbe verbindungslokale Platzhalteradresse
# wie im Kommandozeilen-Eintrag; `dhcp` ersetzt sie.

//@MARKE_PRODUKT@ -- USB-Diagnose: Regler und jeder Anschluss
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: hwdiag usb hidgen usbleg usbstop gfx nokbd nosched noproc nofs noring3

//@MARKE_PRODUKT@ -- Netz-Selbstlauf ohne Tastatur (dhcp, ota)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum vfs netlauf usb hidgen nic nip=169.254.10.1/16 nsvc=0 nwait=0 console=ttyS0 nosched noproc nofs

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

//@MARKE_PRODUKT@ -- Vektoreinheit pruefen (bleibt stehen)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: hwdiag hwdiagstop vecproc gfx nokbd nosched noproc nofs noring3

# ================= RUNDE VIELKERN 3: DER EINTRAG FUER DAS BLECH
#
# Bis zur Runde BLECHKERN lief die ganze Oberflaeche auf EINEM Kern --
# nicht aus Bequemlichkeit, sondern weil `syscall_entry` den Kernstapel
# aus einem Wort fuer die ganze Maschine holte. Justins Foto vom 05.09.
# (`VEK 6 #UD RIP 0x80`, Kern 2) ist genau das gewesen.
#
# Der Unterbau dafuer steht seit VIELKERN 1 (Kernstapel je Kern ueber
# die GS-Basis), und seit VIELKERN 3 kommt auch der volle Schreibtisch
# damit hoch -- die zweite Ursache war ein Inodepuffer fuer die ganze
# Maschine (`fs.inode_get`), der nur solange hielt, wie nie zwei Kerne
# gleichzeitig hinsahen.
#
# GEMESSEN IST DAS BISHER NUR IN QEMU (-smp 1, 4 und 8). DIESER EINTRAG
# IST DIE MESSUNG AUF BLECH, und er ist deshalb ein EIGENER Eintrag und
# keine Aenderung am Schreibtisch darueber: geht etwas schief, nimmt
# man den anderen.
#
# WAS AUF DEM SCHREIBTISCH-EINTRAG ZU FOTOGRAFIEREN IST -- Tafelzeile 23,
# unten rechts:
#
#     23 SICHER WA 0 KS <n> R3W 0 R3K <n> LG 0
#
#   R3K   auf WIE VIELEN Kernen Ring 3 wirklich gelaufen ist. Auf
#         Justins Brett muss dort etwas GROESSER ALS 1 stehen; steht
#         dort 1, hat kein Anwendungskern einen Prozess bekommen.
#   R3W   Kerne, deren GS-Basis NICHT auf ihren eigenen Satz zeigt.
#         MUSS 0 sein. Steht dort etwas anderes, hat der Riegel in
#         `sched.darf_ring3` gegriffen und Ring 3 auf Kern 0 gehalten
#         -- die Maschine lebt dann, aber die Runde ist nicht erfuellt.
#   WA    Ueberlauf einer Kernstapel-Waechterseite. MUSS 0 sein.
#
# Und Zeile 7 (LEISTE) sagt, ob der Schreibtisch dabei wirklich malt.
# DER SCHREIBTISCH-EINTRAG GANZ OBEN BRAUCHT DAFUER KEIN WORT MEHR:
# seit VIELKERN 3 ist Ring 3 auf allen Kernen die VORGABE. Was hier
# steht, sind die beiden Eintraege, mit denen sich das ueberpruefen und
# zurueckdrehen laesst.
#
# DIE RUECKFALLEBENE. `r3eins` haelt Ring 3 auf Kern 0 -- Oktett fuer
# Oktett das Verhalten der Runde BLECHKERN. Wenn der Schreibtisch mit
# allen Kernen auf diesem Brett nicht so laeuft wie mit einem, ist das
# der Eintrag, der es beweist: derselbe Kern, dieselbe Wurzel, ein Wort
# Unterschied.
/@MARKE_PRODUKT@ -- Schreibtisch, Ring 3 nur Kern 0 (Rueckfall)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum r3eins gfx wm wig desk wmshell wmdauer tafel herz absturzhalt nopuls tz=120 usb hidgen nic nip=169.254.10.1/16 nsvc=0 nwait=0 dhcp nosched noproc nofs

# Und die GEGENPROBE dazu, auf demselben Stick: `gsluege` gibt jedem
# Anwendungskern eine FALSCHE GS-Basis. Der Riegel MUSS das sehen und
# Ring 3 auf Kern 0 halten -- auf der Tafel steht dann `R3W` groesser
# null und `R3K 1`, UND DIE MASCHINE LAEUFT WEITER. Das ist derselbe
# Nachweis, den tools/vielkern/run.sh in QEMU fuehrt, nur auf Blech.
# (`r3blind` gibt es auf dem Stick absichtlich NICHT: das ist der
# Eintrag, der die Maschine mit Absicht umbringt, und der gehoert in
# den Pruefstand und nicht in die Hand eines Menschen vor einem
# echten Rechner.)
/@MARKE_PRODUKT@ -- Gegenprobe: falsche GS-Basis (Riegel haelt?)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum r3alle gsluege gfx wm wig desk wmshell wmdauer tafel herz absturzhalt nopuls tz=120 usb hidgen nic nip=169.254.10.1/16 nsvc=0 nwait=0 nosched noproc nofs

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

//@MARKE_PRODUKT@ -- Schreibtisch auf einem WQHD-Schirm (2560x1440)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    resolution: 2560x1440
    cmdline: modfs osum gfx wm wig desk wmshell wmdauer tafel herz usb hidgen nosched noproc nofs

//@MARKE_PRODUKT@ -- Schreibtisch auf einem 4K-Schirm (3840x2160)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    resolution: 3840x2160
    cmdline: modfs osum gfx wm wig desk wmshell wmdauer tafel herz usb hidgen nosched noproc nofs

EOF

# Und JETZT der Name hinein. `@MARKE_PRODUKT@` ist der einzige
# Platzhalter in dieser Datei; bleibt einer stehen, bricht der Bau ab --
# ein Bootmenue, in dem "@MARKE_PRODUKT@" steht, waere schlimmer als
# eines mit dem alten Namen.
sed -i "s|@MARKE_PRODUKT@|$MARKE_PRODUKT|g" "$OUT/limine.conf" \
    || fehler "der Produktname liess sich nicht in limine.conf einsetzen"
if grep -q '@MARKE_PRODUKT@' "$OUT/limine.conf"; then
    fehler "in limine.conf steht noch ein Platzhalter"
fi
# RUNDE BLECH2: KEIN MENUEEINTRAG LAENGER ALS 60 ZEICHEN. Justins Foto
# vom 05.09.: "OrientOS -- Schreibtisch (Zwischenspeicher nach jedem Bild
# lee" -- Limine schneidet den Text an der Spaltenzahl des Menues ab, und
# der Rest stand nirgends. Gezaehlt wird NACH dem Einsetzen des
# Produktnamens: ein laengerer Name aus marke.conf nimmt dem Rest den
# Platz, und dann soll der Bau das sagen und nicht der Bildschirm.
zu_lang=$(grep -E '^/' "$OUT/limine.conf" | sed 's|^/*||' | awk 'length($0) > 60')
if [ -n "$zu_lang" ]; then
    fehler "Menueeintrag laenger als 60 Zeichen: $zu_lang"
fi
sagen "menue       $(grep -cE '^/' "$OUT/limine.conf") Eintraege, laengster $(grep -E '^/' "$OUT/limine.conf" | sed 's|^/*||' | awk '{ if (length($0) > m) m = length($0) } END { print m }') Zeichen"

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

# RUNDE MESSTAFEL: DER ALTE NAME BLEIBT ERREICHBAR. Ein Verweis und
# keine Kopie -- zwei Dateien mit demselben Inhalt sind zwei Dinge, die
# auseinanderlaufen koennen, und genau daran ist diese Runde schon
# einmal fast gescheitert.
ln -sf "$(basename "$IMG")" "$IMG_ALT"

sagen "abbild      $IMG"
sagen "            (alter Name als Verweis: $IMG_ALT)"
sagen "            $(stat -c%s "$IMG") Oktette (${GES_MIB} MiB), GPT, EFI ${ESP_MIB} MiB + Wurzel ${FS_MIB} MiB"
sagen "            auf den Stick:  sudo dd if=$IMG of=/dev/sdX bs=4M conv=fsync status=progress"
exit 0
