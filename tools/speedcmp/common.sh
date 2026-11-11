SPEED_SMP=${SPEED_SMP:-2}
SPEED_MEM=${SPEED_MEM:-1024}
SPEED_RUNS=${SPEED_RUNS:-5}
SPEED_BOOT_TIMEOUT=${SPEED_BOOT_TIMEOUT:-240}
SPEED_KVM=()
[ -w /dev/kvm ] && SPEED_KVM=(-accel kvm -cpu host)

resolve_musl_libc() {
    local ld=${LDSO:-/lib/ld-musl-x86_64.so.1} real
    real=$(readlink -f "$ld" 2>/dev/null || true)
    [ -r "$real" ] || real=/usr/lib/x86_64-linux-musl/libc.so
    [ -r "$real" ] || return 1
    echo "$real"
}

build_bench() {
    musl-gcc -O2 -pthread -Wall -o "$2" "$1/tools/speedcmp/speedbench.c"
}

drive_args() {
    local kind=$1 file=$2 extra=${3:-}
    case "$kind" in
        ide) DRIVE_ARGS=(-drive "file=$file,format=raw,if=ide,index=0$extra"); DRIVE_ROOT=/dev/sda ;;
        virtio) DRIVE_ARGS=(-drive "file=$file,format=raw,if=virtio$extra"); DRIVE_ROOT=/dev/vda ;;
        ahci) DRIVE_ARGS=(-device ich9-ahci,id=ahci0 -drive "file=$file,format=raw,if=none,id=hd0$extra" -device ide-hd,drive=hd0,bus=ahci0.0); DRIVE_ROOT=/dev/sda ;;
        nvme) DRIVE_ARGS=(-drive "file=$file,format=raw,if=none,id=hd0$extra" -device nvme,drive=hd0,serial=speedcmp); DRIVE_ROOT=/dev/nvme0n1 ;;
        *) echo "unknown drive kind: $kind" >&2; return 1 ;;
    esac
}
