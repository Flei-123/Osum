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
fin() { echo "DRMX-GATE: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }
LDREAL=$(readlink -f /lib/ld-musl-x86_64.so.1 2>/dev/null || echo /usr/lib/x86_64-linux-musl/libc.so)
QEMU=${QEMU_X86:-qemu-system-x86_64}
KVM=(); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
CHECKS="open_nodes scanout_ready flip_event_queued flip_event_read flip_loop_ordered flip_loop_paced read_nonblock_empty read_small_buffer_refused
    flip_bad_flags_refused flip_queue_full_busy get_sequence wait_vblank_relative wait_vblank_zero_immediate vblank_event wait_vblank_signal_refused
    queue_sequence_event queue_sequence_past_refused render_vblank_refused syncobj_create syncobj_wait_signaled syncobj_wait_no_fence_einval
    syncobj_wait_timeout_etime syncobj_wait_past_deadline_etime syncobj_wait_blocks_until_signal syncobj_reset syncobj_wait_all_needs_both
    syncobj_wait_any_first_index syncobj_wait_all_both_signaled syncobj_create_bad_flags syncobj_destroy syncobj_destroy_twice_enoent
    timeline_signal timeline_wait_reached timeline_wait_exact timeline_wait_unsubmitted_einval timeline_wait_submit_etime
    timeline_signal_backwards_refused timeline_wait_blocks_until_point timeline_transfer timeline_transfer_unready_refused
    syncobj_fd_export syncobj_fd_poll_idle syncobj_fd_poll_signaled syncobj_fd_import_render syncobj_fd_shared_state syncobj_fd_import_wrong_kind
    sync_file_export_unsignaled_refused sync_file_export sync_file_poll_signaled sync_file_import syncobj_survives_fd_close
    prime_create prime_export prime_dmabuf_mmap_sees_data prime_shared_writes prime_import_same_client_dedup prime_import_other_client
    prime_gem_close_keeps_buffer prime_reimport_after_close prime_export_bad_handle prime_import_wrong_kind cap_prime cap_syncobj_timeline_vblank_event"

if [ -n "${KERNEL:-}" ]; then cp "$KERNEL" "$D/k.mb"; ok "kernel supplied"; else
    bash tools/build-kernel.sh "$D/k.mb" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; fin; }
fi
mkdir -p "$D/bin"
musl-gcc -static -O2 -o "$D/bin/t_drmx" tools/drm/t_drmx.c 2> "$D/cc.txt" && ok "test program builds" || { bad "test program"; head -5 "$D/cc.txt"; fin; }
. tools/unterbau/image.sh
build_image "$ROOT" "$D/img" && ok "image builds" || { bad "image"; fin; }

runvm() {
    local name=$1 kernel=$2 i=0 pid
    cp -f "$D/img/disk.img" "$D/$name.img"
    timeout 150 $QEMU "${KVM[@]}" -smp "${DRMX_SMP:-1}" -kernel "$kernel" -m 512 \
        -append "osum vfs gfx ${DRMX_KARGS:-} nokbd nosched noproc nofs script=/bin/t_drmx;exit" -serial "file:$D/$name.ser" \
        -display none -no-reboot -drive "file=$D/$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1 &
    pid=$!
    while [ $i -lt 560 ]; do
        grep -qa "DRMX_DONE" "$D/$name.ser" 2>/dev/null && break
        kill -0 $pid 2>/dev/null || break
        sleep 0.25; i=$((i+1))
    done
    kill $pid 2>/dev/null; wait $pid 2>/dev/null
    rm -f "$D/$name.img"
}

runvm new "$D/k.mb"
for t in $CHECKS; do
    line=$(grep -a "^T t_drmx\.$t " "$D/new.ser" | tail -1)
    case "$line" in *" PASS"*) ok "$t" ;; *) bad "$t: ${line:-no line}" ;; esac
done
grep -qa "DRMX_DONE" "$D/new.ser" && ok "test ran to the end" || bad "test did not finish"
grep -qa "EXCEPTION" "$D/new.ser" && bad "kernel exception" || ok "no kernel exception"

if [ -n "${KERNEL_OLD:-}" ]; then
    cp "$KERNEL_OLD" "$D/old.mb"
    runvm old "$D/old.mb"
    red=0
    for t in flip_event_read syncobj_create timeline_signal prime_export; do
        line=$(grep -a "^T t_drmx\.$t " "$D/old.ser" | tail -1)
        case "$line" in *" PASS"*) ;; *) red=$((red+1)) ;; esac
    done
    [ "$red" -eq 4 ] && ok "counter-proof: old kernel fails events, syncobj, timeline, prime" || bad "counter-proof: old kernel passed $((4-red)) of 4 probes"
fi
fin
