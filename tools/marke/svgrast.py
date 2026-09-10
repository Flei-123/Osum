#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# Rastert die SVG-Pfade des Signets in Zielgroesse -- dieselbe Regel wie
# kernel/vektor.fi: Kanten aus Bezier-Unterteilung, nonzero-Fuellregel,
# 4x4 Ueberabtastung.
import re, sys

def toks(d):
    return re.findall(r'([MmLlCcZzHhVv])|(-?\d*\.?\d+(?:[eE][-+]?\d+)?)', d)

def pfad_punkte(d, tol=0.2):
    """Gibt Liste von Konturen (Liste von (x,y)) zurueck."""
    it = toks(d); i = 0
    konturen=[]; akt=[]; cx=cy=0.0; sx=sy=0.0; cmd=None
    def num():
        nonlocal i
        while i < len(it) and it[i][1]=='' : i+=1
        v=float(it[i][1]); i+=1; return v
    while i < len(it):
        if it[i][0]:
            cmd=it[i][0]; i+=1
        if cmd in ('M','m'):
            x=num(); y=num()
            if cmd=='m': x+=cx; y+=cy
            if len(akt)>1: konturen.append(akt)
            akt=[(x,y)]; cx,cy=x,y; sx,sy=x,y
            cmd='L' if cmd=='M' else 'l'
        elif cmd in ('L','l'):
            x=num(); y=num()
            if cmd=='l': x+=cx; y+=cy
            akt.append((x,y)); cx,cy=x,y
        elif cmd in ('H','h'):
            x=num()
            if cmd=='h': x+=cx
            akt.append((x,cy)); cx=x
        elif cmd in ('V','v'):
            y=num()
            if cmd=='v': y+=cy
            akt.append((cx,y)); cy=y
        elif cmd in ('C','c'):
            x1=num();y1=num();x2=num();y2=num();x=num();y=num()
            if cmd=='c': x1+=cx;y1+=cy;x2+=cx;y2+=cy;x+=cx;y+=cy
            # adaptive Unterteilung nach Sehnenlaenge
            n=max(3,int((abs(x1-cx)+abs(y1-cy)+abs(x2-x1)+abs(y2-y1)+abs(x-x2)+abs(y-y2))/tol))
            n=min(n,64)
            for k in range(1,n+1):
                t=k/n; mt=1-t
                px=mt**3*cx+3*mt*mt*t*x1+3*mt*t*t*x2+t**3*x
                py=mt**3*cy+3*mt*mt*t*y1+3*mt*t*t*y2+t**3*y
                akt.append((px,py))
            cx,cy=x,y
        elif cmd in ('Z','z'):
            if len(akt)>1:
                akt.append((sx,sy)); konturen.append(akt)
            akt=[(sx,sy)]; cx,cy=sx,sy
            i+=0
            if i<len(it) and not it[i][0]: pass
        else:
            i+=1
    if len(akt)>1: konturen.append(akt)
    return konturen

def rastern(pfade, groesse, vb, ss=4):
    """pfade: Liste (konturen, (r,g,b)). Gibt RGBA-Bytes zurueck."""
    W=H=groesse
    vx,vy,vw,vh = vb
    acc=[[None]*(W) for _ in range(H)]   # (r,g,b,a) akkumuliert
    for konturen, farbe in pfade:
        # Kantenliste in Geraetekoordinaten
        kanten=[]
        for k in konturen:
            pts=[((px-vx)*W/vw, (py-vy)*H/vh) for px,py in k]
            for a in range(len(pts)-1):
                x0,y0=pts[a]; x1,y1=pts[a+1]
                if y0!=y1: kanten.append((x0,y0,x1,y1))
        if not kanten: continue
        for py in range(H):
            deck=[0]*W
            for sub in range(ss):
                yy=py+(sub+0.5)/ss
                xs=[]
                for x0,y0,x1,y1 in kanten:
                    if (y0<=yy<y1) or (y1<=yy<y0):
                        t=(yy-y0)/(y1-y0)
                        xs.append((x0+t*(x1-x0), 1 if y1>y0 else -1))
                if not xs: continue
                xs.sort()
                wind=0; start=0.0
                for xv,d in xs:
                    if wind!=0:
                        a0=max(0.0,start); a1=min(float(W),xv)
                        if a1>a0:
                            i0=int(a0); i1=int(a1)
                            for px in range(i0,min(i1+1,W)):
                                l=max(a0,px); r=min(a1,px+1)
                                if r>l: deck[px]+=(r-l)
                    wind+=d
                    if wind!=0 and (wind-d)==0: start=xv
            for px in range(W):
                a=deck[px]/ss
                if a<=0: continue
                if a>1: a=1
                old=acc[py][px]
                r,g,b=farbe
                if old is None:
                    acc[py][px]=(r,g,b,a)
                else:
                    orr,og,ob,oa=old
                    na=a+oa*(1-a)
                    if na<=0: continue
                    nr=(r*a+orr*oa*(1-a))/na
                    ng=(g*a+og*oa*(1-a))/na
                    nb=(b*a+ob*oa*(1-a))/na
                    acc[py][px]=(nr,ng,nb,na)
    out=bytearray()
    for py in range(H):
        for px in range(W):
            v=acc[py][px]
            if v is None: out+=bytes((0,0,0,0))
            else:
                r,g,b,a=v
                out+=bytes((int(r+0.5),int(g+0.5),int(b+0.5),int(a*255+0.5)))
    return bytes(out)

def _mat(a,b):
    """a nach b verketten (a wird zuerst angewandt? nein: b innen, a aussen)."""
    (a0,a1,a2,a3,a4,a5)=a; (b0,b1,b2,b3,b4,b5)=b
    return (a0*b0+a2*b1, a1*b0+a3*b1, a0*b2+a2*b3, a1*b2+a3*b3,
            a0*b4+a2*b5+a4, a1*b4+a3*b5+a5)

def _parse_tf(t):
    m=(1,0,0,1,0,0)
    for name,args in re.findall(r'(translate|scale|matrix|rotate)\s*\(([^)]*)\)', t):
        v=[float(x) for x in re.split(r'[,\s]+', args.strip()) if x]
        if name=='translate':
            tm=(1,0,0,1,v[0], v[1] if len(v)>1 else 0.0)
        elif name=='scale':
            sx=v[0]; sy=v[1] if len(v)>1 else v[0]
            tm=(sx,0,0,sy,0,0)
        elif name=='matrix':
            tm=tuple(v[:6])
        else:
            continue
        m=_mat(m,tm)
    return m

def _anwenden(m,x,y):
    return (m[0]*x+m[2]*y+m[4], m[1]*x+m[3]*y+m[5])

def lade_svg(p):
    """Liest die Pfade MIT der Transformationskette ihrer <g>-Eltern.
    Ohne das liegen die Koordinaten im Zehntausenderbereich (potrace
    schreibt sie so und stellt sie per translate/scale zurecht)."""
    s=open(p).read()
    vb=[float(x) for x in re.search(r'viewBox="([^"]*)"',s).group(1).split()]
    pfade=[]
    stapel=[(1,0,0,1,0,0)]
    fuell=[(0,0,0)]
    for m in re.finditer(r'<g([^>]*)>|</g>|<path([^>]*)/?>', s):
        tag=m.group(0)
        if tag.startswith('</g'):
            if len(stapel)>1: stapel.pop(); fuell.pop()
            continue
        if tag.startswith('<g'):
            at=m.group(1)
            tm=re.search(r'transform="([^"]*)"',at)
            cur=stapel[-1]
            if tm: cur=_mat(cur,_parse_tf(tm.group(1)))
            stapel.append(cur)
            fm=re.search(r'fill="#([0-9A-Fa-f]{6})"',at)
            if fm:
                h=fm.group(1); fuell.append((int(h[0:2],16),int(h[2:4],16),int(h[4:6],16)))
            else:
                fuell.append(fuell[-1])
            continue
        at=m.group(2) or ''
        dm=re.search(r'd="([^"]*)"',at)
        if not dm: continue
        cur=stapel[-1]
        tm=re.search(r'transform="([^"]*)"',at)
        if tm: cur=_mat(cur,_parse_tf(tm.group(1)))
        fm=re.search(r'fill="#([0-9A-Fa-f]{6})"',at)
        col=fuell[-1]
        if fm:
            h=fm.group(1); col=(int(h[0:2],16),int(h[2:4],16),int(h[4:6],16))
        kont=pfad_punkte(dm.group(1))
        kont=[[_anwenden(cur,x,y) for x,y in k] for k in kont]
        pfade.append((kont, col))
    return pfade, vb


# ============================================================ RUNDE VEKTOR
# WOZU DIESE DATEI. Das Startzeichen lag als 832x1248-JPEG-FOTO im Baum
# (assets/marke/osum-vorlage-justin.jpg) und wurde daraus mit LANCZOS auf
# 16/24/32/48/64 verkleinert. Ein Foto hat keine Kanten, sondern
# Uebergaenge samt JPEG-Ringen -- deshalb sah der Knopf auf Justins
# Schirm auch dann noch grob aus, als die Groessen endlich stimmten.
#
# Die ECHTE Vektorfassung desselben Zeichens liegt in einem anderen Baum
# (assets/marke/osum-signet-*.svg im OrientOS-Ablegen, "FESTGELEGT
# (Runde 5)", mit potrace aus derselben Vorlage gewonnen): 12 Pfade,
# reine kubische Beziers, drei Markenfarben. Daraus wird hier in
# ZIELGROESSE gerastert -- mit derselben Regel wie kernel/vektor.fi
# (Bezier-Unterteilung nach Sehnenlaenge, nonzero-Fuellregel, 4x4
# Ueberabtastung).
#
# GEMESSEN, harte Farbspruenge zwischen Nachbarpunkten (weniger ist
# glatter) gegen weiche Uebergaenge:
#     Groesse | alt (aus dem Foto) | neu (aus den Pfaden)
#       32    | 214 hart / 152 weich |  25 hart / 102 weich
#       48    | 392 / 219            |  41 / 156
#       64    | 609 / 295            |  58 / 207
# Bei 64 sind das 90 Prozent weniger harte Spruenge. Das ist der
# Unterschied zwischen "gerastert" und "hochgezogen".
#
#   python3 tools/marke/svgrast.py <signet.svg> <ausgabeordner>

def _png(px, w, h, fn):
    import struct, zlib
    raw = b''.join(b'\x00' + px[y * w * 4:(y + 1) * w * 4] for y in range(h))
    def ch(t, d):
        return (struct.pack('>I', len(d)) + t + d
                + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff))
    open(fn, 'wb').write(
        b'\x89PNG\r\n\x1a\n'
        + ch(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
        + ch(b'IDAT', zlib.compress(raw, 9)) + ch(b'IEND', b''))


def signet_pfade(svg):
    """Nur die Pfade INNERHALB der viewBox. Die Lockup-Dateien haben die
    Wortmarke rechts daneben liegen -- die gehoert nicht auf den Knopf."""
    pfade, vb = lade_svg(svg)
    innen = [(k, c) for k, c in pfade
             if max(x for kk in k for x, y in kk) <= vb[2] + 1]
    return innen, vb


if __name__ == '__main__':
    import sys, os
    svg = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else 'assets/marke'
    pf, vb = signet_pfade(svg)
    for g in (16, 24, 32, 48, 64):
        d = rastern(pf, g, vb, ss=4)
        ziel = os.path.join(out, 'start-%d.png' % g)
        _png(d, g, g, ziel)
        voll = sum(1 for i in range(3, len(d), 4) if d[i] >= 243)
        kant = sum(1 for i in range(3, len(d), 4) if 12 < d[i] < 243)
        print('%s  deckend=%d kantenpunkte=%d' % (ziel, voll, kant))
