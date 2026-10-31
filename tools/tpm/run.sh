#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
T=$(mktemp -d)
SW=()
cleanup() { for p in "${SW[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done; rm -rf "$T"; }
trap cleanup EXIT
OK=0
FAIL=0
check() {
    if [ "$2" = 1 ]; then OK=$((OK + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1"; fi
}
has() { grep -q -- "$2" "$1" && echo 1 || echo 0; }
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
mkdir -p "$T/bin"
bash tools/sync/build.sh "$T/bin" 0 sh cat echo > "$T/b.txt" 2>&1 || { tail -15 "$T/b.txt"; exit 1; }
./tools/build-kernel.sh "$T/k0.img" --stufe 0 > "$T/k.txt" 2>&1 || { tail -15 "$T/k.txt"; exit 1; }
printf 'echo ==TPM==\ncat /proc/tpm\necho ==END==\n' > "$T/s.sh"
python3 tools/osum/mkfs.py build "$T/d.img" 20000 /bin/ /t/ /tmp/ /proc/ /dev/ /etc/ /var/ \
    $(for p in sh cat echo; do echo "/bin/$p=$T/bin/$p.elf"; done) "/t/s.sh=$T/s.sh" > "$T/mkfs.txt" 2>&1 || tail -3 "$T/mkfs.txt"
run_case() {
    local name=$1 dev=$2
    local extra=()
    if [ -n "$dev" ]; then
        mkdir -p "$T/st-$name"
        swtpm socket --tpmstate "dir=$T/st-$name" --ctrl "type=unixio,path=$T/sock-$name" --tpm2 --log "file=$T/sw-$name.log" &
        SW+=($!)
        for _ in $(seq 50); do [ -S "$T/sock-$name" ] && break; sleep 0.1; done
        extra=(-chardev "socket,id=chrtpm,path=$T/sock-$name" -tpmdev emulator,id=tpm0,chardev=chrtpm -device "$dev,tpmdev=tpm0")
    fi
    timeout 150 qemu-system-x86_64 -accel tcg -smp 1 -kernel "$T/k0.img" -m 512 -cpu max "${extra[@]}" \
        -append "osum vfs nokbd script=sh /t/s.sh;exit" \
        -serial "file:$T/o-$name.txt" -display none -no-reboot \
        -drive "file=$T/d.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/o-$name.txt" | awk 'index($0,"==TPM=="){f=1;next} index($0,"==END=="){f=0} f' > "$T/r-$name.txt"
    echo "### $name"
    cat "$T/r-$name.txt"
}
CASES=${TPM_CASES:-"crb tis none"}
for c in $CASES; do
    case $c in
        crb) run_case crb tpm-crb ;;
        tis) run_case tis tpm-tis ;;
        none) run_case none "" ;;
    esac
done
for c in $CASES; do
    [ "$c" = none ] && continue
    r="$T/r-$c.txt"
    check "$c acpi TPM2 table" "$(has "$r" 'tpm: acpi=TPM2')"
    check "$c interface" "$(has "$r" "tpm: interface=$c")"
    check "$c fixed rc=0" "$(has "$r" 'tpm: fixed rc=0x00000000')"
    check "$c family 2.0" "$(has "$r" 'family=2.0')"
    check "$c manufacturer" "$(has "$r" 'manufacturer=')"
    check "$c pcr banks sha256" "$(has "$r" 'bank=0x000b')"
    check "$c algs listed" "$(has "$r" 'tpm: algs rc=0x00000000 n=')"
    check "$c usable=yes" "$(has "$r" 'usable=yes')"
done
case " $CASES " in *" crb "*) check "crb method 7" "$(has "$T/r-crb.txt" 'method=7')" ;; esac
case " $CASES " in *" tis "*) check "tis method 6" "$(has "$T/r-tis.txt" 'method=6')" ;; esac
case " $CASES " in *" none "*)
    check "none acpi" "$(has "$T/r-none.txt" 'acpi=none')"
    check "none interface" "$(has "$T/r-none.txt" 'tpm: interface=none')"
    check "none usable=no" "$(has "$T/r-none.txt" 'usable=no')" ;;
esac
echo "tpm gate: $OK ok, $FAIL fail"
[ "$FAIL" = 0 ]
