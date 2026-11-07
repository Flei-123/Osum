import hashlib, sys

serial, ref_yuv, w, h = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
fs = w * h * 3 // 2
ref = open(ref_yuv, "rb").read()
n = len(ref) // fs
shas = {}
for line in open(serial, errors="replace"):
    line = line.replace("\r", "").replace("\0", "").strip()
    if line.startswith("vdec: sha "):
        p = line.split()
        shas[int(p[2])] = p[4]
wrong = [k for k in range(n) if shas.get(k) != hashlib.sha256(ref[k * fs:(k + 1) * fs]).hexdigest()]
print("frames %d, wrong sha %d (first %s), extra %d" % (n, len(wrong), wrong[:6], len(shas) - n))
sys.exit(1 if wrong or len(shas) != n else 0)
