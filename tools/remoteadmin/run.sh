#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/remoteadmin/run.sh -- remote-admin gate: who may answer the trusted dialog.
#   bash tools/remoteadmin/run.sh            real kernel, then three mutant kernels that must fail
#   RA_MUTANT=authall|anypid|nolock bash tools/remoteadmin/run.sh   one mutant kernel (expected to fail)
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }
count() { grep -ac -- "$2" "$1" 2>/dev/null || true; }

TMPD=${1:-$(mktemp -d)}
. tools/lib/tmpdir.sh
osum_tmp_guard "${1:-}" "$TMPD"
MUTANT=${RA_MUTANT:-}
PROGS="sh ls cat echo sleep orientbus act settingsd"
. tools/lib/firnenv.sh

if [ -z "$MUTANT" ] && [ -z "${RA_CHILD:-}" ]; then
    SELF=$(readlink -f "$0")
    mkdir -p "$TMPD/shared"
    RA_CHILD=1 RA_SHARED="$TMPD/shared" bash "$SELF" "$TMPD/real" 2>&1 | sed 's/^/  /'
    REAL=${PIPESTATUS[0]}
    [ "$REAL" = 0 ] && ok "real kernel: all cases pass" || bad "real kernel: cases failed"
    for m in authall anypid nolock; do
        RA_CHILD=1 RA_MUTANT=$m RA_SHARED="$TMPD/shared" bash "$SELF" "$TMPD/mut_$m" > "$TMPD/mut_$m.log" 2>&1
        r=$?
        [ "$r" != 0 ] && ok "mutant $m is caught (gate red)" || { bad "mutant $m is NOT caught"; tail -5 "$TMPD/mut_$m.log"; }
    done
    echo "REMOTEADMIN: $pass passed, $fail failed"
    [ "$fail" = 0 ]
    exit
fi

mkdir -p "$TMPD"
BIN=${RA_SHARED:-$TMPD}/bin
if [ ! -f "$BIN/radmin" ]; then
    mkdir -p "$BIN"
    bash tools/sync/build.sh "$BIN" 0 $PROGS > "$TMPD/b.txt" 2>&1 && ok "programs build" \
        || { bad "programs do not build"; tail -8 "$TMPD/b.txt"; echo "REMOTEADMIN: $pass passed, $fail failed"; exit 1; }
    musl-gcc -static -O2 -nostartfiles -T tools/foreign/osum.ld -Wl,--build-id=none \
        -o "$BIN/radmin" tools/foreign/start.s tools/foreign/osum_main.c tools/remoteadmin/radmin.c 2> "$TMPD/cc.txt" \
        && ok "radmin builds" || { bad "radmin does not build"; head -5 "$TMPD/cc.txt"; echo "REMOTEADMIN: $pass passed, $fail failed"; exit 1; }
fi

KSRC=$ROOT
if [ -n "$MUTANT" ]; then
    KSRC="$TMPD/mut"; mkdir -p "$KSRC"
    tar -c --exclude=.git --exclude=reports --exclude=docs/shots . | tar -x -C "$KSRC"
    firnenv_prepare_old_tree "$KSRC"
    TIP="$KSRC/kernel/ipc/tip.fi"
    case "$MUTANT" in
        authall) sed -i '/^fn mark_by/,/^}/ s/remote_mode(state, pid) == REMOTE_ADMIN/remote_mode(state, pid) != REMOTE_OFF/' "$TIP" ;;
        anypid)  sed -i '/^fn remote_mode/,/^}/ s/if pid == 0 || gs(state, S_RPID) != pid {/if pid == 0 {/' "$TIP" ;;
        nolock)  sed -i '/^fn lock/,/^}/ s/ss(state, S_LOCK, 1)/ss(state, S_LOCK, 0)/' "$TIP" ;;
        *) echo "unknown mutant $MUTANT"; exit 2 ;;
    esac
    if cmp -s "$TIP" "$ROOT/kernel/ipc/tip.fi"; then bad "mutant $MUTANT did not change tip.fi"; echo "REMOTEADMIN: $pass passed, $fail failed"; exit 1; fi
fi
(cd "$KSRC" && ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0) > "$TMPD/k.txt" 2>&1 && ok "kernel builds${MUTANT:+ (mutant $MUTANT)}" \
    || { bad "kernel does not build"; tail -5 "$TMPD/k.txt"; echo "REMOTEADMIN: $pass passed, $fail failed"; exit 1; }

printf '# /etc/sperre.conf\nleerlauf=300\n' > "$TMPD/sperre.conf"
printf 'root:x:0:0:root:/:/bin/sh\n' > "$TMPD/passwd"
printf 'lang=en\n' > "$TMPD/locale.conf"
printf '# /etc/theme.conf\nscheme=night\nmode=dark\naccent=\nshape=classic\n' > "$TMPD/theme.conf"
cat > "$TMPD/g.sh" <<'EOS'
orientbus serve 0 &
sleep -m 300
settingsd serve 0 &
sleep 1
radmin nonroot 1000
echo ==C0==
act call settings.set key=lock.idle value=700 --as helper
sleep 3
radmin self 0 36
sleep 2
act call settings.get key=lock.idle
echo ==C1==
radmin self 1 36
sleep 2
act call settings.get key=lock.idle
echo ==C2==
radmin child 2 36
sleep 2
act call settings.get key=lock.idle
echo ==C3==
radmin lock 2 36
sleep 2
act call settings.get key=lock.idle
echo ==C4==
radmin self 2 36
sleep 4
act call settings.get key=lock.idle
echo ==C5==
radmin clear
act stop
echo ==FERTIG==
EOS
A=(build "$TMPD/disk.img" 32768 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf"
   "/lib/sans.ttf=assets/osum-sans.ttf" /bin/ /t/ /tmp/ /var/ /var/log/
   /etc/ /etc/actions.d/ /etc/orientbus/ /apps/
   "/etc/settings.schema=etc/settings.schema"
   "/etc/actions.d/settings.actions=etc/actions.d/settings.actions"
   "/etc/orientbus/policy=etc/orientbus/policy"
   "/etc/sperre.conf=$TMPD/sperre.conf" "/etc/theme.conf=$TMPD/theme.conf"
   "/etc/passwd=$TMPD/passwd" "/etc/locale.conf=$TMPD/locale.conf"
   /usr/ /usr/share/ /usr/share/locale/ /usr/share/locale/de/ /usr/share/locale/en/
   "/usr/share/locale/de/messages=locale/de/messages"
   "/usr/share/locale/en/messages=locale/en/messages"
   "/t/g.sh=$TMPD/g.sh" "/bin/radmin=$BIN/radmin")
[ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
[ -f assets/osum-sans-bold.ttf ] && A+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
cp assets/jarvis/rechte-justin.conf "$TMPD/permissions.conf"
A+=(/etc/jarvis/ /var/jarvis/ "/etc/jarvis/permissions.conf=$TMPD/permissions.conf")
A+=(/etc/schemas/)
for s in assets/schemes/*.scheme; do A+=("/etc/schemas/$(basename "$s" .scheme)=$s"); done
for p in $PROGS; do A+=("/bin/$p=$BIN/$p.elf"); done
bash tools/mkfsfi/mkfs.sh "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 && ok "disk built" \
    || { bad "mkfs"; tail -3 "$TMPD/mkfs.txt"; echo "REMOTEADMIN: $pass passed, $fail failed"; exit 1; }

ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
timeout 240 qemu-system-x86_64 "${ACC[@]}" -kernel "$TMPD/k0.img" -m 512 \
    -append "gfx disp wm wmdauer wmshell osum vfs bus uiscale=1 script=sh /t/g.sh;exit" \
    -serial "file:$TMPD/ser.txt" -display none -no-reboot -vga std \
    -drive "file=$TMPD/disk.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/qemu.txt" 2>&1
tr -cd '\11\12\15\40-\176' < "$TMPD/ser.txt" > "$TMPD/ser.klar"; G="$TMPD/ser.klar"

echo "== checks${MUTANT:+ (mutant $MUTANT)} =="
has "$G" "==FERTIG==" "script ran to the end"
for c in C0:C1 C1:C2 C2:C3 C3:C4 C4:C5; do part "$G" "${c%%:*}" "${c##*:}" > "$TMPD/p_${c%%:*}.txt"; done
grep -a '^RA-NONROOT' "$G" | head -1 | sed 's/^/        /'
if grep -aq 'RA-NONROOT uid=1000 setuid=0' "$G"; then
    grep -aqE 'RA-NONROOT .* set=-' "$G" && ok "non-root cannot set the remote session" || bad "non-root set the remote session"
else
    bad "setuid(1000) unusable: non-root check not possible"
fi
has "$TMPD/p_C0.txt" "RA-SELF mode=0 set=0 arm=0 scan=0" "no remote session: injection reaches the dialog"
has "$TMPD/p_C0.txt" "refused injected input" "no remote session (switch off): Yes from injection refused"
has "$TMPD/p_C0.txt" "value=300" "no remote session: value unchanged"
has "$TMPD/p_C1.txt" "RA-SELF mode=1 set=0 arm=0 scan=0" "authenticated session without admin right: injection reaches the dialog"
has "$TMPD/p_C1.txt" "refused injected input" "authenticated but remote.admin off: Yes refused"
has "$TMPD/p_C1.txt" "value=300" "authenticated but remote.admin off: value unchanged"
has "$TMPD/p_C2.txt" "RA-CHILD mode=2 set=0 arm=0 scan=0" "other source (ODB/bridge/jarvisd stand-in): injection reaches the dialog"
has "$TMPD/p_C2.txt" "refused injected input" "admin session but another pid: Yes refused"
has "$TMPD/p_C2.txt" "value=300" "admin session but another pid: value unchanged"
grep -a '^RA-LOCK' "$G" | head -1 | sed 's/^/        /'
has "$TMPD/p_C3.txt" "RA-LOCK mode=2" "emergency stop case ran"
hasnot "$TMPD/p_C3.txt" "scan=0 unlock" "emergency stop: no injected key delivered"
has "$TMPD/p_C3.txt" "value=300" "emergency stop: value unchanged"
for c in C0 C1 C2 C3; do hasnot "$TMPD/p_$c.txt" "wm: trusted dialog answer=" "no dialog answer during $c"; done
has "$TMPD/p_C4.txt" "RA-SELF mode=2 set=0 arm=0 scan=0" "admin session of the authenticated pid: injection reaches the dialog"
has "$TMPD/p_C4.txt" "wm: trusted dialog answer=1" "admin + authenticated pid: Yes accepted"
has "$TMPD/p_C4.txt" "answered by authenticated remote" "audit line for the remote answer"
has "$TMPD/p_C4.txt" "value=700" "remote Yes applied the change"
echo "REMOTEADMIN: $pass passed, $fail failed"
[ "$fail" = 0 ]
