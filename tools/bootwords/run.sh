#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
pass=0; fail=0
. "${FIRN:-/root/firn}/tools/testkit/testkit.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

python3 -I tools/bootwords/gen.py --check && ok "docs/bootwords.md matches the kernel sources" || bad "docs/bootwords.md is stale: python3 tools/bootwords/gen.py"

count=$(grep -c '^| `' docs/bootwords.md)
[ "$count" -ge 600 ] && ok "doc lists $count words" || bad "doc lists only $count words"

for word in vfs nofs nokbd osum fastboot nonvmemany intelgpuback; do
    grep -q "^| \`$word\` " docs/bootwords.md && ok "word $word documented" || bad "word $word missing"
done

mkdir -p "$tmp/docs"
grep -v '^| `nonvmemany` ' docs/bootwords.md > "$tmp/docs/bootwords.md"
BOOTWORDS_DOC="$tmp/docs/bootwords.md" python3 -I tools/bootwords/gen.py --check && bad "counter-proof: doc without a word was accepted" || ok "counter-proof: doc without a word is rejected"
echo "BOOTWORDS: $pass passed, $fail failed"
[ $fail -eq 0 ]
