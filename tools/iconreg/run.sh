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
mksite() { rm -rf "$D/site"; mkdir -p "$D/site/src/partials" "$D/site/src/assets/icons"; printf '{{icon:explorer}}' > "$D/site/src/index.template.html"; }
expect_red_site() {
    if ICONREG_SITE="$D/site" python3 -I "$ROOT/tools/iconreg/check.py" "$ROOT" > /dev/null 2>&1; then bad "counter-proof not caught: $1"; else ok "counter-proof caught: $1"; fi
}
mksite; ICONREG_SITE="$D/site" python3 -I "$ROOT/tools/iconreg/check.py" "$ROOT" > /dev/null 2>&1 && ok "homepage with registry ids only" || bad "clean homepage flagged"
mksite; printf '<svg/>' > "$D/site/src/assets/icons/explorer.svg"; expect_red_site "homepage icon copy"
mksite; printf '{{icon:ghost}}' >> "$D/site/src/index.template.html"; expect_red_site "homepage icon id outside the registry"
mksite; printf '<svg viewBox="0 0 1 1"/>' >> "$D/site/src/partials/bar.html"; expect_red_site "homepage inline svg"
python3 -I "$ROOT/tools/appreg/export.py" --out "$D/exp" > /dev/null && python3 -I -c "
import json,sys
d=json.load(open(sys.argv[1]+'/index.json'))
assert d['icons']['edit']['alias_of']=='editor' and d['icons']['explorer']['file']=='explorer.svg'
assert all(open(sys.argv[1]+'/'+v['file']).read().lstrip().startswith('<svg') for v in d['icons'].values())
" "$D/exp" && ok "export: every id has its SVG, aliases resolve" || bad "export index wrong"
echo "iconreg: $PASS ok, $FAIL fail"
[ "$FAIL" = 0 ]
