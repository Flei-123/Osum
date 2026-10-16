#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/iconaudit/run.sh -- ICON AUDIT (W3 polish run, boss point 4).
#
#   bash tools/iconaudit/run.sh [repo-root]
#
# Host-only, no VM, a few seconds. Every program a user can SEE (start menu,
# taskbar, store row) must carry an icon, and all of them must be the same
# kind of icon. Red means a program would show an empty square / a different
# drawing style:
#   1. every bundle assets/apps/*.osp has INFO (name=), start.txt and a symbol
#   2. the symbol is the vector tile (symbol.osym, OSYM 32x32, >= 25 % opaque
#      pixels, not one flat colour) -- no 16x16 pixel art among 24 px icons
#   3. tools/design/mkicons.py knows every bundle (else the next icon run
#      leaves it out)
#   4. every installable GUI package (pakete/*/rezept with `datei=start`) ships
#      `datei=symbol` and has its symbol.txt source
#   5. the programs pinned by the image's taskbar.conf have a bundle with an icon
#   6. COUNTER-PROOF: a copy of the tree with one symbol removed / one flat
#      square / one 16x16 drawing must make this audit FAIL
set -uo pipefail
ROOT=${1:-$(cd "$(dirname "$0")/../.." && pwd)}
PASS=0; FAIL=0
ok()  { echo "  OK    $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $*"; FAIL=$((FAIL+1)); }

audit() {  # audit <root>: prints "OK ..." / "FAIL ..." lines
python3 -I - "$1" <<'PY'
import os, re, struct, sys, glob
root = sys.argv[1]
apps = sorted(glob.glob(os.path.join(root, "assets/apps/*.osp")))
def say(ok, msg): print(("OK    " if ok else "FAIL  ") + msg)
def osym_check(path):
    d = open(path, "rb").read()
    if d[:4] != b"OSYM" or len(d) < 12: return "no OSYM header"
    w, h = struct.unpack("<II", d[4:12])
    if (w, h) != (32, 32): return "%dx%d, not 32x32 vector tile" % (w, h)
    if len(d) != 12 + w * h * 4: return "wrong size"
    px = [d[12 + i*4:16 + i*4] for i in range(w * h)]
    opaque = sum(1 for p in px if p[3] > 128)
    if opaque * 4 < w * h: return "only %d opaque pixels" % opaque
    if len(set(px)) < 8: return "flat picture (%d colours)" % len(set(px))
    return ""
for a in apps:
    n = os.path.basename(a)[:-4]
    info = os.path.join(a, "INFO")
    has_name = os.path.isfile(info) and re.search(r"^name=.+", open(info, errors="replace").read(), re.M)
    say(bool(has_name), "%s: INFO with name=" % n)
    say(os.path.isfile(os.path.join(a, "start.txt")), "%s: start.txt" % n)
    sym = os.path.join(a, "symbol.osym")
    if os.path.isfile(sym):
        r = osym_check(sym)
        say(r == "", "%s: symbol.osym%s" % (n, "" if r == "" else " (" + r + ")"))
    elif os.path.isfile(os.path.join(a, "symbol.txt")):
        say(False, "%s: only a 16x16 symbol.txt, no vector symbol.osym" % n)
    else:
        say(False, "%s: NO ICON (no symbol.osym, no symbol.txt)" % n)
mk = open(os.path.join(root, "tools/design/mkicons.py")).read()
known = set(re.findall(r'^\s+"([a-z0-9_]+)":\s+\(', mk, re.M))
for a in apps:
    n = os.path.basename(a)[:-4]
    say(n in known, "%s: listed in tools/design/mkicons.py" % n)
for r in sorted(glob.glob(os.path.join(root, "pakete/*/rezept"))):
    t = open(r, errors="replace").read()
    n = os.path.basename(os.path.dirname(r))
    if re.search(r"^datei=start\s", t, re.M):
        say(re.search(r"^datei=symbol\s", t, re.M) is not None, "package %s: ships datei=symbol" % n)
        say(os.path.isfile(os.path.join(os.path.dirname(r), "symbol.txt")), "package %s: symbol.txt source" % n)
tb = open(os.path.join(root, "tools/usbimg/build.sh"), errors="replace").read()
m = re.search(r"pins=([a-z0-9_,]+)", tb)
if m:
    have = {os.path.basename(a)[:-4] for a in apps if os.path.isfile(os.path.join(a, "symbol.osym"))}
    for p in m.group(1).split(","):
        say(p in have, "pinned program %s has a bundle icon" % p)
PY
}

echo "== 1. the tree"
OUTT=$(audit "$ROOT")
echo "$OUTT" | grep '^FAIL' | sed 's/^/  /'
nf=$(echo "$OUTT" | grep -c '^FAIL'); np=$(echo "$OUTT" | grep -c '^OK')
echo "        $np ok, $nf red"
PASS=$((PASS+np)); FAIL=$((FAIL+nf))
[ "$np" -ge 40 ] && ok "the audit looked at $np things (not an empty run)" || bad "audit ran only $np checks"

echo "== 2. COUNTER-PROOF: the audit must turn red on broken trees"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
mkcopy() { rm -rf "$D/t"; mkdir -p "$D/t/assets" "$D/t/tools/design" "$D/t/tools/usbimg" "$D/t/pakete"
    cp -r "$ROOT/assets/apps" "$D/t/assets/apps"
    cp "$ROOT/tools/design/mkicons.py" "$D/t/tools/design/"; cp "$ROOT/tools/usbimg/build.sh" "$D/t/tools/usbimg/"
    cp -r "$ROOT/pakete/." "$D/t/pakete/"; }
expect_red() {  # expect_red <name>
    r=$(audit "$D/t" | grep -c '^FAIL'); [ "$r" -ge 1 ] && ok "counter-proof '$1': $r red" || bad "counter-proof '$1' stayed green"; }
mkcopy; rm "$D/t/assets/apps/store.osp/symbol.osym"; expect_red "icon file removed"
mkcopy; python3 -I -c "
import sys; sys.stdout.buffer.write(b'OSYM'+(32).to_bytes(4,'little')*2+bytes([0,0,0,0])*1024)" > "$D/t/assets/apps/store.osp/symbol.osym"; expect_red "empty transparent icon"
mkcopy; head -c 1036 "$ROOT/assets/apps/explorer.osp/symbol.osym" > "$D/t/assets/apps/store.osp/symbol.osym"; expect_red "truncated / 16x16 icon"
mkcopy; mkdir -p "$D/t/assets/apps/newapp.osp"; echo "name=New" > "$D/t/assets/apps/newapp.osp/INFO"; echo /bin/new > "$D/t/assets/apps/newapp.osp/start.txt"; expect_red "new program without icon"
mkcopy; sed -i '/"welcome":/d' "$D/t/tools/design/mkicons.py"; expect_red "program not in mkicons.py"
mkcopy; sed -i 's/^datei=symbol .*//' "$D/t/pakete/mail/rezept"; expect_red "package without symbol"

echo
echo "ICONAUDIT: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
