#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/eckpruef.py -- LIEGT FUELLFARBE AUSSERHALB DES RADIUS?
#
# Justins Befund von echter Hardware: hinter der abgerundeten Flaeche
# (Tooltip, Kontrollzentrum) ist ein RECHTECK sichtbar. Das ist keine
# Geschmacksfrage, das ist nachrechenbar:
#
#   Eine Flaeche mit Eckradius r darf in ihren vier Eckquadraten
#   (r x r) KEINEN Bildpunkt ihrer Fuellfarbe haben, dessen Abstand
#   vom Eckmittelpunkt groesser als r ist.
#
# Dieses Werkzeug findet die Flaeche selbst (groesster zusammenhaengender
# Block einer Farbe), bestimmt ihren Radius aus dem Bild und zaehlt die
# Punkte, die ausserhalb liegen. Ausgabe: Zahlen, keine Meinung.
import sys, struct, zlib
from collections import Counter

def readpng(p):
    d=open(p,'rb').read(); pos=8; idat=b''; pal=None; ct=2
    while pos<len(d):
        ln=struct.unpack('>I',d[pos:pos+4])[0]; t=d[pos+4:pos+8]
        if t==b'IHDR': w,h,bd,ct=struct.unpack('>IIBB',d[pos+8:pos+18])[:4]
        elif t==b'PLTE': pal=d[pos+8:pos+8+ln]
        elif t==b'IDAT': idat+=d[pos+8:pos+8+ln]
        pos+=12+ln
    raw=zlib.decompress(idat)
    bpp={0:1,2:3,3:1,4:2,6:4}[ct]; stride=w*bpp
    out=bytearray(); prev=bytearray(stride); i=0
    for y in range(h):
        f=raw[i]; i+=1; line=bytearray(raw[i:i+stride]); i+=stride
        for x in range(stride):
            a=line[x-bpp] if x>=bpp else 0; b=prev[x]; c=prev[x-bpp] if x>=bpp else 0
            if f==1: line[x]=(line[x]+a)&255
            elif f==2: line[x]=(line[x]+b)&255
            elif f==3: line[x]=(line[x]+((a+b)>>1))&255
            elif f==4:
                pp=a+b-c; pa=abs(pp-a);pb=abs(pp-b);pc=abs(pp-c)
                pr=a if (pa<=pb and pa<=pc) else (b if pb<=pc else c)
                line[x]=(line[x]+pr)&255
        out+=line; prev=line
    px=[]
    for y in range(h):
        row=[]
        for x in range(w):
            if ct==3:
                k=out[y*stride+x]; row.append(tuple(pal[k*3:k*3+3]))
            elif ct==6:
                o=y*stride+x*4; row.append(tuple(out[o:o+3]))
            else:
                o=y*stride+x*3; row.append(tuple(out[o:o+3]))
        px.append(row)
    return w,h,px

def flaechen(px,w,h,minflaeche=2000):
    """Rechteckige Bloecke einer Farbe finden (Zeilenlauf-Verfahren)."""
    c=Counter()
    for y in range(0,h,2):
        for x in range(0,w,2):
            c[px[y][x]]+=1
    out=[]
    for farbe,n in c.most_common(8):
        if n*4<minflaeche: continue
        xs=[];ys=[]
        for y in range(h):
            for x in range(w):
                if px[y][x]==farbe: xs.append(x);ys.append(y)
        if not xs: continue
        bx0,by0,bx1,by1=min(xs),min(ys),max(xs),max(ys)
        # Nur echte KAESTEN: die Farbe muss den Rahmen weitgehend
        # ausfuellen. Ein Farbverlauf auf dem Schreibtisch belegt zwar
        # eine grosse Flaeche, fuellt seinen Rahmen aber nur duenn.
        flaeche=(bx1-bx0+1)*(by1-by0+1)
        if flaeche==0 or len(xs)*100//flaeche < 60: continue
        # und der Schreibtisch selbst (fast das ganze Bild) faellt weg
        if flaeche > w*h*70//100: continue
        out.append((farbe,bx0,by0,bx1,by1,len(xs)))
    return out

def eckpruef(px,w,h,farbe,x0,y0,x1,y1,rmax=32):
    """Radius aus dem Bild bestimmen und Ausreisser zaehlen."""
    # Radius: wie weit ist die Fuellung in der obersten Zeile eingerueckt?
    obere=[x for x in range(x0,x1+1) if px[y0][x]==farbe]
    if not obere: return None
    r=obere[0]-x0
    if r<1 or r>rmax: r=0
    aus=0; gepr=0
    if r>0:
        for (cx,cy,sx,sy) in ((x0+r,y0+r,-1,-1),(x1-r,y0+r,1,-1),
                              (x0+r,y1-r,-1,1),(x1-r,y1-r,1,1)):
            for dy in range(r):
                for dx in range(r):
                    X=cx+sx*(r-dx); Y=cy+sy*(r-dy)
                    if not (0<=X<w and 0<=Y<h): continue
                    gepr+=1
                    d2=(r-dx)**2+(r-dy)**2
                    if d2>(r+0.5)**2 and px[Y][X]==farbe: aus+=1
    return r,aus,gepr

if __name__=='__main__':
    print("%-44s %-16s %5s %6s %6s %s"%("Bild","Farbe","Radius","ausserhalb","geprueft","Urteil"))
    for f in sys.argv[1:]:
        w,h,px=readpng(f)
        for (farbe,x0,y0,x1,y1,n) in flaechen(px,w,h):
            if (x1-x0)<40 or (y1-y0)<40: continue
            e=eckpruef(px,w,h,farbe,x0,y0,x1,y1)
            if not e: continue
            r,aus,gepr=e
            if r==0: continue
            print("%-44s %-16s %5d %6d %6d %s"%(f.split('/')[-1],"#%02x%02x%02x"%farbe,r,aus,gepr,
                  "OK" if aus==0 else "RECHTECK SICHTBAR"))
