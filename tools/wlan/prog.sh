#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wlan/prog.sh -- /bin/wlan WIRKLICH LAUFEN LASSEN.
#
# Ein Programm, das nur uebersetzt, ist nicht gemessen. Dieser Laeufer
# baut ein Abbild MIT /bin/wlan darin, bootet es in QEMU und liest die
# Ausgabe der drei Unterbefehle, die ohne Karte etwas tun koennen:
# `status`, `chips` und `verbinden`.
#
# Was das misst und was nicht: es misst, dass das Programm laeuft,
# dass es die richtigen Saetze sagt und dass `/etc/wlan.conf` mit den
# Rechten 0600 entsteht. Es misst NICHT, dass sich irgendetwas
# verbindet -- es gibt keine Karte, und das Programm sagt das auch.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
W=${1:-/tmp/wlanprog-w}
mkdir -p "$W"

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

# 1. Uebersetzt es ueberhaupt?
if $FIRNC kernel/user/wlan.fi -o "$W/wlan" > "$W/bau.txt" 2>&1; then
    ok "kernel/user/wlan.fi uebersetzt (und bindet lib/wlan/usbchip.fi)"
else
    bad "kernel/user/wlan.fi uebersetzt nicht"
    head -20 "$W/bau.txt"
    echo "WLANPROG: $pass Zusagen, $fail Fehler"
    exit 1
fi

# 2. Es ist in den Programmlisten angemeldet -- sonst landet es in
#    keinem Abbild und niemand kann es aufrufen.
for f in tools/loader/build.sh tools/install/build.sh; do
    if grep -q '\bwlan\b' "$f"; then
        ok "$f fuehrt wlan in seiner Programmliste"
    else
        bad "$f kennt wlan nicht -- dann fehlt es im Abbild"
    fi
done

# 3. Die Saetze, die das Programm sagt, stehen wirklich drin. Das ist
#    eine schwaechere Zusage als ein Lauf, aber sie faellt auf, wenn
#    jemand die Ehrlichkeit herausnimmt.
if grep -q 'kein Geraet -- es gibt keinen Treiber' kernel/user/wlan.fi; then
    ok "'wlan status' sagt, dass es kein Geraet gibt, statt zu schweigen"
else
    bad "'wlan status' behauptet etwas anderes"
fi
if grep -q '0600\|384' kernel/user/wlan.fi; then
    ok "/etc/wlan.conf bekommt die Rechte 0600 (der PMK ist ein Geheimnis)"
else
    bad "die Rechte von /etc/wlan.conf werden nicht gesetzt"
fi
if grep -q 'SYS_UNLINK' kernel/user/wlan.fi; then
    ok "geht das Rechtesetzen schief, wird die Datei WIEDER GELOESCHT"
else
    bad "eine Datei mit falschen Rechten bliebe liegen"
fi

# 4. UND JETZT LAEUFT ES WIRKLICH. Alles davor war Papier: dass eine
#    Datei uebersetzt und die richtigen Saetze enthaelt, heisst nicht,
#    dass ein Mensch das Programm aufrufen kann. Dieser Teil baut ein
#    Abbild MIT /bin/wlan darin und ruft es in QEMU auf.
if ! command -v qemu-system-x86_64 > /dev/null 2>&1; then
    ok "kein QEMU vorhanden -- der Lauf wird uebersprungen (nicht behauptet)"
else
    if HWNET_PROGS="sh ls cat echo mkdir wlan" \
        bash tools/hwnet/build.sh "$W/img" 0 > "$W/img.txt" 2>&1; then
        ok "ein Abbild mit /bin/wlan darin baut"
        timeout 150 qemu-system-x86_64 -kernel "$W/img/k.mb" -m 256 \
            -append "osum script=wlan status;mkdir /etc;wlan verbinden MeinNetz geheim12345;cat /etc/wlan.conf;wlan verbinden X kurz;wlan vergessen;exit" \
            -serial "file:$W/lauf.txt" -display none -no-reboot \
            -drive "file=$W/img/disk.img,format=raw,if=ide,index=0" \
            -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
        RC=$?
        if [ "$RC" = 21 ]; then
            ok "Osum faehrt mit /bin/wlan sauber hoch und wieder herunter (Abbruchwert 21)"
        else
            bad "der Lauf endet mit $RC statt 21"
        fi
        L="$W/lauf.txt"
        grep -qa 'wlan: kein Gerät -- es gibt keinen Treiber' "$L" \
            && ok "'wlan status' sagt im LAUF, dass es kein Geraet gibt" \
            || bad "'wlan status' sagt im Lauf nichts dergleichen"
        grep -qa 'wlan: /etc/wlan.conf geschrieben für Netz MeinNetz' "$L" \
            && ok "'wlan verbinden' legt /etc/wlan.conf wirklich an" \
            || bad "/etc/wlan.conf wird im Lauf nicht angelegt"
        grep -qa '^ssid MeinNetz' "$L" && grep -qa '^psk geheim12345' "$L" \
            && ok "in /etc/wlan.conf stehen wirklich ssid und psk" \
            || bad "der Inhalt von /etc/wlan.conf stimmt nicht"
        grep -qa 'wlan: das Passwort muss 8 bis 63 Zeichen haben' "$L" \
            && ok "ein zu kurzes Passwort wird abgewiesen, statt es zu nehmen" \
            || bad "ein zu kurzes Passwort kommt durch"
        grep -qa 'wlan: /etc/wlan.conf gelöscht' "$L" \
            && ok "'wlan vergessen' loescht die Datei wieder" \
            || bad "'wlan vergessen' loescht nichts"
        # Und die Zusage, die am meisten wert ist: es wird NICHTS
        # behauptet, was nicht da ist.
        grep -qa 'wlan: verbunden wird damit NICHT' "$L" \
            && ok "das Programm sagt nach dem Einrichten ausdruecklich, dass es sich NICHT verbindet" \
            || bad "das Programm laesst offen, ob es sich verbindet"
    else
        bad "das Abbild mit /bin/wlan baut nicht"
        tail -5 "$W/img.txt"
    fi
fi

echo
echo "WLANPROG: $pass Zusagen, $fail Fehler"
[ "$fail" = "0" ] || exit 1
exit 0
