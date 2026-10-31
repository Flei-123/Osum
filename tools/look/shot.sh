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
#     append="..."      REPLACE the whole kernel command line instead
#                       of appending to it. Round UMLAUT2 needs the
#                       storage dialog, and that one comes up in the
#                       WINDOW SERVER path (`wig wigspeicher`), which
#                       the desktop path (`desk`) does not run. Empty
#                       by default -- nothing changes for anyone else.
#     shots="a b c"    take several pictures during the hold, in
#                       these second-gaps (round ZIEH). Empty = one.
#     accel=tcg|kvm     which QEMU accelerator (default tcg -- KVM is
#                       faster, and round UMLAUT2 takes its pictures
#                       with it, but a host without /dev/kvm must still
#                       be able to run this script)
#
# It prints, on stdout, the numbers a caller wants to assert on: the
# QEMU exit code, the size of the picture, and every `taskbar:` and
# `wm:` line the run reported.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/sync/gc.sh   # r278: FIRN_FUNCTION_SECTIONS + ld --gc-sections (OSUM_NO_GC=1 = off)
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
# RUNDE ZIEH: MEHRERE BILDER WAEHREND DES HALTENS.
#
shots=""
# ROUND SOFTUI: HARDWARE VIRTUALISATION, AND WHY IT IS A SWITCH AND NOT
# A CONSTANT.  Round PAINT wrote "the measuring machine has no /dev/kvm"
# and measured everything under TCG.  This machine HAS one, and the
# difference is not cosmetic -- see docs/ROUNDSOFTUI.md, section 1.
# It stays a switch because round KVMFIX found four test sections that
# measure something DIFFERENT under KVM; a picture is not one of them,
# and `accel=tcg` reproduces every older number.
accel=kvm
# ROUND SOFTUI: WHERE THE POINTER STANDS WHEN THE PICTURE IS TAKEN.
# The hover state of the three caption buttons IS a measurement of this
# round -- a close button that only turns red when the pointer is on it
# cannot be photographed without a pointer. `hover=x,y` drives it there
# and does NOT click; see tools/softui/hover.py.
hover=""
# The programs print their reports only when /etc/uitrace exists (commit
# adde7c58 gated the serial output); every caller of this script parses those
# reports, so the trace file is on by default.
uitrace=yes
# The window shadow is OFF by default in the system (round ECHTHARDWARE-6);
# the shadow measurements ask for it with `shadow=on`.
shadow=off
winalpha=100
blur=0
# The bar hides a battery / network field the machine does not have
# (`hide_missing=1`, the system default since round STARTKNOPF). The look
# measurements want those fields, so the default HERE is 0; a test of the
# system default passes `hidemissing=1`.
hidemissing=0
autohide=0
accel=tcg
append=""
modulconf=""
progs="desktop taskbar settings launcher dhcp explorer widgetdemo locate sh echo ls cat edit nedit"
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
        shots=*) shots=${a#*=} ;;
        uitrace=*) uitrace=${a#*=} ;;
        shadow=*) shadow=${a#*=} ;;
        winalpha=*) winalpha=${a#*=} ;;
        blur=*) blur=${a#*=} ;;
        hidemissing=*) hidemissing=${a#*=} ;;
        autohide=*) autohide=${a#*=} ;;
        accel=*) accel=${a#*=} ;;
        append=*) append=${a#*=} ;;
        modul=*) modulconf=${a#*=} ;;
        hover=*) hover=${a#*=} ;;
        *) echo "unknown option: $a" >&2; exit 2 ;;
    esac
done

MONO=assets/osum-mono.ttf
SANS=assets/osum-sans.ttf
ICONF=assets/osum-icons.ttf

# The build tree is shared between runs so that thirteen programs are
# not recompiled for every variant.  The options above do not change it;
# every option above is a FILE on the disk.
#
# ROUND PAINT: AND IT IS KEYED ON THE WORKING TREE, which it was not.
# The path was the literal `/root/lookrun/build`, so two worktrees of
# this repository -- the one under test and the one it is measured
# against -- shared one cache and one kernel.  The measurement that
# found it: a screenshot taken from the OLD branch showed the NEW
# branch's window shadow, and the two pictures were identical in the
# band where the shadow lives, 0 differing pixels out of 3720.  A
# baseline that is the thing it is supposed to be compared with is
# worse than no baseline.
#
# Keyed on the absolute path of the tree, outside the repository so
# that no build output can land in a commit.
BUILDD=${LOOKBUILD:-/tmp/osum-lookbuild-$(pwd | md5sum | cut -c1-12)}
mkdir -p "$BUILDD" "$OUT"

# ---------------------------------------------------------- 1. kernel
# THE KERNEL IS CACHED, AND THE CACHE HAS TO KNOW WHEN IT IS STALE.
# It did not: the programs were rebuilt when their source was newer,
# the kernel was rebuilt only when it was missing, and a round that
# changed which programs `desk_start` spawns got a picture of the OLD
# kernel starting the OLD programs. `desk: start /bin/schreibtisch
# pid=0` was the only sign, and pid=0 is not an error anybody reads.
# Same rule for both now: newer source, new build.
newer=$(find kernel tools/build-kernel.sh -newer "$BUILDD/k0.mb" -print -quit 2>/dev/null || true)
if [ ! -s "$BUILDD/k0.mb" ] || [ -n "$newer" ] || [ -n "${LOOKREBUILD:-}" ]; then
    ./tools/build-kernel.sh "$BUILDD/k0.mb" > "$BUILDD/k.log" 2>&1 \
        || { echo "FAILED: the kernel does not build"; tail -20 "$BUILDD/k.log"; exit 1; }
fi
echo "kernel $(stat -c%s "$BUILDD/k0.mb") octets"

# -------------------------------------------------------- 2. programs
if [ ! -s "$BUILDD/crt.o" ] || [ -n "${LOOKREBUILD:-}" ]; then
    as --64 -o "$BUILDD/crt.o" kernel/user/crt.s 2>"$BUILDD/as.err" \
        || { echo "FAILED: crt.s"; cat "$BUILDD/as.err"; exit 1; }
fi
# A PROGRAM IS NOT ONLY ITS OWN FILE.
#
# This compared $p.elf against kernel/user/$p.fi and nothing else. But
# every one of these programs does `import wlib`, and wlib.fi is where
# the widgets live -- so a change to a list, a button or a trace never
# reached the image, and the ONLY symptom was that the new line was
# missing from the serial log. That is the same silent staleness the
# second addendum found in the kernel step ("only rebuilt when it was
# MISSING"), one directory further down.
#
# The newest file in kernel/user decides for all of them. Recompiling
# thirteen small programs costs a few seconds; a measurement taken
# against yesterday's binary costs a round.
USERNEW=$(ls -t kernel/user/*.fi 2>/dev/null | head -1)
for p in $progs; do
    if [ -s "$BUILDD/$p.elf" ] && [ -z "${LOOKREBUILD:-}" ] \
       && [ "$BUILDD/$p.elf" -nt "kernel/user/$p.fi" ] \
       && [ -n "$USERNEW" ] && [ "$BUILDD/$p.elf" -nt "$USERNEW" ]; then
        continue
    fi
    vendor/firn/bin/firnc $OPTL -c "kernel/user/$p.fi" -o "$BUILDD/$p.o" \
        > "$BUILDD/e-$p" 2>&1 \
        || { echo "FAILED to compile $p"; head -20 "$BUILDD/e-$p"; exit 1; }
    #
    CRT="$BUILDD/crt.o"
    if grep -qa '^profile app' "kernel/user/$p.fi"; then
        CRT=""
    fi
    ld $GCS -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
        -o "$BUILDD/$p.elf" $CRT "$BUILDD/$p.o" 2>"$BUILDD/ld.err" \
        || { echo "FAILED to link $p"; cat "$BUILDD/ld.err"; exit 1; }
    strip --strip-all "$BUILDD/$p.elf"
done
echo "programs $(echo $progs | wc -w)"

# ------------------------------------------------------------ 3. disk
python3 tools/k15/tree.py "$OUT/baum" > "$OUT/baum.log" 2>&1 || exit 1

printf '# taskbar.conf -- written by tools/look/shot.sh\nedge=%s\nheight=28\nwidth=104\nautohide=%s\nontop=1\nalign=%s\nhide_missing=%s\n' \
    "$edge" "$autohide" "$align" "$hidemissing" > "$OUT/taskbar.conf"
# r402: the runs that measure the start menu's LIST (rows, the Run button, the umlaut of its label)
# use the list window; the Windows 11 window is measured by tools/startmenu
echo "style=list" > "$OUT/startmenu.conf"
printf '# /etc/theme.conf\nscheme=%s\nmode=%s\naccent=\nshape=%s\nlight_start=07:00\ndark_start=19:00\nshadow=%s\nwindow_alpha=%s\nblur=%s\n' \
    "$scheme" "$mode" "$shape" "$shadow" "$winalpha" "$blur" > "$OUT/theme.conf"
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

# 8192 blocks (4 MiB) held these programs with 4 per cent to spare
# after round LOOK. That is not spare room, that is a countdown.
#
#     $ bash tools/look/shot.sh /tmp/shottest
#     FAILED: mkfs
#     mkfs: the disk is full
#
ARGS=(build "$OUT/disk.img" 32768 --v3 --inodes=512 /lib/
      "/lib/mono.ttf=$MONO" "/lib/sans.ttf=$SANS")
[ "$icons" = yes ] && ARGS+=("/lib/icons.ttf=$ICONF")
ARGS+=(/bin/)
for p in $progs; do ARGS+=("/bin/$p=$BUILDD/$p.elf"); done
ARGS+=("/bin/files@/bin/explorer")
case " $progs " in *" storage "*) ARGS+=("/bin/speicher@/bin/storage");; esac
ARGS+=(/etc/
       "/etc/theme.conf=$OUT/theme.conf@0644"
       "/etc/time.conf=$OUT/time.conf@0644"
       "/etc/locale.conf=$OUT/locale.conf@0644"
       "/etc/passwd=$OUT/passwd@0644"
       "/etc/taskbar.conf=$OUT/taskbar.conf@0644" "/etc/startmenu.conf=$OUT/startmenu.conf@0644")
#
if [ -n "$modulconf" ]; then
    cp "$modulconf" "$OUT/module.conf"
    ARGS+=("/etc/module.conf=$OUT/module.conf@0644")
fi
if [ "$uitrace" = yes ]; then
    printf 'on\n' > "$OUT/uitrace"
    ARGS+=("/etc/uitrace=$OUT/uitrace@0644")
fi
ARGS+=(/etc/schemas/)
for s in assets/schemes/*.scheme; do
    # The shadow switch is read out of the SCHEME file (wlibc.scheme_key),
    # not out of /etc/theme.conf: with `shadow=on` a copy with that line is used.
    if [ "$shadow" = on ]; then
        cp "$s" "$OUT/$(basename "$s")"
        printf '\nshadow=on\n' >> "$OUT/$(basename "$s")"
        s="$OUT/$(basename "$s")"
    fi
    ARGS+=("/etc/schemas/$(basename "$s" .scheme)=$s@0644")
done
if ls assets/shapes/*.shape >/dev/null 2>&1; then
    ARGS+=(/etc/shapes/)
    for s in assets/shapes/*.shape; do
        ARGS+=("/etc/shapes/$(basename "$s" .shape)=$s@0644")
    done
fi
#
if ls assets/themes/*.preset >/dev/null 2>&1; then
    ARGS+=(/etc/themes/)
    for s in assets/themes/*.preset; do
        ARGS+=("/etc/themes/$(basename "$s" .preset)=$s@0644")
    done
fi
if [ "$nvicons" = yes ]; then
    if python3 tools/netview/icons.py bauen "$OUT/nvicons" > "$OUT/nvicons.log" 2>&1; then
        ARGS+=(/etc/netview/)
        #
        for q in state-nocarrier state-noip state-noroute state-online \
                 mark-filtered mark-faked mark-none sys-faking \
                 tile-fake tile-net tile-hide tile-dark tile-power \
                 tile-tile; do
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
while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py assets/apps "$OUT/buendel" nur="$progs")
while read -r z; do ARGS+=("$z"); done < "$OUT/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$OUT/mkfs.log" 2>&1 \
    || { echo "FAILED: mkfs"; tail -20 "$OUT/mkfs.log"; exit 1; }
echo "disk $(stat -c%s "$OUT/disk.img") octets"

# ------------------------------------------------------------ 4. boot
SOCK="$OUT/mon.sock"; rm -f "$SOCK" "$OUT/serial.txt"
ACC=()
if [ "$accel" = kvm ]; then
    if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        ACC=(-accel kvm -cpu host)
    else
        echo "accel=kvm asked for, /dev/kvm not usable -- falling back to tcg"
    fi
fi
timeout 420 qemu-system-x86_64 "${ACC[@]}" -kernel "$BUILDD/k0.mb" -m 512 \
    -append "${append:-gfx wm wig wigicons desk wmhold wiglong nokbd nosched noproc nofs $extra}" \
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
if [ -n "$hover" ]; then
    python3 tools/softui/hover.py "$hover" > "$OUT/hover.txt" 2>"$OUT/hover.err"
    python3 tools/wm/monitor.py "$SOCK" "$OUT/hover.txt" > "$OUT/hover.log" 2>&1
    sleep 2
fi
if [ -n "$shots" ]; then
    n=0
    for g in $shots; do
        n=$((n+1))
        sleep "$g"
        python3 tools/gfx/screenshot.py "$SOCK" "$OUT/schuss-$n.ppm" 25 \
            > "$OUT/shot-$n.log" 2>&1
    done
fi
python3 tools/gfx/screenshot.py "$SOCK" "$OUT/desktop.ppm" 25 > "$OUT/shot.log" 2>&1
wait "$PID"; RC=$?
rm -f "$SOCK"
echo "qemu exit $RC"
echo "accel ${ACC[*]:-tcg}"

for q in "$OUT"/schuss-*.ppm; do
    [ -s "$q" ] || continue
    python3 - "$q" <<'PY'
import sys
from PIL import Image
q = sys.argv[1]
Image.open(q).convert("RGB").save(q[:-4] + ".png")
print("schuss %s" % (q[:-4] + ".png"))
PY
    rm -f "$q"
done
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
grep -aE '^(taskbar|desktop|settings|wlib|wm|msg|i18n|theme|shape|desk): ' \
    "$OUT/serial.txt" 2>/dev/null | head -6000
if [ "$keep" = no ]; then rm -f "$OUT/disk.img" "$OUT"/*.o 2>/dev/null; fi
exit 0
