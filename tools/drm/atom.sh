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
fin() { echo "DRMA-GATE: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }
LDREAL=$(readlink -f /lib/ld-musl-x86_64.so.1 2>/dev/null || echo /usr/lib/x86_64-linux-musl/libc.so)
QEMU=${QEMU_X86:-qemu-system-x86_64}
KVM=(); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
CHECKS="client_cap_universal client_cap_atomic client_cap_bad_value_refused cap_cursor_size plane_resources get_plane_primary get_plane_cursor_idle get_plane_unknown_enoent prop_plane_type_primary prop_plane_type_cursor prop_plane_fb_id_value prop_crtc_active prop_crtc_mode_blob prop_connector_crtc obj_props_unknown_enoent get_property_type_enum get_property_fb_id_object_atomic get_property_signed_range get_property_mode_blob get_property_unknown_enoent blob_create blob_get_roundtrip blob_destroy blob_destroy_twice_enoent blob_get_gone_enoent blob_create_empty_refused blob_mode_length atomic_test_only_ok atomic_test_only_no_effect atomic_commit_switches_fb atomic_prop_reads_back atomic_flip_event atomic_test_only_event_refused atomic_unknown_fb_enoent atomic_failed_commit_keeps_state atomic_bad_flags_refused atomic_wrong_crtc_refused atomic_size_mismatch_refused atomic_immutable_type_refused atomic_foreign_prop_refused atomic_unknown_prop_enoent atomic_modeset_needs_flag atomic_modeset_allowed_test atomic_modeset_test_no_effect atomic_unknown_mode_blob_refused atomic_needs_client_cap cursor_fb_create cursor_atomic_commit cursor_plane_fb_set cursor_position_reads_back cursor_primary_unaffected cursor_too_big_refused setplane_legacy_cursor_move setplane_disable_cursor setplane_unknown_enoent eventfd_syncobj_create syncobj_eventfd_register syncobj_eventfd_idle syncobj_eventfd_signal_fires syncobj_eventfd_already_signaled syncobj_eventfd_bad_handle_enoent syncobj_eventfd_wrong_fd_einval syncobj_eventfd_bad_flags_einval vblank_rate_measured open_card scanout_ready"

if [ -n "${KERNEL:-}" ]; then cp "$KERNEL" "$D/k.mb"; ok "kernel supplied"; else
    bash tools/build-kernel.sh "$D/k.mb" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; fin; }
fi
mkdir -p "$D/bin"
musl-gcc -static -O2 -o "$D/bin/t_drmatom" tools/drm/t_drmatom.c 2> "$D/cc.txt" && ok "test program builds" || { bad "test program"; head -5 "$D/cc.txt"; fin; }
. tools/unterbau/image.sh
build_image "$ROOT" "$D/img" && ok "image builds" || { bad "image"; fin; }

runvm() {
    local name=$1 kernel=$2 kargs=${3:-} i=0 pid
    cp -f "$D/img/disk.img" "$D/$name.img"
    timeout 150 $QEMU "${KVM[@]}" -smp "${DRMA_SMP:-1}" -kernel "$kernel" -m 512 \
        -append "osum vfs gfx ${DRMA_KARGS:-} $kargs nokbd nosched noproc nofs script=/bin/t_drmatom;exit" -serial "file:$D/$name.ser" \
        -display none -no-reboot -drive "file=$D/$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1 &
    pid=$!
    while [ $i -lt 560 ]; do
        grep -qa "DRMA_DONE" "$D/$name.ser" 2>/dev/null && break
        kill -0 $pid 2>/dev/null || break
        sleep 0.25; i=$((i+1))
    done
    kill $pid 2>/dev/null; wait $pid 2>/dev/null
    rm -f "$D/$name.img"
}

runvm new "$D/k.mb"
for t in $CHECKS; do
    line=$(grep -a "^T t_drmatom\.$t " "$D/new.ser" | tail -1)
    case "$line" in *" PASS"*) ok "$t" ;; *) bad "$t: ${line:-no line}" ;; esac
done
grep -qa "DRMA_DONE" "$D/new.ser" && ok "test ran to the end" || bad "test did not finish"
grep -qa "EXCEPTION" "$D/new.ser" && bad "kernel exception" || ok "no kernel exception"

rate_of() { grep -a "^VBLRATE " "$1" | tail -1 | cut -d' ' -f2; }
rate=$(rate_of "$D/new.ser")
[ -n "$rate" ] && [ "$rate" -ge 50 ] && [ "$rate" -le 70 ] && ok "vblank timer rate $rate/s" || bad "vblank timer rate ${rate:-none}"
runvm sim "$D/k.mb" drmvblsim
srate=$(rate_of "$D/sim.ser")
[ -n "$srate" ] && [ "$srate" -ge 24 ] && [ "$srate" -le 36 ] && ok "vblank follows reported source: $srate/s" || bad "vblank source rate ${srate:-none}"

if [ -n "${KERNEL_OLD:-}" ]; then
    cp "$KERNEL_OLD" "$D/old.mb"
    runvm old "$D/old.mb"
    red=0
    for t in plane_resources atomic_commit_switches_fb cursor_atomic_commit syncobj_eventfd_signal_fires; do
        line=$(grep -a "^T t_drmatom\.$t " "$D/old.ser" | tail -1)
        case "$line" in *" PASS"*) ;; *) red=$((red+1)) ;; esac
    done
    [ "$red" -eq 4 ] && ok "counter-proof: old kernel fails planes, atomic, cursor, syncobj eventfd" || bad "counter-proof: old kernel passed $((4-red)) of 4 probes"
fi
fin
