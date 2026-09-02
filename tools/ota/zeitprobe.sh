#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ota/zeitprobe.sh -- WANN GENAU PASSIERT WAS BEIM EINSPIELEN.
#
# WOZU DAS DA IST: Test (e) schiesst die Maschine mitten im Einspielen
# ab. Damit das etwas misst, muessen die Schuesse dort liegen, wo wirklich
# geschrieben wird -- nicht in der Firmware. Im ersten vollen Lauf lagen
# alle dreissig Schuesse zwischen 1 und 16 Sekunden, und der Rechner war
# nach 16 Sekunden noch nicht einmal mit dem Hochfahren fertig: dreissig
# von dreissig Durchlaeufen endeten auf "alt", KEIN EINZIGER auf "neu".
# Dreissig gruene Haken, die nichts belegen.
#
# Diese Probe faehrt EINEN sauberen Lauf von `ota einspielen` und stempelt
# jede serielle Zeile mit der Zeit seit dem Start von QEMU. Daraus kommt
# das Fenster fuer die Schuesse. Ausgabe auf der Standardausgabe:
#
#     MS <Tab> <Zeile>            fuer jede Zeile
#   und am Ende auf Deskriptor 3 bzw. in --marken:
#     T_NETZ=..  T_SCHREIB=..  T_FERTIG=..  T_ENDE=..
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
OUT=${OUT:-/tmp/ota-run}
MARKEN=${1:-$OUT/zeitprobe.marken}
export OSUM_CPU=${OSUM_CPU:-Haswell}
NETZ="nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0"

OVMF=$(ls /usr/share/OVMF/OVMF_CODE.fd /usr/share/ovmf/OVMF.fd 2>/dev/null | head -1)
cp -f /usr/share/OVMF/OVMF_VARS.fd "$OUT/zp.vars.fd" 2>/dev/null || true
cp -f "$OUT/basis.img" "$OUT/zp.img"
{
    echo "timeout: 0"; echo "verbose: yes"; echo
    echo "/OrientOS"; echo "    protocol: multiboot1"
    echo "    path: boot():/osum.mb"
    echo "    cmdline: osum vfs nokbd nosched noproc nofs noring3 $NETZ script=ota einspielen;exit"
} > "$OUT/zp.conf"
mcopy -o -i "$OUT/zp.img@@1048576" "$OUT/zp.conf" ::/limine.conf 2>/dev/null

FIFO=$OUT/zp.fifo
rm -f "$FIFO"; mkfifo "$FIFO"

# Der Leser stempelt jede Zeile. Er muss VOR QEMU laufen, sonst blockiert
# das Oeffnen der Roehre.
python3 - "$FIFO" "$OUT/zp.stempel" <<'PY' &
import sys, time
fifo, ziel = sys.argv[1], sys.argv[2]
t0 = time.time()
with open(fifo, "rb") as f, open(ziel, "w") as z:
    z.write("# t0=%.3f\n" % t0)
    rest = b""
    while True:
        b = f.read(1)
        if not b:
            break
        if b in (b"\n", b"\r"):
            if rest.strip():
                z.write("%d\t%s\n" % ((time.time() - t0) * 1000,
                                      rest.decode("utf-8", "replace")))
                z.flush()
            rest = b""
        else:
            rest += b
PY
LESER=$!

qemu-system-x86_64 -machine pc -cpu "$OSUM_CPU" -m 512 -display none -no-reboot \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF" \
    -drive "if=pflash,format=raw,unit=1,file=$OUT/zp.vars.fd" \
    -serial "file:$FIFO" \
    -drive "file=$OUT/zp.img,format=raw,if=ide,index=0" \
    -netdev user,id=otan0 -device e1000,netdev=otan0,mac=52:54:00:0a:0b:0c \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
wait "$LESER" 2>/dev/null

sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/zp.stempel"
marke() { grep -aF "$1" "$OUT/zp.stempel" | head -1 | cut -f1; }
T_NETZ=$(marke "ota: quelle")
T_LADEN=$(marke "ota: streuwert stimmt")
T_SCHREIB=$(marke "opk: installiert")
T_FERTIG=$(marke "ota: BEREIT ZUM NEUSTART")
T_ENDE=$(tail -1 "$OUT/zp.stempel" | cut -f1)
{
    echo "T_NETZ=${T_NETZ:-0}"
    echo "T_LADEN=${T_LADEN:-0}"
    echo "T_SCHREIB=${T_SCHREIB:-0}"
    echo "T_FERTIG=${T_FERTIG:-0}"
    echo "T_ENDE=${T_ENDE:-0}"
} > "$MARKEN"
cat "$MARKEN"
