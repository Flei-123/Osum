#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/firnenv.sh

AUS=${1:-docs/shots/hotplug2}
mkdir -p "$AUS"
ARB=${HP_ARB:-$(mktemp -d)}
mkdir -p "$ARB"
[ -n "${HP_ARB:-}" ] || trap 'rm -rf "$ARB"' EXIT

PROGS="explorer sh echo ls cat edit launcher locate eject"

for w in mkfs.vfat mcopy sfdisk qemu-system-x86_64 python3; do
    command -v "$w" >/dev/null 2>&1 || { echo "KNOPF: uebersprungen, $w fehlt"; exit 0; }
done
python3 -c "import PIL" 2>/dev/null || { echo "KNOPF: uebersprungen, PIL fehlt"; exit 0; }

echo "== bauen =="
./tools/build-kernel.sh "$ARB/k.mb" > "$ARB/build.log" 2>&1 \
    || { echo "the kernel cannot be built"; tail -5 "$ARB/build.log"; exit 1; }
echo "  Kern: $(stat -c%s "$ARB/k.mb") Oktette"

as --64 -o "$ARB/crt.o" kernel/user/crt.s 2>/dev/null
for p in $PROGS; do
    [ -f "kernel/user/$p.fi" ] || continue
    UPROF=""; UCRT="$ARB/crt.o"
    grep -qa '^profile app' "kernel/user/$p.fi" && { UPROF=--profile=app; UCRT=""; }
    "$FIRNC" $UPROF -c "kernel/user/$p.fi" -o "$ARB/$p.o" > "$ARB/$p.log" 2>&1 || {
        echo "  $p uebersetzt nicht:"; grep -E '^error' "$ARB/$p.log" | head -3; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
        -o "$ARB/$p.elf" $UCRT "$ARB/$p.o" 2>/dev/null || {
        echo "  ld scheitert an $p"; exit 1; }
    strip --strip-all "$ARB/$p.elf"
done
echo "  Programme: $(echo $PROGS | wc -w)"

python3 tools/k15/tree.py "$ARB/baum" > "$ARB/baum.log" 2>&1 \
    || { echo "tree.py scheitert"; tail -3 "$ARB/baum.log"; exit 1; }

printf 'on\n' > "$ARB/uitrace"

MK=()
for p in $PROGS; do MK+=("/bin/$p=$ARB/$p.elf"); done
while read -r z; do MK+=("$z"); done < "$ARB/baum/liste"
bash tools/mkfsfi/mkfs.sh build "$ARB/disk.img" 16384 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ "${MK[@]}" "/bin/files@/bin/explorer" \
    /proc/ /dev/ /mnt/ /medien/ /etc/ \
    "/etc/theme=$ARB/baum/theme" "/etc/uitrace=$ARB/uitrace" \
    /usr/ /usr/share/ /usr/share/locale/ /usr/share/locale/de/ \
    "/usr/share/locale/de/messages=locale/de/messages" \
    /usr/share/locale/en/ \
    "/usr/share/locale/en/messages=locale/en/messages" \
    > "$ARB/mkfs.log" 2>&1 \
    || { echo "mkfs scheitert"; tail -3 "$ARB/mkfs.log"; exit 1; }
echo "  Platte: $(tail -1 "$ARB/mkfs.log")"

# der Stick
rm -f "$ARB/stick.img" "$ARB/stick.part"
dd if=/dev/zero of="$ARB/stick.img" bs=1M count=48 status=none
sfdisk "$ARB/stick.img" >/dev/null 2>&1 <<'SF'
label: dos
start=2048, type=c
SF
dd if=/dev/zero of="$ARB/stick.part" bs=1M count=46 status=none
mkfs.vfat -F32 -n OSUMSTICK "$ARB/stick.part" >/dev/null 2>&1
printf 'from linux to stick\n' > "$ARB/host.txt"
mcopy -i "$ARB/stick.part" "$ARB/host.txt" ::host.txt
dd if="$ARB/stick.part" of="$ARB/stick.img" bs=512 seek=2048 conv=notrunc status=none
rm -f "$ARB/stick.part"
echo "  stick: FAT32, MBR, one file from the host"

cp "$ARB/disk.img" "$ARB/live-knopf.img"

echo
echo "== der Lauf =="
python3 tools/hotplug/button.py "$ARB" "$AUS"
RC=$?

echo
echo "== what the machine reported =="
grep -aE 'wechsel:|explorer: places |explorer: eject|explorer: ausknopf' \
    "$ARB/knopf-seriell.txt" 2>/dev/null | sed 's/^/  /' | head -14
echo "  (Arbeitsverzeichnis: $ARB)"
exit $RC
