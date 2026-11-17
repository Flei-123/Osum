#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
firnenv_need_firnc1
ROOT=$(pwd)
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$*"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$*"; }
fin() { [ -n "${LIBDRM_OUT:-}" ] && mkdir -p "$LIBDRM_OUT" && cp "$D"/*.ser "$LIBDRM_OUT"/ 2>/dev/null; echo "LIBDRM-GATE: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }
LIBDRM_VERSION=2.4.124
LIBDRM_URL=https://dri.freedesktop.org/libdrm/libdrm-$LIBDRM_VERSION.tar.xz
LIBDRM_SHA256=ac36293f61ca4aafaf4b16a2a7afff312aa4f5c37c9fbd797de9e3c0863ca379
LDREAL=$(readlink -f /lib/ld-musl-x86_64.so.1 2>/dev/null || echo /usr/lib/x86_64-linux-musl/libc.so)
QEMU=${QEMU_X86:-qemu-system-x86_64}
KVM=(); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)

if [ -n "${LIBDRM_TARBALL:-}" ]; then cp "$LIBDRM_TARBALL" "$D/libdrm.tar.xz"; else curl -fsSL -m 120 -o "$D/libdrm.tar.xz" "$LIBDRM_URL" || { bad "fetch libdrm"; fin; }; fi
echo "$LIBDRM_SHA256  $D/libdrm.tar.xz" | sha256sum -c --quiet - && ok "libdrm $LIBDRM_VERSION tarball sha256 pinned" || { bad "libdrm tarball sha256 mismatch"; fin; }
mkdir -p "$D/src" "$D/obj" "$D/bin"
tar -xJf "$D/libdrm.tar.xz" -C "$D/src" --strip-components=1
printf '#define HAVE_VISIBILITY 1\n#define _GNU_SOURCE 1\n#define HAVE_OPEN_MEMSTREAM 1\n#define MAJOR_IN_SYSMACROS 1\n#define HAVE_ALLOCA_H 1\n' > "$D/config.h"
python3 -I "$D/src/gen_table_fourcc.py" "$D/src/include/drm/drm_fourcc.h" "$D/generated_static_table_fourcc.h" || { bad "fourcc table"; fin; }
CF=(-O2 -w -I"$D" -I"$D/src" -I"$D/src/include/drm" -I"$D/src/tests" -I"$D/src/tests/util" -I"$D/src/tests/modetest" -include config.h -DHAVE_CONFIG_H)
built=1
for f in xf86drm xf86drmHash xf86drmRandom xf86drmSL xf86drmMode; do musl-gcc -c "${CF[@]}" -o "$D/obj/$f.o" "$D/src/$f.c" 2>> "$D/cc.txt" || built=0; done
[ $built = 1 ] && ok "libdrm builds with musl" || { bad "libdrm build"; head -5 "$D/cc.txt"; fin; }
for f in modetest buffers cursor; do musl-gcc -c "${CF[@]}" -o "$D/obj/mt_$f.o" "$D/src/tests/modetest/$f.c" 2>> "$D/cc.txt" || built=0; done
for f in format kms pattern; do musl-gcc -c "${CF[@]}" -o "$D/obj/mt_$f.o" "$D/src/tests/util/$f.c" 2>> "$D/cc.txt" || built=0; done
musl-gcc -static -o "$D/bin/modetest" "$D"/obj/mt_*.o "$D"/obj/xf86drm*.o -lm 2>> "$D/cc.txt" && [ $built = 1 ] && ok "modetest builds with musl" || { bad "modetest build"; head -5 "$D/cc.txt"; fin; }
musl-gcc -static "${CF[@]}" -o "$D/bin/t_libdrm" tools/drm/t_libdrm.c "$D"/obj/xf86drm*.o 2>> "$D/cc.txt" && ok "libdrm test program builds" || { bad "libdrm test program"; head -5 "$D/cc.txt"; fin; }

if [ -n "${KERNEL:-}" ]; then cp "$KERNEL" "$D/k.mb"; ok "kernel supplied"; else
    bash tools/build-kernel.sh "$D/k.mb" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; fin; }
fi
. tools/unterbau/image.sh
build_image "$ROOT" "$D/img" && ok "image builds" || { bad "image"; fin; }

runvm() {
    local name=$1 marker=$2 script=$3 i=0 pid
    cp -f "$D/img/disk.img" "$D/$name.img"
    timeout 150 $QEMU "${KVM[@]}" -smp 1 -kernel "$D/k.mb" -m 512 \
        -append "osum vfs gfx nokbd nosched noproc nofs script=$script;exit" -serial "file:$D/$name.ser" \
        -display none -no-reboot -drive "file=$D/$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1 &
    pid=$!
    while [ $i -lt 560 ]; do
        grep -qa "^$marker" "$D/$name.ser" 2>/dev/null && break
        kill -0 $pid 2>/dev/null || break
        sleep 0.25; i=$((i+1))
    done
    kill $pid 2>/dev/null; wait $pid 2>/dev/null
    rm -f "$D/$name.img"
}

runvm lib LIBDRM_DONE /bin/t_libdrm
for t in lib_open lib_getresources lib_getconnector lib_addfb2 lib_setcrtc lib_pageflip_event_handler lib_pageflip_paced lib_crtc_get_sequence lib_wait_vblank \
    lib_sequence_advances lib_syncobj_create lib_syncobj_wait_signaled lib_syncobj_wait_timeout lib_syncobj_signal_wait lib_syncobj_reset \
    lib_timeline_signal_query lib_timeline_wait lib_syncobj_fd_roundtrip lib_sync_file_roundtrip lib_syncobj_destroy lib_prime_create \
    lib_prime_handle_to_fd lib_prime_content_shared lib_prime_fd_to_handle; do
    line=$(grep -a "^T t_libdrm\.$t " "$D/lib.ser" | tail -1)
    case "$line" in *" PASS"*) ok "$t" ;; *) bad "$t: ${line:-no line}" ;; esac
done
grep -qa "LIBDRM_DONE" "$D/lib.ser" && ok "libdrm test ran to the end" || bad "libdrm test did not finish"
grep -qa "EXCEPTION" "$D/lib.ser" && bad "kernel exception" || ok "no kernel exception"

runvm modetest "MODETEST_END" "/bin/modetest -M osum -c;echo MODETEST_END"
grep -qa "modetest -> 0" "$D/modetest.ser" && ok "modetest -c exits 0" || bad "modetest -c exit status"
if grep -qa "Connectors:" "$D/modetest.ser" && grep -qa "1280x800" "$D/modetest.ser"; then ok "modetest -c lists the connector and its 1280x800 mode"; else bad "modetest -c output"; grep -a -i "modetest\|failed\|Connectors" "$D/modetest.ser" | head -5; fi
runvm modetestp "MODETEST_END" "/bin/modetest -M osum -p;echo MODETEST_END"
grep -qa "modetest -> 0" "$D/modetestp.ser" && ok "modetest -p exits 0" || bad "modetest -p exit status"
if grep -qa "Planes:" "$D/modetestp.ser" && [ "$(grep -ac "type:" "$D/modetestp.ser")" -ge 2 ]; then ok "modetest -p lists the primary and cursor planes"; else bad "modetest -p output"; grep -a -i "modetest\|Planes\|type" "$D/modetestp.ser" | head -8; fi
if grep -aqE "XR24|XRGB8888" "$D/modetestp.ser"; then ok "modetest -p lists plane formats"; else bad "modetest -p formats"; grep -a -A12 "Planes:" "$D/modetestp.ser" | head -20; fi
fin
