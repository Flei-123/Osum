#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
expect_fail() { local name=$1; shift; if "$@" > "$T/out" 2>&1; then bad "$name (accepted)"; else ok "$name"; fi; }
expect_pass() { local name=$1; shift; if "$@" > "$T/out" 2>&1; then ok "$name"; else bad "$name"; tail -5 "$T/out"; fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
LIVE=${PUBLISHDEV_LIVE:-/srv/store/osum}
mkdir -p "$T/feed/aktuell"
cp -a "$LIVE/system" "$T/feed/system"
cp "$LIVE/aktuell/schluessel.pub" "$T/feed/aktuell/"
URL="file://$T/feed"
STAND=$(awk -F'\t' '$1=="system"{print $2}' "$T/feed/system/dev/VERZEICHNIS")
expect_pass "intact feed verifies" python3 -I tools/ota/verify_feed.py "$URL" dev --count "$STAND"
expect_fail "wrong stand rejected" python3 -I tools/ota/verify_feed.py "$URL" dev --count 1
KERNEL=$(awk -F'\t' '$1=="sysfile"&&$2=="kernel"{print $5}' "$T/feed/system/dev/VERZEICHNIS")
cp -a "$T/feed" "$T/bad1"
printf 'X' | dd of="$T/bad1/system/dev/$KERNEL" bs=1 seek=100 conv=notrunc 2> /dev/null
expect_fail "tampered kernel byte rejected" python3 -I tools/ota/verify_feed.py "file://$T/bad1" dev
cp -a "$T/feed" "$T/bad2"
sed -i "s/^\(sysfile\tkernel\t\)./\10/" "$T/bad2/system/dev/VERZEICHNIS"
expect_fail "tampered hash in VERZEICHNIS rejected" python3 -I tools/ota/verify_feed.py "file://$T/bad2" dev
cp -a "$T/feed" "$T/bad3"
head -c 64 /dev/zero > "$T/bad3/system/dev/VERZEICHNIS.sig"
expect_fail "broken signature rejected" python3 -I tools/ota/verify_feed.py "file://$T/bad3" dev
export FEED_URL="$URL"
expect_fail "missing HP_BASE rejected" env HP_BASE="$T/nope" bash tools/ota/publish-dev.sh --dry
mkdir -p "$T/emptybase"
expect_fail "HP_BASE without SYSVERSION rejected" env HP_BASE="$T/emptybase" bash tools/ota/publish-dev.sh --dry
touch "$T/emptybase/SYSVERSION"
expect_fail "HP_BASE with too few programs rejected" env HP_BASE="$T/emptybase" bash tools/ota/publish-dev.sh --dry
mkdir -p "$T/base"
touch "$T/base/SYSVERSION"
for i in $(seq 1 100); do touch "$T/base/p$i.elf"; done
printf '#!/usr/bin/env bash\necho publisher-without-verification\n' > "$T/heavy-silent"
printf '#!/usr/bin/env bash\nprintf "verify OK: signature valid, 3 files match their hashes\\npackage feed unchanged (x)\\n(dry run, nothing published)\\n"\n' > "$T/heavy-good"
printf '#!/usr/bin/env bash\nprintf "verify OK: x\\n(dry run, nothing published)\\n"\n' > "$T/heavy-nopkg"
chmod +x "$T"/heavy-*
expect_fail "publisher without verify line rejected" env HP_BASE="$T/base" HEAVY_BIN="$T/heavy-silent" bash tools/ota/publish-dev.sh --dry
expect_fail "publisher without package-feed check rejected" env HP_BASE="$T/base" HEAVY_BIN="$T/heavy-nopkg" bash tools/ota/publish-dev.sh --dry
expect_pass "dry run with good publisher + intact feed" env HP_BASE="$T/base" HEAVY_BIN="$T/heavy-good" bash tools/ota/publish-dev.sh --dry
grep -q 'DRY OK' "$T/out" && ok "dry run reports DRY OK" || bad "dry run reports DRY OK"
expect_fail "dry run with tampered live feed rejected" env HP_BASE="$T/base" HEAVY_BIN="$T/heavy-good" FEED_URL="file://$T/bad1" bash tools/ota/publish-dev.sh --dry
echo "PUBLISHDEV: $pass passed, $fail failed"
[ "$fail" = 0 ]
