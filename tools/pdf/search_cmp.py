#!/usr/bin/env python3
# tools/pdf/search_cmp.py -- the viewer's text search against poppler.
#   search_cmp.py pdfsearch-binary file.pdf [file2.pdf ...]
# Per page: (a) the reader's text with all blanks removed equals pdftotext's with all
# blanks removed (folded the same way); (b) for up to 12 words of the page the number of
# matches equals the number of occurrences in pdftotext's text. Prints `OK n` / `DIFF ...`.
import re, subprocess, sys, unicodedata

def fold(t):
    t = t.replace("­", "").replace("ﬀ", "ff").replace("ﬁ", "fi").replace("ﬂ", "fl")
    t = t.replace("ﬃ", "ffi").replace("ﬄ", "ffl").replace(" ", " ")
    return t.lower()

def squash(t):
    return re.sub(r"\s+", "", fold(t))

binpath = sys.argv[1]
bad = 0
total = 0
for pdf in sys.argv[2:]:
    dump = subprocess.run([binpath, pdf, "--dump", "100"], capture_output=True)
    if dump.returncode != 0:
        print("DIFF %s: pdfsearch exit %d" % (pdf, dump.returncode)); bad += 1; continue
    pages = {}
    for line in dump.stdout.decode("utf-8", "replace").split("\n"):
        m = re.match(r"T (\d+) ?(.*)$", line)
        if m:
            pages[int(m.group(1))] = m.group(2)
    for pg, mine in sorted(pages.items()):
        ref = subprocess.run(["pdftotext", "-raw", "-f", str(pg), "-l", str(pg), pdf, "-"], capture_output=True).stdout.decode("utf-8", "replace")
        total += 1
        a, b = squash(mine), squash(ref)
        # a hyphen joined at a line end is removed by the reader and kept by pdftotext
        b2 = re.sub(r"-(?=\n)", "", fold(ref))
        b2 = re.sub(r"\s+", "", b2)
        if a != b and a != b2:
            bad += 1
            print("DIFF %s page %d text:\n   mine=%r\n   ref =%r" % (pdf, pg, a[:120], b[:120]))
            continue
        words = []
        for w in re.findall(r"[^\W\d_]{3,}", fold(ref)):
            if w not in words:
                words.append(w)
            if len(words) >= 12:
                break
        flat_ref = re.sub(r"\s+", " ", fold(ref)).strip()
        for w in words:
            want = flat_ref.count(w)
            out = subprocess.run([binpath, pdf, w, "100"], capture_output=True).stdout.decode()
            m = re.search(r"^page %d matches=(\d+)" % pg, out, re.M)
            got = int(m.group(1)) if m else -1
            # an occurrence split over a line end may be found by one and not the other
            if got != want and abs(got - want) > 0:
                bad += 1
                print("DIFF %s page %d word %r: mine %d, poppler %d" % (pdf, pg, w, got, want))
print("pages=%d bad=%d" % (total, bad))
sys.exit(1 if bad else 0)
