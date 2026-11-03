#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/tmpdir.sh
D=$(mktemp -d)
osum_tmp_guard "${1:-}" "$D"
pass=0
fail=0
ok() { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
L=tools/layers/layers.py

rules="$D/rules.tsv"
printf 'layer\tstd\nlayer\tsyslib\nlayer\tframework\nlayer\tkernel\nlayer\tapp\nlib/libc\tstd\nlib/net\tsyslib\nlib/fui\tframework\nkernel/x\tkernel\nkernel/user/.\tapp\n' > "$rules"
mk() { rm -rf "$D/t"; mkdir -p "$D/t/lib/libc" "$D/t/lib/net" "$D/t/lib/fui" "$D/t/kernel/x" "$D/t/kernel/user"; }
expect_fail() {
    local name=$1 needle=$2
    out=$(python3 $L check --root "$D/t" --rules "$rules" --baseline "$D/empty.json" 2>&1); rc=$?
    if [ $rc -ne 0 ] && printf '%s' "$out" | grep -q "$needle"; then ok "$name"; else bad "$name (rc=$rc)"; fi
}
echo '{}' > "$D/empty.json"

echo "== 1. synthetic trees =="
mk
printf 'import net.b\nexport { a }\nfn a() {}\n' > "$D/t/lib/fui/a.fi"
printf 'export { b }\nfn b() {}\n' > "$D/t/lib/net/b.fi"
out=$(python3 $L check --root "$D/t" --rules "$rules" --baseline "$D/empty.json" 2>&1) && ok "clean tree (framework imports syslib) passes" || bad "clean tree fails: $out"
mk
printf 'import fui.a\nexport { s }\nfn s() {}\n' > "$D/t/lib/libc/s.fi"
printf 'export { a }\nfn a() {}\n' > "$D/t/lib/fui/a.fi"
expect_fail "counter-proof: std importing framework is caught" "new up_edges"
mk
printf 'import x.q\nexport { p }\nfn p() {}\n' > "$D/t/kernel/x/p.fi"
printf 'import x.p\nexport { q }\nfn q() {}\n' > "$D/t/kernel/x/q.fi"
expect_fail "counter-proof: import cycle is caught" "new cycle_files"
mk
mkdir -p "$D/t/lib/newdir"
printf 'export { z }\nfn z() {}\n' > "$D/t/lib/newdir/z.fi"
expect_fail "counter-proof: unmapped directory is caught" "unmapped"
mk
python3 -c "print('fn f() {}\n' * 2100)" > "$D/t/kernel/x/big.fi"
expect_fail "counter-proof: new giant file is caught" "new giants"
mk
printf 'import net.b\nexport { s }\nfn s() {}\n' > "$D/t/lib/libc/s.fi"
printf 'export { b }\nfn b() {}\n' > "$D/t/lib/net/b.fi"
python3 $L update --force --root "$D/t" --rules "$rules" --baseline "$D/known.json" > /dev/null
out=$(python3 $L check --root "$D/t" --rules "$rules" --baseline "$D/known.json" 2>&1) && ok "known violation in the baseline passes (ratchet)" || bad "baseline not honoured"
printf 'import net.b\nimport net.c\nexport { s }\nfn s() {}\n' > "$D/t/lib/libc/s.fi"
printf 'export { c }\nfn c() {}\n' > "$D/t/lib/net/c.fi"
out=$(python3 $L check --root "$D/t" --rules "$rules" --baseline "$D/known.json" 2>&1) && bad "second violation passed" || ok "a NEW violation beside a known one fails"

echo "== 2. the real tree =="
out=$(python3 $L check 2>&1); rc=$?
printf '%s\n' "$out" | head -12 | sed 's/^/        /'
[ $rc -eq 0 ] && ok "no new upward import, cycle member, giant, loose or unmapped file" || bad "layer rules violated"
sed 's#^lib/fui\tframework#lib/fui\tstd#' tools/layers/layers.tsv > "$D/swapped.tsv"
out=$(python3 $L check --rules "$D/swapped.tsv" 2>&1) && bad "counter-proof: wrong layer map on the real tree passed" || ok "counter-proof: wrong layer map on the real tree fails"
[ "$(python3 $L dump | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["up_edges"]))')" = 0 ] && ok "upward imports: 0" || bad "upward imports not 0"

echo "== $pass ok, $fail fail =="
[ $fail -eq 0 ]
