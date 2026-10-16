#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/usbimg/bbsh.sh -- LC-006 gate: busybox is /bin/sh in the personal image, so musl system()/popen() work.
#   /root/jarvis/bin/heavy bash tools/usbimg/bbsh.sh
# Builds the image twice (BBSH=1 and the counter-proof BBSH=0), puts the musl test t_proc on both, boots the console
# entry and checks: sh -c works, osh is still the login shell, proc.system_exit_status + proc.popen PASS (only with BBSH=1).
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
BBDYN=${BBDYN:-/root/bbdyn/busybox}
for t in musl-gcc qemu-system-x86_64 mcopy python3; do command -v "$t" >/dev/null 2>&1 || { echo "BBSH: $t missing, skipped"; exit 0; }; done
[ -r "$BBDYN" ] || { echo "BBSH: $BBDYN missing, skipped"; exit 0; }
LIBC=$(readlink -f /lib/ld-musl-x86_64.so.1 2>/dev/null || true); [ -r "$LIBC" ] || LIBC=/usr/lib/x86_64-linux-musl/libc.so
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$*"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$*"; }
musl-gcc -O1 -g0 -Wno-unused-result -o "$D/t_proc" tools/unterbau/t_proc.c -Itools/unterbau -ldl -lrt 2> "$D/cc.err" || { cat "$D/cc.err" | head; echo "BBSH: t_proc does not build"; exit 1; }
cat > "$D/boot.py" <<'PY'
import subprocess, sys, time, os, shutil, select
img, wd = sys.argv[1], sys.argv[2]; cmds = sys.argv[3:]
off = 2048*512
subprocess.run(['mcopy','-o','-i',img+'@@%d'%off,'::/limine.conf',wd+'/l.orig'],check=True)
L = open(wd+'/l.orig').read().splitlines()
st = [i for i,l in enumerate(L) if l.startswith('/Command line')][0]
en = next((j for j in range(st+1,len(L)) if L[j].startswith('/')),len(L))
open(wd+'/l.conf','w').write('timeout: 0\ndefault_entry: 1\n\n'+'\n'.join(L[st:en])+'\n')
for t in ('::/limine.conf','::/boot/limine.conf'):
    subprocess.run(['mcopy','-o','-i',img+'@@%d'%off,wd+'/l.conf',t],check=True)
acc = ['-accel','kvm','-cpu','host'] if os.access('/dev/kvm', os.W_OK) else []
p = subprocess.Popen(['qemu-system-x86_64']+acc+['-m','1024','-drive','file=%s,format=raw,if=none,id=s'%img,'-device','ide-hd,drive=s','-serial','stdio','-display','none','-monitor','none','-no-reboot'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
buf = b''
def rd(t, stop=None):
    global buf
    e = time.time()+t
    while time.time() < e:
        r,_,_ = select.select([p.stdout],[],[],0.2)
        if r:
            d = os.read(p.stdout.fileno(),65536)
            if not d: break
            buf += d
        if stop and stop in buf[-4000:]: break
out = open(wd+'/console.txt','wb')
rd(40, b'osum$')
for c in cmds:
    n = len(buf); p.stdin.write((c+'\n').encode()); p.stdin.flush(); rd(45 if 't_proc' in c else 8, b'@@DONE' if 't_proc' in c else None)
    out.write(('$ '+c+'\n').encode()); out.write(buf[n:]); out.write(b'\n')
p.kill(); out.close()
PY
CMDS=("/bin/sh -c 'echo AB'" "/bin/sh -c 'exit 7'; echo rc7" "/bin/t_proc" "echo @@DONE")
run() {  # $1 = BBSH value, $2 = dir
    mkdir -p "$2"
    BBSH=$1 USBIMG_EXTRA="/bin/t_proc=$D/t_proc${3:-}" IMAGE_PROFILE=personal bash tools/usbimg/build.sh "$2" > "$2/build.log" 2>&1 || { bad "image build BBSH=$1 failed (see $2/build.log)"; tail -5 "$2/build.log"; return 1; }
    python3 -I "$D/boot.py" "$2/orientos-usb.img" "$2" "${CMDS[@]}" > "$2/boot.log" 2>&1
    rm -f "$2/orientos-usb.img" "$2/osum-usb.img" "$2/root.img"
}
echo "== 1. BBSH=1: busybox is /bin/sh =="
run 1 "$D/on" && {
    C=$D/on/console.txt
    grep -q '^AB' <(tr -d '\r' < "$C") && ok "sh -c 'echo AB' prints AB" || bad "sh -c 'echo AB' prints nothing"
    grep -q 'rc7' "$C" && ok "sh -c 'exit 7' returns, console alive" || bad "console dead after sh -c"
    grep -q 'T proc.system_exit_status PASS' "$C" && ok "proc.system_exit_status PASS" || bad "proc.system_exit_status not PASS"
    grep -q 'T proc.popen PASS' "$C" && ok "proc.popen PASS" || bad "proc.popen not PASS"
    grep -q 'osum\$' "$C" && ok "Osum shell (osh) is the console shell" || bad "no osum\$ prompt"
}
echo "== 2. counter-proof BBSH=0: Osum shell is /bin/sh, system()/popen() must NOT pass =="
run 0 "$D/off" " /lib/ld-musl-x86_64.so.1=$LIBC" && {
    C=$D/off/console.txt
    grep -q 'T proc.system_exit_status PASS' "$C" && bad "counter-proof: system_exit_status passes without busybox" || ok "counter-proof: system_exit_status not PASS without busybox"
    grep -q 'T proc.popen PASS' "$C" && bad "counter-proof: popen passes without busybox" || ok "counter-proof: popen not PASS without busybox"
}
echo "BBSH: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
