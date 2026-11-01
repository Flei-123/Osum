#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
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
    c=Counter()
    for y in range(0,h,2):
        for x in range(0,w,2):
            c[px[y][x]]+=1
    out=[]
    for color,n in c.most_common(8):
        if n*4<minflaeche: continue
        xs=[];ys=[]
        for y in range(h):
            for x in range(w):
                if px[y][x]==color: xs.append(x);ys.append(y)
        if not xs: continue
        bx0,by0,bx1,by1=min(xs),min(ys),max(xs),max(ys)
        area=(bx1-bx0+1)*(by1-by0+1)
        if area==0 or len(xs)*100//area < 60: continue
        if area > w*h*70//100: continue
        out.append((color,bx0,by0,bx1,by1,len(xs)))
    return out

def eckpruef(px,w,h,color,x0,y0,x1,y1,rmax=32):
    obere=[x for x in range(x0,x1+1) if px[y0][x]==color]
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
                    if d2>(r+0.5)**2 and px[Y][X]==color: aus+=1
    return r,aus,gepr

if __name__=='__main__':
    print("%-44s %-16s %5s %6s %6s %s"%("Bild","Farbe","Radius","ausserhalb","geprueft","Urteil"))
    for f in sys.argv[1:]:
        w,h,px=readpng(f)
        for (color,x0,y0,x1,y1,n) in flaechen(px,w,h):
            if (x1-x0)<40 or (y1-y0)<40: continue
            e=eckpruef(px,w,h,color,x0,y0,x1,y1)
            if not e: continue
            r,aus,gepr=e
            if r==0: continue
            print("%-44s %-16s %5d %6d %6d %s"%(f.split('/')[-1],"#%02x%02x%02x"%color,r,aus,gepr,
                  "OK" if aus==0 else "RECHTECK SICHTBAR"))
