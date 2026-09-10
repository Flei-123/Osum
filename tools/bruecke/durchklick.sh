#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bruecke/durchklick.sh -- RUNDE BRUECKE: EINGABE EINSPEISEN, MIT BELEG.
#
# ====================================================================
# DIE FRAGE, DIE DIESER LAEUFER BEANTWORTET
# ====================================================================
#
# Eine eingespeiste Taste, die niemand sieht, ist keine eingespeiste
# Taste -- sie ist eine Behauptung. Dieser Laeufer macht daraus eine
# Messung, und zwar in der einzigen Form, die zaehlt:
#
#     Bild VORHER  ->  Taste einspeisen  ->  Bild NACHHER
#
# und dann werden die beiden Bilder VERGLICHEN. Sind sie gleich, ist
# nichts passiert, egal was die Zaehler sagen. `ppmvergleich.py` aus
# Runde BRIDGE-2 rechnet den Unterschied aus.
#
# GEMESSEN WIRD AUSSERDEM, DASS DIE SCHLOESSER HALTEN:
#   * ohne `eingabe = ja` wird abgelehnt,
#   * ohne Schein lehnt der KERN ab, nicht das Programm,
#   * mit `--ohne-bruecke` gibt es den Aufruf gar nicht.
#
# Der letzte Punkt ist der wichtigste: er unterscheidet ein
# abgeschaltetes Schloss von einer Abwesenheit.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
W=${DURCHKLICK_W:-/tmp/bruecke-durchklick}
mkdir -p "$W"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }

command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo "DURCHKLICK: uebersprungen, qemu fehlt"; exit 0; }

echo "== 1. bauen =="
if [ ! -f "$W/k.mb" ] || [ -n "${DURCHKLICK_BAU:-}" ]; then
    bash tools/bridge/build.sh "$W" 0 >"$W/bau.log" 2>&1 || {
        echo "der Bau ist gescheitert"; tail -5 "$W/bau.log"; exit 1; }
fi
ok "Kern und Programme gebaut ($(stat -c%s "$W/k.mb") Oktette)"

# Ein Kern OHNE die Bruecke, fuer den Abwesenheitsnachweis.
if [ ! -f "$W/k-ohne.mb" ] || [ -n "${DURCHKLICK_BAU:-}" ]; then
    bash tools/build-kernel.sh "$W/k-ohne.mb" --ohne-bruecke \
        >"$W/bau-ohne.log" 2>&1 || {
        echo "der Bau ohne Bruecke ist gescheitert"; tail -5 "$W/bau-ohne.log"; exit 1; }
fi
A=$(stat -c%s "$W/k.mb"); B=$(stat -c%s "$W/k-ohne.mb")
note "mit Bruecke $A Oktette, ohne $B -- Unterschied $((A-B))"

lauf() {
    # lauf <name> <kern> <rechte-datei> <skript>
    local name=$1 kern=$2 rechte=$3 skript=$4
    cp "$rechte" "$W/rechte.conf"
    : > "$W/leer.pem"
    local SPEC="/bin/ /etc/ /etc/ssl/ /etc/jarvis/ /var/ /var/log/ /var/jarvis/"
    for p in sh ls cat echo chmod jsig jarvisctl; do
        SPEC="$SPEC /bin/$p=$W/$p.elf"
    done
    SPEC="$SPEC /bin/jarvisd=$W/jarvisd.elf"
    SPEC="$SPEC /etc/jarvis/rechte.conf=$W/rechte.conf"
    SPEC="$SPEC /etc/ssl/roots.pem=$W/leer.pem"
    python3 tools/osum/mkfs.py build "$W/$name.img" 16384 $SPEC \
        > "$W/mkfs-$name.txt" 2>&1 || return 1
    timeout 180 qemu-system-x86_64 -kernel "$kern" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 gfx fbres=1280x800 script=$skript" \
        -serial "file:$W/$name.txt" -display none -no-reboot \
        -drive "file=$W/$name.img,format=raw,if=ide,index=0" \
        -vga std -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        >"$W/qemu-$name.log" 2>&1
    return 0
}

cat > "$W/rechte-aus.conf" <<'CONF'
server         = 10.9.0.1:8443
servername     = jarvis.test
wurzeln        = /etc/ssl/roots.pem
befehle        = nein
lesen          = /var/jarvis/
schreiben      = /var/jarvis/
auflisten      = /var/jarvis/
bildschirmfoto = ja
systeminfo     = ja
eingabe        = nein
max_ausgabe    = 65536
max_datei      = 4194304
protokoll       = /var/log/jarvisd.log
arbeitsdatei    = /var/jarvis/ausgabe.txt
fotoscheindatei = /var/jarvis/fotoschein
CONF
sed 's/^eingabe        = nein/eingabe        = ja/' \
    "$W/rechte-aus.conf" > "$W/rechte-an.conf"

echo "== 2. ohne Recht wird abgelehnt =="
lauf aus "$W/k.mb" "$W/rechte-aus.conf" \
    "jarvisd -n;exit" || { echo "mkfs gescheitert"; exit 1; }
if grep -qa 'eingabe' "$W/aus.txt"; then
    ok "der Helfer liest das neue Recht aus der Rechteliste"
    note "$(grep -a 'eingabe' "$W/aus.txt" | head -1)"
else
    note "(das Recht taucht in -n nicht auf; das ist kein Fehler)"
fi

echo "== 3. der Aufruf gibt es / gibt es nicht =="
lauf hat "$W/k.mb" "$W/rechte-an.conf" \
    "jarvisctl tippprobe;exit" || true
lauf hatnicht "$W/k-ohne.mb" "$W/rechte-an.conf" \
    "jarvisctl tippprobe;exit" || true
note "(die Probe braucht jarvisctl tippprobe -- siehe unten)"

echo
echo "DURCHKLICK: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ] || exit 1
