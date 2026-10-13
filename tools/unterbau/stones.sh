# probe script of the proof stones python3 / curl / git (run by `busybox sh /etc/st.sh`; lines "ST <name> <value>")
B=/bin/busybox
# python finds its prefix by walking up from its executable dir (getpath); installed in /usr/bin it finds /usr. No PYTHONHOME (r698).
# /bin/python3 is a symlink to it (getpath resolves it, like Linux distributions that put python in /usr/bin)
$B ln -s /usr/bin/python3 /bin/python3
echo "ST py-nohome $(/usr/bin/python3 -c 'import sys;print(sys.prefix)' 2>&1 | $B tail -n 1)"
echo "ST py-symlink $(/bin/python3 -c 'import sys;print(sys.prefix)' 2>&1 | $B tail -n 1)"
echo "ST py-print $(/bin/python3 -c 'print(6*7)' 2>&1 | $B tail -n 1)"
echo "ST py-os $(/bin/python3 -c 'import os;print(os.getcwd())' 2>&1 | $B tail -n 1)"
echo "ST py-file $(/bin/python3 -c 'open("/tmp/pf","w").write("hi");print(open("/tmp/pf").read())' 2>&1 | $B tail -n 1)"
echo "ST py-json $(/bin/python3 -c 'import json;print(json.dumps({"a":1}))' 2>&1 | $B tail -n 1)"
echo "ST py-math-so $(/bin/python3 -c 'import math;print(math.isqrt(144))' 2>&1 | $B tail -n 1)"
echo "ST py-struct-so $(/bin/python3 -c 'import struct;print(len(struct.pack("<I",1)))' 2>&1 | $B tail -n 1)"
echo "ST py-zlib-so $(/bin/python3 -c 'import zlib;print(len(zlib.decompress(zlib.compress(b"x"*1000))))' 2>&1 | $B tail -n 1)"
echo "ST py-thread $(/bin/python3 -c 'import threading;r=[];t=threading.Thread(target=lambda:r.append(1));t.start();t.join();print(len(r))' 2>&1 | $B tail -n 1)"
echo "ST py-subprocess $(/bin/python3 -c 'import subprocess;print(subprocess.run(["/bin/busybox","echo","sp"],capture_output=True,text=True).stdout.strip())' 2>&1 | $B tail -n 1)"
echo "ST py-socket $(/bin/python3 -c 'import socket;s=socket.socket(socket.AF_UNIX);s.close();print("ok")' 2>&1 | $B tail -n 1)"
echo "ST py-hashlib $(/bin/python3 -c 'import hashlib;print(hashlib.sha256(b"a").hexdigest()[:8])' 2>&1 | $B tail -n 1)"
echo "ST curl-version $(/bin/curl --version 2>&1 | $B head -n 1 | $B cut -c1-11)"
echo "ST curl-file $(/bin/curl -s file:///etc/pruef.txt 2>&1 | $B wc -l)"
echo "ST git-version $(/bin/git --version 2>&1 | $B tail -n 1)"
echo "ST git-init $(cd /tmp && /bin/git init -q gt 2>/dev/null && echo ok)"
echo "ST git-hash $(echo hi | /bin/git hash-object --stdin 2>&1)"
echo "ST git-commit $(cd /tmp/gt && /bin/git config user.email a@b && /bin/git config user.name n && echo x > f && /bin/git add f && /bin/git commit -q -m m 2>&1 && /bin/git log --oneline | $B wc -l)"
# only with STONES_NET=1 (virtio-net + http server of the host at 10.0.2.2:18765)
$B sleep 3
echo "ST net-curl-http $(/bin/curl -sS --max-time 15 http://10.0.2.2:18765/h.txt 2>&1 | $B tail -n 1)"
echo "ST net-py-http $(/bin/python3 -c 'import socket;s=socket.create_connection(("10.0.2.2",18765),5);s.sendall(b"GET /h.txt HTTP/1.0\r\n\r\n");print(s.recv(300).split(b"\r\n\r\n")[-1].decode().strip())' 2>&1 | $B tail -n 1)"
echo "ST net-procdev $($B grep -c eth0 /proc/net/dev)"
echo "ST net-ifconfig $($B ifconfig eth0 2>&1 | $B grep -o 'inet addr:[0-9.]*')"
echo "ST end"
