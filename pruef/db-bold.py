#!/usr/bin/env python3
# BEWEIS: assets/osum-sans-bold.ttf traegt WIRKLICH den fetten Schnitt.
# Nicht "sieht fett aus", sondern: die Umrisse von A, g, eight sind
# BITGLEICH zu DejaVuSans-Bold und VERSCHIEDEN von DejaVuSans (Regular).
# Dazu die Vorschubbreite von A: 1585 (Bold) gegen 1401 (Regular).
import struct, sys

def tabs(d):
    n = struct.unpack('>H', d[4:6])[0]
    t = {}
    for i in range(n):
        o = 12 + 16 * i
        nm = d[o:o+4].decode('latin1')
        off, ln = struct.unpack('>II', d[o+8:o+16])
        t[nm] = (off, ln)
    return t

def cmap_map(d, t):
    off, _ = t['cmap']
    n = struct.unpack('>H', d[off+2:off+4])[0]
    best = None
    for i in range(n):
        o = off + 4 + 8 * i
        pid, eid, so = struct.unpack('>HHI', d[o:o+8])
        if (pid, eid) in ((3, 1), (3, 10), (0, 3), (0, 4)):
            best = off + so
    if best is None:
        best = off + struct.unpack('>I', d[off+8:off+12])[0]
    fmt = struct.unpack('>H', d[best:best+2])[0]
    m = {}
    if fmt == 4:
        segx2 = struct.unpack('>H', d[best+6:best+8])[0]
        sc = segx2 // 2
        e = best + 14
        ends = struct.unpack('>%dH' % sc, d[e:e+segx2])
        s = e + segx2 + 2
        starts = struct.unpack('>%dH' % sc, d[s:s+segx2])
        dl = s + segx2
        deltas = struct.unpack('>%dh' % sc, d[dl:dl+segx2])
        rp = dl + segx2
        ranges = struct.unpack('>%dH' % sc, d[rp:rp+segx2])
        for i in range(sc):
            for c in range(starts[i], min(ends[i], 0xFFFF) + 1):
                if ranges[i] == 0:
                    g = (c + deltas[i]) & 0xFFFF
                else:
                    gi = rp + i*2 + ranges[i] + (c - starts[i]) * 2
                    if gi + 2 > len(d):
                        continue
                    g = struct.unpack('>H', d[gi:gi+2])[0]
                    if g:
                        g = (g + deltas[i]) & 0xFFFF
                if g:
                    m[c] = g
    elif fmt == 12:
        ng = struct.unpack('>I', d[best+12:best+16])[0]
        for i in range(ng):
            o = best + 16 + 12*i
            sc_, ec, sg = struct.unpack('>III', d[o:o+12])
            for c in range(sc_, ec+1):
                m[c] = sg + (c - sc_)
    return m

def glyf_bytes(d, t, gid):
    ho, _ = t['head']
    fmt = struct.unpack('>h', d[ho+50:ho+52])[0]
    lo, ll = t['loca']
    if fmt == 0:
        a = struct.unpack('>H', d[lo+gid*2:lo+gid*2+2])[0] * 2
        b = struct.unpack('>H', d[lo+gid*2+2:lo+gid*2+4])[0] * 2
    else:
        a = struct.unpack('>I', d[lo+gid*4:lo+gid*4+4])[0]
        b = struct.unpack('>I', d[lo+gid*4+4:lo+gid*4+8])[0]
    go, _ = t['glyf']
    return d[go+a:go+b]

def adv(d, t, gid):
    hh, _ = t['hhea']
    num = struct.unpack('>H', d[hh+34:hh+36])[0]
    hm, _ = t['hmtx']
    i = min(gid, num-1)
    return struct.unpack('>H', d[hm+i*4:hm+i*4+2])[0]

def upem(d, t):
    ho, _ = t['head']
    return struct.unpack('>H', d[ho+18:ho+20])[0]

sub = open(sys.argv[1], 'rb').read()
bold = open('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 'rb').read()
reg = open('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 'rb').read()

ts, tb, tr = tabs(sub), tabs(bold), tabs(reg)
cs, cb, cr = cmap_map(sub, ts), cmap_map(bold, tb), cmap_map(reg, tr)
us, ub, ur = upem(sub, ts), upem(bold, tb), upem(reg, tr)

print("Einheiten/Em: subset=%d bold=%d regular=%d" % (us, ub, ur))
print("Glyphen im Subset: %d" % struct.unpack('>H', sub[ts['maxp'][0]+4:ts['maxp'][0]+6])[0])
print()

proben = [('A', 0x41), ('g', 0x67), ('eight', 0x38)]
fehler = 0
for name, cp in proben:
    gs, gb, gr = cs.get(cp), cb.get(cp), cr.get(cp)
    if gs is None or gb is None or gr is None:
        print("%-6s FEHLT (sub=%s bold=%s reg=%s)" % (name, gs, gb, gr))
        fehler += 1
        continue
    bs, bb, br = glyf_bytes(sub, ts, gs), glyf_bytes(bold, tb, gb), glyf_bytes(reg, tr, gr)
    gleich_bold = (bs == bb)
    gleich_reg = (bs == br)
    ok = gleich_bold and not gleich_reg
    print("%-6s Umriss %4d Oktett | == Bold: %-5s | == Regular: %-5s | %s"
          % (name, len(bs), gleich_bold, gleich_reg, "OK" if ok else "FEHLER"))
    if not ok:
        fehler += 1

print()
a_s, a_b, a_r = cs[0x41], cb[0x41], cr[0x41]
ws, wb, wr = adv(sub, ts, a_s), adv(bold, tb, a_b), adv(reg, tr, a_r)
print("Vorschubbreite 'A': subset=%d  Bold=%d  Regular=%d" % (ws, wb, wr))
if ws == wb == 1585 and wr == 1401:
    print("  -> SOLL getroffen (1585 gegen 1401)")
else:
    print("  -> ABWEICHUNG vom Sollwert 1585/1401")
    fehler += 1

print()
print("ERGEBNIS: %s (%d Fehler)" % ("FETTER SCHNITT ECHT" if fehler == 0 else "NICHT BELEGT", fehler))
sys.exit(1 if fehler else 0)
