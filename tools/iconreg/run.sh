#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
REF=${ICONREG_REF:-/root/jarvis/data/projects_kb/orientos/attach/osum_icons_auswahl_20261122}
PASS=0; FAIL=0
ok()  { echo "  OK    $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $*"; FAIL=$((FAIL+1)); }

if python3 -I "$ROOT/tools/iconreg/check.py" "$ROOT" > /tmp/iconreg.$$ 2>&1; then ok "icons outside registry: 0"; else bad "icons outside registry"; cat /tmp/iconreg.$$; fi
rm -f /tmp/iconreg.$$

if [ -d "$REF/png" ]; then
    python3 -I "$ROOT/tools/iconreg/compare.py" "$REF" "$ROOT" 4 > /dev/null && ok "delivered icons match their PNG (mean error <= 4)" || bad "delivered icons differ from the PNG"
fi

D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
mkcopy() {
    rm -rf "$D/t"; mkdir -p "$D/t"
    for p in kernel lib tools/svg tools/appreg tools/loader assets/icons assets/apps assets/pkgicons pakete; do
        mkdir -p "$D/t/$(dirname "$p")"; cp -r "$ROOT/$p" "$D/t/$p"
    done
}
expect_red() {
    if python3 -I "$ROOT/tools/iconreg/check.py" "$D/t" > /dev/null 2>&1; then bad "counter-proof not caught: $1"; else ok "counter-proof caught: $1"; fi
}
mkcopy; printf 'static mut p_leak: [u8; 12] = ".osp/symbol\\0"\n' >> "$D/t/kernel/user/taskmgr.fi"; expect_red "second icon path in code"
mkcopy; printf 'fn leak() {\n    register("explorer\\0", icons.FILE_FOLDER, 0xE8A92A)\n}\n' >> "$D/t/kernel/user/store.fi"; expect_red "per-program icon table"
mkcopy; printf '<svg/>' > "$D/t/assets/apps/explorer.osp/symbol.svg"; expect_red "diverging icon copy"
mkcopy; rm "$D/t/assets/pkgicons/calc/symbol.osym"; expect_red "registry source without symbol"
mkcopy; rm "$D/t/assets/icons/app/lock.svg"; expect_red "program without central source"
echo "iconreg: $PASS ok, $FAIL fail"
[ "$FAIL" = 0 ]
