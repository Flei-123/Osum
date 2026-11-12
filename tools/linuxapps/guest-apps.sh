echo "APPS start"
export HOME=/root TERM=xterm XDG_RUNTIME_DIR=/tmp LANG=C PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
mkdir -p /tmp /root
t() {
    n=$1; want=$2; shift 2
    echo "APPS $n begin"
    timeout ${APP_TMO:-90} "$@" > /tmp/o.$n 2>&1 < /dev/null
    rc=$?
    if [ $rc -eq 0 ] && grep -q -- "$want" /tmp/o.$n; then echo "APPS-RESULT $n ok"; else echo "APPS-RESULT $n red rc=$rc want=$want"; fi
    head -${APP_LINES:-5} /tmp/o.$n
}
t busybox-list acpid busybox --list
t bb-tar h.txt sh -c 'echo hello > /tmp/h.txt && tar cf /tmp/h.tar -C /tmp h.txt && tar tf /tmp/h.tar'
t bb-gzip hello sh -c 'echo hello | gzip -c | gunzip -c'
t bb-sed aXc sh -c 'echo abc | sed s/b/X/'
t bb-awk 3 sh -c 'echo "1 2" | awk "{print \$1+\$2}"'
t bb-find passwd find /etc -maxdepth 1 -name 'passw*'
t bb-grep 1 sh -c 'echo abc | grep -c b'
t bb-sort a sh -c 'printf "b\na\n" | sort'
t bb-ps PID ps
t bb-top Mem top -b -n 1
t htop-version htop htop --version
t htop-run Tasks timeout 8 htop -d 5
t nano-version GNU nano --version
t vim-version VIM vim --version
t vim-batch hi sh -c 'vim -es -u NONE -c "call setline(1,\"hi\")" -c "w! /tmp/v.txt" -c q; cat /tmp/v.txt'
t less-version less less --version
t less-pipe hi sh -c 'echo hi | less'
t ffmpeg-version ffmpeg ffmpeg -version
t ffmpeg-video frame ffmpeg -nostdin -f lavfi -i testsrc=d=1:s=64x64:r=5 -f null -
t ffmpeg-audio size ffmpeg -nostdin -f lavfi -i sine=d=1 -c:a pcm_s16le /tmp/a.wav
t mpv-version mpv mpv --version
t mpv-play Exiting mpv --no-config --vo=null --ao=null /tmp/a.wav
t pcmanfm-help Usage pcmanfm --help
t bash-version GNU bash --version
t bash-script 6 bash -c 'a=(1 2 3); s=0; for i in "${a[@]}"; do s=$((s+i)); done; echo $s'
t bash-pipe 3 bash -c 'seq 1 3 | tail -1'
t coreutils-ls total ls -l /etc
t coreutils-sha ba7816bf sh -c 'printf abc | sha256sum'
t coreutils-sort 1 sh -c 'seq 1 5 | sort -rn | tail -1'
t coreutils-date 20 date +%Y
t grep-gnu 1 sh -c 'echo abc | grep -c b'
t sed-gnu aXc sh -c 'echo abc | sed s/b/X/'
t gawk-run 3 sh -c 'echo "1 2" | awk "{print \$1+\$2}"'
t tar-gnu g.txt sh -c 'echo hi > /tmp/g.txt && tar czf /tmp/g.tgz -C /tmp g.txt && tar tzf /tmp/g.tgz'
t find-gnu passwd find /etc -maxdepth 1 -name 'passw*'
t file-run ELF file /bin/busybox
t python-version Python python3 --version
t python-print 5050 python3 -c 'print(sum(range(101)))'
t python-threads 8 python3 -c 'import threading;r=[];ts=[threading.Thread(target=lambda i=i:r.append(i)) for i in range(8)];[x.start() for x in ts];[x.join() for x in ts];print(len(r))'
t python-json ok python3 -c 'import json,hashlib,zlib,socket,ssl,sqlite3,ctypes;print("ok")'
t python-sqlite 3 python3 -c 'import sqlite3;c=sqlite3.connect(":memory:");c.execute("create table t(a)");c.executemany("insert into t values(?)",[(1,),(2,),(3,)]);print(c.execute("select count(*) from t").fetchone()[0])'
t python-file hello python3 -c 'open("/tmp/p.txt","w").write("hello");print(open("/tmp/p.txt").read())'
t python-subprocess hi python3 -c 'import subprocess;print(subprocess.check_output(["echo","hi"]).decode().strip())'
t curl-version curl curl --version
t curl-file hello sh -c 'echo hello > /tmp/c.txt; curl -s file:///tmp/c.txt'
t git-version git git --version
t git-repo init sh -c 'cd /tmp && rm -rf gr && git init gr && cd gr && git config user.email a@b.c && git config user.name n && echo x > f && git add f && git commit -qm m && git log --oneline && git status'
t sqlite-cli 3 sqlite3 :memory: 'create table t(a);insert into t values(1),(2),(3);select count(*) from t;'
t sqlite-file 2 sh -c 'rm -f /tmp/s.db; sqlite3 /tmp/s.db "create table t(a);insert into t values(1),(2);" && sqlite3 /tmp/s.db "select count(*) from t;"'
t node-version v node --version
t node-eval 5050 node -e 'let s=0;for(let i=0;i<=100;i++)s+=i;console.log(s)'
t node-fs hello node -e 'const fs=require("fs");fs.writeFileSync("/tmp/n.txt","hello");console.log(fs.readFileSync("/tmp/n.txt","utf8"))'
t ssh-version OpenSSH ssh -V
t ssh-keygen SHA256 sh -c 'rm -f /tmp/k /tmp/k.pub; ssh-keygen -q -t ed25519 -N "" -f /tmp/k && ssh-keygen -l -f /tmp/k.pub'
t tcc-version tcc tcc -v
t tcc-run hello-tcc sh -c 'printf "#include <stdio.h>\nint main(){puts(\"hello-tcc\");return 0;}\n" > /tmp/h.c && tcc -run /tmp/h.c'
t tcc-compile hello-tcc sh -c 'tcc -o /tmp/h /tmp/h.c && /tmp/h'
t foot-version foot foot --version
t xterm-version XTerm xterm -version
t gcc-version gcc gcc --version
t gcc-compile hello-gcc sh -c 'echo "int main(){puts(\"hello-gcc\");return 0;}" > /tmp/g.c && gcc -include stdio.h -o /tmp/g /tmp/g.c && /tmp/g'
t make-version GNU make --version
echo APPS-END
echo FX-END
