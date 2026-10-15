#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/stickwr/run.sh -- D7: THE USB STICK WRITER (kernel/user/stickwr.fi + lib/stickwr/guard.fi), MEASURED.
#
#   bash tools/stickwr/run.sh [stage ...]      (stages: host hot bus; default all; use heavy)
#
# host  the guards against tools/stickwr/guard.fi (target only /dev/usb0..3, source .img/.iso, --yes,
#       64 KiB geometry) + two MUTATIONS (usb range opened, --yes ignored) that must turn it red
# hot   QEMU, a FAT32 stick plugged in WHILE RUNNING and mounted at /medien/usb0 (tools/hotplug):
#       refusals (hda, hdb, nvme0, "/dev/usb", no --yes, bad source, device as source, missing source)
#       change NOTHING (the stick still lists its host file, hda has no second copy of the image
#       marker); --dry writes nothing; the real write ejects the mount first (ls fails afterwards),
#       prints "verified ok"; THE HOST then compares the stick image octet for octet with the source
#       and checks that everything behind the image is untouched
# bus   QEMU, stick present at boot: orient-bus + `stickwr serve`; the two critical actions park until
#       the user confirms; refused target / too big / dry run / write via `stickwr.write` and the
#       menu action `stickwr.writefile`; THE HOST compares the stick bytes of both writes
# DOES NOT MEASURE: a real stick on real hardware (readback goes through the same driver), an open
# file on the mounted stick (E_BUSY path is by reading, not run), the explorer click.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
STAGES=${*:-host hot bus}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" 2>/dev/null && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
keep() { [ -z "${SW_KEEP:-}" ] || cp "$T"/*.txt "$T"/*.klar "$T"/*.lauf "$SW_KEEP"/ 2>/dev/null; }  # SW_KEEP=<dir>: copy logs out for debugging
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
[ -x "$FIRNC" ] || bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

# ---------------------------------------------------------------- shared test data
MAGIC='STICKWR-MAGIC-01!'
mkimg() { # <file> <size> <seed> <marker>
    python3 - "$1" "$2" "$3" "$4" <<'EOF'
import sys, random
path, size, seed, marker = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4].encode()
r = random.Random(seed)
data = bytearray(r.getrandbits(8) for _ in range(size))
data[:len(marker)] = marker
open(path, "wb").write(bytes(data))
EOF
}
count_marker() { python3 -c "import sys;print(open(sys.argv[1],'rb').read().count(sys.argv[2].encode()))" "$1" "$2"; }

stage_host() {
    echo "== stage host =="
    $FIRNC tools/stickwr/guard.fi -o "$T/guard" 2> "$T/g.err" && ok "guard test builds" || { bad "guard test build"; head -5 "$T/g.err"; return; }
    "$T/guard" > "$T/guard.txt" 2>&1
    local n1 n2; n1=$(grep -c '^OK' "$T/guard.txt"); n2=$(grep -c '^FAIL' "$T/guard.txt")
    sed -n 's/^FAIL /  FAIL  guard: /p' "$T/guard.txt"
    [ "$n2" = 0 ] && [ "$n1" -ge 45 ] && ok "guards: $n1 checks OK, 0 FAIL" || bad "guards ($n1 ok, $n2 fail)"
    pass=$((pass+n1))
    mkdir -p "$T/lib-mut"
    local d
    for d in lib/*; do [ "$(basename "$d")" = stickwr ] || ln -sfn "$ROOT/$d" "$T/lib-mut/$(basename "$d")"; done
    mkdir -p "$T/lib-mut/stickwr"
    # mutation 1: the usb range is opened (usb4..usb9 and ':' etc. pass)
    sed 's/    if d < 48 || d > 51 {/    if d < 48 {/' lib/stickwr/guard.fi > "$T/lib-mut/stickwr/guard.fi"
    cmp -s lib/stickwr/guard.fi "$T/lib-mut/stickwr/guard.fi" && bad "mutation 1 did not change the lib"
    if FIRNLIB="$T/lib-mut" $FIRNC tools/stickwr/guard.fi -o "$T/g-mut1" 2>/dev/null; then
        local m; m=$("$T/g-mut1" 2>&1 | grep -c '^FAIL')
        [ "$m" -gt 0 ] && ok "mutation (usb range opened) -> $m red checks" || bad "mutation 1 stayed green"
    else bad "mutation 1 build failed"; fi
    # mutation 2: --yes is ignored
    sed 's/    if !yes {/    if false {/' lib/stickwr/guard.fi > "$T/lib-mut/stickwr/guard.fi"
    cmp -s lib/stickwr/guard.fi "$T/lib-mut/stickwr/guard.fi" && bad "mutation 2 did not change the lib"
    if FIRNLIB="$T/lib-mut" $FIRNC tools/stickwr/guard.fi -o "$T/g-mut2" 2>/dev/null; then
        local m2; m2=$("$T/g-mut2" 2>&1 | grep -c '^FAIL')
        [ "$m2" -gt 0 ] && ok "mutation (--yes ignored) -> $m2 red checks" || bad "mutation 2 stayed green"
    else bad "mutation 2 build failed"; fi
    # mutation 3: a device is accepted as image source
    sed 's/    return starts_dev(p) || starts_proc(p)/    return false/' lib/stickwr/guard.fi > "$T/lib-mut/stickwr/guard.fi"
    if FIRNLIB="$T/lib-mut" $FIRNC tools/stickwr/guard.fi -o "$T/g-mut3" 2>/dev/null; then
        local m3; m3=$("$T/g-mut3" 2>&1 | grep -c '^FAIL')
        [ "$m3" -gt 0 ] && ok "mutation (device as source accepted) -> $m3 red checks" || bad "mutation 3 stayed green"
    else bad "mutation 3 build failed"; fi
    # manifest
    python3 tools/actionbus/manifest.py check pakete/stickwr/ACTIONS > "$T/lint.txt" 2>&1 \
        && ok "manifest lint: $(cut -d' ' -f2- "$T/lint.txt")" || bad "manifest lint: $(cat "$T/lint.txt")"
    python3 tools/actionbus/manifest.py json pakete/stickwr/ACTIONS 2>/dev/null | python3 -c "
import sys, json
j = json.load(sys.stdin)
acts = {a['name']: a for a in j.get('actions', [])}
w, f = acts.get('stickwr.write'), acts.get('stickwr.writefile')
assert w and w['level'] == 'critical' and f and f['level'] == 'critical', 'both critical'
assert f['menu']['kind'] == 'file' and f['menu']['ext'] == ['img', 'iso'], 'menu file img iso'
assert not w.get('menu'), 'stickwr.write has no menu'
" 2> "$T/man.err" && ok "manifest: both actions critical, only writefile in the file menu (img, iso)" || bad "manifest json: $(tail -1 "$T/man.err")"
}

build_progs() { # <outdir> <progs...>  (hotplug style: firnc + ld + crt)
    local out=$1; shift
    as --64 -o "$T/crt.o" kernel/user/crt.s 2>/dev/null
    local p n=0
    mkdir -p "$out"
    for p in "$@"; do
        if "$FIRNC" kernel/user/$p.fi -o "$T/$p.o" > "$T/$p.log" 2>&1 \
            && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$out/$p" "$T/crt.o" "$T/$p.o" 2>>"$T/$p.log"; then
            n=$((n+1))
        else
            bad "$p does not build"; grep -E '^error' "$T/$p.log" | head -3 | sed 's/^/        /'
        fi
    done
    [ "$n" = "$#" ] && ok "$n programs build ($*)"
}

stage_hot() {
    echo "== stage hot =="
    for w in mkfs.vfat mcopy mdir sfdisk qemu-system-x86_64; do
        command -v "$w" >/dev/null 2>&1 || { echo "STICKWR hot: skipped, $w missing"; return; }
    done
    local KERN="$T/k.mb"
    ./tools/build-kernel.sh "$KERN" > "$T/hk.log" 2>&1 && ok "kernel builds" || { bad "kernel build"; tail -3 "$T/hk.log"; return; }
    build_progs "$T/hb" sh cat echo ls stickwr
    mkimg "$T/boot.img" 200003 11 "$MAGIC"
    echo "just text" > "$T/note.txt"
    cat > "$T/s1.sh" <<'EOS'
echo ==A==
ls /medien/usb0
echo ==R==
stickwr /t/boot.img /dev/hda --yes
echo rc=$?
stickwr /t/boot.img /dev/hdb --yes
echo rc=$?
stickwr /t/boot.img /dev/nvme0 --yes
echo rc=$?
stickwr /t/boot.img /dev/usb --yes
echo rc=$?
stickwr /t/boot.img /dev/usb0
echo rc=$?
stickwr /t/note.txt /dev/usb0 --yes
echo rc=$?
stickwr /dev/hda /dev/usb0 --yes
echo rc=$?
stickwr /t/missing.img /dev/usb0 --yes
echo rc=$?
stickwr /t/boot.img /dev/usb0 --dry --yes
echo rc=$?
echo ==B==
ls /medien/usb0
echo ==C==
stickwr /t/boot.img /dev/usb0 --yes
echo rc=$?
echo ==D==
ls /medien/usb0
echo ==END==
EOS
    python3 tools/osum/mkfs.py build "$T/root.img" 20000 /bin/ /proc/ /dev/ /mnt/ /usb/ /medien/ /t/ \
        $(for p in sh cat echo ls stickwr; do echo "/bin/$p=$T/hb/$p"; done) \
        "/t/s1.sh=$T/s1.sh" "/t/boot.img=$T/boot.img" "/t/note.txt=$T/note.txt" > "$T/mkfs.txt" 2>&1 \
        && ok "root disk built" || { bad "mkfs"; tail -3 "$T/mkfs.txt"; return; }
    local before; before=$(count_marker "$T/root.img" "$MAGIC")
    # the stick: FAT32 behind an MBR, one host file
    local OFF=$((2048*512))
    dd if=/dev/zero of="$T/stick1.img" bs=1M count=48 status=none
    sfdisk "$T/stick1.img" >/dev/null 2>&1 <<SF
label: dos
start=2048, type=c
SF
    dd if=/dev/zero of="$T/stick1.part" bs=1M count=46 status=none
    mkfs.vfat -F32 -n STICKW "$T/stick1.part" >/dev/null 2>&1
    echo "host file on the stick" > "$T/hostfile.txt"
    mcopy -i "$T/stick1.part" "$T/hostfile.txt" ::host.txt
    dd if="$T/stick1.part" of="$T/stick1.img" bs=512 seek=2048 conv=notrunc status=none
    rm -f "$T/stick1.part"
    cp "$T/stick1.img" "$T/stick1.orig"
    cat > "$T/dreh.txt" <<EOF
aufzeile k17: hold
warte 1
stecke stk1 $T/stick1.img
aufzeile wechsel: kommt
warte 2
EOF
    cp "$T/root.img" "$T/live.img"
    HP_TIMEOUT=${HP_TIMEOUT:-240} ARB="$T" bash tools/hotplug/lauf.sh hot "$KERN" \
        "osum usb usbhold vfs gfx nosched noproc script=sh /t/s1.sh;exit" "$T/dreh.txt" \
        -drive "file=$T/live.img,format=raw,if=ide,index=0" -device qemu-xhci,id=xhci > "$T/hot.lauf" 2>&1
    local RC; RC=$(sed -n 's/^RC=//p' "$T/hot.lauf" | tail -1)
    [ "${RC:-99}" = 21 ] && ok "the guest ends itself (21)" || bad "the guest did not end itself (rc=${RC:-?})"
    tr -cd '\11\12\15\40-\176' < "$T/hot.txt" > "$T/h.klar"
    part "$T/h.klar" A R > "$T/pa.txt"
    part "$T/h.klar" R B > "$T/pr.txt"
    part "$T/h.klar" B C > "$T/pb.txt"
    part "$T/h.klar" C D > "$T/pc.txt"
    part "$T/h.klar" D END > "$T/pd.txt"
    has "$T/pa.txt" "host.txt" "before: the stick is mounted and lists the host file"
    has "$T/pr.txt" "refused_target" "hda / hdb / nvme0 / '/dev/usb': refused_target"
    [ "$(grep -ac 'refused_target' "$T/pr.txt")" -ge 4 ] && ok "all four wrong targets refused (hda, hdb, nvme0, /dev/usb)" || bad "fewer than four refused_target lines"
    has "$T/pr.txt" "need_yes" "no --yes: nothing happens"
    has "$T/pr.txt" "refused_source" "a .txt file is not an image"
    has "$T/pr.txt" "refused_source_dev" "a device as source is refused"
    has "$T/pr.txt" "no_source" "a missing image is reported"
    has "$T/pr.txt" "dry run ok" "--dry runs the checks"
    [ "$(grep -ac '^rc=1' "$T/pr.txt")" -ge 7 ] && ok "refusals exit with 1" || bad "refusal exit codes: $(grep -a '^rc=' "$T/pr.txt" | tr '\n' ' ')"
    hasnot "$T/pr.txt" "wrote " "no refusal wrote anything"
    has "$T/pb.txt" "host.txt" "after all refusals + dry run: the stick STILL lists its host file"
    has "$T/pc.txt" "wrote 200003 bytes in 4 blocks, verified ok" "the real write: 200003 octets, 4 blocks, verified"
    has "$T/pc.txt" "rc=0" "exit code 0"
    hasnot "$T/pd.txt" "host.txt" "after the write the mount is gone (ejected first), no stale listing"
    # THE HOST MEASURES
    cmp -n 200003 "$T/boot.img" "$T/stick1.img" > /dev/null 2>&1 \
        && ok "HOST: the first 200003 octets of the stick equal the image" || bad "HOST: the stick does not equal the image"
    cmp -n 4096 "$T/stick1.orig" "$T/stick1.img" > /dev/null 2>&1 \
        && bad "HOST (control): the stick head did not change at all" || ok "HOST (control): the stick head did change"
    cmp -i 200003 "$T/stick1.orig" "$T/stick1.img" > /dev/null 2>&1 \
        && ok "HOST: everything behind the image is untouched" || bad "HOST: octets behind the image changed"
    local after; after=$(count_marker "$T/live.img" "$MAGIC")
    [ "$after" = "$before" ] && ok "HOST: hda has no extra copy of the image marker ($before before, $after after)" \
        || bad "HOST: hda marker count $before -> $after (something was written to hda)"
}

stage_bus() {
    echo "== stage bus =="
    command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "STICKWR bus: skipped, qemu missing"; return; }
    mkdir -p "$T/bb"
    local PROGS="sh ls cat echo sleep orientbus stickwr act"
    bash tools/sync/build.sh "$T/bb" 0 $PROGS > "$T/bb.txt" 2>&1 \
        && ok "bus programs build" || { bad "bus programs build"; head -10 "$T/bb.txt"; return; }
    ./tools/build-kernel.sh "$T/k0.img" --stufe 0 > "$T/k0.txt" 2>&1 && ok "kernel (stage 0) builds" || { bad "kernel build"; return; }
    mkimg "$T/boot2.img" 200003 21 "$MAGIC"
    mkimg "$T/other.img" 70000 22 "OTHER-MAGIC-0001"
    mkimg "$T/big.img" 5242880 23 "BIG-MAGIC-0000001"
    head -c 4194304 /dev/zero > "$T/stick2.img"
    mkdir -p "$T/etc/orientbus"
    echo "# empty policy" > "$T/etc/orientbus/policy"
    cat > "$T/s2.sh" <<'EOS'
orientbus serve 30000 &
sleep -m 300
stickwr serve 30000 &
sleep 1
echo ==LIST==
act list
echo ==MENU==
act list --menu file x.iso
act list --menu file x.txt
echo ==DRY==
act call stickwr.write image=/t/boot.img target=/dev/usb0 --dry
echo rc=$?
echo ==HDA==
act call stickwr.write image=/t/boot.img target=/dev/hda
echo rc=$?
act confirm last
echo rc=$?
echo ==BIG==
act call stickwr.write image=/t/big.img target=/dev/usb0
act confirm last
echo rc=$?
echo ==W1==
act call stickwr.write image=/t/boot.img target=/dev/usb0
echo rc=$?
act confirm last
echo rc=$?
echo ==W2==
act call stickwr.writefile path=/t/other.img
echo rc=$?
act confirm last
echo rc=$?
echo ==NOIMG==
act call stickwr.writefile path=/t/notes.txt
act confirm last
echo rc=$?
echo ==END==
EOS
    python3 tools/osum/mkfs.py build "$T/d2.img" 30000 /lib/ \
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /etc/orientbus/ /apps/ /apps/stickwr.prog/ /var/ /var/log/ \
        $(for p in $PROGS; do echo "/bin/$p=$T/bb/$p.elf"; done) \
        "/apps/stickwr.prog/start=$T/bb/stickwr.elf" "/apps/stickwr.prog/ACTIONS=pakete/stickwr/ACTIONS" \
        "/etc/orientbus/policy=$T/etc/orientbus/policy" \
        "/t/s.sh=$T/s2.sh" "/t/boot.img=$T/boot2.img" "/t/other.img=$T/other.img" "/t/big.img=$T/big.img" \
        "/t/notes.txt=$T/etc/orientbus/policy" > "$T/mkfs2.txt" 2>&1 || { bad "mkfs (bus)"; tail -3 "$T/mkfs2.txt"; return; }
    local hda_before; hda_before=$(count_marker "$T/d2.img" "$MAGIC")
    timeout 280 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$T/k0.img" -m 512 \
        -append "osum vfs usb nokbd bus script=sh /t/s.sh;exit" \
        -serial "file:$T/bus.txt" -display none -no-reboot \
        -drive "file=$T/d2.img,format=raw,if=ide,index=0" \
        -device qemu-xhci -drive "file=$T/stick2.img,format=raw,if=none,id=stk2" -device usb-storage,drive=stk2 \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/bus.txt" > "$T/b.klar"
    has "$T/b.klar" "==END==" "the script ran to its end"
    part "$T/b.klar" LIST MENU > "$T/q1.txt"
    has "$T/q1.txt" "stickwr.write" "the broker lists stickwr.write"
    has "$T/q1.txt" "stickwr.writefile" "the broker lists stickwr.writefile"
    part "$T/b.klar" MENU DRY > "$T/q2.txt"
    has "$T/q2.txt" "stickwr.writefile" "menu: an .iso file is offered 'stickwr.writefile'"
    [ "$(grep -ac 'stickwr.writefile' "$T/q2.txt")" = 1 ] && ok "menu: a .txt file is NOT offered it (menuext)" || bad "menu: stickwr.writefile offered $(grep -ac 'stickwr.writefile' "$T/q2.txt") times"
    part "$T/b.klar" DRY HDA > "$T/q3.txt"
    has "$T/q3.txt" "dry=1" "dry run: the stick answers with dry=1 and changes nothing"
    part "$T/b.klar" HDA BIG > "$T/q4.txt"
    has "$T/q4.txt" "confirm " "critical: the call parks and asks first"
    has "$T/q4.txt" "err refused_target" "after confirm: /dev/hda is refused"
    part "$T/b.klar" BIG W1 > "$T/q5.txt"
    has "$T/q5.txt" "err too_big" "a 5 MiB image on a 4 MiB stick: too_big"
    part "$T/b.klar" W1 W2 > "$T/q6.txt"
    has "$T/q6.txt" "confirm " "write: parked until confirmed"
    has "$T/q6.txt" "written=200003" "write: 200003 octets"
    has "$T/q6.txt" "blocks=4" "write: 4 blocks"
    has "$T/q6.txt" "verified=1" "write: verified"
    part "$T/b.klar" W2 NOIMG > "$T/q7.txt"
    has "$T/q7.txt" "written=70000" "menu action: 70000 octets onto the first stick"
    part "$T/b.klar" NOIMG END > "$T/q8.txt"
    has "$T/q8.txt" "err refused_source" "menu action on a .txt: refused_source"
    # THE HOST MEASURES the stick: image 2 on top of image 1, zeros behind
    cmp -n 70000 "$T/other.img" "$T/stick2.img" >/dev/null 2>&1 \
        && ok "HOST: the first 70000 octets equal other.img (second write)" || bad "HOST: other.img is not on the stick"
    cmp -i 70000:70000 -n $((200003-70000)) "$T/boot2.img" "$T/stick2.img" >/dev/null 2>&1 \
        && ok "HOST: octets 70000..200003 still equal boot.img (first write, not clobbered)" || bad "HOST: first write lost or changed"
    local tail_zero; tail_zero=$(tail -c +200004 "$T/stick2.img" | tr -d '\0' | wc -c)
    [ "$tail_zero" = 0 ] && ok "HOST: everything behind the image is still zero (hda/big/refused writes did nothing)" || bad "HOST: $tail_zero non-zero octets behind the image"
    local hda_after; hda_after=$(count_marker "$T/d2.img" "$MAGIC")
    [ "$hda_after" = "$hda_before" ] && ok "HOST: hda has no extra marker copy ($hda_before -> $hda_after)" || bad "HOST: hda marker $hda_before -> $hda_after"
}

for s in $STAGES; do
    case $s in
        host) stage_host ;;
        hot) stage_hot ;;
        bus) stage_bus ;;
        *) echo "unknown stage $s"; exit 2 ;;
    esac
done
keep
echo "STICKWR: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
