#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/social/sdk.sh -- THE SOCIAL SDK FOR APPS AND GAMES (r29): setActivity with a party, invite, join.
#
#   bash tools/social/sdk.sh
#
#   1. build
#   2. host: the C header and the JS shim against a fake `act` (the exact command lines)
#   3. guest: the Firn module (socapp) against the real broker, social and soclocal
#      party -> default target of an invite and of an answer to a join request,
#      social.party.take once per accepted invite / join, scopes of apps
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasre() { grep -qaE -- "$2" "$1" && ok "$3" || bad "$3 -- /$2/ missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }
fin() { echo "SOCIAL-SDK: $pass passed, $fail failed"; exit $(( fail > 0 )); }

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
BLOCKS=30000
PROGS="sh ls cat echo sleep mkdir orientbus act social soclocal socapp partyrun"
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
[ -x vendor/firn/bin/firnc ] || { echo "SOCIAL-SDK: firnc0 missing"; exit 1; }
mkdir -p "$TMPD/bin"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then
    ok "firnc0 builds $(echo $PROGS | wc -w) programs (socapp uses kernel/user/socsdk.fi)"
else
    bad "the programs do not build"; sed 's/^/        /' "$TMPD/b.txt" | head -20; fin
fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then
    ok "the kernel builds"
else
    bad "the kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'; fin
fi
python3 tools/actionbus/manifest.py check pakete/social/ACTIONS > "$TMPD/lint.txt" 2>&1 \
    && ok "host reader: $(head -1 "$TMPD/lint.txt")" \
    || bad "host reader refuses pakete/social/ACTIONS: $(cat "$TMPD/lint.txt")"
[ "$(wc -c < pakete/social/ACTIONS)" -lt 16383 ] && ok "the manifest fits the broker's read buffer (16383 octets)" || bad "pakete/social/ACTIONS is over 16383 octets (the broker rejects it)"
has pakete/social/ACTIONS "action social.party.take" "ACTIONS declares social.party.take"
has pakete/social/ACTIONS "arg party string optional" "ACTIONS declares the party argument of social.activity.set"

echo "== 2. host: C header and JS shim =="
FAKE="$(pwd)/tools/social/sdk/fake_act.sh"
cat > "$TMPD/expect.log" <<'EOL'
call social.activity.set name=Minecraft join=true party=mc://h:1
call social.activity.set name=Pong join=true
call social.activity.set name=Solo
call social.activity.clear
call social.invites.send id=local:peter kind=invite name=Chess
call social.invites.send id=local:peter kind=invite
call social.invites.send id=local:peter kind=join
call social.party.take name=Chess
call social.party.take
EOL
for cc in gcc musl-gcc; do
    command -v "$cc" >/dev/null 2>&1 || { note "$cc missing, skipped"; continue; }
    if "$cc" -std=c99 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror -Isdk/social \
        -o "$TMPD/t_$cc" tools/social/sdk/test_sdk.c 2> "$TMPD/cc.txt"; then
        ok "$cc: sdk/social/orient_social.h compiles clean (-Wall -Wextra -Werror)"
    else
        bad "$cc: the header does not compile: $(head -3 "$TMPD/cc.txt")"; continue
    fi
    : > "$TMPD/c_$cc.log"
    ORIENT_ACT="$FAKE" FAKE_ACT_LOG="$TMPD/c_$cc.log" "$TMPD/t_$cc" > "$TMPD/c_$cc.out" 2>&1
    has "$TMPD/c_$cc.out" "c-ok" "$cc: every call of the C test passes (bad input refused, take_join finds the target)"
    cmp -s "$TMPD/c_$cc.log" "$TMPD/expect.log" \
        && ok "$cc: the command lines to act are exactly the expected nine" \
        || { bad "$cc: command lines differ"; diff "$TMPD/expect.log" "$TMPD/c_$cc.log" | head -6 | sed 's/^/        /'; }
done
if command -v node >/dev/null 2>&1; then
    : > "$TMPD/j.log"
    ORIENT_ACT="$FAKE" FAKE_ACT_LOG="$TMPD/j.log" node tools/social/sdk/test_sdk.mjs > "$TMPD/j.out" 2>&1
    has "$TMPD/j.out" "js-ok" "js shim: every call of the JS test passes (bad input refused, injected transport, failure -> false/null)"
    cmp -s "$TMPD/j.log" "$TMPD/expect.log" \
        && ok "js shim: the command lines to act are the same as the C header's" \
        || { bad "js shim: command lines differ"; diff "$TMPD/expect.log" "$TMPD/j.log" | head -6 | sed 's/^/        /'; }
else
    note "node missing, JS shim skipped"
fi
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "SOCIAL-SDK: skipped, qemu missing"; fin; }

mkdir -p "$TMPD/etc"
printf 'lang=de\n' > "$TMPD/etc/locale.conf"
printf 'provider local /bin/soclocal\n' > "$TMPD/etc/providers"
printf 'c\toma\tincoming\tunknown\tOma Rosi\t\t\t\t0\t\nc\tpeter\tfriend\tonline\tPeter (LAN)\tpeter\tim Keller\t\t0\t\n' > "$TMPD/etc/local.book"
{
    printf 'i\tlinv10\tpeter\tin\tinvite\taccepted\t0\tgame://lobby/77\tChess\n'
    printf 'i\tlinv11\tpeter\tout\tjoin\taccepted\t0\tgame://lobby/88\tMinecraft\n'
    printf 'i\tlinv12\tpeter\tin\tinvite\taccepted\t0\t-\tDull\n'
    printf 'i\tlinv13\tpeter\tin\tinvite\topen\t0\tgame://lobby/99\tOpen\n'
    printf 'i\tlinv20\tpeter\tin\tjoin\topen\t0\t-\tMinecraft\n'
    printf 'i\tlinv21\tpeter\tin\tjoin\topen\t0\t-\tMinecraft\n'
    printf 'i\tlinv30\tpeter\tin\tinvite\topen\t0\tgame://lobby/echo\tEchoGame\n'
    printf 'i\tlinv31\tpeter\tin\tinvite\topen\t0\tgame://lobby/busy\tBusyGame\n'
} > "$TMPD/etc/local.invites"
printf 'l\techo\tEchoGame\nl\tsleep\tBusyGame\nl\tnap\tQuietGame\nl\techo\tOpen\nw\techo\tWinGame\n' > "$TMPD/etc/games.tsv"
printf 'app:game activity.write\napp:reader contacts.read\napp:talker messages.send invites.send\n' > "$TMPD/etc/apps"

cat > "$TMPD/s.sh" <<'EOS'
orientbus serve 30000 &
sleep -m 300
social serve 30000 300 60000 &
sleep 4
act grant app:game social.* write 600
act grant app:reader social.* write 600
act grant app:talker social.* write 600
act grant app:none social.* write 600
echo ==LIST==
act call social.invites.list
echo ==TAKE1==
socapp take Chess
echo ==TAKE2==
socapp take Chess
echo ==TAKE3==
socapp take Open
echo ==DRY==
act call social.party.take name=Minecraft --dry
echo ==TAKE4==
socapp take Minecraft
echo ==TAKE5==
socapp take
echo ==PLAY==
socapp play Minecraft mc://10.0.2.15:25565
sleep 2
cat /tmp/social/local.me
socapp invite local:peter
act call social.invites.list
echo ==ANSWER==
act call social.invites.answer id=local:linv20 accept=true
echo ==SOLO==
socapp play Solo
socapp invite local:peter Solo
act call social.invites.list
echo ==STOP==
socapp play Minecraft mc://10.0.2.15:25565
socapp stop
act call social.invites.answer id=local:linv21 accept=true
echo ==SCOPES==
act call social.party.take --as app:game
act call social.party.take --as app:reader
act call social.party.take --as app:talker
act call social.party.take --as app:none
act call social.activity.set name=Pong party=pong://1 --as app:game
act call social.invites.send id=local:peter kind=invite name=Pong --as app:talker
act call social.invites.list
act call social.activity.clear --as app:reader
act call social.activity.clear --as app:talker
act call social.activity.clear --as app:game
act call social.invites.send id=local:peter kind=invite name=Pong2 --as app:talker
act call social.invites.list
echo ==LAUNCH==
act call social.invites.answer id=local:linv30 accept=true
act call social.invites.answer id=local:linv31 accept=true
sleep 15 &
partyrun once
sleep 1
echo ==LAUNCH2==
partyrun once
echo ==BUSY==
socapp take BusyGame
echo ==WATCH==
partyrun watch 12 &
sleep 2
act call social.invites.answer id=local:linv13 accept=true
sleep 5
echo ==WATCHEND==
partyrun watch 2
echo ==LAUNCHEND==
act stop
sleep 1
echo ==FERTIG==
EOS

S_=(build "$TMPD/C.img" $BLOCKS /lib/
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/
    /etc/actions.d/ /etc/orientbus/ /etc/social/ /apps/ /apps/social.prog/ /var/ /var/log/
    /usr/ /usr/share/ /usr/share/locale/ /usr/share/locale/de/ /usr/share/locale/en/
    "/etc/locale.conf=$TMPD/etc/locale.conf")
for p in $PROGS; do S_+=("/bin/$p=$TMPD/bin/$p.elf"); done
S_+=("/apps/social.prog/ACTIONS=pakete/social/ACTIONS"
     "/etc/social/providers=$TMPD/etc/providers"
     "/etc/social/local.book=$TMPD/etc/local.book"
     "/etc/social/local.invites=$TMPD/etc/local.invites"
     "/etc/social/apps=$TMPD/etc/apps"
     "/etc/social/games.tsv=$TMPD/etc/games.tsv"
     "/t/s.sh=$TMPD/s.sh")
python3 tools/osum/mkfs.py "${S_[@]}" > "$TMPD/mkfs.txt" 2>&1 || { bad "mkfs: $(tail -2 "$TMPD/mkfs.txt")"; fin; }
: > "$TMPD/c.txt"
timeout 200 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 \
    -kernel "$TMPD/k0.img" -m 512 \
    -append "osum vfs nokbd bus script=sh /t/s.sh;exit" \
    -serial "file:$TMPD/c.txt" -display none -no-reboot \
    -drive "file=$TMPD/C.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$TMPD/c.txt" > "$TMPD/c.klar"
C="$TMPD/c.klar"
[ -z "${SDK_OUT:-}" ] || cp "$C" "$SDK_OUT"
has "$C" "==FERTIG==" "the guest script reached its end"

echo "== 3. accepted invites and joins, taken once =="
part "$C" LIST TAKE1 > "$TMPD/p.txt"
has "$TMPD/p.txt" "game://lobby/77" "the planted accepted invite is in the list"
part "$C" TAKE1 TAKE2 > "$TMPD/p.txt"
has "$TMPD/p.txt" "target=game://lobby/77" "take_join(Chess): the target of an accepted incoming invite"
part "$C" TAKE2 TAKE3 > "$TMPD/p.txt"
has "$TMPD/p.txt" "target=none" "... and the same invite is not handed out twice"
part "$C" TAKE3 DRY > "$TMPD/p.txt"
has "$TMPD/p.txt" "target=none" "an invite still open has no target to take"
part "$C" DRY TAKE4 > "$TMPD/p.txt"
has "$TMPD/p.txt" "would=take" "social.party.take --dry says what it would take"
part "$C" TAKE4 TAKE5 > "$TMPD/p.txt"
has "$TMPD/p.txt" "target=game://lobby/88" "take_join(Minecraft): the target of an accepted join request (dry run did not use it up)"
part "$C" TAKE5 PLAY > "$TMPD/p.txt"
has "$TMPD/p.txt" "target=none" "nothing else waits (a target '-' is none)"

echo "== 4. party: the default target =="
part "$C" PLAY ANSWER > "$TMPD/p.txt"
has "$TMPD/p.txt" "ok" "socapp play <name> <party> answers ok"
hasre "$TMPD/p.txt" "\|out\|invite\|open\|[0-9]+\|mc://10.0.2.15:25565\|Minecraft" "an invite without a target carries my party"
part "$C" ANSWER SOLO > "$TMPD/p.txt"
has "$TMPD/p.txt" "state=accepted" "answering a join request: accepted"
has "$TMPD/p.txt" "target=mc://10.0.2.15:25565" "... without a target hands out my party"
part "$C" SOLO STOP > "$TMPD/p.txt"
hasre "$TMPD/p.txt" "\|[0-9]+\|\|Solo" "an activity without a party: the invite has no target"
part "$C" STOP SCOPES > "$TMPD/p.txt"
has "$TMPD/p.txt" "state=accepted" "answering after the activity was cleared: accepted"
hasnot "$TMPD/p.txt" "target=mc://" "... and the cleared party is no longer handed out"

echo "== 5. scopes =="
part "$C" SCOPES LAUNCH > "$TMPD/p.txt"
has "$TMPD/p.txt" "found=false" "activity.write: social.party.take works for app:game"
has "$TMPD/p.txt" "err denied scope activity.write" "contacts.read only: social.party.take is refused"
hasre "$TMPD/p.txt" "\|pong://1\|Pong" "app:game's party is the default target of app:talker's invite"
hasre "$TMPD/p.txt" "\|[0-9]+\|\|Pong2" "after app:game cleared its activity the party is gone"
[ "$(grep -ac 'err denied scope activity.write' "$TMPD/p.txt")" -ge 5 ] \
    && ok "take (reader, talker, none) and clear (reader, talker) are denied without activity.write" \
    || bad "expected five scope denials, got $(grep -ac 'err denied scope activity.write' "$TMPD/p.txt")"

echo "== 6. launcher: Beitreten starts the game with the target =="
part "$C" LAUNCH LAUNCH2 > "$TMPD/p.txt"
has "$TMPD/p.txt" "partyrun: start /bin/echo target=game://lobby/echo" "partyrun once: a game that is not running and has an accepted invite is started with its target"
has "$TMPD/p.txt" "--join game://lobby/echo" "... the game gets --join <target> as its arguments"
has "$TMPD/p.txt" "started=1" "... exactly one game started (QuietGame has nothing waiting, BusyGame is running, WinGame is not an os l row)"
hasnot "$TMPD/p.txt" "start /bin/sleep" "a game that already runs is left alone"
part "$C" LAUNCH2 BUSY > "$TMPD/p.txt"
has "$TMPD/p.txt" "started=0" "the same invite is not launched twice"
part "$C" BUSY WATCH > "$TMPD/p.txt"
has "$TMPD/p.txt" "target=game://lobby/busy" "the running game still takes its own target (the launcher did not use it up)"
part "$C" WATCH WATCHEND > "$TMPD/p.txt"
has "$TMPD/p.txt" "partyrun: start /bin/echo target=game://lobby/99" "partyrun watch: waits, the answer yes arrives, the game starts with the target"
has "$TMPD/p.txt" "started=1" "... and the watcher ends after the launch"
part "$C" WATCHEND LAUNCHEND > "$TMPD/p.txt"
has "$TMPD/p.txt" "started=0" "partyrun watch without a waiting target ends with started=0 after its time"
fin
