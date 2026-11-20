#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
PASS=0
FAIL=0
ok() { echo "ok   $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL $1"; FAIL=$((FAIL + 1)); }

python3 -I tools/noopaudit/scan.py kernel/user > "$TMPD/scan.txt" && ok "no control without a handler in kernel/user" || { bad "controls without handler"; cat "$TMPD/scan.txt"; }
python3 -I tools/noopaudit/storecheck.py kernel/user tools/loader/apps.tab > "$TMPD/store.txt" && ok "store open path audit" || { bad "store open path audit"; cat "$TMPD/store.txt"; }

mkdir -p "$TMPD/m1" "$TMPD/m2" "$TMPD/m3"
cp -r kernel/user/. "$TMPD/m1/"
python3 -I - "$TMPD/m1/store.fi" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
marker = "slot3: u64 = s_page * PER_PAGE_UP"
cut = text.index("} else if key >= K_ROWACT")
end = text.index("} else if key == K_PRIMARY")
text = text[:cut] + text[end:]
open(path, "w").write(text)
PY
python3 -I tools/noopaudit/scan.py "$TMPD/m1" > "$TMPD/m1.txt" && bad "mutant without row handler not caught" || { grep -q "K_ROWACT" "$TMPD/m1.txt" && ok "mutant: removed K_ROWACT handler is caught" || bad "mutant caught for the wrong reason"; }

cp -r kernel/user/. "$TMPD/m2/"
python3 -I - "$TMPD/m2/store.fi" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace("P_APPS[0 as usize]) as u64)\n    ulib.strcat((&path[0 as usize]) as u64, name_at(i))", "P_BIN[0 as usize]) as u64)\n    ulib.strcat((&path[0 as usize]) as u64, name_at(i))", 1)
text = text.replace("static mut P_APPS", "static mut P_BIN: [u8; 6] = \"/bin/\\0\"\nstatic mut P_APPS", 1)
open(path, "w").write(text)
PY
python3 -I tools/noopaudit/storecheck.py "$TMPD/m2" tools/loader/apps.tab > "$TMPD/m2.txt" && bad "mutant with /bin path not caught" || ok "mutant: open_app on /bin/<name> is caught"

cp -r kernel/user/. "$TMPD/m3/"
python3 -I - "$TMPD/m3/store.fi" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace("notice(msg.get((&T_OPENFAIL[0 as usize]) as u64), title_of(i))", "", 1)
open(path, "w").write(text)
PY
python3 -I tools/noopaudit/storecheck.py "$TMPD/m3" tools/loader/apps.tab > "$TMPD/m3.txt" && bad "mutant with silent failure not caught" || ok "mutant: silent open failure is caught"

echo "NOOPAUDIT: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
