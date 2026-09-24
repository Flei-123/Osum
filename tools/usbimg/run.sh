#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/usbimg/run.sh -- DIE ABNAHME DER RUNDE USBIMG.
#
#   bash tools/usbimg/run.sh [arbeitsverzeichnis]
#
# ==================================================================
# WAS HIER GEMESSEN WIRD, UND WARUM ES UNTER KVM GEMESSEN WIRD
# ==================================================================
#
# Die Runde KVMFIX hat vorgefuehrt, was TCG verschweigt: zwei Fehler, die
# auf jeder AMD-CPU toedlich sind, standen 25 Runden lang unter einer
# Nachbildung, die sie stillschweigend zurechtbog. Ein Abbild, das auf
# einem ECHTEN Rechner starten soll, wird deshalb hier auf der ECHTEN CPU
# gestartet: `-accel kvm -cpu host`. Was darunter kracht, kracht auch auf
# Justins Blech.
#
# DIE VIER LAEUFE:
#
#   1. BIOS. Der Startweg ueber `limine bios-install` und den MBR-Bereich.
#   2. UEFI. Dieselbe Datei, dieselbe `limine.conf`, aber die Firmware
#      (OVMF) startet /EFI/BOOT/BOOTX64.EFI. Das ist der Lauf, der ohne
#      Bit 2 im Multiboot-Kopf mit "Cannot use text mode with UEFI"
#      abbraeche.
#   3. AHCI STATT IDE. Damit die Diagnose etwas ANDERES melden muss.
#      Meldete sie in beiden Laeufen dasselbe, waere sie kein Messgeraet,
#      sondern eine Konstante.
#   4. e1000 STATT virtio-net. Dieselbe Gegenprobe fuer den Netzteil:
#      `netdev` muss die andere Karte nennen -- oder, wenn es sie nicht
#      bedienen kann, "no driver for" mit Hersteller und Geraet.
#
# UND EIN BILD. Der Schreibtisch-Eintrag der `limine.conf` wird gefahren
# und fotografiert, und in dem Foto muessen DEUTSCHE Texte MIT UMLAUTEN
# stehen. Das ist die eigentliche Gegenprobe zum Fehler der letzten
# Runde: Sprachdateien im Abbild, die die Oberflaeche dann doch nicht
# benutzt, waeren derselbe Fehler mit einer neuen Ausrede.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

TMPD=${1:-$(mktemp -d)}
mkdir -p "$TMPD"
IMGDIR="$TMPD/bau"
IMG="$IMGDIR/osum-usb.img"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  \033[32mok\033[0m   %s\n' "$*"; }
bad() { fail=$((fail + 1)); printf '  \033[31mNEIN\033[0m %s\n' "$*"; }
is() { # was ist soll
    if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: $2 (erwartet $3)"; fi
}

OVMF_CODE=""
for c in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd \
         /usr/share/ovmf/OVMF.fd; do
    [ -f "$c" ] && { OVMF_CODE=$c; break; }
done
OVMF_VARS=""
for v in /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd; do
    [ -f "$v" ] && { OVMF_VARS=$v; break; }
done
KVM=()
[ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)

echo "== 1. das Abbild bauen =="
if bash tools/usbimg/build.sh "$IMGDIR" > "$TMPD/build.txt" 2>&1; then
    ok "tools/usbimg/build.sh laeuft durch"
    sed 's/^/       /' "$TMPD/build.txt"
else
    bad "das Abbild laesst sich nicht bauen"
    sed 's/^/       /' "$TMPD/build.txt" | tail -20
    echo "USBIMG: $pass bestanden, $fail gescheitert"
    exit 1
fi

echo "== 2. was in der Datei wirklich steht =="
if sgdisk --print "$IMG" > "$TMPD/gpt.txt" 2>&1; then
    grep -q 'EF00' "$TMPD/gpt.txt" && ok "GPT: Partition 1 ist eine EFI-Partition (EF00)" \
        || bad "keine EFI-Partition in der Tafel"
    n=$(grep -cE '^ +[0-9]+ ' "$TMPD/gpt.txt")
    is "Partitionen in der Tafel" "$n" "2"
else
    bad "sgdisk kann die Tafel nicht lesen"
fi
# Der BIOS-Teil: Limine traegt seinen Namen in den MBR-Bereich ein.
if dd if="$IMG" bs=512 count=4 status=none | grep -qa 'LIMINE'; then
    ok "der BIOS-Startteil von Limine steht im MBR-Bereich"
else
    bad "im MBR-Bereich steht kein Limine"
fi
for f in ::/EFI/BOOT/BOOTX64.EFI ::/limine.conf ::/osum.mb ::/root.img \
         ::/limine-bios.sys; do
    if mdir -i "$IMGDIR/esp.img" "$f" >/dev/null 2>&1; then
        ok "auf der EFI-Partition liegt $f"
    else
        bad "auf der EFI-Partition fehlt $f"
    fi
done

echo "== 3. echte Umlaute in locale/de/messages =="
# Der Fehler, der zurueckkommen soll, wenn ihn jemand rueckgaengig macht:
# in der Datei stand durchgehend ASCII-Umschrift, obwohl ihr eigener
# Kommentar echte Umlaute behauptete.
u=$(grep -cP '[äöüßÄÖÜ]' locale/de/messages)
if [ "${u:-0}" -gt 0 ]; then
    ok "locale/de/messages: $u Zeilen mit echten UTF-8-Umlauten"
else
    bad "locale/de/messages enthaelt keinen einzigen echten Umlaut"
fi
# UND KEINE UMSCHRIFT MEHR IM ANGEZEIGTEN TEXT. Geprueft wird nur RECHTS
# vom Gleichheitszeichen: die Schluessel links sind englisch und bleiben
# es, und ein Kommentar darf schreiben, was er will.
umschrift=$(awk -F' = ' '/^[a-z][a-z0-9._]* = /{print $2}' locale/de/messages \
    | grep -ocP '\b(aendern|Groesse|groesse|fuer|schliessen|Uebernehmen|Aufloesung|laesst|liess|Oeffnen|Loeschen)\b' || true)
is "ASCII-Umschriften im angezeigten deutschen Text" "${umschrift:-0}" "0"
# Und die Oktettrechnung: ein 'ü' sind ZWEI Oktette.
zeichen=$(python3 -c '
import sys
d = open("locale/de/messages", encoding="utf-8").read()
u = sum(d.count(c) for c in "äöüßÄÖÜ")
print("%d %d %d" % (u, len(d), len(d.encode("utf-8"))))
')
set -- $zeichen
if [ "$3" -eq $(( $2 + $1 )) ]; then
    ok "Oktettrechnung stimmt: $1 Umlaute, $2 Zeichen, $3 Oktette ($2 + $1)"
else
    bad "Oktettrechnung: $2 Zeichen, $3 Oktette, $1 Umlaute -- geht nicht auf"
fi

# ------------------------------------------------------------- Laeufe

lauf() { # name zusatzargumente...
    #
    # DER DIAGNOSE-EINTRAG HAELT AN (`hwdiagstop`), also endet der Lauf
    # nicht von selbst. Auf das Zeitlimit zu warten waere bei sechs
    # Laeufen eine Viertelstunde Leerlauf; also wird auf die letzte Zeile
    # des Berichts gewartet und dann abgeschaltet.
    #
    # ================================================ RUNDE TUERSCHLOSS
    # DER DIAGNOSE-EINTRAG WIRD AUSGEWAEHLT UND NICHT MEHR VORAUSGESETZT.
    #
    # Dieser Laeufer startete das Abbild und erwartete den
    # hwdiag-Bericht auf der Leitung -- weil `default_entry` frueher auf
    # die Hardware-Diagnose zeigte. Runde HAENGER hat das aus gutem
    # Grund umgestellt (Commit 4ca1d9e): ein Stick, der nach zwanzig
    # Sekunden von selbst in einen Bericht laeuft, der ABSICHTLICH
    # stehenbleibt, kommt nie bis zum Schreibtisch. Seither zeigt
    # `default_entry: 1` auf den Schreibtisch -- und dieser Laeufer
    # meldete elf Fehlschlaege, die alle denselben Satz sagen:
    # "hwdiag: ... fehlt im Bericht". Gemessen: im Mitschnitt steht
    # stattdessen `desktop: ready w=1280 h=800`. Der Stick tat das
    # Richtige, die Erwartung war alt.
    #
    # Statt `default_entry` zurueckzudrehen (das waere der Fehler, den
    # HAENGER behoben hat) wird der Eintrag jetzt AUSGEWAEHLT: Limine
    # nimmt Pfeiltasten und Eingabe entgegen, und der Diagnose-Eintrag
    # ist der achte. `sendkey` ueber den Monitor ist der Weg, den
    # tools/wm/monitor.py fuer die Tastatur ohnehin geht.
    local name=$1; shift
    local out="$TMPD/$name.txt"
    cp -f "$IMG" "$TMPD/$name.img"
    rm -f "$out"
    local mon="$TMPD/$name.mon"
    rm -f "$mon"
    timeout 200 qemu-system-x86_64 "${KVM[@]}" -m 2048 \
        -drive "file=$TMPD/$name.img,format=raw,if=none,id=stick" \
        "$@" \
        -serial "file:$out" -display none -no-reboot \
        -monitor "unix:$mon,server,nowait" \
        > "$TMPD/$name.qemu" 2>&1 &
    local pid=$!
    # DEN ACHTEN EINTRAG WAEHLEN. Limine malt sein Menue erst, wenn die
    # Firmware durch ist; vorher gehen die Tasten ins Leere. Also wird
    # gewartet, bis der Anschluss da ist, und dann siebenmal nach unten.
    ( local w=0
      while [ $w -lt 100 ] && [ ! -S "$mon" ]; do sleep 0.1; w=$((w+1)); done
      # AUF DAS MENUE WARTEN UND NICHT AUF EINE FRIST. Unter BIOS ist
      # Limine nach gut einer Sekunde da; unter UEFI laeuft erst OVMF
      # (`BdsDxe: loading Boot0001 ...`), und drei Sekunden reichen
      # nicht -- gemessen: die Pfeiltasten gingen ins Leere, der
      # Standardeintrag lief los, und der UEFI-Lauf meldete
      # "erkannte Firmware: ?". Limine loescht beim Zeichnen seines
      # Menues den Schirm; auf der SERIELLEN Leitung steht zu diesem
      # Zeitpunkt noch nichts vom Kern. Also wird gewartet, bis der
      # Kern NOCH NICHT da ist, aber die Firmware fertig -- messbar
      # daran, dass die Datei seit einer Sekunde nicht mehr waechst.
      local vor=-1 jetzt=0 ruhe=0 t=0
      while [ $t -lt 300 ]; do
          jetzt=$(stat -c%s "$out" 2>/dev/null || echo 0)
          if [ "$jetzt" = "$vor" ]; then
              ruhe=$((ruhe+1))
              [ $ruhe -ge 5 ] && break
          else
              ruhe=0
          fi
          vor=$jetzt
          sleep 0.2; t=$((t+1))
      done
      for _ in 1 2 3 4 5 6 7; do
          printf 'sendkey down\n' | timeout 3 socat - "UNIX-CONNECT:$mon" \
              >/dev/null 2>&1
          sleep 0.2
      done
      printf 'sendkey ret\n' | timeout 3 socat - "UNIX-CONNECT:$mon" \
          >/dev/null 2>&1 ) &
    local i=0
    while [ $i -lt 1000 ]; do
        grep -qa 'ENDE DER DIAGNOSE' "$out" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2; i=$((i + 1))
    done
    sleep 0.5
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    return 0
}

# Dasselbe ohne das Abbild: der Kern und sein Modul kommen direkt von
# QEMU. Damit lassen sich Maschinen bauen, die es als STARTBARES Abbild
# nicht gibt -- eine ohne jedes Standardgeraet zum Beispiel.
lauf_direkt() { # name kommandozeile zusatzargumente...
    local name=$1 cmd=$2; shift 2
    local out="$TMPD/$name.txt"
    rm -f "$out"
    timeout 200 qemu-system-x86_64 "${KVM[@]}" -m 512 -nodefaults -device VGA \
        -kernel "$IMGDIR/osum.mb" -append "$cmd" -net none "$@" \
        -serial "file:$out" -display none -no-reboot \
        > "$TMPD/$name.qemu" 2>&1 &
    local pid=$!
    local i=0
    while [ $i -lt 1000 ]; do
        grep -qa 'ENDE DER DIAGNOSE' "$out" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2; i=$((i + 1))
    done
    sleep 0.5
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    return 0
}

warte_auf() { # datei muster sekunden
    local i=0
    while [ $i -lt $(( ${3:-60} * 5 )) ]; do
        grep -qa "$2" "$1" 2>/dev/null && return 0
        sleep 0.2; i=$((i + 1))
    done
    return 1
}

echo "== 4. BIOS: dieselbe Datei, der Weg ueber den MBR =="
lauf bios -device ide-hd,drive=stick
if grep -qa 'firn kernel' "$TMPD/bios.txt"; then
    ok "der Kern startet unter BIOS von dem Abbild"
else
    bad "unter BIOS startet der Kern nicht"
    tail -20 "$TMPD/bios.txt" | sed 's/^/       /'
fi
for m in 'hwdiag: firmware=' 'hwdiag: cpu vendor=' 'hwdiag: pci devices=' \
         'hwdiag: fb '; do
    grep -qa "$m" "$TMPD/bios.txt" && ok "BIOS: der Bericht enthaelt '$m'" \
        || bad "BIOS: '$m' fehlt im Bericht"
done
fw=$(grep -aoE 'firmware=(BIOS|UEFI)' "$TMPD/bios.txt" | head -1 | sed 's/.*=//')
is "BIOS-Lauf: erkannte Firmware" "${fw:-?}" "BIOS"
# ANGEHALTEN heisst ANGEHALTEN: nach dem Bericht darf nichts mehr kommen.
if grep -qa 'ANGEHALTEN' "$TMPD/bios.txt"; then
    ok "der Diagnose-Eintrag haelt an, statt abzuschalten"
else
    bad "der Diagnose-Eintrag haelt nicht an"
fi
if grep -qa 'kernel: done' "$TMPD/bios.txt"; then
    bad "GEGENPROBE: der Lauf lief trotz hwdiagstop bis zum Ende durch"
else
    ok "GEGENPROBE: nach dem Anhalten kommt kein 'kernel: done' mehr"
fi

echo "== 5. UEFI: dieselbe Datei, der Weg ueber BOOTX64.EFI =="
if [ -n "$OVMF_CODE" ]; then
    cp -f "$OVMF_VARS" "$TMPD/vars.fd" 2>/dev/null
    lauf uefi -device ide-hd,drive=stick \
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE" \
        -drive "if=pflash,format=raw,unit=1,file=$TMPD/vars.fd"
    if grep -qa 'firn kernel' "$TMPD/uefi.txt"; then
        ok "derselbe Kern startet unter UEFI (OVMF)"
    else
        bad "unter UEFI startet der Kern nicht"
        tail -25 "$TMPD/uefi.txt" | sed 's/^/       /'
    fi
    grep -qa 'Cannot use text mode with UEFI' "$TMPD/uefi.txt" \
        && bad "der Lader verlangt einen Textmodus -- Bit 2 im Multiboot-Kopf fehlt" \
        || ok "kein 'Cannot use text mode with UEFI' -- der Rahmenpuffer kommt von der Firmware"
    fwu=$(grep -aoE 'firmware=(BIOS|UEFI)' "$TMPD/uefi.txt" | head -1 | sed 's/.*=//')
    is "UEFI-Lauf: erkannte Firmware" "${fwu:-?}" "UEFI"
    src=$(grep -aoE 'hwdiag: fb [0-9]+x[0-9]+' "$TMPD/uefi.txt" | head -1)
    [ -n "$src" ] && ok "UEFI: die Firmware hat einen Rahmenpuffer gesetzt ($src)" \
        || bad "UEFI: kein Rahmenpuffer im Bericht"
else
    bad "OVMF liegt nicht auf diesem Rechner -- der UEFI-Lauf faellt aus"
fi

echo "== 6. Gegenprobe: anderer Plattencontroller, andere Netzkarte =="
lauf ahci -device ahci,id=ahci0 -device ide-hd,bus=ahci0.0,drive=stick \
     -device e1000,netdev=n0 -netdev user,id=n0
if grep -qa 'hwdiag: disk AHCI' "$TMPD/ahci.txt"; then
    ok "mit -device ahci meldet die Diagnose AHCI"
else
    bad "mit -device ahci meldet die Diagnose kein AHCI"
    grep -a 'hwdiag: disk' "$TMPD/ahci.txt" | sed 's/^/       /'
fi
if grep -qa 'hwdiag: disk IDE' "$TMPD/bios.txt"; then
    ok "GEGENPROBE: derselbe Bericht meldete mit -device ide-hd noch IDE"
else
    bad "GEGENPROBE: der IDE-Lauf meldete kein IDE -- die Zeile ist eine Konstante"
fi
if grep -qa 'netdev: c0=e1000' "$TMPD/ahci.txt"; then
    ok "netdev waehlt fuer die Intel-Karte den e1000-Treiber"
else
    bad "netdev nennt den Treiber der Intel-Karte nicht"
    grep -a 'netdev:' "$TMPD/ahci.txt" | sed 's/^/       /'
fi

lauf virtio -device ide-hd,drive=stick \
     -device virtio-net-pci,netdev=n0 -netdev user,id=n0
if grep -qa 'netdev: c0=virtio-net' "$TMPD/virtio.txt"; then
    ok "und fuer die virtio-Karte den virtio-Treiber -- zwei Karten, zwei Antworten"
else
    bad "netdev nennt fuer virtio nicht virtio-net"
    grep -a 'netdev:' "$TMPD/virtio.txt" | sed 's/^/       /'
fi
# UND EINE KARTE, DIE DIESER KERN NICHT KANN. Ohne diesen Lauf waere die
# Zeile "no driver for" nie gemessen worden -- und genau sie ist die
# Zeile, an der Justin ablesen soll, welchen Treiber er braucht.
#
# RUNDE BLECH, NACHTRAG: HIER STAND `-device rtl8139`, UND DAS IST SEIT
# DEM MERGE DES ZWEIGS `rtl` KEINE FREMDE KARTE MEHR. QEMUs rtl8139
# meldet PCI-Revision 0x20, also den C+-Modus -- und genau den faehrt
# `kernel/r8169.fi` seit Runde RTL, er ist dort sogar der EINZIGE in QEMU
# gemessene Zweig. Die Zusage hat danach nicht mehr geprueft, was sie
# pruefen wollte: sie verlangte "kein Treiber" von einer Karte, fuer die
# es inzwischen einen gibt.
#
# Das ist kein Fehler dieser Runde, sondern eine Altlast des Merges
# (Commit "BLECH 16/n"): die volle Abnahme um 12:59 lief noch VOR ihm und
# war deshalb gruen. Sie faellt seitdem -- gesehen hat es niemand, weil
# usbimg zwischen dem Merge und jetzt nicht mehr einzeln lief.
#
# Genommen wird jetzt `ne2k_pci` (10EC:8029): derselbe Hersteller wie der
# gefahrene Realtek, aber ein Chip ohne Ringe, den dieser Kern nicht
# faehrt und nie fahren wird. Damit prueft die Zusage wieder ihre Absicht
# -- und sie prueft zusaetzlich, dass die Zeile den KLARNAMEN traegt.
lauf fremd -device ide-hd,drive=stick \
     -device ne2k_pci,netdev=n0 -netdev user,id=n0
if grep -qa 'netdev: no driver for' "$TMPD/fremd.txt"; then
    ok "eine fremde Karte (ne2k_pci) wird als 'no driver for' gemeldet: $(grep -ao 'no driver for.*' "$TMPD/fremd.txt" | head -1)"
else
    bad "eine fremde Karte wird nicht als 'no driver for' gemeldet"
    grep -a 'netdev:' "$TMPD/fremd.txt" | sed 's/^/       /'
fi
if grep -qa 'RTL8029 (ne2000)' "$TMPD/fremd.txt"; then
    ok "und sie wird beim NAMEN genannt, nicht nur bei der Nummer"
else
    bad "die fremde Karte wird nicht beim Namen genannt"
fi
# GEGENPROBE ZUR ZUSAGE SELBST: derselbe Lauf mit rtl8139 muss das
# GEGENTEIL zeigen -- eine Karte, die dieser Kern SEHR WOHL faehrt. Ohne
# sie stuende hier wieder eine Zusage, die nur zufaellig gruen ist.
lauf gefahren -device ide-hd,drive=stick \
     -device rtl8139,netdev=n0 -netdev user,id=n0
if grep -qa 'netdev: c0=r8169' "$TMPD/gefahren.txt"; then
    ok "GEGENPROBE: derselbe rtl8139 wird als r8169 GEFAHREN, ist also keine fremde Karte mehr"
else
    bad "GEGENPROBE: der rtl8139 wird nicht als r8169 gefahren"
    grep -a 'netdev:' "$TMPD/gefahren.txt" | sed 's/^/       /'
fi
# UND DER KERN LAEUFT TROTZDEM WEITER. Punkt 5 der Runde.
if grep -qa 'ANGEHALTEN' "$TMPD/fremd.txt"; then
    ok "und der Kern laeuft nach der unbekannten Karte bis zum Ende des Berichts"
else
    bad "der Kern kommt nach der unbekannten Karte nicht mehr bis zum Ende"
fi

echo "== 7. keine Platte, keine Karte -- und trotzdem ein Bericht =="
#
# PUNKT 5 DER RUNDE: findet der Kern nichts, darf er nicht still haengen,
# sondern muss es BENENNEN und weiterlaufen.
#
# UND HIER STEHT EINE EHRLICHE EINSCHRAENKUNG. Eine x86-Maschine OHNE
# Plattencontroller laesst sich mit QEMU nicht bauen: der PIIX3 der
# `pc`-Maschine und der ICH9-AHCI der `q35`-Maschine gehoeren zum
# Chipsatz und sind auch mit `-nodefaults` da (nachgemessen: `pc` meldet
# `disk IDE 8086:7010`, `q35` meldet `disk AHCI 8086:2922`). `isapc` hat
# gar keinen PCI-Bus, startet diesen Kern aber nicht.
#
# Also wird die Lage auf dem einzigen Weg hergestellt, auf dem sie
# herstellbar ist: mit `nopci`, dem Gegenprobenwort, das `kernel/hw.fi`
# seit Runde K2 dafuer hat. Der Bus wird dann gar nicht erst gelesen,
# die Geraetetabelle bleibt leer, und genau das ist die Lage, in der ein
# echter Rechner mit einem Controller, den dieser Kern nicht findet,
# ebenfalls landet.
lauf_direkt leer "hwdiag hwdiagstop gfx nopci nokbd nosched noproc nofs noring3"
if grep -qa 'hwdiag: pci=KEIN GERÄT' "$TMPD/leer.txt"; then
    ok "ohne Bus sagt der Bericht das, statt still zu haengen"
else
    bad "ohne Bus fehlt die Meldung"
    grep -a 'hwdiag: pci' "$TMPD/leer.txt" | sed 's/^/       /' | head -3
fi
if grep -qa 'hwdiag: disk=KEINER' "$TMPD/leer.txt"; then
    ok "und ohne Plattencontroller ebenso"
else
    bad "ohne Plattencontroller fehlt die Meldung"
    grep -a 'hwdiag: disk' "$TMPD/leer.txt" | sed 's/^/       /'
fi
if grep -qa 'hwdiag: net=KEINE KARTE' "$TMPD/leer.txt"; then
    ok "und ohne Netzkarte auch"
else
    bad "ohne Netzkarte fehlt die Meldung"
    grep -a 'hwdiag: net' "$TMPD/leer.txt" | sed 's/^/       /'
fi
if grep -qa 'ANGEHALTEN' "$TMPD/leer.txt"; then
    ok "und der Bericht ist trotzdem vollstaendig"
else
    bad "der Bericht bricht ab, wenn nichts gefunden wird"
fi
# GEGENPROBE ZUR GEGENPROBE: dieselbe Maschine MIT Bus meldet sehr wohl
# etwas. Ohne diese Zeile waere oben nur bewiesen, dass der Bericht
# immer dasselbe sagt.
lauf_direkt mitbus "hwdiag hwdiagstop gfx nokbd nosched noproc nofs noring3"
if grep -qa 'hwdiag: disk IDE' "$TMPD/mitbus.txt"; then
    ok "GEGENPROBE: dieselbe Maschine MIT Bus meldet ihren IDE-Controller"
else
    bad "GEGENPROBE: die Maschine mit Bus meldet keinen Controller"
    grep -a 'hwdiag: disk' "$TMPD/mitbus.txt" | sed 's/^/       /'
fi
# UND OHNE NETZKARTE, ABER MIT BUS -- die Lage eines Rechners, dessen
# Netzteil auf dem Mainboard sitzt und den dieser Kern nicht kennt.
if grep -qa 'hwdiag: net=KEINE KARTE' "$TMPD/mitbus.txt"; then
    ok "und ohne Netzkarte (aber mit Bus) sagt sie auch das"
else
    bad "die Maschine ohne Netzkarte meldet das nicht"
fi

echo "== 8. der Schreibtisch, auf deutsch, mit Umlauten im BILD =="
#
# WAS HIER GEMESSEN WIRD UND WAS NICHT.
#
# NICHT gemessen wird, ob der Rasterer Umlaute kann -- das hat Runde
# I18N bildpunktgenau erledigt. Gemessen wird, ob DIESES ABBILD seine
# Sprachdateien mitbringt UND BENUTZT. Der Unterschied ist genau der
# Fehler der letzten Runde: die Oberflaeche fiel auf englische
# Ersatztexte zurueck, weil /usr/share/locale/de/messages nicht im
# Abbild lag.
#
# Der Weg: Kern und Wurzelmodul wie auf dem Stick, dann von aussen
# Super+A -- das oeffnet den Starter. Auf ihm steht "Ausfuehren", und
# zwar mit ue-Ligatur: `Ausführen`. Dieses eine Wort traegt beide
# Zusagen auf einmal, die deutsche Sprache und den echten Umlaut.
#
# `tools/usbimg/searchtext.py` sucht die Zeile im GANZEN Bild -- gerastert
# mit `tools/ttf/raster.py`, der zweiten Fassung des Rasterers. Es wird
# also nicht gegen sich selbst geprueft.
# RUNDE ABBILD: `lang=de` GEHOERT AUF DIE ZEILE, WEIL DAS ABBILD
# ENGLISCH AUSLIEFERT.
#
# Dieser Abschnitt misst den DEUTSCHEN Katalog: `Suchen`, `Ausfuehren`
# mit echtem Umlaut, `Programm suchen:`, `kein Netz`. Bis zum 09.09.2026
# kam der Stick deutsch hoch, also stimmte das ohne Zutun. Seitdem ist
# Englisch die Hauptsprache der Oberflaeche und Deutsch die waehlbare
# Uebersetzung (die Begruendung steht in tools/usbimg/build.sh bei
# `locale-de`) -- der Bau schreibt `en` in /users/root/config/locale.
#
# Der Abschnitt hat das nicht mitbekommen und ist seitdem rot: er
# verlangte deutschen Text von einem System, das er englisch startet.
# GEMESSEN: `taskbar: lang=en src=1` -- src=1 ist genau diese
# Benutzerdatei.
#
# `lang=de` auf der Kernel-Kommandozeile ist die vorgesehene Antwort:
# `kgui.locale_set` schreibt damit `de` in dieselbe Datei, bevor die
# Oberflaeche startet, und setzt die Tastaturbelegung gleich mit. Damit
# misst dieser Abschnitt wieder, was er messen will -- dass der deutsche
# Katalog im Abbild liegt und wirkt --, ohne die Auslieferungssprache zu
# behaupten.
DESKARGS="modfs osum gfx wm wig desk wmhold wiglong nokbd nosched noproc nofs lang=de"
rm -f "$TMPD/desk.txt" "$TMPD/desk.ppm" "$TMPD/desk.sock"
printf 'warte 5\nsendkey a\nwarte 2\nsendkey meta_l-a\nwarte 3\n' > "$TMPD/drive"
timeout 240 qemu-system-x86_64 "${KVM[@]}" -m 512 \
    -kernel "$IMGDIR/osum.mb" -initrd "$IMGDIR/root.img" \
    -append "$DESKARGS" \
    -serial "file:$TMPD/desk.txt" -display none -no-reboot -vga std \
    -monitor "unix:$TMPD/desk.sock,server,nowait" \
    > "$TMPD/desk.qemu" 2>&1 &
qpid=$!
warte_auf "$TMPD/desk.txt" '^wm: hold' 120
python3 tools/wm/monitor.py "$TMPD/desk.sock" "$TMPD/drive" 0.12 \
    > "$TMPD/mon.log" 2>&1
sleep 2
python3 tools/gfx/screenshot.py "$TMPD/desk.sock" "$TMPD/desk.ppm" 30 \
    > "$TMPD/shot.txt" 2>&1
kill "$qpid" 2>/dev/null; wait "$qpid" 2>/dev/null

if grep -qa 'osum: from module' "$TMPD/desk.txt"; then
    ok "die Wurzel kommt aus dem Boot-Modul -- kein Plattentreiber noetig"
else
    bad "die Wurzel kommt nicht aus dem Modul"
    grep -a 'osum:' "$TMPD/desk.txt" | sed 's/^/       /' | head -5
fi
if grep -qa 'glyphs=' "$TMPD/desk.txt"; then
    ok "die Schriften kommen aus dem Abbild: $(grep -aoE 'glyphs=[0-9]+' "$TMPD/desk.txt" | head -1)"
else
    bad "keine Schrift geladen"
fi
# DER MITSCHNITT SAGT ES SCHON: der Starter meldet seinen eigenen Namen,
# und der kommt aus dem Katalog.
if grep -qa 'launcher: name \[Suchen\]' "$TMPD/desk.txt"; then
    ok "der Starter nennt sich 'Suchen' -- deutsch, aus /usr/share/locale/de"
else
    bad "der Starter ist nicht deutsch: $(grep -a 'launcher: name' "$TMPD/desk.txt" | tail -1)"
fi

if [ -s "$TMPD/desk.ppm" ]; then
    ok "ein Bildschirmfoto ist entstanden ($(stat -c%s "$TMPD/desk.ppm") Oktette)"
    finde() { # was text [--nicht]
        local was=$1 text=$2; shift 2
        local aus rc
        aus=$(python3 tools/usbimg/searchtext.py "$TMPD/desk.ppm" \
              fui:assets/osum-sans.ttf 15 "$text" "$@" 2>&1)
        rc=$?
        if [ $rc = 0 ]; then ok "$was: $aus"; else bad "$was: $aus"; fi
    }
    finde "DER UMLAUT STEHT IM BILD" "Ausführen"
    finde "GEGENPROBE: die ASCII-Ersatzschreibung steht NICHT da" \
          "Ausfuehren" --nicht
    finde "GEGENPROBE: und der englische Text auch nicht" "Run" --nicht
    finde "der deutsche Aufforderungstext des Starters" "Programm suchen:"
    finde "und die Taskleiste ist ebenfalls deutsch" "kein Netz"
    python3 -c "
from PIL import Image
Image.open('$TMPD/desk.ppm').save('$TMPD/desk.png')
" 2>/dev/null && ok "und liegt als $TMPD/desk.png"
else
    bad "kein Bildschirmfoto"
    tail -10 "$TMPD/shot.txt" | sed 's/^/       /'
fi

echo
echo "USBIMG: $pass bestanden, $fail gescheitert"
echo "        Abbild:     $IMG"
echo "        Foto:       $TMPD/desk.png"
[ "$fail" = 0 ]
