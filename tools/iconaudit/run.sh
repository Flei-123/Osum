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
#   2. the symbol is the vector picture (symbol.osym, OSYM 72x72, baked from symbol.svg, >= 10 % opaque
#      pixels, not one flat colour, NO FILLED TILE behind the glyph: r1016) -- no 16x16 pixel art
#      among 24 px icons
#   3. tools/svg/apps.tsv knows every bundle (else the next icon run
#      leaves it out)
#   4. every installable GUI package (pakete/*/rezept with `datei=start`) ships
#      `datei=symbol` and has its symbol.txt source
#   5. the programs pinned by the image's taskbar.conf have a bundle with an icon
#   5b. every GUI program of a bundle calls set_app (WM_APP), else its taskbar button has no icon
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
    if (w, h) != (72, 72): return "%dx%d, not 72x72 vector tile" % (w, h)
    if len(d) != 12 + w * h * 4: return "wrong size"
    px = [d[12 + i*4:16 + i*4] for i in range(w * h)]
    opaque = sum(1 for p in px if p[3] > 128)
    if opaque * 10 < w * h: return "only %d opaque pixels" % opaque
    # r1016: NO TILE.  A program icon is the glyph itself, rounded by its own shape; a filled
    # square / rounded square behind it (Win11 does not do that) shows as (a) most of the 72x72
    # box opaque, or (b) the four corner insets AND the four edge middles all opaque.
    def op(x, y): return px[y * w + x][3] > 128
    ring = [(36, 6), (36, 65), (6, 36), (65, 36)]
    cor = [(10, 10), (61, 10), (10, 61), (61, 61)]
    if opaque * 100 > w * h * 62: return "filled tile: %d %% of the box opaque" % (opaque * 100 // (w * h))
    if all(op(x, y) for x, y in ring) and all(op(x, y) for x, y in cor):
        return "filled tile: corners and edge middles opaque"
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
mk = open(os.path.join(root, "tools/svg/apps.tsv")).read()
known = set(re.findall(r"^([a-z0-9_]+)\t", mk, re.M))
for a in apps:
    n = os.path.basename(a)[:-4]
    say(n in known, "%s: listed in tools/svg/apps.tsv" % n)
for r in sorted(glob.glob(os.path.join(root, "pakete/*/rezept"))):
    t = open(r, errors="replace").read()
    n = os.path.basename(os.path.dirname(r))
    if re.search(r"^datei=start\s", t, re.M):
        say(re.search(r"^datei=symbol\s", t, re.M) is not None, "package %s: ships datei=symbol" % n)
        say(os.path.isfile(os.path.join(os.path.dirname(r), "symbol.txt")), "package %s: symbol.txt source" % n)
# 7. A window only gets its icon in the taskbar when the program itself says which bundle it belongs
#    to (WM_APP = fuiscene.set_app). welcome.fi never did: its button was an empty plate (W2c, laptop).
for a in apps:
    n = os.path.basename(a)[:-4]
    st = os.path.join(a, "start.txt")
    if not os.path.isfile(st): continue
    ex = [l.strip() for l in open(st, errors="replace") if l.strip() and not l.startswith("#")]
    m2 = re.match(r"/bin/([a-z0-9_]+)$", ex[0]) if ex else None
    if not m2 or m2.group(1) == "sh": continue
    src = os.path.join(root, "kernel/user", m2.group(1) + ".fi")
    if not os.path.isfile(src): continue
    t = open(src, "rb").read().decode("latin1")
    if not re.search(r"fuiscene\.open|open_window|wlib\.window\(", t): continue
    say(re.search(r"set_app\(|window_app\(|win_app\(", t) is not None, "%s: %s.fi sets its bundle name (WM_APP), else no taskbar icon" % (n, m2.group(1)))
tb = open(os.path.join(root, "tools/usbimg/build.sh"), errors="replace").read()
m = re.search(r"pins=([a-z0-9_,]+)", tb)
if m:
    have = {os.path.basename(a)[:-4] for a in apps if os.path.isfile(os.path.join(a, "symbol.osym"))}
    for p in m.group(1).split(","):
        say(p in have, "pinned program %s has a bundle icon" % p)
# 5c. r1090: the taskbar's symbol cache must hold a place for every pin, every window button, the start button and one spare. With
#     10 places a bar with its row of pins had none left for the Character Map: grey field instead of the Omega.
tb = os.path.join(root, "kernel/user/taskbar.fi")
if os.path.exists(tb):
    t = open(tb, "rb").read().decode("latin1")
    def cst(n):
        m = re.search(r"^const %s: u64 = (\d+)" % n, t, re.M)
        return int(m.group(1)) if m else 0
    sn, mp, mk = cst("SYM_N"), cst("MAXPIN"), cst("MAXK")
    say(sn >= mp + mk + 2 and mp > 0 and mk > 0, "taskbar symbol cache has a place for every pin, window button and the start button (SYM_N %d >= MAXPIN %d + MAXK %d + 2)" % (sn, mp, mk))
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
mkcopy() { rm -rf "$D/t"; mkdir -p "$D/t/assets" "$D/t/tools/svg" "$D/t/tools/usbimg" "$D/t/pakete"
    cp -r "$ROOT/assets/apps" "$D/t/assets/apps"
    cp "$ROOT/tools/svg/apps.tsv" "$D/t/tools/svg/"; cp "$ROOT/tools/usbimg/build.sh" "$D/t/tools/usbimg/"
    cp -r "$ROOT/pakete/." "$D/t/pakete/"; mkdir -p "$D/t/kernel"; cp -r "$ROOT/kernel/user" "$D/t/kernel/user"; }
expect_red() {  # expect_red <name>
    r=$(audit "$D/t" | grep -c '^FAIL'); [ "$r" -ge 1 ] && ok "counter-proof '$1': $r red" || bad "counter-proof '$1' stayed green"; }
mkcopy; rm "$D/t/assets/apps/store.osp/symbol.osym"; expect_red "icon file removed"
mkcopy; python3 -I -c "
import sys; sys.stdout.buffer.write(b'OSYM'+(72).to_bytes(4,'little')*2+bytes([0,0,0,0])*5184)" > "$D/t/assets/apps/store.osp/symbol.osym"; expect_red "empty transparent icon"
mkcopy; head -c 1036 "$ROOT/assets/apps/explorer.osp/symbol.osym" > "$D/t/assets/apps/store.osp/symbol.osym"; expect_red "truncated / 16x16 icon"
mkcopy; python3 -I -c "
import sys
b=bytearray(b'OSYM'+(72).to_bytes(4,'little')*2)
for y in range(72):
    for x in range(72):
        b+=bytes((200,100,50,255)) if 1<=x<=70 and 1<=y<=70 else bytes((0,0,0,0))
        if (x*7+y*3)%5==0: b[-4:]=bytes((255,255,255,255))
sys.stdout.buffer.write(bytes(b))" > "$D/t/assets/apps/store.osp/symbol.osym"; expect_red "icon on a filled tile (the old look)"
mkcopy; mkdir -p "$D/t/assets/apps/newapp.osp"; echo "name=New" > "$D/t/assets/apps/newapp.osp/INFO"; echo /bin/new > "$D/t/assets/apps/newapp.osp/start.txt"; expect_red "new program without icon"
mkcopy; sed -i '/^welcome\t/d' "$D/t/tools/svg/apps.tsv"; expect_red "program not in apps.tsv"
mkcopy; sed -i 's/^datei=symbol .*//' "$D/t/pakete/mail/rezept"; expect_red "package without symbol"
mkcopy; sed -i '/set_app(/d' "$D/t/kernel/user/welcome.fi"; expect_red "program without set_app (empty taskbar plate)"
mkcopy; sed -i 's/^const SYM_N: u64 = .*/const SYM_N: u64 = 10/' "$D/t/kernel/user/taskbar.fi"; expect_red "symbol cache smaller than pins + window buttons (grey charmap button)"

echo
echo "ICONAUDIT: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
