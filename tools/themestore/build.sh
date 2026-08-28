#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/themestore/build.sh -- ROUND THEMESTORE: ONE DISK, ONE KNOB EACH.
#
#   bash tools/themestore/build.sh <outdir> [key=value ...]
#
#     preset=<id>       apply this preset's files as the STARTING state
#                       (writes /etc/theme.conf and /etc/taskbar.conf on
#                       the host, out of assets/themes/<id>.preset, with
#                       the same seven keys the system reads)
#     scheme= mode= shape= accent= edge= align=
#                       the individual axes, when no preset is named
#     script=<cmd>      run this in the guest shell instead of the desktop
#     user=<name>       put /users/<name>/config/ on the disk (the
#                       account store lives under it)
#     account=yes|no    whether /etc/passwd maps uid 0 to that user
#     shot=yes|no       take a screenshot of the desktop
#     themes=yes|no     put /etc/themes/ on the disk at all
#     localdir=<dir>    seed /etc/themes.local/ from a host directory
#     extra="..."       extra words on the kernel command line
#     progs="..."       override the program list
#     accel=tcg|kvm     which QEMU accelerator (measured, see the round log)
#
# It prints the numbers a caller asserts on: the QEMU exit code, the
# size of the picture, and every `theme:`, `taskbar:`, `settings:`,
# `wm:` and `desk:` line the run produced.
#
# THE BUILD TREE IS KEYED ON THE WORKING TREE, for the reason round
# PAINT wrote down: two worktrees of this repository sharing one build
# directory produced a "before" screenshot that contained the "after"
# code, and 0 differing pixels was reported as a success.
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"

OUT=${1:?usage: build.sh <outdir> [key=value ...]}
shift || true

preset=""
scheme=day
mode=light
shape=modern
accent=""
edge=bottom
align=left
script=""
user=root
account=yes
shot=yes
themes=yes
local_dir=""
extra=""
accel=${OSUM_ACCEL:-tcg}
uitrace=no
clicks=""
keep=no
progs="desktop taskbar settings launcher theme explorer sh echo ls cat"
for a in "$@"; do
    case "$a" in
        preset=*) preset=${a#*=} ;;
        scheme=*) scheme=${a#*=} ;;
        mode=*) mode=${a#*=} ;;
        shape=*) shape=${a#*=} ;;
        accent=*) accent=${a#*=} ;;
        edge=*) edge=${a#*=} ;;
        align=*) align=${a#*=} ;;
        script=*) script=${a#*=} ;;
        user=*) user=${a#*=} ;;
        account=*) account=${a#*=} ;;
        shot=*) shot=${a#*=} ;;
        themes=*) themes=${a#*=} ;;
        localdir=*) local_dir=${a#*=} ;;
        extra=*) extra=${a#*=} ;;
        progs=*) progs=${a#*=} ;;
        accel=*) accel=${a#*=} ;;
        keep=*) keep=${a#*=} ;;
        uitrace=*) uitrace=${a#*=} ;;
        click=*) clicks="$clicks ${a#*=}" ;;
        *) echo "unknown option: $a" >&2; exit 2 ;;
    esac
done

# A preset FILE decides the starting state, and it is read by the same
# seven key names the system reads -- not re-typed here.  If it were
# re-typed, a disagreement between the file and this script would look
# like a bug in the operating system.
if [ -n "$preset" ]; then
    P="assets/themes/$preset.preset"
    [ -f "$P" ] || { echo "no such preset: $P"; exit 2; }
    scheme=$(grep -aE "^scheme=" "$P" | tail -1 | cut -d= -f2-)
    mode=$(grep -aE "^mode=" "$P" | tail -1 | cut -d= -f2-)
    shape=$(grep -aE "^shape=" "$P" | tail -1 | cut -d= -f2-)
    accent=$(grep -aE "^accent=" "$P" | tail -1 | cut -d= -f2-)
    edge=$(grep -aE "^edge=" "$P" | tail -1 | cut -d= -f2-)
    align=$(grep -aE "^align=" "$P" | tail -1 | cut -d= -f2-)
fi

BUILDD=${TSBUILD:-/tmp/osum-tsbuild-$(pwd | md5sum | cut -c1-12)}
mkdir -p "$BUILDD" "$OUT"

# ---------------------------------------------------------- 1. kernel
newer=$(find kernel tools/build-kernel.sh -newer "$BUILDD/k0.mb" -print -quit 2>/dev/null || true)
if [ ! -s "$BUILDD/k0.mb" ] || [ -n "$newer" ] || [ -n "${TSREBUILD:-}" ]; then
    ./tools/build-kernel.sh "$BUILDD/k0.mb" > "$BUILDD/k.log" 2>&1 \
        || { echo "FAILED: the kernel does not build"; tail -20 "$BUILDD/k.log"; exit 1; }
fi
echo "kernel $(stat -c%s "$BUILDD/k0.mb") octets"

# -------------------------------------------------------- 2. programs
if [ ! -s "$BUILDD/crt.o" ] || [ -n "${TSREBUILD:-}" ]; then
    as --64 -o "$BUILDD/crt.o" kernel/user/crt.s 2>"$BUILDD/as.err" \
        || { echo "FAILED: crt.s"; cat "$BUILDD/as.err"; exit 1; }
fi
# A program is not only its own file: every one of these imports wlib,
# wlibc and now vorlage.  The newest file in kernel/user decides for all
# of them -- round LOOK found that out the slow way.
USERNEW=$(ls -t kernel/user/*.fi 2>/dev/null | head -1)
for p in $progs; do
    if [ -s "$BUILDD/$p.elf" ] && [ -z "${TSREBUILD:-}" ] \
       && [ "$BUILDD/$p.elf" -nt "kernel/user/$p.fi" ] \
       && [ -n "$USERNEW" ] && [ "$BUILDD/$p.elf" -nt "$USERNEW" ]; then
        continue
    fi
    vendor/firn/bin/firnc "kernel/user/$p.fi" -o "$BUILDD/$p.o" \
        > "$BUILDD/e-$p" 2>&1 \
        || { echo "FAILED to compile $p"; head -25 "$BUILDD/e-$p"; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
        -o "$BUILDD/$p.elf" "$BUILDD/crt.o" "$BUILDD/$p.o" 2>"$BUILDD/ld.err" \
        || { echo "FAILED to link $p"; cat "$BUILDD/ld.err"; exit 1; }
    strip --strip-all "$BUILDD/$p.elf"
done
echo "programs $(echo $progs | wc -w)"

# ------------------------------------------------------------ 3. disk
python3 tools/k15/tree.py "$OUT/baum" > "$OUT/baum.log" 2>&1 || exit 1

printf '# taskbar.conf -- written by tools/themestore/build.sh\nedge=%s\nheight=28\nwidth=104\nautohide=0\nontop=1\nalign=%s\n' \
    "$edge" "$align" > "$OUT/taskbar.conf"
printf '# /etc/theme.conf\nscheme=%s\nmode=%s\naccent=%s\nshape=%s\nlight_start=07:00\ndark_start=19:00\n' \
    "$scheme" "$mode" "$accent" "$shape" > "$OUT/theme.conf"
printf '# /etc/time.conf\noffset=120\n' > "$OUT/time.conf"
printf '# /etc/locale.conf\nlang=de\n' > "$OUT/locale.conf"
if [ "$account" = yes ]; then
    printf 'root:x:0:0:root:/users/%s:/bin/sh\n' "$user" > "$OUT/passwd"
else
    # NO ACCOUNT AT ALL: uid 0 is not in /etc/passwd, so `msg.user_path`
    # fails and there is no account store.  This is the case the round
    # promises must still work completely, so it is a case the runner
    # can actually build.
    printf 'nobody:x:65534:65534:nobody:/:/bin/sh\n' > "$OUT/passwd"
fi
printf '%s\n' de > "$OUT/userlocale"

ARGS=(build "$OUT/disk.img" 16384 /lib/
      "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
      "/lib/icons.ttf=assets/osum-icons.ttf")
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
ARGS+=(/etc/shapes/)
for s in assets/shapes/*.shape; do
    ARGS+=("/etc/shapes/$(basename "$s" .shape)=$s@0644")
done
if [ "$themes" = yes ]; then
    ARGS+=(/etc/themes/)
    for s in assets/themes/*.preset; do
        ARGS+=("/etc/themes/$(basename "$s" .preset)=$s@0644")
    done
fi
# A local store that is already populated -- for the "it survived a
# restart" section, which has to boot a SECOND disk carrying what the
# first one wrote.
if [ -n "$local_dir" ] && [ -d "$local_dir" ]; then
    ARGS+=(/etc/themes.local/)
    for s in "$local_dir"/*; do
        [ -f "$s" ] && ARGS+=("/etc/themes.local/$(basename "$s")=$s@0644")
    done
fi
ARGS+=(/usr/ /usr/share/ /usr/share/locale/
       /usr/share/locale/en/ "/usr/share/locale/en/messages=locale/en/messages"
       /usr/share/locale/de/ "/usr/share/locale/de/messages=locale/de/messages")
[ -e locale/en/icons ] && ARGS+=("/usr/share/locale/en/icons=locale/en/icons")
[ -e locale/de/icons ] && ARGS+=("/usr/share/locale/de/icons=locale/de/icons")
if [ "$account" = yes ]; then
    ARGS+=(/users/ "/users/$user/" "/users/$user/config/"
           "/users/$user/config/locale=$OUT/userlocale@0644")
fi
# THE APPLICATION BUNDLES, but only those whose program is really on
# this disk. `editor.osp` points at /bin/edit and `widgets.osp` at
# /bin/widgetdemo; neither is in the program list of this round, and
# mkfs.py stops with "gibt es nicht" -- rightly.
rm -rf "$OUT/apps"
cp -a assets/apps "$OUT/apps"
rm -rf "$OUT/apps/editor.osp" "$OUT/apps/widgets.osp"
while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py "$OUT/apps" "$OUT/buendel" 2>/dev/null || true)
while read -r z; do ARGS+=("$z"); done < "$OUT/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$OUT/mkfs.log" 2>&1 \
    || { echo "FAILED: mkfs"; tail -20 "$OUT/mkfs.log"; exit 1; }
echo "disk $(stat -c%s "$OUT/disk.img") octets"

# ------------------------------------------------------------ 4. boot
ACC=()
[ "$accel" = kvm ] && ACC=(-accel kvm)
SOCK="$OUT/mon.sock"; rm -f "$SOCK" "$OUT/serial.txt"
if [ -n "$script" ]; then
    APPEND="osum nokbd nosched noproc nofs script=$script"
    WAITFOR='^kernel: done'
else
    APPEND="gfx wm wig wigicons desk wmhold wiglong nokbd nosched noproc nofs $extra"
    WAITFOR='^wm: hold'
fi
T0=$(date +%s%N)
timeout 420 qemu-system-x86_64 "${ACC[@]}" -kernel "$BUILDD/k0.mb" -m 512 \
    -append "$APPEND" \
    -serial "file:$OUT/serial.txt" -display none -no-reboot -vga std \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$OUT/disk.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$OUT/qemu.log" 2>&1 &
PID=$!
i=0
while [ $i -lt 3200 ]; do
    grep -qaE "$WAITFOR" "$OUT/serial.txt" 2>/dev/null && break
    kill -0 "$PID" 2>/dev/null || break
    sleep 0.15; i=$((i+1))
done
if [ -n "$clicks" ]; then
    # THE CLICKS GO THROUGH THE QEMU MONITOR, and `mouse_move` there is
    # RELATIVE -- see tools/themestore/click.py for why that matters and
    # what it costs to get it wrong.
    python3 tools/themestore/click.py $clicks > "$OUT/mon.txt" 2>"$OUT/click.err"
    python3 tools/wm/monitor.py "$SOCK" "$OUT/mon.txt" > "$OUT/click.log" 2>&1
    sleep 2
fi
if [ -z "$script" ] && [ "$shot" = yes ]; then
    python3 tools/gfx/screenshot.py "$SOCK" "$OUT/desktop.ppm" 25 \
        > "$OUT/shot.log" 2>&1
fi
[ -n "$script" ] || kill "$PID" 2>/dev/null
wait "$PID"; RC=$?
T1=$(date +%s%N)
rm -f "$SOCK"
echo "qemu exit $RC  accel $accel  wall $(( (T1-T0)/1000000 )) ms"

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
grep -aE '^(theme|taskbar|desktop|settings|wlib|wm|msg|i18n|shape|desk|vorlage): ' \
    "$OUT/serial.txt" 2>/dev/null | head -220
if [ "$keep" = no ]; then rm -f "$OUT"/*.o 2>/dev/null; fi
exit 0
