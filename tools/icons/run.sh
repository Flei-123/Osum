#!/usr/bin/env bash
# tools/icons/run.sh -- ROUND ICONS: the acceptance run.
#
# Six parts, and the fourth is the one the round stands or falls on.
#
#   1. THE FONT CAN BE REBUILT.  `assets/osum-icons.ttf` is a binary in
#      the tree, and a binary in a tree is a thing nobody can read a
#      diff of.  So it has to come back octet for octet out of
#      `assets/icons/icons.map` and the Lucide package -- the same rule
#      `tools/wm/run.sh` applies to the two text fonts.  The generated
#      `lib/icons.fi` has to come back identical as well; if it did not,
#      the names in the code and the glyphs in the font could drift
#      apart without anybody noticing.
#
#   2. NO RAW CODE POINTS.  `tools/icons/rawcp.py` counts every literal
#      in the drawing code that is one of the code points the map has
#      given away.  The answer has to be 0.  This is the promise that
#      makes the whole arrangement worth having: the day somebody writes
#      0xE041 into a paint routine, the map has stopped being the single
#      place and nobody will find out until an icon is wrong.
#
#   3. NAMES AND ICONS MATCH.  Every icon in the map has a tooltip in
#      `locale/en/icons`, and every tooltip has an icon.  An icon with
#      no name cannot be read by anyone who does not already know it.
#
#   4. THE PROMISES, MEASURED ON THE MACHINE.  `/bin/icont` in Ring 3:
#      every icon has a glyph at every size, the ink fits its box, the
#      shape does not depend on the colour, an unknown code point comes
#      back as "no glyph", and the dense index is the inverse of the
#      code points.  Plus the three costs -- an icon cold, an icon warm,
#      an OSYM bitmap of the same size -- because the question this
#      round has to answer is not "does it work".
#
#   5. THE COUNTERPROOF.  Boot the same kernel with a disk that has NO
#      /lib/icons.ttf.  The system has to come up, say so, and draw its
#      interface without icons.  A missing font must not be a crash --
#      and without this run, "not required" would be a claim.
#
#   6. THE PICTURES.  The file manager before and after, photographed
#      out of QEMU, and the overview sheet rendered on the host through
#      the second rasteriser.
#
# Usage:  bash tools/icons/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

CC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
LUCIDE=${LUCIDE:-/root/icon-src/lucide/font/lucide.ttf}
LUCIDE_INFO=${LUCIDE_INFO:-/root/icon-src/lucide/font/info.json}
SHOTS=docs/icons

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { # name value op expected
    local name=$1 value=$2 op=$3 want=$4
    if [ -z "$value" ]; then bad "$name: no number found (wanted $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, wanted $op $want"; fi
}
same() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', wanted '$3'"; fi; }
wert() { grep -a -m1 -oE "$2" "$1" 2>/dev/null | head -1; }

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || {
    echo "icons: fetch-firnc.sh failed"; exit 1; }

# ===================================================================
echo "== 1. the font comes back out of the map =="

if [ ! -f "$LUCIDE" ]; then
    echo "  SKIP  the Lucide package is not unpacked at $LUCIDE"
    echo "        (set LUCIDE and LUCIDE_INFO, or unpack lucide-static there)"
else
    python3 tools/icons/build.py --source "$LUCIDE" --info "$LUCIDE_INFO" \
        --out "$TMPD/icons.ttf" --ids "$TMPD/icons.fi" \
        --list "$TMPD/icons.list" > "$TMPD/build.txt" 2>&1
    if [ $? -ne 0 ]; then
        bad "the builder does not run"; sed 's/^/        /' "$TMPD/build.txt"
    else
        sed 's/^/        /' "$TMPD/build.txt"
        cmp -s "$TMPD/icons.ttf" assets/osum-icons.ttf \
            && ok "assets/osum-icons.ttf is reproduced octet for octet" \
            || bad "assets/osum-icons.ttf cannot be reproduced"
        cmp -s "$TMPD/icons.fi" lib/icons.fi \
            && ok "lib/icons.fi is reproduced octet for octet" \
            || bad "lib/icons.fi does not match the map -- run the builder"
        cmp -s "$TMPD/icons.list" assets/icons/icons.list \
            && ok "assets/icons/icons.list is reproduced" \
            || bad "assets/icons/icons.list does not match the map"
    fi
fi

QUELL=$(stat -c%s "$LUCIDE" 2>/dev/null || echo 0)
ZIEL=$(stat -c%s assets/osum-icons.ttf)
GLYPHEN=$(python3 tools/ttf/raster.py info assets/osum-icons.ttf \
    | grep -oE 'glyphen=[0-9]+' | cut -d= -f2)
NAMEN=$(grep -cv '^#' assets/icons/icons.list)
echo "        source $QUELL octets -> $ZIEL octets, $GLYPHEN glyphs, $NAMEN names"
num "the cut font is smaller than a tenth of the source" \
    "$((ZIEL * 10))" lt "${QUELL:-1}"
[ -f assets/icons/LICENSE.lucide ] \
    && ok "the licence of the source font is in the tree" \
    || bad "assets/icons/LICENSE.lucide is missing"
grep -qi 'ISC License' assets/icons/LICENSE.lucide \
    && ok "and it is the ISC licence Lucide is published under" \
    || bad "LICENSE.lucide does not look like Lucide's licence"

# ===================================================================
echo "== 2. no raw code point in the drawing code =="

python3 tools/icons/rawcp.py > "$TMPD/rawcp.txt" 2>&1
RAW=$(wert "$TMPD/rawcp.txt" 'rawcp: [0-9]+ raw' | grep -oE '[0-9]+')
sed 's/^/        /' "$TMPD/rawcp.txt"
same "raw code points in the drawing code" "${RAW:-x}" "0"

# The counterproof: put one in, and the checker MUST find it.  Without
# this the "0" above could just mean the checker is broken.
mkdir -p "$TMPD/gegen/assets/icons" "$TMPD/gegen/kernel/user" "$TMPD/gegen/lib"
cp assets/icons/icons.map "$TMPD/gegen/assets/icons/"
CP=$(grep -m1 -oE '= E0[0-9A-F]{2}' assets/icons/icons.map | cut -d' ' -f2)
printf 'fn f() -> u64 {\n    return 0x%s\n}\n' "$CP" \
    > "$TMPD/gegen/kernel/user/schummel.fi"
python3 tools/icons/rawcp.py --root "$TMPD/gegen" > "$TMPD/rawcp2.txt" 2>&1
GRAW=$(wert "$TMPD/rawcp2.txt" 'rawcp: [0-9]+ raw' | grep -oE '[0-9]+')
num "counterproof: a planted code point is found" "${GRAW:-0}" ge 1

# ===================================================================
echo "== 3. every icon has a name, every name has an icon =="

python3 - "$TMPD" <<'PY'
import sys
tmp = sys.argv[1]
karte = {}
for roh in open("assets/icons/icons.map", encoding="ascii"):
    z = roh.split("#", 1)[0].strip()
    if "=" in z:
        karte[z.split("=")[0].strip()] = True
tips = {}
for roh in open("locale/en/icons", encoding="ascii"):
    z = roh.split("#", 1)[0].strip()
    if "=" in z:
        k = z.split("=")[0].strip()
        if k.endswith(".tip"):
            tips[k[:-4]] = True
fehlt = sorted(k for k in karte if k not in tips)
zuviel = sorted(k for k in tips if k not in karte)
de = {}
for roh in open("locale/de/icons", encoding="ascii"):
    z = roh.split("#", 1)[0].strip()
    if "=" in z:
        k = z.split("=")[0].strip()
        if k.endswith(".tip"):
            de[k[:-4]] = True
offen = open(tmp + "/tips.txt", "w")
offen.write("icons=%d tips=%d missing=%d extra=%d de=%d\n"
            % (len(karte), len(tips), len(fehlt), len(zuviel), len(de)))
for k in fehlt:
    offen.write("no tooltip: %s\n" % k)
for k in zuviel:
    offen.write("tooltip without icon: %s\n" % k)
offen.close()
PY
sed 's/^/        /' "$TMPD/tips.txt"
TFEHLT=$(wert "$TMPD/tips.txt" 'missing=[0-9]+' | cut -d= -f2)
TEXTRA=$(wert "$TMPD/tips.txt" 'extra=[0-9]+' | cut -d= -f2)
TDE=$(wert "$TMPD/tips.txt" 'de=[0-9]+' | cut -d= -f2)
TN=$(wert "$TMPD/tips.txt" 'tips=[0-9]+' | cut -d= -f2)
same "icons without a tooltip name" "${TFEHLT:-x}" "0"
same "tooltip names without an icon" "${TEXTRA:-x}" "0"
same "the German catalogue covers all of them" "${TDE:-x}" "${TN:-y}"

# ===================================================================
echo "== 4. the promises, measured in Ring 3 =="

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "  SKIP  qemu-system-x86_64 is not here"
else
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/k.log" 2>&1 \
    || { bad "the kernel does not build"; tail -20 "$TMPD/k.log"; }
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null

PROGS="icont explorer launcher locate widgetdemo sh ls cat edit"
rc=0
for p in $PROGS; do
    "$CC" "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/$p.err" 2>&1 || {
        bad "$p does not compile"; head -12 "$TMPD/$p.err"; rc=1; continue; }
    ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start -o "$TMPD/$p.elf" \
        "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null || {
        bad "$p does not link"; rc=1; continue; }
    strip --strip-all "$TMPD/$p.elf"
done
[ $rc = 0 ] && ok "the programs of this round are built"

python3 tools/k15/tree.py "$TMPD/baum" > /dev/null 2>&1
bau_img() { # ziel [--noicons]
    local ziel=$1 mit=${2:-mit}
    local ARGS=(build "$ziel" 4096 /lib/
        "/lib/mono.ttf=assets/osum-mono.ttf"
        "/lib/sans.ttf=assets/osum-sans.ttf")
    [ "$mit" = mit ] && ARGS+=("/lib/icons.ttf=assets/osum-icons.ttf")
    ARGS+=(/bin/)
    for p in $PROGS; do ARGS+=("/bin/$p=$TMPD/$p.elf"); done
    ARGS+=("/bin/files@/bin/explorer")
    ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme")
    while read -r zeile; do ARGS+=("$zeile"); done \
        < <(python3 tools/k15/bundle.py assets/apps "$TMPD/buendel")
    while read -r pfad; do ARGS+=("$pfad"); done < "$TMPD/baum/liste"
    python3 tools/osum/mkfs.py "${ARGS[@]}" > "$TMPD/mkfs.log" 2>&1
}
bau_img "$TMPD/disk.img" mit || { bad "mkfs failed"; tail -5 "$TMPD/mkfs.log"; }
bau_img "$TMPD/nofont.img" ohne || bad "mkfs without the icon font failed"

lauf() { # name kommandozeile abbild [marke]
    local name=$1 zeile=$2 img=$3 marke=${4:-'^wm: hold'}
    local sock="$TMPD/mon-$name.sock" aus="$TMPD/$name.txt"
    local ppm="$TMPD/$name.ppm"
    rm -f "$aus" "$ppm" "$sock"
    cp -f "$img" "$TMPD/live-$name.img"
    timeout 240 qemu-system-x86_64 -kernel "$TMPD/k.mb" -m 256 \
        -append "$zeile" -serial "file:$aus" -display none -no-reboot \
        -vga std -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$! i=0
    while [ $i -lt 1400 ]; do
        grep -qaE "$marke" "$aus" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.15
        i=$((i + 1))
    done
    python3 tools/gfx/screenshot.py "$sock" "$ppm" 25 > "$TMPD/$name.shot" 2>&1
    wait "$pid"
    rm -f "$sock"
    return 0
}

GRUND="nokbd nosched noproc nofs"
lauf icont "gfx wm wig wigicons wmhold wiglong $GRUND" "$TMPD/disk.img"
sed -n 's/^icons: /        /p' "$TMPD/icont.txt" | head -40

IP=$(wert "$TMPD/icont.txt" 'icons: pass=[0-9]+' | grep -oE '[0-9]+')
IF=$(wert "$TMPD/icont.txt" 'fail=[0-9]+' | grep -oE '[0-9]+')
num "assertions passed in Ring 3" "${IP:-0}" ge 8
same "assertions failed in Ring 3" "${IF:-x}" "0"
grep -qa 'wm: no icon font' "$TMPD/icont.txt" \
    && bad "the icon font was not loaded although the disk has it" \
    || ok "the kernel loaded /lib/icons.ttf into the third slot"

COLD=$(wert "$TMPD/icont.txt" 'ns_cold=[0-9]+' | grep -oE '[0-9]+')
WARM=$(wert "$TMPD/icont.txt" 'ns_warm=[0-9]+' | grep -oE '[0-9]+')
OSYM=$(wert "$TMPD/icont.txt" 'ns_osym=[0-9]+' | grep -oE '[0-9]+')
BG=$(wert "$TMPD/icont.txt" 'bytes_glyph=[0-9]+' | grep -oE '[0-9]+')
BO=$(wert "$TMPD/icont.txt" 'bytes_osym=[0-9]+' | grep -oE '[0-9]+')
INK=$(wert "$TMPD/icont.txt" 'ink_px=[0-9]+' | grep -oE '[0-9]+')
CPX=$(wert "$TMPD/icont.txt" 'colour_px=[0-9]+' | grep -oE '[0-9]+')
echo "        one icon cold ${COLD:-?} ns, warm ${WARM:-?} ns," \
     "one OSYM bitmap ${OSYM:-?} ns"
echo "        in memory: glyph ${BG:-?} octets, OSYM ${BO:-?} octets"
echo "        both mix the same ${INK:-?} pixels -- the bitmap was made"\
     "out of the glyph, so the two draw identical work"
if [ -n "${INK:-}" ] && [ "${INK:-0}" -gt 0 ]; then
    echo "        per mixed pixel: icon $((${WARM:-0} / INK)) ns," \
         "OSYM $((${OSYM:-0} / INK)) ns   (QEMU without KVM, TCG)"
fi
num "a cached icon costs something and the clock saw it" "${WARM:-0}" ge 1
num "the colour check touched real ink, not nothing" "${CPX:-0}" ge 1
num "and not the whole box either" "${CPX:-999}" lt 256
num "an icon in memory is smaller than the same OSYM picture" \
    "${BG:-999999}" lt "${BO:-0}"

# ===================================================================
echo "== 5. counterproof: a disk without the icon font =="

lauf noicons "gfx wm wig wigicons wmhold wiglong $GRUND" "$TMPD/nofont.img"
grep -qa 'wm: no icon font' "$TMPD/noicons.txt" \
    && ok "the kernel says the icon font is missing instead of dying" \
    || bad "no message about the missing icon font"
NF=$(wert "$TMPD/noicons.txt" 'icons: bad  font-loaded  got=[0-9]+' \
    | grep -oE 'got=[0-9]+' | cut -d= -f2)
same "and Ring 3 sees no icon font (0 = none)" "${NF:-x}" "0"
grep -qa 'user fault' "$TMPD/noicons.txt" \
    && bad "a process died without the icon font" \
    || ok "nothing crashed without the icon font"

# ===================================================================
echo "== 6. the pictures =="

mkdir -p "$SHOTS"
lauf files "gfx wm wig wigfiles wmhold wiglong $GRUND" "$TMPD/disk.img"
lauf filesnone "gfx wm wig wigfiles wmhold wiglong $GRUND" "$TMPD/nofont.img"
for n in files filesnone; do
    if [ -s "$TMPD/$n.ppm" ]; then
        python3 - "$TMPD/$n.ppm" "$SHOTS/$n.png" <<'PY'
import struct, sys, zlib
p, ziel = sys.argv[1], sys.argv[2]
d = open(p, "rb").read()
# P6 <w> <h> <max>\n
teile = d.split(b"\n", 1)
kopf = d[:64].split()
w, h = int(kopf[1]), int(kopf[2])
start = d.index(b"255\n") + 4
pix = d[start:start + w * h * 3]
roh = bytearray()
for y in range(h):
    roh.append(0)
    roh += pix[y * w * 3:(y + 1) * w * 3]
def block(m, n):
    return (struct.pack(">I", len(n)) + m + n
            + struct.pack(">I", zlib.crc32(m + n) & 0xFFFFFFFF))
open(ziel, "wb").write(
    b"\x89PNG\r\n\x1a\n"
    + block(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    + block(b"IDAT", zlib.compress(bytes(roh), 9))
    + block(b"IEND", b""))
print("%s: %d x %d" % (ziel, w, h))
PY
        ok "screenshot $SHOTS/$n.png"
    else
        bad "no screenshot for $n"
    fi
done
fi

python3 tools/icons/sheet.py > "$TMPD/sheet.txt" 2>&1 \
    && ok "the overview sheets are rendered" \
    || bad "the sheet renderer failed"
sed 's/^/        /' "$TMPD/sheet.txt"

echo
echo "icons: $pass ok, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
