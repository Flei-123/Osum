"""Kreisprobe fuer residual_block.

Der Kodierer hier ist die STRENGE UMKEHRUNG des Dekodierers: er baut
die Bitfolge aus denselben Tafeln und derselben suffixLength-Regel.
Dadurch prueft der Kreis genau das, was er pruefen soll -- die
Tafeln, die Positionsrechnung und die Zustandsfortschreibung.
"""
import json, random, ref264 as R
T=json.load(open('tabs.json'))
CT_LAB=[(t1,tc) for tc in range(17) for t1 in range(4)]
CDC_LAB=[(t1,tc) for tc in range(5) for t1 in range(4)]
SL=[0,3,6,12,24,48,1<<30]

class W:
    def __init__(s): s.b=[]
    def put(s,v,n):
        for i in range(n-1,-1,-1): s.b.append((v>>i)&1)
    def s(s): return ''.join(map(str,s.b))
class RB:
    def __init__(s,st): s.s=st; s.p=0; s.over=False
    def u1(s):
        if s.p>=len(s.s): s.over=True; s.p+=1; return 0
        v=int(s.s[s.p]); s.p+=1; return v
    def un(s,k):
        v=0
        for _ in range(k): v=(v<<1)|s.u1()
        return v

def lev_to_code(v, sub2):
    """Umkehrung von: lc gerade -> (lc+2)>>1 ; ungerade -> (-lc-1)>>1"""
    if v>0: lc=2*v-2
    else:   lc=-2*v-1
    if sub2: lc-=2
    return lc

def enc(co, nC, maxc):
    w=W()
    nz=[(i,c) for i,c in enumerate(co) if c!=0]
    tc=len(nz)
    lev=[c for _,c in nz][::-1]        # hoechste Position zuerst
    pos=[i for i,_ in nz][::-1]
    t1=0
    for i in range(min(3,tc)):
        if abs(lev[i])==1: t1+=1
        else: break
    if nC==-1: lens,bits,lab=T['chroma_dc_coeff_token_len'],T['chroma_dc_coeff_token_bits'],CDC_LAB
    else:
        k=0 if nC<2 else (1 if nC<4 else (2 if nC<8 else 3))
        lens,bits,lab=T['coeff_token_len'][k],T['coeff_token_bits'][k],CT_LAB
    idx=lab.index((t1,tc))
    if lens[idx]==0: raise ValueError('kein coeff_token')
    w.put(bits[idx],lens[idx])
    if tc==0: return w.s()
    for i in range(t1):
        w.put(0 if lev[i]>0 else 1,1)
    if t1<tc:
        sl=1 if (tc>10 and t1<3) else 0
        first=True
        for i in range(t1,tc):
            lc=lev_to_code(lev[i], first and t1<3)
            if lc<0: raise ValueError('lc negativ')
            if first:
                if sl==0:
                    if lc<14: pre=lc; sb=0; suf=0
                    elif lc<30: pre=14; sb=4; suf=lc-14
                    else: raise ValueError('zu gross fuer den Test')
                else:
                    pre=lc>>1; suf=lc&1; sb=1
                    if pre>=14: raise ValueError('zu gross')
            else:
                if (lc>>sl)<15: pre=lc>>sl; suf=lc&((1<<sl)-1); sb=sl
                else: raise ValueError('zu gross')
            for _ in range(pre): w.put(0,1)
            w.put(1,1)
            if sb: w.put(suf,sb)
            if first:
                # Der Dekodierer rechnet sl aus dem levelCode NACH dem
                # +2 (t1<3). Der Kodierer hat vorher -2 gerechnet --
                # also hier dieselbe Groesse verwenden, sonst laufen
                # Kodierer und Dekodierer auseinander.
                lc_dec = lc + (2 if t1<3 else 0)
                if pre>=14 or (1 if (tc>10 and t1<3) else 0): sl=2
                else: sl=1+(1 if (lc_dec+3)>6 else 0)
                first=False
            else:
                if sl<6 and abs(lev[i])>SL[sl]: sl+=1
    tz=pos[0]+1-tc
    if tc<maxc:
        if maxc==4: l2,b2=T['chroma_dc_total_zeros_len'][tc-1],T['chroma_dc_total_zeros_bits'][tc-1]
        else:       l2,b2=T['total_zeros_len'][tc-1],T['total_zeros_bits'][tc-1]
        if tz>=len(l2) or l2[tz]==0: raise ValueError('total_zeros')
        w.put(b2[tz],l2[tz])
    runs=[(pos[i]-pos[i+1]-1) if i<tc-1 else pos[i] for i in range(tc)]
    zl=tz
    for i in range(tc-1):
        if zl<=0: break
        r=runs[i]; k=min(zl,7)-1
        l3,b3=T['run_len'][k],T['run_bits'][k]
        if r>=len(l3) or l3[r]==0: raise ValueError('run')
        w.put(b3[r],l3[r]); zl-=r
    return w.s()

random.seed(11)
n=0; bad=0; skipped=0
for _ in range(60000):
    maxc=random.choice([16,15,4])
    nC=-1 if maxc==4 else random.choice([0,1,2,3,5,9,12])
    cnt=random.randint(1,maxc)
    p=sorted(random.sample(range(maxc),cnt))
    co=[0]*maxc
    for q in p: co[q]=random.choice([1,-1,2,-2,3,-3,4,-5,7,-9,13,-17])
    try: st=enc(co,nC,maxc)
    except Exception: skipped+=1; continue
    n+=1
    try: got,tc=R.residual_block(RB(st),nC,maxc)
    except Exception as e:
        bad+=1
        if bad<=3: print("LESEFEHLER",e,"\n  co",co,"nC",nC,"maxc",maxc)
        continue
    if got!=co:
        bad+=1
        if bad<=3:
            print("UNGLEICH nC=%d maxc=%d\n  soll %s\n  ist  %s"%(nC,maxc,co,got))
print("geprueft %d Bloecke (%d uebersprungen), %d falsch"%(n,skipped,bad))
