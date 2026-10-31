#!/usr/bin/env bash
#
#   bash tools/hotplug/run.sh
#
#     drive_add 0 id=stk1,if=none,file=...,format=raw
#     device_add usb-storage,id=devstk1,drive=stk1
#
# DIE ZUSAGEN:
#
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
BLOCKS=4096
PROGS="sh cat echo ls cp rm mkdir wc grep head true false ps mount umount eject"

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

python3 tools/osum/mkfs.py build "$ARB/root.img" "$BLOCKS" \
    /bin/ /proc/ /dev/ /mnt/ /usb/ /medien/ $MK > "$ARB/mkfs.log" 2>&1 \
    && ok "die Wurzelplatte steht: $(tail -1 "$ARB/mkfs.log")" \
    || { bad "mkfs.py scheitert"; sed 's/^/        /' "$ARB/mkfs.log" | head -5; }

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
    "osum usb usbhold vfs gfx nosched noproc script=ls /medien/usb0;cat /medien/usb0/host.txt;echo osum-war-hier > /medien/usb0/osum.txt;eject;eject 0;eject" \
    "$ARB/dreh-rw.txt"
S="$ARB/schreiben.txt"
num "der Lauf beendet sich selbst (21)" "${RC:-99}" eq 21
hat "$S" "host.txt" "ls sieht die Datei, die der WIRT auf den Stick gelegt hat"
hat "$S" "von linux auf den ersten stick" "und cat liest ihren Inhalt"
hat "$S" "/medien/usb0" "auswerfen zeigt den Traeger an"
hat "$S" "ejected: " "und wirft ihn aus"

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
if command -v fsck.fat >/dev/null 2>&1; then
    if fsck.fat -n "$STK@@$OFF" > "$ARB/fsck1.txt" 2>&1 \
       || ! grep -qai 'dirty\|corrupt\|error' "$ARB/fsck1.txt"; then
        ok "fsck.fat findet nach dem Auswerfen keinen Schaden"
    else
        bad "fsck.fat meldet Schaden"; sed 's/^/        /' "$ARB/fsck1.txt" | head -5
    fi
fi

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
    "osum usb usbhold vfs gfx nosched noproc script=ls /medien/usb0;ls /medien/usb1;cat /medien/usb0/host.txt;cat /medien/usb1/host.txt;echo eins-auf-usb0 > /medien/usb0/a.txt;echo zwei-auf-usb1 > /medien/usb1/b.txt;eject;eject 0;eject 1;eject" \
    "$ARB/dreh-zwei.txt"
S="$ARB/zwei.txt"
num "der Lauf mit zwei Sticks beendet sich selbst (21)" "${RC:-99}" eq 21
dv=$(grep -a 'devices=' "$S" | tail -1 | grep -oE 'devices=[0-9]+' | tail -1 | cut -d= -f2)
num "BEIDE Sticks werden aufgezaehlt (der USB-Baum kann zwei)" "${dv:-0}" ge 2

n_kommt=$(grep -ac 'wechsel: kommt' "$S" 2>/dev/null || echo 0)
num "BEIDE Sticks werden eingehaengt (zwei 'wechsel: kommt')" \
    "${n_kommt:-0}" eq 2
hat_nicht "$S" "wechsel: dev schon in der Tafel" \
    "kein Stick wird mehr als Doppelgaenger abgelehnt"
hat "$S" "/medien/usb0" "der erste haengt unter /medien/usb0"
hat "$S" "/medien/usb1" "der zweite unter /medien/usb1 -- EIGENER Pfad"

hat "$S" "von linux auf den ersten stick" "cat liest die Datei des ERSTEN Sticks"
hat "$S" "und dies ist der zweite" "cat liest die Datei des ZWEITEN Sticks"
hat "$S" "ejected: " "die Traeger werden ausgeworfen"
hat_nicht "$S" "panic" "kein Absturz am zweiten Stick"
hat_nicht "$S" "EXCEPTION" "keine Ausnahme bei zwei Sticks"

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
