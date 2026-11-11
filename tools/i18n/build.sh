#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
#   bash tools/i18n/build.sh [ausgabeverzeichnis] [--stufe 0|1]
#
#
#
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/sync/gc.sh   # r278: FIRN_FUNCTION_SECTIONS + ld --gc-sections (OSUM_NO_GC=1 = off)
export FIRNLIB="$(pwd)/lib"

OUT=/tmp/i18n
STUFE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --stufe) STUFE=$2; shift 2 ;;
        *) OUT=$1; shift ;;
    esac
done
mkdir -p "$OUT"

. tools/lib/firnenv.sh
firnenv_need_firnc1
if [[ $STUFE == 0 ]]; then CC=${FIRNC:-"$FIRNC"}
else CC=${FIRNC1:-"$FIRNC1"}; OPTL="$OPTL1"; fi

PROGS="desktop taskbar settings launcher explorer i18nt \
       sh echo ls cat"

bash tools/build-kernel.sh "$OUT/k.mb" --stufe "$STUFE" > "$OUT/k.log" 2>&1 || {
    echo "== the kernel cannot be built"; tail -20 "$OUT/k.log"; exit 1; }
echo "   kern      $(stat -c%s "$OUT/k.mb") Oktette"

as --64 -o "$OUT/crt.o" kernel/user/crt.s || exit 1
rc=0
for p in $PROGS; do
    UPROF=""; UCRT="$OUT/crt.o"
    grep -qa '^profile app' "kernel/user/$p.fi" && { UPROF=--profile=app; UCRT=""; }
    if ! "$CC" $UPROF $OPTL -c "kernel/user/$p.fi" -o "$OUT/$p.o" > "$OUT/$p.err" 2>&1; then
        echo "== $p: der Uebersetzer sagt nein"; head -25 "$OUT/$p.err"
        rc=1; continue
    fi
    if ! ld $GCS -T kernel/user/user.ld --defsym=USER_ENTRY="_F$STUFE.u_start" \
            -o "$OUT/$p.elf" $UCRT "$OUT/$p.o" 2> "$OUT/$p.lderr"; then
        echo "== $p: der Binder sagt nein"; head -12 "$OUT/$p.lderr"
        rc=1; continue
    fi
    strip --strip-all "$OUT/$p.elf"
    printf '   %-14s %7d Oktette\n' "$p" "$(stat -c%s "$OUT/$p.elf")"
done
[ "$rc" = 0 ] || exit 1

cat > "$OUT/theme" <<'EOF'
bg=1E2228
fg=E6E6E6
panel=2A2F37
btn=39404A
line=4A515C
EOF
cat > "$OUT/passwd" <<'EOF'
root:x:0:0:root:/:/bin/sh
justin:x:1000:1000:Justin:/users/justin:/bin/sh
EOF
printf 'en\n' > "$OUT/locale-en"
printf 'de\n' > "$OUT/locale-de"

# 16384 BLOCKS AND NOT 4096. mkfs' block is 512 octets, so this is
# 8 MiB and used to be 2. Round LOOK made the three programs of the
# desktop considerably bigger -- the shape tokens and the rounded,
# antialiased drawing in settings, the icon glyphs and the second
# status field in the taskbar, and a message catalogue that went
# from 72 keys to 154:
#
#     settings  384200 -> 565248     taskbar  278032 -> 371248
#     desktop   181568 -> 249368     (+342 KiB together)
#
# and the image stopped fitting. The failure is loud but it is loud
# in the WRONG PLACE: `mkfs: the disk is full`, then twenty-nine
# assertions about drag, autohide and the settings page fail because
# there was no image to boot. tools/look/shot.sh and
# tools/netview/run.sh were already on 8192 for the same set of
# programs, which is why they did not notice.
#
# ROUND USBIMG found the same wall independently and set 12288; this
# line stays at 16384 -- the larger of the two -- and the finding of
# that round is kept because it names a second cause: `/bin/explorer`
# at 485,392 octets. Measured there on 28.08.2026, and the predecessor
# `mergeline` (3e92c27) failed the same way, so it is older than either
# round.
# ROUND ROADMAP-7: 24576 (12 MiB). The six programs plus the kernel's
# fonts passed 8 MiB when the settings window got its fourteenth page
# (Protokoll) -- the same wall, the same loud wrong place.
ARGS=(build "$OUT/disk.img" 24576 /lib/
      "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
      /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$OUT/$p.elf"); done
ARGS+=(/etc/ "/etc/theme=$OUT/theme" "/etc/passwd=$OUT/passwd")
printf 'on\n' > "$OUT/uitrace"
ARGS+=("/etc/uitrace=$OUT/uitrace")
# DIE SPRACHDATEIEN. /usr/share/locale/<code>/messages -- englische
# Pfade, ISO-639-Codes als Verzeichnisnamen.
ARGS+=(/usr/ /usr/share/ /usr/share/locale/
       /usr/share/locale/en/ "/usr/share/locale/en/messages=locale/en/messages"
       /usr/share/locale/de/ "/usr/share/locale/de/messages=locale/de/messages")
ARGS+=(/users/ /users/root/ /users/root/config/
       "/users/root/config/locale=$OUT/locale-${LANG_SET:-en}")
bash tools/mkfsfi/mkfs.sh "${ARGS[@]}" > "$OUT/mkfs.log" 2>&1 || {
    echo "== mkfs.py fehlgeschlagen"; tail -20 "$OUT/mkfs.log"; exit 1; }
echo "   abbild    $(stat -c%s "$OUT/disk.img") Oktette (Sprache: ${LANG_SET:-en})"
exit 0
