import hashlib, sys

serial, order_file, ref_yuv, src_yuv, w, h = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5]), int(sys.argv[6])
gop, reorder = [int(x) for x in open(sys.argv[7]).read().split()]
fs = w * h * 3 // 2
ref = open(ref_yuv, "rb").read()
src = open(src_yuv, "rb").read()
order = [int(x) for x in open(order_file).read().split()]
n = len(ref) // fs
bad = 0
if n != len(order) or len(src) // fs != n:
    print("frame count mismatch ref=%d src=%d order=%d" % (n, len(src) // fs, len(order)))
    sys.exit(1)
for k, d in enumerate(order):
    a = ref[k * fs:(k + 1) * fs]
    b = src[d * fs:(d + 1) * fs]
    if a != b:
        bad += 1
        print("generator inconsistent at output %d" % k)
def display_index(d):
    if d == 0:
        return 0
    k = (d + 1) // 2
    return 2 * k if d % 2 == 1 else 2 * k - 1


def model_emit_samples(count):
    waiting = []
    epoch = 0
    emitted = []
    for i in range(count):
        d = i % gop
        if d == 0:
            epoch += 1
        waiting.append((epoch, 2 * display_index(d), i))
        while waiting:
            waiting.sort()
            if len(waiting) > reorder or waiting[0][0] < epoch:
                emitted.append(i)
                waiting.pop(0)
            else:
                break
    while waiting:
        emitted.append(count)
        waiting.pop(0)
    return emitted


shas = {}
tags = {}
ats = {}
for line in open(serial, errors="replace"):
    line = line.replace("\r", "").replace("\0", "").strip()
    if line.startswith("vdec: sha "):
        p = line.split()
        shas[int(p[2])] = p[4]
    elif line.startswith("vdec: at "):
        p = line.split()
        ats[int(p[2])] = int(p[4])
    elif line.startswith("vdec: tag "):
        p = line.split()
        tags[int(p[2])] = int(p[4])
wrong_sha = 0
wrong_tag = 0
for k in range(n):
    want = hashlib.sha256(ref[k * fs:(k + 1) * fs]).hexdigest()
    if shas.get(k) != want:
        wrong_sha += 1
    if tags.get(k) != order[k]:
        wrong_tag += 1
want_at = model_emit_samples(n)
wrong_at = sum(1 for k in range(n) if ats.get(k) != want_at[k])
print("frames %d, wrong sha %d, wrong tag %d, wrong latency %d, generator errors %d, extra %d" %
      (n, wrong_sha, wrong_tag, wrong_at, bad, len(shas) - n))
sys.exit(1 if (wrong_sha or wrong_tag or wrong_at or bad or len(shas) != n) else 0)
