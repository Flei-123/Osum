#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# heavy bash tools/resetsys/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${OUT:-$(mktemp -d)}
mkdir -p "$OUT"
export OUT
trap '[ -n "${KEEP:-}" ] || rm -rf "$OUT"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }
hat() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' is not in $(basename "$1")"; }
nicht() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is in $(basename "$1")" || ok "$3"; }

after_marker() {
    python3 -I -c 'import sys; t = open(sys.argv[1], errors="replace").read(); open(sys.argv[3], "w").write(t.rsplit(sys.argv[2], 1)[-1])' "$1" "$2" "$3"
}

lauf() {
    OUT="$OUT" bash tools/install/oneshot.sh "$1" "$2" "${3:-}" "${4:-300}" > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/$1.txt" 2>/dev/null
}

echo "== 1. build =="
PROGS="sh ls cat echo cp mv rm mkdir rmdir touch head tail wc grep sort uniq true false sleep ps kill uname date df mount umount sync id whoami shasum resetsys" \
    bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 || {
        echo "  FAIL  build.sh"; tail -20 "$OUT/build.log"; exit 1; }
[ -f "$OUT/bin/resetsys" ] && ok "resetsys is built" || bad "resetsys is not built"

SETUP="mkdir /etc;mkdir /users;mkdir /users/root;mkdir /users/alice;mkdir /users/alice/config;mkdir /users/alice/sub;mkdir /users/alice/sub/deep;echo doc-alice > /users/alice/doc.txt;echo deep-alice > /users/alice/sub/deep/f.txt;echo cfg-alice > /users/alice/config/k.conf;mkdir /users/carol;echo doc-carol > /users/carol/c.txt;echo root:x:0:0:root:/:/bin/sh > /etc/passwd;mkdir /system;mkdir /system/factory;echo speed=100 > /system/factory/mouse.conf;echo speed=999 > /etc/mouse.conf;mkdir /var;mkdir /var/log;echo logline > /var/log/a.log;echo Correct-horse-7 > /pw;echo night=true > /etc/modes.conf;echo brightness=11 > /etc/settings.db"

echo
echo "== 2. nothing happens without confirmation =="
lauf noconf iso "$SETUP;shasum /bin/sh;resetsys system --name bob --confirm WRONG --ja < /pw;resetsys system --name bob --confirm RESET < /pw;resetsys system --confirm RESET --ja < /pw;resetsys settings;ls /users;cat /etc/mouse.conf;ls /var/log;shasum /bin/sh;exit" 300
hat "$OUT/noconf.txt" "resetsys: not confirmed, nothing changed" "wrong confirmation word is refused"
hat "$OUT/noconf.txt" "resetsys: dry run, nothing was changed" "missing --ja is a dry run"
nicht "$OUT/noconf.txt" "resetsys: step" "no step ran"
hat "$OUT/noconf.txt" "alice" "alice still exists"
hat "$OUT/noconf.txt" "carol" "carol still exists"
hat "$OUT/noconf.txt" "speed=999" "settings untouched"
hat "$OUT/noconf.txt" "a.log" "logs untouched"

echo
echo "== 3. settings reset keeps data =="
lauf sett iso "$SETUP;resetsys settings --ja;cat /etc/mouse.conf;echo DB-AFTER;ls /etc;ls /users/alice;ls /users/alice/config;cat /users/alice/doc.txt;exit" 300
after_marker "$OUT/sett.txt" "DB-AFTER" "$OUT/sett-after.txt"
hat "$OUT/sett.txt" "resetsys: step 1/1 settings" "settings step reported"
hat "$OUT/sett.txt" "speed=100" "factory mouse.conf restored"
nicht "$OUT/sett-after.txt" "k.conf" "user config cleared"
nicht "$OUT/sett-after.txt" "settings.db" "settings database dropped"
nicht "$OUT/sett-after.txt" "modes.conf" "mode overrides dropped"
hat "$OUT/sett.txt" "doc-alice" "user data survives a settings reset"
hat "$OUT/sett.txt" "resetsys: ok" "settings reset ok"

echo
echo "== 4. system reset: accounts and data gone, system intact =="
lauf sys iso "$SETUP;shasum /bin/sh;resetsys system --name bob --confirm RESET --ja < /pw;echo PASSWD-AFTER;cat /etc/passwd;echo USERS-AFTER;ls /users;echo LOG-AFTER;ls /var/log;shasum /bin/sh;ls /bin/ls;cat /etc/welcome.conf;cat /etc/mouse.conf;exit" 300
hat "$OUT/sys.txt" "resetsys: step 5/5 sync" "all five steps reported"
hat "$OUT/sys.txt" "resetsys: ok" "system reset ok"
nicht "$OUT/sys.txt" "resetsys: error" "no error"
python3 -I - "$OUT/sys.txt" <<'PY' && ok "alice and carol are gone, bob exists, root kept" || bad "account state after reset"
import sys
t = open(sys.argv[1], errors="replace").read()
after = t.rsplit("PASSWD-AFTER", 1)[1]
passwd, rest = after.split("USERS-AFTER", 1)
users, logs = rest.split("LOG-AFTER", 1)
logs = logs.split("\n\n")[0]
assert "bob:x:1000" in passwd and "root:x:0" in passwd
assert "alice" not in passwd and "carol" not in passwd
assert "bob" in users and "root" in users
assert "alice" not in users and "carol" not in users
assert "a.log" not in logs
PY
SHA1=$(grep -aoE '^[0-9a-f]{64}  /bin/sh' "$OUT/sys.txt" | sed -n 1p | cut -c1-64)
SHA2=$(grep -aoE '^[0-9a-f]{64}  /bin/sh' "$OUT/sys.txt" | sed -n 2p | cut -c1-64)
[ ${#SHA1} -eq 64 ] && [ "$SHA1" = "$SHA2" ] && ok "system binary /bin/sh unchanged" || bad "/bin/sh hash differs: '$SHA1' '$SHA2'"
hat "$OUT/sys.txt" "show=ja" "welcome window is armed for the new owner"
hat "$OUT/sys.txt" "speed=100" "factory settings restored"

echo
echo "== 5. bad new account writes nothing =="
lauf badacct iso "$SETUP;echo x > /pw2;resetsys system --name bob --confirm RESET --ja < /pw2;ls /users;exit" 300
hat "$OUT/badacct.txt" "resetsys: error" "weak password is refused"
hat "$OUT/badacct.txt" "alice" "alice still exists after the refused reset"
nicht "$OUT/badacct.txt" "resetsys: step" "no step ran"

echo
echo "$pass green, $fail red"
[ "$fail" -eq 0 ] || exit 1
