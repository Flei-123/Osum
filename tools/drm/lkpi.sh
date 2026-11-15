#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
. tools/lib/firnenv.sh
. tools/lib/tmpdir.sh
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$*"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$*"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there" || ok "$3"; }
D=$(mktemp -d); osum_tmp_guard "" "$D"
fin() { [ -n "${DRM_OUT:-}" ] && mkdir -p "$DRM_OUT" && cp "$D"/*.klar "$D"/*.ppm "$DRM_OUT"/ 2>/dev/null; echo "DRM-LKPI-GATE: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }
QEMU=${QEMU_X86:-qemu-system-x86_64}
KVM=(); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
SCREEN="python3 -I compat/linuxkpi/hosttest/screen.py"
B="$D/b"
bash compat/linuxkpi/build.sh "$B" > "$D/build.txt" 2>&1 && ok "shim and bochs driver build" || { bad "build"; tail -5 "$D/build.txt"; fin; }
if [ -n "${KERNEL:-}" ]; then cp "$KERNEL" "$D/k.img"; ok "kernel supplied"; else
    bash tools/build-kernel.sh "$D/k.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; fin; }
fi
musl-gcc -static -O2 -o "$D/t_drm" tools/drm/t_drm.c 2> "$D/cc.txt" && ok "test program builds" || { bad "test program"; head -5 "$D/cc.txt"; fin; }
mkdir -p "$D/bin"
bash tools/sync/build.sh "$D/bin" 0 sh > "$D/p.txt" 2>&1 && ok "shell builds" || { bad "shell"; head -5 "$D/p.txt"; fin; }
PKG=$(bash compat/linuxkpi/pack.sh bochs "$B/linuxkpi.omod" "$B/bochs_drv.omod" "$D/pk" 2> "$D/pack.txt")
[ -d "$PKG" ] && ok "store package built" || { bad "package"; fin; }
nobackend_pkg() {
    local m="$D/sm" n objs=()
    . compat/linuxkpi/flags.sh
    cp -r compat/linuxkpi/shim "$m"
    sed -i 's/^\tlkpi_backend_register(dev);//' "$m/src/drm_core.c"
    lkpi_flags "$m"
    for n in $LKPI_SHIM_SOURCES; do
        "$LKPI_CC" "${LKPI_CFLAGS[@]}" -c "$m/src/$n.c" -o "$m/$n.o" || return 1
        objs+=("$m/$n.o")
    done
    ld -r -o "$m/linuxkpi.o" "${objs[@]}" || return 1
    python3 -I tools/module/mkomod.py bauen "$m/linuxkpi.o" "$m/linuxkpi.omod" --name linuxkpi --abi 1 > /dev/null || return 1
    bash compat/linuxkpi/pack.sh bochs "$m/linuxkpi.omod" "$B/bochs_drv.omod" "$D/pk-nb"
}
PKG_NB=$(nobackend_pkg 2> "$D/nb.txt" | tail -1)
[ -d "$PKG_NB" ] && ok "counter-proof package built (shim without backend registration)" || { bad "counter-proof package"; tail -3 "$D/nb.txt"; fin; }
printf 'tiers=native+compat\n' > "$D/conf-both"
printf 'tiers=native\n' > "$D/conf-native"

mkimg() {
    local name=$1 conf=$2 files="" f
    local dir=""
    case "$3" in pkg) dir=$PKG ;; nobackend) dir=$PKG_NB ;; esac
    if [ -n "$dir" ]; then
        files="/lib/drivers/ /lib/drivers/lkpi-bochs/"
        for f in $(ls "$dir"); do files="$files /lib/drivers/lkpi-bochs/$f=$dir/$f"; done
    fi
    bash tools/mkfsfi/mkfs.sh build "$D/d-$name.img" 20000 /lib/ \
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
        /bin/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ "/bin/t_drm=$D/t_drm" "/bin/sh=$D/bin/sh.elf" \
        "/etc/drvstore.conf=$conf" $files > "$D/mkfs-$name.txt" 2>&1 || tail -3 "$D/mkfs-$name.txt"
}
runvm() {
    local name=$1 kargs=$2 i=0 pid
    shift 2
    timeout 170 $QEMU "${KVM[@]}" -smp 1 -kernel "$D/k.img" -m 512 \
        -append "osum vfs $kargs nokbd nosched noproc nofs script=/bin/t_drm alt;exit" -serial "file:$D/$name.ser" \
        -display none -no-reboot "$@" \
        -drive "file=$D/d-$name.img,format=raw,if=ide,index=0" \
        -monitor "unix:$D/$name.sock,server,nowait" -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1 &
    pid=$!
    while [ $i -lt 640 ]; do
        grep -qa "DRM_HOLD" "$D/$name.ser" 2>/dev/null && break
        kill -0 $pid 2>/dev/null || break
        sleep 0.25; i=$((i+1))
    done
    $SCREEN dump "$D/$name.sock" "$D/$name.ppm"
    wait $pid
    tr -cd '\11\12\15\40-\176' < "$D/$name.ser" > "$D/$name.klar"
}
mkimg linux "$D/conf-both" pkg
mkimg native "$D/conf-both" none
mkimg tier "$D/conf-native" pkg
mkimg nobackend "$D/conf-both" nobackend
runvm linux "" -vga none -device bochs-display
runvm native "gfx" -vga std
runvm tier "gfx" -vga std
runvm nobackend "" -vga none -device bochs-display

T="open_card0 version cap_dumb getresources getconnector create_dumb map_dumb mmap addfb2 fstat_rdev getresources_fbs setcrtc getcrtc"
for v in linux native tier; do
    for t in $T; do
        line=$(grep -a "^T t_drm\.$t " "$D/$v.klar" | tail -1)
        case "$line" in *" PASS"*) ok "$v: $t" ;; *) bad "$v: $t: ${line:-no line}" ;; esac
    done
    has "$D/$v.klar" "DRM_DONE" "$v: test ran to the end"
    hasnot "$D/$v.klar" "EXCEPTION" "$v: no kernel exception"
    q=$(python3 -I tools/drm/quadrants.py "$D/$v.ppm" alt 2>&1)
    case "$q" in "quadrants ok"*) ok "$v: screendump shows the four colour quadrants ($q)" ;; *) bad "$v: screendump: $q" ;; esac
done
has "$D/linux.klar" "lkpi: modeset 1024x768 ok" "linux: Linux bochs driver set the mode through the shim"
has "$D/linux.klar" "lkpi: kms backend registered" "linux: shim registered its kms backend"
has "$D/linux.klar" "lkpi: kms op stack aligned=1" "linux: kms ops run on a 16-byte aligned stack"
has "$D/linux.klar" "DRM_MODE 1024x768" "linux: /dev/dri reports the Linux driver's mode"
hasnot "$D/native.klar" "lkpi: kms backend registered" "native counter-proof: no Linux backend without the package"
hasnot "$D/tier.klar" "lkpi: kms backend registered" "tier counter-proof: tiers=native keeps the package out"
has "$D/tier.klar" "drvstore: pkg lkpi-bochs rejected 26" "tier counter-proof: compat package rejected by tier policy"
has "$D/nobackend.klar" "lkpi: modeset 1024x768 ok" "nobackend counter-proof: Linux driver still binds and sets its mode"
hasnot "$D/nobackend.klar" "lkpi: kms backend registered" "nobackend counter-proof: no kms backend registered"
q=$(python3 -I tools/drm/quadrants.py "$D/nobackend.ppm" alt 2>&1)
case "$q" in "quadrants ok"*) bad "nobackend counter-proof: picture shown without a backend" ;; *) ok "nobackend counter-proof: /dev/dri shows no picture" ;; esac
line=$(grep -a "^T t_drm.getresources " "$D/nobackend.klar" | tail -1)
case "$line" in *" PASS"*) bad "nobackend counter-proof: getresources passes" ;; *) ok "nobackend counter-proof: getresources refused" ;; esac
fin
