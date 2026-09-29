#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/social/run.sh -- THE SOCIAL LAYER ON ORIENT-BUS, MEASURED.
#
#   bash tools/social/run.sh
#   FLEIKONTAKTE=/path/to/bin/fleikontakte   (default: the FirnChat repo)
#
# A real Osum guest under QEMU with the broker /bin/orientbus, the social
# service /bin/social (kernel/user/social.fi) and two providers behind
# the provider interface: /bin/socfleitec (kernel/app, speaks to a REAL
# fleikontakte on the host with a device access token, over the guest's
# network) and /bin/soclocal (contacts kept on the device). The client
# is /bin/act -- the same every caller uses. On the host, tools/social/
# host.py plays the friends: it watches the guest's output and checks at
# markers what they see of justin.
#
# Sections:
#   1. build: kernel, programs, the manifest (host reader)
#   2. the catalogue: 14 social.* actions and 3 events, provider bound
#   3. the book: both providers merged, filters, one contact, search
#   4. relations: an agent is parked, the user accepts, dry run, withdraw,
#      request + undo (the manifest's inverse), a local contact
#   5. presence and activity: set on OrientOS, seen by a friend on the
#      server; an app needs a grant; privacy.set is critical and keeps
#      the activity on the device; invisible hides everything
#   6. events: a friend coming online on the server reaches the bus
#   7. the audit log names the calls
#   8. the friends bar /bin/freunde (wlib/fUi) in a guest with the window
#      server reads the service over the bus: who plays first, a picture
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }
fin() { echo "SOCIAL: $pass passed, $fail failed"; exit $(( fail > 0 )); }

TMPD=$(mktemp -d)
SRV=""
[ -n "${SOCIAL_KEEP:-}" ] || trap 'rm -rf "$TMPD"; [ -n "$SRV" ] && kill $SRV 2>/dev/null' EXIT
[ -z "${SOCIAL_KEEP:-}" ] || trap '[ -n "$SRV" ] && kill $SRV 2>/dev/null; echo "kept $TMPD"' EXIT
BLOCKS=30000
PROGS="sh ls cat echo sleep mkdir orientbus act social soclocal freunde desktop taskbar"
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
FLEIKONTAKTE=${FLEIKONTAKTE:-/root/jarvis/projects/u_DiS4in7esMF1/firnchat/bin/fleikontakte}

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
[ -x vendor/firn/bin/firnc ] || { echo "SOCIAL: firnc0 missing"; exit 1; }
mkdir -p "$TMPD/bin"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then
    ok "firnc0 builds $(echo $PROGS | wc -w) programs"
else
    bad "the programs do not build"; sed 's/^/        /' "$TMPD/b.txt" | head -20; fin
fi
if vendor/firn/bin/firnc -c --profile=app -o "$TMPD/socfleitec.o" \
        kernel/app/socfleitec.fi > "$TMPD/sf.txt" 2>&1 \
    && ld -T kernel/user/user.ld -o "$TMPD/bin/socfleitec.elf" "$TMPD/socfleitec.o" 2>> "$TMPD/sf.txt"; then
    strip --strip-all "$TMPD/bin/socfleitec.elf"
    ok "the fleitec provider builds (--profile=app, knetz + kjson)"
else
    bad "socfleitec does not build"; head -12 "$TMPD/sf.txt" | sed 's/^/        /'; fin
fi
note "social $(stat -c%s "$TMPD/bin/social.elf") B, socfleitec $(stat -c%s "$TMPD/bin/socfleitec.elf") B, soclocal $(stat -c%s "$TMPD/bin/soclocal.elf") B"
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then
    ok "the kernel builds"
else
    bad "the kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'; fin
fi
python3 tools/actionbus/manifest.py check pakete/social/ACTIONS > "$TMPD/lint.txt" 2>&1 \
    && ok "host reader: $(head -1 "$TMPD/lint.txt")" \
    || bad "host reader refuses pakete/social/ACTIONS: $(cat "$TMPD/lint.txt")"

command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "SOCIAL: skipped, qemu missing"; fin; }
[ -x "$FLEIKONTAKTE" ] || { bad "no fleikontakte at $FLEIKONTAKTE (FirnChat: bash build.sh)"; fin; }

# ------------------------------------------------ the host: fleikontakte
python3 -c "import secrets; print(secrets.token_hex(32))" > "$TMPD/jarvis.secret"
cat > "$TMPD/anbieter.conf" <<EOF
[jarvis]
typ = jwt
cookie = fleitec_session
geheimnis = $TMPD/jarvis.secret
auto-konto = ja
EOF
mkdir -p "$TMPD/web"
"$FLEIKONTAKTE" --port 0 --daten "$TMPD/daten" --anbieter-conf "$TMPD/anbieter.conf" \
    --web-dir "$TMPD/web" > "$TMPD/srv.out" 2> "$TMPD/srv.err" &
SRV=$!
PORT=""
for _ in $(seq 1 50); do
    PORT=$(sed -n 's/^FLEIKONTAKTE listening \([0-9]*\)$/\1/p' "$TMPD/srv.out")
    [ -n "$PORT" ] && break
    sleep 0.1
done
[ -n "$PORT" ] && ok "fleikontakte runs on the host (port $PORT)" || { bad "fleikontakte did not start"; fin; }
SECRET=$(cat "$TMPD/jarvis.secret")
TOKEN=$(python3 tools/social/host.py setup "$PORT" "$SECRET")
case "$TOKEN" in fkz1.u_JUSTIN.*) ok "justin's device access token made on the host (fkz1)";;
    *) bad "no device access token: '$TOKEN'"; fin;; esac

mkdir -p "$TMPD/etc"
printf 'lang=de\n' > "$TMPD/etc/locale.conf"
printf 'provider fleitec /bin/socfleitec\nprovider local /bin/soclocal\n' > "$TMPD/etc/providers"
printf 'url=http://10.0.2.2:%s\ntoken=%s\n' "$PORT" "$TOKEN" > "$TMPD/etc/fleitec.conf"
printf 'c\toma\tincoming\tunknown\tOma Rosi\t\t\t\t0\t\nc\tpeter\tfriend\tonline\tPeter (LAN)\tpeter\tim Keller\tMinecraft\t60\t\n' \
    > "$TMPD/etc/local.book"

cat > "$TMPD/s1.sh" <<'EOS'
orientbus serve 90000 &
sleep -m 300
social serve 90000 300 &
act watch 90000 > /tmp/events.txt &
sleep 4
echo ==LIST==
act list social.
echo ==STATUS==
act call social.status
echo ==ALL==
act call social.contacts.list
echo ==ONLINE==
act call social.contacts.list filter=online
echo ==ACTIVE==
act call social.contacts.list filter=active
echo ==GET==
act call social.contacts.get id=fleitec:u_ANNA
echo ==SEARCH==
act call social.contacts.search query=dora
echo ==AGENT==
act call social.contacts.accept id=fleitec:u_CARLA --as jarvis
echo rc=$?
act reject last
echo ==ACCEPT==
act call social.contacts.accept id=fleitec:u_CARLA
echo rc=$?
echo ==DRY==
act call social.contacts.remove id=fleitec:u_BERT --dry
echo rc=$?
echo ==WITHDRAW==
act call social.contacts.withdraw id=fleitec:u_DORA
echo rc=$?
act call social.contacts.get id=fleitec:u_DORA
echo ==REQUNDO==
act call social.contacts.request id=local:oma
echo rc=$?
act undo
echo rc=$?
act call social.contacts.get id=local:oma
echo ==LOCAL==
act call social.contacts.accept id=local:oma
echo rc=$?
act call social.contacts.get id=local:oma
echo ==NOSUCH==
act call social.contacts.accept id=matrix:x
echo rc=$?
echo ==PRESENCE==
act call social.presence.set state=dnd "text=Im Spiel"
echo rc=$?
echo ==GAME==
act call social.activity.set "name=Counter-Strike 2" --as app:game
echo rc=$?
act reject last
act grant app:game social.activity.* write 120
act call social.activity.set "name=Counter-Strike 2" --as app:game
echo rc=$?
act call social.activity.clear --as app:other
echo rc=$?
act confirm last
echo rc=$?
echo ==CHECK1==
sleep 3
echo ==PRIVACY==
act call social.privacy.set share_activity=false
echo rc=$?
act confirm last
echo rc=$?
act call social.activity.set "name=Secret Game"
echo rc=$?
echo ==BERTON==
sleep 9
act call social.contacts.list filter=online
echo ==INVISIBLE==
act call social.presence.set state=invisible
echo rc=$?
echo ==CHECK2==
sleep 3
echo ==ME==
cat /tmp/social/local.me
echo ==PRIVFILE==
cat /etc/social/privacy
echo ==EVENTS==
cat /tmp/events.txt
echo ==LOG==
cat /var/log/orientbus.log
act stop
sleep 1
echo ==FERTIG==
EOS

A_=(build "$TMPD/A.img" $BLOCKS /lib/
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/
    /etc/actions.d/ /etc/orientbus/ /etc/social/ /apps/ /apps/social.prog/ /var/ /var/log/
    /usr/ /usr/share/ /usr/share/locale/ /usr/share/locale/de/ /usr/share/locale/en/
    "/usr/share/locale/de/messages=locale/de/messages" "/usr/share/locale/en/messages=locale/en/messages"
    "/etc/locale.conf=$TMPD/etc/locale.conf")
for p in $PROGS socfleitec; do A_+=("/bin/$p=$TMPD/bin/$p.elf"); done
A_+=("/apps/social.prog/ACTIONS=pakete/social/ACTIONS"
     "/etc/social/providers=$TMPD/etc/providers"
     "/etc/social/fleitec.conf=$TMPD/etc/fleitec.conf"
     "/etc/social/local.book=$TMPD/etc/local.book"
     "/t/s.sh=$TMPD/s1.sh")
python3 tools/osum/mkfs.py "${A_[@]}" > "$TMPD/mkfs.txt" 2>&1 || { bad "mkfs: $(tail -2 "$TMPD/mkfs.txt")"; fin; }

: > "$TMPD/a.txt"
if [ -n "${SOCIAL_ONLY_BAR:-}" ]; then echo "(SOCIAL_ONLY_BAR: main guest skipped)"; else
python3 tools/social/host.py watch "$PORT" "$SECRET" "$TMPD/a.txt" "$TMPD/host.txt" &
WATCH=$!
T0=$(date +%s)
timeout 240 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 \
    -kernel "$TMPD/k0.img" -m 512 \
    -append "osum vfs nokbd bus nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0 script=sh /t/s.sh;exit" \
    -serial "file:$TMPD/a.txt" -display none -no-reboot \
    -drive "file=$TMPD/A.img,format=raw,if=ide,index=0" \
    -netdev user,id=n0 -device e1000,netdev=n0,mac=52:54:00:0a:0b:0d \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
T1=$(date +%s)
wait $WATCH 2>/dev/null
tr -cd '\11\12\15\40-\176' < "$TMPD/a.txt" > "$TMPD/a.klar"
A="$TMPD/a.klar"
note "guest run: $((T1-T0)) s, accel=$OSUM_QEMU_ACCEL"
grep -qa '==FERTIG==' "$A" || { bad "the guest script did not reach its end"; tail -30 "$A" | sed 's/^/        /'; }

echo "== 2. the catalogue =="
part "$A" LIST STATUS > "$TMPD/p.txt"
n_act=$(grep -ac '^social\.' "$TMPD/p.txt")
n_evt=$(grep -ac '^event social\.' "$TMPD/p.txt")
[ "$n_act" = 14 ] && [ "$n_evt" = 3 ] && ok "the catalogue has 14 social.* actions and 3 events" \
    || { bad "catalogue: $n_act actions, $n_evt events"; head -20 "$TMPD/p.txt" | sed 's/^/        /'; }
has "$TMPD/p.txt" "social.privacy.set critical" "privacy.set is critical"
hasnot "$TMPD/p.txt" "(not running)" "the service is bound (not 'not running')"
has "$A" "social: serving a.social, providers=2" "the service reads both providers from /etc/social/providers"

echo "== 3. the book =="
part "$A" STATUS ALL > "$TMPD/p.txt"
has "$TMPD/p.txt" "provider.1=fleitec ok 4" "fleitec: ok, 4 contacts (anna, bert, carla, dora) over the guest's network"
has "$TMPD/p.txt" "provider.2=local ok 2" "local: ok, 2 contacts"
has "$TMPD/p.txt" "contacts=6" "the merged book has 6"
has "$TMPD/p.txt" "online=2" "2 friends online (anna, peter)"
has "$TMPD/p.txt" "active=2" "2 friends active (anna plays, peter plays)"
part "$A" ALL ONLINE > "$TMPD/p.txt"
has "$TMPD/p.txt" "total=6" "list: 6 contacts"
has "$TMPD/p.txt" "fleitec:u_ANNA|friend|online|Anna Berger|anna_berger||Counter-Strike 2|" "anna: friend, online, plays Counter-Strike 2"
has "$TMPD/p.txt" "fleitec:u_CARLA|incoming|" "carla asks justin (incoming)"
has "$TMPD/p.txt" "fleitec:u_DORA|outgoing|" "justin asked dora (outgoing)"
has "$TMPD/p.txt" "local:peter|friend|online|Peter (LAN)|peter|im Keller|Minecraft|" "a contact of the local provider in the same book"
part "$A" ONLINE ACTIVE > "$TMPD/p.txt"
has "$TMPD/p.txt" "total=2" "filter=online: 2"
hasnot "$TMPD/p.txt" "u_BERT" "bert (invisible) is not online"
part "$A" GET SEARCH > "$TMPD/p.txt"
has "$TMPD/p.txt" "activity=Counter-Strike 2" "get: one contact with every field"
has "$TMPD/p.txt" "provider=fleitec" "get: its provider"
part "$A" SEARCH AGENT > "$TMPD/p.txt"
has "$TMPD/p.txt" "fleitec:u_DORA|" "search at the providers finds dora"

echo "== 4. relations =="
part "$A" AGENT ACCEPT > "$TMPD/p.txt"
has "$TMPD/p.txt" "confirm " "an agent accepting a friend request is parked for the user"
has "$TMPD/p.txt" "rc=2" "... exit code 2"
part "$A" ACCEPT DRY > "$TMPD/p.txt"
has "$TMPD/p.txt" "relation=friend" "the user accepts carla: friend"
part "$A" DRY WITHDRAW > "$TMPD/p.txt"
has "$TMPD/p.txt" "would=remove fleitec:u_BERT" "dry run says what it would do"
part "$A" WITHDRAW REQUNDO > "$TMPD/p.txt"
has "$TMPD/p.txt" "relation=none" "the request to dora is withdrawn"
part "$A" REQUNDO LOCAL > "$TMPD/p.txt"
has "$TMPD/p.txt" "relation=outgoing" "request at the local provider: outgoing"
grep -aq "^relation=none" "$TMPD/p.txt" && ok "undo runs the manifest's inverse (withdraw): none again" \
    || bad "undo of a request did not withdraw it"
part "$A" LOCAL NOSUCH > "$TMPD/p.txt"
has "$TMPD/p.txt" "relation=friend" "accept at the local provider: friend"
part "$A" NOSUCH PRESENCE > "$TMPD/p.txt"
has "$TMPD/p.txt" "err no_such_contact" "an unknown provider in the id is refused"

echo "== 5. presence and activity =="
part "$A" PRESENCE GAME > "$TMPD/p.txt"
has "$TMPD/p.txt" "presence=dnd" "presence set to dnd"
part "$A" GAME CHECK1 > "$TMPD/p.txt"
has "$TMPD/p.txt" "confirm " "an app setting an activity without a grant is parked"
has "$TMPD/p.txt" "shared=true" "with the user's grant the game's activity goes out"
has "$TMPD/p.txt" "confirm 3 social.activity.clear" "another app clearing it is parked (no grant)"
has "$TMPD/p.txt" "err denied not_your_activity" "... and even with the user's yes the service refuses: not its activity"
part "$A" PRIVACY BERTON > "$TMPD/p.txt"
n_c=$(grep -ac '^confirm [0-9]* social.privacy.set' "$TMPD/p.txt")
[ "$n_c" = 1 ] && ok "privacy.set is asked even for the user (critical)" || bad "privacy.set: $n_c confirmations"
has "$TMPD/p.txt" "share_activity=false" "confirmed: activity stays on the device"
has "$TMPD/p.txt" "shared=false" "an activity set now is not shared"
part "$A" PRIVFILE EVENTS > "$TMPD/p.txt"
has "$TMPD/p.txt" "share_activity=false" "the switch is kept in /etc/social/privacy"
part "$A" ME PRIVFILE > "$TMPD/p.txt"
has "$TMPD/p.txt" "presence dnd Im Spiel" "the local provider got the presence too (all providers)"
has "$TMPD/p.txt" "activity Counter-Strike 2" "... and the game"
hasnot "$TMPD/p.txt" "Secret Game" "the activity set after 'share_activity=false' reached no provider"
has "$TMPD/p.txt" "presence invisible" "invisible reached the providers"
while IFS= read -r l; do
    case "$l" in OK*) ok "${l#OK    }";; FAIL*) bad "${l#FAIL  }";; esac
done < "$TMPD/host.txt"
n_host=$(grep -c . "$TMPD/host.txt" 2>/dev/null || echo 0)
[ "$n_host" = 5 ] && ok "the host checked at both markers (5 checks)" || bad "host checks: $n_host of 5 ran"

echo "== 6. events =="
part "$A" BERTON INVISIBLE > "$TMPD/p.txt"
has "$TMPD/p.txt" "fleitec:u_BERT|friend|online" "bert came online on the server: the next book has him online"
part "$A" EVENTS LOG > "$TMPD/p.txt"
has "$TMPD/p.txt" "social.presence" "an event social.presence went out on the bus"
grep -aq "id=fleitec:u_BERT" "$TMPD/p.txt" && ok "... for bert" || bad "no event for bert"
grep -aq "id=fleitec:u_CARLA" "$TMPD/p.txt" && ok "social.contact for carla (the new friendship)" || bad "no social.contact for carla"

echo "== 7. the log =="
part "$A" LOG FERTIG > "$TMPD/p.txt"
has "$TMPD/p.txt" "action=social.contacts.accept" "the audit log names the relation calls"
has "$TMPD/p.txt" "action=social.privacy.set" "... and the privacy switch"
has "$TMPD/p.txt" "client=app:game" "... and which app set the activity"
fi

echo "== 8. the friends bar =="
cat > "$TMPD/s2.sh" <<'EOS'
orientbus serve 6000 &
sleep -m 300
social serve 6000 300 &
sleep 3
freunde --rahmen 900
EOS
A2_=(); for x in "${A_[@]}"; do A2_+=("${x/$TMPD\/A.img/$TMPD/B.img}"); done
A3_=(); for x in "${A2_[@]}"; do A3_+=("${x/s1.sh/s2.sh}"); done
python3 tools/osum/mkfs.py "${A3_[@]}" > "$TMPD/mkfs2.txt" 2>&1 || bad "mkfs (bar): $(tail -2 "$TMPD/mkfs2.txt")"
mkdir -p docs/shots/social
rm -f "$TMPD/mon"
timeout 120 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 \
    -kernel "$TMPD/k0.img" -m 512 -vga std \
    -append "osum vfs bus gfx wm wig desk wmhold wiglong wmdauer nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0 wigapp=/bin/sh,/t/s.sh wighalt=40 r3alle nokbd" \
    -serial "file:$TMPD/b.txt" -display none -no-reboot \
    -drive "file=$TMPD/B.img,format=raw,if=ide,index=0" \
    -netdev user,id=n1 -device e1000,netdev=n1,mac=52:54:00:0a:0b:0e \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -monitor "unix:$TMPD/mon,server,nowait" >/dev/null 2>&1 &
QB=$!
w=0
while [ $w -lt 90 ] && ! grep -qa 'quelle=bus' "$TMPD/b.txt" 2>/dev/null; do sleep 1; w=$((w+1)); done
sleep 6
if [ -S "$TMPD/mon" ] && command -v socat >/dev/null 2>&1; then
    printf 'screendump %s\n' "$TMPD/bar.ppm" | timeout 10 socat - "unix-connect:$TMPD/mon" >/dev/null 2>&1 || true
    sleep 1
fi
kill -9 "$QB" 2>/dev/null; wait "$QB" 2>/dev/null
tr -cd '\11\12\15\40-\176' < "$TMPD/b.txt" > "$TMPD/b.klar"
B="$TMPD/b.klar"
has "$B" "quelle=bus" "the bar found orient-bus and the social service"
EIN=$(grep -a 'freunde: eintraege=' "$B" | head -1 | sed 's/.*eintraege=\([0-9]*\).*/\1/')
# as many as justin has friends at fleikontakte right now, plus peter on the device
WANT=$(python3 - "$PORT" "$SECRET" <<'PY'
import sys; sys.path.insert(0, 'tools/social'); import host
st, j = host.api(int(sys.argv[1]), host.people(sys.argv[2])["justin"], "/api/kontakte/liste")
print(1 + sum(1 for i in j.get("items", []) if i.get("status") == "freunde"))
PY
)
[ "${EIN:-x}" = "$WANT" ] && ok "the bar shows justin's $WANT friends (fleitec + the device's own), from the service" \
    || { bad "the bar shows ${EIN:-no} entries instead of $WANT"; grep -a "freunde:\|social:" "$B" | head -5 | sed 's/^/        /'; }
if [ -f "$TMPD/bar.ppm" ]; then
    python3 -c "from PIL import Image; Image.open('$TMPD/bar.ppm').save('docs/shots/social/freunde.png')" 2>/dev/null \
        && ok "a picture of the bar: docs/shots/social/freunde.png" || bad "the picture could not be converted"
else
    note "no picture (socat/monitor missing) -- not a failure of this round"
fi
fin
