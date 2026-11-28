echo "APPS start"
. /etc/apps-lib.sh
LC=/usr/share/linuxcompat
JAVA="java -XX:+UseSerialGC -Xmx256m -XX:-UsePerfData -cp $LC/java Compat"
APP_TMO=300
t java-version version java -version
t java-hello 'hello osum' $JAVA hello
t java-default-flags 'hello osum' java -cp $LC/java Compat hello
t java-threads 'sum=2080 seen=64 parallel=500500' $JAVA threads
t java-nio nio-ok $JAVA nio
t java-mapped mapped $JAVA mapped
t java-http pong $JAVA http
t java-process 'child-42 rc=0' $JAVA process
t java-gc heap=true $JAVA gc
t java-npe npe=10000 $JAVA npe
t java-files '\[a, c, link\]' $JAVA files
t java-watch created=new $JAVA watch
t java-time slept=true $JAVA time
t java-cpus cpus= $JAVA cpus
APP_TMO=120
t go-hello 'OK hello osum' $LC/gotest hello
t go-goroutines sum=20100 $LC/gotest goroutines
t go-gc 'OK gc=' $LC/gotest gc
t go-http pong $LC/gotest http
t go-unix unix-ok $LC/gotest unix
t go-exec child-42 $LC/gotest exec
t go-timers ticks=5 $LC/gotest timers
t go-signal sigusr1 $LC/gotest signal
t go-files 'link=a' $LC/gotest files
t go-mmap mapped $LC/gotest mmap
t go-cpus cpus= $LC/gotest cpus
t rust-hello 'OK hello osum' $LC/rusttest hello
t rust-threads 'sum=28 recv=28' $LC/rusttest threads
t rust-condvar condvar $LC/rusttest condvar
t rust-tcp echo $LC/rusttest tcp
t rust-unix unix-ok $LC/rusttest unix
t rust-process child-42 $LC/rusttest process
t rust-files 'link=a' $LC/rusttest files
t rust-bigalloc pages=32768 $LC/rusttest bigalloc
t rust-hashmap sum=39999800000 $LC/rusttest hashmap
t rust-panic caught $LC/rusttest panic
t rust-timing slept $LC/rusttest timing
t rust-cpus cpus= $LC/rusttest cpus
t py-ctypes pid=True python3 $LC/pycompat.py ctypes
t py-ssl tls=True python3 $LC/pycompat.py ssl
t py-sqlite rows=500 python3 $LC/pycompat.py sqlite
t py-mmap mapped python3 $LC/pycompat.py mmap
t py-flock locked python3 $LC/pycompat.py flock
t py-forkpipe child python3 $LC/pycompat.py forkpipe
t py-epoll events=1 python3 $LC/pycompat.py epoll
t py-itimer fired=1 python3 $LC/pycompat.py itimer
t py-rlimit nofile=True python3 $LC/pycompat.py rlimit
t py-http pong python3 $LC/pycompat.py http
t py-zip zipped python3 $LC/pycompat.py zip
t py-subprocess child-42 python3 $LC/pycompat.py subprocess
t py-threads sum=9900 python3 $LC/pycompat.py threads
t py-hash ba7816bf python3 $LC/pycompat.py hash
t py-json same=True python3 $LC/pycompat.py json
t py-venv venv=True python3 $LC/pycompat.py venv
t node-fs b,link node $LC/nodecompat.js fs
t node-tcp tcp-ok node $LC/nodecompat.js tcp
t node-http pong node $LC/nodecompat.js http
t node-udp udp-ok node $LC/nodecompat.js udp
t node-spawn 'child-42 rc=0' node $LC/nodecompat.js spawn
t node-fork fork-ok node $LC/nodecompat.js fork
t node-worker 'worker-done value=7' node $LC/nodecompat.js worker
t node-zlib same=true node $LC/nodecompat.js zlib
t node-crypto 'key=16 rnd=8' node $LC/nodecompat.js crypto
t node-watch ':new' node $LC/nodecompat.js watch
t node-timers 'ticks=3 slept=true' node $LC/nodecompat.js timers
t node-cpus cpus= node $LC/nodecompat.js cpus
t node-dns lookup=true node $LC/nodecompat.js dns
t node-bigbuffer bytes=134217728 node $LC/nodecompat.js bigbuffer
t gdb-version 'GNU gdb' gdb --version
t gdb-break 'Breakpoint 1, add' gdb -batch -ex 'break add' -ex run -ex bt -ex finish $LC/gdbhello
t gdb-regs rip gdb -batch -ex 'break main' -ex run -ex 'info registers rip' $LC/gdbhello
t gdb-crash SIGSEGV gdb -batch -ex run -ex bt --args $LC/gdbhello c
t valgrind-version valgrind- valgrind --version
t valgrind-run total=42 valgrind -q $LC/gdbhello
t emacs-version 'GNU Emacs' emacs --version
t emacs-batch 42 emacs -Q --batch --eval '(princ (+ 40 2))'
t emacs-file hi sh -c 'emacs -Q --batch --eval "(with-temp-file \"/tmp/e.txt\" (insert \"hi\"))" && cat /tmp/e.txt'
t vim-regex aXc sh -c 'vim -es -u NONE -N -c "call setline(1,[\"abc\"])" -c "%s/b/X/" -c "w! /tmp/vr.txt" -c q; cat /tmp/vr.txt'
t vim-shell shell-ok sh -c 'vim -es -u NONE -N -c "call writefile([system(\"echo shell-ok\")], \"/tmp/vs.txt\")" -c q; cat /tmp/vs.txt'
t vim-swap x sh -c 'vim -es -u NONE -N -c "set swapfile" -c "e /tmp/sw.txt" -c "call setline(1,\"x\")" -c w -c q; cat /tmp/sw.txt'
t lynx-dump 'Hello Osum' sh -c 'echo "<html><body><h1>Hello Osum</h1></body></html>" > /tmp/l.html && lynx -dump /tmp/l.html'
t w3m-dump 'Hello Osum' w3m -dump /tmp/l.html
t gs-calc 3 gs -q -dNODISPLAY -dNOSAFER -dBATCH -c '1 2 add = quit'
t gs-png g.png sh -c 'gs -q -sDEVICE=png16m -r20 -o /tmp/g.png -c "0 0 100 100 rectfill showpage" && ls -l /tmp/g.png'
t gs-pdf PDF sh -c 'gs -q -sDEVICE=pdfwrite -o /tmp/g.pdf -c "showpage" && head -c 8 /tmp/g.pdf'
t mutool-info PDF mutool info /tmp/g.pdf
t git-gc 40 sh -c 'cd /tmp && rm -rf gg && git init -q gg && cd gg && git config user.email a@b.c && git config user.name n && i=0 && while [ $i -lt 40 ]; do echo $i > f$i && git add f$i && git commit -qm c$i; i=$((i+1)); done && git gc -q --aggressive && git fsck > /dev/null 2>&1 && git log --oneline | wc -l'
t sqlite-fts 'hello osum' sqlite3 :memory: "create virtual table t using fts5(a); insert into t values('hello osum'); select * from t where t match 'osum';"
t sqlite-json 2 sqlite3 :memory: "select json_extract('{\"a\":[1,2,3]}','\$.a[1]');"
echo FX-END
