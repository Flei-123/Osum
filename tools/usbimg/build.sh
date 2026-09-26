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
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/sperre.sh" && osum_sperre "$OUT"   # A-024
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

# ============================================ ROUND LIVE: TWO IMAGES
#
#   IMAGE_PROFILE=personal  (default) Justin's own test stick and every
#                           acceptance run in this tree: the accounts
#                           `root` and `justin` with the start passwords
#                           below, the normal sign-in screen, and -- if
#                           JARVIS_CONF is given -- his bridge settings.
#   IMAGE_PROFILE=public    the DOWNLOAD image (store.fleitec.com/abbilder,
#                           built ONLY through tools/usbimg/publish.sh).
#                           A live system like a Linux live stick: no
#                           personal account, the generic user `live`
#                           (password `live`) is signed in automatically,
#                           root is locked, the bridge is off and cannot
#                           be switched on at build time, the screen does
#                           not lock by itself, and the boot menu offers
#                           "Install OrientOS" as its second entry.
#
# WHY THE DEFAULT STAYS `personal`: forty acceptance runs in this tree
# build through this script and sign in as `justin`. The public image is
# protected by the ONE way it is published -- publish.sh builds with
# IMAGE_PROFILE=public and refuses to copy an image whose /etc/passwd,
# /etc/shadow or /users/ name anyone but root and live.
IMAGE_PROFILE=${IMAGE_PROFILE:-personal}
case "$IMAGE_PROFILE" in
    personal|public) ;;
    *) fehler "IMAGE_PROFILE=$IMAGE_PROFILE (personal oder public)" ;;
esac
if [ "$IMAGE_PROFILE" = public ]; then
    [ -z "${JARVIS_CONF:-}" ] \
        || fehler "JARVIS_CONF gehoert nicht in das oeffentliche Abbild"
    [ -z "${PW_JUSTIN:-}" ] \
        || fehler "PW_JUSTIN gehoert nicht in das oeffentliche Abbild"
    KONTO=${LIVE_USER:-live}
    KONTO_NAME="Live user"
else
    KONTO=justin
    KONTO_NAME=Justin
fi

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
# ================================================ RUNDE ECHTHARDWARE-5
# `taskmgr` MUSSTE HIER STEHEN, UND ER STAND NICHT DA.
#
# Justins Befund F: "Taskmanager und Einstellungen lassen sich nicht
# oeffnen, die Knoepfe im Kontrollzentrum reagieren nicht."
#
# NACHGEWIESEN, nicht vermutet: die Wurzelpartition des ausgelieferten
# Abbildes orientos-usb-20260910-44a5af3.img, ausgelesen mit
#
#     python3 tools/osum/mkfs.py list <wurzel.img>
#
# hat 177 Inoden und darunter KEIN /bin/taskmgr. Das Kontrollzentrum
# startet aber genau diesen Pfad (kernel/user/qs.fi, `p_taskmgr`).
# Ein Knopf, dessen Programm nicht auf der Platte liegt, kann nicht
# reagieren -- und weil `SYS_EXEC` still fehlschlaegt, sah es aus, als
# waere der Knopf kaputt.
#
# `/bin/settings` LAG im Abbild; der Einstellungsknopf hat deshalb eine
# andere Ursache und wird getrennt behandelt.
# RUNDE INSTALLER (P-001): `installer` MUSS HIER STEHEN.
#
# Dieselbe Falle wie bei `taskmgr` in Runde ECHTHARDWARE-5 und bei
# `settings` in Runde TUERSCHLOSS: das Programm ist gebaut, das
# Buendel liegt unter assets/apps/ -- und wenn der Name hier fehlt,
# ist es trotzdem nicht auf dem Stick. Der Starter zeigt dann einen
# Eintrag, dessen Programm es nicht gibt, und `SYS_EXEC` schlaegt
# STILL fehl: es sieht aus, als reagiere der Knopf nicht.
#
# Und ausgerechnet dieses Programm darf nicht fehlen -- es ist der
# einzige Weg vom Stick auf eine Platte, und ein Stick, der sich
# nicht installieren laesst, bleibt ein Vorfuehrstueck.
# ============ INTEGRATIONSRUNDE 19.09.2026: `nedit` HAT HIER GEFEHLT.
#
# Die Runde GUI-EDITOR hat /bin/nedit gebaut, gemessen (18/0) und ein
# Buendel dafuer angelegt (assets/apps/nedit.osp). In DIESE Zeile ist
# es nie eingetragen worden -- und `tools/k15/bundle.py` bekommt
# `nur="$PROGS"`, filtert das Buendel also mit heraus. Ergebnis: auf
# dem Stick gab es den neuen Editor nicht, weder unter /bin noch im
# Startmenue, und der alte Zeileneditor `edit` war weiterhin das
# einzige, was "Editor" hiess.
#
# GEMESSEN in der Integrationspruefung: ein Lauf des fertigen Abbilds
# fand `/bin/nedit` nicht im Wurzelabbild (grep -c nedit root.img = 0),
# waehrend derselbe Quellbaum in tools/alltag/build.sh 18/0 meldete --
# die Abnahme baut ihre eigene Platte und hatte nedit in ihrer Liste.
# Genau so sieht ein Programm aus, das "fertig" ist und trotzdem bei
# niemandem ankommt.
#
# ============ RUNDE DREI 22.09.2026: `papierkorb` HAT HIER GEFEHLT --
# ZUM DRITTEN MAL DERSELBE FEHLER (nach `nedit` und `bold.ttf`).
#
# `kernel/user/papierkorb.fi` ist seit Runde ALLTAG fertig: ein Fenster
# mit Tabelle und vier Knoepfen (Zurueckholen, Entfernen, Leeren, Neu
# lesen), und `tools/alltag/run.sh` misst es mit `progs="... papierkorb
# ..."` in SEINER eigenen Liste. In DIESER Zeile stand es nie.
#
# WAS DAS BEDEUTET HAT: der Dateimanager loescht mit Entf in den Korb
# (`expakt.in_korb` -> `trash.hinein`) und bietet ihn in der
# Seitenleiste und unter "Gehe zu" als Ort an -- aber das Programm, mit
# dem man etwas WIEDERHERSTELLT, lag auf dem Stick nicht. Gelegtes kam
# hinein und nicht wieder heraus, ausser von Hand auf der
# Kommandozeile. Genau der Rest, den OFFEN.md unter D-016
# "Wiederherstellen aus der Oberflaeche" fuehrt.
#
# `edit` BLEIBT: es ist das Terminalprogramm (kein wlib), und die
# Abnahme der Runde GUI-EDITOR prueft ausdruecklich, dass es
# unveraendert eines ist.
PROGS=${PROGS:-"desktop taskbar settings launcher explorer netview \
widgetdemo taskmgr installer dualcli locate edit nedit papierkorb sh echo ls cat ps uname date df mkdir rm cp mv \
grep head tail wc find du chmod id whoami install opk mount umount sync \
touch true false sleep kill sort uniq rmdir tar \
dhcp log host ota jsig jarvisctl pollbr reboot shutdown power fas \
glogin lock login passwd su chown sperrwache init svc"}

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
# ROUND ROADMAP-5 (K-008): `drucke` prints over IPP -- same build path
# (profile app, TrueType reader from the library), see kernel/app/drucke.fi.
APPS=${APPS:-"fetch jarvisd drucke"}

as --64 -o "$OUT/crt.o" kernel/user/crt.s || fehler "crt.s laesst sich nicht assemblieren"
gebaut=""
rc=0
# RUNDE ABBILD: EIN PROGRAMM IM PROFIL `app` WIRD ANDERS GEBAUT.
#
# Seit Runde 31 kommen die Bedienelemente der Oberflaeche aus fUi, und
# fUi rechnet in f64 und benutzt `std.rt` -- beides ist im Profil
# `kernel` gesperrt. Wessen Wurzeldatei deshalb `profile app` sagt
# (desktop, settings, launcher, explorer, widgetdemo), braucht ZWEI
# Unterschiede, und ohne sie baut der Stick nicht mehr:
#
#   1. `--profile=app`, sonst sagt der Uebersetzer
#      "the module 'std.rt' belongs to the standard library and is not
#       available in profile 'kernel'"  (vendor/firn/lib/fui/render.fi)
#   2. KEIN crt.o. Unter `app` legt firnc dieselben vier Befehle selbst
#      hinein, die in crt.s stehen; crt.o dazuzubinden waere
#      "multiple definition of `_start`".
#
# Genau diese Unterscheidung trifft `tools/look/shot.sh` seit Runde 31,
# und sie wird auch hier GELESEN und nicht getippt -- sonst stimmt sie
# nach der naechsten Umstellung nicht mehr.
for p in $PROGS; do
    [ -f "kernel/user/$p.fi" ] || continue
    PROF=""
    CRT="$OUT/crt.o"
    if grep -qa '^profile app' "kernel/user/$p.fi"; then
        PROF="--profile=app"
        CRT=""
    fi
    # `-c` NUR UEBERSETZEN, NICHT BINDEN. Ohne das versucht firnc im
    # Profil `app` gleich zu binden und sagt dann "input file is the
    # same as output file" -- im Profil `kernel` faellt das nicht auf,
    # weil dort ohnehin nur ein Objekt entsteht.
    if ! "$CC" $PROF -c "kernel/user/$p.fi" -o "$OUT/$p.o" > "$OUT/$p.err" 2>&1; then
        echo "== $p: der Uebersetzer sagt nein" >&2; head -20 "$OUT/$p.err" >&2
        rc=1; continue
    fi
    if ! ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F$STUFE.u_start" \
            -o "$OUT/$p.elf" $CRT "$OUT/$p.o" 2> "$OUT/$p.lderr"; then
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
mark-filtered mark-faked mark-none sys-faking tile-fake tile-net tile-hide tile-dark tile-power tile-tile"
sagen "symbole     $(echo $SYMBOLE | wc -w) Stueck nach /etc/netview/"

python3 tools/k15/tree.py "$OUT/baum" > "$OUT/baum.log" 2>&1 \
    || fehler "tools/k15/tree.py fehlgeschlagen"

printf 'root:x:0:0:root:/:/bin/sh\n%s:x:1000:1000:%s:/users/%s:/bin/sh\n' \
    "$KONTO" "$KONTO_NAME" "$KONTO" > "$OUT/passwd"

# ============================================== RUNDE ANMELDUNG
# /etc/shadow, /etc/group, /etc/login.conf, /etc/sperre.conf
#
# BIS HIERHER GAB ES KEIN /etc/shadow IM ABBILD. `/etc/passwd` lag
# darin (zwei Konten, `root` und `justin`), aber kein einziger
# Kennworteintrag -- gemessen am Abbild vom 13.09.:
#
#     python3 tools/osum/mkfs.py list root.img | grep shadow   ->  nichts
#
# Damit konnte sich niemand anmelden, auch wenn `login` im Abbild
# gelegen haette (tat es auch nicht). Der Schreibtisch startete direkt
# aus dem Kern als root, und das ist der Befund P-002.
#
# DAS KENNWORT STEHT NICHT IM KLARTEXT AUF DER PLATTE, und das ist
# keine Behauptung, sondern das Format: `$osum1$<runden>$<salz>$<dk>`
# mit PBKDF2-HMAC-SHA256, genau das, was `kernel/user/pw.fi`
# (`make_hash`, `check_hash`) liest und schreibt. Die Rundenzahl ist
# `pw.KOSTEN` = 8192; sie wird HIER AUS DER QUELLE GELESEN und nicht
# getippt, sonst laufen die beiden Zahlen nach der naechsten Aenderung
# auseinander.
#
# DAS SALZ IST ZUFAELLIG, je Konto ein eigenes, aus os.urandom. Ein
# festes Salz waere in jedem Abbild dasselbe -- dann hilft eine
# Regenbogentabelle wieder, und genau dagegen ist ein Salz da.
#
# DAS ANFANGSKENNWORT steht in der Datei FASSUNG des Bauverzeichnisses
# und wird auf der Bauausgabe GENANNT. Es ist kein Geheimnis dieses
# Systems, sondern eines, das der Mensch beim ersten Anmelden aendert
# (`passwd`); ein Abbild ohne bekanntes Anfangskennwort waere eines,
# an dem sich niemand anmelden kann.
PW_RUNDEN=$(sed -n 's/^const KOSTEN: u64 = \([0-9]*\).*/\1/p' kernel/user/pw.fi | head -1)
[ -n "$PW_RUNDEN" ] || fehler "die Rundenzahl steht nicht in kernel/user/pw.fi"
# ROUND LIVE: on the public image root is LOCKED (`!` is no hash, so
# check_hash says no to every password) and the one account is `live` /
# `live` -- the password is printed on the download page and is no secret;
# it only exists so the lock screen and `su` have something to ask for.
if [ "$IMAGE_PROFILE" = public ]; then
    PW_ROOT='!'
    PW_KONTO=${LIVE_PW:-live}
else
    PW_ROOT=${PW_ROOT:-osumroot}
    PW_KONTO=${PW_JUSTIN:-startkennwort}
fi
python3 - "$OUT" "$PW_RUNDEN" "$PW_ROOT" "$PW_KONTO" "$KONTO" <<'PYEOF'
import binascii, hashlib, os, sys
d, it, pr, pj, konto = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5]

def rec(pw):
    if pw == '!':
        return '!'
    # DAS SALZ IST ZUFAELLIG UND ACHT OKTETTE LANG -- so lang, wie
    # pw.fi es schreibt (`make_hash`: acht Oktette aus dem Kern).
    salt = os.urandom(8)
    dk = hashlib.pbkdf2_hmac('sha256', pw.encode(), salt, it, 32)
    return "$osum1$%d$%s$%s" % (it, binascii.hexlify(salt).decode(),
                                binascii.hexlify(dk).decode())

with open(d + "/shadow", "w") as f:
    f.write("root:%s:0:0:99999:7:::\n" % rec(pr))
    f.write("%s:%s:0:0:99999:7:::\n" % (konto, rec(pj)))

with open(d + "/group", "w") as f:
    f.write("root:x:0:\n")
    f.write("%s:x:1000:\n" % konto)
PYEOF
chmod 600 "$OUT/shadow"

# /etc/login.conf -- was die Anmeldung an Verzoegerung nimmt.
# `verzoegerung_ms` ist die ERSTE Wartezeit; sie verdoppelt sich mit
# jedem Fehlversuch (login.fi, glogin.fi).
printf '# /etc/login.conf -- die Anmeldung.\n# verzoegerung_ms: die erste Wartezeit nach einem Fehlversuch.\n#   Sie VERDOPPELT sich mit jedem weiteren und ist bei einer Minute\n#   gedeckelt. max_versuche gilt nur fuer die Anmeldung am Terminal.\nverzoegerung_ms=1000\nmax_versuche=3\n# runden: der Kostenfaktor fuer NEUE Kennwoerter (passwd).\nrunden=%s\n' \
    "$PW_RUNDEN" > "$OUT/login.conf"

# /etc/sperre.conf -- der Leerlauf, nach dem von selbst gesperrt wird.
# 300 Sekunden sind fuenf Minuten; 0 hiesse "nie von selbst".
printf '# /etc/sperre.conf -- der Sperrbildschirm.\n# leerlauf: Sekunden ohne Eingabe, nach denen von selbst gesperrt\n#   wird. 0 schaltet den Waechter ab.\nleerlauf=%s\n' \
    "${SPERRE_LEERLAUF:-$([ "$IMAGE_PROFILE" = public ] && echo 0 || echo 300)}" > "$OUT/sperre.conf"
# ROUND LIVE: /etc/autologin -- ONLY on the public image. glogin signs
# the user named there in once per boot (kernel/user/glogin.fi,
# auto_anmelden).
if [ "$IMAGE_PROFILE" = public ]; then
    printf '%s\n' "$KONTO" > "$OUT/autologin"
fi

sagen "profil      $IMAGE_PROFILE"
if [ "$IMAGE_PROFILE" = public ]; then
    sagen "konten      2 (root gesperrt, $KONTO), PBKDF2 $PW_RUNDEN Runden, automatisch angemeldet: $KONTO"
    sagen "            Kennwort $KONTO='$PW_KONTO' (Live-System, steht auf der Downloadseite)"
else
    sagen "konten      2 (root, $KONTO), PBKDF2 $PW_RUNDEN Runden, Salz je Konto zufaellig"
    sagen "            Anfangskennwort $KONTO='$PW_KONTO' root='$PW_ROOT' -- mit passwd aendern"
fi
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
# ROUND LIVE: on the public stick "Install OrientOS" is pinned first --
# the one thing a live stick is for, visible without opening a menu.
if [ "$IMAGE_PROFILE" = public ]; then
    printf 'pins=installer,explorer,terminal,settings\n' >> "$OUT/taskbar.conf"
fi
# ====================================================== RUNDE MODULE
# /etc/module.conf -- DIE LAGE DER SCHREIBTISCHMODULE, AUSGELIEFERT.
#
# Eine Zeile je Modul: name=an,anker,dx,dy. Der Anker ist die ECKE
# (0 links oben, 1 rechts oben, 2 links unten, 3 rechts unten), dx/dy
# zaehlen von ihr aus nach innen -- deshalb liegt ein Modul auf jedem
# Schirm an derselben Ecke und nicht bei 1700 Bildpunkten, die es auf
# einem 1280er nicht gibt.
#
# `taste=280` ist F9 (0x118): das Kuerzel, das den Bearbeitungsmodus
# aufmacht. Es steht in der Datei und nicht im Quelltext, damit die
# Seite "Darstellung" es aendern kann.
printf '# /etc/module.conf -- name=an,anker,dx,dy\nuhr=1,1,16,16\nspeicher=1,1,16,56\ncpu=1,1,16,96\ntaste=280\n' \
    > "$OUT/module.conf"

# ================================================= RUNDE DREI (D-016)
# /etc/papierkorb.conf -- DIE GRENZE DES PAPIERKORBS.
#
# `kernel/user/trash.fi::grenze()` liest hier `grenze=<MiB>` und faellt
# ohne die Datei auf 64 MiB zurueck. Die Vorgabe ist also nicht neu --
# neu ist, dass sie im Abbild STEHT und damit aenderbar ist, ohne den
# Quelltext anzufassen. Vorher gab es keinen Weg, sie zu verstellen:
# die Datei wurde nie ausgeliefert.
#
# WARUM 512 UND NICHT 64. Ein Korb, der bei 64 MiB das Aelteste
# endgueltig wegwirft, verliert bei einem einzigen geloeschten Video
# alles, was vorher darin lag -- und das ist genau der Fall, in dem man
# den Korb braucht. 512 MiB sind auf jedem Traeger, auf den dieses
# System passt, verschmerzbar.
printf '# /etc/papierkorb.conf -- die Grenze des Papierkorbs.\n# grenze=<MiB>: wird sie ueberschritten, fliegt das AELTESTE heraus,\n# bis es wieder passt. trash.fi sagt jedes endgueltige Loeschen auf\n# der seriellen Leitung an.\ngrenze=512\n' \
    > "$OUT/papierkorb.conf"

# ============================================ RUNDE ECHTHARDWARE-1
# DAS ABBILD BEKOMMT DAS AUSSEHEN, DAS DIE DEMO HATTE.
#
# Justin, vor den Fotos vom 09.09.: "alles komplett eckig -- nicht die
# Demo, die du mir damals gezeigt hast". Er hat recht, und der Grund
# stand nicht im Kernel, sondern in DIESER Datei.
#
# Die Demo (.design-shots/nachher/*.png) entstand mit
# tools/design/capture.sh, und dieses Skript legt VIER Dinge ins
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
T_ACCENT=$(lies_preset accent)
# ==================================================== RUNDE FARBE
# `dark_scheme=` UND `accent=` GEHOEREN MIT INS ABBILD.
#
# Ohne die erste Zeile schaltet der Dunkelmodus nur das ANDERE ENDE
# DERSELBEN RAMPE ein -- und die Rampe von `tageslicht` ist Slate,
# also blau (#0f172a hat B-R = +27). Die Vorlage sagt seit dieser
# Runde `dark_scheme=midnight` (Zinc, B-R = +3); wer sie hier nicht
# ausliest, baut ein Abbild, dessen Dunkelmodus wieder blau ist,
# obwohl die Vorlage daneben es besser weiss.
#
# Beide Zeilen werden NUR geschrieben, wenn die Vorlage sie hat: ein
# leeres `dark_scheme=` waere kein leerer Wert, sondern ein leerer
# DATEINAME, und `wlibc` faende im Dunkelmodus gar kein Schema mehr.
T_DSCHEME=$(lies_preset dark_scheme)
{
  printf '# /etc/theme.conf -- Runde FARBE (MERGE-10)\nscheme=%s\n' "$T_SCHEME"
  [ -n "$T_DSCHEME" ] && printf 'dark_scheme=%s\n' "$T_DSCHEME"
  printf 'mode=%s\naccent=%s\nshape=%s\nlight_start=07:00\ndark_start=19:00\n' \
    "$T_MODE" "$T_ACCENT" "$T_SHAPE"
} > "$OUT/theme.conf"
# ================================================ RUNDE FUI-WIN11
# DIE AKZENTFARBE WIRD AUFGELOEST GEMELDET UND NICHT ALS STRICH.
#
# Justins Befund am 13.09.: der Bau meldete `accent=-`, und daraus las
# sich "es gibt keine Akzentfarbe, also ist alles fest blau". Das
# stimmt NICHT, und die Meldung war schuld.
#
# `accent=` LEER ist ein gueltiger Wert mit einer Bedeutung: "diese
# Vorlage schreibt keine eigene Akzentfarbe vor, es gilt die des
# SCHEMAS" (assets/themes/*.preset, Kopfzeile: "accent the accent, or
# empty for the scheme's own"). `vorlage.fi` traegt dafuer ACC_NONE und
# NICHT 0 -- 0 waere Schwarz und damit eine echte Farbe.
#
# Die Farbe, die dann wirklich gilt, steht im Schema
# (assets/schemes/<scheme>.scheme, Zeile `accent=`) und wird von
# `wlibc.bind_accent` auf die Rampe gelegt, samt Kontrollrechnung gegen
# WCAG. Also wird sie hier NACHGESCHLAGEN und mitgemeldet -- wer den
# Bericht liest, sieht die Farbe, die auf dem Schirm landet, und nicht
# einen Strich.
T_ACC_EFF="$T_ACCENT"
T_ACC_HER="vorlage"
if [ -z "$T_ACC_EFF" ]; then
    T_ACC_HER="schema $T_SCHEME"
    T_ACC_EFF=$(grep -a "^accent=" "assets/schemes/$T_SCHEME.scheme" 2>/dev/null \
        | head -1 | cut -d= -f2-)
fi
sagen "thema       $THEMA (scheme=$T_SCHEME dark_scheme=${T_DSCHEME:--} mode=$T_MODE shape=$T_SHAPE accent=${T_ACCENT:--})"
sagen "akzent      #${T_ACC_EFF:-??} (aus ${T_ACC_HER}) -- das ist die Farbe, die aktive Kacheln, Auswahl und Fokusring tragen"

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
# ===================================================== RUNDE ECHTHARDWARE-2
#
# DIE SPRACHE DES STICKS IST ENGLISCH. Dauerregel von Justin vom
# 09.09.2026: Englisch ist die Hauptsprache der Oberflaeche, Deutsch
# bleibt als waehlbare Uebersetzung.
#
# HIER UND NUR HIER. Der Katalog (kernel/user/msg.fi, Runde I18N) hat
# das immer schon gekonnt: `init` liest ZUERST locale/en/messages, und
# Englisch ist die Rueckfallsprache fuer jeden Schluessel, den eine
# Uebersetzung nicht hat. Was den Stick trotzdem deutsch machte, war
# diese eine Zeile -- sie schrieb `de` in /users/root/config/locale,
# und der Katalog legte die Uebersetzung folgsam ueber das Englische.
# GEMESSEN auf Justins Abbild: `taskbar: lang=de src=1 keys=288`
# (src=1 = die Wahl des Benutzers, genau diese Datei).
#
# Es waren also NICHT 71 Stellen im Quelltext zu aendern, sondern ein
# Wort in einer Datei. Beide Kataloge bleiben im Abbild, und wer
# Deutsch will, waehlt es in den Einstellungen -- die Datei wird dann
# mit `de` ueberschrieben.
#
# Die Datei heisst weiterhin `locale-de` im Baubaum; sie ist nur der
# Zwischenspeicher fuer den Inhalt und wird nach
# /users/root/config/locale kopiert.
# ---------------------------------------------------------------------
# INTEGRATIONSRUNDE 19.09.2026: ZURUECK AUF DEUTSCH -- UND ZWAR HIER.
#
# Der Absatz darueber beschreibt den Stand vom 09.09., als Englisch zur
# Hauptsprache gemacht wurde. Die Begruendung von damals stimmt
# technisch immer noch (eine Zeile, nicht 71 Stellen im Quelltext) --
# nur zeigt das Abbild damit eine ENGLISCHE Oberflaeche auf einem
# System, dessen Quelltext, Kommentare, Berichte und Katalog
# durchgehend deutsch sind. Der deutsche Katalog liegt vollstaendig im
# Abbild (locale/de/messages, 588 Zeilen) und wurde nie benutzt.
#
# Also `de` -- und zwar an ALLEN DREI Stellen, die die Sprache
# festlegen, weil eine allein nichts bewirkt (Reihenfolge aus
# kernel/user/msg.fi, staerkste zuerst):
#
#   1. /users/root/config/locale   die WAHL DES BENUTZERS  <- diese Zeile
#   2. /etc/locale.conf            die VORGABE DES SYSTEMS
#   3. `lang=` auf der Kommandozeile schreibt (1) VOR dem ersten
#      Ring-3-Programm (kernel/lib/kstate.fi, M_LANGDE)
#
# Haette man nur (2) geaendert, bliebe die Oberflaeche englisch: (1)
# sticht (2). Genau diese Falle hat die Pruefung dieser Runde gekostet.
#
# ENGLISCH BLEIBT WAEHLBAR und geht nicht verloren: der englische
# Katalog bleibt im Abbild, er ist weiterhin die Rueckfallsprache fuer
# jeden Schluessel, den die Uebersetzung nicht hat, das
# Einstellungsprogramm schaltet um, und der Bootmenue-Eintrag mit
# `lang=en` (weiter unten) bleibt Wort fuer Wort stehen.
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
# ============ RUNDE MODERN + INTEGRATION 21.09.2026: `bold.ttf` HAT
# HIER GEFEHLT -- DERSELBE FEHLER WIE BEI `nedit`, NUR EINE SCHRIFT.
#
# RUNDE MODERN hat den echten fetten Schnitt geschnitten
# (assets/osum-sans-bold.ttf, 45012 Oktett, 364 Glyphen, Umrisse
# bitgleich zu DejaVuSans-Bold) und ihn in tools/k15/build.sh und
# tools/design/capture.sh eingetragen -- also in die Abbilder, mit
# denen GEMESSEN wird. In DIESE Zeile, die das AUSGELIEFERTE
# Wurzelabbild baut, kam er nie. Kein Testlauf war rot: kgui.fi laedt
# /lib/bold.ttf ausdruecklich als NICHT PFLICHT (fehlt er, wiegt Fett
# so viel wie Normal). Auf dem Messplatz war der fette Schnitt also
# da, auf dem Stick nicht -- und die Schrifthierarchie, die diese
# Runde gebaut hat, waere bei niemandem angekommen.
#
# Darum steht /lib/bold.ttf ab jetzt AUCH unten in PFLICHT: die
# Schrift darf zur Laufzeit fehlen duerfen, aber sie darf nicht
# STILL aus dem Bauplan fallen.
ARGS+=(/lib/
       "/lib/mono.ttf=assets/osum-mono.ttf"
       "/lib/sans.ttf=assets/osum-sans.ttf"
       "/lib/bold.ttf=assets/osum-sans-bold.ttf"
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
# RUNDE ABBILD: DIE VORGABE DES SYSTEMS STEHT AUCH IM ABBILD.
#
# /users/root/config/locale sagt seit dem 09.09.2026 `en` -- Englisch
# ist die Hauptsprache der Oberflaeche, Deutsch die waehlbare
# Uebersetzung (Begruendung oben bei `locale-de`). Was fehlte, war die
# VORGABE DES SYSTEMS daneben: ohne /etc/locale.conf gibt es nur die
# Benutzerwahl, und wer die Datei loescht, faellt auf die eingebaute
# Vorgabe zurueck, statt auf eine, die im Abbild steht und die man
# lesen kann. Dieselbe Datei, die tools/look/shot.sh seit Runde LOOK
# schreibt -- mit demselben Inhalt wie die Benutzerwahl, damit beide
# dasselbe sagen.
printf '# /etc/locale.conf -- the system default language.\n# A user who has chosen one overrides this in\n# /users/<name>/config/locale; the settings program writes only there.\nlang=de\n' \
    > "$OUT/locale.conf"
ARGS+=(/etc/ "/etc/passwd=$OUT/passwd"
       "/etc/shadow=$OUT/shadow"
       "/etc/group=$OUT/group"
       "/etc/login.conf=$OUT/login.conf"
       "/etc/sperre.conf=$OUT/sperre.conf"
       "/etc/taskbar.conf=$OUT/taskbar.conf"
       "/etc/module.conf=$OUT/module.conf"
       "/etc/papierkorb.conf=$OUT/papierkorb.conf"
       "/etc/theme.conf=$OUT/theme.conf"
       "/etc/locale.conf=$OUT/locale.conf"
       "/etc/netlauf.sh=$OUT/netlauf.sh")
# ===================================================== RUNDE HOVERSTIL
# /etc/uitrace -- DER SCHALTER, OHNE DEN DIE OBERFLAECHE STUMM IST.
#
# `kernel/user/qs.fi::dbg_setup` macht ALLE Meldungen des
# Kontrollzentrums von dieser Datei abhaengig:
#
#     let fdt: u64 = io.open("/etc/uitrace", 0)
#     if !ulib.bad(fdt) { s_dbg = 1 }
#
# und `say`/`sayn`/`nl` kehren ohne sie sofort zurueck. Fehlt sie, dann
# laeuft das Panel VOLLSTAENDIG richtig -- es geht auf, es geht zu, der
# Zeiger wirkt --, aber es steht KEINE EINZIGE `qs:`-Zeile auf der
# Leitung. Genau das hat diese Runde zwei Anlaeufe gekostet: gemessen
# wurden fuenfmal `hk: super+a` und fuenfmal ein Wechsel von `fl=19`
# (versteckt) auf `fl=18` (sichtbar) im Fensterbericht -- das Panel
# gehorchte also --, waehrend `qs: kachel` und selbst eine eigens
# eingebaute Diagnosezeile NULL Treffer hatten. Wer daraus "die Maus
# kommt nicht an" schliesst, misst diesen Schalter und nicht das
# System.
#
# Die Datei ist LEER und kostet einen Verzeichniseintrag. Sie kommt nur
# mit UITRACE=1 ins Abbild, damit ein Auslieferungsstick weiter still
# ist; jeder Messlauf setzt die Umgebungsvariable.
if [ "${UITRACE:-0}" = "1" ]; then
    : > "$OUT/uitrace"
    ARGS+=("/etc/uitrace=$OUT/uitrace")
    echo "   uitrace    AN -- die Oberflaeche meldet (qs:, taskbar:)"
fi
# ROUND LOGIN-2: /etc/uiblink -- the caret blinks even with /etc/uitrace
# (without it a measuring run keeps the caret steady; see wlib.blink_setup).
if [ "${UIBLINK:-0}" = "1" ]; then
    : > "$OUT/uiblink"
    ARGS+=("/etc/uiblink=$OUT/uiblink")
    echo "   uiblink    AN -- die Einfuegemarke blinkt auch im Messlauf"
fi
# RUNDE ECHTHARDWARE-1: die drei Verzeichnisse, ohne die `shape=` und
# `scheme=` ins Leere zeigen. Derselbe Weg wie in
# tools/design/capture.sh -- dieselben Dateien, damit der Stick zeigt,
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
# ============================================== RUNDE LOGIND
# DIE HEIMATVERZEICHNISSE -- /etc/passwd VERSPRACH EINES, DAS ES NICHT
# GAB.
#
# `/etc/passwd` traegt seit der Runde ANMELDUNG zwei Konten, und
# `justin` steht dort mit dem Heimatverzeichnis `/users/justin`. Im
# Abbild gab es aber NUR `/users/root/` -- gemessen am Abbild vom
# 15.09.:
#
#     python3 tools/osum/mkfs.py list root.img | grep /users/
#         /users/ /users/root/ /users/root/config/ ...
#         (kein /users/justin)
#
# docs/RUNDE-ANMELDUNG.md hat das unter 5.4 selbst als offen benannt.
# Es ist kein Schoenheitsfehler: `glogin` legt die Rechte ab und
# startet den Schreibtisch als uid 1000. Jedes Programm, das danach
# etwas Eigenes ablegen will (die Einstellungen schreiben
# `/users/<name>/config/locale`, der Explorer will ein Zuhause zum
# Anzeigen), schreibt in ein Verzeichnis, das nicht existiert -- und
# ein Schreibfehler in einem Pfad, den /etc/passwd verspricht, ist ein
# gebrochenes Versprechen und kein fehlendes Merkmal.
#
# RECHTE UND EIGENTUM SIND DER PUNKT. Ohne `@0700:1000:1000` gehoerte
# das Verzeichnis root mit 0755 (die Vorgabe von mkfs.py) -- dann
# koennte justin in seinem eigenen Zuhause nichts anlegen, und jeder
# andere koennte hineinsehen. 0700 heisst: nur er, und niemand sonst.
ARGS+=(/users/ /users/root/ /users/root/config/
       "/users/root/config/locale=$OUT/locale-de"
       "/users/$KONTO/@0700:1000:1000"
       "/users/$KONTO/config/@0700:1000:1000")
if [ "$IMAGE_PROFILE" = public ]; then
    ARGS+=("/etc/autologin=$OUT/autologin")
fi
ARGS+=(/boot/ "/boot/osum.mb=$OUT/osum.mb"
       "/boot/BOOTX64.EFI=$LIMINE/BOOTX64.EFI")
# ==================================================== RUNDE ENERGIE
# /run, /etc/inittab UND /etc/ziel -- OHNE SIE HAT DER AUSSCHALTKNOPF
# NIEMANDEN, DEM ER ES SAGEN KANN.
#
# GEMESSEN AN DIESEM ABBILD, bevor diese Zeilen dazukamen:
# `mkfs.py list` fand WEDER /bin/init NOCH /etc/inittab NOCH ein
# Verzeichnis /run. Der Weg, den `/bin/shutdown` seit Runde INIT geht
# (eine Zeile nach /run/svc.cmd, Prozess 1 raeumt auf), war auf dem
# Auslieferungsstick also gar nicht vorhanden -- `/bin/shutdown` fiel
# dort IMMER auf seinen Notweg `self()` zurueck: sync und ACPI, ohne
# dass ein einziger Dienst ein Signal bekommt.
#
# Das ist genau der Unterschied, um den es bei einem Ausschaltknopf
# geht. Ein Knopf, der die Platte im Flug abschneidet, ist schlimmer
# als keiner -- deshalb liegt ab dieser Runde das Ziel `grafik` im
# Abbild, dazu eine inittab, die den Schreibtisch als Dienst fuehrt,
# und das leere /run, in das die Oberflaeche ihre Zeile schreibt.
#
# DIE TAFEL IST ABSICHTLICH KURZ. Sie fuehrt genau das, was dieser
# Stick wirklich startet; jeder weitere Dienst waere eine Behauptung
# ueber einen Betrieb, den niemand gemessen hat.
cat > "$OUT/inittab" <<'EOFTAB'
# /etc/inittab -- name:ziele:art:befehl:optionen
#
# DIE OBERFLAECHE STEHT HIER NICHT DRIN, und das ist kein Versaeumnis:
# `kgui.desk_start` startet Schreibtisch, Leiste, Starter und den Rest
# selbst, direkt aus dem Kern. Was init auf einem Abbild mit Bildschirm
# tut, ist deshalb genau zweierlei -- Waisen einsammeln und beim
# Abschalten aufraeumen (SIGTERM, Frist, SIGKILL, sync, umount) --,
# und dafuer braucht es keinen eigenen Dienst.
#
# DIE KONSOLE LAEUFT NUR IM ZIEL `konsole`, und `ctrl` heisst dort
# "wenn diese Shell endet, endet das System" (init.fi: A_CTRL ->
# going = 0). Fuer einen Serverlauf ist das richtig: das Skript von
# `script=` laeuft, die Shell endet, die Maschine faehrt sauber herunter.
#
# WARUM NICHT AUCH IM ZIEL `grafik`, gemessen und wieder verworfen:
#   * mit `ctrl` wuerde ein `exit` im Terminalfenster den ganzen
#     Rechner ausschalten.
#   * mit `respawn` startet sie endlos neu -- gemessen 71 Mal in
#     zwanzig Sekunden ("sh: ready" / "sh: bye" im Wechsel), weil auf
#     einem Schreibtisch niemand an dieser Konsole sitzt und sie sofort
#     wieder auf EOF laeuft.
# Also gar nicht. Ein Dienst, der nichts zu tun hat, gehoert nicht in
# die Tafel.
sh:konsole:ctrl:/bin/sh
EOFTAB
printf 'grafik
' > "$OUT/ziel"
ARGS+=("/etc/inittab=$OUT/inittab" "/etc/ziel=$OUT/ziel")
ARGS+=(/dev/ /proc/ /mnt/ /tmp/ /store/ /apps/ /system/ /run/)
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
# nach tools/foreign/README.md). Wer sie hat, gibt ihren Pfad an; wer
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
/lib/sans.ttf /lib/mono.ttf /lib/icons.ttf /lib/bold.ttf /users/root/config/locale \
/etc/netview/state-online /etc/netview/state-nocarrier \
/etc/netview/state-noip /etc/netview/state-noroute \
/etc/netview/mark-filtered /etc/netview/mark-faked /etc/netview/mark-none \
/etc/netview/sys-faking /etc/netview/tile-fake /etc/netview/tile-net \
/etc/netview/tile-hide /etc/netview/tile-dark \
/etc/netview/tile-power /etc/netview/tile-tile /etc/taskbar.conf /etc/netlauf.sh \
/etc/module.conf \
/etc/theme.conf /etc/shapes/osum /etc/shapes/classic \
/etc/schemas/day /etc/schemas/night /etc/themes/tageslicht \
/bin/desktop /bin/taskbar /bin/netview /bin/explorer /boot/osum.mb \
/bin/ota /bin/fetch /bin/host /bin/dhcp /bin/log /bin/jarvisd /bin/jsig /bin/drucke \
/bin/jarvisctl /bin/pollbr /etc/ota.conf /etc/jarvis/rechte.conf \
/system/FASSUNG /system/SCHLUESSELGEN \
/apps/explorer.osp/start /apps/editor.osp/start /apps/terminal.osp/start \
/bin/nedit /apps/nedit.osp/start /apps/nedit.osp/INFO \
/bin/papierkorb /apps/papierkorb.osp/start /apps/papierkorb.osp/INFO \
/apps/papierkorb.osp/symbol /etc/papierkorb.conf \
/apps/launcher.osp/start /apps/widgets.osp/start /apps/settings.osp/start \
/apps/settings.osp/INFO /apps/settings.osp/symbol \
/bin/taskmgr /apps/taskmgr.osp/start /apps/taskmgr.osp/INFO \
/apps/taskmgr.osp/symbol \
/bin/shutdown /bin/power /bin/firnc /bin/fas /beispiel/hallo.fi \
/bin/installer /apps/installer.osp/start /apps/installer.osp/INFO \
/apps/installer.osp/symbol \
/bin/init /etc/inittab /etc/ziel \
/users/$KONTO/ /users/$KONTO/config/"
[ "$IMAGE_PROFILE" = public ] && PFLICHT="$PFLICHT /etc/autologin"
python3 tools/osum/mkfs.py list "$OUT/root.img" > "$OUT/liste.txt" 2>&1 \
    || fehler "das fertige Dateisystem laesst sich nicht lesen"
fehlt=0
for f in $PFLICHT; do
    grep -qE "(^|[[:space:]])${f}([[:space:]]|\$)" "$OUT/liste.txt" || {
        echo "== FEHLT IM ABBILD: $f" >&2; fehlt=$((fehlt + 1)); }
done
[ "$fehlt" = 0 ] || fehler "$fehlt Pflichtdatei(en) fehlen im Abbild"
sagen "geprueft    $(echo $PFLICHT | wc -w) Pflichtpfade im fertigen Dateisystem"
# ROUND LIVE: THE PUBLIC IMAGE IS CHECKED, NOT TRUSTED. Read back from
# the finished file system: /etc/passwd, /etc/shadow and /etc/group may
# name root and the live user and nobody else, /users/ may hold nothing
# else, and the bridge settings must be the factory ones (no server=).
if [ "$IMAGE_PROFILE" = public ]; then
    python3 tools/usbimg/pubcheck.py "$OUT/root.img" "$KONTO" \
        || fehler "das oeffentliche Abbild enthaelt Persoenliches -- abgebrochen"
    sagen "oeffentlich geprueft: nur root (gesperrt) und $KONTO, Bruecke aus"
fi

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
# THE MENU ON THE STICK CARRIES NO COMMENTS (24.09.2026). Limine shows
# the whole file in its editor (key E), and the development notes that
# stood here appeared under every entry -- in German, with notes about
# single machines. The reasons for every entry are in docs/STICK-MENUE.md
# now; this file only says WHAT is built. The build refuses a limine.conf
# with a comment line in it (see below).
#
# Titles are English and short. The desktop language still follows the
# system setting (/users/root/config/locale); only "(English)" forces it.
#
#   1  OrientOS                   the desktop, network, login
#   2  OrientOS (safe graphics)   no display settings, no audio, cache
#                                 flushed after every frame (fbflush)
#   3  OrientOS (no network)      the fallback: no nic, no dhcp, no jarvis
#   4  Command line               a shell with network, no graphics
#   5  Hardware diagnostics       report and stop, touches nothing
#   Advanced/                     the test and measuring entries; the
#                                 measuring board (tafel, herz) is only here
#
# The quoted heredoc stays quoted and the product name comes in through
# the placeholder, for the reason given in docs/STICK-MENUE.md.
cat > "$OUT/limine.conf" <<'EOF'
timeout: 20
default_entry: 1
verbose: yes

/@MARKE_PRODUKT@
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum gfx disp audio wm wig desk wmshell wmdauer absturzhalt nopuls tz=120 usb hidgen nic nip=169.254.10.1/16 nsvc=0 nwait=0 dhcp jarvis nosched noproc nofs anmeldung

/@MARKE_PRODUKT@ (safe graphics)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum gfx fbflush wm wig desk wmshell wmdauer absturzhalt nopuls tz=120 usb hidgen nic nip=169.254.10.1/16 nsvc=0 nwait=0 dhcp jarvis nosched noproc nofs anmeldung

/@MARKE_PRODUKT@ (no network)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum gfx disp audio wm wig desk wmshell wmdauer absturzhalt nopuls tz=120 usb hidgen nosched noproc nofs anmeldung

/Command line
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum vfs usb hidgen nic nip=169.254.10.1/16 nsvc=0 nwait=0 console=ttyS0 nosched noproc nofs initsh

/Hardware diagnostics
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: hwdiag hwdiagstop gfx nokbd nosched noproc nofs noring3

/Advanced

//@MARKE_PRODUKT@ (English)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum gfx disp audio wm wig desk wmshell wmdauer absturzhalt nopuls tz=120 usb hidgen nic nip=169.254.10.1/16 nsvc=0 nwait=0 dhcp jarvis nosched noproc nofs lang=en anmeldung

//@MARKE_PRODUKT@ (measuring board)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum gfx disp audio wm wig desk wmshell wmdauer absturzhalt nopuls tz=120 usb hidgen tafel herz nic nip=169.254.10.1/16 nsvc=0 nwait=0 dhcp jarvis nosched noproc nofs anmeldung

//@MARKE_PRODUKT@ (network: interrupt pin)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum gfx disp audio wm wig desk wmshell wmdauer absturzhalt nopuls tz=120 usb hidgen tafel herz nic nip=169.254.10.1/16 nsvc=0 nwait=0 nicintx dhcp jarvis nosched noproc nofs anmeldung

//@MARKE_PRODUKT@ (network: polled)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum gfx disp audio wm wig desk wmshell wmdauer absturzhalt nopuls tz=120 usb hidgen tafel herz nic nip=169.254.10.1/16 nsvc=0 nwait=0 nicnoirq dhcp jarvis nosched noproc nofs anmeldung

//@MARKE_PRODUKT@ (framebuffer uncached)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum gfx fbuc wm wig desk wmshell wmdauer tafel herz absturzhalt nopuls tz=120 usb hidgen nic nip=169.254.10.1/16 nsvc=0 nwait=0 nosched noproc nofs

//@MARKE_PRODUKT@ (framebuffer write-back)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum gfx fbwb wm wig desk wmshell wmdauer tafel herz absturzhalt nopuls tz=120 usb hidgen nic nip=169.254.10.1/16 nsvc=0 nwait=0 nosched noproc nofs

//@MARKE_PRODUKT@ (status lamp, blink fields)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum gfx wm wig desk wmshell wmdauer tafel herz pulsled absturzhalt tz=120 usb hidgen nic nip=169.254.10.1/16 nsvc=0 nwait=0 nosched noproc nofs

//@MARKE_PRODUKT@ (apps on core 0 only)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum r3eins gfx wm wig desk wmshell wmdauer tafel herz absturzhalt nopuls tz=120 usb hidgen nic nip=169.254.10.1/16 nsvc=0 nwait=0 dhcp jarvis nosched noproc nofs

//@MARKE_PRODUKT@ (check: wrong GS base)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum r3alle gsluege gfx wm wig desk wmshell wmdauer tafel herz absturzhalt nopuls tz=120 usb hidgen nic nip=169.254.10.1/16 nsvc=0 nwait=0 nosched noproc nofs

//@MARKE_PRODUKT@ (2560x1440)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    resolution: 2560x1440
    cmdline: modfs osum gfx wm wig desk wmshell wmdauer usb hidgen nosched noproc nofs

//@MARKE_PRODUKT@ (3840x2160)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    resolution: 3840x2160
    cmdline: modfs osum gfx wm wig desk wmshell wmdauer usb hidgen nosched noproc nofs

//Diagnostics, then desktop
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: hwdiag modfs osum gfx wm wig desk wmshell wmdauer tafel herz usb hidgen nosched noproc nofs

//USB diagnostics
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: hwdiag usb hidgen usbleg usbstop gfx nokbd nosched noproc nofs noring3

//Network self-test (no keyboard)
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: modfs osum vfs netlauf usb hidgen nic nip=169.254.10.1/16 nsvc=0 nwait=0 console=ttyS0 nosched noproc nofs initsh

//Vector unit check
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: hwdiag hwdiagstop vecproc gfx nokbd nosched noproc nofs noring3

//Graphics survey
    protocol: multiboot1
    path: boot():/osum.mb
    module_path: boot():/root.img
    cmdline: hwdiag hwdiagstop grafik gfx nokbd nosched noproc nofs noring3
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
# ROUND LIVE: THE PUBLIC MENU SAYS WHAT THE STICK IS. Entry 1 is the
# live system ("try without installing" -- nothing is written to a disk),
# entry 2 is the same live system with the installer already open
# (`wigapp=`, kernel/ui/kgui.fi: started after taskbar and launcher). The
# other entries keep their order; entry 2 is new, so "Advanced" moves down
# by one on the public stick only.
if [ "$IMAGE_PROFILE" = public ]; then
    python3 - "$OUT/limine.conf" "$MARKE_PRODUKT" <<'PYLIVE' || fehler "das Live-Menue liess sich nicht schreiben"
import sys
path, prod = sys.argv[1], sys.argv[2]
lines = open(path).read().split('\n')
first = '/' + prod
i = lines.index(first)
j = i + 1
while j < len(lines) and lines[j].startswith(' '):
    j += 1
# `vfs` IN BOTH: without it there is no /dev/, and the installer --
# pinned in the taskbar of entry 1, open in entry 2 -- said "no writable
# disk found" with an empty disk attached (measured, tools/usbimg/live.sh).
# vfs only shows the devices; nothing is written until the installer's
# two questions are answered.
for k in range(i + 1, j):
    if lines[k].strip().startswith('cmdline:') and ' vfs ' not in lines[k] + ' ':
        lines[k] = lines[k].replace('modfs osum ', 'modfs osum vfs ', 1)
body = lines[i + 1:j]
lines[i] = '/%s Live (try without installing)' % prod
inst = ['', '/Install %s' % prod]
for l in body:
    if l.strip().startswith('cmdline:'):
        l = l + ' wigapp=/bin/installer'
    inst.append(l)
lines[j:j] = inst
open(path, 'w').write('\n'.join(lines))
PYLIVE
    grep -q "^/Install $MARKE_PRODUKT\$" "$OUT/limine.conf" \
        || fehler "der Menueeintrag 'Install $MARKE_PRODUKT' fehlt"
fi
# 24.09.2026: no comment lines on the stick (see section 6).
if grep -qE '^[[:space:]]*#' "$OUT/limine.conf"; then
    fehler "limine.conf enthaelt Kommentarzeilen -- die gehoeren nach docs/STICK-MENUE.md"
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
#
# THE PARTITION TABLE: `PARTTAB=gpt|mbr|hybrid` (default gpt).
#
#   gpt     GPT, partition 1 EFI (EF00), partition 2 the root (8300).
#   mbr     a plain MBR: partition 1 FAT32 LBA (0x0C) ACTIVE, 2048 up to
#           the end of the ESP, partition 2 Linux (0x83). No GPT at all.
#   hybrid  the GPT of `gpt`, plus an MBR that carries the same two
#           partitions (0x0C active, 0x83) and a 0xEE entry over the GPT
#           area instead of the protective MBR.
#
# WHY: a Dell OptiPlex 9020 (Haswell, Q87) under UEFI does not find the
# EFI partition of the GPT image ("File System Not Found", empty boot
# list), and boots the MBR variant. The MBR variant starts in QEMU under
# OVMF and SeaBIOS alike.
#
# AND IN EVERY MODE: the FAT boot sector says where it sits. `mkfs.vfat`
# on a separate file writes "hidden sectors = 0" into the BPB; the
# partition starts at 2048, so the field has to say 2048 (`-h`). Firmware
# that trusts the BPB over the partition table found no file system at
# all with the old value.
PARTTAB=${PARTTAB:-gpt}
case "$PARTTAB" in gpt|mbr|hybrid) ;; *) fehler "PARTTAB=$PARTTAB (gpt, mbr oder hybrid)";; esac
FS_MIB=$(( ( $(stat -c%s "$OUT/root.img") + 1048575 ) / 1048576 ))
GES_MIB=$(( ESP_MIB + FS_MIB + 2 ))
rm -f "$IMG"
truncate -s "${GES_MIB}M" "$IMG"

# One MBR partition table, written straight into sector 0 (bytes
# 440..511: disk signature, the four entries, 0x55AA). Entries are
# "boot:type:start:count".
mbr_tafel() { # img entry...
    python3 - "$@" <<'PYMBR'
import struct, sys
img = sys.argv[1]
ents = []
for a in sys.argv[2:]:
    boot, typ, start, count = (int(x, 0) for x in a.split(':'))
    # CHS fields as "beyond 1024 cylinders": every firmware of the last
    # twenty years reads the LBA fields.
    ents.append(struct.pack('<B3sB3sII', boot, b'\xfe\xff\xff', typ,
                            b'\xfe\xff\xff', start, count))
while len(ents) < 4:
    ents.append(b'\0' * 16)
with open(img, 'r+b') as f:
    f.seek(440)
    old = f.read(4)
    sig = old if old != b'\0\0\0\0' else b'OSUM'
    f.seek(440)
    f.write(sig + b'\0\0' + b''.join(ents) + b'\x55\xaa')
PYMBR
}

TOTAL_SEK=$(( GES_MIB * 2048 ))
ESP_SEK=$(( ESP_MIB * 2048 ))
if [ "$PARTTAB" = mbr ]; then
    P1_ANF=2048
    P2_ANF=$(( 2048 + ESP_SEK ))
    mbr_tafel "$IMG" "0x80:0x0C:$P1_ANF:$ESP_SEK" \
        "0x00:0x83:$P2_ANF:$(( TOTAL_SEK - P2_ANF ))" \
        || fehler "MBR-Tafel liess sich nicht schreiben"
else
    sgdisk --clear \
        --new=1:2048:+${ESP_MIB}M --typecode=1:EF00 --change-name=1:"OSUM-EFI" \
        --new=2:0:0              --typecode=2:8300 --change-name=2:"OSUM-ROOT" \
        "$IMG" > "$OUT/sgdisk.log" 2>&1 || {
        cat "$OUT/sgdisk.log" >&2; fehler "sgdisk fehlgeschlagen"; }

    P1_ANF=$(sgdisk --info=1 "$IMG" | grep -oE 'First sector: [0-9]+' | grep -oE '[0-9]+')
    P2_ANF=$(sgdisk --info=2 "$IMG" | grep -oE 'First sector: [0-9]+' | grep -oE '[0-9]+')
    if [ "$PARTTAB" = hybrid ]; then
        P2_END=$(sgdisk --info=2 "$IMG" | grep -oE 'Last sector: [0-9]+' | grep -oE '[0-9]+')
        mbr_tafel "$IMG" "0x00:0xEE:1:$(( P1_ANF - 1 ))" \
            "0x80:0x0C:$P1_ANF:$ESP_SEK" \
            "0x00:0x83:$P2_ANF:$(( P2_END - P2_ANF + 1 ))" \
            || fehler "Hybrid-MBR liess sich nicht schreiben"
    fi
fi

# Die EFI-Partition wird EINZELN gebaut und dann hineingelegt: mkfs.vfat
# und mtools auf einen Bereich MITTEN in einer Datei zu richten geht nur
# ueber Schleifengeraete, und die braucht dieses Skript sonst nirgends.
dd if=/dev/zero of="$OUT/esp.img" bs=1M count="$ESP_MIB" status=none
mkfs.vfat -F 32 -h "$P1_ANF" -n OSUMEFI "$OUT/esp.img" > "$OUT/vfat.log" 2>&1 \
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
sagen "            $(stat -c%s "$IMG") Oktette (${GES_MIB} MiB), $PARTTAB, EFI ${ESP_MIB} MiB + Wurzel ${FS_MIB} MiB"
sagen "            auf den Stick:  sudo dd if=$IMG of=/dev/sdX bs=4M conv=fsync status=progress"
exit 0
# A-002 (24.09.2026): `initsh`. Since RUNDE K13 the kernel starts
# /sbin/init when the image has one, and init reads `/etc/ziel` = grafik
# from this image. Without `gfx` there is no graphics, init finds no
# service, and shuts the machine down -- this entry gave NO command line
# ("init: ziel=grafik", "init: herunterfahren", measured in
# tools/stick/run.sh). `initsh` is the kernel's own word for "the shell is
# the first process"; the same holds for the `netlauf` entry below.
