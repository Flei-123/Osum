#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."

export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
BIG_MIB=${BIG_MIB:-24}
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hin() { printf '  --    %s\n' "$1"; }
seg() { awk -v n="@@$2" '/^@@/{on=($0==n);next} on' "$1" | tr -d '\r'; }
has() { seg "$1" "$2" | grep -qaE -- "$3" && ok "$4" || bad "$4 -- '$3' missing in @@$2"; }
hasnot() { seg "$1" "$2" | grep -qaE -- "$3" && bad "$4 -- '$3' present in @@$2" || ok "$4"; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh failed"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc missing: $FIRNC"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "XFX: skipped, qemu-system-x86_64 missing"
    exit 0
fi

ACCEL=""
[ -r /dev/kvm ] && [ -w /dev/kvm ] && ACCEL="-accel kvm -cpu host"

echo "== 1. build =="

bash tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/b0.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel build failed"; head -12 "$TMPD/b0.txt"; }
[ -f "$TMPD/k0.img" ] || { echo "XFX: $pass passed, $((fail+1)) failed"; exit 1; }

SRC="$TMPD/src"
mkdir -p "$SRC"
cp kernel/user/*.fi tools/xfx/*.fi "$SRC/"
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s does not assemble"
PROGS="sh echo cat sleep tar xfx xfxt xfxstub"
for p in $PROGS; do
    "$FIRNC" "$SRC/$p.fi" -o "$TMPD/$p.o" >"$TMPD/e$p" 2>&1 || {
        bad "firnc fails on $p.fi"; head -6 "$TMPD/e$p"; continue; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null \
        || { bad "ld fails on $p"; continue; }
    strip --strip-all "$TMPD/$p.elf"
done
[ -f "$TMPD/xfx.elf" ] && [ -f "$TMPD/xfxstub.elf" ] && ok "programs built: $PROGS" || bad "programs missing"
undef=$(nm -u "$TMPD/xfx.elf" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
[ -z "$undef" ] && ok "xfx has no undefined symbols" || bad "xfx undefined: $undef"

echo "== 2. images =="

python3 -I - "$TMPD" "$BIG_MIB" <<'PY'
import hashlib, io, os, sys, tarfile
d, big = sys.argv[1], int(sys.argv[2])
stub = open(d + "/xfxstub.elf", "rb").read()

def make_tar(path, filler):
    with tarfile.open(path, "w", format=tarfile.USTAR_FORMAT) as t:
        for dirname in ("usr", "usr/lib", "usr/lib/firefox"):
            i = tarfile.TarInfo(dirname)
            i.type = tarfile.DIRTYPE
            i.mode = 0o755
            t.addfile(i)
        i = tarfile.TarInfo("usr/lib/firefox/firefox")
        i.size = len(stub)
        i.mode = 0o755
        t.addfile(i, io.BytesIO(stub))
        if filler:
            blob = bytes((k * 31 + 7) & 255 for k in range(65536)) * (filler * 16)
            i = tarfile.TarInfo("usr/lib/firefox/libfiller.so")
            i.size = len(blob)
            i.mode = 0o644
            t.addfile(i, io.BytesIO(blob))

def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()

def manifest(path, out, flip=False):
    s = sha(path)
    if flip:
        s = ("0" if s[0] != "0" else "1") + s[1:]
    open(out, "w").write("files 2\nlinks 0\ntar %d %s\ngz 0 %s\n" % (os.path.getsize(path), s, "0" * 64))

make_tar(d + "/good.tar", 0)
raw = open(d + "/good.tar", "rb").read()
cuts = [0, len(raw) // 3 + 7, 2 * len(raw) // 3 + 11, len(raw)]
for k in range(3):
    open(d + "/good.part%03d" % k, "wb").write(raw[cuts[k]:cuts[k + 1]])
make_tar(d + "/big.tar", big)
manifest(d + "/good.tar", d + "/good.manifest")
manifest(d + "/good.tar", d + "/bad.manifest", True)
manifest(d + "/big.tar", d + "/big.manifest")
braw = open(d + "/big.tar", "rb").read()
bq = len(braw) // 4
for k in range(4):
    open(d + "/big.part%03d" % k, "wb").write(braw[k * bq:(k + 1) * bq if k < 3 else len(braw)])
open(d + "/user.js", "w").write('user_pref("browser.shell.checkDefaultBrowser", false);\n')
open(d + "/passwd", "w").write("root:x:0:0:root:/:/bin/sh\njustin:x:1000:1000:Justin:/home/justin:/bin/sh\n")
open(d + "/group", "w").write("root:x:0:\njustin:x:1000:\n")
PY
[ -f "$TMPD/good.tar" ] && ok "stub pack tar and manifests written" || bad "pack generation failed"

cat > "$TMPD/main.sh" <<'SCRIPT'
echo @@usage
/bin/xfx
echo rc=$?
/bin/xfx bogus
echo rc=$?
/bin/xfx start now
echo rc=$?
/bin/xfx status extra
echo rc=$?
/bin/xfx install install
echo rc=$?
echo @@fresh
/bin/xfx status
/bin/xfx start
echo rc=$?
/bin/xfx stop
echo rc=$?
echo @@install
/bin/xfx install
echo rc=$?
/bin/xfxt waitfor /run/xfx.install done 120
/bin/xfx status
/bin/xfxt exists /usr/lib/firefox/firefox
/bin/xfxt exists /usr/share/xfx/firefox.tar
echo @@again
/bin/xfx install
echo rc=$?
/bin/xfxt waitfor /run/xfx.install done 60
/bin/xfx status
echo @@nosession
/bin/xfx start
echo rc=$?
/bin/xfxt procs
echo @@start
/bin/xfxt sess 1000
/bin/xfx start
echo rc=$?
/bin/xfx status
/bin/xfxt procs
/bin/xfxt exists /run/xfx-1000/wayland-0
/bin/xfxt exists /home/justin/.xfx/profile/user.js
echo @@twice
/bin/xfx start
echo rc=$?
echo @@nonroot
/bin/xfxt asuser 1000 /bin/xfx start
/bin/xfxt asuser 1000 /bin/xfx install
/bin/xfxt asuser 1000 /bin/xfx stop
/bin/xfxt asuser 1000 /bin/xfxt canwrite /run/hack
/bin/xfxt asuser 1000 /bin/xfxt canwrite /usr/share/xfx/hack
/bin/xfx status
echo @@stop
/bin/xfx stop
echo rc=$?
/bin/xfx status
/bin/xfxt procs
/bin/xfxt exists /run/xfx-1000/wayland-0
echo @@log
cat /var/log/xfx.log
echo @@end
SCRIPT

cat > "$TMPD/bad.sh" <<'SCRIPT'
echo @@bad
/bin/xfx install
echo rc=$?
/bin/xfxt waitfor /run/xfx.install failed 120
/bin/xfx status
/bin/xfxt exists /usr/lib/firefox/firefox
/bin/xfxt exists /usr/lib
/bin/xfxt exists /usr/share/xfx/installed
/bin/xfx start
echo rc=$?
cat /var/log/xfx.log
echo @@end
SCRIPT

cat > "$TMPD/big.sh" <<'SCRIPT'
echo @@big
/bin/xfxt clock
/bin/xfx install
/bin/xfxt waitfor /run/xfx.install done 900
/bin/xfxt clock
/bin/xfx status
/bin/xfxt size /usr/lib/firefox/libfiller.so
cat /var/log/xfx.log
echo @@end
SCRIPT

DIRS="/bin/ /etc/ /run/ /tmp/ /t/ /var/ /var/log/ /usr/ /usr/share/ /usr/share/xfx/ /home/@755:0:0 /home/justin/@700:1000:1000"
SPEC=""
for p in sh echo cat sleep tar xfx xfxt; do
    SPEC="$SPEC /bin/$p=$TMPD/$p.elf"
done
SPEC="$SPEC /bin/wayd=$TMPD/xfxstub.elf"
BASE="$SPEC /etc/passwd=$TMPD/passwd@644:0:0 /etc/group=$TMPD/group@644:0:0 /usr/share/xfx/user.js=$TMPD/user.js@644:0:0"

build_parts_img() {
    local name=$1 script=$2 plist="" src=${PARTS_SRC:-good} blocks=${PARTS_BLOCKS:-16384}
    shift 2
    for k in "$@"; do plist="$plist /usr/share/xfx/firefox.tar.part$k=$TMPD/$src.part$k@644:0:0"; done
    python3 tools/osum/mkfs.py build "$TMPD/$name.img" "$blocks" $DIRS $BASE $plist \
        "/usr/share/xfx/firefox.manifest=$TMPD/$src.manifest@644:0:0" \
        "/t/run.sh=$TMPD/$script@644:0:0" > "$TMPD/mkfs-$name.txt" 2>&1 \
        && ok "image $name built" || { bad "mkfs fails for $name"; head -5 "$TMPD/mkfs-$name.txt"; }
}

build_img() {
    local name=$1 tar=$2 man=$3 script=$4 blocks=$5
    python3 tools/osum/mkfs.py build "$TMPD/$name.img" "$blocks" $DIRS $BASE \
        "/usr/share/xfx/firefox.tar=$TMPD/$tar@644:0:0" "/usr/share/xfx/firefox.manifest=$TMPD/$man@644:0:0" \
        "/t/run.sh=$TMPD/$script@644:0:0" > "$TMPD/mkfs-$name.txt" 2>&1 \
        && ok "image $name built" || { bad "mkfs fails for $name"; head -5 "$TMPD/mkfs-$name.txt"; }
}
cat > "$TMPD/parts.sh" <<'SCRIPT'
echo @@parts
/bin/xfx install
/bin/xfxt waitfor /run/xfx.install done 120
/bin/xfx status
/bin/xfxt exists /usr/lib/firefox/firefox
/bin/xfxt exists /usr/share/xfx/firefox.tar
/bin/xfxt exists /usr/share/xfx/firefox.tar.part000
/bin/xfxt exists /usr/share/xfx/firefox.tar.part001
/bin/xfxt exists /usr/share/xfx/firefox.tar.part002
cat /var/log/xfx.log
echo @@end
SCRIPT

cat > "$TMPD/gap.sh" <<'SCRIPT'
echo @@gap
/bin/xfx install
/bin/xfxt waitfor /run/xfx.install failed 120
/bin/xfx status
/bin/xfxt exists /usr/lib/firefox/firefox
/bin/xfxt exists /usr/share/xfx/installed
cat /var/log/xfx.log
echo @@end
SCRIPT

build_img main good.tar good.manifest main.sh 16384
build_img bad good.tar bad.manifest bad.sh 16384
build_img big big.tar big.manifest big.sh $(( BIG_MIB * 2 * 2 * 1024 + 32768 ))
build_parts_img parts parts.sh 000 001 002
build_parts_img gap gap.sh 000 002
cat > "$TMPD/bigparts.sh" <<'SCRIPT'
echo @@bigparts
/bin/xfx install
/bin/xfxt waitfor /run/xfx.install done 900
/bin/xfx status
cat /var/log/xfx.log
echo @@end
SCRIPT
PARTS_SRC=big PARTS_BLOCKS=$(( BIG_MIB * 3 * 2048 + 32768 )) build_parts_img bigparts bigparts.sh 000 001 002 003

BASIS="nokbd nosched noproc nofs noring3 vfs"
run_case() {
    local name=$1 limit=$2 words=${3:-} drive
    cp "$TMPD/$name.img" "$TMPD/live-$name.img"
    if [ -n "$words" ]; then
        drive="-device ahci,id=ahci -drive file=$TMPD/live-$name.img,format=raw,if=none,id=d0 -device ide-hd,drive=d0,bus=ahci.0"
    else
        drive="-drive file=$TMPD/live-$name.img,format=raw,if=ide,index=0"
    fi
    timeout "$limit" qemu-system-x86_64 $ACCEL -kernel "$TMPD/k0.img" -m 512 \
        -append "osum $BASIS ${XFX_EXTRA:-} script=sh /t/run.sh" -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        $drive -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    RC=$?
    [ -n "${XFX_KEEP:-}" ] && cp "$TMPD/$name.txt" "$XFX_KEEP/" 2>/dev/null
}

if [ "${ONLY:-}" != big ]; then
echo "== 3. main flow =="
run_case main 400
M="$TMPD/main.txt"
hin "qemu rc=$RC"
grep -qa '^@@end' "$M" && ok "script ran to the end" || bad "script did not finish"

has "$M" usage 'usage: xfx install\|start\|stop\|status' "no argument prints usage"
[ "$(seg "$M" usage | grep -ac '^rc=2')" = 5 ] && ok "no args, unknown subcommand and extra args all return 2" || bad "usage rc is not 2 five times: $(seg "$M" usage | grep -a '^rc=' | tr '\n' ' ')"
has "$M" fresh 'installed=no install=idle firefox=stopped' "fresh status"
has "$M" fresh 'not installed' "start refuses without installation"
has "$M" install 'install started' "install returns at once"
has "$M" install 'waitfor=ok' "install reaches done"
has "$M" install 'installed=yes install=done firefox=stopped' "status after install"
has "$M" install 'exists=yes' "firefox binary extracted"
[ "$(seg "$M" install | grep -ac 'exists=no')" = 1 ] && ok "pack tar removed after install" || bad "pack tar still present or binary missing"
has "$M" again 'install started' "second install accepted"
has "$M" again 'waitfor=ok' "second install finishes"
has "$M" again 'installed=yes install=done' "still installed after second install"
has "$M" nosession 'no desktop session' "start refused without session"
has "$M" nosession '^rc=1' "refusal returns 1"
hasnot "$M" nosession 'proc (firefox|wayd)' "no firefox/wayd without session"
has "$M" start 'sess rc=0' "session set to uid 1000"
has "$M" start 'xfx: started uid=1000' "start reports uid 1000"
has "$M" start 'installed=yes install=done firefox=running pid=[0-9]+ uid=1000' "status: firefox running as 1000 (process name = basename)"
has "$M" start 'proc firefox +uid=1000' "PSTAT shows firefox uid 1000"
has "$M" start 'proc wayd +uid=1000' "PSTAT shows wayd uid 1000"
hasnot "$M" start 'proc (firefox|wayd) +uid=0' "no firefox/wayd as root"
[ "$(seg "$M" start | grep -ac 'exists=yes')" = 2 ] && ok "socket and profile user.js exist" || bad "socket or profile user.js missing"
has "$M" twice 'already running' "second start refused"
has "$M" nonroot 'root only' "non-root start/install/stop refused"
[ "$(seg "$M" nonroot | grep -ac 'xfx: root only')" = 3 ] && ok "all three privileged subcommands refused for uid 1000" || bad "not three refusals for uid 1000"
[ "$(seg "$M" nonroot | grep -ac 'canwrite=no')" = 2 ] && ok "uid 1000 cannot write /run or /usr/share/xfx" || bad "uid 1000 can write a root-only path"
has "$M" nonroot 'firefox=running' "refused calls did not stop firefox"
has "$M" stop 'xfx: stopped' "stop reports stopped"
has "$M" stop 'firefox=stopped' "status after stop"
hasnot "$M" stop 'proc (firefox|wayd) ' "firefox and wayd gone after stop"
has "$M" stop 'exists=no' "socket removed after stop"
has "$M" log 'xfxstub: wayd uid=1000' "wayd ran as uid 1000"
has "$M" log 'xfxstub: /usr/lib/firefox/firefox uid=1000 home=/home/justin xdg=/run/xfx-1000 args=5' "firefox ran as uid 1000 with session env and 5 args"
has "$M" log 'sha256 ok, extracting' "sha verified before extraction"
has "$M" log 'already installed' "second install was idempotent"
[ "$(seg "$M" log | grep -ac 'install done')" = 1 ] && ok "extraction ran exactly once" || bad "extraction did not run exactly once"

echo "== 4. bad sha =="
run_case bad 300
B="$TMPD/bad.txt"
grep -qa '^@@end' "$B" && ok "script ran to the end" || bad "script did not finish"
has "$B" bad 'waitfor=ok' "install ends in failed"
has "$B" bad 'sha256 mismatch, nothing extracted' "mismatch reported"
has "$B" bad 'installed=no install=failed' "status failed, not installed"
[ "$(seg "$B" bad | grep -ac 'exists=no')" = 3 ] && ok "nothing extracted (no binary, no /usr/lib, no marker)" || bad "something was extracted"
has "$B" bad 'not installed' "start refused after failed install"

echo "== 4b. split pack =="
run_case parts 300
P="$TMPD/parts.txt"
grep -qa '^@@end' "$P" && ok "parts: script ran to the end" || bad "parts: script did not finish"
has "$P" parts 'waitfor=ok' "parts: install reaches done"
has "$P" parts 'installed=yes install=done' "parts: status after install"
has "$P" parts 'parts joined\+hashed in' "parts: joined message logged"
has "$P" parts 'sha256 ok, extracting' "parts: joined tar matches the manifest sha"
[ "$(seg "$P" parts | grep -ac 'exists=yes')" = 1 ] && ok "parts: only the firefox binary exists afterwards" || bad "parts: wrong set of files left (tar or parts remain)"
[ "$(seg "$P" parts | grep -ac 'exists=no')" = 4 ] && ok "parts: tar and all three parts removed" || bad "parts: tar or parts still present"

echo "== 4c. missing part =="
run_case gap 300
Q="$TMPD/gap.txt"
grep -qa '^@@end' "$Q" && ok "gap: script ran to the end" || bad "gap: script did not finish"
has "$Q" gap 'waitfor=ok' "gap: install ends in failed"
has "$Q" gap 'installed=no install=failed' "gap: status failed, not installed"
has "$Q" gap 'pack size differs from manifest' "gap: short pack refused by size"
[ "$(seg "$Q" gap | grep -ac 'exists=no')" = 2 ] && ok "gap: nothing extracted" || bad "gap: something was extracted"
fi

echo "== 5. hashing speed =="
run_case big 900 ahci
G="$TMPD/big.txt"
grep -qa '^@@end' "$G" && ok "script ran to the end" || bad "script did not finish"
has "$G" big 'waitfor=ok' "big pack installed"
hms=$(seg "$G" big | grep -aoE 'sha256 took [0-9]+ ms' | grep -oE '[0-9]+' | head -1)
tms=$(seg "$G" big | grep -aoE 'install done in [0-9]+ ms' | grep -oE '[0-9]+' | head -1)
if [ -n "${hms:-}" ] && [ -n "${tms:-}" ] && [ "$hms" -gt 0 ]; then
    hest=$(( 333 * hms / BIG_MIB / 1000 ))
    xest=$(( 333 * (tms - hms) / BIG_MIB / 1000 ))
    hin "sha256 of ${BIG_MIB} MiB: ${hms} ms; extraction: $((tms - hms)) ms"
    hin "333 MiB would take about ${hest} s to hash and ${xest} s to extract (tar speed is not gated here)"
    [ "$hest" -le "${XFX_MAX_HASH_SECONDS:-90}" ] && ok "estimated sha256 time for 333 MiB: ${hest} s" || bad "estimated sha256 time for 333 MiB: ${hest} s (limit ${XFX_MAX_HASH_SECONDS:-90})"
else
    bad "timing lines missing in the install log"
fi

echo "== 6. join + hash speed (split pack) =="
run_case bigparts 1200 ahci
J="$TMPD/bigparts.txt"
grep -qa '^@@end' "$J" && ok "bigparts: script ran to the end" || bad "bigparts: script did not finish"
has "$J" bigparts 'waitfor=ok' "bigparts: installed"
has "$J" bigparts 'sha256 ok, extracting' "bigparts: joined tar matches the manifest sha"
jms=$(seg "$J" bigparts | grep -aoE 'parts joined\+hashed in [0-9]+ ms' | grep -oE '[0-9]+' | head -1)
if [ -n "${jms:-}" ] && [ "$jms" -gt 0 ]; then
    jest=$(( 333 * jms / BIG_MIB / 1000 ))
    hin "join+hash of ${BIG_MIB} MiB: ${jms} ms; 333 MiB would take about ${jest} s"
    echo "METRIC join_hash_ms=${jms} mib=${BIG_MIB}"
    ok "join+hash timing line present"
else
    bad "join+hash timing line missing in the install log"
fi

echo "XFX: $pass passed, $fail failed"
[ "$fail" = 0 ]
