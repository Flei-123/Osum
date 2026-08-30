#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hid/run.sh -- DER BEWEIS, DASS OSUM EIN HID-GERAET LESEN KANN.
#
# Bis zu dieser Runde konnte Osum zwei HID-Geraete: eine Tastatur und
# eine Maus, beide im BOOT-PROTOKOLL -- einer Abmachung aus der Zeit, als
# ein BIOS eine USB-Tastatur bedienen koennen musste, ohne einen Zerleger
# zu haben.  Alles andere ging nicht: keine Tastatur mit mehr als sechs
# gleichzeitigen Tasten, keine Maus mit mehr als drei Knoepfen an der
# richtigen Stelle, kein Touchpad, und auf einem gewoehnlichen Laptop von
# 2026, wo Tastatur und Touchpad an I2C haengen, GAR KEINE EINGABE.
#
# WAS HIER GEMESSEN WIRD, UND WARUM SO:
#
#  1. DER ZERLEGER GEGEN EINEN ZWEITEN ZERLEGER.  Ein Test, in dem
#     dieselbe Person zuerst den Zerleger schreibt und dann hinschreibt,
#     was herauskommen soll, misst nur, ob sie sich zweimal gleich
#     geirrt hat.  Deshalb steht in `tools/hid/descs.py` eine ZWEITE
#     Umsetzung, in einer anderen Sprache, aus der Spezifikation heraus,
#     und hier werden beide ZEILE FUER ZEILE gegeneinander gehalten --
#     zwanzig Kopfzeilen und jedes einzelne Feld mit Bitlage, Groesse,
#     Anzahl, Gebrauchsseite, Gebrauch und Wertebereich.
#     Sechs ECHTE Beschreibungen: die Boot-Tastatur und die Boot-Maus
#     woertlich aus HID 1.11 Anhang B, eine Radmaus mit Berichtsnummer,
#     ein Praezisions-Touchpad in der von Microsoft vorgeschriebenen
#     Bauform, eine Verbrauchersteuerung und eine Tastatur ohne
#     Anschlagsgrenze.
#
#  2. VIERZEHN KAPUTTE BESCHREIBUNGEN.  Eine Beschreibung kommt von
#     einem Geraet, das jemand angesteckt hat -- sie ist Eingabe von
#     aussen.  Abgeschnitten, Sammlung nie geschlossen, Sammlungsende
#     ohne Sammlung, Holen ohne Ablegen, Berichtsgroesse 255,
#     Berichtsnummer 0, ein Bericht ueber 4096 Bit, ein langer Posten,
#     leer, zu viele Felder, zu viele Nummern, zu viele Gebraeuche, neun
#     Sammlungen tief.  Jede MUSS mit GENAU EINER Fehlernummer an GENAU
#     EINER Stelle scheitern, und der Kern MUSS weiterlaufen.
#
#  3. BERICHTE DURCH DENSELBEN WEG, DEN EIN ECHTES GERAET NIMMT.  Ein
#     Zerleger, der richtig zerlegt, ist noch keine Eingabe.  Also gehen
#     echte Berichte durch `hidin.report`, und jedes Ereignis wird
#     mitgeschrieben.  Darunter der Fall, den das Boot-Protokoll NICHT
#     kann: acht Tasten aus EINEM Bericht, dann elf gleichzeitig.
#
#  4. DIE SUPER-TASTE, ALS REGRESSION.  In `kbd.fi` steht seit Runde
#     NETVIEW: "A hotkey has no window -- that is what makes it global."
#     Super+A wird GELATCHT und NICHT ins Fenster geliefert, sonst
#     stuende bei jedem Oeffnen der Schnelleinstellungen ein `a` im
#     Dokument.  Der neue Weg MUSS dieselben Abtastcodes erzeugen
#     (0xE0 0x5B) und darf KEIN Zeichen mehr liefern als vorher.
#
#  5. QEMU MIT ECHTEN GERAETEN.  `-device usb-kbd`, `-device usb-mouse`
#     und `-device usb-tablet`.  Das letzte ist neu: es hat KEIN
#     Boot-Protokoll (Klasse 03:00:00) und wurde bis zu dieser Runde
#     ABGELEHNT.  Und dazu die Gegenprobe `nurboot`, mit der alles
#     wieder laeuft wie vorher.
#
#  6. I2C-HID, SO WEIT ES GEHT, UND EHRLICH GETRENNT.  QEMU hat keinen
#     Designware-Regler (`-device help` kennt nur `i2c-ddc` und
#     `smbus-ipmi`).  Gemessen wird deshalb: der ACPI-Ersatzweg an einer
#     Tabelle, in der GENAU BEKANNT ist, was drinsteht (zwei
#     I2C-Verbindungen und drei Koeder, die wie eine aussehen), UND an
#     der ECHTEN Firmware, die QEMU stellt -- dort MUSS er null finden,
#     denn dort ist nichts.  Der Rest steht in docs/REALHW.md als "nur
#     aus der Spezifikation".
#
#  7. DIE LATENZ.  Wie lange ein Tastendruck vom Bericht bis in die
#     Zeilendisziplin braucht, in Mikrosekunden, gegen den PS/2-Weg.
#
# Gemessen wie in den Runden 59 bis MERGE-2: QEMU je Fall, mit
# Zeitlimit, serielle Ausgabe gegen Erwartungen, Beendigungscode aus
# `isa-debug-exit` (21 = der Kernel hat sich selbst beendet).
#
# Aufruf:  bash tools/hid/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

OK=0
FAIL=0
zusage() { # name bedingung-als-text ergebnis(0=gut)
    if [ "$2" -eq 0 ]; then
        OK=$((OK+1)); printf '  ok    %s\n' "$1"
    else
        FAIL=$((FAIL+1)); printf '  FALL  %s\n' "$1"
    fi
}
gleich() { # name erwartet bekommen
    if [ "$2" = "$3" ]; then
        OK=$((OK+1)); printf '  ok    %s (%s)\n' "$1" "$3"
    else
        FAIL=$((FAIL+1)); printf '  FALL  %s: erwartet <%s>, bekommen <%s>\n' \
            "$1" "$2" "$3"
    fi
}

echo "== 0a. kein Moduswort steckt neu in einem anderen"
python3 tools/hid/worte.py kernel
zusage "die Moduswoerter des ganzen Baums sind eindeutig" $?

echo "== 0. der Kern wird gebaut"
./tools/build-kernel.sh "$TMPD/osum.mb" > /dev/null || { echo "Bau fehlgeschlagen"; exit 1; }
IMG="$TMPD/osum.mb"

lauf() { # name kommandozeile [qemu-args...]
    local name=$1 app=$2
    shift 2
    timeout 60 $QEMU_X86 -kernel "$IMG" -m 256 -append "$app" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        "$@" -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    echo $?
}

# ----------------------------------------------------------------------
echo
echo "== 1. der Zerleger gegen den zweiten Zerleger"
RC=$(lauf zerleger "hidrep nokbd noring3 nofs")
zusage "der Lauf endet sauber (Code 21, bekommen $RC)" \
    "$([ "$RC" = 21 ] && echo 0 || echo 1)"

grep -a '^hidrep: dev=' "$TMPD/zerleger.txt" > "$TMPD/k-kopf.txt"
python3 tools/hid/descs.py kopf > "$TMPD/p-kopf.txt"
grep -a '^hidf:' "$TMPD/zerleger.txt" > "$TMPD/k-feld.txt"
python3 tools/hid/descs.py felder > "$TMPD/p-feld.txt"

# DIE LEHRE AUS B3 (Runde K17): EIN VERGLEICH ZWEIER LEERER SEITEN IST
# KEIN TEST. Vor jedem Vergleich wird geprueft, dass beide Seiten voll
# sind.
NK=$(wc -l < "$TMPD/k-kopf.txt"); NP=$(wc -l < "$TMPD/p-kopf.txt")
NKF=$(wc -l < "$TMPD/k-feld.txt"); NPF=$(wc -l < "$TMPD/p-feld.txt")
zusage "der Kern hat ueberhaupt Kopfzeilen gedruckt ($NK)" \
    "$([ "$NK" -ge 20 ] && echo 0 || echo 1)"
zusage "der Kern hat ueberhaupt Feldzeilen gedruckt ($NKF)" \
    "$([ "$NKF" -ge 40 ] && echo 0 || echo 1)"
gleich "gleich viele Kopfzeilen" "$NP" "$NK"
gleich "gleich viele Feldzeilen" "$NPF" "$NKF"
diff -q "$TMPD/p-kopf.txt" "$TMPD/k-kopf.txt" > /dev/null 2>&1
zusage "JEDE Kopfzeile stimmt mit dem zweiten Zerleger ueberein" $?
diff -q "$TMPD/p-feld.txt" "$TMPD/k-feld.txt" > /dev/null 2>&1
zusage "JEDES Feld stimmt mit dem zweiten Zerleger ueberein" $?
if ! diff -q "$TMPD/p-kopf.txt" "$TMPD/k-kopf.txt" > /dev/null 2>&1; then
    diff "$TMPD/p-kopf.txt" "$TMPD/k-kopf.txt" | head -10
fi
if ! diff -q "$TMPD/p-feld.txt" "$TMPD/k-feld.txt" > /dev/null 2>&1; then
    diff "$TMPD/p-feld.txt" "$TMPD/k-feld.txt" | head -10
fi

# ----------------------------------------------------------------------
echo
echo "== 2. die vierzehn kaputten Beschreibungen"
# Der Referenzzerleger prueft SICH SELBST gegen die Erwartung, die
# neben jeder kaputten Beschreibung steht; der Kern wurde oben schon
# Zeile fuer Zeile dagegen gehalten. Bleibt die Frage, ob er dabei
# stehengeblieben ist -- die beantwortet der Beendigungscode.
python3 tools/hid/descs.py fehler > "$TMPD/fehler.txt" 2>&1
zusage "jede kaputte Beschreibung gibt ihre eigene Fehlernummer" $?
sed 's/^/    /' "$TMPD/fehler.txt"
KAP=$(grep -ac '^hidrep: .* ok=0 ' "$TMPD/zerleger.txt")
gleich "vierzehn Beschreibungen fallen durch" "14" "$KAP"
GUT=$(grep -ac '^hidrep: .* ok=1 ' "$TMPD/zerleger.txt")
gleich "sechs gehen durch" "6" "$GUT"
grep -aq 'kernel: done' "$TMPD/zerleger.txt"
zusage "der Kern laeuft nach allen vierzehn weiter" $?

# ----------------------------------------------------------------------
echo
echo "== 3. Berichte durch denselben Weg, den ein Geraet nimmt"
RC=$(lauf berichte "hidpad nokbd noring3 nofs")
zusage "der Lauf endet sauber (Code 21, bekommen $RC)" \
    "$([ "$RC" = 21 ] && echo 0 || echo 1)"
B="$TMPD/berichte.txt"

# (c) MEHR ALS SECHS TASTEN GLEICHZEITIG.
# Bericht 0 der NKRO-Tastatur traegt die Gebraeuche 4..11 -- acht Stueck
# in EINEM Bericht. Im Boot-Protokoll gibt es dafuer sechs Plaetze.
ACHT=$(sed -n '/^hidb: nr=0 /q;p' "$B" | grep -ac '^hidev: druck ')
gleich "acht Tasten aus EINEM Bericht" "8" "$ACHT"
for u in 0x4 0x5 0x6 0x7 0x8 0x9 0xa 0xb; do
    grep -aq "^hidev: druck $u " "$B" || { FAIL=$((FAIL+1)); echo "  FALL  Taste $u fehlt"; }
done
OK=$((OK+1)); echo "  ok    alle acht Gebraeuche 0x4..0xb sind einzeln da"
# Bericht 1 legt zwei weitere und Umschalt dazu: elf gleichzeitig.
grep -aq '^hidev: druck 0xe1 code=0x2a' "$B"
zusage "Umschalt kommt als eigener Abtastcode 0x2a" $?
ZEICHEN=$(grep -ao 'key: .' "$B" | sed 's/key: //' | tr -d '\n')
gleich "die Zeichen, die in der Zeilendisziplin ankommen" "abcdefghija" "$ZEICHEN"
LOS=$(grep -ac '^hidev: los ' "$B")
zusage "es gibt ueberhaupt ein Loslassen ($LOS Ereignisse)" \
    "$([ "$LOS" -ge 14 ] && echo 0 || echo 1)"

# (d) DIE SUPER-TASTE, REGRESSION.
gleich "Super wird zu 0xE0 0x5B, wie kbd.fi es seit NETVIEW kennt" \
    "hidev: druck 0xe3 code=0x5b" \
    "$(grep -am1 '^hidev: druck 0xe3' "$B")"
HK=$(grep -ac '^hk: super+a' "$B")
gleich "Super+A wird GELATCHT (genau eine hk-Zeile)" "1" "$HK"
# UND DIE ANDERE HAELFTE, die die eigentliche Zusage ist: das `a` unter
# Super darf NICHT als Zeichen im Fenster landen. Es wurden elf
# Buchstaben getippt; waere es geliefert worden, waeren es zwoelf.
AS=$(grep -ao 'key: a' "$B" | wc -l)
gleich "das a unter Super gibt KEIN zusaetzliches Zeichen" "2" "$AS"

# Die Maus: HID zaehlt y nach unten, PS/2 nach oben.
gleich "Boot-Maus: dy=-6 wird zu PS/2 +6" "hidev: maus 0x1 x=0xa y=0x6 r=0x0" \
    "$(grep -am1 '^hidev: maus 0x1 x=0xa' "$B")"

# ----------------------------------------------------------------------
echo
echo "== 4. das Praezisions-Touchpad"
# NACHGERECHNET, nicht geschaetzt: das Touchpad ist 3616 Einheiten breit
# und 2184 hoch (steht im logischen Maximum seiner Achsen), der Schirm
# 1024x768. Teiler 3616/1024 = 3 und 2184/768 = 2.
#   +300 Einheiten in x  ->  300/3 = 100 = 0x64 Bildpunkte
#   +150 Einheiten in y  ->  150/2 =  75 Bildpunkte, und weil PS/2 y
#                            nach oben zaehlt: 256-75 = 181 = 0xb5
# DIE NUMMERN WERDEN GEHOLT UND NICHT HINGESCHRIEBEN.  Als in dieser
# Runde zwei Berichte fuer die Super-Taste dazukamen, verschoben sich
# alle folgenden, und drei Zusagen fielen, obwohl am Kernel nichts
# falsch war.  Ein Test, der bei jeder Erweiterung von Hand nachgezogen
# werden muss, wird irgendwann nicht nachgezogen.
NAUF=$(python3 tools/hid/descs.py nr "pad: aufsetzen")
NX=$(python3 tools/hid/descs.py nr "pad: +300x -> +100px")
gleich "erster Bericht: aufgesetzt, aber NICHT gesprungen" \
    "hidb: nr=$NAUF desc=3 ok=1" "$(grep -a "^hidb: nr=$NAUF " "$B")"
# Die Ereignisse stehen VOR ihrer `hidb`-Zeile (der Bericht wird erst
# ausgewertet, dann gemeldet). Was zum Bericht NAUF gehoert, liegt also
# zwischen der Zeile davor und seiner eigenen.
VOR=$((NAUF-1))
ZW=$(sed -n "/^hidb: nr=$VOR /,/^hidb: nr=$NAUF /p" "$B" | grep -ac '^hidev: maus')
gleich "beim Aufsetzen wird kein Paket erzeugt" "0" "$ZW"
gleich "+300 Geraeteeinheiten in x werden 100 Bildpunkte" \
    "hidev: maus 0x0 x=0x64 y=0x0 r=0x0" \
    "$(sed -n "/^hidb: nr=$NX /q;p" "$B" | grep -a '^hidev: maus' | tail -1)"
grep -aq '^hidev: maus 0x0 x=0x0 y=0xb5 r=0x0' "$B"
zusage "+150 in y werden 75 Bildpunkte, Vorzeichen gedreht (0xb5)" $?
grep -aq '^hidev: maus 0x1 x=0x0 y=0x0 r=0x0' "$B"
zusage "der Knopf des Touchpads kommt als Linksklick" $?
grep -aq '^hidev: maus 0x0 x=0x0 y=0x0 r=0x1' "$B"
zusage "zwei Finger, 120 Einheiten: genau EINE Radrastung" $?
ROLL=$(grep -a 'hidin: ta=' "$B" | sed 's/.*rollen=\([0-9]*\).*/\1/')
gleich "und nur eine" "1" "$ROLL"
UEBER=$(grep -a 'hidin: ta=' "$B" | sed 's/.*ueber=\([0-9]*\).*/\1/')
gleich "der Ueberlaufbericht (sechs mal 0x01) wird erkannt" "1" "$UEBER"
WEG=$(grep -a 'hidin: ta=' "$B" | sed 's/.*weg=\([0-9]*\).*/\1/')
gleich "kein Bericht ging verloren" "0" "$WEG"

# ----------------------------------------------------------------------
echo
echo "== 5. QEMU mit echten Geraeten"
XHCI="-device qemu-xhci"
RC=$(lauf gkbd "usb hidgen nofs noring3" $XHCI -device usb-kbd)
zusage "usb-kbd: Lauf endet sauber ($RC)" \
    "$([ "$RC" = 21 ] && echo 0 || echo 1)"
gleich "usb-kbd: die Beschreibung wird geholt und zerlegt" "1" \
    "$(grep -ac '^hidrep: dev=0 ok=1' "$TMPD/gkbd.txt")"
gleich "usb-kbd: sie ist 63 Oktett lang -- die aus HID 1.11 Anhang B.1" \
    "63" "$(grep -a '^hid: gen=' "$TMPD/gkbd.txt" | sed 's/.*rdlen=\([0-9]*\).*/\1/')"
gleich "usb-kbd: laeuft ueber den generischen Weg" "1" \
    "$(grep -a '^hid: gen=' "$TMPD/gkbd.txt" | sed 's/hid: gen=\([0-9]*\).*/\1/')"
gleich "usb-kbd: erkannt als Tastatur (art=1)" "1" \
    "$(grep -a '^hidrep: dev=0' "$TMPD/gkbd.txt" | sed 's/.* art=\([0-9]*\).*/\1/')"

RC=$(lauf gmaus "usb hidgen nofs noring3" $XHCI -device usb-mouse)
zusage "usb-mouse: Lauf endet sauber ($RC)" \
    "$([ "$RC" = 21 ] && echo 0 || echo 1)"
gleich "usb-mouse: erkannt als Maus (art=2)" "2" \
    "$(grep -a '^hidrep: dev=0' "$TMPD/gmaus.txt" | sed 's/.* art=\([0-9]*\).*/\1/')"

# DAS IST DER NEUE FALL. `usb-tablet` meldet Klasse 03:00:00 -- HID OHNE
# Boot-Protokoll. `wanted` in usb.fi hat es bis zu dieser Runde
# ausdruecklich ABGELEHNT ("ihr Berichtsformat steht in einer
# Berichtsbeschreibung, und die zerlegt diese Runde nicht").
RC=$(lauf gtab "usb hidgen nofs noring3" $XHCI -device usb-tablet)
zusage "usb-tablet: Lauf endet sauber ($RC)" \
    "$([ "$RC" = 21 ] && echo 0 || echo 1)"
grep -aq 'class=03:00:00' "$TMPD/gtab.txt"
zusage "usb-tablet: hat KEIN Boot-Protokoll (Klasse 03:00:00)" $?
gleich "usb-tablet: wird trotzdem angenommen und zerlegt" "1" \
    "$(grep -ac '^hidrep: dev=0 ok=1' "$TMPD/gtab.txt")"
gleich "usb-tablet: haengt am Zeiger" "1" \
    "$(grep -a '^usb: devices=' "$TMPD/gtab.txt" | sed 's/.*mouse=\([0-9]*\).*/\1/')"

# DIE GEGENPROBE. Mit `nurboot` laeuft alles wie vor dieser Runde --
# und dann wird usb-tablet wieder abgelehnt. Ein Schalter, der nichts
# aendert, ist keiner.
RC=$(lauf gtabaus "usb nurboot nofs noring3" $XHCI -device usb-tablet)
gleich "GEGENPROBE nurboot: usb-tablet wird wieder abgelehnt" "0" \
    "$(grep -a '^usb: devices=' "$TMPD/gtabaus.txt" | sed 's/.*mouse=\([0-9]*\).*/\1/')"
gleich "GEGENPROBE nurboot: kein Geraet ueber den Zerleger" "0" \
    "$(grep -a '^hid: gen=' "$TMPD/gtabaus.txt" | sed 's/hid: gen=\([0-9]*\).*/\1/')"
RC=$(lauf gkbdaus "usb nurboot nofs noring3" $XHCI -device usb-kbd)
gleich "GEGENPROBE nurboot: usb-kbd laeuft weiter (Boot-Protokoll)" "1" \
    "$(grep -a '^usb: devices=' "$TMPD/gkbdaus.txt" | sed 's/.*kbd=\([0-9]*\).*/\1/')"

# ----------------------------------------------------------------------
echo
echo "== 6. I2C-HID, so weit es in QEMU geht"
RC=$(lauf i2ctest "hiddump nokbd noring3 nofs")
zusage "der Lauf endet sauber ($RC)" \
    "$([ "$RC" = 21 ] && echo 0 || echo 1)"
ERW_LEN=$(python3 -c "
import sys; sys.path.insert(0,'tools/hid'); import descs
print(len(descs.ACPI_BLOB))")
ERW_ADR=$(python3 -c "
import sys; sys.path.insert(0,'tools/hid'); import descs
print(' '.join('i2ctest: adr=%s' % hex(a) for a in descs.I2C_ADRESSEN))")
Z=$(grep -a '^i2ctest: laenge=' "$TMPD/i2ctest.txt")
gleich "die gebaute Tabelle kommt vollstaendig an" \
    "$ERW_LEN" "$(echo "$Z" | sed 's/i2ctest: laenge=\([0-9]*\).*/\1/')"
gleich "GENAU zwei I2C-Verbindungen -- die drei Koeder fallen weg" "2" \
    "$(echo "$Z" | sed 's/.*treffer=\([0-9]*\).*/\1/')"
gleich "und die Adressen sind die, die drinstehen" "$ERW_ADR" \
    "$(grep -a '^i2ctest: adr=' "$TMPD/i2ctest.txt" | tr '\n' ' ' | sed 's/ $//')"
gleich "die Kennung PNP0C50 wird gefunden" "1" \
    "$(echo "$Z" | sed 's/.*pnp0c50=\([0-9]*\).*/\1/')"
gleich "der Zerleger der HID-ueber-I2C-Beschreibung: 6 von 6" "6" \
    "$(echo "$Z" | sed 's/.*prueb=\([0-9]*\).*/\1/')"

# UND AN DER ECHTEN FIRMWARE. QEMU hat keinen I2C-HID -- der Sucher MUSS
# dort null finden. Ein Sucher, der ueberall etwas findet, findet nichts.
RC=$(lauf i2creal "i2chid nokbd nofs noring3")
zusage "gegen die ECHTEN ACPI-Tabellen: Lauf endet sauber ($RC)" \
    "$([ "$RC" = 21 ] && echo 0 || echo 1)"
R=$(grep -a '^i2chid: regler=' "$TMPD/i2creal.txt")
gleich "kein Designware-Regler in QEMU -- und das wird auch so gesagt" \
    "0" "$(echo "$R" | sed 's/i2chid: regler=\([0-9]*\).*/\1/')"
gleich "keine erfundene I2C-Adresse in der echten DSDT" "0" \
    "$(echo "$R" | sed 's/.* adressen=\([0-9]*\).*/\1/')"
TAB=$(echo "$R" | sed 's/.* tabellen=\([0-9]*\).*/\1/')
zusage "es wurden ueberhaupt Tabellen durchsucht ($TAB) -- sonst waere die
        Null oben wertlos" "$([ "$TAB" -ge 3 ] && echo 0 || echo 1)"

# GEGENPROBE: ohne das Wort passiert gar nichts.
RC=$(lauf i2caus "noi2c i2chid nokbd nofs noring3")
gleich "GEGENPROBE noi2c: die Stufe kehrt sofort zurueck" "1" \
    "$(grep -ac 'i2chid: noi2c' "$TMPD/i2caus.txt")"

# ----------------------------------------------------------------------
echo
echo "== 7. die Latenz, in Mikrosekunden"
RC=$(lauf latenz "hidlat nokbd noring3 nofs")
sed -n 's/^hidlat: /    /p' "$TMPD/latenz.txt"
grep -aq '^hidlat:' "$TMPD/latenz.txt"
zusage "die Latenz wurde gemessen" $?

# ----------------------------------------------------------------------
echo
echo "======================================================================"
echo "  $OK bestanden, $FAIL gefallen"
echo "======================================================================"
[ "$FAIL" -eq 0 ]
