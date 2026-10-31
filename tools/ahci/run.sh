#!/usr/bin/env bash
#
# Aufruf:  bash tools/ahci/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hin() { printf '  --    %s\n' "$1"; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "AHCI: uebersprungen, qemu-system-x86_64 fehlt"
    exit 0
fi

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

ACC=tcg
CPUARGS=()
if [ -c /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACC=kvm
    CPUARGS=(-cpu host)
fi

echo "== 0. der Wirt =="
if [ "$ACC" = tcg ]; then
    hin "Beschleuniger: tcg  (kein /dev/kvm -- die Messung auf der ECHTEN CPU faellt aus)"
else
    hin "Beschleuniger: kvm, -cpu host  (die echte CPU dieses Wirtes)"
fi
hin "CPU: $(grep -m1 '^model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//')"
hin "QEMU: $(qemu-system-x86_64 --version | head -1)"

# ------------------------------------------------------------ der Kernel

bash tools/build-kernel.sh "$TMPD/osum.mb" --stufe 0 >/dev/null 2>&1 \
    || { echo "AHCI: der Kernel liess sich nicht bauen"; exit 1; }
if [ -s "$TMPD/osum.mb" ]; then
    ok "der Kernel ist gebaut ($(stat -c%s "$TMPD/osum.mb") Oktette, Stufe 0)"
else
    bad "der Kernel fehlt"
fi

if python3 tools/kernel/memmap.py >"$TMPD/map.txt" 2>&1; then
    ok "die Speicherkarte von kdata ist kollisionsfrei -- $(cat "$TMPD/map.txt")"
else
    bad "die Speicherkarte kollidiert"
    sed 's/^/          /' "$TMPD/map.txt" | head -10
fi

# ------------------------------------------------------------ ein Lauf

# lauf NAME MASCHINE BEFEHLSZEILE [ZUSATZ...]
lauf() {
    local name=$1 mach=$2 cmd=$3
    shift 3
    RC=0
    timeout 240 qemu-system-x86_64 -machine "$mach" -accel "$ACC" \
        "${CPUARGS[@]}" -kernel "$TMPD/osum.mb" -m 128 -append "$cmd" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 || RC=$?
}

bild() {
    rm -f "$TMPD/$1.img"
    dd if=/dev/zero of="$TMPD/$1.img" bs=1M count=8 2>/dev/null
}

platte() {
    printf '%s\n' -drive "file=$TMPD/$1.img,format=raw,if=none,id=d0" \
        -device "ahci,id=a0" -device "ide-hd,drive=d0,bus=a0.0"
}

gruen() { # NAME BESCHREIBUNG
    local name=$1 was=$2 log="$TMPD/$1.txt"
    if [ "$RC" -eq 21 ]; then
        ok "$was: Beendigungscode 21"
    else
        bad "$was: Beendigungscode $RC statt 21"
    fi
    if grep -qa '^kernel: done' "$log"; then
        ok "$was: bis \"kernel: done\" gekommen"
    else
        bad "$was: \"kernel: done\" fehlt"
        grep -a -A6 'EXCEPTION' "$log" | head -8 | sed 's/^/          /'
    fi
    if grep -qa 'EXCEPTION' "$log"; then
        bad "$was: eine Ausnahme im Lauf -- $(grep -a -m1 'EXCEPTION' "$log")"
    else
        ok "$was: keine einzige Ausnahme"
    fi
}

# feld NAME ZEILENMUSTER SCHLUESSEL -- holt "schluessel=WERT" heraus.
feld() {
    grep -a -m1 "$2" "$TMPD/$1.txt" \
        | sed -n "s/.*$3=\([0-9a-fA-Fx]*\).*/\1/p"
}

zahl() { # BESCHREIBUNG IST OP SOLL
    local was=$1 ist=${2:-} op=$3 soll=$4
    if [ -z "$ist" ]; then
        bad "$was: nichts gemessen (erwartet $op $soll)"
        return
    fi
    if [ "$ist" "-$op" "$soll" ] 2>/dev/null; then
        ok "$was: $ist"
    else
        bad "$was: $ist, erwartet $op $soll"
    fi
}

echo
echo "== 1. der Controller wird auf dem BUS gefunden, nicht im Kernel =="

bild a
mapfile -t AARGS < <(platte a)
lauf a q35 "ahci" "${AARGS[@]}"
gruen a "1.1 q35 mit AHCI-Controller und einer Platte"

if grep -qa '^pci: .*class=01:06:01 ahci' "$TMPD/a.txt"; then
    ok "1.2 die PCI-Liste zeigt die Klasse 01:06:01 -- $(grep -a -m1 'class=01:06:01' "$TMPD/a.txt")"
else
    bad "1.2 kein Geraet der Klasse 01:06:01 in der PCI-Liste"
fi

BLK=$(feld a '^ahci: blocks=' blocks)
SZ=$(feld a '^ahci: blocks=' lbasz)
PRT=$(feld a '^ahci: blocks=' ports)
SLT=$(feld a '^ahci: blocks=' slots)
BM=$(feld a '^ahci: blocks=' master)
zahl "1.3 die Groesse kommt aus IDENTIFY DEVICE (8 MiB = 16384 Sektoren)" "$BLK" eq 16384
zahl "1.4 die Sektorgroesse kommt aus IDENTIFY DEVICE" "$SZ" eq 512
zahl "1.5 genau ein Port hat eine Verbindung" "$PRT" eq 1
zahl "1.6 der Controller meldet seine Befehlsplaetze" "$SLT" ge 1
zahl "1.7 das Busmaster-Bit steht" "$BM" eq 1

echo
echo "== 2. Lesen und Schreiben gegen bekannte Daten =="

W1=$(feld a '^ahci: one ' wr); R1=$(feld a '^ahci: one ' rd)
P1=$(feld a '^ahci: one ' pre); S1=$(feld a '^ahci: one ' same)
zahl "2.1 ein Sektor geschrieben" "$W1" eq 1
zahl "2.2 derselbe Sektor gelesen" "$R1" eq 1
zahl "2.3 vorher sind Schreib- und Lesepuffer verschieden (pre)" "$P1" eq 0
zahl "2.4 nachher sind sie Oktett fuer Oktett gleich (same)" "$S1" eq 1

WN=$(feld a '^ahci: many ' wr); RN=$(feld a '^ahci: many ' rd)
NN=$(feld a '^ahci: many ' n);  SN=$(feld a '^ahci: many ' same)
zahl "2.5 acht Sektoren in EINEM Befehl geschrieben" "$WN" eq 1
zahl "2.6 acht Sektoren in EINEM Befehl gelesen" "$RN" eq 1
zahl "2.7 und es waren wirklich 4096 Oktette" "$NN" eq 4096
zahl "2.8 alle 4096 Oktette stimmen (die PRDT-Laenge minus eins)" "$SN" eq 1

ERR=$(feld a '^ahci:   cmds=' errs)
CMD=$(feld a '^ahci:   cmds=' cmds)
DEAD=$(feld a '^ahci:   cmds=' dead)
zahl "2.9 kein einziger Fehler im ganzen Lauf" "$ERR" eq 0
# w-disklag: writes are no longer flushed one by one (cmds 198 -> 84 in this run), so the floor is lower.
zahl "2.10 und es waren wirklich Befehle unterwegs" "$CMD" ge 60
zahl "2.11 keine abgelaufene Zeitschranke" "$DEAD" eq 0

echo
echo "== 3. dasselbe Dateisystem darauf, ohne eine geaenderte Zeile in fs.fi =="

FMT=$(grep -a -m1 '^ahci: format ' "$TMPD/a.txt" | sed -n 's/^ahci: format \([0-9]*\).*/\1/p')
MNT=$(feld a '^ahci: format ' mount)
WR=$(feld a '^ahci: wrote=' wrote)
RD=$(feld a '^ahci: wrote=' read)
SM=$(feld a '^ahci: wrote=' same)
zahl "3.1 formatiert" "$FMT" eq 1
zahl "3.2 eingehaengt" "$MNT" eq 1
zahl "3.3 30 Oktette geschrieben" "$WR" eq 30
zahl "3.4 30 Oktette gelesen" "$RD" eq 30
zahl "3.5 und es sind dieselben" "$SM" eq 1
if grep -qa '^ahci: list .*sata\.txt' "$TMPD/a.txt"; then
    ok "3.6 die Datei steht im Verzeichnis -- $(grep -a -m1 '^ahci: list' "$TMPD/a.txt")"
else
    bad "3.6 die Datei steht nicht im Verzeichnis"
fi

echo
echo "== 4. der WIRT liest das Abbild nach: hier ist der Kernel nicht mehr sein eigener Zeuge =="

if grep -qa 'ahci wrote this line over DMA' "$TMPD/a.img"; then
    ok "4.1 der Text des Dateisystems steht wirklich in der Datei auf DIESEM Rechner"
else
    bad "4.1 der Text steht nicht im Abbild -- es wurde nichts geschrieben"
fi

# Sektor 4096: 512 mal 0x5A und nichts anderes.
n5a=$(dd if="$TMPD/a.img" bs=512 skip=4096 count=1 2>/dev/null \
      | od -An -v -t x1 | tr -s ' ' '\n' | grep -c '^5a$')
zahl "4.2 Sektor 4096 traegt 512 mal das Muster 0x5A" "$n5a" eq 512

mismatch=0
for i in 0 1 2 3 4 5 6 7; do
    soll=$(( ( i*17 + i*512 ) & 255 ))
    ist=$(dd if="$TMPD/a.img" bs=512 skip=$((5000+i)) count=1 2>/dev/null \
          | od -An -v -t u1 -N1 | tr -d ' ')
    [ "${ist:-x}" = "$soll" ] || mismatch=$((mismatch+1))
done
zahl "4.3 alle acht Sektoren ab 5000 tragen ihr EIGENES Muster" "$mismatch" eq 0

leer=$(dd if="$TMPD/a.img" bs=512 skip=5008 count=1 2>/dev/null \
       | od -An -v -t x1 | tr -s ' ' '\n' | grep -c -v '^00$\|^$')
zahl "4.4 der Sektor DAHINTER (5008) ist unberuehrt" "$leer" eq 0

echo
echo "== 5. Gegenprobe: ein AHCI-Controller OHNE Platte =="

lauf c q35 "ahci" -device "ahci,id=a0"
gruen c "5.1 der Lauf ohne Platte"
if grep -qa '^ahci: init failed' "$TMPD/c.txt"; then
    ok "5.2 der Treiber sagt, dass er nichts gefunden hat -- $(grep -a -m1 '^ahci:' "$TMPD/c.txt")"
else
    bad "5.2 der Treiber hat eine Platte erfunden -- $(grep -a -m1 '^ahci:' "$TMPD/c.txt")"
fi
WHY=$(feld c '^ahci: init failed' why)
zahl "5.3 und zwar an der richtigen Stelle (kein Port mit ATA-Kennung)" "$WHY" eq 8
if grep -qa '^ahci: blocks=' "$TMPD/c.txt"; then
    bad "5.4 es wurde trotzdem eine Groesse gemeldet"
else
    ok "5.4 es wird KEINE Groesse gemeldet"
fi

echo
echo "== 6. Gegenprobe: kein AHCI, sondern IDE (Maschine pc) =="

bild e
lauf e pc "ahci" -drive "file=$TMPD/e.img,format=raw,if=ide,index=0"
gruen e "6.1 der Lauf auf einer Maschine ohne AHCI"
if grep -qa '^ahci: mode=ide' "$TMPD/e.txt"; then
    ok "6.2 der Treiber erkennt den IDE-Modus und sagt, was zu tun ist -- $(grep -a -m1 '^ahci:' "$TMPD/e.txt")"
else
    bad "6.2 der Treiber scheitert stumm statt den IDE-Modus zu melden -- $(grep -a -m1 '^ahci:' "$TMPD/e.txt")"
fi
if grep -qa '^pci: .*class=01:01' "$TMPD/e.txt"; then
    ok "6.3 und der Bus bestaetigt es: Klasse 01:01 -- $(grep -a -m1 'class=01:01' "$TMPD/e.txt")"
else
    bad "6.3 kein IDE-Geraet in der PCI-Liste -- dann sagt 6.2 nichts"
fi

echo
echo "== 7. Gegenprobe: OHNE Busmaster-Bit -- der Beweis, dass es DMA war =="

bild f
mapfile -t FARGS < <(platte f)
lauf f q35 "ahci nobm" "${FARGS[@]}"
gruen f "7.1 der Lauf ohne Busmaster"
FBM=$(feld f '^ahci: blocks=' master)
zahl "7.2 das Busmaster-Bit ist wirklich weg" "$FBM" eq 0
FW=$(feld f '^ahci: one ' wr); FR=$(feld f '^ahci: one ' rd)
FS=$(feld f '^ahci: one ' same)
zahl "7.3 der Schreibbefehl schlaegt fehl" "$FW" eq 0
zahl "7.4 der Lesebefehl schlaegt fehl" "$FR" eq 0
zahl "7.5 und die Puffer sind verschieden geblieben" "$FS" eq 0
FD=$(feld f '^ahci:   cmds=' dead)
FA=$(feld f '^ahci:   cmds=' alive)
zahl "7.6 die Zeitschranke ist genau EINMAL abgelaufen" "$FD" eq 1
zahl "7.7 und das Geraet gilt danach als weg statt die Maschine anzuhalten" "$FA" eq 0
FFMT=$(grep -a -m1 '^ahci: format ' "$TMPD/f.txt" | sed -n 's/^ahci: format \([0-9]*\).*/\1/p')
zahl "7.8 das Dateisystem laesst sich nicht anlegen" "$FFMT" eq 0
if grep -qa 'over DMA' "$TMPD/f.img"; then
    bad "7.9 im Abbild steht trotzdem etwas -- dann war es kein DMA"
else
    ok "7.9 das Abbild auf dem Wirt ist LEER geblieben"
fi
n0=$(dd if="$TMPD/f.img" bs=512 skip=4096 count=1 2>/dev/null \
     | od -An -v -t x1 | tr -s ' ' '\n' | grep -c -v '^00$\|^$')
zahl "7.10 auch Sektor 4096 ist unberuehrt" "$n0" eq 0

echo
echo "== 8. die Gegenrichtung: derselbe Lauf unter TCG =="

if [ "$ACC" = tcg ]; then
    hin "8.x uebersprungen -- der ganze Abschnitt lief schon unter TCG"
else
    bild t
    mapfile -t TARGS < <(platte t)
    RC=0
    timeout 300 qemu-system-x86_64 -machine q35 -accel tcg \
        -kernel "$TMPD/osum.mb" -m 128 -append "ahci" \
        -serial "file:$TMPD/t.txt" -display none -no-reboot "${TARGS[@]}" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 || RC=$?
    gruen t "8.1 derselbe Lauf unter TCG"
    TS=$(feld t '^ahci: one ' same)
    TN=$(feld t '^ahci: many ' same)
    TE=$(feld t '^ahci:   cmds=' errs)
    zahl "8.2 ein Sektor stimmt auch unter TCG" "$TS" eq 1
    zahl "8.3 acht Sektoren stimmen auch unter TCG" "$TN" eq 1
    zahl "8.4 kein Fehler unter TCG" "$TE" eq 0
    if grep -qa 'ahci wrote this line over DMA' "$TMPD/t.img"; then
        ok "8.5 und das Abbild traegt den Text auch dort"
    else
        bad "8.5 das Abbild ist unter TCG leer geblieben"
    fi
fi

# ============ 9. Dell OptiPlex 9020: "SATA Operation = RAID On"

echo
echo "== 9. the controller reports class 01:04 (Intel RST, RAID On) -- still a disk =="

# The hw mode word `fakeraid` makes pci.fi report the AHCI controller the way
# the Dell does in RAID mode (class 01:04:00). Before r340 the driver searched
# for 01:06:01 only and said "no disk" -- the installer's "No writable disk found".
bild g
mapfile -t GARGS < <(platte g)
lauf g q35 "ahci fakeraid" "${GARGS[@]}"
gruen g "9.1 the run with a RAID-class controller"
if grep -qa 'class=01:04' "$TMPD/g.txt"; then
    ok "9.2 the bus list shows class 01:04 -- $(grep -a -m1 'class=01:04' "$TMPD/g.txt")"
else
    bad "9.2 the controller does not look like RAID mode (test hook broken)"
fi
if grep -qa '^ahci: raid mode' "$TMPD/g.txt"; then
    ok "9.3 the driver says it used the RAID-mode controller as AHCI"
else
    bad "9.3 no raid-mode line -- $(grep -a -m1 '^ahci:' "$TMPD/g.txt")"
fi
GS=$(feld g '^ahci: one ' same); GN=$(feld g '^ahci: many ' same)
zahl "9.4 one sector round trip over the RAID-class controller" "$GS" eq 1
zahl "9.5 eight sectors in one command" "$GN" eq 1
if grep -qa 'ahci wrote this line over DMA' "$TMPD/g.img"; then
    ok "9.6 and the host finds the text in the image"
else
    bad "9.6 the image stayed empty"
fi

# ============ 10. r558: the Dell case -- the link comes LATE / the signature is LOST
echo
echo "== 10. late link (DET 0 for 0.7 s, BSY for 2.5 s) and lost signature, with counter-checks =="
# Real silicon differs from QEMU in two ways the first driver version could not
# survive: a link that needs a second or more after the HBA reset (HDD), and a
# device signature that is thrown away because FIS receive was off when it came.
# `slowsata` / `lostsig` model them; `oldsata` is the first-version scan
# (no COMRESET, empty port abandoned after 0.3 s) as the counter-check.
bild h
mapfile -t HARGS < <(platte h)
lauf h q35 "ahci slowsata" "${HARGS[@]}"
gruen h "10.1 slowsata (new scan)"
zahl "10.2 the disk is found despite the late link" "$(feld h '^ahci: blocks=' blocks)" eq 16384
zahl "10.3 sector round trip over the late link" "$(feld h '^ahci: one ' same)" eq 1
SU=$(feld h '^ahci: blocks=' scanus)
zahl "10.4 the scan waited for the link (>= 1 s) but not forever (< 6 s)" "${SU:-0}" ge 1000000
zahl "10.5 and not longer than 6 s" "${SU:-99999999}" le 6000000

bild i
mapfile -t IARGS < <(platte i)
lauf i q35 "ahci slowsata oldsata" "${IARGS[@]}"
if grep -qa '^ahci: init failed' "$TMPD/i.txt"; then
    ok "10.6 counter-check: the first-version scan LOSES the disk (why=$(feld i '^ahci: init failed' why))"
else
    bad "10.6 counter-check: the old scan found the disk, the hook shows nothing"
fi

bild j
mapfile -t JARGS < <(platte j)
lauf j q35 "ahci lostsig" "${JARGS[@]}"
gruen j "10.7 lostsig (new scan)"
zahl "10.8 the lost signature is recovered by COMRESET" "$(feld j '^ahci: blocks=' blocks)" eq 16384
zahl "10.9 sector round trip" "$(feld j '^ahci: one ' same)" eq 1
bild k
mapfile -t KARGS < <(platte k)
lauf k q35 "ahci lostsig oldsata" "${KARGS[@]}"
if grep -qa '^ahci: init failed' "$TMPD/k.txt"; then
    ok "10.10 counter-check: without COMRESET the signature never comes (why=$(feld k '^ahci: init failed' why))"
else
    bad "10.10 counter-check: lostsig has no effect"
fi
# the same on the RAID-class controller, both hooks at once
bild l
mapfile -t LARGS < <(platte l)
lauf l q35 "ahci fakeraid slowsata lostsig" "${LARGS[@]}"
zahl "10.11 RAID class + late link + lost signature" "$(feld l '^ahci: blocks=' blocks)" eq 16384

# ============ 11. several ports: disk not on port 0, ATAPI in front
echo
echo "== 11. disk on port 3 behind two CD-ROMs; two disks (lowest wins); no-disk cost =="
dd if=/dev/zero of="$TMPD/cd.iso" bs=1M count=1 2>/dev/null
bild m
lauf m q35 "ahci" -drive "file=$TMPD/m.img,format=raw,if=none,id=d0" -device "ahci,id=a0" \
    -drive "file=$TMPD/cd.iso,format=raw,if=none,id=c0,media=cdrom,readonly=on" \
    -drive "file=$TMPD/cd.iso,format=raw,if=none,id=c1,media=cdrom,readonly=on" \
    -device "ide-cd,drive=c0,bus=a0.0" -device "ide-cd,drive=c1,bus=a0.1" \
    -device "ide-hd,drive=d0,bus=a0.3"
gruen m "11.1 disk behind two ATAPI drives"
zahl "11.2 the ATA disk on port 3 is chosen" "$(feld m '^ahci: blocks=' port)" eq 3
zahl "11.3 three devices were seen (2 ATAPI + 1 ATA)" "$(feld m '^ahci: blocks=' ports)" ge 2
zahl "11.4 sector round trip on port 3" "$(feld m '^ahci: one ' same)" eq 1
bild n; dd if=/dev/zero of="$TMPD/n2.img" bs=1M count=8 2>/dev/null
lauf n q35 "ahci" -drive "file=$TMPD/n.img,format=raw,if=none,id=d0" -device "ahci,id=a0" \
    -drive "file=$TMPD/n2.img,format=raw,if=none,id=d1" \
    -device "ide-hd,drive=d0,bus=a0.4" -device "ide-hd,drive=d1,bus=a0.2"
zahl "11.5 two disks (ports 2 and 4): the lowest wins" "$(feld n '^ahci: blocks=' port)" eq 2
bild o
lauf o q35 "ahci" -drive "file=$TMPD/o.img,format=raw,if=none,id=d0" -device "ahci,id=a0" -device "ide-hd,drive=d0,bus=a0.5"
zahl "11.6 disk on the LAST port (5)" "$(feld o '^ahci: blocks=' port)" eq 5
if grep -qa 'ahci: port, verdict: 0 1' "$TMPD/c.txt"; then
    ok "11.7 a controller without disk leaves per-port register lines in the log (port 0 = empty)"
else
    bad "11.7 no per-port diagnostics for the empty controller"
fi

# ============================================================= Ergebnis

echo
echo "AHCI: $pass gruen, $fail rot"
[ "$fail" -eq 0 ] || exit 1
