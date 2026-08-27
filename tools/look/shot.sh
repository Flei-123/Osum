#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/look/shot.sh -- ROUND LOOK: ONE BOOTABLE IMAGE, PARAMETERISED.
#
# /root/mergerun/bootshot.sh built an image that showed the desktop and
# proved the window titles were not empty.  It also, without saying so,
# left four things OFF the disk:
#
#     /lib/icons.ttf        the icon font of round ICONS
#     /etc/passwd           which msg.fi needs to find the user's name
#     /etc/schemas/*        the five colour schemes of round THEME
#     /etc/theme.conf       which scheme, which mode
#
# The consequences were exactly the complaints this round answers:
# no umlauts (no passwd -> no user -> no language -> English), no
# battery or network symbol (no icon font -> the text fallback), and an
# interface in the built-in fallback ramp with square 1px borders.
#
# So this script does not "fix the screenshot".  It builds the image the
# system is supposed to have, and every knob the round adds is an
# argument here, so that a claim about a variant is a claim about a
# picture that was actually taken.
#
#   bash tools/look/shot.sh <outdir> [key=value ...]
#
#     lang=de|en        /etc/locale.conf   (system default language)
#     user=de|en|-      /users/root/config/locale ('-' = do not write)
#     scheme=day|paper|night|midnight|contrast
#     mode=light|dark|auto
#     shape=classic|modern
#     edge=bottom|top|left|right
#     align=left|center
#     icons=yes|no      put /lib/icons.ttf on the disk or not
#     nvicons=yes|no    put /etc/netview/* on the disk or not
#     progs="..."       override the program list
#
# It prints, on stdout, the numbers a caller wants to assert on: the
# QEMU exit code, the size of the picture, and every `leiste:` and
# `wm:` line the run reported.
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRN_REPO=${FIRN_REPO:-/root/jarvis/projects/u_DiS4in7esMF1/firn}
export FIRNLIB="$(pwd)/lib"

OUT=${1:?usage: shot.sh <outdir> [key=value ...]}
shift || true

lang=de
user=-
scheme=day
mode=light
shape=classic
edge=bottom
align=left
icons=yes
nvicons=yes
keep=no
extra=""
uitrace=no
autohide=0
progs="schreibtisch leiste einstellungen launcher dhcp explorer widgetdemo locate sh echo ls cat edit"
for a in "$@"; do
    case "$a" in
        lang=*) lang=${a#*=} ;;
        user=*) user=${a#*=} ;;
        scheme=*) scheme=${a#*=} ;;
        mode=*) mode=${a#*=} ;;
        shape=*) shape=${a#*=} ;;
        edge=*) edge=${a#*=} ;;
        align=*) align=${a#*=} ;;
        icons=*) icons=${a#*=} ;;
        nvicons=*) nvicons=${a#*=} ;;
        keep=*) keep=${a#*=} ;;
        progs=*) progs=${a#*=} ;;
        extra=*) extra=${a#*=} ;;
        uitrace=*) uitrace=${a#*=} ;;
        autohide=*) autohide=${a#*=} ;;
        *) echo "unknown option: $a" >&2; exit 2 ;;
    esac
done

MONO=assets/osum-mono.ttf
SANS=assets/osum-sans.ttf
ICONF=assets/osum-icons.ttf

# The build tree is shared between runs so that thirteen programs are
# not recompiled for every variant.  It is keyed on nothing but the
# repository, because the programs do not depend on any option above;
# every option above is a FILE on the disk.
BUILDD=${LOOKBUILD:-/root/lookrun/build}
mkdir -p "$BUILDD" "$OUT"

# ---------------------------------------------------------- 1. kernel
if [ ! -s "$BUILDD/k0.mb" ] || [ -n "${LOOKREBUILD:-}" ]; then
    ./tools/build-kernel.sh "$BUILDD/k0.mb" > "$BUILDD/k.log" 2>&1 \
        || { echo "FAILED: the kernel does not build"; tail -20 "$BUILDD/k.log"; exit 1; }
fi
echo "kernel $(stat -c%s "$BUILDD/k0.mb") octets"

# -------------------------------------------------------- 2. programs
if [ ! -s "$BUILDD/crt.o" ] || [ -n "${LOOKREBUILD:-}" ]; then
    as --64 -o "$BUILDD/crt.o" kernel/user/crt.s 2>"$BUILDD/as.err" \
        || { echo "FAILED: crt.s"; cat "$BUILDD/as.err"; exit 1; }
fi
for p in $progs; do
    if [ -s "$BUILDD/$p.elf" ] && [ -z "${LOOKREBUILD:-}" ] \
       && [ "$BUILDD/$p.elf" -nt "kernel/user/$p.fi" ]; then
        continue
    fi
    vendor/firn/bin/firnc "kernel/user/$p.fi" -o "$BUILDD/$p.o" \
        > "$BUILDD/e-$p" 2>&1 \
        || { echo "FAILED to compile $p"; head -20 "$BUILDD/e-$p"; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
        -o "$BUILDD/$p.elf" "$BUILDD/crt.o" "$BUILDD/$p.o" 2>"$BUILDD/ld.err" \
        || { echo "FAILED to link $p"; cat "$BUILDD/ld.err"; exit 1; }
    strip --strip-all "$BUILDD/$p.elf"
done
echo "programs $(echo $progs | wc -w)"

# ------------------------------------------------------------ 3. disk
python3 tools/k15/tree.py "$OUT/baum" > "$OUT/baum.log" 2>&1 || exit 1

printf '# taskbar.conf -- written by tools/look/shot.sh\nedge=%s\nheight=28\nwidth=104\nautohide=%s\nontop=1\nalign=%s\n' \
    "$edge" "$autohide" "$align" > "$OUT/taskbar.conf"
printf '# /etc/theme.conf\nscheme=%s\nmode=%s\naccent=\nshape=%s\nlight_start=07:00\ndark_start=19:00\n' \
    "$scheme" "$mode" "$shape" > "$OUT/theme.conf"
printf '# /etc/time.conf\noffset=120\n' > "$OUT/time.conf"
# THE SYSTEM DEFAULT LANGUAGE.  It is a DEFAULT and not the answer:
# /users/<name>/config/locale still wins, and the settings program
# still writes only that one.  See docs/ROUNDLOOK.md section A.
printf '# /etc/locale.conf -- the system default language.\n# A user who has chosen one overrides this in\n# /users/<name>/config/locale; the settings program writes only there.\nlang=%s\n' \
    "$lang" > "$OUT/locale.conf"
cat > "$OUT/passwd" <<'EOF'
root:x:0:0:root:/:/bin/sh
justin:x:1000:1000:Justin:/users/justin:/bin/sh
EOF

ARGS=(build "$OUT/disk.img" 8192 /lib/
      "/lib/mono.ttf=$MONO" "/lib/sans.ttf=$SANS")
[ "$icons" = yes ] && ARGS+=("/lib/icons.ttf=$ICONF")
ARGS+=(/bin/)
for p in $progs; do ARGS+=("/bin/$p=$BUILDD/$p.elf"); done
ARGS+=("/bin/files@/bin/explorer")
ARGS+=(/etc/
       "/etc/theme.conf=$OUT/theme.conf@0644"
       "/etc/time.conf=$OUT/time.conf@0644"
       "/etc/locale.conf=$OUT/locale.conf@0644"
       "/etc/passwd=$OUT/passwd@0644"
       "/etc/taskbar.conf=$OUT/taskbar.conf@0644")
if [ "$uitrace" = yes ]; then
    printf 'on\n' > "$OUT/uitrace"
    ARGS+=("/etc/uitrace=$OUT/uitrace@0644")
fi
ARGS+=(/etc/schemas/)
for s in assets/schemes/*.scheme; do
    ARGS+=("/etc/schemas/$(basename "$s" .scheme)=$s@0644")
done
if ls assets/shapes/*.shape >/dev/null 2>&1; then
    ARGS+=(/etc/shapes/)
    for s in assets/shapes/*.shape; do
        ARGS+=("/etc/shapes/$(basename "$s" .shape)=$s@0644")
    done
fi
if [ "$nvicons" = yes ]; then
    if python3 tools/netview/icons.py bauen "$OUT/nvicons" > "$OUT/nvicons.log" 2>&1; then
        ARGS+=(/etc/netview/)
        for q in state-nocarrier state-noip state-noroute state-online \
                 mark-filtered mark-faked mark-none sys-faking \
                 tile-fake tile-net tile-hide; do
            [ -e "$OUT/nvicons/$q" ] && ARGS+=("/etc/netview/$q=$OUT/nvicons/$q")
        done
    fi
fi
ARGS+=(/usr/ /usr/share/ /usr/share/locale/
       /usr/share/locale/en/ "/usr/share/locale/en/messages=locale/en/messages"
       /usr/share/locale/de/ "/usr/share/locale/de/messages=locale/de/messages")
[ -e locale/en/icons ] && ARGS+=("/usr/share/locale/en/icons=locale/en/icons")
[ -e locale/de/icons ] && ARGS+=("/usr/share/locale/de/icons=locale/de/icons")
if [ "$user" != "-" ]; then
    printf '%s\n' "$user" > "$OUT/userlocale"
    ARGS+=(/users/ /users/root/ /users/root/config/
           "/users/root/config/locale=$OUT/userlocale@0644")
fi
while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py assets/apps "$OUT/buendel")
while read -r z; do ARGS+=("$z"); done < "$OUT/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$OUT/mkfs.log" 2>&1 \
    || { echo "FAILED: mkfs"; tail -20 "$OUT/mkfs.log"; exit 1; }
echo "disk $(stat -c%s "$OUT/disk.img") octets"

# ------------------------------------------------------------ 4. boot
SOCK="$OUT/mon.sock"; rm -f "$SOCK" "$OUT/serial.txt"
timeout 420 qemu-system-x86_64 -kernel "$BUILDD/k0.mb" -m 512 \
    -append "gfx wm wig wigicons desk wmhold wiglong nokbd nosched noproc nofs $extra" \
    -serial "file:$OUT/serial.txt" -display none -no-reboot -vga std \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$OUT/disk.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$OUT/qemu.log" 2>&1 &
PID=$!
i=0
while [ $i -lt 2400 ]; do
    grep -qaE '^wm: hold' "$OUT/serial.txt" 2>/dev/null && break
    kill -0 "$PID" 2>/dev/null || break
    sleep 0.15; i=$((i+1))
done
python3 tools/gfx/screenshot.py "$SOCK" "$OUT/desktop.ppm" 25 > "$OUT/shot.log" 2>&1
wait "$PID"; RC=$?
rm -f "$SOCK"
echo "qemu exit $RC"

if [ -s "$OUT/desktop.ppm" ]; then
    python3 - "$OUT" <<'PY'
import sys, os
from PIL import Image
o = sys.argv[1]
im = Image.open(os.path.join(o, "desktop.ppm")).convert("RGB")
im.save(os.path.join(o, "desktop.png"))
print("picture %dx%d colours %d" % (im.size[0], im.size[1],
      len(im.getcolors(maxcolors=1 << 24) or [])))
PY
fi
grep -aE '^(leiste|taskbar|wlib|wm|msg|i18n|theme|shape|desk|schreibtisch|einstellungen|settings): ' \
    "$OUT/serial.txt" 2>/dev/null | head -140
if [ "$keep" = no ]; then rm -f "$OUT/disk.img" "$OUT"/*.o 2>/dev/null; fi
exit 0
