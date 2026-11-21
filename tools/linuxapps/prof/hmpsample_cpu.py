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
        b=cmd("info registers -a")
        for blk in re.split(r"(?=CPU#\d+)",b):
            m=re.search(r"RIP=([0-9a-f]+)",blk); c=re.search(r"CS =([0-9a-f]+)",blk)
            cpu=re.match(r"CPU#(\d+)",blk); hlt=re.search(r"HLT=(\d)",blk)
            if not (m and c and cpu): continue
            f.write("%.2f %s %s %s %s\n"%(time.time()-t0,cpu[1],c[1],m[1],hlt[1] if hlt else "?")); n+=1
    except Exception:
        break
    time.sleep(0.01)
f.close(); print("samples",n)
