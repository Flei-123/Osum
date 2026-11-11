#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

build_run() {
    FIRNLIB="$1" "$FIRNC" --profile=app tools/services/host.fi -o "$2" > "$2.build" 2>&1 || return 99
    "$2" > "$2.txt"
}

build_run "$PWD/lib" "$T/real"; rc=$?
if [ "$rc" = 0 ]; then ok "host test green ($(tail -1 "$T/real.txt"))"; else bad "host test rc=$rc"; grep -v '^warning' "$T/real.build" | head; grep '^FAIL' "$T/real.txt" | head; fi

cat > "$T/kcheck.fi" <<'EOK'
profile kernel
import services.svcrules
import services.svcqueue
export { u_start }
fn u_start(args: u64) -> u64 {
    return svcrules.store_path(args, 1, args, 1, args, 160) + svcqueue.pending()
}
EOK
if FIRNLIB="$PWD/lib" "$FIRNC" --profile=kernel -c "$T/kcheck.fi" -o "$T/kcheck.o" > "$T/kcheck.build" 2>&1; then
    ok "services libs compile in profile kernel"
else
    bad "services libs do not compile in profile kernel"; grep -v '^warning' "$T/kcheck.build" | head
fi

mkdir -p "$T/kuser"
ln -s "$PWD"/kernel/user/* "$T/kuser/" 2>/dev/null
cat > "$T/kuser/_chk.fi" <<'EOK'
profile kernel
import services.svcosum
export { u_start }
fn u_start(args: u64) -> u64 {
    return svcosum.caps() + svcosum.pending()
}
EOK
if FIRNLIB="$PWD/lib" "$FIRNC" --profile=kernel -c "$T/kuser/_chk.fi" -o "$T/kuser.o" > "$T/kuser.build" 2>&1; then
    ok "kernel/user/services/svcosum.fi compiles in profile kernel"
else
    bad "svcosum.fi does not compile"; grep -v '^warning' "$T/kuser.build" | head
fi

mutate() {
    local d="$T/m_$1"
    rm -rf "$d"; mkdir -p "$d"; cp -r lib "$d/lib"
    python3 -I - "$d/lib/services/$2" "$3" "$4" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if old not in s:
    print("MUTATION-ANCHOR-MISSING"); sys.exit(2)
open(p, "w").write(s.replace(old, new, 1))
PY
    [ "$?" = 0 ] || { bad "mutation $1: anchor missing (the lib changed, update this script)"; return; }
    build_run "$d/lib" "$d/t"; local r=$?
    if [ "$r" = 1 ]; then ok "mutation '$1' is caught ($(grep -c '^FAIL' "$d/t.txt") red)"
    elif [ "$r" = 99 ]; then bad "mutation '$1' does not even compile"
    else bad "mutation '$1' SURVIVED (test stays green)"; fi
}

mutate dot-leading svcrules.fi "    if octets.ld8(p, 0) == DOT {
        return false
    }" ""
mutate slash-allowed svcrules.fi "return c == DOT || c == 45 || c == 95" "return c == DOT || c == 45 || c == 95 || c == SLASH"
mutate name-limit svcrules.fi "if n == 0 || n > NAME_MAX {" "if n == 0 || n > NAME_MAX + 1 {"
mutate empty-name svcrules.fi "if n == 0 || n > NAME_MAX {" "if n > NAME_MAX {"
mutate digits svcrules.fi "if c >= 48 && c <= 57 {" "if c >= 49 && c <= 57 {"
mutate upper svcrules.fi "if c >= 65 && c <= 90 {" "if c >= 66 && c <= 90 {"
mutate key-unchecked svcrules.fi "    if !valid_key(key, key_len) {
        return 0
    }" ""
mutate app-unchecked svcrules.fi "    if !valid_name(app, app_len) {
        return 0
    }" ""
mutate dir-bound svcrules.fi "if root_len + app_len + sub_len + 1 > max {" "if root_len + app_len + sub_len > max {"
mutate path-bound svcrules.fi "if at == 0 || at + 1 + key_len + 1 > max {" "if at == 0 || at + 1 + key_len > max {"
mutate status-table svcrules.fi "busy\\0not-found" "busy\\0not_found"
mutate status-clamp svcrules.fi "        wanted = FAILED" "        wanted = OK"
mutate has-any svcrules.fi "return (caps & cap) == cap" "return (caps & cap) != 0"
mutate cap-value svcrules.fi "const CAP_CLIP_READ: u64 = 8" "const CAP_CLIP_READ: u64 = 16"
mutate pad-two svcqueue.fi "return (n + 3) & 4294967292" "return (n + 1) & 4294967294"
mutate head-size svcqueue.fi "const HEAD_BYTES: u64 = 28" "const HEAD_BYTES: u64 = 24"
mutate data-after-name svcqueue.fi "octets.copy(at + HEAD_BYTES + padded(name_len), data, data_len)" "octets.copy(at + HEAD_BYTES + name_len, data, data_len)"
mutate no-clip-name svcqueue.fi "    if name_out > name_max {
        name_out = name_max
    }" ""
mutate no-compact svcqueue.fi "    if write_at + total > CAPACITY {
        compact()
    }" ""
mutate id-constant svcqueue.fi "    last_id = last_id + 1" "    last_id = last_id + 0"
mutate read-stuck svcqueue.fi "    read_at = read_at + total" "    read_at = read_at + 0"

echo "SERVICES: $pass passed, $fail failed"
[ "$fail" = 0 ]
