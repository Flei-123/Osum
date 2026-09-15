#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/geraetekey/run.sh -- DIE ABNAHME VON O-009: DER GERAETESCHLUESSEL
# UEBERLEBT DEN NEUSTART.
#
# ==================================================================
# DIE FRAGE, UND WARUM SIE NICHT DIE VON P-001 IST
# ==================================================================
#
# `O-009` in OFFEN.md: `jarvisd` weist das Geraet mit einem
# Ed25519-Paar aus; der private Teil liegt in /etc/jarvis/geraet.key,
# entsteht aber erst beim Koppeln und zwar in der RAM-Wurzel. Nach
# jedem Neustart muss neu gekoppelt werden. In OFFEN.md steht dazu
# "haengt an P-001" -- also an der Installation auf Platte.
#
# DAS IST EINE VERMISCHUNG ZWEIER FRAGEN, und diese Abnahme trennt sie:
#
#   P-001 fragt: kann ein MENSCH OrientOS ueber die Oberflaeche auf
#         eine Platte installieren? Das ist eine Frage an den
#         Installer und seine Bedienung.
#   O-009 fragt: wenn die Wurzel auf einem SCHREIBBAREN Traeger liegt
#         -- bleibt der Geraeteschluessel dann derselbe?
#
# Die zweite Frage laesst sich messen, OHNE die erste zu loesen: eine
# Wurzel auf einer IDE-Platte, die ueber zwei Starts DIESELBE bleibt.
# Genau so misst `tools/bridge2/kette.sh` schon heute (Zeile 265-278,
# "ein Rechner, der beim Neustart seine Identitaet verliert, DARF nicht
# mehr hereinkommen"), und genau das wird hier fuer den Schluessel
# nachgeholt.
#
# WAS DIESE ABNAHME ALSO BELEGT: der Schluessel ueberlebt, sobald die
# Wurzel ueberlebt -- und `jsig` wuerfelt ihn NICHT bei jedem Start neu.
# WAS SIE NICHT BELEGT: dass man OrientOS bequem installieren kann. Das
# bleibt P-001.
#
# ==================================================================
# WIE GEMESSEN WIRD
# ==================================================================
#
#   Lauf 1   jsig aus                 -> legt das Paar an, nennt `pub`
#            jsig unterschreibe <hex> -> `sig` auf eine feste Nachricht
#   Lauf 2   DIESELBE PLATTE, neuer Start des Kerns
#            jsig aus                 -> darf KEINEN neuen anlegen
#            jsig pruefe <pub1> <msg> <sig1> -> die ALTE Unterschrift
#   Lauf 3   GEGENPROBE (Zuruecksetzen): rm geraet.key, dann jsig aus
#            -> jetzt MUSS ein ANDERER Schluessel herauskommen
#
# Und die Unterschrift aus Lauf 1 wird zusaetzlich von
# `python-cryptography` nachgerechnet -- fremdes Werkzeug, damit ein
# Fehler, der in `jsig aus` und `jsig pruefe` gleich steckt, auffliegt.
#
# Aufruf:  bash tools/geraetekey/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

TMPD=${OSUM_GK_TMP:-$(mktemp -d)}
mkdir -p "$TMPD"
KEEP=${OSUM_GK_KEEP:-}
trap '[ -n "$KEEP" ] || rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

# $QEMU_X86 aus tools/lib/qemu.sh ist DREI Woerter
# ("qemu-system-x86_64 -accel kvm") und muss deshalb UNGEQUOTET stehen --
# in Anfuehrungszeichen suchte die Shell ein Programm dieses ganzen
# Namens und fand keines (gemessen: kein einziges Serienprotokoll).
if [ -f tools/lib/qemu.sh ]; then . tools/lib/qemu.sh; fi
QEMU=${QEMU_X86:-qemu-system-x86_64}

echo "== 0. bauen: Kern und die Programme, aus DEMSELBEN Baum =="
# `rm` gehoert dazu: die Gegenprobe in Abschnitt 4 setzt den Schluessel
# zurueck, und dafuer muss er sich loeschen lassen. In der
# Voreinstellung von tools/bridge/build.sh ist `rm` nicht dabei.
export BRIDGE_PROGS="sh ls cat echo chmod rm jsig jarvisctl"
if bash tools/bridge/build.sh "$TMPD/w0" 0 > "$TMPD/build.txt" 2>&1; then
    ok "Kern und Ring-3-Programme gebaut"
else
    bad "der Bau ist fehlgeschlagen"
    tail -15 "$TMPD/build.txt" | sed 's/^/        /'
    echo "GERAETEKEY: $pass bestanden, $fail gescheitert"; exit 1
fi
K="$TMPD/w0/k.mb"
[ -f "$TMPD/w0/jsig.elf" ] && ok "/bin/jsig liegt vor ($(stat -c%s "$TMPD/w0/jsig.elf") Oktette)" \
    || bad "jsig.elf fehlt"

# Die Wurzel. EINMAL angelegt und danach BEHALTEN -- das ist der ganze
# Punkt: eine Platte, die jeder Lauf frisch kopiert, kann gar nichts
# ueberleben.
cat > "$TMPD/rechte.conf" <<'CONF'
befehle        = nein
bildschirmfoto = nein
systeminfo     = nein
CONF
python3 tools/osum/mkfs.py build "$TMPD/platte.img" 16384 \
    /bin/ /etc/ /etc/jarvis/ /var/ /var/log/ /var/jarvis/ \
    "/bin/sh=$TMPD/w0/sh.elf" \
    "/bin/ls=$TMPD/w0/ls.elf" \
    "/bin/cat=$TMPD/w0/cat.elf" \
    "/bin/echo=$TMPD/w0/echo.elf" \
    "/bin/rm=$TMPD/w0/rm.elf" \
    "/bin/chmod=$TMPD/w0/chmod.elf" \
    "/bin/jsig=$TMPD/w0/jsig.elf" \
    "/bin/jarvisctl=$TMPD/w0/jarvisctl.elf" \
    "/etc/jarvis/rechte.conf=$TMPD/rechte.conf" \
    > "$TMPD/mkfs.txt" 2>&1 \
    && ok "die Wurzel steht auf der Platte ($(stat -c%s "$TMPD/platte.img") Oktette)" \
    || { bad "mkfs"; tail -6 "$TMPD/mkfs.txt" | sed 's/^/        /'; }

# EIN START. DIESELBE Platte, kein Kopieren, kein Loeschen danach.
start() { # <name> <skript>
    # GK_WEGWERF ist die Gegenprobe (Abschnitt 5): die Platte wird vor
    # JEDEM Start frisch ueberschrieben -- genau das Verhalten der
    # RAM-Wurzel, an dem O-009 haengt. Ohne den Schalter bleibt die
    # Platte, wie es sich fuer eine Platte gehoert.
    [ -n "${GK_WEGWERF:-}" ] && cp -f "$TMPD/frisch.img" "$TMPD/platte.img"
    timeout 180 $QEMU -kernel "$K" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 script=$2" \
        -serial "file:$TMPD/$1.txt" -display none -no-reboot \
        -drive "file=$TMPD/platte.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$TMPD/q-$1.log" 2>&1
    return 0
}

# Die unberuehrte Wurzel, fuer die Gegenprobe in Abschnitt 5.
cp -f "$TMPD/platte.img" "$TMPD/frisch.img"
NACHRICHT=4f2d303039   # "O-009" in Hex

echo "== 1. Lauf 1: den Geraeteschluessel anlegen und unterschreiben =="
start lauf1 "jsig aus;jsig unterschreibe $NACHRICHT;exit"
PUB1=$(grep -aoE '^pub [0-9a-f]{64}' "$TMPD/lauf1.txt" | head -1 | awk '{print $2}')
SIG1=$(grep -aoE '^sig [0-9a-f]{128}' "$TMPD/lauf1.txt" | head -1 | awk '{print $2}')
if [ -n "$PUB1" ]; then
    ok "das Ed25519-Paar ist angelegt (pub ${PUB1:0:16}...)"
else
    bad "jsig hat keinen Schluessel geliefert"
    tail -8 "$TMPD/lauf1.txt" | sed 's/^/        /'
fi
if [ -n "$SIG1" ]; then
    ok "und eine Unterschrift darauf (${#SIG1} Hexziffern)"
else
    bad "keine Unterschrift"
    tail -8 "$TMPD/lauf1.txt" | sed 's/^/        /'
fi

echo "== 2. NEUSTART -- dieselbe Platte, neuer Kern =="
start lauf2 "jsig aus;jsig pruefe $PUB1 $NACHRICHT $SIG1;exit"
PUB2=$(grep -aoE '^pub [0-9a-f]{64}' "$TMPD/lauf2.txt" | head -1 | awk '{print $2}')
if [ -n "$PUB1" ] && [ "$PUB2" = "$PUB1" ]; then
    ok "O-009: NACH DEM NEUSTART DERSELBE oeffentliche Teil -- kein zweites Koppeln noetig"
else
    bad "O-009: der Schluessel hat den Neustart nicht ueberlebt (vorher ${PUB1:-?}, nachher ${PUB2:-?})"
    tail -8 "$TMPD/lauf2.txt" | sed 's/^/        /'
fi
if grep -qa '^ja$' "$TMPD/lauf2.txt"; then
    ok "O-009: eine Unterschrift VON VOR dem Neustart verifiziert weiterhin"
else
    bad "O-009: die alte Unterschrift verifiziert nach dem Neustart nicht"
    tail -8 "$TMPD/lauf2.txt" | sed 's/^/        /'
fi

echo "== 3. mit fremden Augen: python-cryptography rechnet nach =="
if [ -n "$PUB1" ] && [ -n "$SIG1" ] && python3 -c 'import cryptography' 2>/dev/null; then
    python3 - "$PUB1" "$SIG1" "$NACHRICHT" > "$TMPD/fremd.txt" 2>&1 <<'PYFREMD'
import sys
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from cryptography.exceptions import InvalidSignature
pub = bytes.fromhex(sys.argv[1]); sig = bytes.fromhex(sys.argv[2])
msg = bytes.fromhex(sys.argv[3])
k = Ed25519PublicKey.from_public_bytes(pub)
try:
    k.verify(sig, msg); print("GUT")
except InvalidSignature:
    print("FALSCH")
try:
    k.verify(sig, msg + b"\x01"); print("GEGENPROBE-FALSCH")
except InvalidSignature:
    print("GEGENPROBE-GUT")
PYFREMD
    grep -qa '^GUT$' "$TMPD/fremd.txt" \
        && ok "fremdes Werkzeug rechnet die ueberlebende Unterschrift nach" \
        || { bad "python-cryptography verwirft die Unterschrift"; sed 's/^/        /' "$TMPD/fremd.txt"|head -4; }
    grep -qa '^GEGENPROBE-GUT$' "$TMPD/fremd.txt" \
        && ok "GEGENPROBE: ueber eine andere Nachricht faellt sie durch" \
        || bad "die Unterschrift passt auch auf eine andere Nachricht"
else
    echo "  [ -- ] python-cryptography fehlt: die fremde Gegenrechnung entfaellt"
fi

echo "== 4. GEGENPROBE: zuruecksetzen -- und er MUSS weg sein =="
# Ohne diese Gegenprobe waere Abschnitt 2 auch dann gruen, wenn `jsig`
# den Schluessel gar nicht aus der Datei liest, sondern etwa aus einer
# festen Zahl ableitet.
start lauf3 "rm /etc/jarvis/geraet.key;jsig aus;exit"
PUB3=$(grep -aoE '^pub [0-9a-f]{64}' "$TMPD/lauf3.txt" | head -1 | awk '{print $2}')
if [ -n "$PUB3" ] && [ -n "$PUB1" ] && [ "$PUB3" != "$PUB1" ]; then
    ok "nach dem Zuruecksetzen entsteht ein ANDERER Schluessel (pub ${PUB3:0:16}...)"
else
    bad "nach dem Loeschen kam derselbe Schluessel wieder (${PUB3:-?}) -- dann liest jsig ihn nicht aus der Datei"
    tail -8 "$TMPD/lauf3.txt" | sed 's/^/        /'
fi
# Und die alte Unterschrift darf gegen den NEUEN Schluessel nicht mehr passen.
start lauf4 "jsig pruefe $PUB3 $NACHRICHT $SIG1;exit"
if grep -qa '^nein$' "$TMPD/lauf4.txt"; then
    ok "GEGENPROBE: die alte Unterschrift passt NICHT zum neuen Schluessel"
else
    bad "die alte Unterschrift passt auch zum neuen Schluessel -- dann prueft jsig nicht"
    tail -6 "$TMPD/lauf4.txt" | sed 's/^/        /'
fi

echo "== 5. GEGENPROBE: eine Wurzel, die NICHT ueberlebt =="
# Der Zustand VOR dieser Runde, nachgestellt: die Platte wird vor jedem
# Start frisch ueberschrieben (die RAM-Wurzel des Sticks). Dann MUSS
# Abschnitt 2 durchfallen -- taete er es nicht, wuerde diese Abnahme
# gar nicht das Ueberleben messen, sondern nur `jsig` mit sich selbst.
if [ -z "${GK_WEGWERF:-}" ]; then
    GK_WEGWERF=1 OSUM_GK_TMP="$TMPD/gegen" OSUM_GK_KEEP=1 \
        bash "$0" > "$TMPD/gegen.txt" 2>&1
    if grep -qa 'der Schluessel hat den Neustart nicht ueberlebt' "$TMPD/gegen.txt"; then
        ok "mit einer Wegwerfwurzel faellt O-009 durch -- die Abnahme misst wirklich das Ueberleben"
    else
        bad "auch mit Wegwerfwurzel bleibt alles gruen -- dann misst diese Abnahme nichts"
        grep -a 'FAIL\|OK    O-009' "$TMPD/gegen.txt" | head -5 | sed 's/^/        /'
    fi
    rm -rf "$TMPD/gegen"
fi

echo "GERAETEKEY: $pass bestanden, $fail gescheitert"
[ "$fail" = 0 ] || exit 1
exit 0
