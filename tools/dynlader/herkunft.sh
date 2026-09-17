#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/dynlader/herkunft.sh -- WELCHER FREMDCODE LANDET AUF DEM SYSTEM?
#
#   bash tools/dynlader/herkunft.sh
#
# Justins Frage vom 14.09.2026, woertlich: ist das "originaler Fremdcode"
# oder nur Uebersetzung?
#
# DIE EHRLICHE ANTWORT, und dieses Skript fuehrt sie vor statt sie zu
# behaupten: BEIDES, und es laesst sich sauber trennen.
#
#   * Was in DIESEM Repo steht, ist eigener Firn-Code. Die Runde
#     DYNLADER hat genau EINE Kerndatei angefasst (kernel/elf.fi) und
#     keine Zeile fremden Code hineingenommen. Regel 4 aus
#     /root/osum-roadmap/FREMDSOFTWARE.md -- "Kein Fremdcode im Kern" --
#     gilt unveraendert.
#
#   * Was auf dem SYSTEM landet, sind FREMDE BINAERDATEIEN. Sie sind
#     nicht uebersetzt, nicht nachgebaut und nicht angepasst: es sind
#     dieselben Oktette, die der Wirt hat. Genau das ist der Sinn der
#     Runde -- ein nachgebauter Lader waere kein Nachweis, dass Linux-
#     Programme laufen, sondern nur einer, dass unser Nachbau laeuft.
#
# Das Skript rechnet die SHA-256 jeder fremden Datei nach und nennt
# Herkunft, Fassung und Lizenz. Es AENDERT nichts.
set -uo pipefail
cd "$(dirname "$0")/../.."

LDSO=${LDSO:-/lib/ld-musl-x86_64.so.1}
BBDYN=${BBDYN:-/root/bbdyn/busybox}
BBQUELLE=${BBQUELLE:-/root/fremdquellen/busybox-1.36.1.tar.bz2}

echo "=================================================================="
echo " FREMDCODE DER RUNDE DYNLADER -- Herkunft, Fassung, Lizenz"
echo "=================================================================="
echo
echo "1. DER INTERPRETER  (Pflicht -- ohne ihn laeuft kein PT_INTERP-Bild)"
echo "   Paket:     linux-abi        Ziel auf dem System: /lib/ld-musl-x86_64.so.1"
echo "   Ring:      3                (wie jedes Programm; NICHT im Kern)"
echo "   Herkunft:  musl libc, https://musl.libc.org/"
if command -v dpkg >/dev/null 2>&1 && dpkg -s musl >/dev/null 2>&1; then
    echo "   Fassung:   $(dpkg -s musl | sed -n 's/^Version: //p')  (Debian-Paket musl:amd64)"
fi
echo "   Lizenz:    MIT -- Copyright 2005-2020 Rich Felker und Mitwirkende"
echo "   Form:      FERTIGE BINAERDATEI, unveraendert uebernommen."
if [ -r "$LDSO" ]; then
    R=$(readlink -f "$LDSO")
    echo "   Datei:     $R"
    echo "   Groesse:   $(stat -c%s "$R") Oktette"
    echo "   SHA-256:   $(sha256sum "$R" | cut -d' ' -f1)"
    echo "   Hinweis:   dieselbe Datei IST libc.so -- deshalb bringt sie"
    echo "              dlopen/dlsym mit, ohne dass etwas hinzukommt."
else
    echo "   Datei:     NICHT VORHANDEN ($LDSO)"
fi
echo
echo "2. DIE ZIELSOFTWARE  (optional -- nur zum Messen der Runde noetig)"
echo "   Paket:     busybox          Ziel auf dem System: /bin/busybox"
echo "   Ring:      3"
echo "   Herkunft:  BusyBox, https://busybox.net/"
echo "   Fassung:   1.36.1"
echo "   Lizenz:    GPL-2.0-only"
echo "   Form:      QUELLTEXT unveraendert, HIER gebaut (musl-gcc,"
echo "              CONFIG_STATIC aus). Das Binaergebilde ist unseres,"
echo "              der Quelltext ist fremd."
if [ -r "$BBQUELLE" ]; then
    echo "   Quelle:    $BBQUELLE"
    echo "   SHA-256:   $(sha256sum "$BBQUELLE" | cut -d' ' -f1)"
    if [ -r /root/fremdquellen/SHA256SUMS.txt ]; then
        SOLL=$(grep 'busybox-1.36.1.tar.bz2' /root/fremdquellen/SHA256SUMS.txt | cut -d' ' -f1)
        IST=$(sha256sum "$BBQUELLE" | cut -d' ' -f1)
        [ "$SOLL" = "$IST" ] \
            && echo "   Abgleich:  stimmt mit /root/fremdquellen/SHA256SUMS.txt ueberein" \
            || echo "   Abgleich:  WEICHT AB von SHA256SUMS.txt -- nachsehen!"
    fi
fi
if [ -r "$BBDYN" ]; then
    echo "   Binaer:    $BBDYN ($(stat -c%s "$BBDYN") Oktette)"
    echo "   SHA-256:   $(sha256sum "$BBDYN" | cut -d' ' -f1)"
fi
echo
echo "3. WAS VON UNS IST"
echo "   kernel/ldr/elf.fi -- die einzige Kerndatei, die diese Runde anfasst."
BASE=$(git merge-base main dynlader 2>/dev/null || echo "")
if [ -n "$BASE" ]; then
    git diff --numstat "$BASE"..dynlader -- kernel/ 2>/dev/null \
        | awk '{printf "   %-22s +%s -%s Zeilen\n", $3, $1, $2}'
    ZU=$(git diff "$BASE"..dynlader -- kernel/ldr/elf.fi | grep '^+' | grep -v '^+++' | wc -l)
    KOM=$(git diff "$BASE"..dynlader -- kernel/ldr/elf.fi | grep '^+' | grep -v '^+++' \
          | sed 's/^+//' | grep -cE '^\s*//')
    LEER=$(git diff "$BASE"..dynlader -- kernel/ldr/elf.fi | grep '^+' | grep -v '^+++' \
          | sed 's/^+//' | grep -cE '^\s*$')
    echo "   davon Kommentar: $KOM, leer: $LEER, echter CODE: $((ZU - KOM - LEER))"
fi
echo "   Keine Zeile fremden Codes im Kern. Kein uebernommenes ld.so,"
echo "   kein abgeschriebener Relokationscode -- der fremde Lader wird"
echo "   BENUTZT, nicht nachgebaut."
echo
echo "4. WAS IM GRUNDABBILD LIEGT"
if grep -q 'ld-musl' tools/usbimg/build.sh 2>/dev/null; then
    echo "   ACHTUNG: tools/usbimg/build.sh nennt ld-musl -- der Interpreter"
    echo "   waere damit im Standardabbild. Das widerspricht Regel 3."
else
    echo "   NICHTS davon. tools/usbimg/build.sh nennt weder ld-musl noch"
    echo "   ein dynamisches busybox; beide kommen als Paket (.opk)."
    echo "   Geprueft mit: grep ld-musl tools/usbimg/build.sh -> kein Treffer."
fi
echo
echo "=================================================================="
