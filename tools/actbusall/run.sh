#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$PWD/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
finish() { echo "ACTBUSALL: $pass passed, $fail failed"; exit $((fail > 0)); }

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
PROGS="sh ls cat echo sleep mkdir cp chmod rm orientbus act"
BLOCKS=20000
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && OSUM_QEMU_ACCEL=kvm
. tools/lib/firnenv.sh
mkdir -p "$TMPD/bin"
bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1 \
    && ok "programs build" || { bad "programs do not build"; tail -5 "$TMPD/b.txt"; finish; }
./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel does not build"; tail -5 "$TMPD/k.txt"; finish; }

count_actions() { grep -hcE '^(action|event) ' "$@" | paste -sd+ | bc; }
SOURCES=(etc/actions.d/*.actions)
APP_ACTIONS=(pakete/social/ACTIONS)
want=$(count_actions "${SOURCES[@]}" "${APP_ACTIONS[@]}")
want_apps=$(( ${#SOURCES[@]} + ${#APP_ACTIONS[@]} ))

{ echo "manifest 1"; echo "app pad"; for i in $(seq 1 140); do echo "action pad.a$i read \"Pad $i\""; done; } > "$TMPD/pad.actions"

cat > "$TMPD/s.sh" <<'EOS'
orientbus serve 0 &
sleep -m 500
echo ==LIST==
act list
echo ==STAT==
act stat
act stop
echo ==FERTIG==
EOS

build_image() {
    local img=$1; shift
    local -a A=(build "$img" $BLOCKS /lib/ "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /etc/actions.d/ /etc/orientbus/ /apps/ /apps/social.prog/ /var/ /var/log/)
    local p f
    for p in $PROGS; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
    for f in "${SOURCES[@]}"; do A+=("/etc/actions.d/$(basename "$f")=$f"); done
    A+=("/apps/social.prog/ACTIONS=pakete/social/ACTIONS" "/t/s.sh=$TMPD/s.sh")
    A+=("$@")
    bash tools/mkfsfi/mkfs.sh "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 || { echo "mkfs failed"; tail -3 "$TMPD/mkfs.txt"; }
}

run_guest() {
    local img=$1 nm=$2
    timeout 120 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$TMPD/k0.img" -m 512 \
        -append "osum vfs nokbd bus script=sh /t/s.sh;exit" \
        -serial "file:$TMPD/$nm.txt" -display none -no-reboot \
        -drive "file=$img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$TMPD/$nm.txt" > "$TMPD/$nm.klar" 2>/dev/null || true
}

build_image "$TMPD/all.img"
run_guest "$TMPD/all.img" all
L="$TMPD/all.klar"
grep -qa '==FERTIG==' "$L" || { bad "guest did not finish"; tail -15 "$L"; finish; }
has "$L" "orientbus: ready apps=$want_apps actions=$want rejected_manifests=0" "every manifest is loaded: $want_apps apps, $want actions, none refused"
awk '/==LIST==/{f=1;next} /==STAT==/{f=0} f' "$L" > "$TMPD/list.txt"
for a in store.list store.apps store.refresh store.status media.publish social.status; do
    grep -qaE "^$a " "$TMPD/list.txt" && ok "catalogue lists $a" || bad "catalogue lists $a"
done

build_image "$TMPD/pad.img" "/etc/actions.d/pad.actions=$TMPD/pad.actions"
run_guest "$TMPD/pad.img" pad
P="$TMPD/pad.klar"
grep -qa '==FERTIG==' "$P" || { bad "control guest did not finish"; finish; }
has "$P" "rejected_manifests=1" "control: a manifest over the table limit is refused"
has "$P" "tables are full" "control: the broker says why"
grep -qaF "actions=$want rejected_manifests=1" "$P" \
    && ok "control: the refused manifest leaves the loaded set unchanged" || bad "control: loaded set changed"
finish
