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
for l in open(f):
    p=l.split()
    if len(p)<3 or float(p[0])<t0: continue
    if int(p[1],16)&3: nu+=1; continue
    n+=1
    fr=[ks(int(p[2],16))]+([ks(int(x,16)) for x in p[3].split(",")] if len(p)>3 else [])
    leaf[fr[0]]+=1
    for s in set(fr): inc[s]+=1
print("kernel",n,"user",nu)
for s,c in inc.most_common(top): print("%5d %5.1f%% %s"%(c,100.0*c/max(n,1),s))
