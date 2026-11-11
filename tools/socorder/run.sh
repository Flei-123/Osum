#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }
last_report() { part "$1" ORDERME ORDEREND | grep -a . | tail -n 1; }
fin() { echo "SOCIAL-ORDER: $pass passed, $fail failed"; exit $(( fail > 0 )); }

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
BLOCKS=30000
PROGS="sh ls cat echo sleep mkdir orientbus act social soclocal"
GUEST_PROGS="sh ls cat echo sleep mkdir orientbus act soclocal"
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm

echo "== 1. build =="
. tools/lib/firnenv.sh
[ -x "$FIRNC" ] || { echo "SOCIAL-ORDER: firnc0 missing"; exit 1; }
mkdir -p "$TMPD/bin" "$TMPD/binold" "$TMPD/etc"
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
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "SOCIAL-ORDER: skipped, qemu missing"; fin; }

printf 'lang=de\n' > "$TMPD/etc/locale.conf"
printf 'provider local /bin/soclocal\nprovider slow /bin/soclocal /etc/social/slow\n' > "$TMPD/etc/providers"
printf 'app:game activity.write\n' > "$TMPD/etc/apps"
printf 'c\tpeter\tfriend\tonline\tPeter (LAN)\tpeter\tim Keller\tMinecraft\t60\t\n' > "$TMPD/etc/local.book"
printf 'c\tzed\tfriend\tonline\tZed (slow)\tzed\t\t\t0\t\t0\n' > "$TMPD/etc/slow.book"
printf '2500' > "$TMPD/etc/slow.slowclear"
cat > "$TMPD/s.sh" <<'EOS'
orientbus serve 9500 &
sleep -m 300
social serve 9500 300 60000 &
sleep 2
act call social.presence.set state=dnd
sleep -m 800
act grant app:game social.activity.* write 120
act call social.activity.set "name=Counter-Strike 2" --as app:game
echo ==SETDONE==
sleep 5
echo ==ORDERME==
cat /etc/social/slow.me
echo ==ORDEREND==
EOS

run_guest() {
    local elf=$1 tag=$2
    local files=(build "$TMPD/$tag.img" $BLOCKS /lib/
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/
        /etc/actions.d/ /etc/orientbus/ /etc/social/ /apps/ /apps/social.prog/ /var/ /var/log/
        /usr/ /usr/share/ /usr/share/locale/ /usr/share/locale/de/ /usr/share/locale/en/
        "/etc/locale.conf=$TMPD/etc/locale.conf")
    local p
    for p in $GUEST_PROGS; do files+=("/bin/$p=$TMPD/bin/$p.elf"); done
    files+=("/bin/social=$elf"
        "/apps/social.prog/ACTIONS=pakete/social/ACTIONS"
        "/etc/social/providers=$TMPD/etc/providers"
        "/etc/social/local.book=$TMPD/etc/local.book"
        "/etc/social/slow.book=$TMPD/etc/slow.book"
        "/etc/social/slow.slowclear=$TMPD/etc/slow.slowclear"
        "/etc/social/apps=$TMPD/etc/apps"
        "/t/s.sh=$TMPD/s.sh")
    bash tools/mkfsfi/mkfs.sh "${files[@]}" > "$TMPD/mkfs-$tag.txt" 2>&1 || bad "mkfs ($tag): $(tail -2 "$TMPD/mkfs-$tag.txt")"
    : > "$TMPD/$tag.txt"
    timeout 120 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 \
        -kernel "$TMPD/k0.img" -m 512 \
        -append "osum vfs nokbd bus script=sh /t/s.sh;exit" \
        -serial "file:$TMPD/$tag.txt" -display none -no-reboot \
        -drive "file=$TMPD/$tag.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$TMPD/$tag.txt" > "$TMPD/$tag.klar"
}

echo "== 2. an activity set while a stale clearing report is in flight =="
run_guest "$TMPD/bin/social.elf" fixed
has "$TMPD/fixed.klar" "==ORDEREND==" "the guest reached its end"
[ "$(last_report "$TMPD/fixed.klar")" = "activity Counter-Strike 2" ] \
    && ok "the slow provider's last report is the game, not the stale empty one" \
    || bad "the slow provider's last report is '$(last_report "$TMPD/fixed.klar")'"

echo "== 3. counter-proof: the service without the wait =="
cp -r kernel/user "$TMPD/oldsrc"
sed -i 's/ || background_activity_busy()//' "$TMPD/oldsrc/socujob.fi"
if USRC="$TMPD/oldsrc" bash tools/sync/build.sh "$TMPD/binold" 0 social > "$TMPD/bold.txt" 2>&1; then
    run_guest "$TMPD/binold/social.elf" old
    has "$TMPD/old.klar" "==ORDEREND==" "the counter-proof guest reached its end"
    [ "$(last_report "$TMPD/old.klar")" = "activity" ] \
        && ok "the stale empty report is the last one and overwrites the game" \
        || bad "the counter-proof did not show the overwrite: '$(last_report "$TMPD/old.klar")'"
else
    bad "counter-proof build: $(head -3 "$TMPD/bold.txt")"
fi

fin
