#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."

IMGDIR=${1:?bauverzeichnis fehlt}
PREFIX=${2:?ausgabe-praefix fehlt}
LANG_=${3:-de}

[ -f "$IMGDIR/osum.mb" ] || { echo "== $IMGDIR/osum.mb fehlt" >&2; exit 1; }
[ -f "$IMGDIR/root.img" ] || { echo "== $IMGDIR/root.img fehlt" >&2; exit 1; }

W=$(mktemp -d)
trap 'kill $QP 2>/dev/null; rm -rf "$W"' EXIT

KVM=(-accel tcg)
[ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)

APPEND="modfs osum gfx wm wig desk wmshell wmdauer herz"
APPEND="$APPEND nosched noproc nofs lang=$LANG_ uiscale=2"

qemu-system-x86_64 "${KVM[@]}" -m 512 \
    -kernel "$IMGDIR/osum.mb" -initrd "$IMGDIR/root.img" \
    -append "$APPEND" \
    -serial "file:$W/serial.txt" -display none -no-reboot -vga std \
    -monitor "unix:$W/mon,server,nowait" > "$W/qemu.log" 2>&1 &
QP=$!

mon() { printf '%s\n' "$1" | socat - "UNIX-CONNECT:$W/mon" >/dev/null 2>&1; sleep "${2:-1}"; }
schuss() { mon "screendump $W/$1.ppm" 3; }

i=0
while [ $i -lt 400 ]; do
    grep -qa 'taskbar: state\|launcher: ready\|wm: windows' "$W/serial.txt" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break
    sleep 0.5; i=$((i + 1))
done
sleep 8


# ---------------------------------------------------- das Kontrollzentrum
mon "sendkey esc" 2
mon "sendkey meta_l-a" 4
schuss 10-qs

mon "sendkey meta_l-a" 3

# ------------------------------------------------------------ der Starter

kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null

mkdir -p "$(dirname "$PREFIX")"
cp "$W/serial.txt" "$PREFIX.txt" 2>/dev/null
for n in 00-schreibtisch 10-qs 20-start; do
    [ -s "$W/$n.ppm" ] || continue
    python3 -c "
from PIL import Image
Image.open('$W/$n.ppm').save('$PREFIX-${n#*-}.png')
" 2>/dev/null && echo "  $PREFIX-${n#*-}.png"
done

echo "  --- was die Oberflaeche gemeldet hat ---"
grep -aE '^(qs|hk|taskbar|launcher):' "$W/serial.txt" | head -25 | sed 's/^/      /'
