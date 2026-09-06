#!/bin/bash
# RUNDE TON -- DIE MESSSTRECKE.
#
# Kein Pruefstand, sondern ein MESSGERAET: EIN Lauf, EINE Zeile Zahlen.
# Die Frage, die dieses Skript beantwortet, ist nicht "geht es?",
# sondern "WORAN liegt es?" -- und dafuer braucht es die vier Zahlen aus
# kernel/audio.fi, die /bin/play am Ende ausgibt:
#
#   luecke_us   groesste Pause zwischen zwei Schueben aus Ring 3
#   kern_us     Zeit, die IN den Ton-Systemaufrufen verging
#   wand_us     erster bis letzter Schub
#   schuebe     wie oft Ring 3 ueberhaupt geliefert hat
#   minvorrat   kleinster Vorrat, der je im Ring stand (Rahmen)
#
# LESEART: ist luecke_us groesser als die Ringlatenz (85333 us), kam
# Ring 3 zu spaet -- der Puffer ist dann NICHT zu klein, der Abspieler
# ist zu langsam. Ist kern_us nahe an wand_us, frisst der Kern die
# Zeit. Ist minvorrat gross und trotzdem Aussetzer gezaehlt, zaehlt der
# Zaehler falsch.
#
# Verwendung: bash tools/ton/mess.sh [datei.wav] [smp]
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
PROGS="sh echo cat ls play"

MEDIA=${1:-/ton.wav}
# RUNDE TON-2: zusaetzliche Argumente an /bin/play (z. B. "-w 6" fuer
# sechs Durchlaeufe). Sie stehen VOR dem Pfad, weil /bin/play seine
# Optionen vor dem Dateinamen erwartet.
PLAYOPT=${TON_PLAYOPT:-}
SMP=${2:-4}
# QUELLE: ide (Platte an den ATA-Ports) oder ram (dieselbe Abbildung als
# Multiboot-Modul). Der Unterschied zwischen beiden Laeufen ist der
# Beweis, ob die Aussetzer vom TON kommen oder vom LESEN.
QUELLE=${3:-ide}
TMPD=${TON_TMPD:-$(mktemp -d)}
KEEP=${TON_KEEP:-0}
mkdir -p "$TMPD"
[ "$KEEP" = 1 ] || trap 'rm -rf "$TMPD"' EXIT

echo "== bauen =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/build.txt" 2>&1 \
    || { echo "der Kern baut nicht:"; tail -30 "$TMPD/build.txt"; exit 1; }
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null
for p in $PROGS; do
    "$FIRNC" -o "$TMPD/$p.o" "kernel/user/$p.fi" > "$TMPD/$p.log" 2>&1 || {
        echo "$p uebersetzt nicht"; tail -20 "$TMPD/$p.log"; exit 1; }
    ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start \
        -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2> >(grep -vE \
        'GNU-stack|deprecated|RWX' >&2) || { echo "$p bindet nicht"; exit 1; }
done
bash tools/hda/mkmedia.sh "$TMPD/m" > "$TMPD/media.txt" 2>&1
SPEC="/bin/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done
for f in "$TMPD"/m/*; do SPEC="$SPEC /$(basename "$f")=$f"; done
# RUNDE TON-2: die Platte richtet sich nach dem, was drauf soll.
# 16384 Sektoren (8 MiB) reichten fuer eine Sekunde Ton; die
# 60-s-Abnahme bringt allein 10,6 MiB mit. Statt einer festen Zahl
# wird gerechnet: alles, was hineinkommt, plus die Haelfte als Luft.
SEKT=$(( $(du -cb "$TMPD"/m/* "$TMPD"/*.elf 2>/dev/null | tail -1 | cut -f1) * 3 / 2 / 512 + 4096 ))
[ "$SEKT" -lt 16384 ] && SEKT=16384
python3 tools/osum/mkfs.py build "$TMPD/disk.img" "$SEKT" $SPEC > "$TMPD/mkfs.txt" 2>&1 \
    || { echo mkfs; tail -5 "$TMPD/mkfs.txt"; exit 1; }
echo "  Platte: $SEKT Sektoren, $(stat -c%s "$TMPD/disk.img") Oktette, Medien: $(ls "$TMPD/m" | tr '\n' ' ')"

HDADEV="-device intel-hda -device hda-duplex,audiodev=snd0"
aud="-audiodev wav,id=snd0,path=$TMPD/out.wav,out.frequency=48000,out.channels=2,out.format=s16"
rm -f "$TMPD/out.wav"
DISKARG="-drive file=$TMPD/disk.img,format=raw,if=ide,index=0"
[ "$QUELLE" = ram ] && DISKARG="-initrd $TMPD/disk.img"
EXTRA=""
[ "$QUELLE" = ram ] && EXTRA="modfs"
echo "== messen: /bin/play $PLAYOPT $MEDIA bei -smp $SMP, Quelle $QUELLE =="
timeout 600 $QEMU_X86 -kernel "$TMPD/k.mb" -m 512 -smp "$SMP" \
    -append "osum nokbd audio nosounds $EXTRA script=/bin/play $PLAYOPT $MEDIA;exit" \
    -serial "file:$TMPD/out.txt" -display none -no-reboot $aud $HDADEV \
    $DISKARG \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
echo "  Rueckgabe: $?"
echo "-- was /bin/play sagt ------------------------------------------"
sed -n '/art:/,$p' "$TMPD/out.txt" | sed 's/^/  /' | head -40
echo "-- was aus dem Geraet kam --------------------------------------"
if [ -s "$TMPD/out.wav" ]; then
    python3 tools/hda/wavcheck.py "$TMPD/out.wav" --hz 440 --rate 48000 2>&1 | sed 's/^/  /'
else
    echo "  KEINE Ausgabe -- out.wav ist leer"
fi
[ "$KEEP" = 1 ] && echo "(Arbeitsstand bleibt in $TMPD)"
exit 0
