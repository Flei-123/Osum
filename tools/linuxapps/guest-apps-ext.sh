echo "APPS start"
. /etc/apps-lib.sh
t openssl-version OpenSSL openssl version
t openssl-sha ba7816bf sh -c 'printf abc | openssl dgst -sha256'
t openssl-enc hello sh -c 'echo hello | openssl enc -aes-256-cbc -pbkdf2 -pass pass:x | openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:x'
t openssl-rand '^3[23]' sh -c 'openssl rand -hex 16 | wc -c'
t openssl-keygen BEGIN sh -c 'openssl genpkey -algorithm ed25519 -out /tmp/ed.pem && head -1 /tmp/ed.pem'
t openssl-cert Certificate sh -c 'openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -subj /CN=osum -keyout /tmp/k.pem -out /tmp/c.pem -days 1 && openssl x509 -in /tmp/c.pem -noout -text'
t xz-roundtrip hello sh -c 'echo hello | xz -c | xz -dc'
t bzip2-roundtrip hello sh -c 'echo hello | bzip2 -c | bzip2 -dc'
t zstd-roundtrip hello sh -c 'echo hello | zstd -qc | zstd -dqc'
t zip-roundtrip z.txt sh -c 'cd /tmp && echo z > z.txt && rm -f z.zip && zip -q z.zip z.txt && unzip -l z.zip'
t bsdtar-roundtrip b.txt sh -c 'cd /tmp && echo b > b.txt && bsdtar -cf b.tar b.txt && bsdtar -tf b.tar'
t patch-apply patched sh -c 'cd /tmp && echo old > p.txt && echo patched > p2.txt && diff -u p.txt p2.txt > p.diff; patch p.txt < p.diff && cat p.txt'
t m4-macro 5 sh -c 'echo "define(X,5)X" | m4'
t ed-edit hi sh -c 'printf "a\nhi\n.\nw /tmp/e.txt\nq\n" | ed -s && cat /tmp/e.txt'
t bc-calc 1024 sh -c 'echo "2^10" | bc'
t tree-run files tree /etc/ssl
t jq-sum 6 sh -c 'echo "{\"a\":[1,2,3]}" | jq ".a | add"'
t perl-version perl perl -v
t perl-print 5050 perl -e 'my $s=0; $s+=$_ for 1..100; print "$s\n"'
t perl-regex bXd perl -e '$_="abcd"; s/c/X/; s/a//; print "$_\n"; $_="bXd" if /b.d/; print "$_\n"'
t perl-modules ok perl -MPOSIX -MData::Dumper -MDigest::MD5 -MFile::Temp -MStorable -e 'print "ok\n"'
t perl-fork child perl -e 'my $p=fork(); if(!$p){print "child\n";exit 0} waitpid($p,0); print "parent\n"'
t lua-version Lua lua5.4 -v
t lua-run 5050 lua5.4 -e 'local s=0 for i=1,100 do s=s+i end print(s)'
t ruby-version ruby ruby -v
t ruby-run 5050 ruby -e 'puts (1..100).sum'
t ruby-threads 8 ruby -e 'r=[]; 8.times.map{|i| Thread.new{r<<i}}.each(&:join); puts r.size'
t php-version PHP php84 -v
t php-run 5050 php84 -r 'echo array_sum(range(1,100)),"\n";'
t python-asyncio 3 python3 -c 'import asyncio;print(asyncio.run(asyncio.sleep(0.01,3)))'
t python-multiproc 4 python3 -c 'import multiprocessing as m;p=m.get_context("fork").Pool(2);print(sum(p.map(abs,[1,-1,2,0])));p.close()'
t python-compress ok python3 -c 'import lzma,bz2,zlib,gzip;d=b"x"*1000;assert lzma.decompress(lzma.compress(d))==d;assert bz2.decompress(bz2.compress(d))==d;print("ok")'
t python-unix-socket hello python3 -c 'import socket,os;a,b=socket.socketpair();a.send(b"hello");print(b.recv(5).decode())'
t git-clone-local hello sh -c 'cd /tmp && rm -rf src dst && git init -q src && cd src && git config user.email a@b.c && git config user.name n && echo hello > f && git add f && git commit -qm m && cd .. && git clone -q src dst && cat dst/f'
t git-branch-merge merged sh -c 'cd /tmp/src && git checkout -qb b && echo merged > g && git add g && git commit -qm g && git checkout -q master 2>/dev/null || git checkout -q main; git merge -q b && cat g'
t git-diff-stat '1 file' sh -c 'cd /tmp/src && echo more >> f && git diff --stat'
t binutils-ld GNU ld --version
t binutils-as GNU as --version
t binutils-readelf ELF readelf -h /bin/busybox
t binutils-objdump file objdump -f /bin/busybox
t binutils-nm main sh -c 'printf "int main(){return 0;}\n" > /tmp/n.c && gcc -o /tmp/n /tmp/n.c && nm /tmp/n'
t gcc-shared-dl 42 sh -c 'cd /tmp && printf "int f(){return 42;}\n" > l.c && gcc -shared -fPIC -o libl.so l.c && printf "#include <dlfcn.h>\n#include <stdio.h>\nint main(){void*h=dlopen(\"/tmp/libl.so\",RTLD_NOW);int(*f)()=dlsym(h,\"f\");printf(\"%%d\",f());return 0;}\n" > d.c && gcc -o d d.c -ldl && ./d; echo'
t gcc-pthread 8 sh -c 'cd /tmp && printf "#include <pthread.h>\n#include <stdio.h>\nint c;pthread_mutex_t m=PTHREAD_MUTEX_INITIALIZER;void*w(void*a){pthread_mutex_lock(&m);c++;pthread_mutex_unlock(&m);return 0;}\nint main(){pthread_t t[8];for(int i=0;i<8;i++)pthread_create(&t[i],0,w,0);for(int i=0;i<8;i++)pthread_join(t[i],0);printf(\"%%d\",c);return 0;}\n" > t.c && gcc -O2 -pthread -o t t.c && ./t; echo'
APP_TMO=240
t make-build built sh -c 'cd /tmp && rm -rf mk && mkdir mk && cd mk && printf "int main(){return 0;}\n" > a.c && printf "a: a.c\n\tgcc -o a a.c\n\techo built\n" > Makefile && make'
t cmake-version cmake cmake --version
t cmake-build built sh -c 'cd /tmp && rm -rf cm && mkdir cm && cd cm && printf "cmake_minimum_required(VERSION 3.10)\nproject(p C)\nadd_executable(p p.c)\n" > CMakeLists.txt && printf "#include <stdio.h>\nint main(){puts(\"built\");return 0;}\n" > p.c && cmake -G Ninja -S . -B b >/dev/null && samu -C b >/dev/null && b/p'
APP_TMO=90
t magick-version ImageMagick magick -version
t magick-convert PNG sh -c 'convert -size 8x8 xc:red /tmp/r.png && identify /tmp/r.png'
t rsync-version rsync rsync --version
t rsync-copy r.txt sh -c 'cd /tmp && rm -rf rs rd && mkdir rs && echo r > rs/r.txt && rsync -a rs/ rd/ && ls rd'
t socat-version socat socat -V
t socat-pipe hi sh -c 'echo hi | socat - -'
t nc-help OpenBSD sh -c 'nc -h 2>&1 | head -2'
t lsof-version lsof lsof -v
t lsof-self . sh -c 'lsof -p $$ 2>&1 | head -3'
t screen-version Screen screen -v
t tmux-version tmux tmux -V
t tmux-session ok sh -c 'tmux -f /dev/null new-session -d -s s "sleep 5" && tmux -f /dev/null has-session -t s && echo ok; tmux -f /dev/null kill-server'
t strace-version strace strace -V
t strace-run write sh -c 'strace -o /tmp/st.out -e trace=write echo hi; cat /tmp/st.out'
t e2fs-mkfs '11/2048 files' sh -c 'truncate -s 8M /tmp/e.img && mke2fs -q /tmp/e.img && e2fsck -fn /tmp/e.img'
t redis-version Redis redis-server --version
t redis-unix PONG sh -c 'redis-server --port 0 --unixsocket /tmp/r.sock --save "" > /tmp/r.log 2>&1 & sleep 3; tail -3 /tmp/r.log; redis-cli -s /tmp/r.sock ping; redis-cli -s /tmp/r.sock shutdown nosave'
t nginx-version nginx nginx -v
t nginx-config 'test is successful' sh -c 'mkdir -p /tmp/logs /run/nginx /var/lib/nginx/tmp && printf "events{}\nhttp{server{listen 8081;}}\n" > /tmp/ng.conf && nginx -t -c /tmp/ng.conf -p /tmp 2>&1'
t ip-version iproute ip -V
t ip-link lo ip link
t dig-version DiG dig -v
t tcpdump-version tcpdump tcpdump --version
t sshd-version OpenSSH sh -c 'sshd -V 2>&1 | head -1'
t big-args 7 sh -c 'x=$(printf "%0400d" 0); sh -c "echo \$#" $x $x $x $x $x $x $x $x'
t big-env 400 sh -c 'A=$(printf "%0400d" 0) B=$A C=$A D=$A E=$A sh -c "echo \${#E}"'
echo APPS-END
echo FX-END
