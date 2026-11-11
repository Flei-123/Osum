#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/otapublish/run.sh -- dry-run test of tools/ota/publish.sh (host only, no QEMU).
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }
expect_ok() { local name=$1; shift; if "$@" > "$T/out" 2>&1; then ok "$name"; else bad "$name"; tail -3 "$T/out"; fi; }
expect_fail() { local name=$1; shift; if "$@" > "$T/out" 2>&1; then bad "$name"; else ok "$name"; fi; }

head -c 32 /dev/urandom > "$T/secret.key"
mkdir -p "$T/img"
{ echo "osum abcdef0"; head -c 20000 /dev/urandom; } > "$T/img/osum.mb"
printf 'notes\n' > "$T/notes.txt"

stand() {
    local tag=$1 feed=$T/feed$1; shift
    python3 tools/ota/publish_system.py "$T/img" "$feed" dev --key "$T/secret.key" --count 7 --gz \
        --notes "$T/notes.txt" --name test "$@" > "$T/pub.log" 2>&1 || { echo "stand build failed"; tail -3 "$T/pub.log"; return 1; }
    cp "$feed/system/dev/schluessel.pub" "$T/pub$tag"
    echo "$feed/system/dev"
}
verify() { bash tools/ota/publish.sh --stand "$1" --pub "$2"; }

GOOD=$(stand good)
expect_ok "good stand verifies" verify "$GOOD" "$T/pubgood"
verify "$GOOD" "$T/pubgood" > "$T/report" 2>&1
KHASH=$(sha256sum "$T/img/osum.mb" | cut -d' ' -f1)
grep -q "$KHASH" "$T/report" && ok "report lists the kernel hash" || bad "report lists the kernel hash"
grep -q "kernel-7.mb" "$T/report" && ok "report lists the package file" || bad "report lists the package file"
grep -q "target .*/system/dev" "$T/report" && ok "report names the target path" || bad "report names the target path"

BADSIG=$(stand badsig --bad-sig)
expect_fail "broken signature aborts" verify "$BADSIG" "$T/pubbadsig"
grep -q "signature INVALID" "$T/out" && ok "broken signature is named" || bad "broken signature is named"

BADHASH=$(stand badhash --bad-hash)
expect_fail "wrong file hash aborts" verify "$BADHASH" "$T/pubbadhash"

TAMPER=$(stand tamper)
printf 'x' | dd of="$TAMPER/kernel-7.mb" bs=1 seek=100 conv=notrunc 2> /dev/null
expect_fail "tampered kernel aborts" verify "$TAMPER" "$T/pubtamper"

OTHERKEY=$(stand other)
head -c 32 /dev/urandom > "$T/secret2.key"
python3 -c "
import sys; sys.path.insert(0, 'tools/ota'); import listing
print(end='', file=sys.stderr)
open(sys.argv[1], 'wb').write(listing.load_opk().ed25519_public(open(sys.argv[2], 'rb').read()))" "$T/pubother" "$T/secret2.key"
expect_fail "foreign key aborts" verify "$OTHERKEY" "$T/pubother"

expect_fail "--apply with --stand is refused" bash tools/ota/publish.sh --stand "$GOOD" --pub "$T/pubgood" --apply

mkdir -p "$T/livefeed/aktuell"
cp "$T/pubgood" "$T/livefeed/aktuell/schluessel.pub"
BEFORE=$(find "$T/livefeed" -type f | sort | xargs sha256sum | sha256sum)
expect_fail "missing HP_BASE aborts the dry run" env FEED_DIR="$T/livefeed" HP_BASE="$T/nobase" bash tools/ota/publish.sh
grep -q "HP_BASE .* missing\|signing bundle" "$T/out" && ok "prerequisite failure is named" || bad "prerequisite failure is named"
expect_fail "missing HP_BASE aborts --apply" env FEED_DIR="$T/livefeed" HP_BASE="$T/nobase" bash tools/ota/publish.sh --apply
AFTER=$(find "$T/livefeed" -type f | sort | xargs sha256sum | sha256sum)
[ "$BEFORE" = "$AFTER" ] && ok "feed dir untouched" || bad "feed dir untouched"

echo "OTAPUBLISH: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
