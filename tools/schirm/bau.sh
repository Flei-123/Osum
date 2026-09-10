#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/schirm/bau.sh -- Kern, Programme und ein Plattenabbild fuer die
# Fotos der Runde SCHIRM.
#
#   bash tools/schirm/bau.sh <arbeitsverzeichnis>
#
# Danach liegen dort:  k0.mb  (Multiboot-Kern, Stufe 0)
#                      disk.img (OFS mit /bin, /lib, /etc, /apps)
#
# Das ist derselbe Satz Programme, den tools/desktop/run.sh baut. Er
# steht hier noch einmal, weil die Runde SCHIRM dieselbe Platte in
# mehreren Aufloesungen fotografiert und der Aufbau dann nicht in der
# Mitte eines fremden Laeufers stehen darf.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

TMPD=${1:?arbeitsverzeichnis fehlt}
mkdir -p "$TMPD"

MONO=assets/osum-mono.ttf
SANS=assets/osum-sans.ttf
PROGS="desktop taskbar settings launcher dhcp explorer widgetdemo locate sh echo ls cat edit"

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "firnc fehlt"; exit 1; }

echo ">> Kern"
bash tools/build-kernel.sh "$TMPD/k0.mb" --stufe 0 > "$TMPD/kern.log" 2>&1 \
    || { tail -20 "$TMPD/kern.log"; exit 1; }
echo "   $(stat -c%s "$TMPD/k0.mb") Oktette"

echo ">> Programme"
as --64 -o "$TMPD/crt.o" kernel/user/crt.s || exit 1
for p in $PROGS; do
    vendor/firn/bin/firnc "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/e-$p" 2>&1 \
        || { echo "firnc $p:"; head -8 "$TMPD/e-$p"; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
        -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" || exit 1
    strip --strip-all "$TMPD/$p.elf"
done
echo "   $(echo $PROGS | wc -w) Stueck"

echo ">> Plattenabbild"
python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 || exit 1
printf '# taskbar.conf\nedge=0\nheight=32\nwidth=100\nautohide=0\nontop=1\n' \
    > "$TMPD/taskbar.conf"
ARGS=(build "$TMPD/disk.img" 16384 /lib/
      "/lib/mono.ttf=$MONO" "/lib/sans.ttf=$SANS" /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$TMPD/$p.elf"); done
ARGS+=("/bin/files@/bin/explorer")
ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme" "/etc/taskbar.conf=$TMPD/taskbar.conf")
while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py assets/apps "$TMPD/buendel" nur="$PROGS")
while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    || { tail -10 "$TMPD/mkfs.txt"; exit 1; }
echo "   $(stat -c%s "$TMPD/disk.img") Oktette"
exit 0
