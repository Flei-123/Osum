#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
TMPD=${TM2_OUT:-$(mktemp -d)}
mkdir -p "$TMPD"
[ -n "${TM2_OUT:-}" ] || trap 'rm -rf "$TMPD"' EXIT
pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
. tools/lib/firnenv.sh
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "TASKMGR-NAMES: skipped, no qemu"; exit 0; }

PROGS="desktop taskbar settings launcher theme explorer taskmgr sh echo ls cat sleep ps kill top thrpark"
echo "== 1. one threaded program next to the task manager =="
cat > "$TMPD/plan.txt" <<'EOF'
marke ---- list with a threaded program ----
warte 6
foto n01_list
EOF
bash tools/toolbench/build.sh "$TMPD/n" desk=yes progs="$PROGS" \
    app=/bin/thrpark,/bin/taskmgr,report,takt,500 wait=14 last=400 extra="wighalt=120" \
    plan="$TMPD/plan.txt" > "$TMPD/n.log" 2>&1 && ok "image with thrpark built" || { bad "build"; tail -5 "$TMPD/n.log"; }
SER="$TMPD/n/serial.txt"
python3 -I - "$SER" > "$TMPD/check.txt" 2>&1 <<'PY'
import re, sys
lines = open(sys.argv[1], "rb").read().decode("latin1").splitlines()
start = max((i for i, z in enumerate(lines) if z.startswith("taskmgr: block ")), default=0)
rows = []
order = []
for z in lines[start:]:
    m = re.match(r"taskmgr: row r=(\d+) pid=(\d+) .* thr=(\d+) .* name=(.*)$", z)
    if m:
        rows.append((int(m.group(1)), int(m.group(2)), int(m.group(3)), m.group(4).strip()))
        continue
    if z.startswith("taskmgr: blockende"):
        break
pids = [r[1] for r in rows]
names = [r[3] for r in rows]
res = {
    "rows": len(rows),
    "unique_pids": len(set(pids)) == len(pids),
    "park_rows": names.count("thrpark"),
    "park_threads": max((r[2] for r in rows if r[3] == "thrpark"), default=0),
    "unnamed": sum(1 for n in names if n in ("", "Programm", "program")),
}
for k, v in res.items():
    print("%s=%s" % (k, v))
PY
get() { grep -a "^$1=" "$TMPD/check.txt" | head -1 | cut -d= -f2; }
[ "$(get rows)" -ge 5 ] 2>/dev/null && ok "the list has rows ($(get rows))" || bad "no list rows: $(cat "$TMPD/check.txt")"
[ "$(get unique_pids)" = True ] && ok "every process is listed once" || bad "a pid is listed twice"
[ "$(get park_rows)" = 1 ] && ok "the threaded program is ONE row, not one per thread" || bad "thrpark rows: $(get park_rows)"
[ "$(get park_threads)" -ge 7 ] 2>/dev/null && ok "that row reports its threads ($(get park_threads))" || bad "thread count: $(get park_threads)"
[ "$(get unnamed)" = 0 ] && ok "no row is called just 'program'" || bad "$(get unnamed) unnamed rows"
grep -aq '^taskmgr: group ' "$SER" && ok "group headings are reported" || bad "no group heading"

echo
echo "TASKMGR-NAMES: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
