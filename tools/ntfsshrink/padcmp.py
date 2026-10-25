#!/usr/bin/env python3
import subprocess, sys

mine_img, rs_img, orig_img, newc = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
cat = lambda img: subprocess.run(["ntfscat", "-f", img, "$Bitmap"], capture_output=True).stdout
mine, rs, orig = cat(mine_img), cat(rs_img), cat(orig_img)
d = (((newc + 7) // 8) + 7) // 8 * 8
errs = []
if len(mine) != len(orig):
    errs.append("size changed %d -> %d" % (len(orig), len(mine)))
if mine[:newc // 8] != orig[:newc // 8]:
    errs.append("bits below the new end changed")
for b in range(newc, 8 * d):
    if not mine[b // 8] >> (b % 8) & 1:
        errs.append("padding bit %d is clear" % b); break
if mine[d:] != orig[d:]:
    errs.append("bytes beyond the padding changed")
lo = newc // 8
if rs[lo:d] != mine[lo:d]:
    diff = [i for i in range(lo, d) if rs[i] != mine[i]]
    errs.append("differs from ntfsresize at bytes %s (mine %s rs %s)" % (diff[:6], [mine[i] for i in diff[:6]], [rs[i] for i in diff[:6]]))
if errs:
    print("\n".join(errs)); sys.exit(1)
print("padding of %d clusters equals ntfsresize in bitmap bytes %d.. (to %d) (padding bits %d..%d set)" % (newc, lo, d, newc, 8 * d - 1))
