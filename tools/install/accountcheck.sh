#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#   bash tools/install/accountcheck.sh <disk.img> <outdir> <name> <password> [partition-number]
#
# Reads /etc/passwd, /etc/shadow, /etc/group and /users from the OFS root partition of an
# installed disk image and checks that exactly root and <name> exist, the PBKDF2 hash
# matches <password> (recomputed in Python), root is locked, the home exists and there is
# no autologin. Prints OK/FAIL lines; exit code 1 on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/../.."
DISK=$1; OUT=$2; GUI_NAME=$3; GUI_PW=$4; PART=${5:-2}
mkdir -p "$OUT"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
START=$(sgdisk -i "$PART" "$DISK" 2>/dev/null | awk '/First sector/ {print $3}')
END=$(sgdisk -i "$PART" "$DISK" 2>/dev/null | awk '/Last sector/ {print $3}')
[ -n "$START" ] && [ -n "$END" ] && ok "root partition sectors $START..$END" || bad "no partition 2 in the table"
dd if="$DISK" of="$OUT/root.part" bs=512 skip="$START" count=$((END - START + 1)) status=none 2>/dev/null
for f in passwd shadow group; do python3 tools/osum/mkfs.py cat "$OUT/root.part" "/etc/$f" > "$OUT/$f.txt" 2>"$OUT/$f.err"; done
python3 tools/osum/mkfs.py list "$OUT/root.part" 2>/dev/null | grep -E "^/users/|^/etc/autologin" > "$OUT/users.txt"
python3 -I - "$OUT" "$GUI_NAME" "$GUI_PW" > "$OUT/check.txt" 2>&1 <<'PYEOF'
import sys, hashlib, binascii, re
out, name, pw = sys.argv[1:4]
rd = lambda f: open(out + "/" + f, "rb").read().decode("latin1")
passwd, shadow, group, users = rd("passwd.txt"), rd("shadow.txt"), rd("group.txt"), rd("users.txt")
names = [l.split(":")[0] for l in passwd.splitlines() if ":" in l]
print("names", names)
print("R1", "ok" if names == ["root", name] else "bad names %r" % names)
sh = {l.split(":")[0]: l.split(":")[1] for l in shadow.splitlines() if ":" in l}
m = re.match(r"^\$osum1\$(\d+)\$([0-9a-f]+)\$([0-9a-f]+)$", sh.get(name, ""))
def check(p):
    if not m: return False
    dk = hashlib.pbkdf2_hmac("sha256", p.encode(), binascii.unhexlify(m.group(2)), int(m.group(1)), 32)
    return binascii.hexlify(dk).decode() == m.group(3)
print("R2", "ok" if check(pw) else "bad hash")
print("R3", "ok" if not check("wrong-pw-1") and sh.get("root") == "!" else "bad counter")
print("R4", "ok" if name in [l.split(":")[0] for l in group.splitlines()] else "bad group")
print("R5", "ok" if ("/users/%s/" % name) in users and "/etc/autologin" not in users else "bad users %r" % users[:200])
PYEOF
sed 's/^/        /' "$OUT/check.txt"
grep -q '^R1 ok' "$OUT/check.txt" && ok "/etc/passwd: root and '$GUI_NAME' only" || bad "/etc/passwd wrong: $(tr '\n' ' ' < "$OUT/passwd.txt")"
grep -q '^R2 ok' "$OUT/check.txt" && ok "hash matches the typed password" || bad "hash does not match"
grep -q '^R3 ok' "$OUT/check.txt" && ok "counter-check: wrong password rejected, root locked" || bad "counter-check failed"
grep -q '^R4 ok' "$OUT/check.txt" && ok "/etc/group has the account" || bad "group missing"
grep -q '^R5 ok' "$OUT/check.txt" && ok "home exists, no autologin" || bad "home/autologin wrong"
echo
echo "ACCOUNTCHECK: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
