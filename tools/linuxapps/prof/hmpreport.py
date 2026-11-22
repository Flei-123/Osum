import sys,collections,subprocess,bisect
f=sys.argv[1]; elf=sys.argv[2]; top=int(sys.argv[3]); t0=float(sys.argv[4])
syms=[]
for l in subprocess.run(["nm","-n",elf],capture_output=True,text=True).stdout.splitlines():
    p=l.split()
    if len(p)==3 and p[1] in "tTwW": syms.append((int(p[0],16),p[2]))
addrs=[a for a,_ in syms]
def ks(a):
    i=bisect.bisect_right(addrs,a)-1
    return syms[i][1].replace("_F0.","") if i>=0 else "?"
inc=collections.Counter(); leaf=collections.Counter(); n=0; nu=0
win=len(sys.argv)>5
marks={}
lines=open(f).read().splitlines()
for l in lines:
    if l.startswith("#"):
        _,t,run,kind=l.split(); marks[(int(run),kind)]=float(t)
spans=[(marks[(r,sys.argv[5])],marks[(r,"rc")]) for r in range(2,99) if win and (r,sys.argv[5]) in marks and (r,"rc") in marks]
for l in lines:
    if l.startswith("#"): continue
    p=l.split()
    if win and not any(a<=float(p[0])<=b for a,b in spans): continue
    if len(p)<3 or float(p[0])<t0: continue
    if int(p[1],16)&3: nu+=1; continue
    n+=1
    fr=[ks(int(p[2],16))]+([ks(int(x,16)) for x in p[3].split(",")] if len(p)>3 else [])
    leaf[fr[0]]+=1
    for s in set(fr): inc[s]+=1
print("kernel",n,"user",nu)
for s,c in inc.most_common(top): print("%5d %5.1f%% %s"%(c,100.0*c/max(n,1),s))
