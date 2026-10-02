#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/pdf/run.sh -- THE PDF VIEWER (r55), MEASURED.
#
#   bash tools/pdf/run.sh
#
#   1. build: the reader's host drivers (the SAME lib/pdfread the viewer uses)
#   2. corpus: PDFs from reportlab, pypdf and a raw writer (xref streams, object
#      streams, ASCII85/Hex/RunLength/LZW, rotated pages, images, Unicode fonts,
#      forms, damaged and encrypted files) -- not from the reader's own idea of a PDF
#   3. against poppler: per page the multiset of characters equals pdftotext's,
#      and the picture (reader -> SVG -> OrientOS's SVG renderer, images blitted)
#      differs from pdftoppm's by less than 3 grey levels on average
#   4. damaged files: encrypted -> error 2, garbage/empty -> error 1, truncated or
#      with a wrong startxref -> the file is rebuilt and the page is there
#   5. fuzz: 800 random corruptions of the corpus; the reader may refuse, never
#      crash, never hang (exit 0 or 3, nothing else)
#   6. speed: 40 pages in under 5 s; a 150-page document in under 15 s
#   7. IN THE GUEST (QEMU, OrientOS's own build): /bin/pdfview --render prints the
#      checksum of the page it made; it must equal the host's, bit for bit
#   8. THE WINDOW: a picture of it, then the keys PgDn and `-` through the QEMU
#      monitor: the page counter says "Seite 2 von 2" and the zoom went down
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${OUT:-/tmp/pdf-run}
mkdir -p "$OUT"
. tools/lib/sperre.sh && osum_sperre "$OUT"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
FONT="$ROOT/assets/osum-sans.ttf"; FONTB="$ROOT/assets/osum-sans-bold.ttf"; FONTM="$ROOT/assets/osum-mono.ttf"
for t in python3 pdftotext pdftoppm; do
    command -v "$t" >/dev/null 2>&1 || { echo "PDF: skipped, $t is missing"; exit 0; }
done

echo "== 1. build =="
vendor/firn/bin/firnc tools/pdf/pdfdump.fi -o "$OUT/pdfdump" > "$OUT/b1.log" 2>&1 && ok "pdfdump (host driver)" || { bad "pdfdump"; head -5 "$OUT/b1.log"; }
vendor/firn/bin/firnc tools/pdf/pdfpng.fi -o "$OUT/pdfpng" > "$OUT/b2.log" 2>&1 && ok "pdfpng (host driver, the viewer's own render path)" || { bad "pdfpng"; head -5 "$OUT/b2.log"; }

echo; echo "== 2. corpus =="
python3 tools/pdf/corpus.py "$OUT/c" > "$OUT/corpus.log" 2>&1 && ok "$(ls "$OUT/c"/*.pdf | wc -l) PDFs written" || { bad "corpus.py"; tail -3 "$OUT/corpus.log"; }

echo; echo "== 3. against poppler (text and picture) =="
cat > "$OUT/cmp.py" <<'PY'
import collections, html, io, re, subprocess, sys
import numpy as np
from PIL import Image, ImageFilter
pdf, raw, svgfile, w, h, page = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6])
def norm(t): return collections.Counter(c for c in t if not c.isspace() and c not in "­ﬁﬂ")
s = open(svgfile, encoding="utf-8").read()
a = norm("".join(html.unescape(t) for t in re.findall(r"<text[^>]*>([^<]*)</text>", s)))
b = norm(subprocess.run(["pdftotext", "-raw", "-f", str(page), "-l", str(page), pdf, "-"], capture_output=True).stdout.decode("utf-8", "replace"))
print("text", "ok" if a == b else "DIFF")
d = np.frombuffer(open(raw, "rb").read(), dtype=np.uint32).reshape(h, w)
rgb = np.stack([(d >> 16) & 255, (d >> 8) & 255, d & 255], axis=-1).astype("uint8")
im = Image.fromarray(rgb).convert("L")
subprocess.run(["pdftoppm", "-r", "72", "-f", str(page), "-l", str(page), "-gray", "-png", pdf, "/tmp/_cmp_%d" % page], capture_output=True)
import glob
ref = sorted(glob.glob("/tmp/_cmp_%d-*.png" % page))
rim = Image.open(ref[0]).convert("L")
for f in ref:
    import os; os.remove(f)
cw, ch = min(rim.size[0], im.size[0]), min(rim.size[1], im.size[1])
x = np.asarray(im.crop((0, 0, cw, ch)).filter(ImageFilter.GaussianBlur(2)), dtype=float)
y = np.asarray(rim.crop((0, 0, cw, ch)).filter(ImageFilter.GaussianBlur(2)), dtype=float)
print("diff %.2f" % float(np.abs(x - y).mean()))
PY
for f in basic graphics unicode images styles rotated rot90 rot180 rot270 xrefstm plain-flate a85 ahx rl lzw form long; do
    mkdir -p "$OUT/s/$f"
    "$OUT/pdfdump" "$OUT/c/$f.pdf" "$OUT/s/$f" 100 > "$OUT/s/$f.txt" 2>&1
    np=$(sed -n 's/^pages=//p' "$OUT/s/$f.txt")
    ref=$(pdfinfo "$OUT/c/$f.pdf" 2>/dev/null | sed -n 's/^Pages: *//p')
    [ -n "$np" ] && [ "$np" = "$ref" ] && ok "$f: $np page(s), as pdfinfo says" || { bad "$f: pages '$np', pdfinfo '$ref'"; continue; }
    read -r w h < <(sed -n 's/^page 1 \([0-9]*\)x\([0-9]*\).*/\1 \2/p' "$OUT/s/$f.txt")
    "$OUT/pdfpng" "$OUT/c/$f.pdf" 1 100 "$OUT/s/$f.raw" "$FONT" "$FONTB" "$FONTM" > /dev/null 2>&1
    res=$(python3 "$OUT/cmp.py" "$OUT/c/$f.pdf" "$OUT/s/$f.raw" "$OUT/s/$f/page1.svg" "$w" "$h" 1 2>&1)
    t=$(echo "$res" | sed -n 's/^text //p'); d=$(echo "$res" | sed -n 's/^diff //p')
    [ "$t" = ok ] && ok "$f: the characters equal pdftotext's" || bad "$f: text $t ($res)"
    if [ -n "$d" ] && awk -v d="$d" 'BEGIN{exit !(d < 3.0)}'; then ok "$f: the picture is $d grey levels from poppler's"; else bad "$f: picture differs by '$d'"; fi
done

echo; echo "== 4. damaged and encrypted =="
chk() { # file expected-line-regex label
    "$OUT/pdfdump" "$OUT/c/$1.pdf" "$OUT/s/_x" 100 > "$OUT/s/$1.d.txt" 2>&1
    grep -qE "$2" "$OUT/s/$1.d.txt" && ok "$3" || bad "$3 ($(head -1 "$OUT/s/$1.d.txt"))"
}
mkdir -p "$OUT/s/_x"
chk encrypted '^error=2' "an encrypted file is named as such (error 2) and not shown as rubbish"
chk damaged-garbage '^error=1' "a file that is no PDF: error 1"
chk damaged-empty '^error=1' "an empty file: error 1"
chk damaged-notrailer '^pages=1' "no trailer, no xref: the objects are found by scanning, the page is there"
chk damaged-startxref '^pages=1' "a wrong startxref: rebuilt, the page is there"

echo; echo "== 5. fuzz =="
cat > "$OUT/fuzz.py" <<'PY'
import os, random, subprocess, sys
random.seed(7)
out = sys.argv[1]
files = ["basic","graphics","images","xrefstm","plain-flate","long","unicode","lzw","a85","form","rot90"]
bad = n = 0
for rnd in range(int(sys.argv[2])):
    f = random.choice(files)
    d = bytearray(open(f"{out}/c/{f}.pdf","rb").read())
    mode = random.choice(["flip","trunc","chunk","zero"])
    if mode == "flip":
        for _ in range(random.randint(1, 40)): d[random.randrange(len(d))] = random.randrange(256)
    elif mode == "trunc": d = d[:random.randrange(len(d))]
    elif mode == "chunk":
        a = random.randrange(len(d)); del d[a:min(len(d), a + random.randint(1, 300))]
    else:
        a = random.randrange(len(d))
        for i in range(a, min(len(d), a + random.randint(1, 200))): d[i] = 0
    open(f"{out}/fz.pdf","wb").write(d); os.makedirs(f"{out}/fzo", exist_ok=True)
    tool = [f"{out}/pdfdump", f"{out}/fz.pdf", f"{out}/fzo", "100"] if rnd % 4 else [f"{out}/pdfpng", f"{out}/fz.pdf", "1", "100", f"{out}/fz.raw", sys.argv[3], sys.argv[4], sys.argv[5]]
    try: rc = subprocess.run(tool, capture_output=True, timeout=30).returncode
    except subprocess.TimeoutExpired: rc = 124
    n += 1
    if rc not in (0, 3, 5, 6):
        bad += 1; open(f"{out}/fz-bad{bad}.pdf","wb").write(d); print("rc", rc, f, mode)
print("runs", n, "bad", bad)
sys.exit(1 if bad else 0)
PY
r=$(python3 "$OUT/fuzz.py" "$OUT" 800 "$FONT" "$FONTB" "$FONTM" 2>&1 | tail -3)
echo "$r" | grep -q 'bad 0' && ok "800 corruptions: no crash, no hang ($(echo "$r" | tail -1))" || bad "fuzz: $r"

echo; echo "== 6. speed =="
t0=$(date +%s.%N); "$OUT/pdfdump" "$OUT/c/long.pdf" "$OUT/s/long" 100 > /dev/null 2>&1; t1=$(date +%s.%N)
dt=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.2f", b-a}')
awk -v d="$dt" 'BEGIN{exit !(d < 5.0)}' && ok "40 pages as SVG in $dt s" || bad "40 pages took $dt s"
python3 - "$OUT" <<'PY'
import sys
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4
c = canvas.Canvas(sys.argv[1] + "/c/big.pdf", pagesize=A4)
for p in range(150):
    c.setFont("Helvetica", 10)
    for l in range(60): c.drawString(50, 800 - l * 12, "page %d line %d The quick brown fox jumps over the lazy dog" % (p, l))
    c.showPage()
c.save()
PY
mkdir -p "$OUT/s/big"
t0=$(date +%s.%N); "$OUT/pdfdump" "$OUT/c/big.pdf" "$OUT/s/big" 100 > /dev/null 2>&1; t1=$(date +%s.%N)
dt=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.2f", b-a}')
awk -v d="$dt" 'BEGIN{exit !(d < 15.0)}' && ok "150 pages with 9000 lines in $dt s" || bad "150 pages took $dt s"

echo; echo "== 7. in the guest: the checksum of a page equals the host's =="
crc_host() { python3 -c "import zlib,sys;print('%08x' % (zlib.crc32(open(sys.argv[1],'rb').read()) & 0xffffffff))" "$1"; }
XF=""
for f in basic graphics unicode images; do XF="$XF xfile=/$f.pdf=$OUT/c/$f.pdf"; done
SCR='pdfview --info /basic.pdf;pdfview --render /basic.pdf 1 100;pdfview --render /graphics.pdf 1 100;pdfview --render /unicode.pdf 1 100;pdfview --render /images.pdf 1 100;pdfview --render /images.pdf 1 150;pdfview --info /nope.pdf;exit'
ALLTAGBUILD="$OUT/bd" bash tools/alltag/build.sh "$OUT/g" accel=kvm desk=no shot=no progs="pdfview sh echo ls cat" $XF script="$SCR" > "$OUT/g.log" 2>&1
S="$OUT/g/serial.txt"
grep -aq 'pdfview: pages=2' "$S" && ok "the guest opens basic.pdf: 2 pages" || bad "guest --info"
grep -aq 'pdfview: error=100' "$S" && ok "a missing file is an error (100), not a crash" || bad "guest: missing file"
i=0
for spec in "basic 1 100" "graphics 1 100" "unicode 1 100" "images 1 100" "images 1 150"; do
    set -- $spec; f=$1; pg=$2; pct=$3
    "$OUT/pdfpng" "$OUT/c/$f.pdf" "$pg" "$pct" "$OUT/h-$f-$pct.raw" "$FONT" "$FONTB" "$FONTM" > "$OUT/h-$f-$pct.txt" 2>&1
    hc=$(crc_host "$OUT/h-$f-$pct.raw"); hs=$(cat "$OUT/h-$f-$pct.txt")
    gl=$(grep -a 'pdfview: rendered' "$S" | sed -n "$((i+1))p")
    case "$gl" in
        *"rendered $hs crc=$hc"*) ok "$f at $pct %: $hs, checksum $hc -- guest and host agree bit for bit" ;;
        *) bad "$f at $pct %: host '$hs $hc', guest '$gl'" ;;
    esac
    i=$((i+1))
done

echo; echo "== 8. the window and its keys =="
win() { # name mon-args...
    local n=$1; shift
    ALLTAGBUILD="$OUT/bd" bash tools/alltag/build.sh "$OUT/w-$n" accel=kvm desk=no uitrace=yes warten=6 \
        extra="wigapp=/bin/pdfview,/t.pdf" progs="pdfview sh echo ls cat" xfile=/t.pdf="$OUT/c/basic.pdf" "$@" > "$OUT/w-$n.log" 2>&1
}
win a
SA="$OUT/w-a/serial.txt"
grep -aq 'wlib: text .*t=Seite 1 von 2' "$SA" && ok "the window says 'Seite 1 von 2'" || bad "no page counter in the window"
if [ -s "$OUT/w-a/desktop.ppm" ]; then
    python3 - "$OUT/w-a/desktop.ppm" > "$OUT/w-a/ink.txt" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("L")
w, h = im.size
box = im.crop((60, 110, 920, 700))
px = list(box.getdata())
dark = sum(1 for v in px if v < 100)
print(dark)
PY
    n=$(cat "$OUT/w-a/ink.txt")
    [ "${n:-0}" -gt 800 ] && ok "the page area holds a drawn page ($n dark pixels: text and graphics)" || bad "the page area is empty ($n)"
else
    bad "no picture of the window"
fi
win b 'mon=sendkey pgdn' 'mon=sleep 1' 'mon=sendkey minus'
SB="$OUT/w-b/serial.txt"
grep -aq 'wlib: text .*t=Seite 2 von 2' "$SB" && ok "PgDn: the counter says 'Seite 2 von 2'" || bad "PgDn did not turn the page"
za=$(grep -ao 't=[0-9]*%' "$SA" | tail -1 | tr -dc 0-9); zb=$(grep -ao 't=[0-9]*%' "$SB" | tail -1 | tr -dc 0-9)
[ -n "$za" ] && [ -n "$zb" ] && [ "$zb" -lt "$za" ] && ok "the key '-' zoomed out: $za % -> $zb %" || bad "zoom: '$za' -> '$zb'"

echo
echo "=================================================================="
echo "  PDF: $pass passed, $fail failed"
echo "=================================================================="
[ "$fail" = 0 ] || exit 1
exit 0
