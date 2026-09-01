#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ofs4/crash.sh -- EIN STROMAUSFALL, MITTEN IM GROESSENWECHSEL.
#
# Das Gegenstueck zu `tools/fsrobust/crash.sh`, und zwar bewusst nach
# demselben Muster: ein Lauf besteht aus zwei Starts derselben Platte.
#
#   1. `ofs4 pendel` verkleinert und vergroessert ohne Unterlass. Sobald
#      es `ofs4: los` gemeldet hat, wartet dieses Programm eine
#      ZUFAELLIGE Zeit und schiesst QEMU mit SIGKILL ab. Nicht
#      `system_powerdown`, nicht `quit`, nicht das Zeitlimit -- SIGKILL,
#      weil nur das dem entspricht, was ein Stromausfall ist.
#   2. Derselbe Kern startet noch einmal auf DENSELBEN Oktetten.
#      `mount` traegt das Journal nach, `/bin/fsck` prueft die Struktur.
#      Danach sieht der WIRT sich das Abbild an (tools/ofs4/pruef.py):
#      Struktur, INHALT des Bestandes und die Grenze. Drei Umsetzungen,
#      und alle drei muessen dasselbe sagen.
#
# DIE PLATTE HAENGT MIT `cache=directsync` DRAN, aus genau dem Grund,
# der in `tools/fsrobust/crash.sh` ausgeschrieben steht: ohne ihn landet
# das Geschriebene im Seitenpuffer des WIRTS, und der ueberlebt ein
# SIGKILL an QEMU muehelos -- der Test waere dann ein Test darueber,
# dass Linux keinen Speicher verliert.
#
# WAS HIER GEMESSEN WIRD, IST ETWAS ANDERES ALS IN DER RUNDE FSROBUST.
# Dort ging es um Daten, die mitten im Schreiben abbrechen. Hier geht es
# um die GROESSE des Dateisystems: nach dem Abschuss muss die Platte
# entweder die alte Groesse haben oder die neue, mit einem in sich
# stimmigen Bestand -- nie einen Zustand dazwischen. Ein halb
# verkleinertes Dateisystem waere der Schaden, den es zu verhindern
# gilt.
#
#   crash.sh <abbild> <arbeitsverzeichnis> <nummer> [zusatzwoerter]
#
# Ausgabe: EINE Zeile
#   lauf=<n> ms=<..> los=<..> blocks=<..> fsck=<..> nachgetragen=<..> wirt=<..>
set -u
cd "$(dirname "$0")/../.."

ABBILD=$1
ARB=$2
NR=$3
EXTRA=${4:-}

K=${OFS4_KERNEL:-/tmp/ofs4-k.mb}
ACC=${OFS4_ACCEL:-kvm}
MINMS=${OFS4_MINMS:-800}
# WIE LANGE WARTEN WIR AUF 'ofs4: los'? Auf einem gut ausgelasteten
# Rechner braucht der Gast bis zum ersten Pendelschlag laenger als die
# 120 Sekunden, die hier zuerst standen -- fuenf von fuenfzig Laeufen
# schossen deshalb waehrend des Startens statt waehrend des
# Groessenwechsels. Das ist kein Fehler des Dateisystems, sondern ein
# zu kurzer Messzaun; er steht jetzt bei 300 Sekunden.
LOSMS=${OFS4_LOSMS:-300000}
PAUSE=${OFS4_PAUSE:-0}
SPANMS=${OFS4_SPANMS:-55000}

LIVE="$ARB/live-$NR.img"
S1="$ARB/p-$NR.txt"
S2="$ARB/v-$NR.txt"
rm -f "$LIVE" "$S1" "$S2"
cp --sparse=always "$ABBILD" "$LIVE"

# ------------------------------------------- 1. pendeln und abschiessen
qemu-system-x86_64 -accel "$ACC" -kernel "$K" -m 512 \
    -append "osum vfs nokbd $EXTRA script=ofs4 pendel $PAUSE" \
    -serial "file:$S1" -display none -no-reboot \
    -drive "file=$LIVE,format=raw,if=ide,index=0,cache=directsync" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
QPID=$!

# Warten, bis das Programm wirklich pendelt. Ohne das traefe der
# Abschuss den Bootvorgang und nicht das Dateisystem.
LOS=0
for _ in $(seq 1 $(( LOSMS / 50 ))); do
    if [ -f "$S1" ] && tr -d '\000' < "$S1" 2>/dev/null | grep -qa 'ofs4: los'; then
        LOS=1
        break
    fi
    kill -0 "$QPID" 2>/dev/null || break
    sleep 0.05
done

# Die zufaellige Wartezeit. Sie kommt vom WIRT -- der Gast darf nicht
# wissen, wann er stirbt, sonst waere der Zeitpunkt kein Zufall mehr.
MS=$(( MINMS + (RANDOM * 32768 + RANDOM) % SPANMS ))
if [ "$LOS" = 1 ]; then
    sleep "$(awk "BEGIN{printf \"%.3f\", $MS/1000}")"
fi
kill -9 "$QPID" 2>/dev/null
wait "$QPID" 2>/dev/null

# Wie weit war er gekommen? Die Rundenzahl steht in der seriellen
# Ausgabe; null heisst, dass nicht einmal EIN Pendelschlag fertig wurde
# -- dann traf der Abschuss mitten hinein, und genau das ist der Fall,
# um den es geht.
RUNDEN=$(tr -d '\000' < "$S1" 2>/dev/null | grep -oa 'ofs4: runde = [0-9]*' \
    | tail -1 | sed 's/.*= //')

# ------------------------------------------------- 2. wieder hochfahren
# EIN WIEDERHOLVERSUCH, UND ZWAR NUR FUER DEN PRUEFLAUF.
# 21 ist der Wert, den `isa-debug-exit` liefert, wenn `fsck` wirklich
# bis zum Ende gekommen ist. Kam etwas anderes heraus, hat sich QEMU
# selbst verabschiedet, bevor die Schlusszeile geschrieben war -- die
# PLATTE ist davon unberuehrt, sie liegt unveraendert da. Dann wird
# derselbe Pruefstart genau EINMAL wiederholt. Das weicht nichts auf:
# geprueft werden dieselben Oktette, und wenn auch der zweite Versuch
# nichts liefert, bleibt fsck=? stehen und der Test wird rot.
VERS=0
while :; do
    timeout 900 qemu-system-x86_64 -accel "$ACC" -kernel "$K" -m 512 \
        -append "osum vfs nokbd $EXTRA script=fsck /dev/hda;exit" \
        -serial "file:$S2" -display none -no-reboot \
        -drive "file=$LIVE,format=raw,if=ide,index=0,cache=directsync" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    RC2=$?
    [ "$RC2" = 21 ] && break
    [ "$VERS" = 1 ] && break
    VERS=1
done

val() { tr -d '\000' < "$S2" 2>/dev/null | grep -a "^$1: $2 = " | head -1 | sed 's/.* = //'; }

FSCK=$(val fsck fehler)
GEOM=$(val fsck geom)
BLOCKS=$(val fsck blocks)
# WURDE UEBERHAUPT NACHGETRAGEN? Ohne diese Zahl waere "0 Schaeden" auch
# dann gruen, wenn das Journal in keinem Lauf gebraucht worden waere.
NACH=$(tr -d '\000' < "$S2" 2>/dev/null | grep -oa 'ofsj: nachgetragen=[0-9]*' \
    | head -1 | sed 's/.*=//')

# ------------------------------------------------- 3. der Wirt sieht nach
WS=$(python3 tools/ofs4/pruef.py struktur "$LIVE" 2>&1 | grep -c BEFUND)
WI=$(python3 tools/ofs4/pruef.py inhalt "$LIVE" 2>&1 | grep -c BEFUND)
WG=$(python3 tools/ofs4/pruef.py grenze "$LIVE" 2>&1 | grep -c BEFUND)
WIRT=$(( WS + WI + WG ))

echo "lauf=$NR ms=$MS los=$LOS runden=${RUNDEN:-0} blocks=${BLOCKS:-?}" \
     "fsck=${FSCK:-?} geom=${GEOM:-?} nachgetragen=${NACH:-0} wirt=$WIRT rc2=$RC2 wdh=$VERS"
if [ "$WIRT" != 0 ]; then
    python3 tools/ofs4/pruef.py struktur "$LIVE" 2>&1 | sed 's/^/    /'
    python3 tools/ofs4/pruef.py inhalt "$LIVE" 2>&1 | sed 's/^/    /'
    python3 tools/ofs4/pruef.py grenze "$LIVE" 2>&1 | sed 's/^/    /'
else
    # PLATZ IST KNAPP AUF DIESEM RECHNER. Ein Lauf, der nichts zu
    # zeigen hat, laesst nichts liegen.
    rm -f "$LIVE"
fi
