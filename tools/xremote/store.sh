#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
. tools/lib/qemu.sh
. tools/lib/firnenv.sh

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is present" || ok "$3"; }

TOOLS=${XR_TOOLS:-/root/jarvis/data/orientos-xremote}
HOSTBIN=${XR_HOST:-$TOOLS/v2/freeviewer-host}
LIBS=${XR_LIBS_DIR:-/root/fxhp/fx-root}
OPK=$(python3 tools/lib/opkpfad.py)
for t in qemu-system-x86_64 python3 musl-gcc curl; do
    command -v "$t" >/dev/null 2>&1 || { echo "XRSTORE: skipped, $t is missing"; exit 0; }
done
for f in "$HOSTBIN" "$LIBS/lib/ld-musl-x86_64.so.1" "$LIBS/usr/lib/libgcc_s.so.1" "$OPK"; do
    [ -e "$f" ] || { echo "XRSTORE: skipped, $f missing"; exit 0; }
done

TMPD=$(mktemp -d)
SRVPIDS=""
cleanup() { for p in $SRVPIDS; do kill "$p" 2>/dev/null; done; [ -n "${XRSTORE_KEEP:-}" ] || rm -rf "$TMPD"; }
trap cleanup EXIT
BLOCKS=${BLOCKS:-60000}
export OSUM_CPU=${OSUM_CPU:-Haswell}
PROGS="sh ls cat echo sleep mkdir cp chmod rm orientbus act su stored opk ota apprights"
PORT=${XRSTORE_PORT:-$(( 19000 + ($$ % 900) ))}

echo "== 1. build =="
mkdir -p "$TMPD/bin"
bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1 && ok "guest programs build" || { bad "programs do not build"; head -20 "$TMPD/b.txt"; echo "XRSTORE: $pass passed, $fail failed"; exit 1; }
"$FIRNC" -c --profile=app -o "$TMPD/fetch.o" kernel/app/fetch.fi > "$TMPD/fe.txt" 2>&1 \
    && ld -T kernel/user/user.ld -o "$TMPD/bin/fetch.elf" "$TMPD/fetch.o" 2>>"$TMPD/fe.txt" \
    && strip --strip-all "$TMPD/bin/fetch.elf" && ok "fetch builds" || { bad "fetch does not build"; echo "XRSTORE: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel does not build"; echo "XRSTORE: $pass passed, $fail failed"; exit 1; }
musl-gcc -static -O2 -nostartfiles -T tools/foreign/osum.ld -Wl,--build-id=none \
    -o "$TMPD/setsess" tools/foreign/start.s tools/foreign/osum_main.c tools/actionbus/setsess.c 2>"$TMPD/ss.txt" && ok "setsess builds" || bad "setsess does not build"

echo "== 2. the real package, signed catalogs =="
python3 "$OPK" schluessel "$TMPD" > "$TMPD/key.log" 2>&1
KEY="$TMPD/geheim.key"
stage() {
    local dir=$1 version=$2
    mkdir -p "$dir/bau"
    sed "s/^version=.*/version=$version/" pakete/xremote/rezept > "$dir/rezept"
    sed "s/^version=.*/version=$version/" pakete/xremote/INFO > "$dir/INFO"
    cp "$HOSTBIN" "$dir/bau/freeviewer-host"
    cp "$LIBS/lib/ld-musl-x86_64.so.1" "$dir/bau/ld-musl-x86_64.so.1"
    cp "$LIBS/usr/lib/libgcc_s.so.1" "$dir/bau/libgcc_s.so.1"
    python3 tools/k15/icon.py pakete/xremote/symbol.txt "$dir/bau/symbol" > /dev/null
    (cd "$dir" && python3 "$OPK" bauen rezept -o "$dir/xremote-$version.opk") > "$dir/build.log" 2>&1
    [ -s "$dir/xremote-$version.opk" ]
}
mkstore() {
    local d=$1; shift
    rm -rf "$d"; mkdir -p "$d"
    cp "$@" "$d/"
    python3 "$OPK" quelle "$d" --schluessel "$KEY" > "$d.log" 2>&1 || { cat "$d.log"; return 1; }
    python3 tools/update/signpak.py "$KEY" "$d"/*.opk >> "$d.log" 2>&1
}
stage "$TMPD/v1" 0.1.0 && stage "$TMPD/v2" 0.1.1 && ok "xremote 0.1.0 and 0.1.1 built from the real recipe" || bad "package build"
mkdir -p "$TMPD/srv"
mkstore "$TMPD/srv/fresh" "$TMPD/v1/xremote-0.1.0.opk" && mkstore "$TMPD/srv/upgrade" "$TMPD/v2/xremote-0.1.1.opk" && ok "two signed catalogs" || bad "catalogs"
grep -q 'xremote' "$TMPD/srv/fresh/INDEX" && ok "the catalog lists xremote" || bad "xremote not in INDEX"
mkdir -p "$TMPD/quelle1"
cp "$TMPD/v1/xremote-0.1.0.opk" "$TMPD/srv/fresh/xremote-0.1.0.opk.sig" "$TMPD/quelle1/" 2>/dev/null
python3 "$OPK" quelle "$TMPD/quelle1" --schluessel "$KEY" > "$TMPD/q1.log" 2>&1
python3 tools/update/signpak.py "$KEY" "$TMPD/quelle1"/*.opk >> "$TMPD/q1.log" 2>&1
python3 tools/ota/mkcerts.py "$TMPD/certs" ota.test 10.0.2.2 > "$TMPD/certs.log" 2>&1 && ok "certificates" || bad "certificates"
PUB="$TMPD/schluessel.pub"
[ -s "$PUB" ] || PUB=$(ls "$TMPD"/*.pub 2>/dev/null | head -1)
serve() {
    python3 tools/ota/server.py --wurzel "$TMPD/srv/$1" --port "$2" --cert "$TMPD/certs/srv.pem" --key "$TMPD/certs/srv.key" \
        --log "$TMPD/srv-$1.log" > "$TMPD/srv-$1.out" 2>&1 &
    SRVPIDS="$SRVPIDS $!"
    local i
    for i in $(seq 1 40); do grep -qa "^START port=$2 " "$TMPD/srv-$1.log" 2>/dev/null && return 0; sleep 0.2; done
    return 1
}
serve fresh "$PORT" && serve upgrade $((PORT+1)) && ok "two HTTPS sources up" || bad "sources do not start"

printf 'root:x:0:0:root:/:/bin/sh\njustin:x:1000:1000:Justin:/:/bin/sh\n' > "$TMPD/passwd"
printf 'root:x:0:\njustin:x:1000:\n' > "$TMPD/group"
printf 'installieren=admin\nentfernen=admin\nadmins=1000\n' > "$TMPD/conf.admin"
printf 'installieren=benutzer\nentfernen=benutzer\n' > "$TMPD/conf.benutzer"
printf 'installieren=aus\nentfernen=aus\n' > "$TMPD/conf.aus"
printf 'installieren=admin\nentfernen=admin\nadmins=1001\n' > "$TMPD/conf.admins"
printf 'dryfirst jarvis\n' > "$TMPD/policy"

image() {
    local img=$1 script=$2 port=$3 preinstall=$4
    printf 'source=https://10.0.2.2:%s\nname=ota.test\nabstand=3600\nauto=nein\nfrist=15\n' "$port" > "$TMPD/ota.conf"
    local -a A=(build "$img" $BLOCKS --v3 --inodes=512 --karten=64 /lib/
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /etc/actions.d/ /etc/orientbus/ /etc/ssl/ /store/ /apps/ /users/ /var/ /var/log/ /quelle1/)
    local p
    for p in $PROGS fetch; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
    A+=("/bin/setsess=$TMPD/setsess"
        "/etc/passwd=$TMPD/passwd" "/etc/group=$TMPD/group"
        "/etc/actions.d/store.actions=etc/actions.d/store.actions"
        "/etc/orientbus/policy=$TMPD/policy"
        "/etc/store.conf=$TMPD/conf.admin" "/etc/store.admin=$TMPD/conf.admin" "/etc/store.benutzer=$TMPD/conf.benutzer"
        "/etc/store.aus=$TMPD/conf.aus" "/etc/store.admins=$TMPD/conf.admins"
        "/etc/ota.conf=$TMPD/ota.conf" "/etc/ssl/roots.pem=$TMPD/certs/ca.pem"
        "/system/schluessel.pub=$PUB" "/t/s.sh=$script")
    if [ "$preinstall" = 1 ]; then
        A+=("/quelle1/xremote-0.1.0.opk=$TMPD/quelle1/xremote-0.1.0.opk" "/quelle1/xremote-0.1.0.opk.sig=$TMPD/quelle1/xremote-0.1.0.opk.sig")
    fi
    bash tools/mkfsfi/mkfs.sh "${A[@]}" > "$TMPD/mkfs-$(basename "$img").txt" 2>&1 || { echo "mkfs failed"; tail -3 "$TMPD/mkfs-$(basename "$img").txt"; }
}
run() {
    local img=$1 nm=$2 secs=$3
    timeout "$secs" $QEMU_X86 -cpu "$OSUM_CPU" -smp 1 -kernel "$TMPD/k0.img" -m 512 \
        -append "osum vfs nokbd bus nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0 script=sh /t/s.sh;exit" \
        -serial "file:$TMPD/$nm.txt" -display none -no-reboot \
        -netdev user,id=n0 -device e1000,netdev=n0,mac=52:54:00:0a:0b:0c \
        -drive "file=$img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$TMPD/$nm.txt" > "$TMPD/$nm.klar" 2>/dev/null || true
}

cat > "$TMPD/sFresh.sh" <<'EOS'
mkdir /users/justin
orientbus serve 24000 &
sleep -m 300
stored serve 24000 &
sleep 1
setsess 1000
act call store.refresh
sleep 30
echo ==F-LIST==
act call store.list
echo ==F-INST==
act call store.install name=xremote
act confirm last
sleep 150
act call store.status
echo ==F-AFTER==
opk list
apprights get xremote
ls /apps/xremote.osp
ls /apps/xremote.osp/bin
act call store.list
echo ==F-END==
EOS
cat > "$TMPD/sUpgrade.sh" <<'EOS'
mkdir /users/justin
opk install /quelle1/xremote-0.1.0.opk
echo ==U-BEFORE==
opk list
apprights get xremote
orientbus serve 24000 &
sleep -m 300
stored serve 24000 &
sleep 1
setsess 1000
act call store.refresh
sleep 30
echo ==U-LIST==
act call store.list
echo ==U-UPD==
act call store.update name=xremote
act confirm last
sleep 150
act call store.status
echo ==U-AFTER==
opk list
apprights get xremote
ls /apps/xremote.osp
act call store.list
echo ==U-END==
EOS
image "$TMPD/F.img" "$TMPD/sFresh.sh" "$PORT" 0
image "$TMPD/U.img" "$TMPD/sUpgrade.sh" $((PORT+1)) 1
run "$TMPD/F.img" fresh 900 &
FP=$!
run "$TMPD/U.img" upgrade 900 &
UP=$!
wait $FP $UP

echo "== 3. install from the store =="
F=$TMPD/fresh.klar
has "$F" "==F-END==" "the fresh script ran to its end"
has "$F" "xremote" "the catalog list names xremote"
has "$F" "item=xremote|0.1.0|" "catalog item xremote 0.1.0"
has "$F" "|neu" "xremote is new on this device before the install"
AFTER=$TMPD/fresh-after.txt
awk '/==F-AFTER==/{f=1;next} /==F-END==/{f=0} f' "$F" > "$AFTER"
has "$AFTER" "xremote -> " "opk list shows xremote after the install"
has "$AFTER" "net" "apprights grants net (perm=net from the package INFO)"
has "$AFTER" "symbol" "the package ships its Store icon (symbol)"
has "$AFTER" "freeviewer-host" "the host binary is under /apps/xremote.osp/bin"
has "$AFTER" "|aktuell" "the store lists xremote as up to date"

echo "== 4. upgrade from the store =="
U=$TMPD/upgrade.klar
has "$U" "==U-END==" "the upgrade script ran to its end"
BEFORE=$TMPD/up-before.txt
awk '/==U-BEFORE==/{f=1;next} /==U-LIST==/{f=0} f' "$U" > "$BEFORE"
has "$BEFORE" "xremote -> " "0.1.0 installed from the local signed source"
has "$BEFORE" "net" "apprights has net after the plain opk install"
has "$U" "item=xremote|0.1.1|" "the catalog offers 0.1.1"
has "$U" "|update" "the store marks xremote as update"
UAFTER=$TMPD/up-after.txt
awk '/==U-AFTER==/{f=1;next} /==U-END==/{f=0} f' "$U" > "$UAFTER"
has "$UAFTER" "|aktuell" "after the update the store says up to date"
has "$UAFTER" "net" "net right survives the upgrade"
hasnot "$UAFTER" "|update" "no pending update after upgrading"

if [ "$fail" -ne 0 ]; then
    for n in fresh upgrade; do echo "== tail $n"; tail -n 40 "$TMPD/$n.klar" | cut -c1-200; done
fi
echo "XRSTORE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
