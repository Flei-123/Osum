#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/melder/run.sh -- THE MELDER ON ORIENTOS (r135), MEASURED.
#
#   /root/jarvis/bin/heavy bash tools/melder/run.sh
#
# A real Osum guest under QEMU with the broker /bin/orientbus, the social
# service /bin/social (one local provider) and /bin/melder
# (kernel/user/melder.fi): the backend of FirnChat's docs/MELDER-INTERFACE.md
# (r41) for OrientOS. A "game" is /bin/nap (a copy of sleep) listed in
# /etc/social/games.tsv. No network, no fleikontakte: the report is the
# bus action, and social.status is where it can be read back.
#
# Sections:
#   1. build: melder, the kernel, the manifest
#   2. the interface: hello / unsupported verbs / versions / games / detect
#   3. report: social.activity.set / .clear by the user; an app needs a grant
#   4. privacy: share (critical: parked, then confirmed), never list
#   5. the core: `once` and `serve` (a game starts, is reported, ends,
#      is cleared; a refusal pauses it)
#   6. autostart: one line in /etc/inittab
#   7. the audit log
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
T=$'\t'

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }
fin() { echo "MELDER: $pass passed, $fail failed"; exit $(( fail > 0 )); }

TMPD=$(mktemp -d)
[ -n "${MELDER_KEEP:-}" ] || trap 'rm -rf "$TMPD"' EXIT
[ -z "${MELDER_KEEP:-}" ] || trap 'echo "kept $TMPD"' EXIT
BLOCKS=30000
PROGS="sh ls cat echo sleep mkdir orientbus act social soclocal melder"
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
[ -x vendor/firn/bin/firnc ] || { echo "MELDER: firnc0 missing"; exit 1; }
mkdir -p "$TMPD/bin"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then
    ok "firnc0 builds $(echo $PROGS | wc -w) programs (melder.fi among them)"
else
    bad "the programs do not build"; sed 's/^/        /' "$TMPD/b.txt" | head -20; fin
fi
note "melder $(stat -c%s "$TMPD/bin/melder.elf") B"
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then
    ok "the kernel builds"
else
    bad "the kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'; fin
fi
python3 tools/actionbus/manifest.py check pakete/social/ACTIONS > "$TMPD/lint.txt" 2>&1 \
    && ok "host reader: $(head -1 "$TMPD/lint.txt")" \
    || bad "host reader refuses pakete/social/ACTIONS: $(cat "$TMPD/lint.txt")"
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "MELDER: skipped, qemu missing"; fin; }

mkdir -p "$TMPD/etc"
printf 'lang=de\n' > "$TMPD/etc/locale.conf"
printf 'provider local /bin/soclocal\n' > "$TMPD/etc/providers"
printf 'app:melder activity.write\n' > "$TMPD/etc/apps"
printf 'w\tnap\tWindows Nap\nl\tnap\tNap Quest\n# a comment\nl\techo\tEcho Hero\ttext-only-the-bash-core-can-check\nl\tcat\tCat Simulator\nl\tnap2\tWrong Args\tqq\nl\tnap2\tArgs Quest\tzz\n' > "$TMPD/etc/games.tsv"
printf '# name:targets:kind:command:options\nlogin:konsole:respawn:/bin/login\n' > "$TMPD/etc/inittab"
cp "$TMPD/bin/sleep.elf" "$TMPD/bin/nap.elf"
cp "$TMPD/bin/sleep.elf" "$TMPD/bin/nap2.elf"

cat > "$TMPD/s1.sh" <<'EOS'
orientbus serve 90000 &
sleep -m 300
social serve 90000 300 &
sleep 2
echo ==HELLO==
melder v1 hello
echo rc=$?
echo ==UNSUP==
melder v1 identity get
echo rc=$?
melder v1 nosuchverb
echo rc=$?
melder v2 hello
echo rc=$?
echo ==GAMES==
melder v1 games
echo rc=$?
echo ==DETECT==
nap 4 &
sleep -m 500
melder v1 detect
echo rc=$?
echo ==REPORT==
melder v1 report "Direct Game"
echo rc=$?
act call social.status
melder v1 report
echo rc=$?
act call social.status
echo ==APP==
melder --as app:melder v1 report "App Game"
echo rc=$?
act reject last
act grant app:melder social.activity.* write 120
melder --as app:melder v1 report "App Game"
echo rc=$?
act call social.status
melder --as app:melder v1 report
echo rc=$?
echo ==SHARE==
melder v1 privacy get
echo rc=$?
melder v1 privacy set share no
echo rc=$?
act confirm last
melder v1 privacy get
nap 4 &
sleep -m 500
melder once
echo rc=$?
melder v1 privacy set share yes
echo rc=$?
act confirm last
melder v1 privacy set share maybe
echo rc=$?
echo ==NEVER==
sleep 4
nap 6 &
sleep -m 500
melder v1 privacy set never nap,foo
echo rc=$?
melder v1 privacy get
melder once
echo rc=$?
melder v1 privacy set never "Bad Name!"
echo rc=$?
melder v1 privacy set never
echo rc=$?
melder v1 privacy get
echo ==ONCE==
melder once
echo rc=$?
act call social.status
melder v1 report
sleep 6
melder once
echo rc=$?
echo ==CMD==
nap2 6 ZZ &
sleep -m 500
melder once
echo rc=$?
act call social.status
melder v1 report
sleep 7
echo ==SERVE==
nap 7 &
melder serve 1700 100 > /tmp/serve.txt &
sleep 3
act call social.status
sleep 8
act call social.status
echo ==SERVEOUT==
sleep 7
cat /tmp/serve.txt
echo ==REFUSED==
nap 3 &
melder --as app:blocked serve 400 100 > /tmp/serve2.txt &
sleep 5
cat /tmp/serve2.txt
act reject last
echo ==AUTOSTART==
melder v1 autostart status
echo rc=$?
melder v1 autostart install
echo rc=$?
melder v1 autostart status
cat /etc/inittab
melder v1 autostart install
echo rc=$?
cat /etc/inittab
echo ==REMOVED==
melder v1 autostart remove
echo rc=$?
melder v1 autostart status
cat /etc/inittab
echo ==LOG==
cat /var/log/orientbus.log
act stop
sleep 1
echo ==FERTIG==
EOS

A_=(build "$TMPD/A.img" $BLOCKS /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/
    /etc/actions.d/ /etc/orientbus/ /etc/social/ /apps/ /apps/social.prog/ /var/ /var/log/
    "/etc/locale.conf=$TMPD/etc/locale.conf")
for p in $PROGS nap nap2; do A_+=("/bin/$p=$TMPD/bin/$p.elf"); done
A_+=("/apps/social.prog/ACTIONS=pakete/social/ACTIONS"
     "/etc/social/providers=$TMPD/etc/providers"
     "/etc/social/games.tsv=$TMPD/etc/games.tsv"
     "/etc/social/apps=$TMPD/etc/apps"
     "/etc/inittab=$TMPD/etc/inittab"
     "/t/s.sh=$TMPD/s1.sh")
python3 tools/osum/mkfs.py "${A_[@]}" > "$TMPD/mkfs.txt" 2>&1 || { bad "mkfs: $(tail -2 "$TMPD/mkfs.txt")"; fin; }

: > "$TMPD/a.txt"
T0=$(date +%s)
timeout 300 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 \
    -kernel "$TMPD/k0.img" -m 512 \
    -append "osum vfs nokbd bus script=sh /t/s.sh;exit" \
    -serial "file:$TMPD/a.txt" -display none -no-reboot \
    -drive "file=$TMPD/A.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
T1=$(date +%s)
tr -cd '\11\12\15\40-\176' < "$TMPD/a.txt" > "$TMPD/a.klar"
A="$TMPD/a.klar"
rm -f "$TMPD/A.img"
note "guest run: $((T1-T0)) s, accel=$OSUM_QEMU_ACCEL"
grep -qa '==FERTIG==' "$A" || { bad "the guest script did not reach its end"; tail -30 "$A" | sed 's/^/        /'; }

echo "== 2. the interface =="
part "$A" HELLO UNSUP > "$TMPD/p.txt"
has "$TMPD/p.txt" "backend${T}orientos${T}1" "hello: backend orientos 1"
has "$TMPD/p.txt" "os${T}l" "hello: os l"
has "$TMPD/p.txt" "caps${T}detect report privacy autostart games" "hello: caps (no identity: no token on OrientOS)"
has "$TMPD/p.txt" "ok 3" "hello ends with ok 3"
has "$TMPD/p.txt" "rc=0" "hello: exit 0"
part "$A" UNSUP GAMES > "$TMPD/p.txt"
has "$TMPD/p.txt" "err unsupported identity" "identity is unsupported"
has "$TMPD/p.txt" "rc=2" "... exit 2 (and for an unknown verb)"
has "$TMPD/p.txt" "err unsupported nosuchverb" "an unknown verb is unsupported"
has "$TMPD/p.txt" "err bad only interface v1" "v2 is refused (a new main version is a new first argument)"
has "$TMPD/p.txt" "rc=1" "... exit 1"
part "$A" GAMES DETECT > "$TMPD/p.txt"
has "$TMPD/p.txt" "l${T}nap${T}Nap Quest" "games: the list of /etc/social/games.tsv as it is"
hasnot "$TMPD/p.txt" "a comment" "games: comments are not rows"
has "$TMPD/p.txt" "ok 6" "games: 6 rows"
part "$A" DETECT REPORT > "$TMPD/p.txt"
grep -aqP '^p\t[0-9]+\tnap\t[0-9]+\tnap 4\r?$' "$TMPD/p.txt" && ok "detect: the game as 5 columns (p, pid, exe, age in s, command line with arguments; r146)" \
    || bad "detect: no p<TAB>pid<TAB>nap<TAB>age<TAB>nap 4 line"
grep -aqP '^p\t[0-9]+\tmelder\t' "$TMPD/p.txt" && ok "detect: the Melder itself is a program too" || bad "detect: no melder line"
grep -aqP '^ok [0-9]+\r?$' "$TMPD/p.txt" && ok "detect: ends with ok <n>" || bad "detect: no ok <n>"

echo "== 3. report =="
part "$A" REPORT APP > "$TMPD/p.txt"
has "$TMPD/p.txt" "ok 0" "report <name>: ok 0"
has "$TMPD/p.txt" "activity=Direct Game" "... social.status shows the activity (social.activity.set)"
grep -aqP '^activity=\r?$' "$TMPD/p.txt" && ok "report without a name clears it (social.activity.clear)" \
    || bad "the activity was not cleared"
part "$A" APP SHARE > "$TMPD/p.txt"
has "$TMPD/p.txt" "err denied confirm" "an app without a grant is parked: err denied"
has "$TMPD/p.txt" "rc=3" "... exit 3"
has "$TMPD/p.txt" "activity=App Game" "with the user's grant the app's report goes through"
grep -aq 'rc=0' "$TMPD/p.txt" && ok "... and its own clear works (rc=0)" || bad "app clear failed"

echo "== 4. privacy =="
part "$A" SHARE NEVER > "$TMPD/p.txt"
has "$TMPD/p.txt" "k${T}share${T}yes" "privacy get: share yes (from social.status)"
has "$TMPD/p.txt" "k${T}never${T}" "privacy get: never list (empty)"
has "$TMPD/p.txt" "err denied confirm" "privacy set share is critical: parked, err denied"
has "$TMPD/p.txt" "k${T}share${T}no" "after the user's confirm: share no (one truth: the social service)"
grep -aqP '^off\r?$' "$TMPD/p.txt" && ok "the core with share=no looks nowhere: off" || bad "once with share=no is not 'off'"
has "$TMPD/p.txt" "err bad privacy get|set share yes|no" "a bad value is refused"
part "$A" NEVER ONCE > "$TMPD/p.txt"
has "$TMPD/p.txt" "k${T}never${T}nap,foo" "privacy set never: kept (/etc/social/melder.never)"
grep -aqP '^idle\r?$' "$TMPD/p.txt" && ok "a program on the never list does not count" || bad "never list: not idle"
has "$TMPD/p.txt" "err bad never list" "a bad name in the list is refused"
grep -aqP "^k\tnever\t\r?\$" "$TMPD/p.txt" && ok "an empty list clears it" || bad "the never list was not cleared"

echo "== 5. the core =="
part "$A" ONCE CMD > "$TMPD/p.txt"
has "$TMPD/p.txt" "playing${T}Nap Quest" "once: the game of the list (os l, exe nap) is found and reported"
has "$TMPD/p.txt" "activity=Nap Quest" "... the activity stands in the social service"
hasnot "$TMPD/p.txt" "Windows Nap" "a row for another os (w) is not used"
hasnot "$TMPD/p.txt" "Echo Hero" "a row whose command-line text is not in the running program's command line does not match"
grep -aqP '^idle\r?$' "$TMPD/p.txt" && ok "once: idle when the game has ended" || bad "once after the game: not idle"
part "$A" CMD SERVE > "$TMPD/p.txt"
has "$TMPD/p.txt" "playing${T}Args Quest" "r146: exe nap2 + command-line text zz (case ignored: the program ran as 'nap2 6 ZZ') is found"
hasnot "$TMPD/p.txt" "Wrong Args" "... and the row with another text (qq) does not match"
has "$TMPD/p.txt" "activity=Args Quest" "... the activity stands in the social service"
part "$A" SERVE SERVEOUT > "$TMPD/p.txt"
has "$TMPD/p.txt" "activity=Nap Quest" "serve: while the game runs the activity is reported"
grep -aqP '^activity=\r?$' "$TMPD/p.txt" && ok "serve: cleared after the game ended" || bad "serve: not cleared"
part "$A" SERVEOUT REFUSED > "$TMPD/p.txt"
has "$TMPD/p.txt" "melder: playing Nap Quest" "serve says: playing"
has "$TMPD/p.txt" "melder: idle" "serve says: idle after the end"
part "$A" REFUSED AUTOSTART > "$TMPD/p.txt"
has "$TMPD/p.txt" "melder: refused (confirm" "serve as an app without a grant: refused (parked), no spam"

echo "== 6. autostart =="
part "$A" AUTOSTART REMOVED > "$TMPD/p.txt"
has "$TMPD/p.txt" "k${T}autostart${T}missing" "autostart status: missing"
has "$TMPD/p.txt" "k${T}unit${T}/etc/inittab" "... the unit is the init table"
has "$TMPD/p.txt" "k${T}autostart${T}installed" "install: installed"
has "$TMPD/p.txt" "melder:*:respawn:/bin/melder serve" "install: one respawn line for init"
has "$TMPD/p.txt" "login:konsole:respawn:/bin/login" "the other lines stay"
n_line=$(grep -ac '^melder:' "$TMPD/p.txt")
[ "$n_line" = 2 ] && ok "install twice is the same (one line in each of the two listings)" || bad "melder line count $n_line (want 2 listings)"
part "$A" REMOVED LOG > "$TMPD/p.txt"
has "$TMPD/p.txt" "k${T}autostart${T}missing" "remove: missing again"
hasnot "$TMPD/p.txt" "melder:" "remove: the line is gone"
has "$TMPD/p.txt" "login:konsole:respawn:/bin/login" "remove: the other lines stay"

echo "== 7. the audit log =="
part "$A" LOG FERTIG > "$TMPD/p.txt"
has "$TMPD/p.txt" "social.activity.set" "the audit log names the activity calls"
has "$TMPD/p.txt" "social.privacy.set" "... and the privacy call"
echo "== 8. a screen image (tools/melder/screen.sh, r140) =="
bash tools/melder/screen.sh > "$TMPD/screen.txt" 2>&1
sed 's/^/    /' "$TMPD/screen.txt"
sp=$(sed -n 's/^MELDER-SCREEN: \([0-9]*\) passed, \([0-9]*\) failed.*/\1/p' "$TMPD/screen.txt" | tail -1)
sf=$(sed -n 's/^MELDER-SCREEN: \([0-9]*\) passed, \([0-9]*\) failed.*/\2/p' "$TMPD/screen.txt" | tail -1)
if [ -n "$sp" ]; then pass=$((pass + sp)); fail=$((fail + sf)); else bad "screen.sh gave no result line"; fi
fin
