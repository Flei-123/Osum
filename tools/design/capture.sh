#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/capture.sh -- RUNDE OBERFLAECHE: SIEBEN ANSICHTEN, EIN START.
#
#   bash tools/design/capture.sh <ausgabeverzeichnis> [key=value ...]
#
#     shape=classic|modern|<name>   /etc/theme.conf shape=
#     scheme=day|paper|night|...    /etc/theme.conf scheme=
#     mode=light|dark|auto
#     res=<b>x<h>                   Bildschirmgroesse (Vorgabe 1280x800)
#     accel=kvm|tcg
#     progs="..."                   Programmliste
#     drehbuch=<pfad>               eigenes Drehbuch statt des eingebauten
#
# WARUM EIN START UND NICHT SIEBEN.  Jede Runde davor hat je Bild eine
# eigene Maschine gebootet.  Sieben Maschinen sind sieben Uhrzeiten in
# der Leiste und sieben verschiedene Zufaelle beim Start; ein
# Vorher/Nachher-Vergleich, in dem sich nebenbei die Uhr bewegt, misst
# Rauschen mit.  Hier laeuft EINE Maschine, und `tools/design/drive.py`
# klickt sich durch die Ansichten.
#
# DIE SIEBEN ANSICHTEN, und warum genau diese: es sind die Flaechen, die
# ein Mensch in der ersten Minute sieht.  Schreibtisch, Taskleiste (als
# Ausschnitt desselben Bildes), Startmenue, Dateimanager, Einstellungen,
# Kontrollzentrum, ein Dialog.
#
# Es druckt die Zahlen, auf die ein Aufrufer sich stuetzen darf: die
# Groesse des Kerns, die der Platte, den QEMU-Beendigungscode und je
# Ansicht die Groesse der Aufnahme.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
export FIRN_REPO=${FIRN_REPO:-/root/jarvis/projects/u_DiS4in7esMF1/firn}

OUT=${1:?usage: capture.sh <outdir> [key=value ...]}
shift || true

shape=osum
# RUNDE 32: die Spur ist AUS, solange niemand sie verlangt -- siehe die
# Begruendung bei `$OUT/uitrace` weiter unten.
uitrace=no
scheme=day
mode=light
res=1280x800
zweite=""
fs=aus
# RUNDE OBERFLAECHE, GEMESSEN AM 05.09.2026: AUF DIESEM ZWEIG IST TCG
# DIE VORGABE, UND DAS IST KEIN GESCHMACK.
#
# Der Kern des Zweiges `hidweg` (1493451, Runde VIELKERN 2/n) kommt
# UNTER KVM nicht bis `wm: hold`.  Gemessen, mit demselben Plattenabbild
# und demselben Kern, nur der Beschleuniger getauscht:
#
#     -accel kvm -cpu host        keine Zeile `wm: hold` in 130 s, die
#                                 Stufentafel bleibt bei ST 22 stehen
#                                 (also mitten in `kgui.desk_start`)
#     -accel kvm -cpu host -smp 1 dasselbe
#     -accel tcg                  `wm: hold`, QEMU-Beendigungscode 21
#
# Gegenprobe, dass es nicht an dieser Runde liegt: derselbe Versuch mit
# einem Kern aus `main` laeuft unter KVM durch, und ein Kern aus
# `hidweg` OHNE die zwei Zeilen dieser Runde haengt genauso.  Das ist
# also eine Regression des Zweiges und keine dieses Werkzeugs -- sie
# steht in docs/RUNDE-OBERFLAECHE.md, damit sie nicht verlorengeht.
accel=tcg
halt=300
extra=""
nurbau=nein
# RUNDE CLIP-2: eine Kopie des Abbilds vor dem Start (siehe unten).
vorherbild=nein
# RUNDE TON-2: eine Tonkarte an die Maschine, `ton=ja`.
#
# WARUM ES DEN SCHALTER BRAUCHT: der Lautstaerkeregler im
# Kontrollzentrum und das Lautsprechersymbol in der Leiste folgen der
# Regel "keine Karte, kein Feld" -- auf einer Maschine ohne Tonkarte
# sind sie ABSICHTLICH nicht da. Ein Bildschirmfoto ohne `-device
# intel-hda` kann sie deshalb gar nicht zeigen, und das sah beim
# ersten Anlauf aus wie ein Fehler (`aud: aus (kein Wort)` in der
# seriellen Ausgabe, Regler auf 0 und gedaempft). Die Vorgabe bleibt
# AUS, damit die Bilder der anderen Runden sich nicht aendern.
ton=nein
drehbuch=""
# RUNDE MERGE-10: die Sprache der Bilder, Vorgabe Englisch wie im Abbild.
lang=en
# RUNDE FARBE: das Schema des Dunkelmodus und ein Akzent, beide leer =
# "wie das Schema es selbst sagt".
dark_scheme=""
accent=""
# ============================================ RUNDE ECHTHARDWARE-4
# `uiscale=<n>` -- DIE VERVIELFACHUNG DER OBERFLAECHE.
#
# GEMESSEN AN DEN BELEGEN AUS ECHTHARDWARE-3 (Justin, 09.09.2026):
# in hell-2560/01-schreibtisch.png ist die Leiste 39 Bildpunkte
# hoch. Bei uiscale 2 muesste sie rund 80 sein. Der Ordner hiess
# "2560", der Lauf war aber Vervielfachung 1 -- weil dieses Skript
# `uiscale=` NIE auf die Kommandozeile geschrieben hat und der Kern
# ohne EDID-Groesse bei 1 bleibt (fb.uiscale: v == 0 -> 1).
# Ein Ordnername ist keine Messung. Ab hier steht das Wort auf der
# Kommandozeile, und die Leistenhoehe im Bild belegt es.
uiscale=""
progs="desktop taskbar settings launcher explorer edit sh echo ls cat theme"
for a in "$@"; do
    case "$a" in
        shape=*) shape=${a#*=} ;;
        uitrace=*) uitrace=${a#*=} ;;
        lang=*) lang=${a#*=} ;;
        dark_scheme=*) dark_scheme=${a#*=} ;;
        uiscale=*) uiscale=${a#*=} ;;
        accent=*) accent=${a#*=} ;;
        clock_lines=*) clock_lines=${a#*=} ;;
        hide_missing=*) hide_missing=${a#*=} ;;
        pins=*) pins=${a#*=} ;;
        battfake=*) battfake=${a#*=} ;;
        clock_seconds=*) clock_seconds=${a#*=} ;;
        scheme=*) scheme=${a#*=} ;;
        mode=*) mode=${a#*=} ;;
        res=*) res=${a#*=} ;;
        accel=*) accel=${a#*=} ;;
        progs=*) progs=${a#*=} ;;
        drehbuch=*) drehbuch=${a#*=} ;;
        halt=*) halt=${a#*=} ;;
        extra=*) extra=${a#*=} ;;
        # RUNDE FREMDFS: eine ZWEITE Platte anhaengen, damit sich
        # ein fremdes Dateisystem im Explorer zeigen laesst.
        zweite=*) zweite=${a#*=} ;;
        fs=*) fs=${a#*=} ;;
        nurbau=*) nurbau=${a#*=} ;;
        vorherbild=*) vorherbild=${a#*=} ;;
        ton=*) ton=${a#*=} ;;
        *) echo "unbekannt: $a" >&2; exit 2 ;;
    esac
done
# RUNDE LEISTE-RECHTS: `battfake=ja` taeuscht dem Kern einen Akku vor,
# damit sich Symbol und Prozentzahl UEBERHAUPT fotografieren lassen --
# dieses QEMU kann keinen Akku nachbilden.
[ "${battfake:-}" = ja ] && extra="$extra battfake"
XRES=${res%x*}
YRES=${res#*x}
SKAL=""
if [ -n "$uiscale" ]; then SKAL="uiscale=$uiscale"; fi
echo "uiscale ${uiscale:-1 (Vorgabe)}"

mkdir -p "$OUT"
BUILDD=${DESIGNBUILD:-/tmp/osum-designbuild-$(pwd | md5sum | cut -c1-12)}
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
# Ein Programm ist nicht nur seine eigene Datei: jedes hier importiert
# wlib und wlibc.  Die neueste Datei in kernel/user entscheidet fuer
# alle -- die Runde LOOK hat das auf die langsame Art gelernt.
USERNEW=$(ls -t kernel/user/*.fi 2>/dev/null | head -1)
for p in $progs; do
    if [ -s "$BUILDD/$p.elf" ] && [ -z "${DESIGNREBUILD:-}" ] \
       && [ "$BUILDD/$p.elf" -nt "kernel/user/$p.fi" ] \
       && [ -n "$USERNEW" ] && [ "$BUILDD/$p.elf" -nt "$USERNEW" ]; then
        continue
    fi
    vendor/firn/bin/firnc -c "kernel/user/$p.fi" -o "$BUILDD/$p.o" \
        > "$BUILDD/e-$p" 2>&1 \
        || { echo "FEHLGESCHLAGEN beim Uebersetzen von $p"; head -30 "$BUILDD/e-$p"; exit 1; }
    # RUNDE 31: ein Programm im Profil `app` bringt seinen `_start` mit
    # (fUis f64/std.rt gehen nur dort). crt.o dazuzubinden waere
    # "multiple definition of `_start`" -- also nur fuer die anderen.
    # Gelesen und nicht getippt, damit es nach der naechsten Umstellung
    # noch stimmt. Dieselbe Regel wie in tools/look/shot.sh.
    CRT="$BUILDD/crt.o"
    if grep -qa '^profile app' "kernel/user/$p.fi"; then
        CRT=""
    fi
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
        -o "$BUILDD/$p.elf" $CRT "$BUILDD/$p.o" 2>"$BUILDD/ld.err" \
        || { echo "FEHLGESCHLAGEN beim Binden von $p"; cat "$BUILDD/ld.err"; exit 1; }
    strip --strip-all "$BUILDD/$p.elf"
done
echo "programme $(echo $progs | wc -w)"

# ------------------------------------------------------------ 2. Platte
python3 tools/k15/tree.py "$OUT/baum" > "$OUT/baum.log" 2>&1 || exit 1
# KEIN `height=`.  Die Dicke der Leiste ist seit dieser Runde eine
# MARKE (`ctrl_h` + zweimal `spacing_xs`, kernel/user/taskbar.fi
# `def_h`); wer sie hier hineinschreibt, misst seine eigene Zahl und
# nicht die des Formsatzes.  `width=` bleibt: das ist die Dicke einer
# SENKRECHTEN Leiste und die haengt an der Breite der Beschriftungen.
printf '# taskbar.conf\nedge=bottom\nwidth=104\nautohide=0\nontop=1\nalign=left\n' \
    > "$OUT/taskbar.conf"
# RUNDE MERGE-11: die Uhr wie in Justins Windows-Vorlage -- Uhrzeit
# oben, Datum darunter. `clock_lines` KANN das seit Runde STARTKNOPF
# (taskbar.fi, `clock_build`); es stand nur auf 1. Ohne Sekunden, weil
# eine Leiste, die jede Sekunde neu malt, jede Sekunde Arbeit macht.
printf 'clock_seconds=%s\nclock_date=1\nclock_weekday=0\nclock_lines=%s\n' \
    "${clock_seconds:-0}" "${clock_lines:-2}" >> "$OUT/taskbar.conf"
# GEGENPROBE-SCHALTER: `hide_missing=0` bringt Akku-/Tonfeld auch dann
# zurueck, wenn die Maschine das Geraet nicht hat -- so laesst sich der
# Zeichenpfad belegen, ohne dass QEMU einen Akku emulieren kann.
[ -n "${hide_missing:-}" ] && \
    printf 'hide_missing=%s\n' "$hide_missing" >> "$OUT/taskbar.conf"
# RUNDE ANHEFTEN: die Werksbelegung der Leiste. Certus steht darin,
# weil Justin es so will; die uebrigen sind die drei, die jedes System
# hat (Dateien, Terminal, Einstellungen). Die Zeile ist eine LISTE und
# keine feste Zahl -- damit "anheften/loesen" spaeter nur diese Zeile
# umschreiben muss und keinen Quelltext.
printf 'pins=%s\n' "${pins:-certus,explorer,terminal,settings}" \
    >> "$OUT/taskbar.conf"
# RUNDE FARBE: `dark_scheme=` nur schreiben, wenn er gesetzt ist -- eine
# leere Zeile waere ein leerer DATEINAME und der Dunkelmodus faende gar
# kein Schema mehr.
{
  printf '# /etc/theme.conf\nscheme=%s\n' "$scheme"
  [ -n "$dark_scheme" ] && printf 'dark_scheme=%s\n' "$dark_scheme"
  printf 'mode=%s\naccent=%s\nshape=%s\nlight_start=07:00\ndark_start=19:00\n' \
    "$mode" "$accent" "$shape"
} > "$OUT/theme.conf"
printf '# /etc/time.conf\noffset=120\n' > "$OUT/time.conf"
# ================================================== RUNDE MERGE-10
# DIE ABNAHMEBILDER SPRECHEN DIESELBE SPRACHE WIE DAS ABBILD: ENGLISCH.
#
# Hier stand `lang=de` (und unten `de` in /etc/userlocale), waehrend
# tools/usbimg/build.sh dem Stick seit Runde ECHTHARDWARE-1
# ausdruecklich `lang=en` mitgibt. Die Bilder, an denen die Oberflaeche
# beurteilt wurde, zeigten also eine Sprache, die auf Justins Blech
# gar nicht laeuft -- und ein deutsches Wort ist im Schnitt laenger als
# das englische, so dass gerade die Fehler, um die es hier geht
# (abgeschnittene Beschriftungen, ueberlappende Spaltenkoepfe), im Bild
# ANDERS aussehen als in Wirklichkeit.
#
# Englisch ist die Hauptsprache der Oberflaeche (Dauerregel). Wer ein
# deutsches Bild braucht, setzt `lang=de` beim Aufruf.
#
# UND DIE SPRACHE MUSS AUCH AUF DIE KOMMANDOZEILE (siehe `-append`
# weiter unten), nicht nur in diese Datei. Der Kern leitet aus
# `lang=` die TASTATURBELEGUNG ab (kgui.fi, `tastatur_zur_sprache`),
# und ohne das Wort blieb sie deutsch, waehrend die Oberflaeche
# englisch war. Gemessen: `sendkey ctrl-n` kam als `key: [` an -- auf
# einer deutschen Belegung liegt dort die eckige Klammer. Deshalb ging
# in JEDEM Abnahmelauf der Strg+N-Dialog nicht auf, und das sah aus
# wie ein Fehler des Dateimanagers (OFFEN.md G-003). Das Abbild selbst
# faehrt `lang=en` auf der Kommandozeile (tools/usbimg/build.sh).
printf 'lang=%s\n' "$lang" > "$OUT/locale.conf"
# ====================================================== RUNDE 32
# DIE SPUR IST AB JETZT ABSCHALTBAR, UND SIE IST STANDARDMAESSIG AUS.
#
# Justin an den Bildern: "im Terminal stehen sichtbar Debugzeilen
# (`wlib ...`, `fg=...`) -- die gehoeren im Normalbetrieb nicht auf den
# Schirm."
#
# Er hat recht, und es ist ein Fehler DIESES SKRIPTS und nicht des
# Systems. `/etc/uitrace` schaltet in wlib `s_trace` ein; die Meldungen
# gehen dann mit `ulib.put` auf die STANDARDAUSGABE, und die Ausgabe
# der Shell IST im Pruefstand das Terminalfenster. Also standen sie im
# Bild. tools/look/shot.sh hat dafuer seit immer einen Schalter
# (`uitrace=no` als Vorgabe) -- hier stand die Datei bedingungslos,
# also war die Spur in JEDER Aufnahme an.
#
# Die Spur ist nicht unnuetz: acht Pruefstaende lesen die `wlib:`-Zeilen
# (tools/design/messen.py, tools/alltag/shotcheck.py und weitere), und
# `drive.py` findet seine Rechtecke darin. Wer sie braucht, schaltet
# sie ein:
#
#     bash tools/design/capture.sh /tmp/x uitrace=yes
#
# Fuer ein Bild, das zeigen soll, was der Nutzer sieht, ist sie aus.
# WICHTIG: bei "aus" wird die Datei NICHT angelegt, nicht nur geleert.
# wlib prueft, OB /etc/uitrace sich oeffnen laesst (wlib.fi ~Z.845), und
# nicht, was darin steht -- eine leere Datei schaltet die Spur genauso
# ein. Das ist mir beim Schreiben dieser Zeilen selbst passiert.
if [ "${uitrace:-no}" = yes ]; then
    printf 'on\n' > "$OUT/uitrace"
else
    rm -f "$OUT/uitrace"
fi
cat > "$OUT/passwd" <<'EOF'
root:x:0:0:root:/users/justin:/bin/sh
justin:x:1000:1000:Justin:/users/justin:/bin/sh
EOF
printf '%s\n' "$lang" > "$OUT/userlocale"

# RUNDE EXPLORER-2, Pflichtpunkt 5: DIE PLATTE TRAEGT ZEITEN.
#
# Ohne `--v3` legt mkfs.py ein Abbild der Fassung 2 an, und dort gibt
# `fs.inode_mtime` (kernel/fs.fi:707) fuer JEDE Datei ausdruecklich 0
# zurueck. Der Dateimanager hat deshalb in der Zeit-Spalte "--" gezeigt
# -- nicht, weil er die Zeit nicht liest, sondern weil keine da war.
# `--time=` setzt dazu die Zeit, mit der die Dateien entstehen (die des
# Wirtes beim Bauen des Abbildes), sonst waeren alle drei Zeiten null
# und die Spalte bliebe leer wie zuvor.
ARGS=(build "$OUT/disk.img" 20480 --v3 "--time=$(date +%s)" /lib/
      "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
      "/lib/icons.ttf=assets/osum-icons.ttf" /bin/)
for p in $progs; do ARGS+=("/bin/$p=$BUILDD/$p.elf"); done
ARGS+=("/bin/files@/bin/explorer")
# RUNDE FREMDFS: ein leeres /mnt. Ein Einhaengepunkt muss ein
# Verzeichnis sein, DAS ES GIBT (vfs.mount_at) -- ohne diese Zeile
# laesst sich auf dieser Platte nichts einhaengen, und der
# Dateimanager koennte ein fremdes Dateisystem nie zeigen.
ARGS+=(/mnt/)
ARGS+=(/etc/
       "/etc/theme.conf=$OUT/theme.conf@0644"
       "/etc/time.conf=$OUT/time.conf@0644"
       "/etc/locale.conf=$OUT/locale.conf@0644"
       "/etc/passwd=$OUT/passwd@0644"
       "/etc/taskbar.conf=$OUT/taskbar.conf@0644")
# /etc/uitrace nur, wenn die Spur an ist -- siehe oben: wlib sieht nur,
# ob die Datei da ist.
if [ -f "$OUT/uitrace" ]; then
    ARGS+=("/etc/uitrace=$OUT/uitrace@0644")
fi
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
             tile-fake tile-net tile-hide tile-dark tile-power tile-tile; do
        [ -e "$OUT/nvicons/$q" ] && ARGS+=("/etc/netview/$q=$OUT/nvicons/$q")
    done
fi
ARGS+=(/usr/ /usr/share/ /usr/share/locale/
       /usr/share/locale/en/ "/usr/share/locale/en/messages=locale/en/messages"
       /usr/share/locale/de/ "/usr/share/locale/de/messages=locale/de/messages")
[ -e locale/en/icons ] && ARGS+=("/usr/share/locale/en/icons=locale/en/icons")
[ -e locale/de/icons ] && ARGS+=("/usr/share/locale/de/icons=locale/de/icons")
ARGS+=(/users/ /users/justin/ /users/justin/config/
       "/users/justin/config/locale=$OUT/userlocale@0644")
# Ein paar Dateien, damit der Dateimanager etwas zu zeigen hat.
mkdir -p "$OUT/heim"
printf 'Notizen zur Runde OBERFLAECHE.\n' > "$OUT/heim/notizen.txt"
printf 'a,b,c\n1,2,3\n' > "$OUT/heim/tabelle.csv"
printf 'Ein Brief an Justin.\n' > "$OUT/heim/brief.txt"
ARGS+=("/users/justin/notizen.txt=$OUT/heim/notizen.txt@0644"
       "/users/justin/tabelle.csv=$OUT/heim/tabelle.csv@0644"
       "/users/justin/brief.txt=$OUT/heim/brief.txt@0644")
rm -rf "$OUT/apps"; cp -a assets/apps "$OUT/apps"
# RUNDE MERGE-6: HIER STAND EIN NAME, JETZT STEHT DIE REGEL.
#
# `rm -rf "$OUT/apps/widgets.osp"` war noetig, weil /bin/widgetdemo
# nicht in der Programmliste dieses Laeufers steht und `mkfs.py`
# dann mit "gibt es nicht" abbricht. Die Runde WERKZEUGE hat ein
# zweites solches Buendel dazugelegt (taskmgr.osp) -- und dieser
# Laeufer ist beim ZUSAMMENFUEHREN daran gestorben:
#
#     FEHLGESCHLAGEN: mkfs
#     mkfs: '/bin/taskmgr' gibt es nicht
#
# Genommen wird derselbe Riegel, den WERKZEUGE fuer
# tools/themestore/build.sh gebaut hat: `bundle.py nur=`
# ueberspringt jedes Buendel, dessen Programm nicht auf DIESER
# Platte liegt. Damit ist die Aufnahme wieder genau die der Runde
# OBERFLAECHE -- dieselben Buendel, dasselbe Startmenue, dieselbe
# Messgrundlage -- und der naechste neue Buendelname bricht sie
# nicht mehr.
while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py "$OUT/apps" "$OUT/buendel" "nur=$progs" 2>/dev/null || true)
while read -r z; do ARGS+=("$z"); done < "$OUT/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$OUT/mkfs.log" 2>&1 \
    || { echo "FEHLGESCHLAGEN: mkfs"; tail -25 "$OUT/mkfs.log"; exit 1; }
echo "platte $(stat -c%s "$OUT/disk.img") Oktette"
# ======================================================= RUNDE CLIP-2
#
# EINE SICHERUNG DES ABBILDS, WIE ES VOR DEM START AUSSAH.
#
# Wer messen will, was ein Lauf an der Platte GEAENDERT hat, braucht
# den Zustand davor -- und zwar von DIESEM Abbild und nicht von einem
# zweiten, das ein frueherer Aufruf gebaut hat: `mkfs.py` laeuft je
# Aufruf neu (`--time=$(date +%s)`) und vergibt dabei andere
# Inodenummern. Genau daran hat die erste Messung der Runde CLIP-2
# einen sauberen `rename` als "inode anders" gemeldet.
#
# Eine Kopie von zehn Megaoktett, nur wenn jemand sie anfordert.
if [ "${vorherbild:-nein}" = ja ]; then
    cp "$OUT/disk.img" "$OUT/disk.img.vorher"
    echo "vorherbild $(stat -c%s "$OUT/disk.img.vorher") Oktette"
fi
[ "$nurbau" = ja ] && exit 0

# ------------------------------------------------------------ 3. starten
if [ -z "$drehbuch" ]; then
    drehbuch="$OUT/drehbuch.txt"
    cat > "$drehbuch" <<'DREH'
# `wig wigstart` laesst den Starter mit hochkommen -- das Startmenue ist
# also schon offen.  Zuerst wird es zugemacht, damit der Schreibtisch der
# Schreibtisch ist und nicht der Schreibtisch mit einem Fenster darauf.
warteauf 'launcher: ready' || 40
warte 1
klickauf start
warte 2
foto 01-schreibtisch
# --- das Startmenue wieder auf
klickauf start
warte 2
foto 02-startmenue
# ==================================================== RUNDE VEKTOR
# HIER DARF NICHT GEWARTET WERDEN, UND DAS IST GEMESSEN.
#
# Justins Befund: "das Abnahmeskript oeffnet Explorer, Einstellungen
# und Kontrollzentrum nie, deshalb sind 02-05 praktisch identisch".
# Er hat recht, und der Grund stand die ganze Zeit auf der Leitung:
#
#     launcher: ready
#     launcher: fokus weg t=9226 gnade=6335
#     launcher: zugemacht
#     ...
#     osum: syscalls=7 forks=0 execves=0     <- NIE ein Programm
#
# Der Starter macht sich SELBST zu, sobald er den Fokus verliert und
# die Gnadenfrist abgelaufen ist (launcher.fi: GNADE_TICKS = 30, also
# 300 ms bei 100 Hz). Ein `warte 1` zwischen den Klicks ist ZEHNMAL
# so lang. Beim Klick auf die Trefferzeile war das Menue also laengst
# zu, der Klick landete auf dem Schreibtisch, der Dateimanager kam nie
# hoch -- und `03-explorer`, `04-dialog` und `05-kontrollzentrum`
# zeigten alle denselben leeren Schreibtisch. Genau das hat er als
# "gleiche Bilder unter verschiedenen Namen" gemeldet.
#
# Es ist WEDER ein 4K-Fehler noch der Strg+N-Fehler aus OFFEN.md
# G-003: die beiden Bilder waren in JEDER Aufloesung Oktett fuer
# Oktett gleich (md5 1abb3b5236 bei 2560x1440, 5019abb57f bei
# 3840x2160).
#
# Also: klicken, ohne dazwischen zu warten.
# --- der Dateimanager: erste Zeile der Trefferliste, dann Ausfuehren
klickauf lzeile0
klickauf lrect3
warteauf 'explorer: ready' || 60
warte 3
# ================================================== RUNDE MERGE-10
# DAS STARTMENUE MUSS ZU SEIN, BEVOR EINE TASTE AN DEN DATEIMANAGER
# GEHEN KANN.
#
# Der Starter startet das Programm und BLEIBT DABEI OFFEN -- er liegt
# auf L_TOP und holt sich den Eingabefokus zurueck, sobald seine
# Bewegung ausgelaufen ist. Im Mitschnitt steht das woertlich:
#
#     wm: fokus id=14 vor=11     <- der Dateimanager bekommt ihn
#     explorer: ready
#     wm: fokus id=11 vor=14     <- der Starter holt ihn zurueck
#     key: ...                   <- und DORT landet Strg+N
#
# Solange das so ist, geht jedes `taste`-Kommando an das Startmenue
# und nicht an das Fenster, das im Bild zu sehen ist. Genau daran ist
# `04-dialog` in jedem bisherigen Lauf gescheitert -- das Bild war
# Oktett fuer Oktett `03-explorer`, und in OFFEN.md steht seitdem
# G-003 "Strg+N oeffnet keinen Dialog, im Emulator reproduzierbar".
#
# ESCAPE UND NICHT NOCH EIN KLICK AUF START. Der Klick ist ein
# UMSCHALTER: das Menue schliesst sich beim Starten eines Programms
# von selbst, ein Klick auf Start macht es dann WIEDER AUF -- gemessen
# als `taskbar: state n=3` mit einem zweiten Dateimanager (id=15)
# hinterher. `Escape` schliesst nur, es oeffnet nie, und der Starter
# nimmt es ausdruecklich entgegen (launcher.fi, `KEY_ESC` -> return).
# Ist das Menue schon zu, geht das Escape ins Leere und schadet nicht.
taste esc
warte 1
foto 03-explorer
# --- ein Dialog aus dem Dateimanager
taste ctrl-n
warte 3
foto 04-dialog
taste esc
warte 2
# --- das Kontrollzentrum in der Ecke der Leiste
klickauf netz
warte 3
foto 05-kontrollzentrum
# --- die Einstellungen ueber die unterste Zeile des Kontrollzentrums
klickauf qsalle
warteauf 'settings: ready' || 60
warte 3
foto 06-einstellungen
DREH
fi

SOCK="$OUT/mon.sock"; rm -f "$SOCK" "$OUT/serial.txt"
TONDEV=()
if [ "$ton" = ja ]; then
    # ZWEI DINGE, NICHT EINES. Die Karte an die Maschine reicht nicht --
    # der Kern setzt den Ton nur auf, wenn das Wort `audio` auf der
    # Befehlszeile steht (kernel/kmain.fi). Ohne es meldet die serielle
    # Ausgabe `aud: aus (kein Wort)`, das Feld bleibt leer, und das sah
    # beim ersten Anlauf wie ein Fehler im Regler aus.
    extra="$extra audio nosounds"
    # Die Ausgabe geht ins Nichts: hier wird ein BILD gemacht und
    # nicht gemessen, wie es klingt. Die Karte muss nur DA sein.
    TONDEV=(-audiodev none,id=snd0 -device intel-hda
            -device hda-duplex,audiodev=snd0)
fi
ACC=()
if [ "$accel" = kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACC=(-accel kvm -cpu host)
fi
# RUNDE FREMDFS: normalerweise faehrt dieser Laeufer OHNE Dateisystem
# (`nofs`) -- er malt Oberflaechen und braucht keine Platte. Wer ein
# fremdes Dateisystem IM Dateimanager zeigen will, braucht beides: die
# Wurzelplatte und die VFS-Schicht. `fs=an` schaltet darauf um.
FSFLAG="nofs"
[ "${fs:-aus}" = an ] && FSFLAG="vfs"

ZWEITE=()
if [ -n "$zweite" ]; then
    cp "$zweite" "$OUT/zweite.img"
    ZWEITE=(-drive "file=$OUT/zweite.img,format=raw,if=ide,index=1")
fi
timeout 600 qemu-system-x86_64 "${ACC[@]}" -kernel "$BUILDD/k0.mb" -m 512 \
    -append "gfx fbres=${XRES}x${YRES} wm desk wmhold wighalt=$halt nokbd nosched noproc $FSFLAG lang=$lang $SKAL $extra" \
    -serial "file:$OUT/serial.txt" -display none -no-reboot \
    -device "VGA,edid=on,xres=$XRES,yres=$YRES,vgamem_mb=32" \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$OUT/disk.img,format=raw,if=ide,index=0" \
    "${ZWEITE[@]}" \
    "${TONDEV[@]}" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$OUT/qemu.log" 2>&1 &
PID=$!
i=0
while [ $i -lt 2400 ]; do
    grep -qaE '^wm: hold' "$OUT/serial.txt" 2>/dev/null && break
    kill -0 "$PID" 2>/dev/null || break
    sleep 0.15; i=$((i+1))
done
if ! grep -qaE '^wm: hold' "$OUT/serial.txt" 2>/dev/null; then
    echo "FEHLGESCHLAGEN: der Fensterserver ist nie bis 'wm: hold' gekommen"
    tail -20 "$OUT/serial.txt" 2>/dev/null
fi

python3 -u tools/design/drive.py "$SOCK" "$OUT/serial.txt" "$OUT" "$drehbuch" \
    2>&1 | tee "$OUT/fahren.log"

wait "$PID"; RC=$?
rm -f "$SOCK"
echo "qemu exit $RC"

# ------------------------------------------------------------ 4. PNG
python3 - "$OUT" <<'PY'
import glob, os, sys
from PIL import Image
o = sys.argv[1]
for p in sorted(glob.glob(os.path.join(o, "*.ppm"))):
    im = Image.open(p).convert("RGB")
    q = p[:-4] + ".png"
    im.save(q)
    print("bild %s %dx%d farben=%d"
          % (os.path.basename(q), im.size[0], im.size[1],
             len(im.getcolors(maxcolors=1 << 24) or [])))
PY
exit 0
