# SPDX-License-Identifier: GPL-2.0-only
# Independent reference for tools/wlan/fh8000.fi (family 8000 FH chunk loader, HP-9a).
#   fh8000_ref.py gen <dir>   -> writes <name>.case (16-octet config + synthetic ucode) and <name>.exp
# The expected output follows the Linux loader LITERALLY (raw section list WITH the separator markers,
# last_read_idx handling of iwl_pcie_load_cpu_sections_8000), not the FwInfo view the Firn library uses.
# Case header: u32 bounce size, u32 mode (0 normal, 1 completion interrupt lost), u64 bus address.
import os, struct, sys

sys.dont_write_bytecode = True
SEP_CPU, SEP_PAGING = 0xFFFFCCCC, 0xAAAABBBB
FH_STATUS, CFG_RUN, BUFSTS = 0x1AF0, 0x80100000, 0x00101003
EXT_START, EXT_END = 0x40000, 0x57FFF
MAXCHUNK, MASK32 = 0x20000, 0xFFFFFFFF


def u32(v): return struct.pack('<I', v)


def tlv(t, d): return struct.pack('<II', t, len(d)) + d + b'\0' * ((-len(d)) & 3)


def hdr(): return struct.pack('<II64sII', 0, 0x0A4C5749, b'synthetic', 77, 1)


def data(n, seed):
    return bytes(((i * 7 + seed * 13) % 251) + 1 for i in range(n))      # never zero


def build(secs):
    """secs: list of (addr_or_separator, bytes)."""
    b = hdr() + tlv(18, u32(0x11)) + tlv(27, u32(2))
    for a, d in secs:
        b += tlv(19, u32(a) + d)
    return b


def expected(secs, bsize, mode, phys):
    """-> list of output lines"""
    out = []
    W = lambda off, v: out.append('W 0x%x 0x%x' % (off, v & MASK32))
    P = lambda a, v: out.append('P 0x%x 0x%x' % (a & 0xFFFFF, v & MASK32))
    # FwInfo-style index (separators do not count), as the library reports fail_sec
    fidx, k = {}, 0
    for i, (a, d) in enumerate(secs):
        if a not in (SEP_CPU, SEP_PAGING):
            fidx[i] = k
            k += 1
    sram = {}
    st = dict(chunks=0, bytes=0, ext=0, cpu1=0, cpu2=0)
    state = dict(status=0, chick=0, rc=0, failsec=0, lost=0)
    # guards of the library (not Linux): CPU1 present, <= 16 per CPU, no empty section
    cpu, n_l, n_u = 0, 0, 0
    for a, d in secs:
        if a == SEP_CPU: cpu = max(cpu, 1)
        elif a == SEP_PAGING: cpu = 2
        elif cpu == 0: n_l += 1
        elif cpu == 1: n_u += 1
    empties = [fidx[i] for i, (a, d) in enumerate(secs) if a not in (SEP_CPU, SEP_PAGING) and len(d) == 0 and not paging_at(secs, i)]
    guard = 0
    if bsize < 4096: guard = -40
    elif n_l == 0: guard = -41
    elif n_l > 16 or n_u > 16: guard = -42
    elif empties: guard, state['failsec'] = -43, empties[0]
    if guard:
        return finish(out, guard, state, st, sram)
    W(0x00C, 0x08000000)
    W(0x05C, 2); W(0x05C, 2)
    P(0xA030B4, 0x01010101)
    P(0x300C, 0x01000000)

    def load_section(i):
        a, d = secs[i]
        csz = min(MAXCHUNK, len(d), bsize)
        off = 0
        while off < len(d):
            n = min(csz, len(d) - off)
            dst = a + off
            ext = EXT_START <= dst <= EXT_END
            if ext:
                state['chick'] |= 1; P(0xA01FF8, state['chick']); st['ext'] += 1
            W(0x008, 0x08000000)
            W(0x1E20, 0); W(0x19C8, dst); W(0x1948, phys & MASK32)
            W(0x194C, (((phys >> 32) & 0xF) << 28) | n); W(0x1E28, BUFSTS); W(0x1E20, CFG_RUN)
            for j in range(n): sram[dst + j] = d[off + j]
            if mode == 1:
                state['rc'], state['failsec'] = -45, fidx[i]
                if ext:
                    state['chick'] &= ~1; P(0xA01FF8, state['chick'])
                return False
            W(0x010, 3); W(0x008, 0x08000000)
            if ext:
                state['chick'] &= ~1; P(0xA01FF8, state['chick'])
            st['chunks'] += 1; st['bytes'] += n
            off += n
        return True

    first = 0
    for cpuno in (1, 2):
        shift = 0 if cpuno == 1 else 16
        if cpuno == 1: first = 0
        else: first += 1
        last, secnum, k = 0, 1, 0
        i = first
        while i < len(secs):
            last = i
            a, d = secs[i]
            if a in (SEP_CPU, SEP_PAGING): break
            if not load_section(i):
                return finish(out, state['rc'], state, st, sram)
            state['status'] |= (secnum << shift) & MASK32
            W(FH_STATUS, state['status'])
            secnum = (secnum << 1) | 1
            k += 1
            i += 1
        first = last
        st['cpu%d' % cpuno] = k
        W(0x00C, 0xBA00008F)
        state['status'] = 0xFFFF if cpuno == 1 else 0xFFFFFFFF
        W(FH_STATUS, state['status'])
    return finish(out, 0, state, st, sram)


def paging_at(secs, i):
    """True when secs[i] lies behind the paging separator (never loaded, may be empty)."""
    return any(a == SEP_PAGING for a, d in secs[:i])


def finish(out, rc, state, st, sram):
    nz = sum(1 for v in sram.values() if v)
    dig = sum(v * ((a % 251) + 1) for a, v in sram.items()) & MASK32
    out.append('RC %d FAILSEC %d' % (rc, state['failsec']))
    out.append('STAT chunks=%d bytes=%d ext=%d cpu1=%d cpu2=%d' % (st['chunks'], st['bytes'], st['ext'], st['cpu1'], st['cpu2']))
    out.append('LOADSTAT 0x%x' % state['status'])
    out.append('CHICK 0x%x' % state['chick'])
    out.append('VIOL 0 LOST 0 NONZERO %d DIGEST 0x%x' % (nz, dig))
    return out


CASES = {}


def case(name, secs, bsize=0x20000, mode=0, phys=0x1000):
    CASES[name] = (secs, bsize, mode, phys)


def mk():
    c1 = [(0x00000, data(100, 1)), (0x10000, data(5000, 2)), (0x20000, data(0x20001, 3)),
          (SEP_CPU, b''),
          (0x60000, data(3000, 4)), (0x57000, data(0x3000, 5)),
          (SEP_PAGING, b''), (0x70000, data(4000, 6))]
    case('c1_big', c1)
    case('c1_page', c1, bsize=4096, phys=0x300001000)
    case('c1_hi15', c1, bsize=0x20000, phys=0xFFFFFF000)
    case('c1_odd', c1, bsize=5000, phys=0x2000)
    case('c2_exact', [(0x0, data(0x20000, 1)), (0x20000, data(0x20000, 2)), (SEP_CPU, b''), (0x80000, data(0x40000, 3))])
    case('cb_bigbuf', [(0x0, data(0x20000, 1)), (0x20000, data(0x20000, 2)), (SEP_CPU, b''), (0x80000, data(0x40000, 3))], bsize=0x40000)
    case('cc_edges', [(0x3FFFF, data(5, 1)), (0x40000, data(5, 2)), (0x57FFF, data(5, 3)), (0x58000, data(5, 4)), (0x57FFE, data(2, 5))])
    case('c3_single', [(0x100, data(300, 1)), (0x5000, data(777, 2))])
    case('c4_16', [(0x1000 * i, data(10, i)) for i in range(16)] + [(SEP_CPU, b''), (0x20000, data(10, 9))])
    case('c5_17', [(0x1000 * i, data(10, i)) for i in range(17)] + [(SEP_CPU, b''), (0x20000, data(10, 9))])
    case('c6_empty', [(0x0, data(40, 1)), (SEP_CPU, b''), (0x2000, data(40, 2)), (0x3000, b'')])
    case('c7_nocpu1', [(SEP_CPU, b''), (0x2000, data(40, 2))])
    case('c8_lost_irq', c1, mode=1)
    case('c8_lost_ext', [(0x40000, data(500, 1))], mode=1)
    case('c9_tiny', c1, bsize=100)
    case('ca_only_ext', [(0x40000, data(0x1800, 1)), (SEP_CPU, b''), (0x50000, data(0x9000, 2))], bsize=4096)


def gen(d):
    mk()
    for name, (secs, bsize, mode, phys) in CASES.items():
        blob = build(secs)
        open(os.path.join(d, name + '.case'), 'wb').write(struct.pack('<IIQ', bsize, mode, phys) + blob)
        open(os.path.join(d, name + '.exp'), 'w').write('\n'.join(expected(secs, bsize, mode, phys)) + '\n')


def real_secs(path):
    """REAL Intel ucode (not committed): TLV walk, SEC_RT (type 19) sections incl. separators, in file order."""
    b = open(path, 'rb').read()
    if struct.unpack_from('<II', b, 0) != (0, 0x0A4C5749): raise SystemExit('not a ucode file')
    o, secs = 80, []
    while o + 8 <= len(b):
        t, n = struct.unpack_from('<II', b, o)
        d = b[o + 8:o + 8 + n]
        if t == 19: secs.append((struct.unpack_from('<I', d, 0)[0], d[4:]))
        o += 8 + n + ((-n) & 3)
    return secs


def gen_real(path, d):
    secs = real_secs(path)
    for name, bsize, phys in (('real_128k', 0x20000, 0x1000), ('real_4k', 4096, 0x300001000)):
        open(os.path.join(d, name + '.case'), 'wb').write(struct.pack('<IIQ', bsize, 0, phys) + open(path, 'rb').read())
        open(os.path.join(d, name + '.exp'), 'w').write('\n'.join(expected(secs, bsize, 0, phys)) + '\n')


if __name__ == '__main__':
    if sys.argv[1] == 'gen': gen(sys.argv[2])
    elif sys.argv[1] == 'real': gen_real(sys.argv[2], sys.argv[3])
