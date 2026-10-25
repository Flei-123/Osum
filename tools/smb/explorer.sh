#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/smb/explorer.sh -- the file manager opens smb://10.9.0.1/data in the OrientOS guest (QEMU, e1000) against Samba in a netns.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

NS=smbx-$$
V0=sx0-$$
V1=sx1
QPORT=$(( 14000 + ($$ % 400) * 2 ))
BPORT=$(( QPORT + 1 ))
TMPD=$(mktemp -d)
chmod 755 "$TMPD"
. tools/smb/samba.sh
. tools/smb/wire.sh
cleanup() {
    wire_down
    rm -rf "$TMPD"
}
trap cleanup EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaE "$2" "$1" && ok "$3" || bad "$3 -- '$2' is missing"; }
hasnot() { grep -qaE "$2" "$1" && bad "$3 -- '$2' is present" || ok "$3"; }

for t in qemu-system-x86_64 ip smbd smbpasswd gcc python3; do
    command -v "$t" >/dev/null 2>&1 || command -v "/usr/sbin/$t" >/dev/null 2>&1 || { echo "SMBEXPLORER: skipped, $t is missing"; exit 0; }
done
export PATH="$PATH:/usr/sbin"
python3 -c "import PIL" 2>/dev/null || { echo "SMBEXPLORER: skipped, Pillow is missing"; exit 0; }
ip netns add "$NS" 2>/dev/null || { echo "SMBEXPLORER: skipped, no network namespaces"; exit 0; }
ip netns del "$NS" 2>/dev/null

echo "== 1. build: smbctl, kernel, programs =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
if vendor/firn/bin/firnc -c --profile=app -o "$TMPD/smbctl.o" kernel/app/smbctl.fi > "$TMPD/cc.log" 2>&1 \
   && ld -T kernel/user/user.ld -o "$TMPD/smbctl.elf" "$TMPD/smbctl.o" 2>"$TMPD/ld.err"; then
    strip --strip-all "$TMPD/smbctl.elf" 2>/dev/null
    ok "smbctl builds as a ring-3 app"
else
    bad "smbctl does not build"; head -10 "$TMPD/cc.log" "$TMPD/ld.err"; echo "SMBEXPLORER: $pass passed, $fail failed"; exit 1
fi
gcc -O2 -o "$TMPD/bridge" tools/net/bridge.c 2>/dev/null || bad "bridge.c"
export DESIGNBUILD=${DESIGNBUILD:-$TMPD/db}

samba_setup "$TMPD/smb" 445
SMB_PREFIX="ip netns exec $NS"
SMB_BIND=10.9.0.1
printf 'sub file\n' > "$SHARE/sub/inner.txt"
WANT_HELLO=$(stat -c%s "$SHARE/hello.txt")

KARGS="nostart wigapp=/bin/explorer nic nip=10.9.0.2/24 ngw=10.9.0.1 nsvc=0 nwait=0"
QARGS="-netdev socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT -device e1000,netdev=n0,mac=52:54:00:aa:bb:cc"

run_case() { # <name> <script> <image files>
    wire_up
    samba_conf auto; samba_user
    samba_start auto || { bad "$1: samba did not start"; head -3 "$TMPD/smb/smbd.out"; }
    bash tools/design/capture.sh "$TMPD/$1" res=1280x800 uitrace=yes lang=en \
        extra="$KARGS" qemuargs="$QARGS" imgfiles="$3" drehbuch="$2" > "$TMPD/$1.log" 2>&1
    [ -n "${SMB_KEEP:-}" ] && { mkdir -p "$SMB_KEEP/$1"; cp "$TMPD/$1/serial.txt" "$TMPD/$1"/*.png "$TMPD/$1.log" "$SMB_KEEP/$1/" 2>/dev/null; }
    wire_down
}

cat > "$TMPD/walk.txt" <<'DREH'
warteauf explorer: ready || 300
warte 8
taste ctrl-l
warte 2
taste backspace
taste backspace
taste backspace
taste backspace
taste backspace
taste backspace
taste backspace
taste backspace
taste backspace
taste backspace
taste backspace
taste backspace
tippe smb://10.9.0.1/data
taste ret
warteauf expsmb: dialog user || 120
warte 2
foto 10-user
tippe gateuser
taste ret
warteauf expsmb: dialog pass || 60
warte 2
foto 11-pass
tippe wrongpass
taste ret
warteauf expsmb: list rc=3 || 120
warteauf expsmb: dialog user-retry || 60
warte 2
foto 12-retry
tippe gateuser
taste ret
warteauf expsmb: dialog pass || 60
tippe gatepass
taste ret
warteauf expsmb: list rc=0 entries=3 || 120
warte 4
foto 13-listing
doppelauf ftabzeile2
warteauf expsmb: fetch rc=0 || 120
warte 4
foto 14-opened
DREH

echo "== 2. explorer walk: smb:// -> user -> wrong password -> retry -> listing -> open file =="
run_case walk "$TMPD/walk.txt" "/tmp/ /bin/smbctl=$TMPD/smbctl.elf"
W="$TMPD/walk/serial.txt"
if [ ! -s "$W" ]; then bad "no serial output"; tail -20 "$TMPD/walk.log"; fi
hasnot "$W" '^panic' "no panic in the guest"
has "$W" 'explorer: ready' "the file manager is up"
has "$W" 'expsmb: dialog user$' "first: the user dialog opens"
has "$W" 'expsmb: dialog pass$' "then the password dialog opens"
has "$W" 'expsmb: list rc=3$' "wrong password: smbctl exits 3 (auth) in the guest"
has "$W" 'expsmb: dialog user-retry$' "wrong password: the user dialog comes back as a retry"
has "$W" 'expsmb: list rc=0 entries=3$' "right password: listing with 3 entries (sub, big.bin, hello.txt)"
has "$W" "expsmb: fetch rc=0 octets=$WANT_HELLO\$" "double click on hello.txt: fetched $WANT_HELLO octets"
hasnot "$W" 'expsmb: dialog error' "no error dialog on the good path"
grep -aoE 'expsmb: list rc=[0-9]+' "$W" | head -3 | tr '\n' ' ' | sed 's/^/  list results: /'; echo

echo "== 3. counter-proof: image without /bin/smbctl =="
cat > "$TMPD/noctl.txt" <<'DREH'
warteauf explorer: ready || 300
warte 8
taste ctrl-l
warte 2
taste backspace
taste backspace
taste backspace
taste backspace
taste backspace
taste backspace
taste backspace
taste backspace
taste backspace
taste backspace
taste backspace
taste backspace
tippe smb://10.9.0.1/data
taste ret
warteauf expsmb: dialog user || 120
tippe gateuser
taste ret
warteauf expsmb: dialog pass || 60
tippe gatepass
taste ret
warteauf expsmb: list rc=255 || 120
warte 5
foto 20-failed
DREH
run_case noctl "$TMPD/noctl.txt" "/tmp/"
N="$TMPD/noctl/serial.txt"
has "$N" 'expsmb: list rc=255$' "no helper: the list fails with 255, no listing"
has "$N" 'expsmb: dialog error$' "no helper: the error dialog opens"
hasnot "$N" 'expsmb: list rc=0' "no helper: no list ever succeeds"

echo "SMBEXPLORER: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
