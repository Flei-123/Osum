#!/usr/bin/env python3
import struct, sys

class Img:
    def __init__(self, path):
        self.f = open(path, 'r+b')
        self.bps = struct.unpack('<H', self.rd(11, 2))[0]
        self.spc = self.rd(13, 1)[0]
        self.cb = self.bps * self.spc
        self.S = struct.unpack('<Q', self.rd(0x28, 8))[0]
        self.C = self.S // self.spc
        self.mft = struct.unpack('<Q', self.rd(0x30, 8))[0] * self.cb
        self.mirr = struct.unpack('<Q', self.rd(0x38, 8))[0] * self.cb
        raw = self.rd(0x40, 1)[0]
        self.rs = raw * self.cb if raw < 128 else 1 << (256 - raw)

    def rd(self, o, n):
        self.f.seek(o)
        return self.f.read(n)

    def wr(self, o, b):
        self.f.seek(o)
        self.f.write(b)

    def load(self, n):
        b = bytearray(self.rd(self.mft + n * self.rs, self.rs))
        ofs, cnt = struct.unpack_from('<HH', b, 4)
        for i in range(1, cnt):
            b[i * 512 - 2:i * 512] = b[ofs + i * 2:ofs + i * 2 + 2]
        return b

    def store(self, n, b):
        ofs, cnt = struct.unpack_from('<HH', b, 4)
        for i in range(1, cnt):
            b[ofs + i * 2:ofs + i * 2 + 2] = b[i * 512 - 2:i * 512]
            b[i * 512 - 2:i * 512] = b[ofs:ofs + 2]
        self.wr(self.mft + n * self.rs, bytes(b))

def attrs(b):
    used = struct.unpack_from('<I', b, 24)[0]
    a = struct.unpack_from('<H', b, 20)[0]
    while a + 16 <= used:
        t, ln = struct.unpack_from('<II', b, a)
        if t == 0xFFFFFFFF:
            return
        yield t, b[a + 9], a, ln
        a += ln

def find(b, kind, name_len):
    for t, nl, off, ln in attrs(b):
        if t == kind and nl == name_len:
            return off, ln
    raise SystemExit('attribute %x not found' % kind)

def find_by_name(im, name):
    name = name.lstrip('/')
    for n in range(16, 256):
        b = im.load(n)
        if b[0:4] != b'FILE':
            continue
        for t, nl, off, ln in attrs(b):
            if t == 0x30:
                vo = struct.unpack_from('<H', b, off + 20)[0]
                nlen = b[off + vo + 64]
                if bytes(b[off + vo + 66:off + vo + 66 + nlen * 2]).decode('utf-16-le') == name:
                    return n
    raise SystemExit('file %s not found' % name)

def put_flags(im, flags):
    b = im.load(3)
    off, ln = find(b, 0x70, 0)
    vo = struct.unpack_from('<H', b, off + 20)[0]
    struct.pack_into('<H', b, off + vo + 10, flags)
    im.store(3, b)
    im.wr(im.mirr + 3 * im.rs, im.rd(im.mft + 3 * im.rs, im.rs))

def log_data_start(im):
    b = im.load(2)
    off, ln = find(b, 0x80, 0)
    ro = struct.unpack_from('<H', b, off + 32)[0]
    h = b[off + ro]
    lb, ob = h & 15, h >> 4
    lcn = int.from_bytes(b[off + ro + 1 + lb:off + ro + 1 + lb + ob], 'little', signed=True)
    return lcn * im.cb

def log_page(im, page, lsn, in_use, flags):
    b = bytearray(512)
    b[0:4] = b'RSTR'
    struct.pack_into('<HH', b, 4, 0x1e, 9)
    struct.pack_into('<II', b, 16, 4096, 4096)
    struct.pack_into('<H', b, 24, 0x30)
    struct.pack_into('<Q', b, 0x30, lsn)
    struct.pack_into('<HH', b, 0x30 + 8, 1, 0xFFFF)
    struct.pack_into('<HH', b, 0x30 + 12, in_use, flags)
    im.wr(log_data_start(im) + page * 4096, bytes(b))

def bad_runs(im, runs):
    b = im.load(8)
    off, ln = find(b, 0x80, 4)
    ro = struct.unpack_from('<H', b, off + 32)[0]
    out = b''
    acc = 0
    for length, lcn in runs:
        lb = max(1, (length.bit_length() + 8) // 8)
        if lcn is None:
            out += bytes([lb]) + length.to_bytes(lb, 'little')
        else:
            d = lcn - acc
            acc = lcn
            ob = max(1, (d.bit_length() + 8) // 8)
            out += bytes([lb | (ob << 4)]) + length.to_bytes(lb, 'little') + d.to_bytes(ob, 'little', signed=True)
    out += b'\0'
    if ro + len(out) > ln:
        raise SystemExit('run list does not fit')
    b[off + ro:off + ln] = out + b'\0' * (ln - ro - len(out))
    im.store(8, b)

def set_rec(im, name, seq=None, flags=None):
    n = find_by_name(im, name)
    b = im.load(n)
    if seq is not None:
        struct.pack_into('<H', b, 16, seq)
    if flags is not None:
        struct.pack_into('<H', b, 22, flags)
    im.store(n, b)

def root_entry(im, target, seq_delta):
    n = find_by_name(im, target)
    seq = struct.unpack_from('<H', im.load(n), 16)[0]
    nm = 'hiberfil.sys'
    key = bytearray(66 + len(nm) * 2)
    key[64] = len(nm)
    key[65] = 1
    key[66:] = nm.encode('utf-16-le')
    elen = (16 + len(key) + 7) // 8 * 8
    ent = bytearray(elen)
    struct.pack_into('<QHHH', ent, 0, n | (((seq + seq_delta) & 0xFFFF) << 48), elen, len(key), 0)
    ent[16:16 + len(key)] = key
    b = im.load(5)
    off, ln = find(b, 0x90, 4)
    vo = struct.unpack_from('<H', b, off + 20)[0]
    vlen = struct.unpack_from('<I', b, off + 16)[0]
    hdr = off + vo + 16
    eoff, ilen, alloc = struct.unpack_from('<III', b, hdr)
    used = struct.unpack_from('<I', b, 24)[0]
    new_ln = (vo + vlen + elen + 7) // 8 * 8
    if used + (new_ln - ln) > struct.unpack_from('<I', b, 28)[0]:
        raise SystemExit('record full')
    head = bytearray(b[off:off + vo + 16 + eoff])
    struct.pack_into('<I', head, 4, new_ln)
    struct.pack_into('<I', head, 16, vlen + elen)
    struct.pack_into('<III', head, vo + 16, eoff, ilen + elen, max(alloc, ilen + elen))
    entries = bytes(b[hdr + eoff:hdr + ilen])
    blob = bytes(head) + bytes(ent) + entries
    blob += b'\0' * (new_ln - len(blob))
    tail = bytes(b[off + ln:used])
    b[off:used + (new_ln - ln)] = blob + tail
    struct.pack_into('<I', b, 24, used + (new_ln - ln))
    im.store(5, b)

def main():
    im = Img(sys.argv[1])
    kind = sys.argv[2]
    arg = sys.argv[3:]
    if kind == 'flags':
        put_flags(im, int(arg[0], 0))
    elif kind == 'log':
        log_page(im, int(arg[0]), int(arg[1]), int(arg[2], 0), int(arg[3], 0))
    elif kind == 'logjunk':
        im.wr(log_data_start(im) + int(arg[0]) * 4096, b'JUNK' + b'\x11' * 508)
    elif kind == 'bad':
        c = im.C
        v = arg[0]
        if v == 'datarun': bad_runs(im, [(c, 100)])
        elif v == 'short': bad_runs(im, [(c - 1, None)])
        elif v == 'split': bad_runs(im, [(c - 1, None), (1, None)])
        elif v == 'long': bad_runs(im, [(c + 1, None)])
    elif kind == 'seq':
        set_rec(im, arg[0], seq=int(arg[1]))
    elif kind == 'free':
        set_rec(im, arg[0], flags=0)
    elif kind == 'rootentry':
        root_entry(im, arg[0], int(arg[1]))
    im.f.close()

main()
