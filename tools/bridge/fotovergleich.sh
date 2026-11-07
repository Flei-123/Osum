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
        echo "COMPARE: the build failed"; tail -5 "$W/bau.txt"; exit 1; }
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
bash tools/mkfsfi/mkfs.sh build "$W/probe.img" 131072 $SPEC --v3 >"$W/mkfs.txt" 2>&1 || {
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
    ok "Osum photographed itself TWICE (via the kernel shim)"
else
    bad "Osum did not take two images (only $N)"
    grep -aE 'jarvisd:|screen:|schirm:|shot:' "$W/seriell.txt" 2>/dev/null | tail -6 | sed 's/^/        /'
fi
grep -qa "shot: pid=" "$W/seriell.txt" \
    && ok "and the KERNEL logged it (shot: pid=...) -- it cannot happen secretly" \
    || bad "the kernel did not log a screenshot"

for n in eins zwei; do
    bash tools/mkfsfi/mkfs.sh cat "$W/live.img" "/var/jarvis/$n.ppm" \
        > "$W/$n.ppm" 2>"$W/cat-$n.txt" || true
    if [ -s "$W/$n.ppm" ]; then
        ok "Image $n is on Osum's own disk ($(stat -c%s "$W/$n.ppm") Oktette)"
    else
        bad "Image $n could not be fetched from the image"
        head -3 "$W/cat-$n.txt" 2>/dev/null | sed 's/^/        /'
    fi
done

if [ -s "$W/eins.ppm" ] && [ -s "$W/zwei.ppm" ]; then
    python3 tools/bridge/ppmvergleich.py "$W/eins.ppm" "$W/zwei.ppm" \
        > "$W/vergleich.txt" 2>&1
    cat "$W/vergleich.txt" | sed 's/^/        /'

    grep -qac "ist VOLLSTAENDIG" "$W/vergleich.txt" >/dev/null \
        && ok "both images are COMPLETE (every line, 3 072 000 octets)" \
        || bad "at least one image is incomplete"

    VZ=$(grep -a "^Zeilen verschieden:" "$W/vergleich.txt" | awk "{print \$3}")
    GZ=$(grep -a "^Zeilen gleich:" "$W/vergleich.txt" | awk "{print \$3}")
    if [ "${VZ:-0}" -gt 0 ] 2>/dev/null; then
        ok "the two images are DIFFERENT ($VZ lines) -- the call delivers the CURRENT screen"
    else
        bad "the two images are equal although the screen changed"
    fi

    AB=$(grep -a "^abweichende Oktette in den gleichen Zeilen:" "$W/vergleich.txt" | awk "{print \$7}")
    if [ "${AB:-1}" = 0 ] && [ "${GZ:-0}" -gt 50 ] 2>/dev/null; then
        ok "in the $GZ unchanged lines: 0 deviating octets -- no random memory"
    else
        bad "even unchanged lines deviate ($AB octets in $GZ lines)"
    fi

    NZ=$(grep -a "nicht-schwarze Bildpunkte innen" "$W/vergleich.txt" | awk "{print \$4}")
    if [ "${NZ:-0}" -gt 1000 ] 2>/dev/null; then
        ok "and it is not simply black ($NZ non-black pixels)"
    else
        bad "the image is (almost) entirely black -- an equal nothing is no proof"
    fi

    python3 tools/bridge/findbrand.py "$W/eins.ppm" "$W/zwei.ppm" \
        > "$W/marke.txt" 2>&1
    cat "$W/marke.txt" | sed 's/^/        /'
    grep -qa "^MARKE-GEFUNDEN" "$W/marke.txt" \
        && ok "the new text line is in the SECOND image and missing in the first" \
        || bad "the new text line cannot be found in the second image"
fi

echo "VERGLEICH: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ]
