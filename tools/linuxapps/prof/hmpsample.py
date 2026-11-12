import socket,sys,time,re,os
sock=sys.argv[1]; out=sys.argv[2]; limit=float(sys.argv[3])
t0=time.time()
while not os.path.exists(sock):
    time.sleep(0.2)
    if time.time()-t0>180: sys.exit(1)
s=socket.socket(socket.AF_UNIX)
while True:
    try: s.connect(sock); break
    except Exception: time.sleep(0.2)
s.settimeout(3)
def cmd(c):
    s.sendall((c+"\n").encode()); b=b""
    while not b.endswith(b"(qemu) "):
        d=s.recv(65536)
        if not d: raise EOFError
        b+=d
    return b.decode(errors="ignore")
try:
    cmd("")
except Exception: pass
f=open(out,"w"); n=0
while time.time()-t0<limit:
    try:
        b=cmd("info registers")
        m=re.search(r"RIP=([0-9a-f]+)",b); c=re.search(r"CS =([0-9a-f]+)",b); bp=re.search(r"RBP=([0-9a-f]+)",b)
        if not (m and c): continue
        chain=[]
        if int(c[1],16)&3==0:
            p=int(bp[1],16)
            for _ in range(10):
                if p<0x1000 or p>0x100000000: break
                r=cmd("x /2gx 0x%x"%p)
                mm=re.search(r":\s+0x([0-9a-f]+)\s+0x([0-9a-f]+)",r)
                if not mm: break
                nb=int(mm[1],16); ra=int(mm[2],16)
                chain.append(ra)
                if nb<=p: break
                p=nb
        f.write("%.2f %s %s %s\n"%(time.time()-t0,c[1],m[1],",".join("%x"%x for x in chain))); n+=1
    except Exception as e:
        break
    time.sleep(0.01)
f.close(); print("samples",n)
