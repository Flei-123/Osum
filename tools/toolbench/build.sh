#!/usr/bin/env bash
#
#   bash tools/toolbench/build.sh <outdir> [key=value ...]
#
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"

OUT=${1:?usage: build.sh <outdir> [key=value ...]}
shift || true

app=""
desk=no
script=""
mode=light
shape=modern
smp=4
clicks=""
shot=""
shots=""
plan=""
wait_s=3
# r368: KVM when the host has it. Under TCG on a loaded host the window server
# never got to mix the bar or the settings window before the picture was taken
# (px=0) and the click plans never got past their second step: eleven of the
# 298 promises of themestore and three of toolbench were red for that reason
# alone. OSUM_ACCEL=tcg still forces the slow way.
accel=${OSUM_ACCEL:-tcg}
if [ -z "${OSUM_ACCEL:-}" ] && [ -w /dev/kvm ]; then accel=kvm; fi
last=60
progs="desktop taskbar settings launcher theme explorer taskmgr sh echo ls cat sleep ps kill top"
extra=""
lang=de
second=""
flaky=""
svcstate=""
for a in "$@"; do
    case "$a" in
        app=*) app=${a#*=} ;;
        desk=*) desk=${a#*=} ;;
        script=*) script=${a#*=} ;;
        mode=*) mode=${a#*=} ;;
        shape=*) shape=${a#*=} ;;
        smp=*) smp=${a#*=} ;;
        click=*) clicks="$clicks ${a#*=}" ;;
        shot=*) shot=${a#*=} ;;
        shots=*) shots=${a#*=} ;;
        plan=*) plan=${a#*=} ;;
        wait=*) wait_s=${a#*=} ;;
        accel=*) accel=${a#*=} ;;
        last=*) last=${a#*=} ;;
        progs=*) progs=${a#*=} ;;
        extra=*) extra=${a#*=} ;;
        lang=*) lang=${a#*=} ;;
        second=*) second=${a#*=} ;;
        flaky=*) flaky=${a#*=} ;;
        svcstate=*) svcstate=${a#*=} ;;
        *) echo "unbekannte Option: $a" >&2; exit 2 ;;
    esac
done

BUILDD=${WZBUILD:-/tmp/osum-wzbuild-$(pwd | md5sum | cut -c1-12)}
mkdir -p "$BUILDD" "$OUT"

# ---------------------------------------------------------- 1. der Kern
newer=$(find kernel tools/build-kernel.sh -newer "$BUILDD/k0.mb" -print -quit 2>/dev/null || true)
if [ ! -s "$BUILDD/k0.mb" ] || [ -n "$newer" ] || [ -n "${WZREBUILD:-}" ]; then
    ./tools/build-kernel.sh "$BUILDD/k0.mb" > "$BUILDD/k.log" 2>&1 \
        || { echo "FEHLGESCHLAGEN: der Kern baut nicht"; tail -20 "$BUILDD/k.log"; exit 1; }
fi
echo "kern $(stat -c%s "$BUILDD/k0.mb") Oktette"

# -------------------------------------------------------- 2. Programme
if [ ! -s "$BUILDD/crt.o" ] || [ -n "${WZREBUILD:-}" ]; then
    as --64 -o "$BUILDD/crt.o" kernel/user/crt.s 2>"$BUILDD/as.err" \
        || { echo "FEHLGESCHLAGEN: crt.s"; cat "$BUILDD/as.err"; exit 1; }
fi
USERNEW=$(ls -t kernel/user/*.fi 2>/dev/null | head -1)
for p in $progs; do
    if [ -s "$BUILDD/$p.elf" ] && [ -z "${WZREBUILD:-}" ] \
       && [ "$BUILDD/$p.elf" -nt "kernel/user/$p.fi" ] \
       && [ -n "$USERNEW" ] && [ "$BUILDD/$p.elf" -nt "$USERNEW" ]; then
        continue
    fi
    UPROF=""; UCRT="$BUILDD/crt.o"
    grep -qa '^profile app' "kernel/user/$p.fi" && { UPROF=--profile=app; UCRT=""; }
    vendor/firn/bin/firnc $UPROF -c "kernel/user/$p.fi" -o "$BUILDD/$p.o" \
        > "$BUILDD/e-$p" 2>&1 \
        || { echo "FEHLGESCHLAGEN beim Uebersetzen von $p"; head -25 "$BUILDD/e-$p"; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
        -o "$BUILDD/$p.elf" $UCRT "$BUILDD/$p.o" 2>"$BUILDD/ld.err" \
        || { echo "FEHLGESCHLAGEN beim Binden von $p"; cat "$BUILDD/ld.err"; exit 1; }
    strip --strip-all "$BUILDD/$p.elf"
done
echo "programme $(echo $progs | wc -w)"

# ------------------------------------------------------------ 3. Platte
python3 tools/k15/tree.py "$OUT/baum" > "$OUT/baum.log" 2>&1 || exit 1

printf '# taskbar.conf -- tools/toolbench/build.sh\nedge=bottom\nheight=28\nwidth=104\nautohide=0\nontop=1\nalign=left\n' \
    > "$OUT/taskbar.conf"
printf '# /etc/theme.conf\nscheme=day\nmode=%s\naccent=\nshape=%s\nlight_start=07:00\ndark_start=19:00\n' \
    "$mode" "$shape" > "$OUT/theme.conf"
printf '# /etc/time.conf\noffset=120\n' > "$OUT/time.conf"
printf '# /etc/locale.conf\nlang=%s\n' "$lang" > "$OUT/locale.conf"
printf 'root:x:0:0:root:/users/osum:/bin/sh\n' > "$OUT/passwd"
printf '%s\n' "$lang" > "$OUT/userlocale"

#     programme 15
#     FEHLGESCHLAGEN: mkfs
#     mkfs: the disk is full
#
ARGS=(build "$OUT/disk.img" 65536 --v3 --inodes=512 /lib/
      "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
      "/lib/icons.ttf=assets/osum-icons.ttf")
ARGS+=(/bin/ /dev/ /mnt/)
for p in $progs; do ARGS+=("/bin/$p=$BUILDD/$p.elf"); done
ARGS+=("/bin/files@/bin/explorer")
printf 'on\n' > "$OUT/uitrace"
ARGS+=(/etc/
       "/etc/uitrace=$OUT/uitrace@0644"
       "/etc/theme.conf=$OUT/theme.conf@0644"
       "/etc/time.conf=$OUT/time.conf@0644"
       "/etc/locale.conf=$OUT/locale.conf@0644"
       "/etc/passwd=$OUT/passwd@0644"
       "/etc/taskbar.conf=$OUT/taskbar.conf@0644")
if [ -n "$flaky" ]; then
    printf '%s\n' "$flaky" > "$OUT/themeflaky"
    ARGS+=("/etc/themeflaky=$OUT/themeflaky@0644")
fi
if [ -n "$svcstate" ]; then
    ARGS+=(/run/ "/run/svc.state=$svcstate@0644")
fi
ARGS+=(/etc/schemas/)
for s in assets/schemes/*.scheme; do
    ARGS+=("/etc/schemas/$(basename "$s" .scheme)=$s@0644")
done
ARGS+=(/etc/shapes/)
for s in assets/shapes/*.shape; do
    ARGS+=("/etc/shapes/$(basename "$s" .shape)=$s@0644")
done
ARGS+=(/etc/themes/)
for s in assets/themes/*.preset; do
    ARGS+=("/etc/themes/$(basename "$s" .preset)=$s@0644")
done
ARGS+=(/etc/netview/)
for s in assets/netview/*.txt; do
    n=$(basename "$s" .txt)
    if python3 tools/k15/icon.py "$s" "$OUT/ic-$n" >/dev/null 2>&1; then
        ARGS+=("/etc/netview/$n=$OUT/ic-$n@0644")
    fi
done
ARGS+=(/usr/ /usr/share/ /usr/share/locale/
       /usr/share/locale/en/ "/usr/share/locale/en/messages=locale/en/messages"
       /usr/share/locale/de/ "/usr/share/locale/de/messages=locale/de/messages")
[ -e locale/en/icons ] && ARGS+=("/usr/share/locale/en/icons=locale/en/icons")
[ -e locale/de/icons ] && ARGS+=("/usr/share/locale/de/icons=locale/de/icons")
ARGS+=(/users/ "/users/osum/" "/users/osum/config/"
       "/users/osum/config/locale=$OUT/userlocale@0644")
rm -rf "$OUT/apps"
cp -a assets/apps "$OUT/apps"
for b in "$OUT/apps"/*.osp; do
    [ -d "$b" ] || continue
    n=$(basename "$b" .osp)
    ziel=$(grep -aoE '^[a-z]+' /dev/null || true)
    keep=no
    for p in $progs; do
        [ "$p" = "$n" ] && keep=yes
    done
    case "$n" in
        files) keep=yes ;;
        terminal) keep=yes ;;
    esac
    [ "$keep" = yes ] || rm -rf "$b"
done
while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py "$OUT/apps" "$OUT/buendel" 2>/dev/null || true)
while read -r z; do ARGS+=("$z"); done < "$OUT/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$OUT/mkfs.log" 2>&1 \
    || { echo "FEHLGESCHLAGEN: mkfs"; tail -20 "$OUT/mkfs.log"; exit 1; }
echo "platte $(stat -c%s "$OUT/disk.img") Oktette"

# ------------------------------------------------------------ 4. starten
ACC=()
[ "$accel" = kvm ] && ACC=(-accel kvm)
SOCK="$OUT/mon.sock"; rm -f "$SOCK" "$OUT/serial.txt"
if [ -n "$script" ]; then
    APPEND="osum nokbd nosched noproc nofs script=$script $extra"
    WAITFOR='^kernel: done'
elif [ "$desk" = yes ]; then
    WA=""; [ -n "$app" ] && WA="wigapp=$app"
    APPEND="gfx wm wig desk wmhold wiglong wmdauer $WA nokbd nosched noproc nofs $extra"
    if [ -n "$app" ]; then
        WAITFOR="^desk: start ${app%%,*} "
    else
        WAITFOR='^wm: hold'
    fi
else
    APPEND="gfx wm wig wmhold wiglong wmdauer wigapp=$app nokbd nosched noproc nofs $extra"
    WAITFOR='^wm: hold|^k15: start'
fi
T0=$(date +%s%N)
SECOND=()
if [ -n "$second" ]; then
    cp "$second" "$OUT/second.img"
    SECOND=(-drive "file=$OUT/second.img,format=raw,if=ide,index=1")
fi
timeout "$last" qemu-system-x86_64 "${ACC[@]}" -kernel "$BUILDD/k0.mb" -m 512 \
    -smp "$smp" -append "$APPEND" \
    -serial "file:$OUT/serial.txt" -display none -no-reboot -vga std \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$OUT/disk.img,format=raw,if=ide,index=0" "${SECOND[@]}" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$OUT/qemu.log" 2>&1 &
PID=$!
i=0
while [ $i -lt 2000 ]; do
    grep -qaE "$WAITFOR" "$OUT/serial.txt" 2>/dev/null && break
    kill -0 "$PID" 2>/dev/null || break
    sleep 0.15; i=$((i+1))
done
sleep "$wait_s"
if [ -n "$clicks" ]; then
    python3 tools/themestore/click.py $clicks > "$OUT/mon.txt" 2>"$OUT/click.err"
    python3 tools/wm/monitor.py "$SOCK" "$OUT/mon.txt" > "$OUT/click.log" 2>&1
    sleep 2
fi
# ------------------------------------------------------------ 4b. der Plan
#
if [ -n "$plan" ] && [ -f "$plan" ]; then
    python3 tools/toolbench/fahren.py "$SOCK" "$plan" "$OUT/serial.txt" "$OUT" \
        2>&1 | tee "$OUT/plan.log"
fi
if [ -n "$shot" ]; then
    python3 tools/gfx/screenshot.py "$SOCK" "$OUT/$shot.ppm" 25 > "$OUT/shot.log" 2>&1
fi
if [ -n "$shots" ]; then
    vor=0
    for e in ${shots//,/ }; do
        sek=${e%@*}; nam=${e#*@}
        d=$(( sek - vor )); [ "$d" -gt 0 ] && sleep "$d"
        vor=$sek
        python3 tools/gfx/screenshot.py "$SOCK" "$OUT/$nam.ppm" 25 \
            >> "$OUT/shot.log" 2>&1
    done
fi
[ -n "$script" ] || kill "$PID" 2>/dev/null
wait "$PID"; RC=$?
T1=$(date +%s%N)
rm -f "$SOCK"
echo "qemu ende $RC  accel $accel  smp $smp  dauer $(( (T1-T0)/1000000 )) ms"
for f in "$OUT"/*.ppm; do
    [ -s "$f" ] || continue
    python3 - "$f" <<'PY'
import sys, os
from PIL import Image
p = sys.argv[1]
im = Image.open(p).convert("RGB")
im.save(p[:-4] + ".png")
print("bild %s %dx%d farben %d" % (os.path.basename(p), im.size[0], im.size[1],
      len(im.getcolors(maxcolors=1 << 24) or [])))
PY
done
exit 0
