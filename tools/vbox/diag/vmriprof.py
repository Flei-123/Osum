import bisect, sys, collections
syms=[]
for l in open(sys.argv[1]):
    p=l.split()
    if len(p)>=3 and p[1] in 'TtWw':
        try: syms.append((int(p[0],16),p[2]))
        except: pass
syms.sort(); addrs=[a for a,_ in syms]
def look(x):
    if x>=0x40000000: return 'USER_WINDOW'
    i=bisect.bisect_right(addrs,x)-1
    return syms[i][1] if i>=0 else '?'
rows=[l.split() for l in sys.stdin if l.strip()]
by=collections.defaultdict(collections.Counter)
cs=collections.defaultdict(collections.Counter)
iff=collections.defaultdict(collections.Counter)
for r in rows:
    t,c,rip,csv,rfl,cr3=r[:6]
    x=int(rip,16); n=look(x)
    by[c][n if int(csv,16)!=0x2b else 'USER:%s'%hex(x>>20)]+=1
    cs[c][csv]+=1
    iff[c]['IF1' if int(rfl,16)&0x200 else 'IF0']+=1
for c in sorted(by):
    print('cpu',c,'cs',dict(cs[c]),'if',dict(iff[c]))
    for k,v in by[c].most_common(14): print('   ',v,k)
