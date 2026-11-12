import sys,collections,subprocess,bisect
f=sys.argv[1]; elf=sys.argv[2]; t0=float(sys.argv[3])
syms=[]
for l in subprocess.run(["nm","-n",elf],capture_output=True,text=True).stdout.splitlines():
    p=l.split()
    if len(p)==3 and p[1] in "tTwW": syms.append((int(p[0],16),p[2]))
addrs=[a for a,_ in syms]
def ks(a):
    i=bisect.bisect_right(addrs,a)-1
    return syms[i][1].replace("_F0.","") if i>=0 else "?"
h=collections.Counter(); n=0; leafw=collections.Counter(); unk=0
for l in open(f):
    p=l.split()
    if len(p)<3 or float(p[0])<t0: continue
    if int(p[1],16)&3: continue
    n+=1
    fr=[ks(int(p[2],16))]+([ks(int(x,16)) for x in p[3].split(",")] if len(p)>3 else [])
    if "pwr__idle_wait" in fr: h["IDLE"]+=1; continue
    idx=-1
    for i,s in enumerate(fr):
        if s in("sys__dispatch","sys__entry","trap__entry"): idx=i;break
    if idx<=0:
        h["?top:"+fr[0]]+=1; continue
    h[fr[idx]+"<-"+fr[idx-1]]+=1
    if fr[0] in("blk__cg","blk__wg","regio__read32_at","blk__copy"):
        leafw[fr[0]+" <- "+" <- ".join(fr[1:4])]+=1
print("kernel",n)
for s,c in h.most_common(40): print("%5d %5.1f%% %s"%(c,100*c/n,s))
print("--- leaf callers")
for s,c in leafw.most_common(16): print(c,s)
