# SPDX-License-Identifier: GPL-2.0-only
# Independent reference for tools/wlan/iwlfw.fi + synthetic blob builder.
#   iwlfw_ref.py parse <blob>        -> prints the same RC/SUM/SEC lines as the Firn driver
#   iwlfw_ref.py gen <dir>           -> writes synthetic blobs good.bin and bad_*.bin into <dir>
import struct, sys

SEP_CPU, SEP_PAGING = 0xFFFFCCCC, 0xAAAABBBB
T = dict(FLAGS=18, SEC_RT=19, SEC_INIT=20, PHY_SKU=23, NUM_CPU=27, API=29, CAPA=30, PAGING=32, IML=52, FWVER=37, SEC_WOWLAN=21, CMDVER=48)

def hdr(ver=77, magic=0x0A4C5749):
    return struct.pack('<II64sII', 0, magic, b'synthetic', ver, 1)

def tlv(t, data):
    pad = (-len(data)) & 3
    return struct.pack('<II', t, len(data)) + data + b'\0' * pad

def sec(t, addr, data):
    return tlv(t, struct.pack('<I', addr) + data)

def u32(v): return struct.pack('<I', v)

def good():
    b = hdr()
    b += tlv(T['FLAGS'], u32(0x11)) + tlv(T['PHY_SKU'], u32(0x44)) + tlv(T['NUM_CPU'], u32(2))
    b += tlv(T['API'], u32(0) + u32(0x5)) + tlv(T['API'], u32(1) + u32(0x80)) + tlv(T['API'], u32(0) + u32(0x10))
    b += tlv(T['CAPA'], u32(0) + u32(0x3)) + tlv(T['PAGING'], u32(0x8000))
    b += tlv(999, b'unknown-tlv-ignored')
    b += sec(T['SEC_RT'], 0x00000000, b'L0' * 6) + sec(T['SEC_RT'], 0x00100000, b'L1' * 5)
    b += sec(T['SEC_RT'], SEP_CPU, b'')
    b += sec(T['SEC_RT'], 0x00800000, b'U0abc') + sec(T['SEC_RT'], 0x00800400, b'U1') + sec(T['SEC_RT'], 0x00800800, b'U2xyz')
    b += sec(T['SEC_RT'], SEP_PAGING, b'')
    b += sec(T['SEC_RT'], 0x00000001, b'P0' * 9) + sec(T['SEC_RT'], 0x00000002, b'P1')
    b += sec(T['SEC_INIT'], 0x0, b'IL') + sec(T['SEC_INIT'], SEP_CPU, b'') + sec(T['SEC_INIT'], 0x00800000, b'IU!')
    b += tlv(T['IML'], b'iml-data!')
    b += tlv(T['CMDVER'], bytes([0x0d, 0, 6, 0, 0x18, 5, 3, 0, 0x1c, 0, 5, 1, 0x6a, 0, 0xff, 0, 0x0d, 1, 9, 0]))
    b += tlv(T['SEC_WOWLAN'], u32(0) + b'ignored')
    return b

def parse(d):
    out = []
    if len(d) < 80 or struct.unpack_from('<II', d, 0) != (0, 0x0A4C5749):
        return ['RC -10']
    ver = struct.unpack_from('<I', d, 72)[0]
    f = dict(flags=0, sku=0, cpu=0, api0=0, api1=0, capa0=0, paging=0, iml=(0, 0))
    cv = {}
    secs = {0: [], 1: []}
    ph = {0: 0, 1: 0}
    o, n = 80, 0
    while o < len(d):
        if len(d) - o < 8: return ['RC -11']
        t, l = struct.unpack_from('<II', d, o)
        pad = (l + 3) & ~3
        if pad > len(d) - o - 8: return ['RC -11']
        x = o + 8
        if t in (19, 20):
            img = 0 if t == 19 else 1
            if l < 4: return ['RC -12']
            a = struct.unpack_from('<I', d, x)[0]
            if a == SEP_CPU:
                if ph[img] == 0: ph[img] = 1
            elif a == SEP_PAGING:
                ph[img] = 2
            else:
                if len(secs[img]) >= 32: return ['RC -12']
                secs[img].append((ph[img], x + 4, l - 4, a))
        elif t == 18 and l >= 4: f['flags'] = struct.unpack_from('<I', d, x)[0]
        elif t == 23 and l >= 4: f['sku'] = struct.unpack_from('<I', d, x)[0]
        elif t == 27 and l >= 4: f['cpu'] = struct.unpack_from('<I', d, x)[0]
        elif t == 32 and l >= 4: f['paging'] = struct.unpack_from('<I', d, x)[0]
        elif t == 29 and l >= 8:
            i, v = struct.unpack_from('<II', d, x)
            if i == 0: f['api0'] |= v
            if i == 1: f['api1'] |= v
        elif t == 30 and l >= 8:
            i, v = struct.unpack_from('<II', d, x)
            if i == 0: f['capa0'] |= v
        elif t == 52: f['iml'] = (x, l)
        elif t == 48:
            for q in range(0, l - 3, 4):
                cmd, grp, cver = d[x + q], d[x + q + 1], d[x + q + 2]
                if grp == 0: cv[cmd] = cver
        n += 1
        o = x + pad
    if not secs[0]: return ['RC -13']
    out.append('RC 0')
    out.append('SUM ver=%d tlv=%d flags=%d sku=%d cpu=%d api0=%d capa0=%d paging=%d iml=%d,%d' % (
        ver, n, f['flags'], f['sku'], f['cpu'], f['api0'], f['capa0'], f['paging'], f['iml'][0], f['iml'][1]))
    def cmdver(c):
        if c >> 8 > 1 or cv.get(c & 0xff, 0xff) == 0xff: return None
        return cv[c & 0xff]
    sv = cmdver(0x0d)
    if sv is None: sv = 7 if f['api1'] & 1 else 1
    out.append('CAP api1=%d scanver=%d' % (f['api1'], sv) + ''.join(' c%d=%s' % (c, 'none' if cmdver(c) is None else cmdver(c)) for c in (0x0D, 0x18, 0x1C, 0x6A, 0x10D, 0x50D)))
    for img in (0, 1):
        for i, (k, off, ln, a) in enumerate(secs[img]):
            out.append('SEC %d %d kind=%d off=%d len=%d addr=%d' % (img, i, k, off, ln, a))
    return out

def gen(dr):
    import os
    g = good()
    w = lambda n, b: open(os.path.join(dr, n), 'wb').write(b)
    w('good.bin', g)
    w('bad_trunc.bin', g[:-3])
    w('bad_len.bin', hdr() + struct.pack('<II', 18, 0xFFFFFFF0) + b'\0' * 8)
    w('bad_magic.bin', hdr(magic=0x12345678) + tlv(19, u32(0) + b'x'))
    w('bad_short.bin', b'\0' * 40)
    w('bad_secshort.bin', hdr() + tlv(19, b'\x01\x02'))
    w('bad_nort.bin', hdr() + tlv(18, u32(1)))
    w('bad_toomany.bin', hdr() + b''.join(sec(19, 0x1000 + i, b'dd') for i in range(33)))
    w('adwell.bin', hdr() + tlv(29, u32(1) + u32(1)) + sec(19, 0x1000, b'dd'))
    w('legacy.bin', hdr() + tlv(29, u32(1) + u32(0x2)) + sec(19, 0x1000, b'dd'))
    w('edge_32.bin', hdr() + b''.join(sec(19, 0x1000 + i, b'dd') for i in range(32)))

if __name__ == '__main__':
    if sys.argv[1] == 'gen': gen(sys.argv[2])
    else: print('\n'.join(parse(open(sys.argv[2], 'rb').read())))
