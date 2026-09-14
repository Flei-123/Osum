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
uitrace=no
autohide=0
accel=tcg
append=""
progs="desktop taskbar settings launcher dhcp explorer widgetdemo locate sh echo ls cat edit"
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
        accel=*) accel=${a#*=} ;;
        append=*) append=${a#*=} ;;
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
    vendor/firn/bin/firnc -c "kernel/user/$p.fi" -o "$BUILDD/$p.o" \
        > "$BUILDD/e-$p" 2>&1 \
        || { echo "FAILED to compile $p"; head -20 "$BUILDD/e-$p"; exit 1; }
    # RUNDE 31: EIN PROGRAMM IM PROFIL `app` BRINGT SEINEN `_start` MIT.
    #
    # Wessen Bedienelemente aus fUi kommen, dessen Wurzeldatei ist
    # `profile app` (fUi rechnet in f64 und benutzt std.rt, beides ist
    # unter `kernel` gesperrt). Unter `app` legt firnc dieselben vier
    # Befehle hinein, die auch in crt.s stehen -- crt.o dazuzubinden
    # waere dann "multiple definition of `_start`".
    #
    # Also: crt.o nur fuer die Programme, die es noch brauchen. Die
    # Unterscheidung wird nicht getippt, sondern GELESEN -- sonst
    # stimmt sie nach der naechsten Umstellung nicht mehr.
    CRT="$BUILDD/crt.o"
    if grep -qa '^profile app' "kernel/user/$p.fi"; then
        CRT=""
    fi
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
        -o "$BUILDD/$p.elf" $CRT "$BUILDD/$p.o" 2>"$BUILDD/ld.err" \
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

# 8192 blocks (4 MiB) held these programs with 4 per cent to spare
# after round LOOK. That is not spare room, that is a countdown.
#
# RUNDE BAUFEHLER (14.09.2026): 16384 -> 32768 Bloecke (8 -> 16 MiB).
# Der Countdown ist abgelaufen. Runde GRUNDLINIE (1d16d34) hat die
# Laeufer -- zu Recht -- auf `--profile=app` umgestellt, und sechs der
# dreizehn Programme dieser Liste tragen `profile app` (desktop,
# taskbar, settings, launcher, explorer, widgetdemo). Das Profil `app`
# bringt Firns volle Laufzeit mit: /bin/explorer ist 1623040 statt
# 907360 Oktette. GEMESSEN, unmittelbar:
#
#     $ bash tools/look/shot.sh /tmp/shottest
#     FAILED: mkfs
#     mkfs: the disk is full
#
# Das traf jeden Laeufer, der ueber diese Datei fotografiert -- SOFTUI
# fiel damit auf "0 bestanden, 2 gefallen" ("classic bootet nicht",
# "modern bootet nicht"), ohne dass am Aussehen irgendetwas falsch war.
# EIN BLOCK IST 512 OKTETTE (tools/osum/mkfs.py, `BS = 512`).
ARGS=(build "$OUT/disk.img" 32768 /lib/
      "/lib/mono.ttf=$MONO" "/lib/sans.ttf=$SANS")
[ "$icons" = yes ] && ARGS+=("/lib/icons.ttf=$ICONF")
ARGS+=(/bin/)
for p in $progs; do ARGS+=("/bin/$p=$BUILDD/$p.elf"); done
ARGS+=("/bin/files@/bin/explorer")
# RUNDE ROTABSCHNITTE: `/bin/speicher` ist der Name, unter dem der
# KERN die Speicherplatzanalyse startet (kgui.fi: p_spei), und der
# hat sich nie geaendert. Die QUELLDATEI heisst seit ENGLISCH
# ETAPPE 7 (9dd8fe4) storage.fi -- gebaut wird also `storage`, und
# der alte Pfad ist ein zweiter Name auf dieselbe Datei. Ohne das
# suchte tools/umlaut/run.sh ein kernel/user/speicher.fi, das es
# nicht mehr gibt ("FAILED to compile speicher"), und drei
# Abschnitte bekamen gar kein Bild.
case " $progs " in *" storage "*) ARGS+=("/bin/speicher@/bin/storage");; esac
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
# ====================================================== RUNDE 32
# /etc/themes -- DER PRUEFSTAND HATTE SIE NICHT, DAS ABBILD SCHON.
#
# Justin, 12.09.2026, zum dritten Mal derselbe Fehler: "der Pruefstand
# ist anders bestueckt als das Abbild, und die Abnahme misst deshalb
# etwas anderes, als der Nutzer bootet." Beim ersten Mal waren es drei
# statt sechs Symboldateien (Runde ECHT-2), beim zweiten die Marke.
#
# Gemessen mit `grep -oP '/etc/\K[a-z]+(?=/)'` gegen beide Skripte:
# das Abbild legt jarvis, netview, schemas, shapes, ssl UND THEMES ab,
# der Pruefstand nur netview, schemas, shapes. `/etc/themes` fehlte --
# das sind die fertigen Voreinstellungen (assets/themes/*.preset), aus
# denen `wlibc` Schema, Modus und Form zusammen liest.
#
# jarvis und ssl bleiben ABSICHTLICH draussen: der Wurzelspeicher und
# die Rechteliste des Helfers gehoeren zu einem Geraet, nicht zu einem
# Bildschirmfoto -- sie stehen deshalb in der Ausnahmeliste von
# tools/look/inventory.sh und nicht hier.
if ls assets/themes/*.preset >/dev/null 2>&1; then
    ARGS+=(/etc/themes/)
    for s in assets/themes/*.preset; do
        ARGS+=("/etc/themes/$(basename "$s" .preset)=$s@0644")
    done
fi
if [ "$nvicons" = yes ]; then
    if python3 tools/netview/icons.py bauen "$OUT/nvicons" > "$OUT/nvicons.log" 2>&1; then
        ARGS+=(/etc/netview/)
        # RUNDE 32: DIESELBE LISTE WIE IM ABBILD, UND ZUM VIERTEN MAL
        # DERSELBE FEHLER.
        #
        # Hier standen ELF Namen, tools/usbimg/build.sh (Zeile 346)
        # nennt aber FUENFZEHN: tile-dark, tile-power und tile-tile
        # fehlten -- genau die Kacheln "Dark mode", "Power" und
        # "Tiling" im Kontrollzentrum. In Runde ECHT-2 war es dieselbe
        # Stelle mit drei statt sechs Dateien.
        #
        # Gefunden hat es diesmal tools/look/inventory.sh, nicht
        # Justin: es zaehlt die Namen in beiden Skripten und schlaegt
        # an, wenn die Zahlen auseinandergehen. Deshalb zaehlt es und
        # prueft nicht nur, ob das Verzeichnis vorkommt -- ein fehlender
        # Name in einer vorhandenen Liste ist unsichtbar.
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
# RUNDE MERGE-2: `-cpu host` von softui, die Pruefung samt Hinweis von
# uns. Ohne `-cpu host` ist der Prozessor `qemu64`, der kein SMAP kann --
# und genau mit SMAP hat softui den fehlenden Gegenpart zu `map_user`
# gefunden. Ohne die Pruefung faellt ein Wirt ohne /dev/kvm still auf
# eine Zeile herein, die er nicht ausfuehren kann.
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
python3 tools/gfx/screenshot.py "$SOCK" "$OUT/desktop.ppm" 25 > "$OUT/shot.log" 2>&1
wait "$PID"; RC=$?
rm -f "$SOCK"
echo "qemu exit $RC"
echo "accel ${ACC[*]:-tcg}"

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
    "$OUT/serial.txt" 2>/dev/null | head -140
if [ "$keep" = no ]; then rm -f "$OUT/disk.img" "$OUT"/*.o 2>/dev/null; fi
exit 0
