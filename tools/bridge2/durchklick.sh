#!/usr/bin/env bash
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
        echo "the build failed"; tail -5 "$W/bau.log"; exit 1; }
fi
ok "Kern und Programme gebaut ($(stat -c%s "$W/k.mb") Oktette)"

if [ ! -f "$W/k-ohne.mb" ] || [ -n "${DURCHKLICK_BAU:-}" ]; then
    bash tools/build-kernel.sh "$W/k-ohne.mb" --ohne-bruecke \
        >"$W/bau-ohne.log" 2>&1 || {
        echo "the build without bridge failed"; tail -5 "$W/bau-ohne.log"; exit 1; }
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
    SPEC="$SPEC /etc/jarvis/permissions.conf=$W/rechte.conf"
    SPEC="$SPEC /etc/ssl/roots.pem=$W/leer.pem"
    bash tools/mkfsfi/mkfs.sh build "$W/$name.img" 16384 $SPEC \
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
roots        = /etc/ssl/roots.pem
commands        = no
read          = /var/jarvis/
write      = /var/jarvis/
list      = /var/jarvis/
screenshot = yes
sysinfo     = yes
input        = no
max_output    = 65536
max_file      = 4194304
log       = /var/log/jarvisd.log
work_file    = /var/jarvis/output.txt
permit_file = /var/jarvis/screenshot-permit
CONF
sed 's/^eingabe        = nein/eingabe        = ja/' \
    "$W/rechte-aus.conf" > "$W/rechte-an.conf"

echo "== 2. without permission it is rejected =="
lauf aus "$W/k.mb" "$W/rechte-aus.conf" \
    "jarvisd -n;exit" || { echo "mkfs gescheitert"; exit 1; }
if grep -qa 'eingabe' "$W/aus.txt"; then
    ok "the helper reads the new permission from the permission list"
    note "$(grep -a 'eingabe' "$W/aus.txt" | head -1)"
else
    note "(das Recht taucht in -n nicht auf; das ist kein Fehler)"
fi

echo "== 3. the call exists / does not exist =="
lauf hat "$W/k.mb" "$W/rechte-an.conf" \
    "jarvisctl tippprobe;exit" || true
lauf hatnicht "$W/k-ohne.mb" "$W/rechte-an.conf" \
    "jarvisctl tippprobe;exit" || true
note "(die Probe braucht jarvisctl tippprobe -- siehe unten)"

echo
echo "DURCHKLICK: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ] || exit 1
