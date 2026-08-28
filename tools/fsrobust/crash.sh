#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fsrobust/crash.sh -- EIN STROMAUSFALL, MITTEN IM SCHREIBEN.
#
# Ein Lauf besteht aus zwei Starts derselben Platte:
#
#   1. `fsrw endlos` schreibt ohne Unterlass. Sobald es `fsrw: los`
#      gemeldet hat, wartet dieses Programm eine ZUFAELLIGE Zeit und
#      schiesst QEMU mit SIGKILL ab. Nicht `system_powerdown`, nicht
#      `quit`, nicht das Zeitlimit -- SIGKILL, weil nur das dem
#      entspricht, was ein Stromausfall ist: der Rechner hoert mitten
#      im Satz auf.
#   2. Derselbe Kern startet noch einmal auf DENSELBEN Oktetten.
#      `mount` traegt das Journal nach, dann prueft `fsrv`, was
#      dasteht, und `/bin/fsck` prueft die Struktur.
#
# DIE PLATTE HAENGT MIT `cache=directsync` DRAN, und das ist der
# wichtigste Schalter dieses ganzen Programms: sonst landen die
# Schreibvorgaenge des Gastes im Seitenpuffer des WIRTS, und der
# ueberlebt ein SIGKILL. Der Test waere dann ein Test darueber, dass
# Linux keinen Speicher verliert. Mit `directsync` oeffnet QEMU die
# Datei mit O_DIRECT|O_DSYNC: was der Gast geschrieben hat, ist auf der
# Platte; was er nicht mehr geschrieben hat, ist weg. Genau das ist ein
# Stromausfall.
#
#   crash.sh <abbild> <arbeitsverzeichnis> <nummer> [nojournal]
#
# Ausgabe: EINE Zeile
#   lauf=<n> ms=<wartezeit> count=<..> schaeden=<..> fsck=<..> rc1=<..> rc2=<..>
set -u
cd "$(dirname "$0")/../.."

ABBILD=$1
ARB=$2
NR=$3
EXTRA=${4:-}

K=${FSR_KERNEL:-/tmp/fsr-k.mb}
MINMS=${FSR_MINMS:-120}
SPANMS=${FSR_SPANMS:-2600}

LIVE="$ARB/live-$NR.img"
S1="$ARB/w-$NR.txt"
S2="$ARB/v-$NR.txt"
rm -f "$LIVE" "$S1" "$S2"
cp --sparse=always "$ABBILD" "$LIVE"

# ------------------------------------------------- 1. schreiben und abschiessen
qemu-system-x86_64 -accel tcg -kernel "$K" -m 512 \
    -append "osum vfs nokbd $EXTRA script=fsrw endlos" \
    -serial "file:$S1" -display none -no-reboot \
    -drive "file=$LIVE,format=raw,if=ide,index=0,cache=directsync" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
QPID=$!

# Warten, bis das Programm wirklich schreibt. Ohne das traefe der
# Abschuss den Bootvorgang und nicht das Dateisystem.
LOS=0
for _ in $(seq 1 600); do
    if [ -f "$S1" ] && tr -d '\000' < "$S1" 2>/dev/null | grep -qa 'fsrw: los'; then
        LOS=1
        break
    fi
    kill -0 "$QPID" 2>/dev/null || break
    sleep 0.05
done

# Die zufaellige Wartezeit. `$RANDOM` ist der Wirt und nicht der Gast --
# der Gast darf nicht wissen, wann er stirbt.
MS=$(( MINMS + (RANDOM * 32768 + RANDOM) % SPANMS ))
if [ "$LOS" = 1 ]; then
    sleep "$(awk "BEGIN{printf \"%.3f\", $MS/1000}")"
fi
kill -9 "$QPID" 2>/dev/null
wait "$QPID" 2>/dev/null
RC1=$?

# ------------------------------------------------- 2. wieder hochfahren
timeout 600 qemu-system-x86_64 -accel tcg -kernel "$K" -m 512 \
    -append "osum vfs nokbd $EXTRA script=fsrv;fsck /dev/hda;exit" \
    -serial "file:$S2" -display none -no-reboot \
    -drive "file=$LIVE,format=raw,if=ide,index=0,cache=directsync" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
RC2=$?

val() { tr -d '\000' < "$S2" | grep -a "^$1: $2 = " | head -1 | sed 's/.* = //'; }

COUNT=$(val fsrv count)
SCH=$(val fsrv schaeden)
FSCK=$(val fsck fehler)
GESCHR=$(tr -d '\000' < "$S1" | grep -ac 'fsrw: los')
echo "lauf=$NR ms=$MS los=$LOS count=${COUNT:-?} schaeden=${SCH:-?}" \
     "fsck=${FSCK:-?} rc2=$RC2"
