#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/store/run.sh -- P-007: THE STORE (provider /bin/stored, window /bin/store), MEASURED.
#
#   bash tools/store/run.sh
#
# AGAINST WHAT. There is no real store to test against from here, so the runner serves
# SIGNED sources over HTTPS from the host (tools/ota/server.py: real TLS 1.3 from Python's
# ssl, a real certificate chain), made with the host's own opk (not this repository's
# idea of a package): two programs, `gruss` (new) and `hallo` (the device has 1.0.0, the
# store offers 2.0.0). The device is a QEMU guest with an e1000 behind QEMU's user network
# (10.0.2.2 is the host), the action bus, and the REAL provider /bin/stored -- every
# call below goes through the broker with `act`, the way the window does it.
#
# SECTIONS
#   1. build: the programs (stored, store, opk, ota, fetch ...), the kernel, setsess
#   2. the sources and the server: good store; three bad ones: a package with a flipped
#      octet and its OLD signature, a flipped package RE-SIGNED with the right key (the
#      signature is fine, the hash in the signed catalog is not -- the case a single signature
#      cannot catch), and a catalog signed with a FOREIGN key
#   3. the good way, over the bus, from the signed-in person: the list is empty before
#      the first fetch, `store.refresh` brings the verified catalog (gruss = neu, hallo =
#      update), install -> the program is in `opk liste`, update -> hallo is the new
#      version, remove -> it is gone; a dry run changes nothing; a name that is no program
#      is refused
#   4. the rights, enforced in the provider: admin (default) lets root and uid 1000 in and
#      keeps uid 1001 out; `benutzer` lets every account in but never nobody; `aus` nobody;
#      `admins=` adds a uid -- and the same over the bus: another account's request
#      confirmed by the person still ends in `not_allowed`
#   5. the three refusals: flipped package (signature), re-signed flipped package (hash),
#      foreign catalog -- and after each NOTHING is installed
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
PROGS="sh ls cat echo sleep mkdir cp chmod rm orientbus act su stored opk ota"
SRV_PORT=${STORE_PORT:-$(( 19000 + ($$ % 900) ))}

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
mkdir -p "$TMPD/bin"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS store > "$TMPD/b.txt" 2>&1; then
    ok "firnc0 builds $(echo $PROGS store | wc -w) programs (stored $(stat -c%s "$TMPD/bin/stored.elf") B, store $(stat -c%s "$TMPD/bin/store.elf") B, opk $(stat -c%s "$TMPD/bin/opk.elf") B)"
else
    bad "the programs do not build"; sed 's/^/        /' "$TMPD/b.txt" | head -20
    echo "STORE: $pass passed, $fail failed"; exit 1
fi
# /bin/fetch: the full library with TLS (profile app, no crt.o)
if vendor/firn/bin/firnc -c --profile=app -o "$TMPD/fetch.o" kernel/app/fetch.fi > "$TMPD/fe.txt" 2>&1 \
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
sed -e 's/^name=hallo/name=gruss/' -e 's/^fassung=.*/fassung=1.0.0/' -e 's/^titel=.*/titel=Gruss/' -e "s#H1ELF#$TMPD/pk/h1.elf#" tools/install/hallo1.rezept > "$TMPD/gruss.rezept"
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
printf 'installieren=admin\nentfernen=admin\nadmins=1000\n' > "$TMPD/conf.admin"
printf 'installieren=benutzer\nentfernen=benutzer\n' > "$TMPD/conf.benutzer"
printf 'installieren=aus\nentfernen=aus\n' > "$TMPD/conf.aus"
printf 'installieren=admin\nentfernen=admin\nadmins=1001\n' > "$TMPD/conf.admins"
cat > "$TMPD/policy" <<'EOF'
# the store test: the shipped defaults
dryfirst jarvis
EOF
EXTRA=()
image() { # <image> <script> <port>
    local img=$1 script=$2 port=$3
    printf 'quelle=https://10.0.2.2:%s\nname=ota.test\nabstand=3600\nauto=nein\nfrist=15\n' "$port" > "$TMPD/ota.conf"
    local -a A=(build "$img" $BLOCKS --v3 --inodes=512 --karten=64 /lib/
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /etc/actions.d/ /etc/orientbus/ /etc/ssl/ /store/ /apps/ /users/ /var/ /var/log/ /quelle1/)
    local p
    for p in $PROGS fetch; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
    A+=("/bin/setsess=$TMPD/setsess"
        "/etc/passwd=$TMPD/passwd" "/etc/group=$TMPD/group"
        "/etc/actions.d/store.actions=etc/actions.d/store.actions"
        "/etc/orientbus/policy=$TMPD/policy"
        "/etc/store.conf=$TMPD/conf.admin" "/etc/store.admin=$TMPD/conf.admin" "/etc/store.benutzer=$TMPD/conf.benutzer"
        "/etc/store.aus=$TMPD/conf.aus" "/etc/store.admins=$TMPD/conf.admins"
        "/etc/ota.conf=$TMPD/ota.conf" "/etc/ssl/roots.pem=$TMPD/certs/ca.pem"
        "/system/schluessel.pub=$TMPD/pk/schluessel.pub"
        "/quelle1/hallo-1.opk=$TMPD/pk/quelle1/hallo-1.opk" "/quelle1/hallo-1.opk.sig=$TMPD/pk/quelle1/hallo-1.opk.sig"
        "/quelle1/INDEX=$TMPD/pk/quelle1/INDEX" "/quelle1/INDEX.sig=$TMPD/pk/quelle1/INDEX.sig"
        "/t/s.sh=$script")
    A+=("${EXTRA[@]}")
    python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 || { echo "mkfs failed"; tail -3 "$TMPD/mkfs.txt"; }
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

if [ -z "${STORE_WINDOW_ONLY:-}" ]; then
echo "== 3. the good way, over the bus, from the signed-in person =="
cat > "$TMPD/sA.sh" <<'EOS'
mkdir /users/justin
opk installieren /quelle1/hallo-1.opk
orientbus serve 600000 &
sleep -m 300
stored serve 600000 &
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
opk liste
act call store.list
echo ==A-UPD==
act call store.update name=hallo
act confirm last
sleep 40
act call store.status
opk liste
act call store.list
echo ==A-REM==
act call store.remove name=gruss
act confirm last
sleep 6
act call store.status
opk liste
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
opk liste
act call store.list
cp /etc/store.benutzer /etc/store.conf
echo ==A-MARA2==
su mara /bin/act call store.install name=gruss
act confirm last
sleep 40
act call store.status
opk liste
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
has "$TMPD/p.txt" "phase=fertig" "the refresh is done (phase=fertig)"
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
has "$TMPD/p.txt" "phase=fertig" "install gruss: done"
has "$TMPD/p.txt" "msg=installiert" "... and says so"
has "$TMPD/p.txt" "  gruss -> " "gruss is in the package list (opk liste)"
has "$TMPD/p.txt" "|aktuell" "gruss is up to date (state aktuell)"
part "$A" A-UPD A-REM > "$TMPD/p.txt"
has "$TMPD/p.txt" "phase=fertig" "update hallo: done"
has "$TMPD/p.txt" "item=hallo|2.0.0|" "hallo is in the catalog"
[ "$(grep -c '|update' "$TMPD/p.txt")" = 0 ] && ok "hallo is no longer 'update' (it IS 2.0.0 now)" || bad "hallo still says update"
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
orientbus serve 600000 &
sleep -m 300
stored serve 600000 &
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
opk liste
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
        has "$TMPD/p.txt" "phase=fehler" "flipped package: refused (phase=fehler)"
        has "$TMPD/p.txt" "abgelehnt" "... named as rejected"
        hasnot "$TMPD/p.txt" "  gruss -> " "... and nothing was installed";;
    hash)
        part "$B" B-INST FERTIG > "$TMPD/p.txt"
        has "$TMPD/p.txt" "phase=fehler" "re-signed flipped package (valid signature, wrong hash): refused"
        hasnot "$TMPD/p.txt" "  gruss -> " "... and nothing was installed"
        has "$B" "opk:" "(opk named the reason)";;
    foreign)
        part "$B" B-REF B-INST > "$TMPD/p.txt"
        has "$TMPD/p.txt" "phase=fehler" "catalog signed with a foreign key: refused (phase=fehler)"
        has "$TMPD/p.txt" "count=0" "... the unverified catalog was never listed (count=0)"
        part "$B" B-INST FERTIG > "$TMPD/p.txt"
        has "$TMPD/p.txt" "not_in_catalog" "... and installing from it is not possible"
        hasnot "$TMPD/p.txt" "  gruss -> " "... nothing installed";;
    esac
done

fi # STORE_WINDOW_ONLY

echo "== 5. the window (/bin/store) on a screen: catalog, install, update, remove, with the clicks of a hand =="
printf 'lang=de\n' > "$TMPD/locale.conf"
printf '# /etc/theme.conf\nscheme=day\nmode=light\naccent=\nshape=classic\n' > "$TMPD/theme.conf"
cat > "$TMPD/sW.sh" <<'EOS'
mkdir /users/justin
opk installieren /quelle1/hallo-1.opk
orientbus serve 0 &
sleep -m 300
stored serve 0 &
sleep 1
setsess 1000
store &
echo ==S-WAIT==
sleep 80
echo ==S-SNAP==
opk liste
act call store.list
sleep 80
echo ==S-SNAP==
opk liste
act call store.list
sleep 80
echo ==S-SNAP==
opk liste
act call store.list
sleep 80
echo ==S-SNAP==
opk liste
act call store.list
sleep 80
echo ==S-SNAP==
opk liste
act call store.list
sleep 80
echo ==S-SNAP==
opk liste
act call store.list
sleep 80
echo ==S-SNAP==
opk liste
act call store.list
sleep 80
echo ==S-SNAP==
opk liste
act call store.list
sleep 80
echo ==S-SNAP==
opk liste
act call store.list
sleep 80
echo ==FERTIG==
EOS
EXTRA=("/etc/uitrace=$TMPD/locale.conf" "/etc/theme.conf=$TMPD/theme.conf" "/etc/locale.conf=$TMPD/locale.conf")
[ -f assets/osum-icons.ttf ] && EXTRA+=("/lib/icons.ttf=assets/osum-icons.ttf")
[ -f assets/osum-sans-bold.ttf ] && EXTRA+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
PROGS_SAVE=$PROGS; PROGS="$PROGS store"
image "$TMPD/W.img" "$TMPD/sW.sh" "$P0"
PROGS=$PROGS_SAVE
SOCK="$TMPD/mon.sock"; rm -f "$SOCK"
timeout 1100 $QEMU_X86 -cpu "$OSUM_CPU" -smp 1 -kernel "$TMPD/k0.img" -m 768 \
    -append "gfx disp wm wmdauer wmshell osum vfs bus nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0 script=sh /t/s.sh;exit" \
    -serial "file:$TMPD/w.txt" -display none -no-reboot -vga std -monitor "unix:$SOCK,server,nowait" \
    -netdev user,id=n0 -device e1000,netdev=n0,mac=52:54:00:0a:0b:0c \
    -drive "file=$TMPD/W.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/qemuw.txt" 2>&1 &
QPID=$!; SRVPIDS="$SRVPIDS $QPID"
wclean() { tr -cd '\11\12\15\40-\176' < "$TMPD/w.txt"; }
waitfor() { local i=0; while [ $i -lt $(( $2 * 5 )) ]; do grep -qaF -- "$1" "$TMPD/w.txt" 2>/dev/null && return 0; kill -0 "$QPID" 2>/dev/null || return 1; sleep 0.2; i=$((i + 1)); done; return 1; }
waitforn() { local i=0; while [ $i -lt $(( $2 * 5 )) ]; do wclean | grep -qaF -- "$1" && return 0; sleep 0.2; i=$((i + 1)); done; return 1; }
shot() { python3 tools/gfx/screenshot.py "$SOCK" "$1" 5 > /dev/null 2>&1; }
klick() { python3 tools/themestore/click.py "$1,$2" > "$TMPD/k.txt" 2>/dev/null; python3 tools/wm/monitor.py "$SOCK" "$TMPD/k.txt" > /dev/null 2>&1; sleep 1.5; }
taste() { echo "sendkey $1" > "$TMPD/t.txt"; python3 tools/wm/monitor.py "$SOCK" "$TMPD/t.txt" 0.15 > /dev/null 2>&1; sleep 1.5; }
mark() { MARK=$(wclean | wc -l); }
waitnew() { local i=0; while [ $i -lt $2 ]; do wclean | tail -n +"$MARK" | grep -qaF -- "t=$1" && return 0; sleep 1; i=$((i + 1)); done; return 1; }
seennew() { wclean | tail -n +"$MARK" | grep -qaF -- "t=$1"; }
if waitfor "==S-WAIT==" 150; then
    ok "the script reached the window part"
    waitforn "t=Programme" 60 && ok "the window opened" || bad "no window"
    mark
    waitnew "Fertig: Katalog neu" 120 && ok "the window fetched the signed catalog by itself (first start): 'Fertig: Katalog neu'" || bad "no 'Fertig: Katalog neu'"
    for t in Aktualisieren Installieren "Neue Fassung" Entfernen; do
        MARK=1; waitnew "$t" 20 && ok "the window shows '$t'" || bad "no '$t'"
    done
    read -r OX OY < <(wclean | grep -ao 'ax=[0-9]* ay=[0-9]*' | tail -1 | tr -cd '0-9 ')
    BI=$((OX + 146 + 58)); BY=$((OY + 348 + 17))      # the button Installieren
    DY=$((OY + 299)); DYES=$((OX + 223)); DNO=$((OX + 376))   # the question: yes / no
    shot "$TMPD/w1.ppm"
    python3 - "$TMPD/w1.ppm" "$OX" "$OY" > "$TMPD/s1.txt" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB"); ox, oy = int(sys.argv[2]), int(sys.argv[3])
rows = [sum(1 for x in range(ox + 20, ox + 560, 4) if im.getpixel((x, oy + 40 + 44 + 28 * i))[2] > 200 and im.getpixel((x, oy + 40 + 44 + 28 * i))[0] < 80) for i in range(2)]
print("selected", rows.index(max(rows)) if max(rows) > 20 else -1)
PY
    grep -qx "selected 0" "$TMPD/s1.txt" && ok "the first row (gruss) is chosen at the start (picture)" || bad "no first row chosen"
    echo "  -- 'Abbrechen' installs nothing"
    mark; klick $BI $BY
    sleep 1; shot "$TMPD/w2.ppm"
    klick $DNO $DY
    sleep 3
    seennew "Arbeitet ... bitte warten" && bad "Abbrechen started a job" || ok "the question 'Programm installieren?' answered with Abbrechen: no job"
    echo "  -- install gruss"
    mark; klick $BI $BY
    klick $DYES $DY
    waitnew "Arbeitet ... bitte warten" 30 && ok "Installieren, then yes: the window says it is working" || bad "no 'Arbeitet' after yes"
    waitnew "Fertig: installiert" 150 && ok "... and 'Fertig: installiert'" || bad "no 'Fertig: installiert'"
    shot "$TMPD/w3.ppm"
    echo "  -- update hallo (row 2)"
    mark; klick $((OX + 100)) $((OY + 40 + 44 + 28))
    klick $((OX + 270 + 68)) $BY
    sleep 1; shot "$TMPD/w4.ppm"
    klick $((OX + 223)) $DY
    waitnew "Fertig: installiert" 150 && ok "Neue Fassung, then yes: hallo is updated ('Fertig: installiert')" || bad "hallo was not updated"
    echo "  -- remove gruss (row 1)"
    mark; klick $((OX + 100)) $((OY + 40 + 44))
    klick $((OX + 415 + 53)) $BY
    sleep 1; shot "$TMPD/w5.ppm"
    klick $((OX + 223)) $DY
    waitnew "Fertig: entfernt" 150 && ok "Entfernen, then yes: 'Fertig: entfernt'" || bad "gruss was not removed"
    shot "$TMPD/w6.ppm"
    N=$(wclean | grep -ac "==S-SNAP==")
    i=0; while [ $i -lt 100 ]; do [ "$(wclean | grep -ac '==S-SNAP==')" -ge $((N + 2)) ] && break; sleep 2; i=$((i + 1)); done
    sleep 6
    wclean > "$TMPD/wc2.txt"
    # the snapshot BEFORE the last marker: complete, and taken after the last click
    awk -v n=$((N + 1)) '/==S-SNAP==/{c++; next} c==n' "$TMPD/wc2.txt" > "$TMPD/e.txt"
    [ -s "$TMPD/e.txt" ] && ok "a snapshot of the guest after the last click" || bad "no snapshot"
    has "$TMPD/e.txt" "  hallo -> " "at the end the package list has hallo ..."
    hasnot "$TMPD/e.txt" "  gruss -> " "... and not gruss (installed, then removed through the window)"
    has "$TMPD/e.txt" "item=hallo|2.0.0|" "the catalog says hallo is at 2.0.0"
    has "$TMPD/e.txt" "|aktuell" "hallo is up to date after the update through the window"
    has "$TMPD/e.txt" "item=gruss|1.0.0|" "gruss is in the catalog again"
else
    bad "the script never reached the window part"; wclean | tail -20 | sed 's/^/        /'
fi
kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null

echo
echo "STORE: $pass passed, $fail failed"
[ "$fail" = 0 ]
