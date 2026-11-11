#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
HERE=tools/devtools
UB=tools/unterbau
. tools/lib/tmpdir.sh
D=${DT_OUT:-$(mktemp -d)}
mkdir -p "$D"
osum_tmp_guard "${DT_OUT:-}" "$D"
QEMU=${QEMU_X86:-qemu-system-x86_64}
KVM=(); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
SMP=${SMP:-2}
TMO=${TMO:-420}
export FIRNLIB="$ROOT/lib"
BBDYN=${BBDYN:-/root/bbdyn/busybox}
STONES=${STONES-/root/stones}
export UB_DRIVE=${UB_DRIVE:-ahci}
pass=0; fail=0
ok() { pass=$((pass+1)); echo "  ok   $*"; }
bad() { fail=$((fail+1)); echo "  FAIL $*"; }

for t in "$QEMU" openssl python3 musl-gcc git; do command -v "$t" >/dev/null 2>&1 || { echo "DEVTOOLS: $t missing, skipped"; exit 0; }; done
LDREAL=$(readlink -f "${LDSO:-/lib/ld-musl-x86_64.so.1}" 2>/dev/null || true)
[ -r "$LDREAL" ] || LDREAL=/usr/lib/x86_64-linux-musl/libc.so
for need in "$LDREAL" "$BBDYN" "$STONES/curl" "$STONES/git" "$STONES/make" "$STONES/tcc" "$STONES/gitexec/git-remote-http"; do
    [ -r "$need" ] || { echo "DEVTOOLS: stone $need missing, skipped"; exit 0; }
done
. "$UB/image.sh"

free_port() { python3 -I -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])'; }
TLSPORT=$(free_port)
mkdir -p "$D/www" "$D/bin" "$D/lib" "$D/src"
echo devtools > "$D/bin/dt-marker"
echo hello-net > "$D/www/h.txt"
head -c 300000 /dev/urandom > "$D/www/big.bin"
BIGSHA=$(sha256sum "$D/www/big.bin" | cut -c1-16)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
git init -q "$D/src" && echo hello-net > "$D/src/file" && git -C "$D/src" add file \
    && git -C "$D/src" -c user.name=t -c user.email=t@t commit -q -m first \
    && git clone -q --bare "$D/src" "$D/www/repo.git" && git -C "$D/www/repo.git" update-server-info || { echo "DEVTOOLS: host git repo failed"; exit 1; }
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$D/key.pem" -out "$D/ca.pem" -days 30 -subj "/CN=10.0.2.2" -addext "subjectAltName=IP:10.0.2.2" >/dev/null 2>&1 || { echo "DEVTOOLS: openssl cannot make a certificate"; exit 1; }
sed "s/TLSPORT/$TLSPORT/g" "${DT_GUEST:-$HERE/guest.sh}" > "$D/wt.sh"
printf 'one\ntwo\nthree\n' > "$D/pruef.txt"; echo 'echo BB end' > "$D/bb.sh"

KNEW=${KERNEL:-$D/k.mb}
if [ -z "${KERNEL:-}" ]; then build_kernel "$ROOT" "$KNEW" && ok "kernel built" || { bad "kernel does not build"; tail -8 "$KNEW.log"; echo "DEVTOOLS: $pass passed, $fail failed"; exit 1; }; fi
EXTRA_SPEC="$(stones_spec "$STONES") /bin/ash@/bin/busybox /etc/wt.sh=$D/wt.sh /etc/ca.pem=$D/ca.pem"
UB_BLOCKS=${UB_BLOCKS:-262144} build_image "$ROOT" "$D/img" && ok "image built" || { bad "image does not build"; tail -5 "$D/img/mkfs.txt"; echo "DEVTOOLS: $pass passed, $fail failed"; exit 1; }

python3 -I "$UB/tlssrv.py" "$TLSPORT" "$D/ca.pem" "$D/key.pem" "$D/www" > "$D/tls.log" 2>&1 &
TLSPID=$!
trap 'kill $TLSPID 2>/dev/null; for d in ${OSUM_TMP_OWNED:-}; do rm -rf "$d"; done' EXIT

KARGS="nic nip=10.0.2.15/24 ngw=10.0.2.2 ${DT_KARGS:-}" NETARGS="-netdev user,id=n0 -device virtio-net-pci,netdev=n0" boot "$KNEW" "$D/img/disk.img" "busybox sh /etc/wt.sh" "$D/wt.ser"
grep -a -o -E 'WT [A-Za-z0-9_-]+( .*)?$' "$D/wt.ser" | tr -d '\r' | awk '!seen[$2]++' > "$D/wt.res" || : > "$D/wt.res"
[ -n "${DT_KEEP_SER:-}" ] && cp "$D/wt.ser" "$DT_KEEP_SER"

check() {
    local name=$1 want=$2 line
    line=$(grep -a "^WT $name " "$D/wt.res" | head -1)
    if [ "$line" = "WT $name $want" ]; then ok "$name: $want"; else bad "$name: expected '$want', got '${line:-nothing}'"; fi
}
while read -r name want; do case "$name" in ''|'#'*) continue ;; esac; check "$name" "$want"; done < "$HERE/expect.txt"
check curl-https-big "300000 $BIGSHA"
check tar-extract "$(grep -a '^WT tar-want ' "$D/wt.res" | cut -d' ' -f3)"
grep -aq '^WT end' "$D/wt.res" && ok "guest script ran to the end" || bad "guest script did not reach its end"
echo "DEVTOOLS: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
