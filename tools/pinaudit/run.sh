#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { echo "  OK    $*"; pass=$((pass+1)); }
bad() { echo "  FAIL  $*"; fail=$((fail+1)); }

check() {
python3 -I - "$1" "$2" <<'PY'
import os, sys
root, reg = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.join(root, "tools/appreg"))
sys.path.insert(0, os.path.join(root, "tools/k15"))
import build, symjoin
aliases = dict(build.read_rows(os.path.join(root, "tools/appreg/alias.tsv"), "\t"))
n = 0
for row in build.read_rows(os.path.join(root, "tools/loader/apps.tab"), "|"):
    app, kind = row[0], row[6]
    d = os.path.join(reg, "usr/share/appreg", app)
    blob = open(os.path.join(d, "symbol"), "rb").read() if os.path.isfile(os.path.join(d, "symbol")) else b""
    m = symjoin.osym_ok(blob[:20748], 72) and symjoin.osym_ok(blob[20748:20748 + 7756], 44) and symjoin.osym_ok(blob[28504:], 64)
    print(("OK    " if m and len(blob) == 44900 else "FAIL  ") + "%s: joined 72/44/64 symbol in the registry" % app)
    al = os.path.join(d, "alias")
    want = build.alias_target(root, app)
    got = open(al).read().strip() if os.path.isfile(al) else None
    print(("OK    " if got == want else "FAIL  ") + "%s: alias marker %s matches alias.tsv %s" % (app, got, want))
    c = os.path.isfile(os.path.join(d, "console"))
    print(("OK    " if c == (kind == "konsole") else "FAIL  ") + "%s: console marker matches art=%s" % (app, kind))
    src = build.icon_dir(root, app, aliases)
    print(("OK    " if src else "FAIL  ") + "%s: icon source dir %s" % (app, os.path.relpath(src, root) if src else "-"))
PY
}

python3 -I tools/appreg/build.py "$ROOT" "$T/reg" && ok "registry builds for every apps.tab package" || bad "registry build"
out=$(check "$ROOT" "$T/reg"); echo "$out" | grep -c '^OK' | xargs -I{} echo "  ({} checks)"; echo "$out" | grep FAIL && fail=$((fail+$(echo "$out" | grep -c FAIL))) || ok "every package: hi-res joined symbol, console marker, SVG source"
python3 -I - "$ROOT" <<'PY' && ok "symbol.osym of every pkgicon within 1.5 of its SVG reference" || bad "pkgicon fidelity"
import glob, subprocess, sys
root = sys.argv[1]
worst = 0.0
for d in sorted(glob.glob(root + "/assets/pkgicons/*")):
    r = subprocess.run(["python3", "-I", root + "/tools/svg/cmp.py", d + "/symbol.svg", d + "/symbol.osym"], capture_output=True, text=True)
    mean = float(r.stdout.split()[0])
    worst = max(worst, mean)
    if mean > 1.5:
        sys.exit(1)
print("  worst mean", worst)
PY
for f in kernel/user/launcher.fi kernel/user/taskbar.fi; do grep -aq 'appreg.launch' $f && ok "$f starts programs through appreg.launch" || bad "$f bypasses appreg.launch"; done
for f in kernel/user/appdir.fi kernel/user/taskbar.fi kernel/user/taskmgr.fi; do grep -aq 'appreg.resolve_symbol' $f && ok "$f resolves symbols through the registry" || bad "$f skips the registry"; done
grep -aq 'appreg.duplicate_of' kernel/user/appdir.fi && ok "appdir drops aliased duplicates through the registry" || bad "appdir lists duplicates"
grep -aq 'start_ok' kernel/user/appdir.fi && ok "appdir drops entries without a startable target" || bad "appdir lists dead entries"

mkdir -p "$T/c1"; cp -a "$ROOT/tools" "$ROOT/assets" "$T/c1/" 2>/dev/null; rm -rf "$T/c1/assets/pkgicons/zip" "$T/c1/assets/apps/trashbin.osp"
python3 -I tools/appreg/build.py "$T/c1" "$T/reg1" > /dev/null && bad "counter-proof: missing icon source not detected" || ok "counter-proof: missing icon source fails the build"
mkdir -p "$T/c2"; cp -a "$ROOT/tools" "$ROOT/assets" "$T/c2/"; head -c 1036 /dev/zero > "$T/c2/assets/pkgicons/top/symbol.osym"
python3 -I tools/appreg/build.py "$T/c2" "$T/reg2" > /dev/null 2>&1; r=$(check "$T/c2" "$T/reg2" 2>&1 | grep -c "FAIL  top")
[ "$r" -ge 1 ] && ok "counter-proof: a 16x16-style symbol is rejected" || bad "counter-proof: low-res symbol accepted"
echo "PINAUDIT: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
