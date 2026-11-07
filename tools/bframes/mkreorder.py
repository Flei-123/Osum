import sys

class Bits:
    def __init__(self, data):
        self.bits = []
        for b in data:
            for i in range(7, -1, -1):
                self.bits.append((b >> i) & 1)
        self.pos = 0

    def u(self, n):
        v = 0
        for _ in range(n):
            v = (v << 1) | self.bits[self.pos]
            self.pos += 1
        return v

    def ue(self):
        z = 0
        while self.u(1) == 0:
            z += 1
        return (1 << z) - 1 + (self.u(z) if z else 0)


class Writer:
    def __init__(self):
        self.bits = []

    def u(self, n, v):
        for i in range(n - 1, -1, -1):
            self.bits.append((v >> i) & 1)

    def ue(self, v):
        v += 1
        n = v.bit_length()
        self.u(n - 1, 0)
        self.u(n, v)

    def extend(self, bits):
        self.bits.extend(bits)

    def finish(self):
        self.bits.append(1)
        while len(self.bits) % 8:
            self.bits.append(0)
        out = bytearray()
        for i in range(0, len(self.bits), 8):
            v = 0
            for b in self.bits[i:i + 8]:
                v = (v << 1) | b
            out.append(v)
        return bytes(out)


def split_nals(data):
    nals = []
    i = 0
    starts = []
    while i + 3 <= len(data):
        if data[i] == 0 and data[i + 1] == 0 and data[i + 2] == 1:
            starts.append(i + 3)
            i += 3
        else:
            i += 1
    for k, s in enumerate(starts):
        e = starts[k + 1] - 3 if k + 1 < len(starts) else len(data)
        while e > s and data[e - 1] == 0:
            e -= 1
        nals.append(data[s:e])
    return nals


def unescape(b):
    out = bytearray()
    zeros = 0
    for x in b:
        if zeros >= 2 and x == 3:
            zeros = 0
            continue
        out.append(x)
        zeros = zeros + 1 if x == 0 else 0
    return bytes(out)


def escape(b):
    out = bytearray()
    zeros = 0
    for x in b:
        if zeros >= 2 and x <= 3:
            out.append(3)
            zeros = 0
        out.append(x)
        zeros = zeros + 1 if x == 0 else 0
    return bytes(out)


def hrd(w):
    w.ue(0)
    w.u(4, 4)
    w.u(4, 6)
    w.ue(12345)
    w.ue(54321)
    w.u(1, 1)
    w.u(5, 23)
    w.u(5, 23)
    w.u(5, 23)
    w.u(5, 23)


def vui(w, kind, reorder):
    if kind == "none":
        w.u(1, 0)
        return
    w.u(1, 1)
    full = kind == "full"
    w.u(1, 1 if full else 0)
    if full:
        w.u(8, 255)
        w.u(16, 4)
        w.u(16, 3)
    w.u(1, 1 if full else 0)
    if full:
        w.u(1, 1)
    w.u(1, 1 if full else 0)
    if full:
        w.u(3, 5)
        w.u(1, 0)
        w.u(1, 1)
        w.u(8, 1)
        w.u(8, 1)
        w.u(8, 1)
    w.u(1, 1 if full else 0)
    if full:
        w.ue(0)
        w.ue(0)
    w.u(1, 1 if full else 0)
    if full:
        w.u(32, 1)
        w.u(32, 20)
        w.u(1, 1)
    w.u(1, 1 if full else 0)
    if full:
        hrd(w)
    w.u(1, 1 if full else 0)
    if full:
        hrd(w)
    if full:
        w.u(1, 0)
    w.u(1, 0)
    w.u(1, 1)
    w.u(1, 1)
    w.ue(2)
    w.ue(1)
    w.ue(16)
    w.ue(16)
    w.ue(reorder)
    w.ue(reorder + 3)


def rewrite_sps(rbsp, kind, reorder, log2poc, profile):
    r = Bits(rbsp[1:])
    r.u(8)
    r.u(8)
    level = r.u(8)
    r.ue()
    log2fn = r.ue() + 4
    poctype = r.ue()
    assert poctype == 2, "source must use poc type 2"
    nref = r.ue()
    r.u(1)
    mbw = r.ue() + 1
    mbh = r.ue() + 1
    assert r.u(1) == 1
    direct8 = r.u(1)
    crop = None
    if r.u(1):
        crop = [r.ue() for _ in range(4)]
    w = Writer()
    w.u(8, profile)
    w.u(8, 0)
    w.u(8, level)
    w.ue(0)
    w.ue(log2fn - 4)
    w.ue(0)
    w.ue(log2poc - 4)
    w.ue(nref)
    w.u(1, 0)
    w.ue(mbw - 1)
    w.ue(mbh - 1)
    w.u(1, 1)
    w.u(1, direct8)
    if crop:
        w.u(1, 1)
        for c in crop:
            w.ue(c)
    else:
        w.u(1, 0)
    vui(w, kind, reorder)
    return bytes([rbsp[0]]) + w.finish(), log2fn


def rewrite_slice(rbsp, log2fn, log2poc, poc_lsb):
    r = Bits(rbsp[1:])
    r.ue()
    r.ue()
    r.ue()
    r.u(log2fn)
    if rbsp[0] & 31 == 5:
        r.ue()
    head = r.pos
    bits = r.bits
    last = len(bits) - 1
    while bits[last] == 0:
        last -= 1
    w = Writer()
    w.extend(bits[:head])
    w.u(log2poc, poc_lsb)
    w.extend(bits[head:last])
    return bytes([rbsp[0]]) + w.finish()


def display_index(d_in_gop):
    if d_in_gop == 0:
        return 0
    k = (d_in_gop + 1) // 2
    return 2 * k if d_in_gop % 2 == 1 else 2 * k - 1


def main():
    src, dst, kind, reorder, gop = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])
    profile = int(sys.argv[6]) if len(sys.argv) > 6 else 77
    log2poc = 4
    nals = split_nals(open(src, "rb").read())
    out = bytearray()
    log2fn = 4
    d = 0
    order = []
    for n in nals:
        t = n[0] & 31
        rb = unescape(n)
        if t == 7:
            rb, log2fn = rewrite_sps(rb, kind, reorder, log2poc, profile)
        elif t in (1, 5):
            if t == 5:
                d = 0
            lsb = (2 * display_index(d)) % (1 << log2poc)
            rb = rewrite_slice(rb, log2fn, log2poc, lsb)
            order.append((len(order), d))
            d += 1
        out += b"\x00\x00\x00\x01" + bytes([rb[0]]) + escape(rb[1:])
    open(dst, "wb").write(bytes(out))
    gops = []
    cur = []
    for idx, dd in order:
        if dd == 0 and cur:
            gops.append(cur)
            cur = []
        cur.append((display_index(dd), idx))
    gops.append(cur)
    print(" ".join(str(i) for g in gops for _, i in sorted(g)))


main()
