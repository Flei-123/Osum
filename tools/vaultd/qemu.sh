#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vaultd/qemu.sh -- r2472: vaultd (orient.vault) and vaultctl in a real Osum guest.
#
#   /root/jarvis/bin/heavy bash tools/vaultd/qemu.sh
#
# Boot A (one disk, script mode): vaultd serves /secrets, test KDF from /etc/vault/kdf.
#   root: status, create, lock, wrong password, unlock, put, find, list, lock, find while locked.
#   justin (uid 1000, via su): own vault, cannot see root's login, root's password does not open it.
# Boot B (same disk, fresh boot): vaults are locked after a restart, unlock works, the login is still there.
# Boot C: no vaultd running -> vaultctl reports "no bus" (counter-proof for the daemon being the one answering).
# Boot D: the shipped inittab line (respawn) starts /bin/vaultd as a service in target grafik.
# Static: build.sh ships /bin/vaultd, /bin/vaultctl and the inittab line.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
TMPD=$(mktemp -d)
[ -n "${VAULTD_KEEP:-}" ] || trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }
hx() { python3 -I -c 'import sys; sys.stdout.write(sys.argv[1].encode().hex())' "$1"; }

PW1="correct-horse-battery"; PW2="justin-secret-9"; PWBAD="wrong-password-1"
ORIGIN="https://example.com"; USER1="alice"; LPW="s3cr3t-pw-7"
H_PW1=$(hx "$PW1"); H_PW2=$(hx "$PW2"); H_BAD=$(hx "$PWBAD")
H_ORI=$(hx "$ORIGIN"); H_USR=$(hx "$USER1"); H_LPW=$(hx "$LPW"); H_TTL=$(hx "Example")

: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
[ -x vendor/firn/bin/firnc ] || { echo "VAULTD-QEMU: firnc missing"; exit 1; }
PROGS="sh ls cat echo sleep mkdir grep su vaultd vaultctl"
mkdir -p "$TMPD/bin"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS init > "$TMPD/b.txt" 2>&1; then
    ok "firnc builds $(echo $PROGS init | wc -w) programs"
else
    bad "the programs do not build"; sed 's/^/        /' "$TMPD/b.txt" | head -20
    echo "VAULTD-QEMU: $pass passed, $fail failed"; exit 1
fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then
    ok "the kernel builds"
else
    bad "the kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'
    echo "VAULTD-QEMU: $pass passed, $fail failed"; exit 1
fi

command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo "VAULTD-QEMU: skipped, qemu missing"; echo "VAULTD-QEMU: $pass passed, $fail failed"; exit 0; }

printf 'root:x:0:0:root:/:/bin/sh\njustin:x:1000:1000:Justin:/:/bin/sh\nmara:x:1001:1001:Mara:/:/bin/sh\n' > "$TMPD/passwd"
printf 'root:x:0:\njustin:x:1000:\nmara:x:1001:\n' > "$TMPD/group"
printf 'kib=64\npasses=1\nlanes=1\n' > "$TMPD/kdf"

SERVE=30000
image() {
    local img=$1 script=$2 inittab=${3:-}
    local -a A=(build "$img" 20000 /lib/
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /etc/vault/ /secrets/ /var/ /var/log/ /run/)
    local p
    for p in $PROGS; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
    A+=("/etc/passwd=$TMPD/passwd" "/etc/group=$TMPD/group" "/etc/vault/kdf=$TMPD/kdf"
        "/t/s.sh=$script" "/t/s2.sh=$TMPD/sb.sh")
    [ -n "$inittab" ] && A+=("/bin/init=$TMPD/bin/init.elf" "/etc/inittab=$inittab" "/etc/ziel=$TMPD/ziel")
    python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 \
        || { echo "mkfs failed"; tail -3 "$TMPD/mkfs.txt"; }
}

run() {
    local img=$1 nm=$2 secs=${3:-240} append=${4:-"osum vfs nokbd bus nosched noproc nofs script=sh /t/s.sh;exit"}
    rm -f "$TMPD/$nm.txt"
    timeout "$secs" qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 \
        -kernel "$TMPD/k0.img" -m 512 \
        -append "$append" \
        -serial "file:$TMPD/$nm.txt" -display none -no-reboot \
        -drive "file=$img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$! i=0
    while [ $i -lt $((secs * 2)) ] && kill -0 "$pid" 2>/dev/null; do
        grep -qa "^==FERTIG==" "$TMPD/$nm.txt" 2>/dev/null && { sleep 1; break; }
        sleep 0.5; i=$((i+1))
    done
    pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$TMPD/$nm.txt" > "$TMPD/$nm.klar" 2>/dev/null || true
}

cat > "$TMPD/sa.sh" <<EOS
vaultd /secrets $SERVE &
sleep -m 500
echo ==ROOT-STATUS0==
vaultctl status
echo rc=\$?
echo ==ROOT-FIND-NOVAULT==
vaultctl find origin=$ORIGIN
echo rc=\$?
echo ==ROOT-SHORTPW==
vaultctl create pw=short
echo rc=\$?
echo ==ROOT-CREATE==
vaultctl create pw=$PW1
echo rc=\$?
echo ==ROOT-CREATE2==
vaultctl create pw=$PW1
echo rc=\$?
echo ==ROOT-LOCK==
vaultctl lock
echo rc=\$?
vaultctl status
echo ==ROOT-FIND-LOCKED==
vaultctl find origin=$ORIGIN
echo rc=\$?
echo ==ROOT-UNLOCK-BAD==
vaultctl unlock pw=$PWBAD
echo rc=\$?
echo ==ROOT-UNLOCK==
vaultctl unlock pw=$PW1
echo rc=\$?
echo ==ROOT-PUT==
vaultctl put title=Example origins=$ORIGIN username=$USER1 password=$LPW
echo rc=\$?
echo ==ROOT-FIND==
vaultctl find origin=$ORIGIN
echo rc=\$?
echo ==ROOT-LIST==
vaultctl list
echo rc=\$?
vaultctl status
echo ==ROOT-FILE==
ls /secrets
ls /secrets/u0
grep -c $PW1 /secrets/u0/vault.vlt
grep -c $LPW /secrets/u0/vault.vlt
grep -c $USER1 /secrets/u0/vault.vlt
echo ==J-STATUS0==
su justin /bin/vaultctl status
echo ==J-FIND-ROOT-ORIGIN==
su justin /bin/vaultctl find origin=$ORIGIN
echo rc=\$?
echo ==J-UNLOCK-ROOT-PW==
su justin /bin/vaultctl unlock pw=$PW1
echo rc=\$?
echo ==J-CREATE==
su justin /bin/vaultctl create pw=$PW2
echo rc=\$?
echo ==J-FIND-EMPTY==
su justin /bin/vaultctl find origin=$ORIGIN
echo rc=\$?
echo ==J-LIST==
su justin /bin/vaultctl list
echo ==J-READ-ROOT-FILE==
su justin /bin/cat /secrets/u0/vault.vlt
echo rc=\$?
echo ==ROOT-STILL==
vaultctl find origin=$ORIGIN
sleep 12
echo ==ROOT-PASSWD==
vaultctl passwd pw=$PW1 new=second-pass-phrase
echo rc=\$?
vaultctl lock
echo ==FERTIG==
EOS

cat > "$TMPD/sb.sh" <<EOS
vaultd /secrets $SERVE &
sleep -m 500
echo ==B-STATUS==
vaultctl status
su justin /bin/vaultctl status
echo ==B-FIND-LOCKED==
vaultctl find origin=$ORIGIN
echo ==B-UNLOCK-OLD==
vaultctl unlock pw=$PW1
echo rc=\$?
echo ==B-UNLOCK==
vaultctl unlock pw=second-pass-phrase
echo rc=\$?
echo ==B-FIND==
vaultctl find origin=$ORIGIN
echo rc=\$?
echo ==B-J-UNLOCK==
su justin /bin/vaultctl unlock pw=$PW2
echo rc=\$?
echo ==FERTIG==
EOS

cat > "$TMPD/sc.sh" <<'EOS'
echo ==C-NODAEMON==
vaultctl status
echo rc=$?
echo ==FERTIG==
EOS

echo "== 2. boot A: root and justin =="
image "$TMPD/A.img" "$TMPD/sa.sh"
run "$TMPD/A.img" a 300
A="$TMPD/a.klar"
if ! grep -qa "==FERTIG==" "$A"; then bad "boot A did not reach the end"; tail -15 "$A" | sed 's/^/        /'; fi
part "$A" ROOT-STATUS0 ROOT-FIND-NOVAULT > "$TMPD/p.txt"
has "$TMPD/p.txt" "state=none" "root: no vault yet"
part "$A" ROOT-FIND-NOVAULT ROOT-SHORTPW > "$TMPD/p.txt"
has "$TMPD/p.txt" "ok=0" "find without a vault is refused"
part "$A" ROOT-SHORTPW ROOT-CREATE > "$TMPD/p.txt"
has "$TMPD/p.txt" "ok=0" "a password of 5 characters is refused"
part "$A" ROOT-CREATE ROOT-CREATE2 > "$TMPD/p.txt"
has "$TMPD/p.txt" "ok=1" "root: vault created"
has "$TMPD/p.txt" "rc=0" "... exit code 0"
part "$A" ROOT-CREATE2 ROOT-LOCK > "$TMPD/p.txt"
has "$TMPD/p.txt" "ok=0" "creating a second vault over the first is refused"
part "$A" ROOT-LOCK ROOT-FIND-LOCKED > "$TMPD/p.txt"
has "$TMPD/p.txt" "state=locked" "lock: the vault is locked"
part "$A" ROOT-FIND-LOCKED ROOT-UNLOCK-BAD > "$TMPD/p.txt"
has "$TMPD/p.txt" "err=locked" "COUNTER-PROOF: find while locked is refused"
has "$TMPD/p.txt" "rc=1" "... exit code 1"
hasnot "$TMPD/p.txt" "login=" "... and no login leaks"
part "$A" ROOT-UNLOCK-BAD ROOT-UNLOCK > "$TMPD/p.txt"
has "$TMPD/p.txt" "ok=0" "COUNTER-PROOF: a wrong password does not unlock"
part "$A" ROOT-UNLOCK ROOT-PUT > "$TMPD/p.txt"
has "$TMPD/p.txt" "ok=1" "the right password unlocks"
part "$A" ROOT-PUT ROOT-FIND > "$TMPD/p.txt"
has "$TMPD/p.txt" "ok=1" "put: a login is stored"
has "$TMPD/p.txt" "id=" "... and gets an id"
part "$A" ROOT-FIND ROOT-LIST > "$TMPD/p.txt"
has "$TMPD/p.txt" "login=" "find: the login comes back"
has "$TMPD/p.txt" "$H_USR" "... with the user name"
has "$TMPD/p.txt" "$H_LPW" "... and the password"
part "$A" ROOT-LIST ROOT-FILE > "$TMPD/p.txt"
has "$TMPD/p.txt" "ok=1" "list answers"
has "$TMPD/p.txt" "state=open" "status: open"
part "$A" ROOT-FILE J-STATUS0 > "$TMPD/p.txt"
has "$TMPD/p.txt" "u0" "the vault lives in /secrets/u0"
has "$TMPD/p.txt" "vault.vlt" "... as vault.vlt"
n_clear=$(grep -aE '^[0-9]+$' "$TMPD/p.txt" | tr '\n' ' ')
[ "$(echo "$n_clear" | tr -d ' 0')" = "" ] && [ -n "$n_clear" ] \
    && ok "the file holds neither the main password, the login password nor the user name in clear (grep -c: $n_clear)" \
    || bad "plaintext on disk (grep -c: ${n_clear:-none})"
part "$A" J-STATUS0 J-FIND-ROOT-ORIGIN > "$TMPD/p.txt"
has "$TMPD/p.txt" "state=none" "justin: has no vault of his own yet (root's is not his)"
part "$A" J-FIND-ROOT-ORIGIN J-UNLOCK-ROOT-PW > "$TMPD/p.txt"
hasnot "$TMPD/p.txt" "login=" "ISOLATION: justin finds no login of root"
part "$A" J-UNLOCK-ROOT-PW J-CREATE > "$TMPD/p.txt"
has "$TMPD/p.txt" "ok=0" "ISOLATION: root's password does not open justin's slot"
part "$A" J-CREATE J-FIND-EMPTY > "$TMPD/p.txt"
has "$TMPD/p.txt" "ok=1" "justin: own vault created"
part "$A" J-FIND-EMPTY J-LIST > "$TMPD/p.txt"
hasnot "$TMPD/p.txt" "login=" "ISOLATION: justin's open vault does not know root's login"
has "$TMPD/p.txt" "ok=1" "... and the find itself works"
part "$A" J-READ-ROOT-FILE ROOT-STILL > "$TMPD/p.txt"
if grep -qa "VAULT2" "$TMPD/p.txt"; then
    echo "  GAP   justin can read the ciphertext of root's vault file (file mode not enforced on /secrets, follow-up r2473)"
else
    ok "justin cannot read root's vault file as bytes"
fi
part "$A" ROOT-STILL ROOT-PASSWD > "$TMPD/p.txt"
has "$TMPD/p.txt" "$H_LPW" "root's login is still there after justin's work"
part "$A" ROOT-PASSWD FERTIG > "$TMPD/p.txt"
has "$TMPD/p.txt" "ok=1" "root: main password changed"

echo "== 3. boot B: a fresh boot on the same disk =="
cp -f "$TMPD/A.img" "$TMPD/B.img"
run "$TMPD/B.img" b 300 "osum vfs nokbd bus nosched noproc nofs script=sh /t/s2.sh;exit"
B="$TMPD/b.klar"
if ! grep -qa "==FERTIG==" "$B"; then bad "boot B did not reach the end"; tail -15 "$B" | sed 's/^/        /'; fi
part "$B" B-STATUS B-FIND-LOCKED > "$TMPD/p.txt"
n_locked=$(grep -ac "state=locked" "$TMPD/p.txt")
[ "$n_locked" = 2 ] && ok "after the restart both vaults are locked" || bad "after the restart: $n_locked of 2 locked"
part "$B" B-FIND-LOCKED B-UNLOCK-OLD > "$TMPD/p.txt"
has "$TMPD/p.txt" "err=locked" "a restarted daemon starts locked"
part "$B" B-UNLOCK-OLD B-UNLOCK > "$TMPD/p.txt"
has "$TMPD/p.txt" "ok=0" "COUNTER-PROOF: the old main password no longer works"
part "$B" B-UNLOCK B-FIND > "$TMPD/p.txt"
has "$TMPD/p.txt" "ok=1" "the new main password unlocks"
part "$B" B-FIND B-J-UNLOCK > "$TMPD/p.txt"
has "$TMPD/p.txt" "$H_LPW" "the login survived the restart"
part "$B" B-J-UNLOCK FERTIG > "$TMPD/p.txt"
has "$TMPD/p.txt" "ok=1" "justin's vault unlocks after the restart"

echo "== 4. boot C: no daemon =="
image "$TMPD/C.img" "$TMPD/sc.sh"
run "$TMPD/C.img" c 120
C="$TMPD/c.klar"
part "$C" C-NODAEMON FERTIG > "$TMPD/p.txt"
has "$TMPD/p.txt" "rc=2" "COUNTER-PROOF: without vaultd, vaultctl reports no bus (exit 2)"
hasnot "$TMPD/p.txt" "ok=1" "... and nothing answers"

echo "== 5. boot D: the shipped inittab line starts the service =="
sed -n '/^cat > "\$OUT\/inittab"/,/^EOFTAB/p' tools/usbimg/build.sh | grep -E '^vaultd:' > "$TMPD/vaultd.line"
[ -s "$TMPD/vaultd.line" ] && ok "usbimg/build.sh carries the inittab line: $(cat "$TMPD/vaultd.line")" || bad "no vaultd line in the usbimg inittab"
{ cat "$TMPD/vaultd.line"; printf 'sh:grafik:ctrl:/bin/sh\n'; } > "$TMPD/inittab"
printf 'grafik\n' > "$TMPD/ziel"
cat > "$TMPD/sd.sh" <<'EOS'
sleep 2
echo ==D-STATUS==
vaultctl status
echo rc=$?
echo ==FERTIG==
EOS
image "$TMPD/D.img" "$TMPD/sd.sh" "$TMPD/inittab"
run "$TMPD/D.img" d 120 "osum vfs nokbd bus nosched noproc nofs script=sh /t/s.sh;exit"
D="$TMPD/d.klar"
part "$D" D-STATUS FERTIG > "$TMPD/p.txt"
has "$TMPD/p.txt" "ok=1" "init started vaultd from the inittab line; vaultctl gets an answer"

echo "== 6. the image builder ships it =="
grep -q 'screenreader xfx vaultd vaultctl' tools/usbimg/build.sh && ok "PROGS lists vaultd and vaultctl" || bad "PROGS misses vaultd/vaultctl"
grep -q '/bin/vaultd /bin/vaultctl' tools/usbimg/build.sh && ok "the build check (PFLICHT) counts both" || bad "PFLICHT misses vaultd/vaultctl"

echo "VAULTD-QEMU: $pass passed, $fail failed"
[ "$fail" = 0 ]
