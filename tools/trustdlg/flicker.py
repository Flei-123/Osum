#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import hashlib, os, socket, sys, time


def dump(sock, path):
    if os.path.exists(path):
        os.unlink(path)
    sock.sendall(("screendump %s\n" % path).encode())
    last = -1
    for _ in range(200):
        time.sleep(0.02)
        if os.path.exists(path):
            n = os.path.getsize(path)
            if n > 0 and n == last:
                return True
            last = n
    return False


def crop(path, x, y, w, h):
    with open(path, "rb") as f:
        data = f.read()
    parts = data.split(b"\n", 3)
    W, H = [int(v) for v in parts[1].split()]
    pix = parts[3]
    rows = []
    for yy in range(y, min(y + h, H)):
        o = (yy * W + x) * 3
        rows.append(pix[o:o + min(w, W - x) * 3])
    return b"".join(rows)


def main():
    sockp, wd, x, y, w, h, n = sys.argv[1], sys.argv[2], *[int(v) for v in sys.argv[3:8]]
    s = socket.socket(socket.AF_UNIX)
    s.connect(sockp)
    s.settimeout(2)
    try:
        s.recv(4096)
    except Exception:
        pass
    crops = []
    for i in range(n):
        p = os.path.join(wd, "fl-%d.ppm" % (i % 2))
        if not dump(s, p):
            continue
        try:
            crops.append(crop(p, x, y, w, h))
        except Exception:
            pass
        try:
            s.recv(65536)
        except Exception:
            pass
    if not crops:
        print("flicker: samples=0")
        return
    cnt = {}
    for c in crops:
        k = hashlib.md5(c).hexdigest()
        cnt.setdefault(k, [0, c])[0] += 1
    ref = max(cnt.values(), key=lambda v: v[0])[1]
    odd = 0
    worst = 0
    for c in crops:
        if c != ref:
            odd += 1
            d = sum(1 for i in range(0, min(len(c), len(ref)), 3) if c[i:i + 3] != ref[i:i + 3])
            worst = max(worst, d)
    print("flicker: samples=%d odd=%d distinct=%d worst_px=%d" % (len(crops), odd, len(cnt), worst))
    for i in range(2):
        try:
            os.unlink(os.path.join(wd, "fl-%d.ppm" % i))
        except OSError:
            pass


main()
