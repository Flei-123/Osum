#!/usr/bin/env bash
#
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
W=${VERGLEICH_W:-/tmp/fotovergleich}
mkdir -p "$W"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }

for t in qemu-system-x86_64 python3; do
    command -v "$t" >/dev/null 2>&1 || { echo "VERGLEICH: uebersprungen, $t fehlt"; exit 0; }
done

if [ ! -f "$W/k.mb" ] || [ -n "${VERGLEICH_BAU:-}" ]; then
    bash tools/bridge/build.sh "$W" 0 >"$W/bau.txt" 2>&1 || {
        echo "VERGLEICH: der Bau ist gescheitert"; tail -5 "$W/bau.txt"; exit 1; }
fi
K="$W/k.mb"

cat > "$W/rechte.conf" <<'CONF'
server         = 10.9.0.1:8443
servername     = jarvis.test
roots        = /etc/ssl/roots.pem
commands        = no
read          = /var/jarvis/
write      = /var/jarvis/
list      = /var/jarvis/
screenshot = yes
sysinfo     = yes
max_output    = 65536
max_file      = 8388608
log       = /var/log/jarvisd.log
work_file    = /var/jarvis/output.txt
permit_file = /var/jarvis/screenshot-permit
CONF
: > "$W/leer.pem"

SPEC="/bin/ /etc/ /etc/ssl/ /etc/jarvis/ /var/ /var/log/ /var/jarvis/"
for p in sh ls cat echo chmod sleep jsig jarvisctl; do SPEC="$SPEC /bin/$p=$W/$p.elf"; done
SPEC="$SPEC /bin/jarvisd=$W/jarvisd.elf"
SPEC="$SPEC /etc/jarvis/permissions.conf=$W/rechte.conf /etc/ssl/roots.pem=$W/leer.pem"
python3 tools/osum/mkfs.py build "$W/probe.img" 131072 $SPEC --v3 >"$W/mkfs.txt" 2>&1 || {
    echo "VERGLEICH: mkfs gescheitert"; tail -4 "$W/mkfs.txt"; exit 1; }
cp "$W/probe.img" "$W/live.img"

SKRIPT="jarvisctl screenshot 600;jarvisd -f /var/jarvis/eins.ppm;echo BRIDGE2-MARKE;jarvisctl screenshot 600;jarvisd -f /var/jarvis/zwei.ppm"
timeout 240 qemu-system-x86_64 -kernel "$K" -m 256 \
    -append "osum nokbd nosched noproc nofs noring3 gfx nocursor script=$SKRIPT" \
    -serial "file:$W/seriell.txt" -display none -no-reboot \
    -drive "file=$W/live.img,format=raw,if=ide,index=0" \
    -vga std \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$W/qemu.log" 2>&1
QPID=""

N=$(grep -ac "Bildschirmfoto geschrieben" "$W/seriell.txt" 2>/dev/null); N=${N:-0}
if [ "$N" -ge 2 ]; then
    ok "Osum hat sich ZWEIMAL selbst fotografiert (ueber den Kern-Schein)"
else
    bad "Osum hat nicht zwei Bilder gemacht (nur $N)"
    grep -aE 'jarvisd:|schirm:|shot:' "$W/seriell.txt" 2>/dev/null | tail -6 | sed 's/^/        /'
fi
grep -qa "shot: pid=" "$W/seriell.txt" \
    && ok "und der KERN hat es protokolliert (shot: pid=...) -- heimlich geht es nicht" \
    || bad "der Kern hat kein Bildschirmfoto protokolliert"

for n in eins zwei; do
    python3 tools/osum/mkfs.py cat "$W/live.img" "/var/jarvis/$n.ppm" \
        > "$W/$n.ppm" 2>"$W/cat-$n.txt" || true
    if [ -s "$W/$n.ppm" ]; then
        ok "Bild $n liegt auf Osums eigener Platte ($(stat -c%s "$W/$n.ppm") Oktette)"
    else
        bad "Bild $n liess sich nicht aus dem Abbild holen"
        head -3 "$W/cat-$n.txt" 2>/dev/null | sed 's/^/        /'
    fi
done

if [ -s "$W/eins.ppm" ] && [ -s "$W/zwei.ppm" ]; then
    python3 tools/bridge/ppmvergleich.py "$W/eins.ppm" "$W/zwei.ppm" \
        > "$W/vergleich.txt" 2>&1
    cat "$W/vergleich.txt" | sed 's/^/        /'

    grep -qac "ist VOLLSTAENDIG" "$W/vergleich.txt" >/dev/null \
        && ok "beide Bilder sind VOLLSTAENDIG (jede Zeile, 3 072 000 Oktette)" \
        || bad "mindestens ein Bild ist unvollstaendig"

    VZ=$(grep -a "^Zeilen verschieden:" "$W/vergleich.txt" | awk "{print \$3}")
    GZ=$(grep -a "^Zeilen gleich:" "$W/vergleich.txt" | awk "{print \$3}")
    if [ "${VZ:-0}" -gt 0 ] 2>/dev/null; then
        ok "die zwei Bilder sind VERSCHIEDEN ($VZ Zeilen) -- der Aufruf liefert den JEWEILIGEN Schirm"
    else
        bad "die zwei Bilder sind gleich, obwohl der Schirm sich geaendert hat"
    fi

    AB=$(grep -a "^abweichende Oktette in den gleichen Zeilen:" "$W/vergleich.txt" | awk "{print \$7}")
    if [ "${AB:-1}" = 0 ] && [ "${GZ:-0}" -gt 50 ] 2>/dev/null; then
        ok "in den $GZ unveraenderten Zeilen: 0 abweichende Oktette -- kein Zufallsspeicher"
    else
        bad "auch unveraenderte Zeilen weichen ab ($AB Oktette in $GZ Zeilen)"
    fi

    NZ=$(grep -a "nicht-schwarze Bildpunkte innen" "$W/vergleich.txt" | awk "{print \$4}")
    if [ "${NZ:-0}" -gt 1000 ] 2>/dev/null; then
        ok "und es ist nicht einfach schwarz ($NZ nicht-schwarze Bildpunkte)"
    else
        bad "das Bild ist (fast) ganz schwarz -- ein gleiches Nichts ist kein Beweis"
    fi

    python3 tools/bridge/findbrand.py "$W/eins.ppm" "$W/zwei.ppm" \
        > "$W/marke.txt" 2>&1
    cat "$W/marke.txt" | sed 's/^/        /'
    grep -qa "^MARKE-GEFUNDEN" "$W/marke.txt" \
        && ok "die neue Textzeile steht im ZWEITEN Bild und fehlt im ersten" \
        || bad "die neue Textzeile ist im zweiten Bild nicht zu finden"
fi

echo "VERGLEICH: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ]
