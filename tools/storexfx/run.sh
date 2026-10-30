#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
. tools/lib/qemu.sh

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }

for t in qemu-system-x86_64 python3 musl-gcc; do
    command -v "$t" >/dev/null 2>&1 || { echo "STOREXFX: skipped, $t is missing"; exit 0; }
done
python3 -c 'import cryptography' 2>/dev/null || { echo "STOREXFX: skipped, python3-cryptography is missing"; exit 0; }

TMPD=$(mktemp -d)
SRVPIDS=""
cleanup() { for p in $SRVPIDS; do kill "$p" 2>/dev/null; done; [ -n "${STOREXFX_KEEP:-}" ] || rm -rf "$TMPD"; }
trap cleanup EXIT
BLOCKS=${BLOCKS:-60000}
FILLER_MIB=${FILLER_MIB:-6}
export OSUM_CPU=${OSUM_CPU:-Haswell}
PROGS="sh ls cat echo sleep mkdir cp chmod rm orientbus act su stored opk ota xfx xfxstub tar"
SRV_PORT=${STOREXFX_PORT:-$(( 19000 + ($$ % 900) ))}
OPK=$(python3 tools/lib/opkpfad.py)
ULD=kernel/user/user.ld

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
mkdir -p "$TMPD/bin"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then
    ok "firnc0 builds $(echo $PROGS | wc -w) programs (xfx $(stat -c%s "$TMPD/bin/xfx.elf") B, stored $(stat -c%s "$TMPD/bin/stored.elf") B)"
else
    bad "the programs do not build"; head -20 "$TMPD/b.txt" | sed 's/^/        /'
    echo "STOREXFX: $pass passed, $fail failed"; exit 1
fi
if vendor/firn/bin/firnc -c --profile=app -o "$TMPD/fetch.o" kernel/app/fetch.fi > "$TMPD/fe.txt" 2>&1 \
        && ld -T "$ULD" -o "$TMPD/bin/fetch.elf" "$TMPD/fetch.o" 2>>"$TMPD/fe.txt"; then
    strip --strip-all "$TMPD/bin/fetch.elf"; ok "/bin/fetch builds"
else
    bad "fetch does not build"; head -5 "$TMPD/fe.txt"; echo "STOREXFX: $pass passed, $fail failed"; exit 1
fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then ok "the kernel builds"; else
    bad "the kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'; echo "STOREXFX: $pass passed, $fail failed"; exit 1; fi
if musl-gcc -static -O2 -nostartfiles -T tools/foreign/osum.ld -Wl,--build-id=none \
        -o "$TMPD/setsess" tools/foreign/start.s tools/foreign/osum_main.c tools/actionbus/setsess.c 2>"$TMPD/ss.txt"; then
    ok "setsess builds"
else bad "setsess does not build"; fi

echo "== 2. the signed Firefox source and the bad ones =="
mkdir -p "$TMPD/pk" "$TMPD/pack/parts" "$TMPD/srv"
python3 "$OPK" schluessel "$TMPD/pk" > "$TMPD/key.log" 2>&1
cp "$TMPD/pk/oeffentlich.key" "$TMPD/pk/schluessel.pub"
python3 -I - "$TMPD" "$FILLER_MIB" <<'PY'
import io, os, sys, tarfile
d, filler = sys.argv[1], int(sys.argv[2])
stub = open(d + "/bin/xfxstub.elf", "rb").read()
path = d + "/pack/firefox.tar"
with tarfile.open(path, "w", format=tarfile.USTAR_FORMAT) as t:
    for name in ("usr", "usr/lib", "usr/lib/firefox"):
        i = tarfile.TarInfo(name); i.type = tarfile.DIRTYPE; i.mode = 0o755; t.addfile(i)
    i = tarfile.TarInfo("usr/lib/firefox/firefox"); i.size = len(stub); i.mode = 0o755
    t.addfile(i, io.BytesIO(stub))
    blob = os.urandom(1 << 20) * filler
    i = tarfile.TarInfo("usr/lib/firefox/libfiller.so"); i.size = len(blob); i.mode = 0o644
    t.addfile(i, io.BytesIO(blob))
raw = open(path, "rb").read()
q = len(raw) // 4
for k in range(4):
    open(d + "/pack/parts/firefox.tar.part%03d" % k, "wb").write(raw[k * q:(k + 1) * q if k < 3 else len(raw)])
open(d + "/passwd", "w").write("root:x:0:0:root:/:/bin/sh\njustin:x:1000:1000:Justin:/home/justin:/bin/sh\nmara:x:1001:1001:Mara:/:/bin/sh\n")
open(d + "/group", "w").write("root:x:0:\njustin:x:1000:\nmara:x:1001:\n")
PY
KEY="$TMPD/pk/geheim.key"
python3 tools/xfx/mkstore.py --pack "$TMPD/pack" --xfx-elf "$TMPD/bin/xfx.elf" --user-js assets/xfx/user.js \
    --key "$KEY" --out "$TMPD/srv/good" --version 1.0.0 > "$TMPD/mk.log" 2>&1 \
    && ok "good source: $(tail -1 "$TMPD/mk.log")" || { bad "mkstore"; tail -5 "$TMPD/mk.log"; }
[ "$(wc -l < "$TMPD/srv/good/INDEX")" = 1 ] && ok "INDEX lists the Firefox package, signed" || bad "INDEX"
[ -f "$TMPD/srv/good/store.meta.sig" ] && grep -q '^title=Firefox' "$TMPD/srv/good/store.meta" \
    && ok "store.meta (display data) is published and signed" || bad "store.meta"

cp -r "$TMPD/srv/good" "$TMPD/srv/unsigned"
rm -f "$TMPD/srv/unsigned/firefox-1.opk.sig"
mkdir -p "$TMPD/fremd"; python3 "$OPK" schluessel "$TMPD/fremd" > "$TMPD/fremd.log" 2>&1
cp -r "$TMPD/srv/good" "$TMPD/srv/foreignsig"
python3 tools/update/signpak.py "$TMPD/fremd/geheim.key" "$TMPD/srv/foreignsig/firefox-1.opk" >> "$TMPD/fremd.log" 2>&1
cp -r "$TMPD/srv/good" "$TMPD/srv/flippart"
python3 - "$TMPD/srv/flippart/firefox.tar.part002" <<'PY'
import sys
d = bytearray(open(sys.argv[1], "rb").read()); d[len(d) // 2] ^= 1; open(sys.argv[1], "wb").write(d)
PY
cp -r "$TMPD/srv/good" "$TMPD/srv/missingpart"
rm -f "$TMPD/srv/missingpart/firefox.tar.part003"
cmp -s "$TMPD/srv/good/firefox-1.opk.sig" "$TMPD/srv/foreignsig/firefox-1.opk.sig" && bad "foreign signature equals the good one" || ok "four bad sources: unsigned, foreign key, flipped part, missing part"
python3 tools/ota/mkcerts.py "$TMPD/certs" ota.test 10.0.2.2 > "$TMPD/certs.log" 2>&1 && ok "certificates" || { bad "mkcerts"; cat "$TMPD/certs.log"; }

serve() {
    python3 tools/ota/server.py --wurzel "$TMPD/srv/$1" --port "$2" --cert "$TMPD/certs/srv.pem" --key "$TMPD/certs/srv.key" \
        --log "$TMPD/srv-$1.log" > "$TMPD/srv-$1.out" 2>&1 &
    SRVPIDS="$SRVPIDS $!"
    local i
    for i in $(seq 1 40); do grep -qa "^START port=$2 " "$TMPD/srv-$1.log" 2>/dev/null && return 0; sleep 0.2; done
    return 1
}
P0=$SRV_PORT
serve good $P0 && serve unsigned $((P0+1)) && serve foreignsig $((P0+2)) && serve flippart $((P0+3)) && serve missingpart $((P0+4)) \
    && ok "five HTTPS sources are up on ports $P0..$((P0+4))" || bad "a source does not start"

echo "== 3. the guest =="
printf 'installieren=admin\nentfernen=admin\nadmins=1000\n' > "$TMPD/conf.admin"
printf 'dryfirst jarvis\n' > "$TMPD/policy"
for n in 0 1 2 3 4; do
    printf 'quelle=https://10.0.2.2:%s\nname=ota.test\nabstand=3600\nauto=nein\nfrist=15\n' "$((P0+n))" > "$TMPD/ota.conf.$n"
done
{
cat <<'EOS'
mkdir /users/justin
orientbus serve 600000 &
sleep -m 300
stored serve 600000 &
sleep 1
setsess 1000
EOS
for step in "1 UNSIGNED FOREIGNSIG 8" "2 FOREIGNSIG FLIPPART 8" "3 FLIPPART MISSINGPART 30" "4 MISSINGPART GOOD-LIST 30"; do
    set -- $step
    printf 'cp /etc/ota.conf.%s /etc/ota.conf\nact call store.refresh\nact confirm last\nsleep 6\nact call store.install name=firefox\nact confirm last\nsleep %s\necho ==%s==\nact call store.status\nopk list\nxfx status\nls /usr/share/xfx\n' "$1" "$4" "$2"
done
cat <<'EOS'
cp /etc/ota.conf.0 /etc/ota.conf
act call store.refresh
act confirm last
sleep 6
echo ==GOOD-LIST==
act call store.list
act call store.install name=firefox
act confirm last
echo ==GOOD-P1==
act call store.status
sleep 1
echo ==GOOD-P2==
act call store.status
sleep 1
echo ==GOOD-P3==
act call store.status
sleep 2
echo ==GOOD-P4==
act call store.status
sleep 2
echo ==GOOD-P5==
act call store.status
sleep 3
echo ==GOOD-P6==
act call store.status
sleep 40
echo ==GOOD-DONE==
act call store.status
opk list
xfx status
ls /usr/lib/firefox
ls /usr/share/xfx
ls /apps/firefox.osp
act call store.list
echo ==FERTIG==
EOS
} > "$TMPD/s.sh"
BASE=(build "$TMPD/g.img" $BLOCKS --v3 --inodes=512 --karten=64 /lib/
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /etc/actions.d/ /etc/orientbus/ /etc/ssl/ /store/ /apps/ /users/ /var/ /var/log/ /run/ /usr/ /usr/share/ /usr/share/xfx/ /home/@755:0:0 /home/justin/@700:1000:1000)
for p in $PROGS fetch; do BASE+=("/bin/$p=$TMPD/bin/$p.elf"); done
BASE+=("/bin/setsess=$TMPD/setsess"
    "/etc/passwd=$TMPD/passwd" "/etc/group=$TMPD/group"
    "/etc/actions.d/store.actions=etc/actions.d/store.actions"
    "/etc/orientbus/policy=$TMPD/policy"
    "/etc/store.conf=$TMPD/conf.admin"
    "/etc/ota.conf=$TMPD/ota.conf.0" "/etc/ssl/roots.pem=$TMPD/certs/ca.pem"
    "/system/schluessel.pub=$TMPD/pk/schluessel.pub"
    "/t/s.sh=$TMPD/s.sh")
for n in 0 1 2 3 4; do BASE+=("/etc/ota.conf.$n=$TMPD/ota.conf.$n"); done
python3 tools/osum/mkfs.py "${BASE[@]}" > "$TMPD/mkfs.txt" 2>&1 || { echo "mkfs failed"; tail -3 "$TMPD/mkfs.txt"; }
ACCEL="-cpu $OSUM_CPU"
[ -r /dev/kvm ] && [ -w /dev/kvm ] && ACCEL="-accel kvm -cpu host"
timeout "${STOREXFX_TIMEOUT:-1500}" qemu-system-x86_64 $ACCEL -smp 1 -kernel "$TMPD/k0.img" -m 768 \
    -append "osum vfs nokbd bus nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0 script=sh /t/s.sh;exit" \
    -serial "file:$TMPD/g.txt" -display none -no-reboot \
    -netdev user,id=n0 -device e1000,netdev=n0,mac=52:54:00:0a:0b:0c \
    -drive "file=$TMPD/g.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$TMPD/g.txt" > "$TMPD/g.klar" 2>/dev/null || true
G="$TMPD/g.klar"
grep -qa '==FERTIG==' "$G" || { bad "the guest did not finish"; tail -25 "$G" | sed 's/^/        /'; }

echo "== 4. refusals: nothing installed, nothing extracted =="
for sec in UNSIGNED:FOREIGNSIG FOREIGNSIG:FLIPPART FLIPPART:MISSINGPART MISSINGPART:GOOD-LIST; do
    a=${sec%%:*}; b=${sec##*:}
    part "$G" "$a" "$b" > "$TMPD/p.txt"
    hasnot "$TMPD/p.txt" "  firefox -> " "$a: firefox is not in the package list"
    has "$TMPD/p.txt" "installed=no" "$a: xfx says not installed"
    has "$TMPD/p.txt" "phase=fehler" "$a: the store reports the failure"
done
part "$G" FLIPPART MISSINGPART > "$TMPD/p.txt"
has "$TMPD/p.txt" "Firefox-Teile nicht zu holen oder abgelehnt" "flipped part: refused at the part hash, package rolled back"
hasnot "$TMPD/p.txt" "firefox.tar.part002" "flipped part: the bad part is not kept"
part "$G" MISSINGPART GOOD-LIST > "$TMPD/p.txt"
has "$TMPD/p.txt" "Firefox-Teile nicht zu holen oder abgelehnt" "missing part: refused, package rolled back"
part "$G" UNSIGNED FOREIGNSIG > "$TMPD/p.txt"
has "$TMPD/p.txt" "msg=Paket" "unsigned package: refused"
part "$G" FOREIGNSIG FLIPPART > "$TMPD/p.txt"
has "$TMPD/p.txt" "msg=Paket" "package signed with a foreign key: refused"

echo "== 5. the good way: signed, installed, progress in the store =="
part "$G" GOOD-LIST GOOD-P1 > "$TMPD/p.txt"
has "$TMPD/p.txt" "item=firefox|1.0.0|" "the catalog offers Firefox 1.0.0"
has "$TMPD/p.txt" "|neu" "Firefox is new on this device"
python3 -I - "$G" <<'PY' > "$TMPD/prog.txt"
import re, sys
text = open(sys.argv[1], errors="replace").read()
vals = []
for k in range(1, 7):
    m = re.search(r"==GOOD-P%d==(.*?)(?===|\Z)" % k, text, re.S)
    p = re.search(r"pct=(\d+)", m.group(1)) if m else None
    vals.append(int(p.group(1)) if p else -1)
print(" ".join(map(str, vals)))
seen = [v for v in vals if v >= 0]
print("mono=%s mid=%s" % (all(b >= a for a, b in zip(seen, seen[1:])), any(0 < v < 100 for v in vals)))
PY
sed 's/^/        samples: /' "$TMPD/prog.txt"
has "$TMPD/prog.txt" "mono=True" "the progress in the store status never goes backwards"
has "$TMPD/prog.txt" "mid=True" "the store status shows progress between 0 and 100 while it runs"
part "$G" GOOD-DONE FERTIG > "$TMPD/p.txt"
has "$TMPD/p.txt" "phase=fertig" "install firefox: done"
has "$TMPD/p.txt" "msg=installiert" "... and says so"
has "$TMPD/p.txt" "  firefox -> " "firefox is in the package list"
has "$TMPD/p.txt" "installed=yes" "xfx says installed"
has "$TMPD/p.txt" "libfiller.so" "the pack was extracted"
has "$TMPD/p.txt" "xfx.manifest" "the signed parts list came with the package"
has "$TMPD/p.txt" "|aktuell" "the catalog says aktuell"
hasnot "$TMPD/p.txt" "firefox.tar.part000" "the parts are gone after the join"

echo "STOREXFX: $pass passed, $fail failed"
[ "$fail" = 0 ]
