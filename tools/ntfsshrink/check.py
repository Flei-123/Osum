#!/usr/bin/env python3
import re, subprocess, sys, struct

def kvs(path):
    d = {}
    lines = []
    for line in open(path):
        line = line.strip()
        lines.append(line)
        m = re.fullmatch(r"(\w+)=(\d+)", line)
        if m:
            d[m.group(1)] = int(m.group(2))
    return d, lines

def run(*a):
    return subprocess.run(a, capture_output=True).stdout

def info(img):
    t = run("ntfsinfo", "-m", img).decode()
    g = lambda k: int(re.search(re.escape(k) + r":\s*(\d+)", t).group(1))
    return {
        "bps": g("Sector Size"), "cb": g("Cluster Size"), "idx_size": g("Index Block Size"),
        "clusters": g("Volume Size in Clusters"), "rec_size": g("MFT Record Size"),
        "mft_lcn": g("LCN of Data Attribute for FILE_MFT"), "mirr_lcn": g("LCN of Data Attribute for File_MFTMirr"),
    }

def used_end(bm, c):
    last = 0
    for i in range(c):
        if bm[i // 8] >> (i % 8) & 1:
            last = i + 1
    return last

def main():
    img, outp = sys.argv[1], sys.argv[2]
    d, lines = kvs(outp)
    bad = []
    def need(name, ok):
        if not ok:
            bad.append(name)
    need("open", d.get("open") == 0)
    oi = info(img)
    for k, v in oi.items():
        need("%s %s!=%s" % (k, d.get(k), v), d.get(k) == v)
    raw = open(img, "rb").read(512)
    need("serial", d.get("serial") == struct.unpack_from("<Q", raw, 0x48)[0])
    need("spc*bps=cb", d.get("spc", 0) * d.get("bps", 0) == oi["cb"])
    need("mft_load", d.get("mft_load") == 0)
    need("mft_size", d.get("mft_size", 1) % oi["rec_size"] == 0 and d.get("mft_size", 0) >= 16 * oi["rec_size"])
    for n in range(16):
        l = [x for x in lines if x.startswith("rec %d " % n)]
        need("rec %d" % n, bool(l) and "code=0" in l[0] and "rewrite=0" in l[0] and "same=1" in l[0] and "flags=" in l[0])
    for n in range(4):
        l = [x for x in lines if x.startswith("mirror %d " % n)]
        need("mirror %d" % n, bool(l) and "codes=0" in l[0] and "eq=1" in l[0])
    bm = run("ntfscat", img, "$Bitmap")
    c = oi["clusters"]
    need("bm_real", d.get("bm_real") == len(bm))
    need("used_end %s!=%s" % (d.get("used_end"), used_end(bm, c)), d.get("used_end") == used_end(bm, c))
    need("bit0", d.get("bit0") == 1 and d.get("bit0_code") == 0)
    need("bytes_for_c", d.get("bytes_for_c") == (((c + 7) // 8) + 7) // 8 * 8)
    need("bad run", d.get("bad_first") == 1 and d.get("bad_sparse") == 1 and d.get("bad_len") == c and d.get("bad_total") == c)
    print("\n".join(bad) if bad else "ALLOK")
    sys.exit(1 if bad else 0)

main()
