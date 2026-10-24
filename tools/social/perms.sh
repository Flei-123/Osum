#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/social/perms.sh -- RIGHTS PER APP AND PRIVACY SWITCHES OF THE SOCIAL SERVICE (r30).
#
#   bash tools/social/perms.sh
#
# A real Osum guest under QEMU with the broker, /bin/social and one local
# provider (no network, no fleikontakte). Clients are claimed with `--as`.
#
#   1. build
#   2. start: /etc/social/apps and /etc/social/privacy are read at boot
#   3. an app with one scope: contacts.read / activity.write / messages.send / invites.send
#   4. everything else is for the user: user_only, critical grants are parked
#   5. grant and revoke by the user (critical, asked), the table on disk
#   6. never show: by client and by activity name, switched back on
#   7. who may invite me: friends / none / all, filtered before the bell
#   8. the calls of the Settings pages (allow/deny/show with one text) and contacts.search as a group job (r341)
set -uo pipefail
cd "$(dirname "$0")/../.."
T=$'\t'
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }
fin() { echo "SOCIAL-PERMS: $pass passed, $fail failed"; exit $(( fail > 0 )); }

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
BLOCKS=30000
PROGS="sh ls cat echo sleep mkdir orientbus act social soclocal"
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
[ -x vendor/firn/bin/firnc ] || { echo "SOCIAL-PERMS: firnc0 missing"; exit 1; }
mkdir -p "$TMPD/bin"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then
    ok "firnc0 builds $(echo $PROGS | wc -w) programs"
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
[ "$(wc -c < pakete/social/ACTIONS)" -gt 8191 ] && ok "the manifest is over the old 8191 octets: the larger buffer is in use" || bad "the manifest is back under the old 8191 octets"
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "SOCIAL-PERMS: skipped, qemu missing"; fin; }

mkdir -p "$TMPD/etc"
printf 'lang=de\n' > "$TMPD/etc/locale.conf"
printf 'provider local /bin/soclocal\n' > "$TMPD/etc/providers"
printf 'c\toma\tincoming\tunknown\tOma Rosi\t\t\t\t0\t\nc\tpeter\tfriend\tonline\tPeter (LAN)\tpeter\tim Keller\t\t0\t\n' > "$TMPD/etc/local.book"
printf 'i\tlinv1\tpeter\tin\tinvite\topen\t0\t\tMinecraft\ni\tlinv2\toma\tin\tinvite\topen\t0\t\tChess\n' > "$TMPD/etc/local.invites"
printf 'app:game activity.write\napp:reader contacts.read\napp:talker messages.send invites.send\n' > "$TMPD/etc/apps"
printf 'share_activity=true\ninvites=friends\nnever=app:seeded\n' > "$TMPD/etc/privacy"

cat > "$TMPD/s.sh" <<'EOS'
orientbus serve 30000 &
sleep -m 300
social serve 30000 300 60000 &
sleep 4
act grant app:game social.* write 600
act grant app:reader social.* write 600
act grant app:talker social.* write 600
act grant app:none social.* write 600
echo ==START==
act call social.privacy.get
act call social.apps.list
act call social.invites.list
echo ==READER==
act call social.contacts.list --as app:reader
act call social.activity.set "name=Reader Game" --as app:reader
act call social.messages.send id=local:peter text=hi --as app:reader
act call social.invites.send id=local:peter kind=invite name=Chess --as app:reader
echo ==GAME==
act call social.activity.set "name=Game On" --as app:game
sleep 2
cat /tmp/social/local.me
act call social.contacts.list --as app:game
act call social.presence.set state=dnd --as app:game
act call social.status --as app:game
echo ==USERONLY==
act call social.contacts.accept id=local:oma --as app:game
act call social.messages.list id=local:peter --as app:game
act call social.privacy.get --as app:game
act call social.apps.list --as app:game
act call social.accounts.list --as app:game
act call social.apps.grant client=app:game scope=contacts.read --as app:game
act reject last
act call social.apps.list
echo ==NONE==
act call social.contacts.list --as app:none
act call social.status --as app:none
echo ==TALKER==
act call social.messages.send id=local:peter text=hello --as app:talker
act call social.invites.send id=local:peter kind=invite name=Chess --as app:talker
act call social.contacts.list --as app:talker
echo ==GRANT==
act call social.apps.grant client=app:reader scope=activity.write
act confirm last
act call social.apps.grant client=app:reader scope=root
act confirm last
act call social.apps.grant client=user scope=activity.write
act confirm last
act call social.apps.list
act call social.activity.set "name=Reader Game" --as app:reader
echo ==FILE==
cat /etc/social/apps
echo ==HIDE==
act call social.privacy.hide entry=app:game
act confirm last
act call social.activity.set "name=Hidden Game" --as app:game
sleep 3
cat /tmp/social/local.me
echo ==H1==
act call social.privacy.hide "entry=Lost Woods"
act confirm last
act call social.activity.set "name=Lost Woods"
sleep 3
cat /tmp/social/local.me
echo ==H2==
act call social.privacy.hide "entry=Lost Woods" hide=false
act confirm last
act call social.activity.set "name=Lost Woods"
sleep 3
cat /tmp/social/local.me
echo ==PRIV==
act call social.privacy.get
cat /etc/social/privacy
echo ==REVOKE==
act call social.apps.revoke client=app:reader scope=activity.write
act confirm last
act call social.activity.set "name=Reader Game" --as app:reader
act call social.apps.revoke client=app:game
act confirm last
act call social.apps.list
act call social.activity.set "name=Game On" --as app:game
cat /etc/social/apps
echo ==INV0==
act call social.invites.list
echo ==INVALL==
act call social.privacy.invites from=all
act confirm last
sleep 3
act call social.invites.list
echo ==INVNONE==
act call social.privacy.invites from=none
act confirm last
sleep 3
act call social.invites.list
echo ==INVBAD==
act call social.privacy.invites from=everyone
act confirm last
echo ==INVFRIENDS==
act call social.privacy.invites from=friends
act confirm last
sleep 3
act call social.invites.list
act call social.status
cat /etc/social/privacy
echo ==PAGE==
act call social.apps.allow "allow=app:reader messages.send"
act confirm last
act call social.apps.list
act call social.apps.allow "allow=app:reader"
act confirm last
act call social.apps.allow "allow=user messages.send"
act confirm last
act call social.apps.deny "deny=app:reader messages.send"
act confirm last
act call social.apps.list
act call social.apps.deny "deny=app:reader"
act confirm last
act call social.apps.list
cat /etc/social/apps
echo ==PAGEHIDE==
act call social.privacy.hide "entry=Zelda"
act confirm last
act call social.privacy.get
act call social.privacy.show "show=Zelda"
act confirm last
act call social.privacy.show "show=app:seeded"
act confirm last
act call social.privacy.get
cat /etc/social/privacy
echo ==SEARCH==
act call social.contacts.search query=Pet
act call social.contacts.search query=Pet --as app:talker
act call social.contacts.search query=nobody-here
echo ==SEARCHEND==
echo ==LOG==
cat /var/log/orientbus.log
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
     "/etc/social/privacy=$TMPD/etc/privacy"
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
[ -z "${PERMS_OUT:-}" ] || cp "$C" "$PERMS_OUT"
has "$C" "==FERTIG==" "the guest script reached its end"

echo "== 2. start =="
part "$C" START READER > "$TMPD/p.txt"
has "$TMPD/p.txt" "share_activity=true" "privacy.get: share_activity read from /etc/social/privacy"
has "$TMPD/p.txt" "invites_from=friends" "... and who may invite"
has "$TMPD/p.txt" "hide.1=app:seeded" "... and the never list"
has "$TMPD/p.txt" "app.1=app:game|activity.write" "apps.list: the table of /etc/social/apps (game)"
has "$TMPD/p.txt" "app.2=app:reader|contacts.read" "... (reader)"
has "$TMPD/p.txt" "local:peter" "invites: the friend's invite is listed at boot (policy friends)"
hasnot "$TMPD/p.txt" "local:oma" "... the stranger's is not"

echo "== 3. one scope each =="
part "$C" READER GAME > "$TMPD/p.txt"
has "$TMPD/p.txt" "contact.1=local:" "contacts.read: the reader sees the book"
has "$TMPD/p.txt" "err denied scope activity.write" "the reader may not set an activity"
has "$TMPD/p.txt" "err denied scope messages.send" "the reader may not write messages"
has "$TMPD/p.txt" "err denied scope invites.send" "the reader may not invite"
part "$C" GAME USERONLY > "$TMPD/p.txt"
has "$TMPD/p.txt" "shared=true" "activity.write: the game's activity goes out"
has "$TMPD/p.txt" "activity Game On" "... to the provider"
has "$TMPD/p.txt" "err denied scope contacts.read" "the game may not read the book"
has "$TMPD/p.txt" "presence=" "activity.write covers the presence line (set ok)"
has "$TMPD/p.txt" "providers=1" "status is open to every app"

echo "== 4. the rest is for the user =="
part "$C" USERONLY NONE > "$TMPD/p.txt"
n_uo=$(grep -ac '^err denied user_only' "$TMPD/p.txt")
[ "$n_uo" = 5 ] && ok "relations, message list, privacy.get, apps.list, accounts.list: user_only for an app" || bad "user_only: $n_uo of 5"
has "$TMPD/p.txt" "confirm " "an app cannot grant itself rights: critical, parked for the user"
hasnot "$TMPD/p.txt" "app.1=app:game|activity.write,contacts.read" "... and nothing was granted"
part "$C" NONE TALKER > "$TMPD/p.txt"
has "$TMPD/p.txt" "err denied scope contacts.read" "an app without a table line has no right"
has "$TMPD/p.txt" "providers=1" "... only status"
part "$C" TALKER GRANT > "$TMPD/p.txt"
has "$TMPD/p.txt" "devices=" "messages.send: the talker writes"
has "$TMPD/p.txt" "invite=" "invites.send: the talker invites"
has "$TMPD/p.txt" "err denied scope contacts.read" "... but does not read the book"

echo "== 5. grant and revoke =="
part "$C" GRANT FILE > "$TMPD/p.txt"
has "$TMPD/p.txt" "app.2=app:reader|contacts.read,activity.write" "the user's grant adds the scope"
has "$TMPD/p.txt" "err bad_arg client scope" "a made-up scope or a non-app client is refused"
has "$TMPD/p.txt" "shared=true" "the reader now sets an activity"
part "$C" FILE HIDE > "$TMPD/p.txt"
has "$TMPD/p.txt" "app:reader contacts.read activity.write" "/etc/social/apps keeps the table"
part "$C" REVOKE INV0 > "$TMPD/p.txt"
has "$TMPD/p.txt" "err denied scope activity.write" "revoked: the reader is denied again"
hasnot "$TMPD/p.txt" "app:game" "revoking a client removes its line"
has "$TMPD/p.txt" "app:talker messages.send invites.send" "the other lines stay on disk"

echo "== 6. never show =="
part "$C" HIDE H1 > "$TMPD/p.txt"
has "$TMPD/p.txt" "shared=false" "a hidden app's activity stays on the device"
hasnot "$TMPD/p.txt" "Hidden Game" "... the provider never got it"
part "$C" H1 H2 > "$TMPD/p.txt"
has "$TMPD/p.txt" "shared=false" "an activity name on the never list stays on the device"
hasnot "$TMPD/p.txt" "Lost Woods" "... the provider never got it (by name)"
part "$C" H2 PRIV > "$TMPD/p.txt"
has "$TMPD/p.txt" "activity Lost Woods" "an activity name that was switched on again is shown"
part "$C" PRIV REVOKE > "$TMPD/p.txt"
has "$TMPD/p.txt" "hidden=" "privacy.get counts the hidden entries"
has "$TMPD/p.txt" "hide.1=app:seeded" "... the seeded one"
has "$TMPD/p.txt" "hide.2=app:game" "... and the new one"
hasnot "$TMPD/p.txt" "Lost Woods" "... the one switched on again is gone"
has "$TMPD/p.txt" "never=app:game" "/etc/social/privacy keeps the never list"
has "$TMPD/p.txt" "invites=friends" "... and the invite policy"
n_lw=$(part "$C" HIDE PRIV | grep -ac 'shared=false')
[ "$n_lw" = 2 ] && ok "two activities kept local (client and name)" || bad "kept local: $n_lw of 2"

echo "== 7. who may invite =="
part "$C" INV0 INVALL > "$TMPD/p.txt"
has "$TMPD/p.txt" "local:peter" "friends only: the friend"
hasnot "$TMPD/p.txt" "local:oma" "... not the stranger"
part "$C" INVALL INVNONE > "$TMPD/p.txt"
has "$TMPD/p.txt" "invites_from=all" "everybody: the policy is set"
has "$TMPD/p.txt" "local:oma" "... the stranger's invite appears"
part "$C" INVNONE INVBAD > "$TMPD/p.txt"
has "$TMPD/p.txt" "invites_from=none" "nobody: the policy is set"
hasnot "$TMPD/p.txt" "|in|" "... no incoming invite is listed (only my own, out)"
part "$C" INVBAD INVFRIENDS > "$TMPD/p.txt"
has "$TMPD/p.txt" "err bad_arg from" "a wrong policy word is refused"
part "$C" INVFRIENDS LOG > "$TMPD/p.txt"
has "$TMPD/p.txt" "local:peter" "friends again: the friend is back"
hasnot "$TMPD/p.txt" "local:oma" "... the stranger is gone"
has "$TMPD/p.txt" "invites_from=friends" "social.status shows the policy"
part "$C" PAGE PAGEHIDE > "$TMPD/p.txt"
has "$TMPD/p.txt" "app:reader|contacts.read,messages.send" "r341 page: allow=<client scope> gives one right (one text field)"
n_two=$(grep -ac 'contacts.read,messages.send' "$TMPD/p.txt")
[ "$n_two" = 1 ] && ok "... and exactly once: after deny=<client scope> the right is gone again" || bad "reader listed with both rights $n_two times (1 expected)"
n_bad=$(grep -ac '^err bad_arg client scope' "$TMPD/p.txt")
[ "$n_bad" = 2 ] && ok "... a missing scope and a non-app client are refused" || bad "bad_arg: $n_bad of 2"
n_ar=$(grep -ac 'app\.[0-9]*=app:reader' "$TMPD/p.txt")
[ "$n_ar" = 2 ] && ok "deny=<client> takes all rights: the reader is listed twice before, gone after" || bad "reader listed $n_ar times (2 expected)"
has "$TMPD/p.txt" "app:talker messages.send invites.send" "the table on disk after the page calls"
part "$C" PAGEHIDE SEARCH > "$TMPD/p.txt"
has "$TMPD/p.txt" "hide.3=Zelda" "r341 page: entry=<name> adds to the never list"
n_ze=$(grep -ac 'Zelda' "$TMPD/p.txt")
[ "$n_ze" = 1 ] && ok "... and show=<name> takes it off again (listed once, before)" || bad "Zelda appears $n_ze times (1 expected)"
has "$TMPD/p.txt" "never=app:game" "... the file keeps the other entries"
hasnot "$TMPD/p.txt" "never=app:seeded" "... and show=app:seeded took the seeded one off"
part "$C" SEARCH SEARCHEND > "$TMPD/p.txt"
has "$TMPD/p.txt" "contact.1=local:peter" "contacts.search as a group job: finds the friend"
has "$TMPD/p.txt" "count=0" "... and an empty search answers count=0"
has "$TMPD/p.txt" "err denied scope contacts.read" "... without the contacts.read right it is denied"
part "$C" LOG FERTIG > "$TMPD/p.txt"
has "$TMPD/p.txt" "social.privacy.invites" "the audit log names the privacy calls"
has "$TMPD/p.txt" "social.apps.grant" "... and the grants"

fin
