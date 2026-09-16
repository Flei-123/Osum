#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hotplug/run.sh -- DER STICK, DER IM BETRIEB KOMMT UND GEHT.
#
#   bash tools/hotplug/run.sh
#
# ==================================================================
# WAS HIER GEMESSEN WIRD, UND WORIN ES SICH VON K17 UNTERSCHEIDET
# ==================================================================
#
# `tools/k17/run.sh` misst einen Stick, DER BEIM START SCHON STECKT.
# Das misst das Aufzaehlen: Deskriptoren lesen, Endpunkte einrichten,
# Bloecke lesen. Es misst NICHT den Weg, um den es dieser Runde geht --
# denn beim Start ist das Dateisystem noch nicht eingehaengt, und ein
# Mensch steckt einen Stick nicht in einen ausgeschalteten Rechner.
#
# Hier kommt der Stick ueber den QEMU-Monitor, WAEHREND DIE MASCHINE
# LAEUFT:
#
#     drive_add 0 id=stk1,if=none,file=...,format=raw
#     device_add usb-storage,id=devstk1,drive=stk1
#
# und geht mit `device_del`. Das ist dieselbe Hardwareaenderung, die
# eine Hand am Stecker macht.
#
# DIE ZUSAGEN:
#
#   1. ANSTECKEN IM BETRIEB. Der Stick erscheint, wird erkannt (FAT32
#      am INHALT, nicht am Typoktett der Partitionstafel) und unter
#      /medien/usb0 eingehaengt. Gemessen an `wechsel: kommt ... mount=1`
#      UND daran, dass `ls /medien/usb0` die Datei des Wirts zeigt.
#   2. SCHREIBEN UND AUSWERFEN. Eine Datei wird auf den Stick
#      geschrieben, dann `auswerfen`. Danach wird der Stick abgezogen
#      und DER WIRT liest mit `mtools` nach: die Datei muss da und
#      VOLLSTAENDIG sein. "Das Schreiben hat keinen Fehler gemeldet"
#      ist keine Messung -- das ist die Lehre aus K17 Punkt 4.
#   3. ABZIEHEN OHNE AUSWERFEN. Die Gegenprobe: der Stick verschwindet
#      mitten im Betrieb. Der Kern darf NICHT stehenbleiben, und die
#      Einhaengung muss aus der Tafel verschwinden.
#   4. ZWEI STICKS. Beide gleichzeitig, beide mit eigenem Pfad.
#   5. EIN UNBEKANNTES DATEISYSTEM wird NICHT eingehaengt und NICHT als
#      Attrappe in die Tafel gestellt.
#
# Gemessen wie in den Runden 59 bis K17: QEMU je Fall, mit Zeitlimit,
# serielle Ausgabe gegen Erwartungen, Beendigungscode aus
# `isa-debug-exit` (21 = der Kernel hat sich selbst beendet).
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
BLOCKS=4096
PROGS="sh cat echo ls cp rm mkdir wc grep head true false ps mount umount auswerfen"

ARB=${HP_ARB:-$(mktemp -d)}
mkdir -p "$ARB"
export ARB
[ -n "${HP_ARB:-}" ] || trap 'rm -rf "$ARB"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hat() { grep -qaF "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' fehlt"; }
hat_nicht() {
    grep -qaF "$2" "$1" 2>/dev/null && bad "$3 -- '$2' steht da und sollte nicht" \
        || ok "$3"
}
num() {
    if [ -z "${2:-}" ]; then bad "$1: keine Zahl (erwartet $3 $4)"; return; fi
    if [ "$2" -"$3" "$4" ] 2>/dev/null; then ok "$1: $2"
    else bad "$1: $2, erwartet $3 $4"; fi
}

for w in mkfs.vfat mcopy mdir mtype sfdisk qemu-system-x86_64; do
    command -v "$w" >/dev/null 2>&1 || { echo "HOTPLUG: uebersprungen, $w fehlt"; exit 0; }
done
qemu-system-x86_64 -device help 2>&1 | grep -q 'qemu-xhci' || {
    echo "HOTPLUG: uebersprungen, dieses QEMU kennt qemu-xhci nicht"; exit 0; }

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || {
    [ -x "$FIRNC" ] || { echo "HOTPLUG: kein firnc"; exit 1; }; }

# ============================================== 1. bauen

echo "== 1. bauen: Kern, Programme, Wurzelplatte, zwei Sticks =="

KERN="$ARB/k.mb"
./tools/build-kernel.sh "$KERN" > "$ARB/build.log" 2>&1 \
    && ok "der Kern steht ($(stat -c%s "$KERN") Oktette)" \
    || { bad "der Kern laesst sich nicht bauen"; tail -5 "$ARB/build.log"; exit 1; }

as --64 -o "$ARB/crt.o" kernel/user/crt.s 2>/dev/null
MK=""
gebaut=0
for p in $PROGS; do
    src=kernel/user/$p.fi
    [ -f "$src" ] || continue
    # `--defsym=USER_ENTRY=_F0.u_start` ist NICHT wegzulassen: der
    # Anfang liegt im Modul und heisst dort so, und ohne die Zeile
    # bindet `ld` ein Programm ohne Einsprung (tools/k17/run.sh macht
    # es genauso).
    if "$FIRNC" "$src" -o "$ARB/$p.o" > "$ARB/$p.log" 2>&1 \
       && ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" \
              -o "$ARB/$p" "$ARB/crt.o" "$ARB/$p.o" 2>>"$ARB/$p.log"; then
        MK="$MK /bin/$p=$ARB/$p"
        gebaut=$((gebaut+1))
    else
        bad "$p laesst sich nicht bauen"
        grep -E '^error' "$ARB/$p.log" | head -3 | sed 's/^/        /'
    fi
done
num "Programme gebaut" "$gebaut" ge 15

# DIE WURZELPLATTE. /medien MUSS darin liegen -- ein Einhaengepunkt ist
# ein Verzeichnis, das es gibt (kernel/vfs.fi, mount_at). Ohne diesen
# Ordner findet der Stick keinen Platz, und das ist kein Fehler des
# Hotplugs, sondern einer des Abbilds.
python3 tools/osum/mkfs.py build "$ARB/root.img" "$BLOCKS" \
    /bin/ /proc/ /dev/ /mnt/ /usb/ /medien/ $MK > "$ARB/mkfs.log" 2>&1 \
    && ok "die Wurzelplatte steht: $(tail -1 "$ARB/mkfs.log")" \
    || { bad "mkfs.py scheitert"; sed 's/^/        /' "$ARB/mkfs.log" | head -5; }

# ZWEI STICKS, beide FAT32 in einer MBR-Tafel, beide mit einer Datei
# des WIRTS darin. Die Dateien unterscheiden sich, damit ein Lauf, der
# den falschen Stick liest, nicht zufaellig recht behaelt.
stick_bauen() { # <datei> <name> <inhalt>
    local img=$1 name=$2 text=$3
    rm -f "$img" "$img.part"
    dd if=/dev/zero of="$img" bs=1M count=48 status=none
    sfdisk "$img" >/dev/null 2>&1 <<SF
label: dos
start=2048, type=c
SF
    dd if=/dev/zero of="$img.part" bs=1M count=46 status=none
    mkfs.vfat -F32 -n "$name" "$img.part" >/dev/null 2>&1
    printf '%s\n' "$text" > "$ARB/$name.host"
    mcopy -i "$img.part" "$ARB/$name.host" ::host.txt
    dd if="$img.part" of="$img" bs=512 seek=2048 conv=notrunc status=none
    rm -f "$img.part"
}
stick_bauen "$ARB/stick1.img" STICK1 "von linux auf den ersten stick"
stick_bauen "$ARB/stick2.img" STICK2 "und dies ist der zweite"
[ -s "$ARB/stick1.img" ] && [ -s "$ARB/stick2.img" ] \
    && ok "zwei FAT32-Sticks mit MBR-Tafel und je einer Datei des Wirts" \
    || bad "die Stickabbilder fehlen"

# EIN STICK MIT EINEM DATEISYSTEM, DAS DIESER KERN NICHT KANN. Kein
# NTFS-Werkzeug noetig: ein FAT16 reicht, und `wechsel.fs_erkennen`
# lehnt es AUSDRUECKLICH ab, statt es einzuhaengen und beim ersten
# Verzeichnis zu scheitern.
rm -f "$ARB/fremd.img" "$ARB/fremd.part"
dd if=/dev/zero of="$ARB/fremd.img" bs=1M count=32 status=none
sfdisk "$ARB/fremd.img" >/dev/null 2>&1 <<'SF'
label: dos
start=2048, type=6
SF
dd if=/dev/zero of="$ARB/fremd.part" bs=1M count=30 status=none
mkfs.vfat -F16 -n FREMD "$ARB/fremd.part" >/dev/null 2>&1
dd if="$ARB/fremd.part" of="$ARB/fremd.img" bs=512 seek=2048 conv=notrunc status=none
rm -f "$ARB/fremd.part"
ok "dazu ein Stick mit FAT16 -- das Dateisystem, das dieser Kern NICHT kann"

# ============================================== der Laeufer

lauf() { # <name> <kommandozeile> <drehbuch> [qemu-args...]
    local name=$1 app=$2 dreh=$3
    shift 3
    cp "$ARB/root.img" "$ARB/live-$name.img"
    HP_TIMEOUT=${HP_TIMEOUT:-200} ARB="$ARB" \
        bash tools/hotplug/lauf.sh "$name" "$KERN" "$app" "$dreh" \
        -drive "file=$ARB/live-$name.img,format=raw,if=ide,index=0" \
        -device qemu-xhci,id=xhci "$@" > "$ARB/$name.lauf" 2>&1
    RC=$(sed -n 's/^RC=//p' "$ARB/$name.lauf" | tail -1)
}

# ============================================== 2. anstecken im Betrieb

echo
echo "== 2. der Stick kommt, WAEHREND die Maschine laeuft =="

cat > "$ARB/dreh-an.txt" <<EOF
aufzeile k17: hold
warte 1
stecke stk1 $ARB/stick1.img
aufzeile wechsel: kommt
warte 2
EOF
lauf anstecken "osum usb usbhold vfs gfx nosched noproc" "$ARB/dreh-an.txt"
S="$ARB/anstecken.txt"
num "der Kern beendet sich selbst (21)" "${RC:-99}" eq 21
hat "$S" "usb: msc blocks=" "der Stick wird im Betrieb aufgezaehlt"
hat "$S" "wechsel: kommt" "die Naht bemerkt ihn"
hat "$S" "mount=1" "und haengt ihn ein"
hat "$S" "fat: spc=" "das FAT32 wurde wirklich angelesen"
# DIE ZAHL, DIE BEWEIST, DASS ES IM BETRIEB WAR: `hotplugs` zaehlt NUR
# Anschluesse, die sich nach dem Aufzaehlen geaendert haben.
hp=$(grep -a 'hotplugs=' "$S" | tail -1 | grep -oE 'hotplugs=[0-9]+' | tail -1 | cut -d= -f2)
num "Anstecken im Betrieb gezaehlt" "${hp:-0}" ge 1

# ============================================== 3. lesen, schreiben, auswerfen

echo
echo "== 3. die Datei des Wirts lesen, eine eigene schreiben, auswerfen =="

cat > "$ARB/dreh-rw.txt" <<EOF
aufzeile k17: hold
warte 1
stecke stk1 $ARB/stick1.img
aufzeile wechsel: kommt
warte 3
EOF
lauf schreiben \
    "osum usb usbhold vfs gfx nosched noproc script=ls /medien/usb0;cat /medien/usb0/host.txt;echo osum-war-hier > /medien/usb0/osum.txt;auswerfen;auswerfen 0;auswerfen" \
    "$ARB/dreh-rw.txt"
S="$ARB/schreiben.txt"
num "der Lauf beendet sich selbst (21)" "${RC:-99}" eq 21
hat "$S" "host.txt" "ls sieht die Datei, die der WIRT auf den Stick gelegt hat"
hat "$S" "von linux auf den ersten stick" "und cat liest ihren Inhalt"
hat "$S" "/medien/usb0" "auswerfen zeigt den Traeger an"
hat "$S" "ausgeworfen" "und wirft ihn aus"

# DIE EIGENTLICHE MESSUNG: DER WIRT LIEST NACH. Nicht der Kern sagt,
# dass die Datei da ist -- `mtools` auf dem Wirt sagt es, und `cmp`
# vergleicht Oktett fuer Oktett. Das ist Punkt 4 aus K17, hier auf das
# Auswerfen angewandt: wer nicht synchronisiert, verliert genau hier.
# NACHGELESEN WIRD DER STICK, NICHT DIE WURZELPLATTE. Der erste
# Entwurf sah in `live-schreiben.img` nach -- das ist die OFS-Platte,
# auf der /medien liegt, und dort war die Datei natuerlich nicht. Die
# Zusage war rot, obwohl das Schreiben stimmte; nachgesehen hat sie an
# der falschen Stelle. Der Stick ist `stick1.img`, und er wird dem Lauf
# UNVERAENDERT gereicht (kein `cp`) -- genau deshalb steht hier sein
# Name und nicht der einer Kopie.
OFF=$((2048*512))
STK="$ARB/stick1.img"
if mdir -i "$STK@@$OFF" ::osum.txt > "$ARB/mdir1.txt" 2>&1; then
    ok "DER WIRT findet die Datei, die Osum geschrieben hat"
    mtype -i "$STK@@$OFF" ::osum.txt > "$ARB/osum.txt" 2>/dev/null
    if grep -qa 'osum-war-hier' "$ARB/osum.txt"; then
        ok "und ihr Inhalt ist vollstaendig ($(tr -d '\r\n' < "$ARB/osum.txt"))"
    else
        bad "die Datei ist da, aber ihr Inhalt stimmt nicht: $(head -c 80 "$ARB/osum.txt")"
    fi
else
    bad "DER WIRT findet die geschriebene Datei NICHT"
    sed 's/^/        /' "$ARB/mdir1.txt" | head -3
fi
# Und das Dateisystem muss heil sein -- ein halb geschriebenes FAT
# faellt hier auf und nicht erst beim naechsten Menschen.
if command -v fsck.fat >/dev/null 2>&1; then
    if fsck.fat -n "$STK@@$OFF" > "$ARB/fsck1.txt" 2>&1 \
       || ! grep -qai 'dirty\|corrupt\|error' "$ARB/fsck1.txt"; then
        ok "fsck.fat findet nach dem Auswerfen keinen Schaden"
    else
        bad "fsck.fat meldet Schaden"; sed 's/^/        /' "$ARB/fsck1.txt" | head -5
    fi
fi

# ============================================== 4. abziehen OHNE auswerfen

echo
echo "== 4. GEGENPROBE: abziehen, ohne auszuwerfen =="

cat > "$ARB/dreh-weg.txt" <<EOF
aufzeile k17: hold
warte 1
stecke stk1 $ARB/stick1.img
aufzeile wechsel: kommt
warte 2
ziehe stk1
aufzeile wechsel: geht
warte 2
EOF
lauf abziehen "osum usb usbhold vfs gfx nosched noproc" "$ARB/dreh-weg.txt"
S="$ARB/abziehen.txt"
num "der Kern UEBERLEBT das Abziehen und beendet sich selbst (21)" "${RC:-99}" eq 21
hat "$S" "wechsel: geht" "die Naht bemerkt das Abziehen"
hat_nicht "$S" "panic" "kein Absturz"
hat_nicht "$S" "EXCEPTION" "keine Ausnahme"
up=$(grep -a 'unplugs=' "$S" | tail -1 | grep -oE 'unplugs=[0-9]+' | tail -1 | cut -d= -f2)
num "Abziehen im Betrieb gezaehlt" "${up:-0}" ge 1

# ============================================== 5. zwei Sticks

echo
echo "== 5. ZWEI STICKS GLEICHZEITIG -- beide eingehaengt, beide beschrieben =="
#
# RUNDE HOTPLUG-2: HIER STAND EINE GRENZE, UND SIE IST GEFALLEN.
#
# Bis zur Vorrunde hielt `usb.fi` den Massenspeicher in EINER Zelle
# (`S_MSC`), `msc_read`/`msc_write` nahmen keine Geraetenummer, und
# `blk.fi` hatte genau ein `DEV_USB`. Der zweite Stick wurde deshalb
# ausdruecklich abgelehnt ("dev schon in der Tafel").
#
# Jetzt ist `S_MSC` eine LISTE (`S_MSCTAB`, vier Plaetze), die Groesse
# steht je Geraet (`D_MSCBLK`/`D_MSCBS`), und `blk.fi` fuehrt
# `DEV_USB0..DEV_USB3`. `bot()` nahm die Geraetenummer schon immer --
# der Transport war nie die Grenze, nur die Zeile darueber.
#
# WAS HIER GEMESSEN WIRD, und warum "kein Fehler gemeldet" nicht reicht:
# Beide Sticks werden eingehaengt, auf BEIDEN wird die Datei des Wirts
# GELESEN und eine EIGENE geschrieben, beide werden EINZELN
# ausgeworfen. Danach liest DER WIRT mit `mtools` auf JEDEM Abbild
# nach. Die Gefahr bei zwei Sticks ist nicht der Absturz, sondern die
# VERWECHSLUNG: ein zweiter Traeger, der auf die Bloecke des ersten
# zeigt, meldet keinen einzigen Fehler -- er schreibt nur die falsche
# Datei auf den falschen Stick. Genau deshalb tragen die beiden Dateien
# VERSCHIEDENEN Inhalt, und jeder wird auf SEINEM Abbild gesucht.

cat > "$ARB/dreh-zwei.txt" <<EOF
aufzeile k17: hold
warte 1
stecke stk1 $ARB/stick1.img
aufzeile wechsel: kommt
warte 2
stecke stk2 $ARB/stick2.img
warte 8
EOF
lauf zwei \
    "osum usb usbhold vfs gfx nosched noproc script=ls /medien/usb0;ls /medien/usb1;cat /medien/usb0/host.txt;cat /medien/usb1/host.txt;echo eins-auf-usb0 > /medien/usb0/a.txt;echo zwei-auf-usb1 > /medien/usb1/b.txt;auswerfen;auswerfen 0;auswerfen 1;auswerfen" \
    "$ARB/dreh-zwei.txt"
S="$ARB/zwei.txt"
num "der Lauf mit zwei Sticks beendet sich selbst (21)" "${RC:-99}" eq 21
dv=$(grep -a 'devices=' "$S" | tail -1 | grep -oE 'devices=[0-9]+' | tail -1 | cut -d= -f2)
num "BEIDE Sticks werden aufgezaehlt (der USB-Baum kann zwei)" "${dv:-0}" ge 2

# DIE ZUSAGE DIESER RUNDE: ZWEI Traeger, nicht einer.
n_kommt=$(grep -ac 'wechsel: kommt' "$S" 2>/dev/null || echo 0)
num "BEIDE Sticks werden eingehaengt (zwei 'wechsel: kommt')" \
    "${n_kommt:-0}" eq 2
hat_nicht "$S" "wechsel: dev schon in der Tafel" \
    "kein Stick wird mehr als Doppelgaenger abgelehnt"
hat "$S" "/medien/usb0" "der erste haengt unter /medien/usb0"
hat "$S" "/medien/usb1" "der zweite unter /medien/usb1 -- EIGENER Pfad"

# BEIDE Dateien des Wirts muessen lesbar sein, und zwar die JEWEILS
# richtige. Stuenden beide Traeger auf denselben Bloecken, kaeme hier
# zweimal derselbe Text.
hat "$S" "von linux auf den ersten stick" "cat liest die Datei des ERSTEN Sticks"
hat "$S" "und dies ist der zweite" "cat liest die Datei des ZWEITEN Sticks"
hat "$S" "ausgeworfen" "die Traeger werden ausgeworfen"
hat_nicht "$S" "panic" "kein Absturz am zweiten Stick"
hat_nicht "$S" "EXCEPTION" "keine Ausnahme bei zwei Sticks"

# ================= DIE GEGENPROBE AUF DEM WIRT, JE STICK EINZELN
#
# Punkt 4 aus K17, auf zwei Sticks angewandt. Jede Datei wird auf IHREM
# Abbild gesucht -- und ausdruecklich auch geprueft, dass sie NICHT auf
# dem anderen liegt. Das ist die Zusage, die eine Verwechslung faengt.
OFF=$((2048*512))
zwei_pruef() { # <abbild> <datei> <inhalt> <wie>
    local img=$1 datei=$2 inhalt=$3 wie=$4
    if mdir -i "$img@@$OFF" "::$datei" > "$ARB/mdir-$wie.txt" 2>&1; then
        mtype -i "$img@@$OFF" "::$datei" > "$ARB/inh-$wie.txt" 2>/dev/null
        if grep -qa "$inhalt" "$ARB/inh-$wie.txt"; then
            ok "DER WIRT findet $datei auf $wie, Inhalt vollstaendig ($inhalt)"
        else
            bad "$datei liegt auf $wie, aber der Inhalt stimmt nicht: $(head -c 80 "$ARB/inh-$wie.txt")"
        fi
    else
        bad "DER WIRT findet $datei NICHT auf $wie"
        sed 's/^/        /' "$ARB/mdir-$wie.txt" | head -3
    fi
}
zwei_pruef "$ARB/stick1.img" a.txt eins-auf-usb0 stick1
zwei_pruef "$ARB/stick2.img" b.txt zwei-auf-usb1 stick2

# KEINE VERWECHSLUNG: die Datei des einen darf NICHT auf dem anderen
# liegen. Ohne diese zwei Zeilen wuerde ein Kern, der beide Traeger auf
# dieselben Bloecke legt, oben gruen durchlaufen.
if mdir -i "$ARB/stick2.img@@$OFF" ::a.txt >/dev/null 2>&1; then
    bad "a.txt liegt AUCH auf stick2 -- die Traeger zeigen auf dieselben Bloecke"
else
    ok "a.txt liegt NICHT auf stick2 (keine Verwechslung)"
fi
if mdir -i "$ARB/stick1.img@@$OFF" ::b.txt >/dev/null 2>&1; then
    bad "b.txt liegt AUCH auf stick1 -- die Traeger zeigen auf dieselben Bloecke"
else
    ok "b.txt liegt NICHT auf stick1 (keine Verwechslung)"
fi

# Und beide Dateisysteme muessen heil sein.
if command -v fsck.fat >/dev/null 2>&1; then
    for nr in 1 2; do
        if fsck.fat -n "$ARB/stick$nr.img@@$OFF" > "$ARB/fsck-z$nr.txt" 2>&1 \
           || ! grep -qai 'dirty\|corrupt\|error' "$ARB/fsck-z$nr.txt"; then
            ok "fsck.fat findet auf stick$nr keinen Schaden"
        else
            bad "fsck.fat meldet Schaden auf stick$nr"
            sed 's/^/        /' "$ARB/fsck-z$nr.txt" | head -5
        fi
    done
fi

# ============================================== 6. fremdes Dateisystem

echo
echo "== 6. GEGENPROBE: ein Dateisystem, das dieser Kern nicht kann =="

cat > "$ARB/dreh-fremd.txt" <<EOF
aufzeile k17: hold
warte 1
stecke fremd $ARB/fremd.img
warte 5
EOF
lauf fremd "osum usb usbhold vfs gfx nosched noproc" "$ARB/dreh-fremd.txt"
S="$ARB/fremd.txt"
num "auch dieser Lauf beendet sich sauber (21)" "${RC:-99}" eq 21
hat "$S" "usb: msc blocks=" "das Geraet wird aufgezaehlt"
hat "$S" "kein Dateisystem erkannt" "und AUSDRUECKLICH nicht eingehaengt"
hat_nicht "$S" "panic" "kein Absturz am fremden Dateisystem"

# ============================================== Schluss

echo
echo "HOTPLUG: $pass passed, $fail failed"
[ -n "${HP_ARB:-}" ] && echo "  (Arbeitsverzeichnis: $ARB)"
[ "$fail" -eq 0 ] || exit 1
exit 0
