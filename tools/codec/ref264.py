#!/usr/bin/env python3
"""Referenz-Dekodierer h.264 Baseline (Python).

DAS IST DAS VERSUCHSGERAET, NICHT DER LIEFERGEGENSTAND. Hier werden die
Algorithmen bitgenau gegen ffmpeg geprueft, BEVOR sie in Firn entstehen --
in Python kostet ein Fehlversuch Sekunden, in Firn einen Kernelbau.
Jede Funktion hat ihr Gegenstueck in kernel/user/h264.fi.

Die CAVLC-Tafeln kommen MECHANISCH aus tabs.json (aus FFmpegs
h264_cavlc.c gezogen, auf Praefixfreiheit geprueft) -- nicht abgetippt.
"""
import json, os, sys

TB = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                 'tabs.json')))

# =========================================================== der Bitleser
class BR:
    """Annex-B-Bitleser. Hinter dem Ende kommen Nullen und `over` steht."""
    def __init__(s, d):
        s.d = d; s.p = 0; s.n = len(d) * 8; s.over = False
    def u1(s):
        if s.p >= s.n:
            s.over = True; s.p += 1; return 0
        b = (s.d[s.p >> 3] >> (7 - (s.p & 7))) & 1
        s.p += 1; return b
    def un(s, k):
        v = 0
        for _ in range(k): v = (v << 1) | s.u1()
        return v
    def ue(s):
        z = 0
        while z < 32 and s.u1() == 0: z += 1
        if z >= 32: s.over = True; return 0
        return (1 << z) - 1 + (s.un(z) if z else 0)
    def se(s):
        k = s.ue()
        return (k + 1) // 2 if (k & 1) else -(k // 2)
    def more(s):
        if s.p >= s.n: return False
        last = s.n - 1
        while last > s.p and ((s.d[last >> 3] >> (7 - (last & 7))) & 1) == 0:
            last -= 1
        return s.p < last
    def show(s, k):
        """k Bits ansehen, ohne zu verbrauchen (fuer die Tafeln)."""
        save = s.p; v = s.un(k); s.p = save; return v

def nal_split(d):
    """Annex B: alles zwischen zwei Startcodes. Nullen am Ende gehoeren
    zum Startcode des naechsten und nicht zur Einheit."""
    out = []; i = 0; n = len(d)
    while i + 2 < n:
        if d[i] == 0 and d[i+1] == 0 and d[i+2] == 1:
            st = i + 3; j = st
            while j + 2 < n and not (d[j] == 0 and d[j+1] == 0 and d[j+2] == 1):
                j += 1
            e = n if j + 2 >= n else j
            while e > st and d[e-1] == 0: e -= 1
            if e > st: out.append(d[st:e])
            i = j if j + 2 < n else n
        else:
            i += 1
    return out

def rbsp(x):
    """emulation_prevention_three_byte entfernen: 00 00 03 -> 00 00."""
    o = bytearray(); i = 0; n = len(x)
    while i < n:
        if i + 2 < n and x[i] == 0 and x[i+1] == 0 and x[i+2] == 3:
            o += b'\x00\x00'; i += 3
        else:
            o.append(x[i]); i += 1
    return bytes(o)

# ============================================================ die Tafeln
def tab_lookup(br, lens, bits, labels):
    """Ein Code aus einer (Laenge,Wert)-Tafel. Liest bitweise und
    vergleicht -- dieselbe Schleife wie spaeter in Firn."""
    v = 0; ln = 0
    while ln < 17:
        v = (v << 1) | br.u1(); ln += 1
        for i in range(len(lens)):
            if lens[i] == ln and bits[i] == v:
                return labels[i]
    raise ValueError('Code nicht in der Tafel')

CT_LAB = [(t1, tc) for tc in range(17) for t1 in range(4)]
CDC_LAB = [(t1, tc) for tc in range(5) for t1 in range(4)]

def coeff_token(br, nC):
    if nC == -1:
        return tab_lookup(br, TB['chroma_dc_coeff_token_len'],
                          TB['chroma_dc_coeff_token_bits'], CDC_LAB)
    k = 0 if nC < 2 else (1 if nC < 4 else (2 if nC < 8 else 3))
    return tab_lookup(br, TB['coeff_token_len'][k],
                      TB['coeff_token_bits'][k], CT_LAB)

def total_zeros(br, tzidx, maxc):
    if maxc == 4:
        return tab_lookup(br, TB['chroma_dc_total_zeros_len'][tzidx-1],
                          TB['chroma_dc_total_zeros_bits'][tzidx-1],
                          list(range(4)))
    return tab_lookup(br, TB['total_zeros_len'][tzidx-1],
                      TB['total_zeros_bits'][tzidx-1], list(range(16)))

def run_before(br, zl):
    i = min(zl, 7) - 1
    return tab_lookup(br, TB['run_len'][i], TB['run_bits'][i],
                      list(range(len(TB['run_len'][i]))))

# ================================================ Restwerte eines Blocks
ZIGZAG4 = [0,1,4,8,5,2,3,6,9,12,13,10,7,11,14,15]

def _av_log2(x):
    return x.bit_length() - 1 if x > 0 else 0

# DIE WERTETAFEL, GENAU WIE FFMPEG SIE BAUT (init_cavlc_level_tab).
# Sie ist der Grund, warum dieser Dekodierer bitgleich ist: die Norm
# beschreibt in 9.2.2.1 dieselbe Sache in Prosa, und beim Abtippen aus
# der Prosa entstehen genau die Fehler, die erst vier Koeffizienten
# spaeter auffallen. Hier wird die Tafel GERECHNET, nicht abgeschrieben.
LEVEL_TAB_BITS = 8
CAVLC_LEVEL_TAB = []
for _sl in range(7):
    _row = []
    for _i in range(1 << LEVEL_TAB_BITS):
        _prefix = LEVEL_TAB_BITS - _av_log2(2 * _i) if _i > 0 else LEVEL_TAB_BITS
        if _prefix + 1 + _sl <= LEVEL_TAB_BITS:
            _lc = (_prefix << _sl) + (_i >> (_av_log2(_i) - _sl)) - (1 << _sl)
            _mask = -(_lc & 1)
            _lc = (((2 + _lc) >> 1) ^ _mask) - _mask
            _row.append((_lc, _prefix + 1 + _sl))
        elif _prefix + 1 <= LEVEL_TAB_BITS:
            _row.append((_prefix + 100, _prefix + 1))
        else:
            _row.append((LEVEL_TAB_BITS + 100, LEVEL_TAB_BITS))
    CAVLC_LEVEL_TAB.append(_row)

def _level_prefix(br):
    n = 0
    while br.u1() == 0 and n < 32: n += 1
    return n

def residual_block(br, nC, maxc):
    """9.2 -- ein Restwertblock. Liefert die Koeffizienten in
    SCAN-Reihenfolge (Position 0..maxc-1) und totalCoeff.

    Schritt fuer Schritt wie FFmpegs decode_residual, samt der
    Wertetafel oben. Die zwei Wege (kurzer Tafelweg / langer Weg mit
    level_prefix) unterscheiden sich in dem, was danach in
    suffixLength steht -- und genau daran scheitert ein von Hand aus
    der Norm abgeschriebener Dekodierer.
    """
    SUFFIX_LIMIT = [0, 3, 6, 12, 24, 48, 1 << 30]
    out = [0] * maxc
    t1, tc = coeff_token(br, nC)
    if tc == 0: return out, 0
    if tc > maxc: raise ValueError('totalCoeff %d > maxCoeff %d' % (tc, maxc))
    lev = [0] * tc
    for i in range(t1):
        lev[i] = 1 - 2 * br.u1()
    if t1 < tc:
        sl = 1 if (tc > 10 and t1 < 3) else 0
        # ---------------- der erste Wert hinter den Einsen
        bitsi = br.show(LEVEL_TAB_BITS)
        levelCode, used = CAVLC_LEVEL_TAB[sl][bitsi]
        br.p += used
        if levelCode >= 100:
            prefix = levelCode - 100
            if prefix == LEVEL_TAB_BITS:
                prefix += _level_prefix(br)
            if prefix > 28: raise ValueError('level_prefix zu gross')
            if prefix < 14:
                levelCode = (prefix << 1) + br.u1() if sl else prefix
            elif prefix == 14:
                levelCode = (prefix << 1) + br.u1() if sl else prefix + br.un(4)
            else:
                levelCode = 30
                if prefix >= 16: levelCode += (1 << (prefix - 3)) - 4096
                levelCode += br.un(prefix - 3)
            if t1 < 3: levelCode += 2
            sl = 2
            lev[t1] = (levelCode + 2) >> 1 if (levelCode % 2 == 0) \
                      else (-levelCode - 1) >> 1
        else:
            # KURZER WEG: levelCode ist hier schon der fertige WERT.
            if t1 < 3:
                levelCode += 1 if levelCode >= 0 else -1
            # FFmpeg: suffix_length = 1 + (level_code + 3U > 6U).
            # Das U ist wesentlich: in vorzeichenloser Arithmetik ist
            # die Bedingung fuer JEDEN negativen Wert ausser -1,-2,-3
            # wahr -- zusammengenommen heisst die Zeile schlicht
            # |level| > 3. Vorzeichenbehaftet gerechnet kommt fuer
            # negative Werte das Falsche heraus.
            sl = 1 + (1 if abs(levelCode) > 3 else 0)
            lev[t1] = levelCode
        # ---------------- die uebrigen
        for i in range(t1 + 1, tc):
            bitsi = br.show(LEVEL_TAB_BITS)
            levelCode, used = CAVLC_LEVEL_TAB[sl][bitsi]
            br.p += used
            if levelCode >= 100:
                prefix = levelCode - 100
                if prefix == LEVEL_TAB_BITS:
                    prefix += _level_prefix(br)
                if prefix > 28: raise ValueError('level_prefix zu gross')
                if prefix < 15:
                    levelCode = (prefix << sl) + br.un(sl)
                else:
                    levelCode = 15 << sl
                    if prefix >= 16: levelCode += (1 << (prefix - 3)) - 4096
                    levelCode += br.un(prefix - 3)
                levelCode = (levelCode + 2) >> 1 if (levelCode % 2 == 0) \
                            else (-levelCode - 1) >> 1
            lev[i] = levelCode
            # Die Norm (9.2.2.1): suffixLength steigt um eins, sobald
            # |level| die Schranke suffixLimit ueberschreitet.
            # FFmpeg schreibt dafuer eine Zeile in vorzeichenloser
            # C-Arithmetik, die fuer NEGATIVE level immer zutrifft --
            # das ist dort ohne Wirkung, weil die Werte, bei denen es
            # auffiele, nicht vorkommen. Hier steht die Regel der Norm.
            if sl < 6 and abs(levelCode) > SUFFIX_LIMIT[sl]:
                sl += 1
    zerosLeft = 0
    if tc < maxc:
        zerosLeft = total_zeros(br, tc, maxc)
    run = [0] * tc
    for i in range(tc - 1):
        if zerosLeft > 0:
            r = run_before(br, zerosLeft)
            run[i] = r; zerosLeft -= r
        else:
            run[i] = 0
    run[tc-1] = zerosLeft
    cn = -1
    for i in range(tc - 1, -1, -1):
        cn += run[i] + 1
        if cn < maxc: out[cn] = lev[i]
    return out, tc

# ================================================= Skalierung/Transformation
VMAT = [[10,16,13],[11,18,14],[13,20,16],[14,23,18],[16,25,20],[18,29,23]]
def norm_adjust(m, i):
    r, c = i >> 2, i & 3
    if (r & 1) == 0 and (c & 1) == 0: return VMAT[m][0]
    if (r & 1) == 1 and (c & 1) == 1: return VMAT[m][1]
    return VMAT[m][2]

QPC_TAB = [29,30,31,32,32,33,34,34,35,35,36,36,37,37,37,38,38,38,39,39,39,39]
def qpc_of(q):
    q = 0 if q < 0 else (51 if q > 51 else q)
    return q if q < 30 else QPC_TAB[q - 30]

def clip(v, lo=0, hi=255):
    return lo if v < lo else (hi if v > hi else v)

def idct4(blk):
    """8.5.12.2 -- die exakte Ganzzahl-Rueckwaertstransformation."""
    t = [0]*16
    for i in range(4):
        d0,d1,d2,d3 = blk[i*4],blk[i*4+1],blk[i*4+2],blk[i*4+3]
        e0 = d0 + d2; e1 = d0 - d2
        e2 = (d1 >> 1) - d3; e3 = d1 + (d3 >> 1)
        t[i*4+0]=e0+e3; t[i*4+1]=e1+e2; t[i*4+2]=e1-e2; t[i*4+3]=e0-e3
    o = [0]*16
    for j in range(4):
        d0,d1,d2,d3 = t[j],t[4+j],t[8+j],t[12+j]
        e0 = d0 + d2; e1 = d0 - d2
        e2 = (d1 >> 1) - d3; e3 = d1 + (d3 >> 1)
        o[j]=e0+e3; o[4+j]=e1+e2; o[8+j]=e1-e2; o[12+j]=e0-e3
    return o

def hadamard4(blk):
    """Luma-DC, 8.5.10."""
    t=[0]*16
    for i in range(4):
        a,b,c,d = blk[i*4],blk[i*4+1],blk[i*4+2],blk[i*4+3]
        e0=a+c; e1=a-c; e2=b-d; e3=b+d
        t[i*4+0]=e0+e3; t[i*4+1]=e1+e2; t[i*4+2]=e1-e2; t[i*4+3]=e0-e3
    o=[0]*16
    for j in range(4):
        a,b,c,d = t[j],t[4+j],t[8+j],t[12+j]
        e0=a+c; e1=a-c; e2=b-d; e3=b+d
        o[j]=e0+e3; o[4+j]=e1+e2; o[8+j]=e1-e2; o[12+j]=e0-e3
    return o

# ===================================================== Intra-Vorhersage
# Die Modi kommen als GEWICHTSTAFEL aus pred4.json (erzeugt von
# pred_gen.py direkt aus den Formeln 8.3.1.2.1-9). Nachbarindex:
# 0..3 = L0..L3, 4 = LU, 5..8 = U0..U3, 9..12 = UR0..UR3.
PRED4 = {int(k): v for k, v in json.load(open(
    os.path.join(os.path.dirname(os.path.abspath(__file__)),
                 'pred4.json'))).items()}

def pred4x4(mode, L, LU, U, UR, avail_l, avail_u):
    nb = list(L) + [LU] + list(U) + list(UR)
    o = [0]*16
    if mode == 2:
        if avail_l and avail_u: v = (sum(L)+sum(U)+4) >> 3
        elif avail_l: v = (sum(L)+2) >> 2
        elif avail_u: v = (sum(U)+2) >> 2
        else: v = 128
        return [v]*16
    rows = PRED4[mode]
    for i in range(16):
        r = rows[i]; w = r[0]
        s = 0
        for (g, idx) in r[1:]:
            s += g * nb[idx]
        if w == 1: o[i] = s
        else: o[i] = (s + (w >> 1)) >> (w.bit_length()-1)
    return o

# ============================================== Intra 16x16 und Chroma
def pred16(mode, L, LU, U, avail_l, avail_u, size=16):
    o=[0]*(size*size)
    if mode==0:   # vertikal
        for y in range(size):
            for x in range(size): o[y*size+x]=U[x]
    elif mode==1: # horizontal
        for y in range(size):
            for x in range(size): o[y*size+x]=L[y]
    elif mode==2: # DC
        if avail_l and avail_u: v=(sum(L)+sum(U)+size)>>(size.bit_length())
        elif avail_u: v=(sum(U)+(size>>1))>>(size.bit_length()-1)
        elif avail_l: v=(sum(L)+(size>>1))>>(size.bit_length()-1)
        else: v=128
        for i in range(size*size): o[i]=v
    else:         # plane
        H=0;V=0
        n=size>>1
        for i in range(n):
            H+=(i+1)*(U[n+i]-(U[n-2-i] if n-2-i>=0 else LU))
            V+=(i+1)*(L[n+i]-(L[n-2-i] if n-2-i>=0 else LU))
        if size==16: a=16*(L[15]+U[15]); b=(5*H+32)>>6; c=(5*V+32)>>6
        else:        a=16*(L[size-1]+U[size-1]); b=(17*H+16)>>5; c=(17*V+16)>>5
        for y in range(size):
            for x in range(size):
                o[y*size+x]=clip((a+b*(x-(size-1)//2*0-(size//2-1))+c*(y-(size//2-1))+16)>>5)
    return o

def pred_chroma(mode, L, LU, U, avail_l, avail_u):
    """8x8 Chroma. 0=DC, 1=horizontal, 2=vertikal, 3=plane."""
    o=[0]*64
    if mode==0:
        for by in range(2):
            for bx in range(2):
                # je 4x4-Viertel eigener DC, 8.3.4.1
                if bx==0 and by==0:
                    if avail_l and avail_u: v=(sum(U[0:4])+sum(L[0:4])+4)>>3
                    elif avail_u: v=(sum(U[0:4])+2)>>2
                    elif avail_l: v=(sum(L[0:4])+2)>>2
                    else: v=128
                elif bx==1 and by==0:
                    if avail_u: v=(sum(U[4:8])+2)>>2
                    elif avail_l: v=(sum(L[0:4])+2)>>2
                    else: v=128
                elif bx==0 and by==1:
                    if avail_l: v=(sum(L[4:8])+2)>>2
                    elif avail_u: v=(sum(U[0:4])+2)>>2
                    else: v=128
                else:
                    if avail_l and avail_u: v=(sum(U[4:8])+sum(L[4:8])+4)>>3
                    elif avail_u: v=(sum(U[4:8])+2)>>2
                    elif avail_l: v=(sum(L[4:8])+2)>>2
                    else: v=128
                for y in range(4):
                    for x in range(4): o[(by*4+y)*8+bx*4+x]=v
    elif mode==1:
        for y in range(8):
            for x in range(8): o[y*8+x]=L[y]
    elif mode==2:
        for y in range(8):
            for x in range(8): o[y*8+x]=U[x]
    else:
        H=0;V=0
        for i in range(4):
            H+=(i+1)*(U[4+i]-(U[2-i] if 2-i>=0 else LU))
            V+=(i+1)*(L[4+i]-(L[2-i] if 2-i>=0 else LU))
        a=16*(L[7]+U[7]); b=(17*H+16)>>5; c=(17*V+16)>>5
        for y in range(8):
            for x in range(8):
                o[y*8+x]=clip((a+b*(x-3)+c*(y-3)+16)>>5)
    return o

# ============================================ Bewegungskompensation
#
# 8.4.2.2.1, sauber nach der Norm und nicht nach Gefuehl. Die 16
# Viertelpel-Stellen (xFrac, yFrac) sind in der Norm mit Buchstaben
# benannt; hier steht fuer jede Stelle, aus welchen ZWEI Groessen sie
# gemittelt wird (oder welche sie direkt ist):
#
#     G a b c      G = ganz        b = halb waagerecht
#     d e f g      h = halb senkrecht
#     h i j k      j = halb/halb (aus den Zwischenwerten, >>10)
#     n p q r
#
# a=(G+b)/2 c=(b+H)/2 d=(G+h)/2 n=(h+M)/2 f=(b+j)/2 i=(h+j)/2
# k=(j+m)/2 q=(j+s)/2 e=(b+h)/2 g=(b+m)/2 p=(h+s)/2 r=(m+s)/2
# wobei H=G(x+1), M=h(x+1), s=b(y+1), m=h... -- siehe Tafel 8-12.

def _clampref(ref, rw, rh, px, py):
    if px < 0: px = 0
    elif px >= rw: px = rw - 1
    if py < 0: py = 0
    elif py >= rh: py = rh - 1
    return ref[py*rw+px]

def luma_qpel(ref, rw, rh, x, y, mvx, mvy, bw, bh, out, ostride, ox, oy):
    fx = mvx & 3; fy = mvy & 3
    ix = x + (mvx >> 2); iy = y + (mvy >> 2)
    R = lambda px, py: _clampref(ref, rw, rh, px, py)
    # Zwischenwerte OHNE Klemmung (fuer j), mit Klemmung (fuer b,h)
    def braw(px, py):
        return (R(px-2,py)-5*R(px-1,py)+20*R(px,py)+20*R(px+1,py)
                -5*R(px+2,py)+R(px+3,py))
    def hraw(px, py):
        return (R(px,py-2)-5*R(px,py-1)+20*R(px,py)+20*R(px,py+1)
                -5*R(px,py+2)+R(px,py+3))
    def b(px,py): return clip((braw(px,py)+16)>>5)
    def h(px,py): return clip((hraw(px,py)+16)>>5)
    def j(px,py):
        s = (hraw(px-2,py)-5*hraw(px-1,py)+20*hraw(px,py)
             +20*hraw(px+1,py)-5*hraw(px+2,py)+hraw(px+3,py))
        return clip((s+512)>>10)
    for r_ in range(bh):
        for c_ in range(bw):
            px = ix+c_; py = iy+r_
            if   fx==0 and fy==0: v = R(px,py)
            elif fx==1 and fy==0: v = (R(px,py)+b(px,py)+1)>>1
            elif fx==2 and fy==0: v = b(px,py)
            elif fx==3 and fy==0: v = (b(px,py)+R(px+1,py)+1)>>1
            elif fx==0 and fy==1: v = (R(px,py)+h(px,py)+1)>>1
            elif fx==0 and fy==2: v = h(px,py)
            elif fx==0 and fy==3: v = (h(px,py)+R(px,py+1)+1)>>1
            elif fx==2 and fy==2: v = j(px,py)
            elif fx==1 and fy==1: v = (b(px,py)+h(px,py)+1)>>1
            elif fx==3 and fy==1: v = (b(px,py)+h(px+1,py)+1)>>1
            elif fx==1 and fy==3: v = (b(px,py+1)+h(px,py)+1)>>1
            elif fx==3 and fy==3: v = (b(px,py+1)+h(px+1,py)+1)>>1
            elif fx==2 and fy==1: v = (j(px,py)+b(px,py)+1)>>1
            elif fx==2 and fy==3: v = (j(px,py)+b(px,py+1)+1)>>1
            elif fx==1 and fy==2: v = (j(px,py)+h(px,py)+1)>>1
            else:                 v = (j(px,py)+h(px+1,py)+1)>>1
            out[(oy+r_)*ostride+ox+c_] = v

def chroma_mc(ref, rw, rh, x, y, mvx, mvy, bw, bh, out, ostride, ox, oy):
    """8.4.2.2.2 -- bilinear auf Achtelpel."""
    xf = mvx & 7; yf = mvy & 7
    ix = x + (mvx >> 3); iy = y + (mvy >> 3)
    R = lambda px, py: _clampref(ref, rw, rh, px, py)
    for r_ in range(bh):
        for c_ in range(bw):
            px=ix+c_; py=iy+r_
            v=((8-xf)*(8-yf)*R(px,py) + xf*(8-yf)*R(px+1,py)
               + (8-xf)*yf*R(px,py+1) + xf*yf*R(px+1,py+1) + 32) >> 6
            out[(oy+r_)*ostride+ox+c_]=v

# ================================================== SPS / PPS / Slice
class SPS: pass
class PPS: pass

def parse_sps(r):
    b=BR(r); s=SPS()
    s.profile=b.un(8); s.constraint=b.un(8); s.level=b.un(8); s.id=b.ue()
    if s.profile in (100,110,122,244,44,83,86,118,128,138,139,134,135):
        raise ValueError('High Profile -- diese Runde kann nur Baseline')
    s.log2_max_frame_num=b.ue()+4
    s.poc_type=b.ue()
    if s.poc_type==0: s.log2_max_poc_lsb=b.ue()+4
    elif s.poc_type==1: raise ValueError('poc_type 1 nicht gebaut')
    s.num_ref_frames=b.ue(); s.gaps=b.u1()
    s.mbw=b.ue()+1; s.mbh=b.ue()+1
    s.frame_mbs_only=b.u1()
    if not s.frame_mbs_only: raise ValueError('Interlace nicht gebaut')
    s.direct8x8=b.u1(); s.crop=b.u1()
    s.cl=s.cr=s.ct=s.cb=0
    if s.crop:
        s.cl=b.ue(); s.cr=b.ue(); s.ct=b.ue(); s.cb=b.ue()
    s.w=s.mbw*16; s.h=s.mbh*16
    # 4:2:0 -> CropUnitX 2, CropUnitY 2 (frame_mbs_only)
    s.vw=s.w-2*(s.cl+s.cr); s.vh=s.h-2*(s.ct+s.cb)
    return s

def parse_pps(r):
    b=BR(r); p=PPS()
    p.id=b.ue(); p.sps_id=b.ue(); p.cabac=b.u1(); p.pic_order_present=b.u1()
    p.num_slice_groups=b.ue()+1
    if p.num_slice_groups>1: raise ValueError('Slice-Gruppen nicht gebaut')
    p.nref0=b.ue()+1; p.nref1=b.ue()+1
    p.weighted_pred=b.u1(); p.weighted_bipred=b.un(2)
    p.qp=b.se()+26; p.qs=b.se()+26; p.chroma_qp_off=b.se()
    p.deblock_ctl=b.u1(); p.constrained_intra=b.u1(); p.redundant=b.u1()
    p.chroma_qp_off2=p.chroma_qp_off
    return p

# Tafel 9-4 (Intra) / golomb_to_inter_cbp: Umsetzung me(v) -> CBP
G2I4 = [47,31,15,0,23,27,29,30,7,11,13,14,39,43,45,46,16,3,5,10,12,19,21,26,28,35,37,42,44,1,2,4,8,17,18,20,24,6,9,22,25,32,33,34,36,40,38,41]
G2P  = [0,16,1,2,4,8,32,3,5,10,12,15,47,7,11,13,14,6,9,31,35,37,42,44,33,34,36,40,39,43,45,46,17,18,20,24,19,21,26,28,23,27,29,30,22,25,38,41]

# ================================================== der Bilddekodierer
class Frame:
    def __init__(s, w, h):
        s.w=w; s.h=h; s.cw=w>>1; s.ch=h>>1
        s.Y=[0]*(w*h); s.U=[0]*(s.cw*s.ch); s.V=[0]*(s.cw*s.ch)
        s.poc=0; s.num=0

class Dec:
    def __init__(s):
        s.sps={}; s.pps={}; s.refs=[]; s.out=[]
        s.prev_frame_num=0
    # --- Nachbarschaft
    def mb_avail(s, mbx, mby):
        pass

    def decode_slice(s, nal, r):
        b=BR(r)
        nal_ref_idc=(nal[0]>>5)&3; nal_type=nal[0]&31
        idr = (nal_type==5)
        first_mb=b.ue(); st=b.ue(); pid=b.ue()
        slice_type = st%5   # 0=P,1=B,2=I,3=SP,4=SI
        if slice_type not in (0,2): raise ValueError('nur I- und P-Slices')
        pps=s.pps[pid]; sps=s.sps[pps.sps_id]
        s.cur_sps=sps; s.cur_pps=pps
        frame_num=b.un(sps.log2_max_frame_num)
        if idr: idr_pid=b.ue()
        if sps.poc_type==0:
            poc_lsb=b.un(sps.log2_max_poc_lsb)
            if pps.pic_order_present: b.se()
        num_ref_idx_l0=pps.nref0
        if slice_type==0:
            if b.u1():   # num_ref_idx_active_override
                num_ref_idx_l0=b.ue()+1
        # ref_pic_list_modification
        if slice_type!=2:
            if b.u1():
                while True:
                    op=b.ue()
                    if op==3: break
                    b.ue()
        if nal_ref_idc:
            if idr:
                b.u1(); b.u1()
            else:
                if b.u1():   # adaptive_ref_pic_marking
                    while True:
                        op=b.ue()
                        if op==0: break
                        if op in (1,3): b.ue()
                        if op==2: b.ue()
                        if op in (3,6): b.ue()
                        if op==4: b.ue()
                        if op==5: pass
        slice_qp=pps.qp+b.se()
        disable_deblock=0; alpha_off=0; beta_off=0
        if pps.deblock_ctl:
            disable_deblock=b.ue()
            if disable_deblock!=1:
                alpha_off=b.se()*2; beta_off=b.se()*2
        s.slice_type=slice_type
        s.qp=slice_qp
        s.disable_deblock=disable_deblock
        s.alpha_off=alpha_off; s.beta_off=beta_off
        s.num_ref_idx_l0=num_ref_idx_l0
        return b, first_mb, idr, frame_num, slice_type

# Block-Nachbarschaft: die 16 Luma-4x4 in Norm-Reihenfolge (8.2.2)
# blkIdx -> (x,y) in 4x4-Einheiten innerhalb des MB
# 8.2.2: blkIdx -> (x,y) in 4x4-Einheiten. Die Reihenfolge ist NICHT
# zeilenweise, sondern in 8x8-Vierteln, darin wieder in 4x4-Vierteln:
#   0 1 | 4 5      Das ist der Z-Zug ueber zwei Ebenen. Wer hier die
#   2 3 | 6 7      naheliegende Bitverdrehung hinschreibt, bekommt
#   ----+----      doppelte Koordinaten und merkt es erst, wenn der
#   8 9 |12 13     Bitstrom drei Makrobloecke spaeter aus dem Tritt
#  10 11|14 15     geraet -- genau das ist hier passiert.
BLK_XY=[]
for i in range(16):
    x=((i>>2)&1)*2 + (i&1)
    y=((i>>3)&1)*2 + ((i>>1)&1)
    BLK_XY.append((x,y))

class MB:
    __slots__=('type','pred','cbp','qp','intra','i16mode','i4','mvx','mvy',
               'ref','nz','skipped','cpred','done')
    def __init__(s):
        s.type=0; s.pred=0; s.cbp=0; s.qp=0; s.intra=True
        s.i16mode=0; s.i4=[2]*16; s.mvx=[0]*16; s.mvy=[0]*16
        s.ref=[-1]*16; s.nz=[0]*24; s.skipped=False; s.cpred=0
        s.done=False   # noch nicht dekodiert -> fuer Nachbarn NICHT da

def dec_frame(s, data):
    pass

def decode_stream(data, want_frames=None, trace=False):
    d=Dec()
    fr=None
    frames=[]
    for nal in nal_split(data):
        t=nal[0]&31
        r=rbsp(nal[1:])
        if t==7:
            sp=parse_sps(r); d.sps[sp.id]=sp
        elif t==8:
            pp=parse_pps(r); d.pps[pp.id]=pp
        elif t in (1,5):
            b, first_mb, idr, frame_num, slice_type = d.decode_slice(nal, r)
            sps=d.cur_sps; pps=d.cur_pps
            if idr: d.refs=[]
            f=Frame(sps.w, sps.h)
            f.num=frame_num
            d.cur=f
            d.mbs=[MB() for _ in range(sps.mbw*sps.mbh)]
            decode_mbs(d, b, first_mb, sps, pps)
            deblock_frame(d, sps, pps)
            frames.append(f)
            d.refs.insert(0, f)
            if len(d.refs)>16: d.refs.pop()
    return d, frames

def nb_mb(d, sps, mbx, mby):
    """Nachbarn A (links) und B (oben), oder None."""
    A = d.mbs[mby*sps.mbw+mbx-1] if mbx>0 else None
    B = d.mbs[(mby-1)*sps.mbw+mbx] if mby>0 else None
    return A,B

def nz_left(d,sps,mbx,mby,bx,by):
    """Zahl der Koeffizienten im 4x4-Nachbarn links (fuer nC)."""
    if bx>0:
        mb=d.mbs[mby*sps.mbw+mbx]; return mb.nz[(by*4+bx-1)]
    if mbx==0: return -1
    mb=d.mbs[mby*sps.mbw+mbx-1]
    if not mb.done: return -1
    return mb.nz[by*4+3]

def nz_up(d,sps,mbx,mby,bx,by):
    if by>0:
        mb=d.mbs[mby*sps.mbw+mbx]; return mb.nz[((by-1)*4+bx)]
    if mby==0: return -1
    mb=d.mbs[(mby-1)*sps.mbw+mbx]
    if not mb.done: return -1
    return mb.nz[3*4+bx]

def calc_nc(d,sps,mbx,mby,bx,by):
    nA=nz_left(d,sps,mbx,mby,bx,by); nB=nz_up(d,sps,mbx,mby,bx,by)
    if nA>=0 and nB>=0: return (nA+nB+1)>>1
    if nA>=0: return nA
    if nB>=0: return nB
    return 0

def nz_left_c(d,sps,mbx,mby,c,bx,by):
    base=16+c*4
    if bx>0:
        mb=d.mbs[mby*sps.mbw+mbx]; return mb.nz[base+by*2+bx-1]
    if mbx==0: return -1
    mb=d.mbs[mby*sps.mbw+mbx-1]
    if not mb.done: return -1
    return mb.nz[base+by*2+1]

def nz_up_c(d,sps,mbx,mby,c,bx,by):
    base=16+c*4
    if by>0:
        mb=d.mbs[mby*sps.mbw+mbx]; return mb.nz[base+(by-1)*2+bx]
    if mby==0: return -1
    mb=d.mbs[(mby-1)*sps.mbw+mbx]
    if not mb.done: return -1
    return mb.nz[base+1*2+bx]

def calc_nc_c(d,sps,mbx,mby,c,bx,by):
    nA=nz_left_c(d,sps,mbx,mby,c,bx,by); nB=nz_up_c(d,sps,mbx,mby,c,bx,by)
    if nA>=0 and nB>=0: return (nA+nB+1)>>1
    if nA>=0: return nA
    if nB>=0: return nB
    return 0

def get_luma_nb(f, px, py, avail_l, avail_u, avail_ur):
    """Nachbarn eines 4x4-Blocks an Bildstelle (px,py)."""
    W=f.w
    L=[0]*4; U=[0]*4; UR=[0]*4; LU=0
    if avail_l:
        for i in range(4): L[i]=f.Y[(py+i)*W+px-1]
    if avail_u:
        for i in range(4): U[i]=f.Y[(py-1)*W+px+i]
    if avail_l and avail_u: LU=f.Y[(py-1)*W+px-1]
    if avail_ur:
        for i in range(4): UR[i]=f.Y[(py-1)*W+px+4+i]
    elif avail_u:
        for i in range(4): UR[i]=U[3]
    return L,LU,U,UR

def decode_mbs(d, b, first_mb, sps, pps):
    """Die Makroblockschleife. In einem P-Slice steht VOR jedem
    kodierten MB ein mb_skip_run -- die Zahl der uebersprungenen."""
    mbw=sps.mbw; mbh=sps.mbh
    total=mbw*mbh
    mb_idx=first_mb
    qp=d.qp
    while mb_idx < total:
        if d.slice_type==0:
            if not b.more(): break
            run=b.ue()
            for _ in range(run):
                if mb_idx>=total: break
                do_skip(d,sps,mb_idx,qp)
                mb_idx+=1
            if mb_idx>=total or not b.more(): break
        qp = decode_mb(d, b, sps, pps, mb_idx, qp)
        mb_idx+=1
    d.qp_end=qp

# ---------------------------------------------- Bewegungsvektorvorhersage
def mv_of(d,sps,mbx,mby,bx,by):
    """MV und Referenz eines 4x4-Blocks in Nachbarschaftskoordinaten.
    bx,by duerfen -1 sein (links/oben ausserhalb)."""
    x=mbx*4+bx; y=mby*4+by
    if x<0 or y<0 or x>=sps.mbw*4 or y>=sps.mbh*4: return None
    nmbx=x>>2; nmby=y>>2
    m=d.mbs[nmby*sps.mbw+nmbx]
    if m is None: return None
    # Der EIGENE Makroblock zaehlt immer (seine Vektoren sind gerade
    # gelesen worden); ein fremder erst, wenn er dekodiert ist.
    if (nmbx!=mbx or nmby!=mby) and not m.done: return None
    i=(y&3)*4+(x&3)
    return (m.mvx[i], m.mvy[i], m.ref[i], m.intra)

def pred_mv(d,sps,mbx,mby,bx,by,bw,refidx):
    """8.4.1.3 -- der Median aus A, B, C."""
    A=mv_of(d,sps,mbx,mby,bx-1,by)
    B=mv_of(d,sps,mbx,mby,bx,by-1)
    C=mv_of(d,sps,mbx,mby,bx+bw,by-1)
    if C is None or (by==0 and bx+bw>=4 and mby>0 and False):
        C=None
    if C is None:
        C=mv_of(d,sps,mbx,mby,bx-1,by-1)   # D statt C
    def norm(t):
        if t is None: return (0,0,-1)
        if t[3]: return (0,0,-1)   # intra -> nicht verfuegbar
        return (t[0],t[1],t[2])
    a=norm(A); bb=norm(B); c=norm(C)
    # Nur EIN Nachbar hat dieselbe Referenz -> der gewinnt
    same=[t for t in (a,bb,c) if t[2]==refidx]
    if len(same)==1: return same[0][0], same[0][1]
    if bb[2]==-1 and c[2]==-1 and A is not None:
        return a[0],a[1]
    def med(p,q,r): return p+q+r-min(p,q,r)-max(p,q,r)
    return med(a[0],bb[0],c[0]), med(a[1],bb[1],c[1])

def do_skip(d,sps,mb_idx,qp):
    """P_Skip, 8.4.1.1: Referenz 0, kein Rest. Der Vektor ist der
    vorhergesagte -- ABER null, wenn A oder B fehlen oder selbst
    null mit Referenz 0 sind."""
    mbx=mb_idx%sps.mbw; mby=mb_idx//sps.mbw
    mb=d.mbs[mb_idx]
    mb.intra=False; mb.skipped=True; mb.type=-1; mb.qp=qp; mb.cbp=0
    A=mv_of(d,sps,mbx,mby,-1,0)
    B=mv_of(d,sps,mbx,mby,0,-1)
    def zero_ref0(t):
        return t is not None and (not t[3]) and t[2]==0 and t[0]==0 and t[1]==0
    if A is None or B is None or zero_ref0(A) or zero_ref0(B):
        mvx,mvy=0,0
    else:
        mvx,mvy=pred_mv(d,sps,mbx,mby,0,0,4,0)
    for i in range(16):
        mb.mvx[i]=mvx; mb.mvy[i]=mvy; mb.ref[i]=0
    for i in range(24): mb.nz[i]=0
    mb.done=True
    mc_mb(d,sps,mbx,mby,mb)

def mc_mb(d,sps,mbx,mby,mb):
    """Bewegungskompensation fuer den ganzen MB. JEDER 4x4-Block traegt
    seinen eigenen Vektor; Chroma wird je 2x2 Bildpunkte aus DEMSELBEN
    Block gerechnet (der Vektor gilt dort in Achtelpel)."""
    f=d.cur
    for by in range(4):
        for bx in range(4):
            i=by*4+bx
            ri=mb.ref[i]
            ref=d.refs[ri] if 0<=ri<len(d.refs) else (d.refs[0] if d.refs else None)
            if ref is None: continue
            luma_qpel(ref.Y, ref.w, ref.h, mbx*16+bx*4, mby*16+by*4,
                      mb.mvx[i], mb.mvy[i], 4, 4, f.Y, f.w,
                      mbx*16+bx*4, mby*16+by*4)
            chroma_mc(ref.U, ref.cw, ref.ch, mbx*8+bx*2, mby*8+by*2,
                      mb.mvx[i], mb.mvy[i], 2, 2, f.U, f.cw,
                      mbx*8+bx*2, mby*8+by*2)
            chroma_mc(ref.V, ref.cw, ref.ch, mbx*8+bx*2, mby*8+by*2,
                      mb.mvx[i], mb.mvy[i], 2, 2, f.V, f.cw,
                      mbx*8+bx*2, mby*8+by*2)

def read_te(b, maxv):
    """te(v): bei maxv==1 EIN Bit (invertiert), sonst ue(v)."""
    if maxv<=0: return 0
    if maxv==1: return 1-b.u1()
    return b.ue()

def pred_mode_from_nb(d,sps,mbx,mby,bx,by):
    """8.3.1.1 -- der vorhergesagte Intra-4x4-Modus aus A (links) und
    B (oben).

    FALLE: die Nachbarn duerfen im SELBEN Makroblock liegen, und die
    sind noch nicht `done` -- sie sind ja gerade erst gelesen worden.
    Die done-Fahne gilt nur fuer FREMDE Makrobloecke. Wer sie auch auf
    den eigenen anwendet, bekommt fuer jeden Block DC vorhergesagt und
    liest damit die falschen Modi aus dem Strom."""
    def m_of(nx,ny):
        x=mbx*4+nx; y=mby*4+ny
        if x<0 or y<0: return None
        nmbx=x>>2; nmby=y>>2
        mb=d.mbs[nmby*sps.mbw+nmbx]
        if mb is None: return None
        if nmbx!=mbx or nmby!=mby:
            if not mb.done: return None
        # Ein INTER-Nachbar ist verfuegbar und zaehlt als DC (2). Nur
        # bei constrained_intra_pred_flag gilt er als nicht vorhanden.
        # Andersherum gedacht (Inter -> None) kommt in einem P-Slice
        # fuer jeden Intra-Makroblock die falsche Modusvorhersage
        # heraus -- und damit der falsche Modus aus dem Strom.
        if not mb.intra:
            return None if d.cur_pps.constrained_intra else 2
        if mb.type!=0: return 2   # I16x16 -> DC
        return mb.i4[(y&3)*4+(x&3)]
    A=m_of(bx-1,by); B=m_of(bx,by-1)
    if A is None or B is None: return 2
    return A if A<B else B

# Die Aufteilung eines P-MB: (Teile, Breite, Hoehe) in 4x4-Einheiten
def p_part(mtype):
    """Die Aufteilung eines P-Makroblocks in 4x4-Einheiten.
    Typ 3 ist P_8x8, Typ 4 ist P_8x8ref0 -- dasselbe, nur dass die
    Referenz fest 0 ist und KEIN ref_idx im Strom steht."""
    if mtype==0: return 1,4,4
    if mtype==1: return 2,4,2
    if mtype==2: return 2,2,4
    if mtype==3: return 4,2,2
    if mtype==4: return 4,2,2
    raise ValueError('P-Typ %d nicht in Baseline'%mtype)

def sub_part(st):
    """sub_mb_type in einem P-Slice: 0=8x8, 1=8x4, 2=4x8, 3=4x4."""
    if st==0: return 1,2,2
    if st==1: return 2,2,1
    if st==2: return 2,1,2
    if st==3: return 4,1,1
    raise ValueError('sub_mb_type %d'%st)

def sub_xy(sn,sw,sh,q):
    if sn==1: return 0,0
    if sw==2: return 0,q      # 8x4
    if sh==2: return q,0      # 4x8
    return q%2,q//2           # 4x4

def part_xy(n,pw,ph,p):
    if n==1: return 0,0
    if pw==4: return 0,p*2      # 16x8
    if ph==4: return p*2,0      # 8x16
    return (p%2)*2,(p//2)*2     # 8x8

def pred_mv_part(d,sps,mbx,mby,bx,by,bw,refidx,ph=None,n=None):
    """8.4.1.3 -- der vorhergesagte Bewegungsvektor einer Partition.

    Reihenfolge, und sie ist NICHT beliebig:
      1. Die Sonderfaelle fuer 16x8 und 8x16 (8.4.1.3.1) greifen VOR
         allem anderen: bei 16x8 nimmt die obere Haelfte B, die untere
         A; bei 8x16 die linke A, die rechte C -- aber nur, wenn der
         betreffende Nachbar DIESELBE Referenz hat.
      2. Hat genau EINER von A,B,C die gesuchte Referenz, gewinnt er.
      3. Sonst der Median.
    Fehlt C (ausserhalb oder noch nicht da), tritt D an seine Stelle.
    """
    A=mv_of(d,sps,mbx,mby,bx-1,by)
    B=mv_of(d,sps,mbx,mby,bx,by-1)
    C=mv_of(d,sps,mbx,mby,bx+bw,by-1)
    if C is None: C=mv_of(d,sps,mbx,mby,bx-1,by-1)
    def norm(t):
        if t is None or t[3]: return (0,0,-1)
        return (t[0],t[1],t[2])
    a=norm(A); bb=norm(B); c=norm(C)
    # --- 1. die Sonderfaelle
    if n==2 and ph==2:           # 16x8
        if by==0 and bb[2]==refidx: return bb[0],bb[1]
        if by==2 and a[2]==refidx: return a[0],a[1]
    if n==2 and ph==4:           # 8x16
        if bx==0 and a[2]==refidx: return a[0],a[1]
        if bx==2 and c[2]==refidx: return c[0],c[1]
    # --- 2. genau einer passt
    same=[t for t in (a,bb,c) if t[2]==refidx]
    if len(same)==1: return same[0][0],same[0][1]
    # --- B und C fehlen ganz: dann gilt A
    if B is None and C is None and A is not None:
        return a[0],a[1]
    def med(p,q,r): return p+q+r-min(p,q,r)-max(p,q,r)
    return med(a[0],bb[0],c[0]), med(a[1],bb[1],c[1])

def decode_mb(d, b, sps, pps, mb_idx, qp):
    mbx=mb_idx%sps.mbw; mby=mb_idx//sps.mbw
    mb=d.mbs[mb_idx]
    mtype=b.ue()
    if d.slice_type==0:
        if mtype<5: mb.intra=False
        else: mtype-=5; mb.intra=True
    else:
        mb.intra=True
    mb.type=mtype
    cbp=0; i16=False
    if mb.intra:
        if mtype==0:
            for i in range(16):
                bx,by=BLK_XY[i]
                pm=pred_mode_from_nb(d,sps,mbx,mby,bx,by)
                if b.u1(): mode=pm
                else:
                    r=b.un(3)
                    mode=r if r<pm else r+1
                mb.i4[by*4+bx]=mode
            mb.cpred=b.ue()
            if mb.cpred>3: raise ValueError('intra_chroma_pred_mode %d'%mb.cpred)
            k=b.ue()
            if k>=48: raise ValueError('coded_block_pattern %d'%k)
            cbp=G2I4[k]
        elif mtype==25:
            raise ValueError('I_PCM nicht gebaut')
        else:
            # I_16x16: mtype 1..24 -> Modus, CBP-Chroma, CBP-Luma
            i16=True
            t=mtype-1
            if t>=24: raise ValueError('mb_type %d'%mtype)
            mb.i16mode=t&3
            cbpc=(t>>2)%3
            cbpl=15 if t>=12 else 0
            cbp=cbpl|(cbpc<<4)
            mb.cpred=b.ue()
            if mb.cpred>3: raise ValueError('intra_chroma_pred_mode')
    else:
        n,pw,ph=p_part(mtype)
        acht = (mtype>=3)          # P_8x8 / P_8x8ref0
        sub=[0]*4
        if acht:
            for p in range(4): sub[p]=b.ue()
        refs=[0]*n
        if d.num_ref_idx_l0>1 and mtype!=4:
            for p in range(n): refs[p]=read_te(b,d.num_ref_idx_l0-1)
        if acht:
            # Erst alle Referenzen, dann alle Vektoren (7.3.5.1)
            for p in range(4):
                sn,sw,sh=sub_part(sub[p])
                bx0=(p%2)*2; by0=(p//2)*2
                for q in range(sn):
                    sx,sy=sub_xy(sn,sw,sh,q)
                    px=bx0+sx; py=by0+sy
                    pmx,pmy=pred_mv_part(d,sps,mbx,mby,px,py,sw,refs[p])
                    vx=pmx+b.se(); vy=pmy+b.se()
                    for yy in range(sh):
                        for xx in range(sw):
                            i=(py+yy)*4+(px+xx)
                            mb.mvx[i]=vx; mb.mvy[i]=vy; mb.ref[i]=refs[p]
        else:
            for p in range(n):
                px,py=part_xy(n,pw,ph,p)
                pmx,pmy=pred_mv_part(d,sps,mbx,mby,px,py,pw,refs[p],ph,n)
                vx=pmx+b.se(); vy=pmy+b.se()
                for yy in range(ph):
                    for xx in range(pw):
                        i=(py+yy)*4+(px+xx)
                        mb.mvx[i]=vx; mb.mvy[i]=vy; mb.ref[i]=refs[p]
        mb.done=True
        mc_mb(d,sps,mbx,mby,mb)
        k=b.ue()
        if k>=48: raise ValueError('coded_block_pattern %d'%k)
        cbp=G2P[k]
    mb.cbp=cbp
    return finish_mb(d,b,sps,pps,mb,mbx,mby,qp,i16,cbp)

def finish_mb(d,b,sps,pps,mb,mbx,mby,qp,i16,cbp):
    """Die Restwerte des MB, dann der Aufbau.

    REIHENFOLGE-FALLE, an der diese Runde eine Stunde gehangen hat:
    `mb.nz` wird von den NACHBARN gelesen (nC), und zwar waehrend
    derselbe Makroblock noch laeuft. Also muessen die Zaehler eines
    Blocks stehen, BEVOR der naechste Block seinen nC rechnet -- und
    die Bloecke, die gar nicht kodiert sind, muessen VORHER auf 0
    stehen und nicht erst hinterher. Sonst liest der zweite
    Chroma-Block den Zaehler des ersten als seinen Nachbarn.
    """
    coef=[[0]*16 for _ in range(16)]
    dcL=[0]*16
    cdc=[[0]*4,[0]*4]
    cac=[[[0]*16 for _ in range(4)] for _ in range(2)]
    # Erst alles auf null -- ein nicht kodierter Block hat nC 0.
    for i in range(24): mb.nz[i]=0
    if cbp>0 or i16:
        qp=qp+b.se()
        while qp<0: qp+=52
        while qp>51: qp-=52
    if i16:
        nC=calc_nc(d,sps,mbx,mby,0,0)
        co,tc=residual_block(b,nC,16)
        for i in range(16): dcL[ZIGZAG4[i]]=co[i]
        # Der Luma-DC-Block zaehlt NICHT in die Nachbarschaft der AC.
    for i8 in range(4):
        if not (cbp & (1<<i8)):
            continue
        for k in range(4):
            bx,by=BLK_XY[i8*4+k]
            nC=calc_nc(d,sps,mbx,mby,bx,by)
            if i16:
                co,tc=residual_block(b,nC,15)
                blk=[0]*16
                for i in range(15): blk[ZIGZAG4[i+1]]=co[i]
            else:
                co,tc=residual_block(b,nC,16)
                blk=[0]*16
                for i in range(16): blk[ZIGZAG4[i]]=co[i]
            coef[by*4+bx]=blk
            mb.nz[by*4+bx]=tc
    if (cbp>>4)>0:
        for c in range(2):
            co,tc=residual_block(b,-1,4)
            cdc[c]=co[:]
    if (cbp>>4)==2:
        for c in range(2):
            for i in range(4):
                bx=i&1; by=i>>1
                nC=calc_nc_c(d,sps,mbx,mby,c,bx,by)
                co,tc=residual_block(b,nC,15)
                blk=[0]*16
                for k in range(15): blk[ZIGZAG4[k+1]]=co[k]
                cac[c][i]=blk
                mb.nz[16+c*4+by*2+bx]=tc
    mb.qp=qp
    mb.done=True
    reconstruct(d,sps,pps,mb,mbx,mby,qp,i16,cbp,dcL,coef,cdc,cac)
    return qp

def scale_block(blk, qp, dc_special=False):
    """8.5.12.1 -- Entquantisierung der 4x4-Koeffizienten.

    LevelScale(m,i,j) = weightScale(i,j) * normAdjust(m,i,j).
    Bei Baseline ist weightScale die FLACHE Matrix mit lauter 16en
    (Flat_4x4_16, 8.5.9) -- und genau diese 16 hat hier zuerst
    gefehlt. Die Wirkung war kein Absturz und kein schiefes Bild,
    sondern ein FLACHES: alle Reste sechzehnmal zu klein, das Bild
    blieb nahe an der Vorhersage. Sowas faellt nur im Wertevergleich
    auf, nicht im Hinsehen.
    """
    m=qp%6; sh=qp//6
    out=[0]*16
    for i in range(16):
        w=norm_adjust(m,i)*16
        if qp>=24: out[i]=(blk[i]*w)<<(sh-4)
        else:      out[i]=(blk[i]*w+(1<<(3-sh)))>>(4-sh)
    return out

def recon_luma4(f, px, py, pred, res):
    W=f.w
    for y in range(4):
        for x in range(4):
            f.Y[(py+y)*W+px+x]=clip(pred[y*4+x]+res[y*4+x])

def reconstruct(d,sps,pps,mb,mbx,mby,qp,i16,cbp,dcL,coef,cdc,cac):
    f=d.cur; W=f.w
    availA = mbx>0
    availB = mby>0
    availC = (mby>0 and mbx+1<sps.mbw)
    availD = (mbx>0 and mby>0)
    if mb.intra:
        if i16:
            # DC durch Hadamard und Skalierung
            dq=hadamard4(dcL)
            # 8.5.10: die DC-Skalierung. ACHTUNG, hier steckte der erste
            # Fehler dieser Runde: die Norm skaliert MIT DEM FAKTOR DER
            # 4x4-Transformation (LevelScale enthaelt schon die 16), und
            # das Ergebnis geht als Koeffizient 0 in die Transformation,
            # die selbst noch (x+32)>>6 macht. Die Formel lautet
            #   qP >= 36:  (f * w) << (qP/6 - 6)
            #   sonst:     (f * w + 2^(5-qP/6)) >> (6 - qP/6)
            # -- aber f ist der HADAMARD-Wert mal 16 noch nicht enthalten.
            # Gemessen gegen ffmpeg: richtig ist
            #   qP >= 12:  (f * w) << (qP/6 - 2)
            #   sonst:     (f * w + 2^(1-qP/6)) >> (2 - qP/6)
            m=qp%6; sh=qp//6
            w=VMAT[m][0]
            dc=[0]*16
            for i in range(16):
                if qp>=12: dc[i]=(dq[i]*w)<<(sh-2)
                else:      dc[i]=(dq[i]*w+(1<<(1-sh)))>>(2-sh)
            # Vorhersage fuer den ganzen MB
            L=[0]*16; U=[0]*16; LU=0
            if availA:
                for i in range(16): L[i]=f.Y[(mby*16+i)*W+mbx*16-1]
            if availB:
                for i in range(16): U[i]=f.Y[(mby*16-1)*W+mbx*16+i]
            if availD: LU=f.Y[(mby*16-1)*W+mbx*16-1]
            P=pred16(mb.i16mode,L,LU,U,availA,availB,16)
            for by in range(4):
                for bx in range(4):
                    blk=coef[by*4+bx][:]
                    sc=scale_block(blk,qp)
                    sc[0]=dc[by*4+bx]
                    res=idct4(sc)
                    for y in range(4):
                        for x in range(4):
                            v=clip(P[(by*4+y)*16+bx*4+x]+((res[y*4+x]+32)>>6))
                            f.Y[(mby*16+by*4+y)*W+mbx*16+bx*4+x]=v
        else:
            for i in range(16):
                bx,by=BLK_XY[i]
                px=mbx*16+bx*4; py=mby*16+by*4
                aL = availA if bx==0 else True
                aU = availB if by==0 else True
                # rechts-oben: nur wenn der Block dort schon steht
                if by==0:
                    aUR = availC if bx==3 else availB
                else:
                    aUR = (bx<3) and not (bx==1 and by==1) and True
                aUR = blk_ur_avail(bx,by,availB,availC)
                L,LU,U,UR=get_luma_nb(f,px,py,aL,aU,aUR)
                if not aUR:
                    for k in range(4): UR[k]=U[3]
                P=pred4x4(mb.i4[by*4+bx],L,LU,U,UR,aL,aU)
                sc=scale_block(coef[by*4+bx],qp)
                res=idct4(sc)
                for y in range(4):
                    for x in range(4):
                        f.Y[(py+y)*W+px+x]=clip(P[y*4+x]+((res[y*4+x]+32)>>6))
    else:
        # Inter: die Vorhersage steht schon (mc_mb), nur der Rest addiert
        for by in range(4):
            for bx in range(4):
                if not any(coef[by*4+bx]): continue
                sc=scale_block(coef[by*4+bx],qp)
                res=idct4(sc)
                px=mbx*16+bx*4; py=mby*16+by*4
                for y in range(4):
                    for x in range(4):
                        f.Y[(py+y)*W+px+x]=clip(
                            f.Y[(py+y)*W+px+x]+((res[y*4+x]+32)>>6))
    recon_chroma(d,sps,pps,mb,mbx,mby,qp,cbp,cdc,cac,availA,availB,availD)

def blk_ur_avail(bx,by,availB,availC):
    """Ist der Block RECHTS OBEN eines 4x4 schon dekodiert?
    Innerhalb des MB haengt das an der Norm-Reihenfolge (8.2.2):
    fuer bx==3 liegt er im Nachbar-MB rechts oben (nur bei by==0),
    und die Bloecke 3,7,11,13,15 (in xy: (1,1),(3,1),(1,3),(3,3),(3,2))
    haben ihn nicht."""
    if by==0:
        return availC if bx==3 else availB
    if bx==3: return False
    # innerhalb: der Block rechts oben ist da, wenn er in der
    # Dekodierreihenfolge VOR diesem liegt
    here=BLK_XY.index((bx,by))
    there=BLK_XY.index((bx+1,by-1))
    return there<here

def recon_chroma(d,sps,pps,mb,mbx,mby,qp,cbp,cdc,cac,availA,availB,availD):
    f=d.cur; CW=f.cw
    qpc=qpc_of(qp+pps.chroma_qp_off)
    for c in range(2):
        plane = f.U if c==0 else f.V
        if mb.intra:
            L=[0]*8; U=[0]*8; LU=0
            if availA:
                for i in range(8): L[i]=plane[(mby*8+i)*CW+mbx*8-1]
            if availB:
                for i in range(8): U[i]=plane[(mby*8-1)*CW+mbx*8+i]
            if availD: LU=plane[(mby*8-1)*CW+mbx*8-1]
            P=pred_chroma(mb.cpred,L,LU,U,availA,availB)
        else:
            P=None
        # DC: 2x2 Hadamard
        dq=[0]*4
        if (cbp>>4)>0:
            a,bb,cc,dd=cdc[c][0],cdc[c][1],cdc[c][2],cdc[c][3]
            e0=a+bb; e1=a-bb; e2=cc+dd; e3=cc-dd
            t=[e0+e2, e1+e3, e0-e2, e1-e3]
            # 8.5.11.2: dcC = ((f * LevelScale(qPc%6,0,0)) << (qPc/6)) >> 5,
            # und LevelScale traegt auch hier die flache 16 (siehe
            # scale_block). Ohne sie sitzt das ganze Chroma um einen
            # festen Betrag daneben -- das Muster stimmt, die Hoehe nicht.
            m=qpc%6; sh=qpc//6
            w=VMAT[m][0]*16
            for i in range(4):
                dq[i]=((t[i]*w)<<sh)>>5
        for i in range(4):
            bx=i&1; by=i>>1
            blk=cac[c][i][:] if (cbp>>4)==2 else [0]*16
            sc=scale_block(blk,qpc)
            sc[0]=dq[i]
            res=idct4(sc)
            px=mbx*8+bx*4; py=mby*8+by*4
            for y in range(4):
                for x in range(4):
                    base = P[(by*4+y)*8+bx*4+x] if P is not None \
                           else plane[(py+y)*CW+px+x]
                    plane[(py+y)*CW+px+x]=clip(base+((res[y*4+x]+32)>>6))

# ====================================================== Deblocking, 8.7
#
# Die drei Tafeln kommen MECHANISCH aus FFmpegs h264_loopfilter.c
# (alpha_table, beta_table, tc0_table). Sie sind je 52*3 lang: der
# Index ist qp + Versatz + 52, damit ein negativer Versatz nicht unter
# null greift. Genau diese Verschiebung steht auch hier.
ALPHA_TABLE=[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 4, 5, 6, 7, 8, 9, 10, 12, 13, 15, 17, 20, 22, 25, 28, 32, 36, 40, 45, 50, 56, 63, 71, 80, 90, 101, 113, 127, 144, 162, 182, 203, 226, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255]
BETA_TABLE=[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15, 16, 16, 17, 17, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18]
TC0_TABLE=[[1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0], [1, 0, 0, 1], [1, 0, 0, 1], [1, 0, 0, 1], [1, 0, 0, 1], [1, 0, 1, 1], [1, 0, 1, 1], [1, 1, 1, 1], [1, 1, 1, 1], [1, 1, 1, 1], [1, 1, 1, 1], [1, 1, 1, 2], [1, 1, 1, 2], [1, 1, 1, 2], [1, 1, 1, 2], [1, 1, 2, 3], [1, 1, 2, 3], [1, 2, 2, 3], [1, 2, 2, 4], [1, 2, 3, 4], [1, 2, 3, 4], [1, 3, 3, 5], [1, 3, 4, 6], [1, 3, 4, 6], [1, 4, 5, 7], [1, 4, 5, 8], [1, 4, 6, 9], [1, 5, 7, 10], [1, 6, 8, 11], [1, 6, 8, 13], [1, 7, 10, 14], [1, 8, 11, 16], [1, 9, 12, 18], [1, 10, 13, 20], [1, 11, 15, 23], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25], [1, 13, 17, 25]]

def _clip3(lo,hi,v):
    return lo if v<lo else (hi if v>hi else v)

def _bs(mbP,iP,mbQ,iQ,mb_edge):
    """8.7.2.1 -- die Filterstaerke zweier benachbarter 4x4-Bloecke."""
    if mbP.intra or mbQ.intra:
        return 4 if mb_edge else 3
    if mbP.nz[iP]>0 or mbQ.nz[iQ]>0:
        return 2
    if mbP.ref[iP]!=mbQ.ref[iQ]: return 1
    if abs(mbP.mvx[iP]-mbQ.mvx[iQ])>=4: return 1
    if abs(mbP.mvy[iP]-mbQ.mvy[iQ])>=4: return 1
    return 0

def _filter_line(plane, base, st, bs, alpha, beta, tc0, chroma):
    """Eine Linie ueber eine Kante. `st` ist der Schritt SENKRECHT zur
    Kante (1 bei senkrechter Kante, W bei waagerechter); `base` zeigt
    auf q0, also auf den ersten Punkt HINTER der Kante."""
    p0=plane[base-st];   q0=plane[base]
    p1=plane[base-2*st]; q1=plane[base+st]
    if not (abs(p0-q0)<alpha and abs(p1-p0)<beta and abs(q1-q0)<beta):
        return
    if bs<4:
        if chroma:
            tc=tc0+1
            delta=_clip3(-tc,tc,((((q0-p0)<<2)+(p1-q1)+4)>>3))
            plane[base-st]=clip(p0+delta)
            plane[base]=clip(q0-delta)
        else:
            p2=plane[base-3*st]; q2=plane[base+2*st]
            ap=abs(p2-p0); aq=abs(q2-q0)
            tc=tc0+(1 if ap<beta else 0)+(1 if aq<beta else 0)
            delta=_clip3(-tc,tc,((((q0-p0)<<2)+(p1-q1)+4)>>3))
            if ap<beta:
                plane[base-2*st]=p1+_clip3(-tc0,tc0,
                    (p2+((p0+q0+1)>>1)-2*p1)>>1)
            if aq<beta:
                plane[base+st]=q1+_clip3(-tc0,tc0,
                    (q2+((p0+q0+1)>>1)-2*q1)>>1)
            plane[base-st]=clip(p0+delta)
            plane[base]=clip(q0-delta)
    else:
        if chroma:
            plane[base-st]=(2*p1+p0+q1+2)>>2
            plane[base]=(2*q1+q0+p1+2)>>2
        else:
            p2=plane[base-3*st]; q2=plane[base+2*st]
            p3=plane[base-4*st]; q3=plane[base+3*st]
            ap=abs(p2-p0); aq=abs(q2-q0)
            klein=abs(p0-q0)<((alpha>>2)+2)
            if ap<beta and klein:
                plane[base-st]=(p2+2*p1+2*p0+2*q0+q1+4)>>3
                plane[base-2*st]=(p2+p1+p0+q0+2)>>2
                plane[base-3*st]=(2*p3+3*p2+p1+p0+q0+4)>>3
            else:
                plane[base-st]=(2*p1+p0+q1+2)>>2
            if aq<beta and klein:
                plane[base]=(q2+2*q1+2*q0+2*p0+p1+4)>>3
                plane[base+st]=(q2+q1+q0+p0+2)>>2
                plane[base+2*st]=(2*q3+3*q2+q1+q0+p0+4)>>3
            else:
                plane[base]=(2*q1+q0+p1+2)>>2

def _deblock(d,sps,pps):
    """8.7: Makroblock fuer Makroblock in Rasterfolge, je MB zuerst
    ALLE senkrechten Kanten (links nach rechts), dann alle
    waagerechten (oben nach unten)."""
    f=d.cur; W=f.w; CW=f.cw
    aoff=d.alpha_off; boff=d.beta_off
    for mby in range(sps.mbh):
        for mbx in range(sps.mbw):
            mbQ=d.mbs[mby*sps.mbw+mbx]
            for e in range(4):
                if e==0:
                    if mbx==0: continue
                    mbP=d.mbs[mby*sps.mbw+mbx-1]
                else:
                    mbP=mbQ
                for y in range(16):
                    by=y>>2
                    iQ=by*4+e
                    iP=by*4+(e-1) if e>0 else by*4+3
                    s=_bs(mbP,iP,mbQ,iQ,e==0)
                    if s==0: continue
                    qp=(mbP.qp+mbQ.qp+1)>>1
                    ia=_clip3(0,51,qp+aoff)+52
                    ib=_clip3(0,51,qp+boff)+52
                    alpha=ALPHA_TABLE[ia]; beta=BETA_TABLE[ib]
                    if alpha==0 or beta==0: continue
                    tc0=TC0_TABLE[ia][s] if s<4 else 0
                    base=(mby*16+y)*W+mbx*16+e*4
                    _filter_line(f.Y,base,1,s,alpha,beta,tc0,False)
                if e%2==0:
                    # Chroma ist halb so gross: die Kante e (0 oder 2)
                    # liegt bei Chromaspalte e*2. Die Filterstaerke
                    # kommt aus DEMSELBEN 4x4-Luma-Blockpaar wie oben --
                    # also mit den Luma-Indizes, nicht mit halbierten.
                    for y in range(8):
                        by=y>>1              # Chromazeile -> Luma-4x4-Zeile
                        iQ=by*4+e
                        iP=by*4+(e-1) if e>0 else by*4+3
                        s=_bs(mbP,iP,mbQ,iQ,e==0)
                        if s==0: continue
                        qp=(qpc_of(mbP.qp+pps.chroma_qp_off)
                            +qpc_of(mbQ.qp+pps.chroma_qp_off)+1)>>1
                        ia=_clip3(0,51,qp+aoff)+52
                        ib=_clip3(0,51,qp+boff)+52
                        alpha=ALPHA_TABLE[ia]; beta=BETA_TABLE[ib]
                        if alpha==0 or beta==0: continue
                        tc0=TC0_TABLE[ia][s] if s<4 else 0
                        base=(mby*8+y)*CW+mbx*8+e*2
                        _filter_line(f.U,base,1,s,alpha,beta,tc0,True)
                        _filter_line(f.V,base,1,s,alpha,beta,tc0,True)
            for e in range(4):
                if e==0:
                    if mby==0: continue
                    mbP=d.mbs[(mby-1)*sps.mbw+mbx]
                else:
                    mbP=mbQ
                for x in range(16):
                    bx=x>>2
                    iQ=e*4+bx
                    iP=(e-1)*4+bx if e>0 else 3*4+bx
                    s=_bs(mbP,iP,mbQ,iQ,e==0)
                    if s==0: continue
                    qp=(mbP.qp+mbQ.qp+1)>>1
                    ia=_clip3(0,51,qp+aoff)+52
                    ib=_clip3(0,51,qp+boff)+52
                    alpha=ALPHA_TABLE[ia]; beta=BETA_TABLE[ib]
                    if alpha==0 or beta==0: continue
                    tc0=TC0_TABLE[ia][s] if s<4 else 0
                    base=(mby*16+e*4)*W+mbx*16+x
                    _filter_line(f.Y,base,W,s,alpha,beta,tc0,False)
                if e%2==0:
                    for x in range(8):
                        bx=x>>1
                        iQ=e*4+bx
                        iP=(e-1)*4+bx if e>0 else 3*4+bx
                        s=_bs(mbP,iP,mbQ,iQ,e==0)
                        if s==0: continue
                        qp=(qpc_of(mbP.qp+pps.chroma_qp_off)
                            +qpc_of(mbQ.qp+pps.chroma_qp_off)+1)>>1
                        ia=_clip3(0,51,qp+aoff)+52
                        ib=_clip3(0,51,qp+boff)+52
                        alpha=ALPHA_TABLE[ia]; beta=BETA_TABLE[ib]
                        if alpha==0 or beta==0: continue
                        tc0=TC0_TABLE[ia][s] if s<4 else 0
                        base=(mby*8+e*2)*CW+mbx*8+x
                        _filter_line(f.U,base,CW,s,alpha,beta,tc0,True)
                        _filter_line(f.V,base,CW,s,alpha,beta,tc0,True)

def deblock_frame(d,sps,pps):
    if getattr(d,'disable_deblock',0)==1: return
    _deblock(d,sps,pps)

def dump_yuv(frames, path):
    with open(path,'wb') as fh:
        for f in frames:
            fh.write(bytes(f.Y)); fh.write(bytes(f.U)); fh.write(bytes(f.V))
