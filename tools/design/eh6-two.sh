#!/usr/bin/env bash
#
#   bash tools/design/eh5.sh <ausgabeverzeichnis> [key=value ...]
#
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

OUT=${1:?usage: eh5.sh <outdir> [key=value ...]}
shift || true
mkdir -p "$OUT"

res=1920x1080
uiscale=1
mode=dark
scheme=day
dark_scheme=midnight
accent=""
lang=en
halt=0
drehbuch=""
accel=auto
nurbau=nein
ton=nein
netz=nein
usb=ja
extra=""
progs="desktop taskbar settings launcher explorer netview taskmgr \
edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc \
find du chmod id whoami touch true false sleep kill sort uniq rmdir \
theme locate dhcp host ping netstat"

for a in "$@"; do
    case "$a" in
        res=*) res=${a#*=} ;;
        uiscale=*) uiscale=${a#*=} ;;
        mode=*) mode=${a#*=} ;;
        scheme=*) scheme=${a#*=} ;;
        dark_scheme=*) dark_scheme=${a#*=} ;;
        accent=*) accent=${a#*=} ;;
        lang=*) lang=${a#*=} ;;
        halt=*) halt=${a#*=} ;;
        drehbuch=*) drehbuch=${a#*=} ;;
        accel=*) accel=${a#*=} ;;
        progs=*) progs=${a#*=} ;;
        nurbau=*) nurbau=${a#*=} ;;
        ton=*) ton=${a#*=} ;;
        netz=*) netz=${a#*=} ;;
        usb=*) usb=${a#*=} ;;
        extra=*) extra=${a#*=} ;;
        *) echo "unbekannt: $a" >&2; exit 2 ;;
    esac
done
XRES=${res%x*}
YRES=${res#*x}
SKAL=""
if [ -n "$uiscale" ] && [ "$uiscale" != 1 ]; then SKAL="uiscale=$uiscale"; fi

BUILDD=${DESIGNBUILD:-/tmp/osum-eh5build-$(pwd | md5sum | cut -c1-12)}
mkdir -p "$BUILDD"

# ---------------------------------------------------------- 1. bauen
bash vendor/firn/fetch-firnc.sh > "$BUILDD/fetch.log" 2>&1 || {
    echo "FEHLGESCHLAGEN: fetch-firnc.sh"; tail -5 "$BUILDD/fetch.log"; exit 1; }
newer=$(find kernel tools/build-kernel.sh -newer "$BUILDD/k0.mb" -print -quit 2>/dev/null || true)
if [ ! -s "$BUILDD/k0.mb" ] || [ -n "$newer" ] || [ -n "${DESIGNREBUILD:-}" ]; then
    ./tools/build-kernel.sh "$BUILDD/k0.mb" > "$BUILDD/k.log" 2>&1 \
        || { echo "FEHLGESCHLAGEN: der Kern baut nicht"; tail -25 "$BUILDD/k.log"; exit 1; }
fi
echo "kernel $(stat -c%s "$BUILDD/k0.mb") Oktette"

if [ ! -s "$BUILDD/crt.o" ] || [ -n "${DESIGNREBUILD:-}" ]; then
    as --64 -o "$BUILDD/crt.o" kernel/user/crt.s 2>"$BUILDD/as.err" \
        || { echo "FEHLGESCHLAGEN: crt.s"; cat "$BUILDD/as.err"; exit 1; }
fi
USERNEW=$(ls -t kernel/user/*.fi 2>/dev/null | head -1)
GEBAUT=""
for p in $progs; do
    [ -f "kernel/user/$p.fi" ] || { echo "   (uebersprungen, keine Quelle: $p)"; continue; }
    if [ -s "$BUILDD/$p.elf" ] && [ -z "${DESIGNREBUILD:-}" ] \
       && [ "$BUILDD/$p.elf" -nt "kernel/user/$p.fi" ] \
       && [ -n "$USERNEW" ] && [ "$BUILDD/$p.elf" -nt "$USERNEW" ]; then
        GEBAUT="$GEBAUT $p"; continue
    fi
    UPROF=""; UCRT="$BUILDD/crt.o"
    grep -qa '^profile app' "kernel/user/$p.fi" && { UPROF=--profile=app; UCRT=""; }
    vendor/firn/bin/firnc $UPROF -c "kernel/user/$p.fi" -o "$BUILDD/$p.o" \
        > "$BUILDD/e-$p" 2>&1 \
        || { echo "FEHLGESCHLAGEN beim Uebersetzen von $p"; head -30 "$BUILDD/e-$p"; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
        -o "$BUILDD/$p.elf" $UCRT "$BUILDD/$p.o" 2>"$BUILDD/ld.err" \
        || { echo "FEHLGESCHLAGEN beim Binden von $p"; cat "$BUILDD/ld.err"; exit 1; }
    strip --strip-all "$BUILDD/$p.elf"
    GEBAUT="$GEBAUT $p"
done
echo "programme $(echo $GEBAUT | wc -w)"

GEBAUT_APP=""
for p in ${APPS:-fetch}; do
    [ -f "kernel/app/$p.fi" ] || continue
    if FIRNLIB="$ROOT/lib" vendor/firn/bin/firnc -c --profile=app \
            -o "$BUILDD/app-$p.o" "kernel/app/$p.fi" \
            > "$BUILDD/app-$p.err" 2>&1 \
       && ld -T kernel/user/user.ld -o "$BUILDD/$p.elf" \
            "$BUILDD/app-$p.o" 2> "$BUILDD/app-$p.lderr"; then
        strip --strip-all "$BUILDD/$p.elf"
        GEBAUT_APP="$GEBAUT_APP $p"
    else
        echo "   (app $p baut nicht -- $(head -1 "$BUILDD/app-$p.err" 2>/dev/null))"
    fi
done
[ -n "$GEBAUT_APP" ] && echo "apps       $(echo $GEBAUT_APP | wc -w)"

# ------------------------------------------------------------ 2. Platte
python3 tools/k15/tree.py "$OUT/baum" > "$OUT/baum.log" 2>&1 || exit 1
printf '# taskbar.conf\nedge=bottom\nwidth=104\nautohide=0\nontop=1\nalign=left\n' \
    > "$OUT/taskbar.conf"
{
  printf '# /etc/theme.conf\nscheme=%s\n' "$scheme"
  [ -n "$dark_scheme" ] && printf 'dark_scheme=%s\n' "$dark_scheme"
  printf 'mode=%s\naccent=%s\nshape=osum\nlight_start=07:00\ndark_start=19:00\n' \
    "$mode" "$accent"
} > "$OUT/theme.conf"
printf '# /etc/time.conf\noffset=120\n' > "$OUT/time.conf"
printf 'lang=%s\n' "$lang" > "$OUT/locale.conf"
printf 'on\n' > "$OUT/uitrace"
cat > "$OUT/passwd" <<'EOF'
root:x:0:0:root:/users/justin:/bin/sh
justin:x:1000:1000:Justin:/users/justin:/bin/sh
EOF
printf '%s\n' "$lang" > "$OUT/userlocale"

ARGS=(build "$OUT/disk.img" 65536 --v3 --inodes=1024 "--time=$(date +%s)" /lib/
      "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
      "/lib/icons.ttf=assets/osum-icons.ttf" /bin/)
for p in $GEBAUT; do ARGS+=("/bin/$p=$BUILDD/$p.elf"); done
for p in $GEBAUT_APP; do ARGS+=("/bin/$p=$BUILDD/$p.elf"); done
ARGS+=("/bin/files@/bin/explorer")
ARGS+=(/etc/
       "/etc/theme.conf=$OUT/theme.conf@0644"
       "/etc/time.conf=$OUT/time.conf@0644"
       "/etc/locale.conf=$OUT/locale.conf@0644"
       "/etc/passwd=$OUT/passwd@0644"
       "/etc/uitrace=$OUT/uitrace@0644"
       "/etc/taskbar.conf=$OUT/taskbar.conf@0644")
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
if python3 tools/netview/icons.py bauen "$OUT/nvicons" > "$OUT/nvicons.log" 2>&1; then
    ARGS+=(/etc/netview/)
    for q in state-nocarrier state-noip state-noroute state-online \
             mark-filtered mark-faked mark-none sys-faking \
             tile-fake tile-net tile-hide; do
        [ -e "$OUT/nvicons/$q" ] && ARGS+=("/etc/netview/$q=$OUT/nvicons/$q")
    done
fi
if python3 tools/hwnet/mkroots.py "$OUT/roots.pem" > "$OUT/roots.log" 2>&1; then
    ARGS+=(/etc/ssl/ "/etc/ssl/roots.pem=$OUT/roots.pem@0644")
    echo "wurzeln    $(stat -c%s "$OUT/roots.pem") Oktette"
fi
ARGS+=(/usr/ /usr/share/ /usr/share/locale/
       /usr/share/locale/en/ "/usr/share/locale/en/messages=locale/en/messages"
       /usr/share/locale/de/ "/usr/share/locale/de/messages=locale/de/messages")
[ -e locale/en/icons ] && ARGS+=("/usr/share/locale/en/icons=locale/en/icons")
[ -e locale/de/icons ] && ARGS+=("/usr/share/locale/de/icons=locale/de/icons")
ARGS+=(/users/ /users/justin/ /users/justin/config/
       "/users/justin/config/locale=$OUT/userlocale@0644")
mkdir -p "$OUT/heim"
printf 'Notizen zur Runde ECHTHARDWARE-5.\n' > "$OUT/heim/notizen.txt"
printf 'a,b,c\n1,2,3\n' > "$OUT/heim/tabelle.csv"
ARGS+=("/users/justin/notizen.txt=$OUT/heim/notizen.txt@0644"
       "/users/justin/tabelle.csv=$OUT/heim/tabelle.csv@0644")
rm -rf "$OUT/apps"; cp -a assets/apps "$OUT/apps"
while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py "$OUT/apps" "$OUT/buendel" "nur=$GEBAUT" 2>/dev/null || true)
while read -r z; do ARGS+=("$z"); done < "$OUT/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$OUT/mkfs.log" 2>&1 \
    || { echo "FEHLGESCHLAGEN: mkfs"; tail -25 "$OUT/mkfs.log"; exit 1; }
echo "platte $(stat -c%s "$OUT/disk.img") Oktette"
[ "$nurbau" = ja ] && exit 0

# ------------------------------------------------------------ 3. starten
#
APPEND="osum gfx fbres=${XRES}x${YRES} wm wig desk wmshell wmdauer tafel herz"
APPEND="$APPEND absturzhalt nopuls tz=120 lang=$lang nosched noproc nofs"
[ -n "$SKAL" ] && APPEND="$APPEND $SKAL"
[ "$halt" != 0 ] && APPEND="$APPEND wighalt=$halt"
[ -n "$extra" ] && APPEND="$APPEND $extra"
echo "append  $APPEND"

SOCK="$OUT/mon.sock"; rm -f "$SOCK" "$OUT/serial.txt"
TONDEV=()
if [ "$ton" = ja ]; then
    APPEND="$APPEND audio nosounds"
    TONDEV=(-audiodev none,id=snd0 -device intel-hda
            -device hda-duplex,audiodev=snd0)
fi
#
NETDEV=()
if [ "$netz" = ja ]; then
    NETDEV=(-netdev user,id=n0 -device e1000,netdev=n0)
    APPEND="$APPEND nic nip=169.254.10.1/16 nsvc=0 nwait=0 dhcp"
fi
#
#     usb: skipped
#     tafel: 18 KEYS  D 0
#
USBDEV=()
if [ "$usb" = ja ]; then
    USBDEV=(-device qemu-xhci,id=x0
            -device usb-kbd,bus=x0.0
            -device usb-mouse,bus=x0.0 -device usb-tablet,bus=x0.0)
    APPEND="$APPEND usb"
fi
ACC=()
if [ "$accel" = kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACC=(-accel kvm -cpu host)
fi
timeout 900 qemu-system-x86_64 "${ACC[@]}" -kernel "$BUILDD/k0.mb" -m 512 \
    -append "$APPEND" \
    -serial "file:$OUT/serial.txt" -display none -no-reboot \
    -device "VGA,edid=on,xres=$XRES,yres=$YRES,vgamem_mb=32" \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$OUT/disk.img,format=raw,if=ide,index=0" \
    "${TONDEV[@]}" "${NETDEV[@]}" "${USBDEV[@]}" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$OUT/qemu.log" 2>&1 &
PID=$!
i=0
while [ $i -lt 3000 ]; do
    grep -qaE 'launcher: ready|taskbar: ready|wm: dauer' "$OUT/serial.txt" 2>/dev/null && break
    kill -0 "$PID" 2>/dev/null || break
    sleep 0.15; i=$((i+1))
done
if ! grep -qaE 'launcher: ready|taskbar: ready|wm: dauer' "$OUT/serial.txt" 2>/dev/null; then
    echo "FEHLGESCHLAGEN: der Schreibtisch ist nie hochgekommen"
    tail -25 "$OUT/serial.txt" 2>/dev/null
fi

if [ -n "$drehbuch" ]; then
    python3 -u tools/design/drive.py "$SOCK" "$OUT/serial.txt" "$OUT" "$drehbuch" \
        2>&1 | tee "$OUT/fahren.log"
fi

printf 'quit\n' | timeout 5 socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1 || true
sleep 0.5
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null
echo "fertig: $(ls "$OUT"/*.ppm 2>/dev/null | wc -l) Bilder"
