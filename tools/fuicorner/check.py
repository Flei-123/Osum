import sys

def old4(px, py, cx, cy, r):
    rr = r * r
    n = 0
    for iy in range(4):
        for ix in range(4):
            sx = px * 8 + 1 + ix * 2
            sy = py * 8 + 1 + iy * 2
            dx = sx - cx * 8
            dy = sy - cy * 8
            if dx * dx + dy * dy <= rr * 64:
                n += 1
    return n * 255 // 16

def new8(px, py, cx, cy, r):
    rr = r * r
    n = 0
    for iy in range(8):
        for ix in range(8):
            sx = px * 16 + 1 + ix * 2
            sy = py * 16 + 1 + iy * 2
            dx = sx - cx * 16
            dy = sy - cy * 16
            if dx * dx + dy * dy <= rr * 256:
                n += 1
    return (n * 255 + 32) // 64

rows = [tuple(int(v) for v in l.split()) for l in open(sys.argv[1]) if l.strip()]
n = len(rows)
vs_ecke = sum(1 for r, x, y, a, b in rows if a != b)
vs_new8 = sum(1 for r, x, y, a, b in rows if a != new8(x, y, r, r, r))
vs_old4 = sum(1 for r, x, y, a, b in rows if a != old4(x, y, r, r, r))
print("rows=%d vs_ecke=%d vs_ref8=%d vs_ref4=%d" % (n, vs_ecke, vs_new8, vs_old4))
