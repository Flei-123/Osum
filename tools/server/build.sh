#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

OUT=${1:-/tmp/osum-server}
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/lock.sh" && osum_sperre "$OUT"   # A-024
GUI=off
shift || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --gui) GUI=$2; shift 2 ;;
        *) echo "unbekannte Option: $1" >&2; exit 1 ;;
    esac
done

PROGS=${PROGS:-"sh ls cat echo cp mv rm mkdir rmdir touch head tail wc \
grep sort uniq cut tr seq tee xargs true false sleep ps kill uname date \
df du find which basename dirname chmod chown id whoami su login passwd \
mount umount sync tar gzip gunzip diff patch sed env top \
netstat ping wget opk power hwid locate edit \
init svc sshd dhcp ctr ota backup sntp host dnswt reboot shutdown"}

mkdir -p "$OUT/bin"

. tools/lib/firnenv.sh
CC=$FIRNC

bash tools/build-kernel.sh "$OUT/k.mb" --gui "$GUI" > "$OUT/k.log" 2>&1 || {
    echo "== the kernel cannot be built"; tail -30 "$OUT/k.log"; exit 1; }

as --64 -o "$OUT/crt.o" kernel/user/crt.s || exit 1
rc=0
gebaut=""
for p in $PROGS; do
    [ -f "kernel/user/$p.fi" ] || continue
    UPROF=""; UCRT="$OUT/crt.o"
    grep -qa '^profile app' "kernel/user/$p.fi" && { UPROF=--profile=app; UCRT=""; }
    if ! "$CC" $UPROF -c "kernel/user/$p.fi" -o "$OUT/$p.o" > "$OUT/$p.err" 2>&1; then
        echo "== $p: der Uebersetzer sagt nein"
        head -12 "$OUT/$p.err"
        rc=1
        continue
    fi
    if ! ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
            -o "$OUT/bin/$p" $UCRT "$OUT/$p.o" 2> "$OUT/$p.lderr"; then
        echo "== $p: der Binder sagt nein"
        grep -v 'GNU-stack\|RWX\|deprecated' "$OUT/$p.lderr" | head -5
        rc=1
        continue
    fi
    strip --strip-all "$OUT/bin/$p" 2>/dev/null
    gebaut="$gebaut $p"
done
[ $rc = 0 ] || exit 1

verboten=""
for p in schreibtisch leiste einstellungen explorer launcher widgetdemo \
         tiling themetest dispctl icont; do
    [ -f "$OUT/bin/$p" ] && verboten="$verboten $p"
done
if [ -n "$verboten" ]; then
    echo "== UI programs are on the server disk:$verboten"
    exit 1
fi

printf 'Osum, Serverbau. Kein Bildschirm, eine Leitung.\n' > "$OUT/readme.txt"
cat > "$OUT/inittab" <<'TAB'
# name:targets:kind:command:options
dhcp:*:once:/bin/dhcp
sntp:*:once:/bin/sntp:netz
sshd:konsole:respawn:/bin/sshd -v:netz,log=/var/log/sshd.log
sh:*:ctrl:/bin/sh
TAB
printf 'konsole\n' > "$OUT/ziel"
printf 'osum-server\n' > "$OUT/hostname"
SPEC="/bin/ /etc/ /run/ /var/ /var/log/@755:0:0 /proc/ /tmp/ /root/@700:0:0"
for p in $gebaut; do
    [ "${SERVER_INIT:-on}" = off ] && [ "$p" = init ] && continue
    SPEC="$SPEC /bin/$p=$OUT/bin/$p@755:0:0"
done
SPEC="$SPEC /etc/ziel=$OUT/ziel@644:0:0 /etc/hostname=$OUT/hostname@644:0:0"
[ "${SERVER_INIT:-on}" = off ] || SPEC="$SPEC /etc/inittab=$OUT/inittab@644:0:0"
BLOCKS=${BLOCKS:-20480}
bash tools/mkfsfi/mkfs.sh build "$OUT/disk.img" "$BLOCKS" ${OFSFLAG:---v3} $SPEC \
    /readme.txt="$OUT/readme.txt" > "$OUT/mkfs.txt" 2>&1 || {
    echo "== mkfs.py"; cat "$OUT/mkfs.txt"; exit 1; }

echo "   kern      $(stat -c%s "$OUT/k.mb") Oktette (gui=$GUI)"
echo "   userland  $(echo $gebaut | wc -w) Programme, $(du -sb "$OUT/bin" | cut -f1) Oktette"
echo "   platte    $(stat -c%s "$OUT/disk.img") Oktette, $BLOCKS Bloecke"
