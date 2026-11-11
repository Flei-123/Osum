#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
ULD=kernel/user/user.ld
. tools/lib/firnenv.sh
firnenv_need_firnc1
FC1=$FIRNC1
MODULES=${SELFHOST_MODULES:-echo fas firnc1}
GUEST_LIMIT=${SELFHOST_TIMEOUT:-1500}

TMPD=$(mktemp -d)
[ -n "${SELFHOST_KEEP:-}" ] && { rm -rf "$SELFHOST_KEEP"; mkdir -p "$SELFHOST_KEEP"; TMPD=$SELFHOST_KEEP; }
[ -z "${SELFHOST_KEEP:-}" ] && trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
same() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', expected '$3'"; fi; }
differ() { if [ "$2" != "$3" ]; then ok "$1"; else bad "$1 (hashes equal: $2)"; fi; }
sha() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }
field() { grep -a -m1 -oE "$2" "$1" 2>/dev/null | head -1; }

[ -x "$FIRNC" ] && [ -x "$FC1" ] || { echo "compiler binaries missing"; exit 1; }

echo "== 1. toolchain for the guest =="

mkdir -p "$TMPD/fz"
ln -s "$FIRN_TOOLCHAIN/src" "$TMPD/fz/bin"
ln -s "$FIRN_TOOLCHAIN/lib" "$TMPD/fz/lib"

as --64 -o "$TMPD/crt.o" kernel/user/crt.s || { bad "crt.s"; exit 1; }
as --64 -o "$TMPD/hostcrt.o" tools/k11/hostcrt.s || { bad "hostcrt.s"; exit 1; }

build_guest() {
    local name=$1 src=$2 dir=$3
    "$FIRNC" -c -o "$TMPD/$name.o" "$src" > "$TMPD/$name.err" 2>&1 || return 1
    ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start -o "$TMPD/$name" "$TMPD/crt.o" "$TMPD/$name.o" 2>>"$TMPD/$name.err" || return 1
    strip --strip-all "$TMPD/$name"
}
for p in sh echo fas; do
    build_guest "$p" "kernel/user/$p.fi" . && ok "guest program $p built" || { bad "guest program $p"; head -3 "$TMPD/$p.err"; }
done

if ( cd "$TMPD/fz" && FIRNLIB="$TMPD/fz/lib" "$ROOT/$FIRNC" -c -o "$TMPD/firnc.o" bin/firnc1.fi ) > "$TMPD/firnc.err" 2>&1 \
   && ld -T "$ULD" -o "$TMPD/firnc" "$TMPD/firnc.o" 2>>"$TMPD/firnc.err"; then
    strip --strip-all "$TMPD/firnc"
    ok "compiler linked for the guest ($(stat -c%s "$TMPD/firnc") octets)"
else
    bad "compiler cannot be linked for the guest"; head -5 "$TMPD/firnc.err"; echo "SELFHOST: $pass passed, $fail failed"; exit 1
fi

ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start -o "$TMPD/fas.host" "$TMPD/hostcrt.o" "$TMPD/fas.o" 2>/dev/null \
    && ok "assembler built for the host" || bad "host assembler"

bash tools/build-kernel.sh "$TMPD/k.mb" >/dev/null 2>&1 && ok "kernel built" || { bad "kernel build"; echo "SELFHOST: $pass passed, $fail failed"; exit 1; }

guest_specs() {
    local entry=$1 dest=$2 f rel edir
    edir=$(cd "$(dirname "$entry")" && pwd)
    while read -r f; do
        rel=${f#"$ROOT/"}
        case "$f" in
            "$edir"/*) printf '%s\n' "$dest/${f#"$edir"/}=$f" ; continue ;;
        esac
        case "$rel" in
            lib/*) printf '%s\n' "$dest/${rel#lib/}=$f" ;;
            "$FIRN_TOOLCHAIN"/lib/*) printf '%s\n' "$dest/${f#"$FIRN_TOOLCHAIN"/lib/}=$f" ;;
        esac
    done < <(bash tools/selfhost/closure.sh "$entry")
}

stage_tree() {
    local entry=$1 dest=$2 spec
    mkdir -p "$dest"
    while IFS='=' read -r target source; do
        mkdir -p "$dest$(dirname "$target")"
        cp "$source" "$dest$target"
    done < <(guest_specs "$entry" /src)
}

host_reference() {
    local entry=$1 out=$2 base
    base=$(basename "$entry" .fi)
    stage_tree "$entry" "$out/tree"
    ( cd "$out/tree/src" && env -u FIRNLIB "$ROOT/$FC1" "$base.fi" > "$out/$base.s" 2>"$out/$base.err" ) || return 1
    "$TMPD/fas.host" "$out/$base.s" -o "$out/$base.elf" $FAS_CRT > "$out/$base.fas" 2>&1
}

run_guest() {
    local img=$1 script=$2 out=$3
    cp "$img" "$TMPD/live.img"
    timeout "$GUEST_LIMIT" $QEMU_X86 -kernel "$TMPD/k.mb" -m 1024 \
        -append "osum nokbd nosched noproc nofs noring3 script=$script" -serial "file:$out" -display none -no-reboot \
        -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    cp "$TMPD/live.img" "$img.after"
}

dir_specs() {
    sed 's/=.*//' | while read -r t; do
        d=$(dirname "$t")
        while [ "$d" != / ]; do printf '%s/\n' "$d"; d=$(dirname "$d"); done
    done | sort -u | awk '{ print gsub("/","/") " " $0 }' | sort -n | cut -d' ' -f2
}

make_image() {
    local img=$1 entry=$2 base=$3
    mapfile -t specs < <(guest_specs "$entry" /src)
    mapfile -t dirs < <(printf '%s\n' "${specs[@]}" | dir_specs)
    bash tools/mkfsfi/mkfs.sh build "$img" $BLOCKS --v3 --inodes=256 /bin/ "${dirs[@]}" \
        /bin/sh="$TMPD/sh" /bin/echo="$TMPD/echo" /bin/fas="$TMPD/fas" /bin/firnc="$TMPD/firnc" "${specs[@]}" > "$TMPD/mkfs.$base.txt" 2>&1
}

for m in $MODULES; do
    echo "== 2. module $m: the compiler runs inside the guest =="
    entry="kernel/user/$m.fi"
    crt="--crt _F1.u_start"
    blocks=40000
    if [ "$m" = firnc1 ]; then entry="$TMPD/fz/bin/firnc1.fi"; crt=""; blocks=200000; fi
    mkdir -p "$TMPD/ref.$m"
    FAS_CRT=$crt host_reference "$entry" "$TMPD/ref.$m" && ok "host reference built ($(stat -c%s "$TMPD/ref.$m/$m.s") octets of assembler text)" || { bad "host reference"; head -3 "$TMPD/ref.$m/$m.err" "$TMPD/ref.$m/$m.fas"; continue; }
    BLOCKS=$blocks make_image "$TMPD/$m.img" "$entry" "$m" && ok "guest disk image written" || { bad "mkfs"; head -3 "$TMPD/mkfs.$m.txt"; continue; }
    S="cd /src;/bin/firnc $m.fi > /$m.s;/bin/echo UEB=\$?;fas /$m.s -o /$m $crt;/bin/echo BIN=\$?;exit"
    run_guest "$TMPD/$m.img" "$S" "$TMPD/$m.serial"
    same "guest compiler exit status" "$(field "$TMPD/$m.serial" 'UEB=[0-9]+')" "UEB=0"
    same "guest assembler exit status" "$(field "$TMPD/$m.serial" 'BIN=[0-9]+')" "BIN=0"
    bash tools/mkfsfi/mkfs.sh cat "$TMPD/$m.img.after" "/$m.s" > "$TMPD/$m.guest.s" 2>/dev/null
    bash tools/mkfsfi/mkfs.sh cat "$TMPD/$m.img.after" "/$m" > "$TMPD/$m.guest.elf" 2>/dev/null
    gs=$(sha "$TMPD/$m.guest.s"); hs=$(sha "$TMPD/ref.$m/$m.s")
    ge=$(sha "$TMPD/$m.guest.elf"); he=$(sha "$TMPD/ref.$m/$m.elf")
    [ -s "$TMPD/$m.guest.s" ] && ok "guest wrote the assembler text ($(stat -c%s "$TMPD/$m.guest.s") octets)" || bad "guest assembler text empty"
    same "assembler text sha256 guest = host" "$gs" "$hs"
    same "executable sha256 guest = host" "$ge" "$he"
    echo "    guest_sha256_s=$gs"
    echo "    guest_sha256_elf=$ge"

    echo "== 3. control: a manipulated source changes the hash =="
    mkdir -p "$TMPD/mut.$m"
    cp "$entry" "$TMPD/mut.$m/$m.fi"
    printf '\nfn selfhost_control_marker() -> i32 {\n    return 4242\n}\n' >> "$TMPD/mut.$m/$m.fi"
    mapfile -t specs < <(guest_specs "$entry" /src | grep -v "^/src/$m.fi=")
    mapfile -t dirs < <(printf '%s\n' "${specs[@]}" | dir_specs)
    bash tools/mkfsfi/mkfs.sh build "$TMPD/$m.mut.img" $blocks --v3 --inodes=256 /bin/ "${dirs[@]}" \
        /bin/sh="$TMPD/sh" /bin/echo="$TMPD/echo" /bin/fas="$TMPD/fas" /bin/firnc="$TMPD/firnc" "/src/$m.fi=$TMPD/mut.$m/$m.fi" "${specs[@]}" > "$TMPD/mkfs.mut.txt" 2>&1
    run_guest "$TMPD/$m.mut.img" "$S" "$TMPD/$m.mut.serial"
    bash tools/mkfsfi/mkfs.sh cat "$TMPD/$m.mut.img.after" "/$m.s" > "$TMPD/$m.mut.s" 2>/dev/null
    differ "manipulated source gives a different assembler text hash" "$(sha "$TMPD/$m.mut.s")" "$gs"
    stage_tree "$entry" "$TMPD/mut.$m/tree"
    cp "$TMPD/mut.$m/$m.fi" "$TMPD/mut.$m/tree/src/$m.fi"
    ( cd "$TMPD/mut.$m/tree/src" && env -u FIRNLIB "$ROOT/$FC1" "$m.fi" > "$TMPD/$m.mut.host.s" 2>/dev/null )
    same "manipulated source: guest = host" "$(sha "$TMPD/$m.mut.s")" "$(sha "$TMPD/$m.mut.host.s")"
done

echo "== 4. control: a broken source fails in the guest =="
printf 'fn main(start: u64) -> i32 {\n    return nosuchname\n}\n' > "$TMPD/broken.fi"
bash tools/mkfsfi/mkfs.sh build "$TMPD/b.img" 8000 --v3 --inodes=64 /bin/ /src/ \
    /bin/sh="$TMPD/sh" /bin/echo="$TMPD/echo" /bin/fas="$TMPD/fas" /bin/firnc="$TMPD/firnc" /src/broken.fi="$TMPD/broken.fi" > "$TMPD/mkfs.b.txt" 2>&1
run_guest "$TMPD/b.img" "cd /src;/bin/firnc broken.fi > /broken.s;/bin/echo UEB=\$?;exit" "$TMPD/b.serial"
rc=$(field "$TMPD/b.serial" 'UEB=[0-9]+')
if [ -n "$rc" ] && [ "$rc" != "UEB=0" ]; then ok "broken source rejected ($rc)"; else bad "broken source accepted or no answer ('$rc')"; fi

echo "SELFHOST: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
