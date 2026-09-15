# Erzeugt die 4x4-Intramodi DIREKT aus den Formeln der Norm 8.3.1.2.1-9,
# als Tafel (Ziel -> welche Nachbarn mit welchen Gewichten).
# Nachbarn: Index 0..3 = L0..L3 (links, oben->unten), 4 = LU (Ecke),
#           5..8 = U0..U3, 9..12 = UR0..UR3
L0,L1,L2,L3,LU = 0,1,2,3,4
U = [5,6,7,8]
UR = [9,10,11,12]
Lr = [L0,L1,L2,L3]
def P(x,y):
    # p[x,y] der Norm: x=-1 -> links, y=-1 -> oben
    if x==-1 and y==-1: return LU
    if x==-1: return Lr[y]
    if y==-1: return (U+UR)[x]
    raise Exception()
T={}
def put(m,x,y,terms):  # terms: Liste (gewicht, idx), + rundung/shift
    T.setdefault(m,{})[(x,y)]=terms
# Modus 0: vertikal
for y in range(4):
    for x in range(4): put(0,x,y,[(1,P(x,-1))])
# 1: horizontal
for y in range(4):
    for x in range(4): put(1,x,y,[(1,P(-1,y))])
# 3: diagonal down-left
for y in range(4):
    for x in range(4):
        if x==3 and y==3: put(3,x,y,[(1,P(6,-1)),(3,P(7,-1))])
        else: put(3,x,y,[(1,P(x+y,-1)),(2,P(x+y+1,-1)),(1,P(x+y+2,-1))])
# 4: diagonal down-right
for y in range(4):
    for x in range(4):
        if x>y:   put(4,x,y,[(1,P(x-y-2,-1)),(2,P(x-y-1,-1)),(1,P(x-y,-1))])
        elif x<y: put(4,x,y,[(1,P(-1,y-x-2)),(2,P(-1,y-x-1)),(1,P(-1,y-x))])
        else:     put(4,x,y,[(1,P(0,-1)),(2,P(-1,-1)),(1,P(-1,0))])
# 5: vertical right
for y in range(4):
    for x in range(4):
        z=2*x-y
        if z>=0 and z%2==0: put(5,x,y,[(1,P(x-(y>>1)-1,-1)),(1,P(x-(y>>1),-1))])
        elif z>=0:          put(5,x,y,[(1,P(x-(y>>1)-2,-1)),(2,P(x-(y>>1)-1,-1)),(1,P(x-(y>>1),-1))])
        elif z==-1:         put(5,x,y,[(1,P(-1,0)),(2,P(-1,-1)),(1,P(0,-1))])
        else:               put(5,x,y,[(1,P(-1,y-1)),(2,P(-1,y-2)),(1,P(-1,y-3))])
# 6: horizontal down
for y in range(4):
    for x in range(4):
        z=2*y-x
        if z>=0 and z%2==0: put(6,x,y,[(1,P(-1,y-(x>>1)-1)),(1,P(-1,y-(x>>1)))])
        elif z>=0:          put(6,x,y,[(1,P(-1,y-(x>>1)-2)),(2,P(-1,y-(x>>1)-1)),(1,P(-1,y-(x>>1)))])
        elif z==-1:         put(6,x,y,[(1,P(-1,0)),(2,P(-1,-1)),(1,P(0,-1))])
        else:               put(6,x,y,[(1,P(x-1,-1)),(2,P(x-2,-1)),(1,P(x-3,-1))])
# 7: vertical left
for y in range(4):
    for x in range(4):
        if y%2==0: put(7,x,y,[(1,P(x+(y>>1),-1)),(1,P(x+(y>>1)+1,-1))])
        else:      put(7,x,y,[(1,P(x+(y>>1),-1)),(2,P(x+(y>>1)+1,-1)),(1,P(x+(y>>1)+2,-1))])
# 8: horizontal up
for y in range(4):
    for x in range(4):
        z=x+2*y
        if z%2==0 and z<5: put(8,x,y,[(1,P(-1,y+(x>>1))),(1,P(-1,y+(x>>1)+1))])
        elif z<5:          put(8,x,y,[(1,P(-1,y+(x>>1))),(2,P(-1,y+(x>>1)+1)),(1,P(-1,y+(x>>1)+2))])
        elif z==5:         put(8,x,y,[(1,P(-1,2)),(3,P(-1,3))])
        else:              put(8,x,y,[(1,P(-1,3))])
import json
out={}
for m in sorted(T):
    rows=[]
    for y in range(4):
        for x in range(4):
            terms=T[m][(x,y)]
            w=sum(t[0] for t in terms)
            rows.append([w]+[list(t) for t in terms])
    out[str(m)]=rows
json.dump(out,open('pred4.json','w'))
for m in sorted(T):
    print("Modus",m, "Gewichtssummen:", sorted(set(sum(t[0] for t in T[m][(x,y)]) for y in range(4) for x in range(4))))
