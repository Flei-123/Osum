#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/marke-env.sh"
# SPDX-License-Identifier: GPL-2.0-only
# tools/fvcrypto/run.sh -- gate for the FreeViewer viewer crypto (lib/fv/crypto.fi,
# lib/crypto/gcm.fi) and for the path to the relay (DNS + TLS 1.3 from OrientOS).
#
#   1. host: build tools/fvcrypto/fvt.fi, compare ~200 answers with Python
#      `cryptography` / hmac / the argon2 CLI (tools/fvcrypto/vectors.py), plus
#      the Rust contract file when it exists
#   2. host, software path: the same selftest under `qemu-x86_64 -cpu qemu64`
#      (no AES-NI) -- AES-NI is NOT required
#   3. OrientOS in QEMU: `fvt selftest` in ring 3 (19 MiB Argon2id, getrandom,
#      AES-GCM), with the time it takes
#   4. OrientOS in QEMU, user-mode net: DHCP, DNS for freeviewer.fleitec.com,
#      TLS 1.3 against the real relay host, GET /fv/health (Let's Encrypt root
#      from /etc/ssl/roots.pem). Skipped (not failed) without internet.
#
#   bash tools/fvcrypto/run.sh            all
#   FVC_NET=0 bash tools/fvcrypto/run.sh  without section 4
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
RUSTVEC=${FVC_RUST_VECTORS:-/root/projects/freeviewer/tests/orientos-vectors.json}
HOSTN=${FVC_HOST:-freeviewer.fleitec.com}
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }

echo "== 1. host: compile and compare with independent implementations =="
if $FIRNC tools/fvcrypto/fvt.fi -o "$TMPD/fvt" 2>"$TMPD/cc.err"; then
    ok "tools/fvcrypto/fvt.fi compiles (lib/fv/crypto.fi + lib/fv/fvgcm.fi)"
else
    bad "fvt.fi does not compile"; head -20 "$TMPD/cc.err" | sed 's/^/        /'
    echo "FVCRYPTO: $pass passed, $fail failed"; exit 1
fi
if command -v argon2 >/dev/null && python3 -c 'import cryptography' 2>/dev/null; then
    python3 -I tools/fvcrypto/vectors.py "$TMPD/fvt" "$RUSTVEC" > "$TMPD/vec.txt" 2>&1
    rc=$?
    tail -4 "$TMPD/vec.txt" | sed 's/^/        /'
    [ $rc -eq 0 ] && ok "all vectors equal (X25519, HKDF, code, Argon2id, proof, AES-256-GCM, frames)" \
                  || bad "vectors differ (see above)"
else
    note "SKIPPED vectors: need python3 cryptography + argon2 CLI"
fi

echo "== 2. software AES (no AES-NI) =="
if command -v qemu-x86_64 >/dev/null; then
    qemu-x86_64 -cpu qemu64 "$TMPD/fvt" selftest > "$TMPD/soft.txt" 2>&1
    grep -q 'FVT: .* 0 FAIL' "$TMPD/soft.txt" && grep -q 'software' "$TMPD/soft.txt" \
        && ok "selftest equal with the software path (cpu qemu64, no AES-NI)" \
        || { bad "software path failed"; tail -6 "$TMPD/soft.txt" | sed 's/^/        /'; }
else
    note "SKIPPED: no qemu-x86_64"
fi

command -v qemu-system-x86_64 >/dev/null || { echo "FVCRYPTO: $pass passed, $fail failed (no qemu-system)"; [ $fail -eq 0 ]; exit; }

echo "== 3. ${MARKE_PRODUKT}: build kernel, userland, fvt and fetch =="
HWNET_PROGS="sh ls cat echo dhcp host" bash tools/hwnet/build.sh "$TMPD/s0" 0 > "$TMPD/b0.txt" 2>&1 \
    || { bad "kernel/userland build"; tail -5 "$TMPD/b0.txt"; echo "FVCRYPTO: $pass passed, $fail failed"; exit 1; }
ok "kernel + sh ls cat echo dhcp host built"
for app in fvt:tools/fvcrypto/fvt.fi fetch:kernel/app/fetch.fi; do
    n=${app%%:*}; src=${app#*:}
    $FIRNC -c --profile=app -o "$TMPD/$n.o" "$src" > "$TMPD/$n.err" 2>&1 \
        && ld -T kernel/user/user.ld -o "$TMPD/$n.elf" "$TMPD/$n.o" 2>>"$TMPD/$n.err" \
        && strip --strip-all "$TMPD/$n.elf" \
        && ok "$n built as a ring 3 app ($(stat -c%s "$TMPD/$n.elf") octets)" \
        || { bad "$n does not build"; head -10 "$TMPD/$n.err" | sed 's/^/        /'; }
done
python3 tools/hwnet/mkroots.py "$TMPD/roots.pem" > "$TMPD/roots.txt" 2>&1 \
    || { bad "mkroots.py"; cat "$TMPD/roots.txt"; }
printf 'nameserver 10.0.2.3\n' > "$TMPD/resolv.conf"
python3 tools/osum/mkfs.py build "$TMPD/disk.img" 32768 /bin/ /etc/ /etc/ssl/ \
    /bin/sh="$TMPD/s0/sh.elf" /bin/ls="$TMPD/s0/ls.elf" /bin/cat="$TMPD/s0/cat.elf" \
    /bin/echo="$TMPD/s0/echo.elf" /bin/dhcp="$TMPD/s0/dhcp.elf" /bin/host="$TMPD/s0/host.elf" \
    /bin/fvt="$TMPD/fvt.elf" /bin/fetch="$TMPD/fetch.elf" \
    /etc/ssl/roots.pem="$TMPD/roots.pem" /etc/resolv.conf="$TMPD/resolv.conf" \
    > "$TMPD/mkfs.txt" 2>&1 && ok "disk image built" || { bad "mkfs"; tail -3 "$TMPD/mkfs.txt"; }

run_vm() { # <script> <out> <timeout> <net 0|1>
    local NETARGS=""
    [ "$4" = 1 ] && NETARGS="-netdev user,id=n0 -device e1000,netdev=n0"
    local NIC="nic nip=169.254.10.1/16 nsvc=0 nwait=0"
    [ "$4" = 0 ] && NIC=""
    timeout "$3" qemu-system-x86_64 -kernel "$TMPD/s0/k.mb" -m 512 \
        -append "osum nokbd nosched noproc nofs modfs $NIC script=$1;exit" \
        -serial "file:$2" -display none -no-reboot \
        -drive "file=$TMPD/disk.img,format=raw,if=ide,index=0" $NETARGS \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
}

echo "== 3b. ${MARKE_PRODUKT} ring 3: fvt selftest (Argon2id 19 MiB) =="
run_vm "fvt selftest" "$TMPD/vm1.txt" 240 0
grep -a -E '^\s+(ok|FAIL)|FVT:|timing|aes path' "$TMPD/vm1.txt" | sed 's/^/        /'
grep -aq 'FVT: .* 0 FAIL' "$TMPD/vm1.txt" \
    && ok "selftest inside ${MARKE_PRODUKT}: all known answers equal (Argon2id with 19 MiB works in user space)" \
    || bad "selftest inside ${MARKE_PRODUKT} failed -- see lines above / serial: $(tail -c 300 "$TMPD/vm1.txt" | tr '\n' ' ')"

[ "${FVC_NET:-1}" = 0 ] && { echo "FVCRYPTO: $pass passed, $fail failed"; [ $fail -eq 0 ]; exit; }

echo "== 4. ${MARKE_PRODUKT}: DNS + TLS 1.3 to $HOSTN =="
if ! curl -s -m 8 -o /dev/null "https://$HOSTN/fv/health"; then
    note "SKIPPED: this machine cannot reach $HOSTN. Nothing is claimed."
else
    CURLB=$(curl -s -m 8 "https://$HOSTN/fv/health")
    run_vm "dhcp;host -v $HOSTN;fetch -v https://$HOSTN/fv/health" "$TMPD/vm2.txt" 200 1
    grep -a -E 'host:|fetch:|dhcp|\{' "$TMPD/vm2.txt" | head -30 | sed 's/^/        /'
    grep -aq "^$(getent hosts "$HOSTN" | awk '{print $1}')" "$TMPD/vm2.txt" \
        && ok "DNS: $HOSTN resolved to the same address as the host" \
        || bad "DNS: the name did not resolve to the expected address"
    grep -aq 'fetch: verify OK' "$TMPD/vm2.txt" \
        && ok "TLS 1.3 handshake + chain verified against /etc/ssl/roots.pem" \
        || bad "TLS: no 'verify OK'"
    grep -aq '"ok":true' "$TMPD/vm2.txt" \
        && ok "GET /fv/health answered {\"ok\":true,...}" \
        || bad "GET /fv/health: no body with ok:true"
fi
echo "FVCRYPTO: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
