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
#   4. damaged files: password needed / AES-256 -> error 2, garbage/empty -> error 1, truncated or
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
FONTS="$ROOT/assets/osum-serif.ttf"; FONTSB="$ROOT/assets/osum-serif-bold.ttf"
for t in python3 pdftotext pdftoppm; do
    command -v "$t" >/dev/null 2>&1 || { echo "PDF: skipped, $t is missing"; exit 0; }
done

echo "== 1. build =="
vendor/firn/bin/firnc tools/pdf/pdfdump.fi -o "$OUT/pdfdump" > "$OUT/b1.log" 2>&1 && ok "pdfdump (host driver)" || { bad "pdfdump"; head -5 "$OUT/b1.log"; }
vendor/firn/bin/firnc tools/pdf/pdfpng.fi -o "$OUT/pdfpng" > "$OUT/b2.log" 2>&1 && ok "pdfpng (host driver, the viewer's own render path)" || { bad "pdfpng"; head -5 "$OUT/b2.log"; }
vendor/firn/bin/firnc tools/pdf/pdfsearch.fi -o "$OUT/pdfsearch" > "$OUT/b3.log" 2>&1 && ok "pdfsearch (host driver of the text search, lib/pdfread/pdftext.fi)" || { bad "pdfsearch"; head -5 "$OUT/b3.log"; }

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
for f in basic graphics unicode images styles serif search rotated enc-rc4-40 enc-rc4-128 enc-aes-128 rot90 rot180 rot270 xrefstm plain-flate a85 ahx rl lzw form long; do
    mkdir -p "$OUT/s/$f"
    "$OUT/pdfdump" "$OUT/c/$f.pdf" "$OUT/s/$f" 100 > "$OUT/s/$f.txt" 2>&1
    np=$(sed -n 's/^pages=//p' "$OUT/s/$f.txt")
    ref=$(pdfinfo "$OUT/c/$f.pdf" 2>/dev/null | sed -n 's/^Pages: *//p')
    [ -n "$np" ] && [ "$np" = "$ref" ] && ok "$f: $np page(s), as pdfinfo says" || { bad "$f: pages '$np', pdfinfo '$ref'"; continue; }
    read -r w h < <(sed -n 's/^page 1 \([0-9]*\)x\([0-9]*\).*/\1 \2/p' "$OUT/s/$f.txt")
    "$OUT/pdfpng" "$OUT/c/$f.pdf" 1 100 "$OUT/s/$f.raw" "$FONT" "$FONTB" "$FONTM" "$FONTS" "$FONTSB" > /dev/null 2>&1
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
chk encrypted '^error=2' "a file that needs a password is named as such (error 2) and not shown as rubbish"
chk enc-aes-256 '^error=2' "AES-256 (needs SHA-512, not built) is refused as encrypted (error 2)"
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

echo; echo "== 6b. serif faces: Times text in a Times-metric serif face =="
# the same page rendered without the serif faces (as in an image that does not carry them) and with them,
# each against poppler: the serif faces must bring the picture closer
cat > "$OUT/serifcmp.py" <<'PY'
import glob, os, subprocess, sys
import numpy as np
from PIL import Image, ImageFilter
pdf, raw_a, raw_b, w, h = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])
subprocess.run(["pdftoppm", "-r", "72", "-f", "1", "-l", "1", "-gray", "-png", pdf, "/tmp/_sf"], capture_output=True)
ref = Image.open(sorted(glob.glob("/tmp/_sf-*.png"))[0]).convert("L")
for f in glob.glob("/tmp/_sf-*.png"): os.remove(f)
def d(raw):
    a = np.frombuffer(open(raw, "rb").read(), dtype=np.uint32).reshape(h, w)
    im = Image.fromarray(np.stack([(a >> 16) & 255, (a >> 8) & 255, a & 255], -1).astype("uint8")).convert("L")
    cw, ch = min(ref.size[0], im.size[0]), min(ref.size[1], im.size[1])
    x = np.asarray(im.crop((0, 0, cw, ch)).filter(ImageFilter.GaussianBlur(2)), dtype=float)
    y = np.asarray(ref.crop((0, 0, cw, ch)).filter(ImageFilter.GaussianBlur(2)), dtype=float)
    return float(np.abs(x - y).mean())
print("%.3f %.3f" % (d(raw_a), d(raw_b)))
PY
read -r sw sh_ < <("$OUT/pdfpng" "$OUT/c/serif.pdf" 1 100 "$OUT/serif-sans.raw" "$FONT" "$FONTB" "$FONTM" 2>/dev/null | sed -n 's/\([0-9]*\)x\([0-9]*\)/\1 \2/p')
"$OUT/pdfpng" "$OUT/c/serif.pdf" 1 100 "$OUT/serif-serif.raw" "$FONT" "$FONTB" "$FONTM" "$FONTS" "$FONTSB" > /dev/null 2>&1
read -r da db < <(python3 "$OUT/serifcmp.py" "$OUT/c/serif.pdf" "$OUT/serif-sans.raw" "$OUT/serif-serif.raw" "$sw" "$sh_")
awk -v a="$da" -v b="$db" 'BEGIN{exit !(b < a * 0.6 && b < 1.5)}' && ok "serif.pdf (Times): $da grey levels from poppler in the system face, $db with the serif faces" || bad "serif faces did not bring the picture closer ($da -> $db)"

echo; echo "== 6c. text search: the reader's text and matches against poppler =="
python3 tools/pdf/search_cmp.py "$OUT/pdfsearch" "$OUT/c/basic.pdf" "$OUT/c/unicode.pdf" "$OUT/c/styles.pdf" "$OUT/c/serif.pdf" "$OUT/c/search.pdf" "$OUT/c/rot90.pdf" "$OUT/c/rot180.pdf" "$OUT/c/rot270.pdf" "$OUT/c/long.pdf" "$OUT/c/xrefstm.pdf" "$OUT/c/form.pdf" "$OUT/c/lzw.pdf" "$OUT/c/a85.pdf" > "$OUT/sc.txt" 2>&1 \
    && ok "every page of $(grep -o 'pages=[0-9]*' "$OUT/sc.txt") : the reader's text equals poppler's (blanks aside) and 12 words per page are found exactly as often as poppler says" \
    || { bad "search vs poppler"; head -8 "$OUT/sc.txt"; }
cnt() { "$OUT/pdfsearch" "$OUT/c/search.pdf" "$1" 100 | awk '{split($3,a,"="); s+=a[2]} END{print s+0}'; }
[ "$(cnt wasser)" = 8 ] && ok "'wasser' in search.pdf: 8 matches over three pages (Wasser, wasser, WASSER, Wasserfall; case does not matter)" || bad "wasser: $(cnt wasser)"
[ "$(cnt WASSER)" = 8 ] && ok "the query's case does not matter either (WASSER: 8)" || bad "WASSER: $(cnt WASSER)"
[ "$(cnt trennung)" = 1 ] && ok "'trennung' is found across a hyphen at a line end (Tren-/nung)" || bad "trennung: $(cnt trennung)"
[ "$(cnt "zeilen und einem")" = 1 ] && ok "a phrase across a line break is found (zeilen und einem)" || bad "zeilen und einem: $(cnt "zeilen und einem")"
[ "$(cnt "größe")" = 1 ] && ok "umlauts and sharp s: 'größe' found (UTF-8 query, ToUnicode text)" || bad "größe: $(cnt "größe")"
[ "$(cnt ÜBUNG)" = 1 ] && ok "an upper-case umlaut query finds the lower-case text (ÜBUNG)" || bad "ÜBUNG: $(cnt ÜBUNG)"
[ "$(cnt office)" = 1 ] && [ "$(cnt difficult)" = 1 ] && [ "$(cnt first)" = 1 ] && ok "ligatures: 'office', 'difficult', 'first' are found although the file has ﬁ/ﬃ glyphs" || bad "ligatures: $(cnt office) $(cnt difficult) $(cnt first)"
[ "$(cnt zzzzqq)" = 0 ] && ok "a word that is not there: 0 matches" || bad "zzzzqq: $(cnt zzzzqq)"
[ "$(cnt "")" = 0 ] && ok "an empty query matches nothing" || bad "empty query: $(cnt "")"
# the marks: the picture with the query differs from the one without, only in the matched words, and a
# query with no match leaves the picture as it was
"$OUT/pdfpng" "$OUT/c/search.pdf" 1 100 "$OUT/m0.raw" "$FONT" "$FONTB" "$FONTM" "$FONTS" "$FONTSB" > /dev/null 2>&1
"$OUT/pdfpng" "$OUT/c/search.pdf" 1 100 "$OUT/m1.raw" "$FONT" "$FONTB" "$FONTM" "$FONTS" "$FONTSB" wasser > /dev/null 2>&1
"$OUT/pdfpng" "$OUT/c/search.pdf" 1 100 "$OUT/m2.raw" "$FONT" "$FONTB" "$FONTM" "$FONTS" "$FONTSB" zzzzqq > /dev/null 2>&1
python3 - "$OUT/m0.raw" "$OUT/m1.raw" "$OUT/m2.raw" > "$OUT/m.txt" <<'PY'
import sys
import numpy as np
a, b, c = (np.frombuffer(open(p, "rb").read(), dtype=np.uint32) for p in sys.argv[1:4])
diff = (a != b)
yellow = ((b >> 16) & 255 > 200) & (((b >> 8) & 255) > 180) & ((b & 255) < 120) & diff
print("changed", int(diff.sum()), "yellowish", int(yellow.sum()), "unchanged_for_missing", int((a == c).all()))
PY
read -r _ ch _ yl _ un < "$OUT/m.txt"
[ "$ch" -gt 300 ] && [ "$yl" -gt 200 ] && ok "the matches are marked: $ch pixels changed, $yl of them yellow (the text under them stays black)" || bad "marks: $(cat "$OUT/m.txt")"
[ "$un" = 1 ] && ok "a query without a match leaves the picture untouched" || bad "marks for a missing word: $(cat "$OUT/m.txt")"
# fuzz the search: 300 corruptions, each searched for a word
cat > "$OUT/sfuzz.py" <<'PY'
import os, random, subprocess, sys
random.seed(3)
out = sys.argv[1]
files = ["basic", "search", "serif", "unicode", "xrefstm", "plain-flate", "long", "lzw", "a85", "rot90", "styles"]
bad = 0
for i in range(300):
    f = random.choice(files)
    d = bytearray(open(f"{out}/c/{f}.pdf", "rb").read())
    m = random.choice(["flip", "trunc", "chunk"])
    if m == "flip":
        for _ in range(random.randint(1, 30)): d[random.randrange(len(d))] = random.randrange(256)
    elif m == "trunc": d = d[:random.randrange(len(d))]
    else:
        a = random.randrange(len(d)); del d[a:min(len(d), a + random.randint(1, 300))]
    open(f"{out}/sfz.pdf", "wb").write(d)
    try: rc = subprocess.run([f"{out}/pdfsearch", f"{out}/sfz.pdf", random.choice(["the", "wasser", "a", "ö", "fox"]), "100"], capture_output=True, timeout=30).returncode
    except subprocess.TimeoutExpired: rc = 124
    if rc not in (0, 3): bad += 1; print("rc", rc, f, m)
print("runs 300 bad", bad)
sys.exit(1 if bad else 0)
PY
python3 "$OUT/sfuzz.py" "$OUT" > "$OUT/sfuzz.txt" 2>&1 && ok "300 corrupted files searched: no crash, no hang" || { bad "search fuzz"; tail -3 "$OUT/sfuzz.txt"; }

echo; echo "== 7. in the guest: the checksum of a page equals the host's =="
crc_host() { python3 -c "import zlib,sys;print('%08x' % (zlib.crc32(open(sys.argv[1],'rb').read()) & 0xffffffff))" "$1"; }
XF=""
for f in basic graphics unicode images serif search; do XF="$XF xfile=/$f.pdf=$OUT/c/$f.pdf"; done
XF="$XF xfile=/lib/bold.ttf=$FONTB xfile=/lib/serif.ttf=$FONTS xfile=/lib/serifb.ttf=$FONTSB"
SCR='pdfview --info /basic.pdf;pdfview --render /basic.pdf 1 100;pdfview --render /graphics.pdf 1 100;pdfview --render /unicode.pdf 1 100;pdfview --render /images.pdf 1 100;pdfview --render /images.pdf 1 150;pdfview --render /serif.pdf 1 100;pdfview --render /search.pdf 1 100 wasser;pdfview --render /search.pdf 2 100 wasser;pdfview --info /nope.pdf;exit'
ALLTAGBUILD="$OUT/bd" bash tools/alltag/build.sh "$OUT/g" accel=kvm desk=no shot=no progs="pdfview sh echo ls cat" $XF script="$SCR" > "$OUT/g.log" 2>&1
S="$OUT/g/serial.txt"
grep -aq 'pdfview: pages=2' "$S" && ok "the guest opens basic.pdf: 2 pages" || bad "guest --info"
grep -aq 'pdfview: error=100' "$S" && ok "a missing file is an error (100), not a crash" || bad "guest: missing file"
i=0
for spec in "basic 1 100" "graphics 1 100" "unicode 1 100" "images 1 100" "images 1 150" "serif 1 100" "search 1 100 wasser" "search 2 100 wasser"; do
    set -- $spec; f=$1; pg=$2; pct=$3; q=${4:-}
    "$OUT/pdfpng" "$OUT/c/$f.pdf" "$pg" "$pct" "$OUT/h-$f-$pg-$pct.raw" "$FONT" "$FONTB" "$FONTM" "$FONTS" "$FONTSB" $q > "$OUT/h-$f-$pg-$pct.txt" 2>&1
    hc=$(crc_host "$OUT/h-$f-$pg-$pct.raw"); hs=$(cat "$OUT/h-$f-$pg-$pct.txt")
    gl=$(grep -a 'pdfview: rendered' "$S" | sed -n "$((i+1))p")
    case "$gl" in
        *"rendered $hs crc=$hc"*) ok "$f page $pg at $pct %${q:+ with the query $q marked}: $hs, checksum $hc -- guest and host agree bit for bit" ;;
        *) bad "$f page $pg at $pct %: host '$hs $hc', guest '$gl'" ;;
    esac
    i=$((i+1))
done

echo; echo "== 8. the window and its keys =="
win() { # name mon-args...
    local n=$1; shift
    ALLTAGBUILD="$OUT/bd" bash tools/alltag/build.sh "$OUT/w-$n" accel=kvm desk=no uitrace=yes warten=6 \
        extra="wigapp=/bin/pdfview,/t.pdf${WIN_ARGS:-}" progs="pdfview sh echo ls cat" xfile=/t.pdf="$OUT/c/${WIN_PDF:-basic}.pdf" \
        xfile=/lib/bold.ttf="$FONTB" xfile=/lib/serif.ttf="$FONTS" xfile=/lib/serifb.ttf="$FONTSB" "$@" > "$OUT/w-$n.log" 2>&1
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

# the search in the window: opened with --find, then n n p through the monitor
WIN_PDF=search WIN_ARGS=",--find,wasser" win c 'mon=sleep 1' 'mon=sendkey n' 'mon=sleep 1' 'mon=sendkey n' 'mon=sleep 1' 'mon=sendkey p'
SC="$OUT/w-c/serial.txt"
grep -aq 'wlib: text .*t=Treffer 1 von 8' "$SC" && ok "the window opened with --find: 'Treffer 1 von 8' (the first of eight matches)" || bad "no 'Treffer 1 von 8' in the window"
grep -aq 'wlib: text .*t=Treffer 2 von 8' "$SC" && ok "the key n: 'Treffer 2 von 8'" || bad "no 'Treffer 2 von 8' after n"
grep -aq 'wlib: text .*t=Treffer 3 von 8' "$SC" && ok "n again: 'Treffer 3 von 8'" || bad "no 'Treffer 3 von 8' after n n"
if [ -s "$OUT/w-c/desktop.ppm" ]; then
    python3 - "$OUT/w-c/desktop.ppm" > "$OUT/w-c/hl.txt" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size
px = im.crop((60, 130, 920, 700)).getdata()
yellow = sum(1 for r, g, b in px if r > 200 and g > 180 and b < 140)
orange = sum(1 for r, g, b in px if r > 200 and 100 < g < 170 and b < 90)
print(yellow, orange)
PY
    read -r yel ora < "$OUT/w-c/hl.txt"
    [ "${yel:-0}" -gt 100 ] && [ "${ora:-0}" -gt 50 ] && ok "the picture shows the marks: $yel yellow and $ora orange (current match) pixels" || bad "no marks in the window picture (yellow $yel, orange $ora)"
else
    bad "no picture of the search window"
fi

echo
echo "=================================================================="
echo "  PDF: $pass passed, $fail failed"
echo "=================================================================="
[ "$fail" = 0 ] || exit 1
exit 0
