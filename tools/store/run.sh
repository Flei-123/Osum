#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
. tools/lib/qemu.sh

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }

for t in qemu-system-x86_64 python3 musl-gcc curl; do
    command -v "$t" >/dev/null 2>&1 || { echo "STORE: skipped, $t is missing"; exit 0; }
done
python3 -c 'import cryptography' 2>/dev/null || { echo "STORE: skipped, python3-cryptography is missing"; exit 0; }

TMPD=$(mktemp -d)
SRVPIDS=""
cleanup() { for p in $SRVPIDS; do kill "$p" 2>/dev/null; done; [ -n "${STORE_KEEP:-}" ] || rm -rf "$TMPD"; }
trap cleanup EXIT
BLOCKS=${BLOCKS:-40000}
export OSUM_CPU=${OSUM_CPU:-Haswell}
PROGS="sh ls cat echo sleep mkdir cp chmod rm orientbus act su stored opk ota apprights"
SRV_PORT=${STORE_PORT:-$(( 19000 + ($$ % 900) ))}

echo "== 1. build =="
. tools/lib/firnenv.sh
mkdir -p "$TMPD/bin"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS store > "$TMPD/b.txt" 2>&1; then
    [ -z "${STORE_ELF:-}" ] || cp "$STORE_ELF" "$TMPD/bin/store.elf"
    ok "firnc0 builds $(echo $PROGS store | wc -w) programs (stored $(stat -c%s "$TMPD/bin/stored.elf") B, store $(stat -c%s "$TMPD/bin/store.elf") B, opk $(stat -c%s "$TMPD/bin/opk.elf") B)"
else
    bad "the programs do not build"; sed 's/^/        /' "$TMPD/b.txt" | head -20
    echo "STORE: $pass passed, $fail failed"; exit 1
fi
# /bin/fetch: the full library with TLS (profile app, no crt.o)
if "$FIRNC" -c --profile=app -o "$TMPD/fetch.o" kernel/app/fetch.fi > "$TMPD/fe.txt" 2>&1 \
        && ld -T kernel/user/user.ld -o "$TMPD/bin/fetch.elf" "$TMPD/fetch.o" 2>>"$TMPD/fe.txt"; then
    strip --strip-all "$TMPD/bin/fetch.elf"; ok "/bin/fetch builds ($(stat -c%s "$TMPD/bin/fetch.elf") B)"
else
    bad "fetch does not build"; head -5 "$TMPD/fe.txt"; echo "STORE: $pass passed, $fail failed"; exit 1
fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then ok "the kernel builds"; else
    bad "the kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'; echo "STORE: $pass passed, $fail failed"; exit 1; fi
if musl-gcc -static -O2 -nostartfiles -T tools/foreign/osum.ld -Wl,--build-id=none \
        -o "$TMPD/setsess" tools/foreign/start.s tools/foreign/osum_main.c tools/actionbus/setsess.c 2>"$TMPD/ss.txt"; then
    ok "setsess (the one kernel call glogin makes) builds"
else bad "setsess does not build"; fi
python3 tools/actionbus/manifest.py check etc/actions.d/store.actions > "$TMPD/lint.txt" 2>&1 \
    && ok "host reader: the store manifest ($(head -1 "$TMPD/lint.txt" | cut -d' ' -f3-))" \
    || bad "host reader refuses etc/actions.d/store.actions: $(cat "$TMPD/lint.txt")"

echo "== 2. signed sources and the server =="
bash tools/install/pakete.sh "$TMPD/pk" > "$TMPD/pk.log" 2>&1 && ok "hallo 1.0.0 and 2.0.0, signed, made by the host's opk" || { bad "install/pakete.sh"; tail -3 "$TMPD/pk.log"; }
OPK=$(python3 tools/lib/opkpfad.py)
KEY="$TMPD/pk/geheim.key"
# `gruss` 1.0.0: the same program under another name
sed -e 's/^name=hallo/name=gruss/' -e 's/^version=.*/version=1.0.0/' -e 's/^titel=.*/titel=Gruss/' -e "s#H1ELF#$TMPD/pk/h1.elf#" tools/install/hallo1.rezept > "$TMPD/gruss.rezept"
python3 "$OPK" bauen "$TMPD/gruss.rezept" -o "$TMPD/pk/pak/gruss-1.opk" > "$TMPD/gruss.log" 2>&1 && ok "gruss 1.0.0 built" || { bad "gruss"; tail -3 "$TMPD/gruss.log"; }
mkstore() { # dir  keyfile  [list of opk files]
    local d=$1 k=$2; shift 2
    rm -rf "$d"; mkdir -p "$d"
    cp "$@" "$d/"
    python3 "$OPK" quelle "$d" --schluessel "$k" > "$d.log" 2>&1 || { cat "$d.log"; return 1; }
    python3 tools/update/signpak.py "$KEY" "$d"/*.opk >> "$d.log" 2>&1
}
mkdir -p "$TMPD/srv"
mkstore "$TMPD/srv/good" "$KEY" "$TMPD/pk/pak/gruss-1.opk" "$TMPD/pk/pak/hallo-2.opk" \
    && ok "the good store: $(wc -l < "$TMPD/srv/good/INDEX") programs, INDEX signed" || bad "good store"
# 1. a flipped octet, the old signature (the package signature fails)
cp -r "$TMPD/srv/good" "$TMPD/srv/flip"
python3 - "$TMPD/srv/flip/gruss-1.opk" <<'PY'
import sys
d = bytearray(open(sys.argv[1], "rb").read()); d[len(d) // 2] ^= 1; open(sys.argv[1], "wb").write(d)
PY
# 2. a flipped octet RE-SIGNED with the right key: package signature fine, hash in the signed INDEX not
cp -r "$TMPD/srv/flip" "$TMPD/srv/hash"
python3 tools/update/signpak.py "$KEY" "$TMPD/srv/hash/gruss-1.opk" > "$TMPD/srv-hash.log" 2>&1
# 3. the catalog signed with a FOREIGN key (the packages are fine)
mkdir -p "$TMPD/fremd"
python3 "$OPK" schluessel "$TMPD/fremd" > "$TMPD/fremd.log" 2>&1
cp -r "$TMPD/srv/good" "$TMPD/srv/foreign"
python3 "$OPK" quelle "$TMPD/srv/foreign" --schluessel "$TMPD/fremd/geheim.key" >> "$TMPD/fremd.log" 2>&1
python3 tools/update/signpak.py "$KEY" "$TMPD/srv/foreign"/*.opk >> "$TMPD/fremd.log" 2>&1
cmp -s "$TMPD/srv/good/INDEX.sig" "$TMPD/srv/foreign/INDEX.sig" && bad "the foreign catalog has the same signature" || ok "three bad stores: flipped, re-signed flipped, foreign catalog"
python3 tools/ota/mkcerts.py "$TMPD/certs" ota.test 10.0.2.2 > "$TMPD/certs.log" 2>&1 && ok "certificates (made by Python's cryptography)" || { bad "mkcerts"; cat "$TMPD/certs.log"; }

serve() { # name port
    python3 tools/ota/server.py --wurzel "$TMPD/srv/$1" --port "$2" --cert "$TMPD/certs/srv.pem" --key "$TMPD/certs/srv.key" \
        --log "$TMPD/srv-$1.log" > "$TMPD/srv-$1.out" 2>&1 &
    SRVPIDS="$SRVPIDS $!"
    local i
    for i in $(seq 1 40); do grep -qa "^START port=$2 " "$TMPD/srv-$1.log" 2>/dev/null && return 0; sleep 0.2; done
    return 1
}
P0=$SRV_PORT
serve good $P0 && serve flip $((P0+1)) && serve hash $((P0+2)) && serve foreign $((P0+3)) && ok "four HTTPS sources are up on ports $P0..$((P0+3))" || bad "a source does not start"
CV=$(curl -s --cacert "$TMPD/certs/ca.pem" --resolve "ota.test:$P0:127.0.0.1" -o /dev/null -w '%{http_code}' "https://ota.test:$P0/INDEX" 2>/dev/null)
[ "$CV" = 200 ] && ok "curl (not this repository's TLS) reads the catalog: 200" || bad "curl: '$CV'"

# ---------------------------------------------------------- the guest
printf 'root:x:0:0:root:/:/bin/sh\njustin:x:1000:1000:Justin:/:/bin/sh\nmara:x:1001:1001:Mara:/:/bin/sh\n' > "$TMPD/passwd"
printf 'root:x:0:\njustin:x:1000:\nmara:x:1001:\n' > "$TMPD/group"
printf 'installieren=admin\nentfernen=admin\nadmins=1000\nautoapps=nein\n' > "$TMPD/conf.admin"
printf 'installieren=admin\nentfernen=admin\nadmins=1000\nautointervall=10\n' > "$TMPD/conf.auto"
printf 'installieren=benutzer\nentfernen=benutzer\nautoapps=nein\n' > "$TMPD/conf.benutzer"
printf 'installieren=aus\nentfernen=aus\nautoapps=nein\n' > "$TMPD/conf.aus"
printf 'installieren=admin\nentfernen=admin\nadmins=1001\nautoapps=nein\n' > "$TMPD/conf.admins"
cat > "$TMPD/policy" <<'EOF'
# the store test: the shipped defaults
dryfirst jarvis
EOF
EXTRA=()
image() { # <image> <script> <port>
    local img=$1 script=$2 port=$3
    printf 'source=https://10.0.2.2:%s\nname=ota.test\nabstand=3600\nauto=nein\nfrist=15\n' "$port" > "$TMPD/ota.conf"
    local -a A=(build "$img" $BLOCKS --v3 --inodes=512 --karten=64 /lib/
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /etc/actions.d/ /etc/orientbus/ /etc/ssl/ /store/ /apps/ /users/ /var/ /var/log/ /quelle1/)
    local p
    for p in $PROGS fetch; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
    A+=("/bin/setsess=$TMPD/setsess"
        "/etc/passwd=$TMPD/passwd" "/etc/group=$TMPD/group"
        "/etc/actions.d/store.actions=etc/actions.d/store.actions"
        "/etc/orientbus/policy=$TMPD/policy"
        "/etc/store.conf=${STORE_CONF:-$TMPD/conf.admin}" "/etc/store.admin=$TMPD/conf.admin" "/etc/store.benutzer=$TMPD/conf.benutzer"
        "/etc/store.aus=$TMPD/conf.aus" "/etc/store.admins=$TMPD/conf.admins"
        "/etc/ota.conf=$TMPD/ota.conf" "/etc/ssl/roots.pem=$TMPD/certs/ca.pem"
        "/system/schluessel.pub=$TMPD/pk/schluessel.pub"
        "/quelle1/hallo-1.opk=$TMPD/pk/quelle1/hallo-1.opk" "/quelle1/hallo-1.opk.sig=$TMPD/pk/quelle1/hallo-1.opk.sig"
        "/quelle1/INDEX=$TMPD/pk/quelle1/INDEX" "/quelle1/INDEX.sig=$TMPD/pk/quelle1/INDEX.sig"
        "/t/s.sh=$script")
    A+=("${EXTRA[@]}")
    bash tools/mkfsfi/mkfs.sh "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 || { echo "mkfs failed"; tail -3 "$TMPD/mkfs.txt"; }
}
run() { # <image> <name> [seconds]
    local img=$1 nm=$2 secs=${3:-600}
    timeout "$secs" $QEMU_X86 -cpu "$OSUM_CPU" -smp 1 -kernel "$TMPD/k0.img" -m 512 \
        -append "osum vfs nokbd bus nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0 script=sh /t/s.sh;exit" \
        -serial "file:$TMPD/$nm.txt" -display none -no-reboot \
        -netdev user,id=n0 -device e1000,netdev=n0,mac=52:54:00:0a:0b:0c \
        -drive "file=$img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$TMPD/$nm.txt" > "$TMPD/$nm.klar" 2>/dev/null || true
}

[ -z "${STORE_WINDOW_ONLY:-}" ] || STORE_PART=window
want() { [ -z "${STORE_PART:-}" ] || [ "$STORE_PART" = "$1" ]; }
# STORE_PART=bus|auto|window|xremote runs one part (STORE_FAST=1 skips the bus part)
if want bus && [ -z "${STORE_FAST:-}" ]; then
echo "== 3. the good way, over the bus, from the signed-in person =="
cat > "$TMPD/sA.sh" <<'EOS'
mkdir /users/justin
opk install /quelle1/hallo-1.opk
orientbus serve 24000 &
sleep -m 300
stored serve 24000 &
sleep 1
setsess 1000
echo ==A-L0==
act call store.list
echo ==A-DRY==
act call store.refresh --dry
act call store.install name=gruss --dry
echo ==A-NOCAT==
act call store.install name=gruss
act confirm last
echo ==A-REF==
act call store.refresh
sleep 30
act call store.status
echo ==A-L1==
act call store.list
cat /var/store/katalog
echo ==A-BADNAME==
act call store.install name=../etc
act confirm last
act call store.install name=nosuch
act confirm last
echo ==A-INST==
act call store.install name=gruss
act confirm last
sleep 40
act call store.status
opk list
act call store.list
echo ==A-UPD==
act call store.update name=hallo
act confirm last
sleep 40
act call store.status
opk list
act call store.list
echo ==A-AGAIN==
act call store.install name=gruss
act confirm last
sleep 3
echo ==A-REM==
act call store.remove name=gruss
act confirm last
sleep 6
act call store.status
opk list
act call store.list
echo ==A-RIGHTS==
stored can install 0
stored can install 1000
stored can install 1001
stored can install 65534
stored can remove 1001
cp /etc/store.benutzer /etc/store.conf
echo ==A-BEN==
stored can install 1001
stored can install 65534
stored can remove 1001
cp /etc/store.aus /etc/store.conf
echo ==A-AUS==
stored can install 0
stored can install 1000
cp /etc/store.admins /etc/store.conf
echo ==A-ADM==
stored can install 1001
stored can install 1002
cp /etc/store.admin /etc/store.conf
echo ==A-MARA==
su mara /bin/act call store.install name=gruss
act confirm last
sleep 3
act call store.status
opk list
act call store.list
cp /etc/store.benutzer /etc/store.conf
echo ==A-MARA2==
su mara /bin/act call store.install name=gruss
act confirm last
sleep 40
act call store.status
opk list
echo ==FERTIG==
EOS
image "$TMPD/A.img" "$TMPD/sA.sh" $P0
run "$TMPD/A.img" a 900
A="$TMPD/a.klar"
grep -qa '==FERTIG==' "$A" || { bad "the good-way guest did not finish"; tail -25 "$A" | sed 's/^/        /'; }
part "$A" A-L0 A-DRY > "$TMPD/p.txt"
has "$TMPD/p.txt" "count=0" "before the first fetch the catalog is empty (count=0)"
has "$TMPD/p.txt" "can_install=1" "the signed-in person (uid 1000) may install (the default is admin)"
part "$A" A-DRY A-NOCAT > "$TMPD/p.txt"
has "$TMPD/p.txt" "would=refresh" "a dry run of the refresh says what it would do"
part "$A" A-NOCAT A-REF > "$TMPD/p.txt"
has "$TMPD/p.txt" "not_in_catalog" "a program the (empty) catalog does not list is refused"
part "$A" A-REF A-L1 > "$TMPD/p.txt"
has "$TMPD/p.txt" "phase=done" "the refresh is done (phase=done)"
has "$TMPD/p.txt" "verb=refresh" "... and says what it was"
part "$A" A-L1 A-BADNAME > "$TMPD/p.txt"
has "$TMPD/p.txt" "count=2" "the verified catalog lists two programs"
has "$TMPD/p.txt" "item=gruss|1.0.0|" "gruss 1.0.0 is in it"
has "$TMPD/p.txt" "|neu" "gruss is new on this device (state neu)"
has "$TMPD/p.txt" "item=hallo|2.0.0|" "hallo 2.0.0 is in it"
has "$TMPD/p.txt" "|update" "hallo 1.0.0 is installed, the store has 2.0.0 (state update)"
part "$A" A-BADNAME A-INST > "$TMPD/p.txt"
has "$TMPD/p.txt" "bad_name" "a name with a slash is refused (bad_name)"
has "$TMPD/p.txt" "not_in_catalog" "a name that is no program is refused (not_in_catalog)"
part "$A" A-INST A-UPD > "$TMPD/p.txt"
has "$TMPD/p.txt" "phase=done" "install gruss: done"
has "$TMPD/p.txt" "msg=installiert" "... and says so"
has "$TMPD/p.txt" "  gruss -> " "gruss is in the package list (opk list)"
has "$TMPD/p.txt" "|aktuell" "gruss is up to date (state aktuell)"
part "$A" A-UPD A-AGAIN > "$TMPD/p.txt"
has "$TMPD/p.txt" "phase=done" "update hallo: done"
has "$TMPD/p.txt" "item=hallo|2.0.0|" "hallo is in the catalog"
[ "$(grep -c '|update' "$TMPD/p.txt")" = 0 ] && ok "hallo is no longer 'update' (it IS 2.0.0 now)" || bad "hallo still says update"
part "$A" A-AGAIN A-REM > "$TMPD/p.txt"
has "$TMPD/p.txt" "already_installed" "installing a program that is installed and current is refused (already_installed)"
part "$A" A-REM A-RIGHTS > "$TMPD/p.txt"
has "$TMPD/p.txt" "msg=entfernt" "remove gruss: done"
hasnot "$TMPD/p.txt" "  gruss -> " "gruss is gone from the package list"
has "$TMPD/p.txt" "|neu" "gruss is 'neu' again"
part "$A" A-RIGHTS A-BEN | grep -ax 'yes\|no' | tr '\n' ' ' | grep -q "^yes yes no no no" && ok "default (admin): root and uid 1000 may, uid 1001 and nobody may not, 1001 may not remove" || bad "default rights: $(part "$A" A-RIGHTS A-BEN | grep -ax 'yes\|no' | tr '\n' ' ')"
part "$A" A-BEN A-AUS | grep -ax 'yes\|no' | tr '\n' ' ' | grep -q "^yes no yes" && ok "benutzer: uid 1001 may install and remove, nobody (65534) may not" || bad "benutzer: $(part "$A" A-BEN A-AUS | grep -ax 'yes\|no' | tr '\n' ' ')"
part "$A" A-AUS A-ADM | grep -ax 'yes\|no' | tr '\n' ' ' | grep -q "^no no" && ok "aus: nobody, not even root" || bad "aus: $(part "$A" A-AUS A-ADM | grep -ax 'yes\|no' | tr '\n' ' ')"
part "$A" A-ADM A-MARA | grep -ax 'yes\|no' | tr '\n' ' ' | grep -q "^yes no" && ok "admins=1001 makes uid 1001 an administrator (and 1002 not)" || bad "admins=: $(part "$A" A-ADM A-MARA | grep -ax 'yes\|no' | tr '\n' ' ')"
part "$A" A-MARA A-MARA2 > "$TMPD/p.txt"
has "$TMPD/p.txt" "not_allowed" "uid 1001's request, confirmed by the person, ends in not_allowed (default admin)"
hasnot "$TMPD/p.txt" "  gruss -> " "... and nothing was installed"
part "$A" A-MARA2 FERTIG > "$TMPD/p.txt"
has "$TMPD/p.txt" "msg=installiert" "with benutzer the same request goes through (installed)"

echo "== 4. the refusals -- and after each one NOTHING is installed =="
for v in flip:1 hash:2 foreign:3; do
    name=${v%%:*}; off=${v##*:}
    cat > "$TMPD/s$name.sh" <<'EOS'
mkdir /users/justin
orientbus serve 15000 &
sleep -m 300
stored serve 15000 &
sleep 1
setsess 1000
echo ==B-REF==
act call store.refresh
sleep 30
act call store.status
act call store.list
echo ==B-INST==
act call store.install name=gruss
act confirm last
sleep 40
act call store.status
opk list
act call store.list
echo ==FERTIG==
EOS
    image "$TMPD/B$name.img" "$TMPD/s$name.sh" $((P0 + off))
    run "$TMPD/B$name.img" "b$name" 600
    B="$TMPD/b$name.klar"
    grep -qa '==FERTIG==' "$B" || { bad "$name guest did not finish"; tail -15 "$B" | sed 's/^/        /'; }
    case $name in
    flip)
        part "$B" B-INST FERTIG > "$TMPD/p.txt"
        has "$TMPD/p.txt" "phase=failed" "flipped package: refused (phase=failed)"
        has "$TMPD/p.txt" "rejected" "... named as rejected"
        hasnot "$TMPD/p.txt" "  gruss -> " "... and nothing was installed";;
    hash)
        part "$B" B-INST FERTIG > "$TMPD/p.txt"
        has "$TMPD/p.txt" "phase=failed" "re-signed flipped package (valid signature, wrong hash): refused"
        hasnot "$TMPD/p.txt" "  gruss -> " "... and nothing was installed"
        has "$B" "opk:" "(opk named the reason)";;
    foreign)
        part "$B" B-REF B-INST > "$TMPD/p.txt"
        has "$TMPD/p.txt" "phase=failed" "catalog signed with a foreign key: refused (phase=failed)"
        has "$TMPD/p.txt" "count=0" "... the unverified catalog was never listed (count=0)"
        part "$B" B-INST FERTIG > "$TMPD/p.txt"
        has "$TMPD/p.txt" "not_in_catalog" "... and installing from it is not possible"
        hasnot "$TMPD/p.txt" "  gruss -> " "... nothing installed";;
    esac
done

fi

if want auto; then
echo "== 4b. automatic updates: global switch, per-program switch, manual update, rights =="
cat > "$TMPD/sC.sh" <<'EOS'
mkdir /users/justin
opk install /quelle1/hallo-1.opk
orientbus serve 26000 &
sleep -m 300
stored serve 26000 &
sleep 1
setsess 1000
echo ==C-DEFAULT==
act call store.list
act call store.autoset value=off
echo ==C-GOFF==
act call store.refresh
sleep 30
act call store.list
sleep 50
act call store.status
act call store.list
echo ==C-POFF==
act call store.autoset value=on
act call store.autoset name=hallo value=off
act call store.autoset name=../x value=off
act call store.autoset name=nosuch value=off
act call store.autoset value=maybe
act call store.autoset name=hallo value=off --dry
act call store.list
sleep 50
act call store.status
act call store.list
echo ==C-DENY==
su mara /bin/act call store.autoset value=off
act call store.list
echo ==C-MANUAL==
act call store.update name=hallo
act confirm last
sleep 45
act call store.status
act call store.list
opk list
echo ==FERTIG==
EOS
STORE_CONF="$TMPD/conf.auto" image "$TMPD/C.img" "$TMPD/sC.sh" $P0
run "$TMPD/C.img" c 900
C="$TMPD/c.klar"
grep -qa '==FERTIG==' "$C" || { bad "the auto-update guest did not finish"; tail -25 "$C" | sed 's/^/        /'; }
part "$C" C-DEFAULT C-GOFF > "$TMPD/p.txt"
has "$TMPD/p.txt" "autoapps=1" "default: the global switch is on (no key in /etc/store.conf)"
has "$TMPD/p.txt" "ok" "the global switch can be turned off over the bus"
part "$C" C-GOFF C-POFF > "$TMPD/p.txt"
has "$TMPD/p.txt" "autoapps=0" "global off: store.list says autoapps=0"
has "$TMPD/p.txt" "item=hallo|2.0.0|" "the store has hallo 2.0.0 ..."
has "$TMPD/p.txt" "|update|1" "... hallo is outdated and its own switch is on (|update|1)"
[ "$(grep -c '|aktuell' "$TMPD/p.txt")" = 0 ] && ok "global off: after several 10 s cycles hallo was NOT updated" || bad "global off: hallo was updated"
part "$C" C-POFF C-DENY > "$TMPD/p.txt"
has "$TMPD/p.txt" "bad_name" "a name with a slash is refused (bad_name)"
has "$TMPD/p.txt" "not_in_catalog" "a name that is no program is refused (not_in_catalog)"
has "$TMPD/p.txt" "bad_value" "a value that is no on/off is refused (bad_value)"
has "$TMPD/p.txt" "would=auto" "a dry run says what it would do"
has "$TMPD/p.txt" "autoapps=1" "global on again"
has "$TMPD/p.txt" "|update|0" "hallo's own switch is off (|update|0)"
[ "$(grep -c '|aktuell' "$TMPD/p.txt")" = 0 ] && ok "global on, hallo off: after several cycles hallo was NOT updated" || bad "per-program off: hallo was updated"
part "$C" C-DENY C-MANUAL > "$TMPD/p.txt"
has "$TMPD/p.txt" "not_allowed" "uid 1001 may not switch (the right to install is needed)"
has "$TMPD/p.txt" "autoapps=1" "... and the switch stayed on"
part "$C" C-MANUAL FERTIG > "$TMPD/p.txt"
has "$TMPD/p.txt" "phase=done" "manual update works while the program's automatic switch is off (job done)"
has "$TMPD/p.txt" "|aktuell|0" "hallo is current, its switch stayed off"

echo "== 4c. automatic updates: it really installs when on =="
cat > "$TMPD/sD.sh" <<'EOS'
mkdir /users/justin
opk install /quelle1/hallo-1.opk
orientbus serve 27000 &
sleep -m 300
stored serve 27000 &
sleep 1
setsess 1000
act call store.refresh
echo ==D-BEFORE==
sleep 90
echo ==D-AFTER==
act call store.status
act call store.list
opk list
echo ==FERTIG==
EOS
STORE_CONF="$TMPD/conf.auto" image "$TMPD/D.img" "$TMPD/sD.sh" $P0
run "$TMPD/D.img" d 900
D="$TMPD/d.klar"
grep -qa '==FERTIG==' "$D" || { bad "the auto-install guest did not finish"; tail -25 "$D" | sed 's/^/        /'; }
part "$D" D-AFTER FERTIG > "$TMPD/p.txt"
has "$TMPD/p.txt" "automatisch aktualisiert" "default on: stored ran an automatic round by itself"
has "$TMPD/p.txt" "|aktuell|1" "... and hallo is now current without any call to install it"

fi

if want apps; then
echo "== 4d. catalog 2 (store.apps / store.app): signed view, honest levels, refusals =="
python3 tools/storeapps/mkview.py gen "$TMPD/c2key" && ok "a test catalog key (Ed25519)" || bad "catalog key"
python3 tools/storeapps/mkview.py gen "$TMPD/c2other"
for v in good flip foreign; do cp -r "$TMPD/srv/good" "$TMPD/srv/c2$v"; done
python3 tools/storeapps/mkview.py write "$TMPD/srv/c2good" "$TMPD/c2key/catalog.seed"
python3 tools/storeapps/mkview.py write "$TMPD/srv/c2flip" "$TMPD/c2key/catalog.seed" flip
python3 tools/storeapps/mkview.py write "$TMPD/srv/c2foreign" "$TMPD/c2other/catalog.seed"
serve c2good $((P0+4)) && serve c2flip $((P0+5)) && serve c2foreign $((P0+6)) && ok "three catalog 2 sources: good, flipped octet, foreign key" || bad "a catalog 2 source does not start"
cat > "$TMPD/sD.sh" <<'EOS'
mkdir /users/justin
orientbus serve 27000 &
sleep -m 300
stored serve 27000 &
sleep 1
setsess 1000
echo ==D-BEFORE==
act call store.apps
echo ==D-REFRESH==
act call store.refresh
sleep 25
echo ==D-LIST==
act call store.apps lang=de
act call store.apps lang=en
ls /var/store
echo ==D-APP==
act call store.app name=com.test.partial lang=en
act call store.app name=com.test.wine lang=de
act call store.app name=com.test.mixed lang=en
act call store.app name=com.test.nogate lang=en
echo ==D-REFUSE==
act call store.app name=com.test.phone
act call store.app name=../etc
act call store.app name=nosuch
echo ==FERTIG==
EOS
EXTRA=("/etc/store.catalog.pub=$TMPD/c2key/catalog.pub")
for v in good:4 flip:5 foreign:6; do
    n=${v%%:*}; k=${v##*:}
    image "$TMPD/D$n.img" "$TMPD/sD.sh" $((P0+k))
    run "$TMPD/D$n.img" "d$n" 600
done
EXTRA=()
D="$TMPD/dgood.klar"
grep -qa '==FERTIG==' "$D" || { bad "the catalog 2 guest did not finish"; tail -25 "$D" | sed 's/^/        /'; }
part "$D" D-BEFORE D-REFRESH > "$TMPD/p.txt"
has "$TMPD/p.txt" "no_catalog2" "before any refresh there is no catalog 2 (old feeds show the old window)"
part "$D" D-LIST D-APP > "$TMPD/p.txt"
grep -q " apps " "$TMPD/p.txt" && ok "the verified view is stored as /var/store/apps" || bad "no /var/store/apps after refresh"
has "$TMPD/p.txt" "cat=internet|Internet" "categories are listed (de)"
has "$TMPD/p.txt" "cat=tools|Tools" "categories are listed (en)"
has "$TMPD/p.txt" "app=com.test.native|Nativ|tools|Fleitec|works|n|1.0.0|opk:nativ" "native app: works with gate, kind n, package"
has "$TMPD/p.txt" "app=com.test.partial|Teilweise|internet|Fleitec|partial|l|" "Linux app: partial, kind l"
has "$TMPD/p.txt" "app=com.test.wine|Wein|tools|Fleitec|broken|w|" "Windows app: broken, kind w"
has "$TMPD/p.txt" "app=com.test.mixed|Gemischt|tools|Fleitec|untested|n|" "mixed app: only the OrientOS variant counts (untested, not the broken Android one)"
has "$TMPD/p.txt" "app=com.test.nogate|Ohne Beleg|tools|Fleitec|untested|n|" "works without a gate is shown as untested"
hasnot "$TMPD/p.txt" "com.test.phone" "an Android-only app is not listed (wrong platform)"
has "$TMPD/p.txt" "apps=5" "five apps are listed"
has "$TMPD/p.txt" "app=com.test.native|Native|" "English names with lang=en"
part "$D" D-APP D-REFUSE > "$TMPD/p.txt"
has "$TMPD/p.txt" "variant=system|osum-linux-x86_64|1.0.0|0|0|0|1|partial|main test|QEMU|2026-11-20|tools/linux|Partly usable.|Unstable on the HP./One window only.|" "detail: variant with level, tested_on, gate, notes and limitations"
has "$TMPD/p.txt" "permissions=netz,disk" "detail: permissions"
has "$TMPD/p.txt" "screenshots=2" "detail: two screenshots"
has "$TMPD/p.txt" "variant=exe|osum-windows-x86_64|1.0.0|0|0|0|0|broken|" "detail: Windows variant is broken and not available"
has "$TMPD/p.txt" "Startet nicht." "detail: German notes with lang=de"
hasnot "$TMPD/p.txt" "android-arm64" "detail: the Android variant of a mixed app is dropped"
has "$TMPD/p.txt" "|1|untested|main test|QEMU|2026-11-20||" "detail: works without gate is downgraded to untested"
part "$D" D-REFUSE FERTIG > "$TMPD/p.txt"
[ "$(grep -c '^err ' "$TMPD/p.txt")" -ge 3 ] && ok "an Android-only app, a bad name and an unknown app are refused" || { bad "refusals: $(grep -c '^err ' "$TMPD/p.txt") of 3"; sed 's/^/        /' "$TMPD/p.txt" | head -8; }
has "$TMPD/p.txt" "err no_such_app com.test.phone" "the Android-only app is refused with no_such_app"
for n in flip foreign; do
    X="$TMPD/d$n.klar"
    grep -qa '==FERTIG==' "$X" || bad "the $n guest did not finish"
    part "$X" D-LIST D-APP > "$TMPD/p.txt"
    has "$TMPD/p.txt" "no_catalog2" "$n: the signature check refuses the view, store.apps has no catalog"
    hasnot "$TMPD/p.txt" "com.test.native" "$n: nothing of the refused view is shown"
    grep -q " apps " "$TMPD/p.txt" && bad "$n: an apps file was installed" || ok "$n: no apps file was installed"
done
fi

if want window; then
echo "== 5. the window (/bin/store) on a screen: grid, detail page, install, update, remove, search, keys =="
# STORE_RES=WxH (default 1024x768)  STORE_MODE=light|dark  STORE_SHOTS=<dir> keeps the pictures as PNG
RES=${STORE_RES:-1024x768}; MODE=${STORE_MODE:-light}; SHOTS=${STORE_SHOTS:-}
python3 tools/storeapps/mkview.py gen "$TMPD/c2wkey"
cp -r "$TMPD/srv/good" "$TMPD/srv/c2win"
python3 tools/storeapps/mkview.py window "$TMPD/srv/c2win" "$TMPD/c2wkey/catalog.seed"
serve c2win $((P0+7)) && ok "the window source: package list plus signed catalog 2 (hallo, gruss, a Windows and a Linux entry)" || bad "the window source does not start"
printf 'lang=de\n' > "$TMPD/locale.conf"
printf '# /etc/theme.conf\nscheme=day\nmode=%s\naccent=\nshape=classic\n' "$MODE" > "$TMPD/theme.conf"
{
    cat <<'EOS'
mkdir /users/justin
opk install /quelle1/hallo-1.opk
orientbus serve 0 &
sleep -m 300
stored serve 0 &
sleep 1
setsess 1000
store --show-installed &
echo ==S-WAIT==
EOS
    # the guest only has to stay alive and answer after the last key: snapshots every 40 s
    for _ in $(seq 1 55); do printf 'sleep 40\necho ==S-SNAP==\nopk list\nact call store.list\nact call store.status\n'; done
    echo "echo ==FERTIG=="
} > "$TMPD/sW.sh"
EXTRA=("/etc/store.catalog.pub=$TMPD/c2wkey/catalog.pub" "/etc/uitrace=$TMPD/locale.conf" "/etc/theme.conf=$TMPD/theme.conf" "/etc/locale.conf=$TMPD/locale.conf")
EXTRA+=(/usr/ /usr/share/ /usr/share/locale/ /usr/share/locale/de/ /usr/share/locale/en/ "/usr/share/locale/de/messages=locale/de/messages" "/usr/share/locale/en/messages=locale/en/messages")
[ -f assets/osum-icons.ttf ] && EXTRA+=("/lib/icons.ttf=assets/osum-icons.ttf")
[ -f assets/osum-sans-bold.ttf ] && EXTRA+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
PROGS_SAVE=$PROGS; PROGS="$PROGS store"
[ -z "${STORE_FIT:-}" ] || sed -i "s|^store --show-installed &\$|store --size ${STORE_FIT} --show-installed \&|" "$TMPD/sW.sh"
image "$TMPD/W.img" "$TMPD/sW.sh" $((P0+7))
PROGS=$PROGS_SAVE
SCALE_WORD=${STORE_SCALE:+uiscale=$STORE_SCALE}
SOCK="$TMPD/mon.sock"; rm -f "$SOCK"
timeout 2200 $QEMU_X86 -cpu "$OSUM_CPU" -smp 1 -kernel "$TMPD/k0.img" -m 768 \
    -append "gfx disp fbres=$RES $SCALE_WORD wm wmdauer wmshell osum vfs bus nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0 script=sh /t/s.sh;exit" \
    -serial "file:$TMPD/w.txt" -display none -no-reboot -device "VGA,edid=on,xres=${RES%x*},yres=${RES#*x},vgamem_mb=32" \
    -monitor "unix:$SOCK,server,nowait" \
    -netdev user,id=n0 -device e1000,netdev=n0,mac=52:54:00:0a:0b:0c \
    -drive "file=$TMPD/W.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/qemuw.txt" 2>&1 &
QPID=$!; SRVPIDS="$SRVPIDS $QPID"
. tools/store/winlib.sh
if waitfor "==S-WAIT==" 150; then
    ok "the script reached the window part"
    MARK=1; i=0; while [ $i -lt 60 ]; do sawt "Alle" && break; sleep 1; i=$((i + 1)); done
    sawt "Alle" && ok "the window opened" || bad "no window"
    MARK=1
    i=0; while [ $i -lt 120 ] && [ "$(lastn)" != 4 ]; do sleep 1; i=$((i + 1)); done
    { [ "$(lastn)" = 4 ] || { [ -n "${STORE_FIT:-}" ] && [ "$(lastn)" -ge 1 ]; }; } && ok "the window fetched the signed catalog by itself (first start): four tiles (two packages, two entries without a package)" || bad "no catalog tiles after the first start"
    sawt "store." && bad "raw locale keys painted" || ok "no raw locale keys"
    sleep 3; shot s1-grid
    if [ -n "${STORE_FIT:-}" ]; then
        sleep 6; shot s2-fit
        wclean | grep -a "store: geom " | tail -1 > "$TMPD/geom.txt"
        wclean | awk '/store: rect /' > "$TMPD/rects.txt"
        python3 -I tools/storefit/check.py "$RES" "${STORE_SCALE:-1}" "${STORE_FIT}" "$TMPD/geom.txt" "$TMPD/rects.txt" > "$TMPD/fit.txt" 2>&1
        while IFS= read -r l; do case "$l" in OK*) ok "${l#OK }";; INFO*) note "${l#INFO }";; *) bad "${l#FAIL }";; esac; done < "$TMPD/fit.txt"
        kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null
        echo "STORE: $pass passed, $fail failed"; [ "$fail" = 0 ]; exit
    fi
    MARK=1
    for t in "Updates" "Installiert" "Installieren" "Neue Fassung"; do sawt "$t" && ok "the window shows '$t'" || bad "no '$t'"; done
    [ "$(lastn)" = 4 ] && ok "four tiles (gruss, hallo, Weinprogramm, Feuerfuchs) -- what the signed catalogs deliver, nothing made up" || bad "tiles: '$(lastn)'"
    mark
    echo "  -- keys: Ctrl+F, type, the grid filters"
    key ctrl-f; typetext gru; sleep 2; shot s2-search
    [ "$(lastn)" = 1 ] && ok "search 'gru': one tile" || bad "search 'gru': tiles '$(lastn)'"
    key esc; sleep 2
    [ "$(lastn)" = 4 ] && ok "Esc clears the search: four tiles again" || bad "Esc: tiles '$(lastn)'"
    echo "  -- catalog 2 in the list: badges, the filter 'Nur einwandfreie', entries without a package"
    MARK=1
    sawt "Einwandfrei" && ok "a card carries the badge 'Einwandfrei'" || bad "no badge 'Einwandfrei'"
    sawt "Teilweise" && ok "a card carries the badge 'Teilweise'" || bad "no badge 'Teilweise'"
    sawt "Startet nicht" && ok "a card carries the badge 'Startet nicht'" || bad "no badge 'Startet nicht'"
    sawt "Nur einwandfreie" && ok "the filter chip 'Nur einwandfreie' is there" || bad "no filter chip"
    sawt "Internet" && ok "the category chips come from the catalog ('Internet')" || bad "no category chip from the catalog"
    mark; tapt "Nur einwandfreie" || bad "filter chip not found"; sleep 2
    [ "$(lastn)" = 2 ] && ok "'Nur einwandfreie': two tiles (hallo, gruss), nothing broken or partial" || bad "filter: tiles '$(lastn)'"
    shot s2b-works
    mark; tapt "Nur einwandfreie"; sleep 2
    [ "$(lastn)" = 4 ] && ok "the chip again: four tiles" || bad "chip off: tiles '$(lastn)'"
    mark; key ctrl-f; typetext wine; sleep 2
    [ "$(lastn)" = 1 ] && ok "search 'wine': the entry without a package" || bad "search 'wine': tiles '$(lastn)'"
    mark; key down ret; sleep 2; shot s2c-nopkg
    sawt "Kein Paket verfügbar" && ok "its detail page says there is no package" || bad "no 'Kein Paket verfügbar'"
    sawt "Installieren" && bad "an entry without a package offers Installieren" || ok "no Installieren button for an entry without a package"
    sawt "Startet nicht." && ok "the detail page shows the notes of the catalog" || bad "no notes on the detail page"
    key esc; sleep 1; key esc; sleep 2
    [ "$(lastn)" = 4 ] && ok "back to the list: four tiles" || bad "back: tiles '$(lastn)'"
    mark
    echo "  -- detail page of the first tile, by keys"
    mark; key ctrl-f down ret; sleep 2; shot s3-detail
    sawt "Version: " && ok "Enter on a tile opens the detail page (Version line)" || bad "no detail page"
    sawt "Prüfung: Katalog und Paket" && ok "the detail page says what is checked (signature + hash)" || bad "no check line"
    echo "  -- 'Abbrechen' installs nothing"
    mark; tapt "Installieren" || bad "no 'Installieren' button"
    sleep 1.5; shot s4-ask
    differs s3-detail s4-ask && ok "Installieren asks first: a question window opens (picture differs)" || bad "no question window"
    key esc; sleep 3
    sawjob && bad "Abbrechen started a job" || ok "the question answered with Abbrechen: no job"
    if [ -z "${STORE_ASK_ONLY:-}" ]; then
    echo "  -- install gruss"
    mark; D0=$(dlgn); tapt "Installieren"; sleep 1; key ret; dlgyes "$D0"
    i=0; while [ $i -lt 30 ] && ! sawjob; do sleep 1; i=$((i + 1)); done
    sawjob && ok "Installieren, then yes: the card shows the job progress in percent" || bad "no job progress after yes"
    shot s5-busy
    waitlog "done installiert" 150 && ok "... and the job ends: installed" || bad "no installed end of the job"
    PCTS=$(wclean | tail -n +"$MARK" | grep -ao "store: pct=[0-9]*" | tr -cd '0-9\n' | tr '\n' ' ')
    note "pct seen while working: $PCTS"
    echo "$PCTS" | awk '{ n=NF; ok=(n>=2); for (i=2;i<=n;i++) if ($i<$(i-1)) ok=0; exit ok?0:1 }' \
        && ok "the progress of stored climbs and never goes back ($PCTS)" || bad "pct not rising: '$PCTS'"
    shot s6-installed
    echo "  -- the updates page: one row, 'Alle aktualisieren', one question"
    key esc; sleep 1
    mark; tapt "Updates" || bad "no 'Updates' in the navigation"
    sleep 2; shot s7-updates
    sawt "Alle aktualisieren" && ok "the updates page offers 'Alle aktualisieren'" || bad "no 'Alle aktualisieren'"
    mark; D0=$(dlgn); tapt "Alle aktualisieren"; sleep 1.5; shot s7b-askall
    differs s7-updates s7b-askall && ok "one question for all opens (picture differs)" || bad "no question for all"
    key ret; dlgyes "$D0"
    waitlog "done installiert" 150 && ok "yes: hallo is updated" || bad "hallo was not updated"
    sleep 2; shot s8-uptodate
    differs s7-updates s8-uptodate && ok "afterwards the updates page looks different (the list is empty)" || bad "updates page unchanged"
    echo "  -- remove gruss from its detail page"
    mark; tapt "Alle" || bad "no 'Alle' in the navigation"; sleep 2
    key ctrl-f down ret; sleep 2
    mark; D0=$(dlgn); tapt "Entfernen" || bad "no Entfernen button"
    sleep 1.5; shot s8b-askremove
    differs s6-installed s8b-askremove && ok "Entfernen asks first: a question window opens (picture differs)" || bad "no remove question"
    key ret; dlgyes "$D0"
    waitlog "done entfernt" 150 && ok "yes: gruss removed" || bad "gruss was not removed"
    shot s9-end
    echo "  -- the automatic-update switches in the window (global on the updates page, one program on its detail page)"
    key esc; sleep 2
    mark; tapt "Updates" || bad "no 'Updates' in the navigation"; sleep 2
    shot s10-auto-off
    sawt "Apps automatisch aktualisieren" && ok "the updates page shows the global switch" || bad "no global switch"
    mark; tapt "Apps automatisch aktualisieren" || bad "global switch not found"; sleep 3
    shot s10b-auto-on
    differs s10-auto-off s10b-auto-on 30 && ok "clicking the global switch changes the picture" || bad "global switch click changed nothing"
    mark; tapt "Alle" || bad "no 'Alle' in the navigation"; sleep 2
    key ctrl-f down right ret; sleep 2
    sawt "Automatisch aktualisieren" && ok "the detail page of an installed program shows its own switch" || bad "no per-program switch"
    shot s11-app-on
    mark; tapt "Automatisch aktualisieren" || bad "per-program switch not found"; sleep 3
    shot s11b-app-off
    differs s11-app-on s11b-app-off 30 && ok "clicking the program's switch changes the picture" || bad "program switch click changed nothing"
    N=$(wclean | grep -ac "==S-SNAP==")
    i=0; while [ $i -lt 100 ]; do [ "$(wclean | grep -ac '==S-SNAP==')" -ge $((N + 2)) ] && break; sleep 2; i=$((i + 1)); done
    sleep 6
    wclean > "$TMPD/wc2.txt"
    awk -v n=$((N + 1)) '/==S-SNAP==/{c++; next} c==n' "$TMPD/wc2.txt" > "$TMPD/e.txt"
    [ -s "$TMPD/e.txt" ] && ok "a snapshot of the guest after the last click" || bad "no snapshot"
    has "$TMPD/e.txt" "  hallo -> " "at the end the package list has hallo ..."
    hasnot "$TMPD/e.txt" "  gruss -> " "... and not gruss (installed, then removed through the window)"
    has "$TMPD/e.txt" "item=hallo|2.0.0|" "the catalog says hallo is at 2.0.0"
    has "$TMPD/e.txt" "|aktuell" "hallo is up to date after the update through the window"
    has "$TMPD/e.txt" "autoapps=1" "the window's click turned the global switch on (it started off)"
    has "$TMPD/e.txt" "|aktuell|0" "the window's click turned hallo's own switch off"
    has "$TMPD/e.txt" "item=gruss|1.0.0|" "gruss is in the catalog again"
    fi
    [ -n "$SHOTS" ] && { cp "$TMPD/w.txt" "$SHOTS/serial-$MODE-$RES.txt" 2>/dev/null; note "pictures: $SHOTS"; }
else
    bad "the script never reached the window part"; wclean | tail -20 | sed 's/^/        /'
fi
kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null
fi

if want deps; then
echo "== 4e. requires: dependencies install first, are skipped when present, stay on removal =="
DSTAGE="$TMPD/dep"; mkdir -p "$DSTAGE"
mk_dep_pkg() { # name version deps
    local rz="$DSTAGE/$1-$2.rezept"
    sed -e "s/^name=hallo/name=$1/" -e "s/^version=.*/version=$2/" -e "s/^titel=.*/titel=$1/" -e "s#H1ELF#$TMPD/pk/h1.elf#" tools/install/hallo1.rezept > "$rz"
    [ -z "$3" ] || printf 'deps=%s\n' "$3" >> "$rz"
    python3 "$OPK" bauen "$rz" -o "$DSTAGE/$1-$2.opk" > "$DSTAGE/$1-$2.log" 2>&1 || { bad "build $1 $2"; tail -3 "$DSTAGE/$1-$2.log"; }
}
mk_dep_pkg wine 8.0.0 ""; mk_dep_pkg wine 9.1.0 ""; mk_dep_pkg winapp 1.0.0 "wine>=9.0"
python3 tools/update/signpak.py "$KEY" "$DSTAGE"/*.opk > "$DSTAGE/sign.log" 2>&1 && ok "wine 8.0.0, wine 9.1.0 and winapp (deps=wine>=9.0), signed" || { bad "signpak"; tail -3 "$DSTAGE/sign.log"; }
cat > "$TMPD/sD.sh" <<'EOS'
mkdir /users/justin
echo ==D-NONE==
opk install /d/winapp-1.0.0.opk
opk list
echo ==D-OLD==
opk install /d/wine-8.0.0.opk
opk install /d/winapp-1.0.0.opk
opk list
opk remove wine
echo ==D-OK==
opk install /d/wine-9.1.0.opk
opk install /d/winapp-1.0.0.opk
opk list
echo ==D-NEEDED==
opk remove wine
opk list
echo ==D-STAY==
opk remove winapp
opk list
echo ==D-LAST==
opk remove wine
opk list
echo ==FERTIG==
EOS
EXTRA=(/d/)
for f in "$DSTAGE"/*.opk "$DSTAGE"/*.opk.sig; do [ -f "$f" ] && EXTRA+=("/d/$(basename "$f")=$f"); done
image "$TMPD/D.img" "$TMPD/sD.sh" "$P0"
run "$TMPD/D.img" d 600
D="$TMPD/d.klar"
grep -qa '==FERTIG==' "$D" || { bad "the dependency guest did not finish"; tail -15 "$D" | sed 's/^/        /'; }
part "$D" D-NONE D-OLD > "$TMPD/p.txt"
has "$TMPD/p.txt" "missing dependency: wine" "winapp without wine: refused, wine named"
hasnot "$TMPD/p.txt" "winapp ->" "... and winapp is not installed"
part "$D" D-OLD D-OK > "$TMPD/p.txt"
has "$TMPD/p.txt" "dependency version too old: wine" "wine 8.0.0 is too old for wine>=9.0: refused"
hasnot "$TMPD/p.txt" "winapp ->" "... and winapp is not installed"
part "$D" D-OK D-NEEDED > "$TMPD/p.txt"
has "$TMPD/p.txt" "wine -> " "wine 9.1.0 installs"
has "$TMPD/p.txt" "winapp -> " "winapp installs after wine, the dependency is met"
part "$D" D-NEEDED D-STAY > "$TMPD/p.txt"
has "$TMPD/p.txt" "still needed by: winapp" "removing wine while winapp needs it: refused"
has "$TMPD/p.txt" "wine -> " "... wine is still there"
part "$D" D-STAY D-LAST > "$TMPD/p.txt"
hasnot "$TMPD/p.txt" "  winapp -> " "winapp removed"
has "$TMPD/p.txt" "wine -> " "the dependency stays when the app goes"
part "$D" D-LAST FERTIG > "$TMPD/p.txt"
hasnot "$TMPD/p.txt" "  wine -> " "wine removed on its own afterwards"
[ "$fail" = 0 ] || { echo "        -- guest output from D-NEEDED:"; sed -n '/==D-NEEDED==/,/==FERTIG==/p' "$D" | head -40 | sed 's/^/        /'; }
fi

if want tabs; then
echo "== 4f. the window tabs: Apps (not installed, no system), System, Runtimes, search is global, requires text =="
RES=${STORE_RES:-1024x768}; MODE=${STORE_MODE:-light}; SHOTS=${STORE_SHOTS:-}
python3 tools/storeapps/mkview.py gen "$TMPD/ctkey"
cp -r "$TMPD/srv/good" "$TMPD/srv/ctabs"
python3 tools/storeapps/mkview.py tabs "$TMPD/srv/ctabs" "$TMPD/ctkey/catalog.seed"
serve ctabs $((P0+8)) && ok "the tabs source: signed catalog with kind=system, runtime, cli and requires" || bad "the tabs source does not start"
printf 'lang=de\n' > "$TMPD/locale.conf"
printf '# /etc/theme.conf\nscheme=day\nmode=%s\naccent=\nshape=classic\n' "$MODE" > "$TMPD/theme.conf"
{
    cat <<'EOS'
mkdir /users/justin
opk install /quelle1/hallo-1.opk
orientbus serve 0 &
sleep -m 300
stored serve 0 &
sleep 1
setsess 1000
store &
echo ==S-WAIT==
EOS
    for _ in $(seq 1 30); do printf 'sleep 40\necho ==S-SNAP==\nact call store.list\n'; done
    echo "echo ==FERTIG=="
} > "$TMPD/sT.sh"
EXTRA=("/etc/store.catalog.pub=$TMPD/ctkey/catalog.pub" "/etc/uitrace=$TMPD/locale.conf" "/etc/theme.conf=$TMPD/theme.conf" "/etc/locale.conf=$TMPD/locale.conf")
EXTRA+=(/usr/ /usr/share/ /usr/share/locale/ /usr/share/locale/de/ /usr/share/locale/en/ "/usr/share/locale/de/messages=locale/de/messages" "/usr/share/locale/en/messages=locale/en/messages")
[ -f assets/osum-icons.ttf ] && EXTRA+=("/lib/icons.ttf=assets/osum-icons.ttf")
[ -f assets/osum-sans-bold.ttf ] && EXTRA+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
PROGS_SAVE=$PROGS; PROGS="$PROGS store"
image "$TMPD/T.img" "$TMPD/sT.sh" $((P0+8))
PROGS=$PROGS_SAVE
SOCK="$TMPD/mon.sock"; rm -f "$SOCK"
timeout 1500 $QEMU_X86 -cpu "$OSUM_CPU" -smp 1 -kernel "$TMPD/k0.img" -m 768 \
    -append "gfx disp fbres=$RES wm wmdauer wmshell osum vfs bus nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0 script=sh /t/s.sh;exit" \
    -serial "file:$TMPD/w.txt" -display none -no-reboot -device "VGA,edid=on,xres=${RES%x*},yres=${RES#*x},vgamem_mb=32" \
    -monitor "unix:$SOCK,server,nowait" \
    -netdev user,id=n0 -device e1000,netdev=n0,mac=52:54:00:0a:0b:0c \
    -drive "file=$TMPD/T.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/qemut.txt" 2>&1 &
QPID=$!; SRVPIDS="$SRVPIDS $QPID"
. tools/store/winlib.sh
if waitfor "==S-WAIT==" 150; then
    ok "the script reached the window part"
    MARK=1; i=0; while [ $i -lt 120 ] && [ "$(lastn)" != 3 ]; do sleep 1; i=$((i + 1)); done
    [ "$(lastn)" = 3 ] && ok "start page is the Apps tab: three tiles (Gruss, Tabnativ, Weinapp), not the installed Hallo, no system or runtime tools" || bad "apps tab tiles: '$(lastn)' (want 3)"
    sleep 3; shot t1-apps
    for t in "Tabnativ" "Weinapp"; do sawt "$t" && ok "Apps tab shows '$t'" || bad "Apps tab misses '$t'"; done
    for t in "Sysbox" "Weinlauf" "Klitool" "Hallo"; do sawt "$t" && bad "Apps tab shows '$t' and should not" || ok "Apps tab hides '$t'"; done
    for t in "System" "Laufzeiten" "Installierte zeigen"; do sawt "$t" && ok "the window offers '$t'" || bad "no '$t'"; done
    mark
    tapt "Installierte zeigen" && sleep 3
    sawt "Hallo" && [ "$(lastn)" = 4 ] && ok "Show installed brings Hallo back (four tiles)" || bad "show installed: tiles '$(lastn)'"
    shot t2-installed
    mark
    tapt "Installierte zeigen" && sleep 3
    [ "$(lastn)" = 3 ] && ok "switching it off hides Hallo again" || bad "show installed off: tiles '$(lastn)'"
    mark
    tapt "System" && sleep 3
    sawt "Sysbox" && [ "$(lastn)" = 1 ] && ok "System tab: only Sysbox" || bad "system tab: tiles '$(lastn)'"
    sawt "Weinlauf" && bad "System tab shows a runtime" || ok "System tab has no runtime"
    shot t3-system
    mark
    tapt "Laufzeiten" && sleep 3
    sawt "Weinlauf" && sawt "Klitool" && [ "$(lastn)" = 2 ] && ok "Runtimes tab: Weinlauf and Klitool (cli)" || bad "runtimes tab: tiles '$(lastn)'"
    sawt "Tabnativ" && bad "Runtimes tab shows an app" || ok "Runtimes tab has no app"
    shot t4-runtimes
    mark
    tapt "Programme" && sleep 2
    key ctrl-f; typetext weinl; sleep 3
    sawt "Weinlauf" && [ "$(lastn)" = 1 ] && ok "search finds the runtime from the Apps tab" || bad "search weinl: tiles '$(lastn)'"
    [ "$(wclean | tail -n +"$MARK" | grep -acF -- "in Laufzeiten")" -gt 0 ] && ok "the hit says where it lives: in Laufzeiten" || { bad "no category on the search hit"; wclean | tail -n +"$MARK" | grep -a "Laufzeiten" | tail -4 | cut -c1-200 | sed 's/^/        /'; }
    shot t5-search
    key esc; key ctrl-f; typetext sysb; sleep 3
    sawt "Sysbox" && ok "search finds the system tool from the Apps tab" || bad "search sysb"
    key esc; key ctrl-f; typetext hall; sleep 3
    sawt "Hallo" && ok "search finds the installed app although the Apps tab hides it" || bad "search hall"
    key esc; sleep 2
    mark
    key esc; key ctrl-f; typetext weinap; sleep 3
    key down; key ret; sleep 3
    sawt "Benötigt: Weinlauf (wird mitinstalliert)" && ok "detail page says what is needed before installing: Weinlauf (wird mitinstalliert)" || bad "no requires line on the detail page"
    shot t6-detail
    sawt "store." && bad "raw locale keys painted" || ok "no raw locale keys"
else
    bad "the script never reached the window part"; wclean | tail -20 | sed 's/^/        /'
fi
kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null
fi

if want offline; then
echo "== 6. the window offline: no store service answers, the installed list comes from local state =="
RES=${STORE_RES:-1024x768}; SHOTS=${STORE_SHOTS:-}
printf 'lang=de\n' > "$TMPD/locale.conf"
printf '# /etc/theme.conf\nscheme=day\nmode=light\naccent=\nshape=classic\n' > "$TMPD/theme.conf"
cat > "$TMPD/sO.sh" <<'EOS'
mkdir /users/justin
opk install /quelle1/hallo-1.opk
setsess 1000
store --show-installed &
echo ==O-WAIT==
sleep 400
echo ==FERTIG==
EOS
EXTRA=("/etc/uitrace=$TMPD/locale.conf" "/etc/theme.conf=$TMPD/theme.conf" "/etc/locale.conf=$TMPD/locale.conf")
EXTRA+=(/usr/ /usr/share/ /usr/share/locale/ /usr/share/locale/de/ /usr/share/locale/en/ "/usr/share/locale/de/messages=locale/de/messages" "/usr/share/locale/en/messages=locale/en/messages")
[ -f assets/osum-icons.ttf ] && EXTRA+=("/lib/icons.ttf=assets/osum-icons.ttf")
[ -f assets/osum-bold.ttf ] && EXTRA+=("/lib/bold.ttf=assets/osum-bold.ttf")
[ -f assets/osum-sans-bold.ttf ] && EXTRA+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
PROGS_SAVE=$PROGS; PROGS="$PROGS store"
image "$TMPD/O.img" "$TMPD/sO.sh" $P0
PROGS=$PROGS_SAVE
SOCK="$TMPD/mon.sock"; rm -f "$SOCK"
timeout 600 $QEMU_X86 -cpu "$OSUM_CPU" -smp 1 -kernel "$TMPD/k0.img" -m 768 \
    -append "gfx disp fbres=$RES wm wmdauer wmshell osum vfs bus nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0 script=sh /t/s.sh;exit" \
    -serial "file:$TMPD/o.txt" -display none -no-reboot -device "VGA,edid=on,xres=${RES%x*},yres=${RES#*x},vgamem_mb=32" \
    -monitor "unix:$SOCK,server,nowait" \
    -netdev user,id=n0 -device e1000,netdev=n0,mac=52:54:00:0a:0b:0c \
    -drive "file=$TMPD/O.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/qemuo.txt" 2>&1 &
QPID=$!; SRVPIDS="$SRVPIDS $QPID"
oclean() { tr -cd '\11\12\15\40-\176\200-\377' < "$TMPD/o.txt"; }
owait() { local i=0; while [ $i -lt $(( $2 * 5 )) ]; do oclean | tail -n +"$MARK" | grep -qaF -- "$1" && return 0; kill -0 "$QPID" 2>/dev/null || return 1; sleep 0.2; i=$((i + 1)); done; return 1; }
oshot() { python3 tools/gfx/screenshot.py "$SOCK" "$TMPD/$1.ppm" 5 > /dev/null 2>&1
    if [ -n "$SHOTS" ] && [ -s "$TMPD/$1.ppm" ]; then mkdir -p "$SHOTS"; python3 -c "import sys; from PIL import Image; Image.open(sys.argv[1]).save(sys.argv[2])" "$TMPD/$1.ppm" "$SHOTS/$1-$RES.png" 2>/dev/null; fi; }
otap() { local xy
    xy=$(oclean | awk -v want="$1" '
        /wlib: text win=/ {
            i = index($0, " t="); txt = substr($0, i + 3); if (txt != want) next
            match($0, / x=[0-9]+/); x = substr($0, RSTART + 3, RLENGTH - 3)
            match($0, / base=[0-9]+/); b = substr($0, RSTART + 6, RLENGTH - 6)
            match($0, / tw=[0-9]+/); w = substr($0, RSTART + 4, RLENGTH - 4)
            match($0, / ax=[0-9]+/); ax = substr($0, RSTART + 4, RLENGTH - 4)
            match($0, / ay=[0-9]+/); ay = substr($0, RSTART + 4, RLENGTH - 4)
            have = 1; cx = ax + x + w / 2; cy = ay + b - 6 }
        END { if (have) printf "%d %d\n", cx, cy }')
    [ -n "$xy" ] || return 1
    set -- $xy
    python3 tools/themestore/click.py "$1,$2" > "$TMPD/k.txt" 2>/dev/null; python3 tools/wm/monitor.py "$SOCK" "$TMPD/k.txt" > /dev/null 2>&1; sleep 1.5; }
MARK=1
if owait "==O-WAIT==" 150; then
    ok "the script reached the window part"
    MARK=1; owait "t=Installiert" 90 && ok "the window opened" || bad "no window"
    sleep 8; oshot o1-first
    MARK=$(oclean | wc -l); otap "Installiert" || bad "no 'Installiert' in the navigation"
    sleep 3; oshot o2-installed
    owait "t=Hallo" 20 && ok "Installiert lists the installed program offline (Hallo, from /apps)" || bad "Installiert does not list hallo offline"
    retry_button_at() { python3 -c "
import sys
from PIL import Image
r, g, b = Image.open(sys.argv[1]).convert('RGB').getpixel((300, 500))
sys.exit(0 if b > 200 and r < 80 else 1)" "$TMPD/$1.ppm" 2>/dev/null; }
    retry_button_at o2-installed && bad "Installiert shows the error state offline (retry button painted)" || ok "Installiert shows no error state (no retry button) offline"
    MARK=$(oclean | wc -l); otap "Programme" || bad "no 'Programme' in the navigation"
    sleep 3; oshot o3-all
    retry_button_at o3-all && ok "the catalog page (Programme) shows the offline state with the retry button" || bad "the catalog page shows no offline state"
else
    bad "the script never reached the window part"; oclean | tail -20 | sed 's/^/        /'
fi
kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null
fi

if want xremote; then
echo "== 7. xremote is a Store package: shipped in the image, then update, remove, install =="
XR_SRC=${XR_DIR:-/root/jarvis/data/orientos-xremote/system}
if [ ! -s "$XR_SRC/freeviewer-host" ]; then
    note "skipped, $XR_SRC/freeviewer-host is missing"
else
    XRS="$TMPD/xr-stage"
    bash tools/xremote/stage.sh "$XRS" > "$TMPD/xr-stage.log" 2>&1 && ok "xremote stages as an installed package (store record + links, no SYSTEM marker)" || { bad "xremote stage"; tail -3 "$TMPD/xr-stage.log"; }
    [ -e "$XRS/apps/xremote.osp/SYSTEM" ] && bad "the staged bundle still carries a SYSTEM marker" || ok "the staged bundle has no SYSTEM marker"
    XR_VERSION=0.2.9 XR_OPK_OUT="$TMPD/xremote-new.opk" bash tools/xremote/stage.sh "$TMPD/xr-new" > "$TMPD/xr-new.log" 2>&1 && ok "xremote 0.2.9 built for the signed source" || { bad "xremote 0.2.9 build"; tail -3 "$TMPD/xr-new.log"; }
    mkstore "$TMPD/srv/xr" "$KEY" "$TMPD/xremote-new.opk" && ok "signed source with xremote 0.2.9: $(wc -l < "$TMPD/srv/xr/INDEX") program" || bad "xremote source"
    serve xr $((P0+4)) && ok "the xremote source is up" || bad "xremote source does not start"
    cat > "$TMPD/sXr.sh" <<'EOS'
mkdir /users/justin
orientbus serve 0 &
sleep -m 300
stored serve 0 &
sleep 1
apprights load
setsess 1000
echo ==X-SHIPPED==
opk list
apprights get xremote
ls /apps
act call store.refresh
sleep 30
echo ==X-LIST==
act call store.list
echo ==X-UPD==
act call store.update name=xremote
act confirm last
sleep 120
act call store.status
opk list
act call store.list
echo ==X-REM==
act call store.remove name=xremote
act confirm last
sleep 10
act call store.status
opk list
ls /apps
act call store.list
echo ==X-INST==
act call store.install name=xremote
act confirm last
sleep 120
act call store.status
opk list
apprights get xremote
ls /apps/xremote.osp/bin
act call store.list
echo ==X-END==
EOS
    EXTRA=($(python3 tools/xremote/mkfsargs.py "$XRS"))
    image "$TMPD/xr.img" "$TMPD/sXr.sh" $((P0+4))
    EXTRA=()
    run "$TMPD/xr.img" xr 900
    X="$TMPD/xr.klar"
    has "$X" "==X-END==" "the xremote script ran to its end"
    part "$X" X-SHIPPED X-LIST > "$TMPD/p.txt"
    has "$TMPD/p.txt" "xremote -> " "the image ships xremote as an installed package (opk list)"
    has "$TMPD/p.txt" "apprights: xremote mask=4 net" "the shipped package holds the net right"
    has "$TMPD/p.txt" "xremote.osp" "/apps links xremote.osp"
    part "$X" X-LIST X-UPD > "$TMPD/p.txt"
    has "$TMPD/p.txt" "item=xremote|0.2.9|" "the signed catalog offers xremote 0.2.9"
    has "$TMPD/p.txt" "|update" "the store marks the shipped xremote as update"
    part "$X" X-UPD X-REM > "$TMPD/p.txt"
    has "$TMPD/p.txt" "phase=done" "update xremote: done"
    has "$TMPD/p.txt" "xremote -> " "xremote is installed after the update"
    hasnot "$TMPD/p.txt" "|update" "no pending update after the update"
    part "$X" X-REM X-INST > "$TMPD/p.txt"
    has "$TMPD/p.txt" "msg=entfernt" "remove xremote: done (it is no longer a fixed system part)"
    hasnot "$TMPD/p.txt" "  xremote -> " "xremote is gone from the package list"
    hasnot "$TMPD/p.txt" "xremote.osp" "/apps/xremote.osp is gone"
    has "$TMPD/p.txt" "|neu" "xremote is 'neu' again"
    part "$X" X-INST X-END > "$TMPD/p.txt"
    has "$TMPD/p.txt" "msg=installiert" "install xremote: done"
    has "$TMPD/p.txt" "xremote -> " "xremote is in the package list again"
    has "$TMPD/p.txt" "freeviewer-host" "the host binary is back under /apps/xremote.osp/bin"
    has "$TMPD/p.txt" "apprights: xremote mask=4 net" "the net right is granted again"
fi
fi

echo
echo "STORE: $pass passed, $fail failed"
[ "$fail" = 0 ]
