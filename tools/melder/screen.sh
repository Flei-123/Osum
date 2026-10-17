#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/melder/screen.sh -- THE SOCIAL SERVICE AND THE MELDER START ON A SCREEN IMAGE (r140).
#
#   /root/jarvis/bin/heavy bash tools/melder/screen.sh
#
# A screen image has no `init` (see wm_owns_shell in kmain.fi): its session
# starts in kgui.desk_start. r140 makes desk_start start /bin/social and
# /bin/melder after the broker, if the image carries them. Measured here in
# a real guest with the desktop word `desk`:
#
#   1. an image WITH them: the session says `desk: social pid=<n>` and
#      `desk: melder pid=<n>` (after `desk: orientbus pid=`), the service
#      binds to the broker (`orientbus: provider social bound`);
#   2. an image WITHOUT them starts exactly what it started before (no
#      social/melder line), so older images are untouched;
#   3. nothing panics.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }
fin() { echo "MELDER-SCREEN: $pass passed, $fail failed"; exit $(( fail > 0 )); }

TMPD=$(mktemp -d)
[ -n "${MELDER_KEEP:-}" ] || trap 'rm -rf "$TMPD"' EXIT
[ -z "${MELDER_KEEP:-}" ] || trap 'echo "kept $TMPD"' EXIT
BLOCKS=30000
PROGS="sh ls cat echo sleep mkdir orientbus act social soclocal melder"
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
[ -x vendor/firn/bin/firnc ] || { echo "MELDER-SCREEN: firnc0 missing"; exit 1; }
mkdir -p "$TMPD/bin"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then
    ok "firnc0 builds $(echo $PROGS | wc -w) programs"
else
    bad "the programs do not build"; sed 's/^/        /' "$TMPD/b.txt" | head -20; fin
fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then
    ok "the kernel builds"
else
    bad "the kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'; fin
fi
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "MELDER-SCREEN: skipped, qemu missing"; fin; }

mkdir -p "$TMPD/etc"
printf 'lang=de\n' > "$TMPD/etc/locale.conf"
printf 'provider local /bin/soclocal\n' > "$TMPD/etc/providers"
printf 'l\tnap\tNap Quest\n' > "$TMPD/etc/games.tsv"

# $1 = tag, $2 = "with" | "without" the social programs
boot() {
    local tag=$1 with=$2
    local A_=(build "$TMPD/$tag.img" $BLOCKS /lib/
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
        /bin/ /tmp/ /proc/ /dev/ /system/ /etc/ /etc/actions.d/ /etc/orientbus/ /etc/social/
        /apps/ /apps/social.prog/ /var/ /var/log/
        "/etc/locale.conf=$TMPD/etc/locale.conf"
        "/etc/orientbus/policy=etc/orientbus/policy")
    local p
    for p in sh ls cat echo sleep mkdir orientbus act; do A_+=("/bin/$p=$TMPD/bin/$p.elf"); done
    if [ "$with" = with ]; then
        for p in social soclocal melder; do A_+=("/bin/$p=$TMPD/bin/$p.elf"); done
        A_+=("/apps/social.prog/ACTIONS=pakete/social/ACTIONS"
             "/etc/social/providers=$TMPD/etc/providers"
             "/etc/social/games.tsv=$TMPD/etc/games.tsv")
    fi
    python3 tools/osum/mkfs.py "${A_[@]}" > "$TMPD/mkfs-$tag.txt" 2>&1 \
        || { bad "mkfs $tag: $(tail -2 "$TMPD/mkfs-$tag.txt")"; return 1; }
    : > "$TMPD/$tag.ser"
    timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 \
        -kernel "$TMPD/k0.img" -m 768 \
        -append "gfx disp wm wmdauer wmshell osum vfs bus desk nokbd nosched noproc fbres=1280x800" \
        -serial "file:$TMPD/$tag.ser" -display none -no-reboot -vga std \
        -drive "file=$TMPD/$tag.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local qp=$! i=0
    # the session has started its services when the Melder line is there; give them 12 s
    while [ $i -lt 600 ]; do
        grep -qaE 'desk: (melder|social) pid=' "$TMPD/$tag.ser" 2>/dev/null && break
        grep -qa 'desk: orientbus pid=' "$TMPD/$tag.ser" 2>/dev/null && [ "$with" = without ] && [ $i -gt 150 ] && break
        kill -0 "$qp" 2>/dev/null || break
        sleep 0.2; i=$((i + 1))
    done
    sleep 12
    kill "$qp" 2>/dev/null; wait "$qp" 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$TMPD/$tag.ser" > "$TMPD/$tag.klar"
}

echo "== 2. an image with social + melder =="
if boot with with; then
    S="$TMPD/with.klar"
    grep -qaE 'desk: orientbus pid=[1-9]' "$S" && ok "the session starts the broker" || bad "no 'desk: orientbus pid='"
    grep -qaE 'desk: social pid=[1-9]' "$S" && ok "the session starts /bin/social ($(grep -aoE 'desk: social pid=[0-9]+' "$S" | head -1))" \
        || bad "no 'desk: social pid=<n>'"
    grep -qaE 'desk: melder pid=[1-9]' "$S" && ok "the session starts /bin/melder ($(grep -aoE 'desk: melder pid=[0-9]+' "$S" | head -1))" \
        || bad "no 'desk: melder pid=<n>'"
    lb=$(grep -anE 'desk: orientbus pid=' "$S" | head -1 | cut -d: -f1)
    ls_=$(grep -anE 'desk: social pid=' "$S" | head -1 | cut -d: -f1)
    lm=$(grep -anE 'desk: melder pid=' "$S" | head -1 | cut -d: -f1)
    [ -n "$lb" ] && [ -n "$ls_" ] && [ -n "$lm" ] && [ "$lb" -lt "$ls_" ] && [ "$ls_" -lt "$lm" ] \
        && ok "order: broker, then the service, then the Melder" || bad "order broker/social/melder: $lb $ls_ $lm"
    python3 - "$S" <<'PY' && ok "the service is bound as the provider of social.* (bus line)" || bad "no 'orientbus: provider social bound'"
import sys
d = open(sys.argv[1], encoding="latin-1").read()
t = "orientbus: provider social bound"
start = 0
while True:
    i = d.find(t[0], start)
    if i < 0:
        sys.exit(1)
    j, k = i, 0
    while j < len(d) and k < len(t) and j - i < 3 * len(t):
        if d[j] == t[k]:
            k += 1
        j += 1
    if k == len(t):
        sys.exit(0)
    start = i + 1
PY
    grep -qaiE 'panic|double fault' "$S" && bad "the guest panicked" || ok "no panic"
fi
rm -f "$TMPD/with.img"

echo "== 3. an image without them is unchanged =="
if boot without without; then
    S="$TMPD/without.klar"
    grep -qaE 'desk: orientbus pid=[1-9]' "$S" && ok "the broker still starts" || bad "no 'desk: orientbus pid='"
    grep -qaE 'desk: (social|melder) pid=' "$S" && bad "social/melder started on an image that has none" \
        || ok "no social/melder line when the image has no /bin/social"
    grep -qaiE 'panic|double fault' "$S" && bad "the guest panicked" || ok "no panic"
fi
fin
