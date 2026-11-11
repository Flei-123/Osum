B=/bin/busybox
export HOME=/tmp
$B sleep 3
$B cat > /tmp/hello.c <<'SRC'
#include <stdio.h>
int main(void) { printf("hello-from-tcc %d\n", 6 * 7); return 0; }
SRC
$B cat > /tmp/Makefile <<'MK'
SHELL := /bin/ash
CC := /bin/tcc
all: prog
	./prog
prog: hello.o
	$(CC) -o $@ hello.o
hello.o: hello.c
	$(CC) -c -o $@ hello.c
MK
echo "WT tcc-version $(/bin/tcc -v 2>&1 | $B head -n 1 | $B cut -c1-11)"
/bin/tcc -o /tmp/hello /tmp/hello.c > /tmp/tcc.log 2>&1; echo "WT dbg-tcc-rc $?"
echo "WT dbg-tcc-log $($B tr '\n' '|' < /tmp/tcc.log | $B cut -c1-400)"
echo "WT dbg-ls $($B ls -l /tmp/hello /tmp/hello.c /usr/lib/crt1.o /usr/lib/libc.so 2>&1 | $B tr '\n' '|' | $B cut -c1-400)"
echo "WT dbg-hex $($B od -A n -v -t x1 /tmp/hello | $B tr -d ' \n')"
echo "WT dbg-tccdir $($B ls /usr/lib/tcc | $B tr '\n' ' ')"
echo "WT dbg-tccsearch $(/bin/tcc -print-search-dirs 2>&1 | $B tr '\n' '|' | $B cut -c1-300)"
echo "WT dbg-ldso $(/lib/ld-musl-x86_64.so.1 /tmp/hello 2>&1 | $B tail -n 2 | $B tr '\n' '|')"
echo "WT dbg-hdr $($B od -A d -t x1 -N 176 /tmp/hello | $B tr '\n' '|')"
echo "WT tcc-hello $(/tmp/hello 2>&1 | $B tail -n 1)"
echo "WT tcc-run $(/bin/tcc -run /tmp/hello.c 2>&1 | $B tail -n 1)"
echo "WT tcc-nohdr $(/bin/tcc -nostdinc -o /tmp/nohdr /tmp/hello.c >/dev/null 2>&1 && echo built || echo refused)"
echo "WT make-version $(/bin/make --version 2>&1 | $B head -n 1)"
echo "WT make-build $(cd /tmp && /bin/make 2>&1 | $B tail -n 1)"
echo "WT make-nomakefile $(cd /w && /bin/make >/dev/null 2>&1; echo $?)"
echo "WT curl-https-ca $(/bin/curl -sS --max-time 30 --cacert /etc/ca.pem https://10.0.2.2:TLSPORT/h.txt 2>&1 | $B tail -n 1)"
echo "WT curl-https-nocert $(/bin/curl -sS --max-time 30 https://10.0.2.2:TLSPORT/h.txt >/dev/null 2>&1 && echo accepted || echo refused)"
/bin/curl -sS --max-time 60 --cacert /etc/ca.pem -o /tmp/big https://10.0.2.2:TLSPORT/big.bin >/dev/null 2>&1
echo "WT curl-https-big $($B wc -c < /tmp/big) $($B sha256sum /tmp/big | $B cut -c1-16)"
echo "WT git-clone-nohelper $(cd /tmp && GIT_SSL_CAINFO=/etc/ca.pem GIT_EXEC_PATH=/nonexistent /bin/git clone -q https://10.0.2.2:TLSPORT/repo.git cl0 >/dev/null 2>&1 && echo cloned || echo refused)"
echo "WT git-clone-https $(cd /tmp && GIT_SSL_CAINFO=/etc/ca.pem /bin/git clone -q https://10.0.2.2:TLSPORT/repo.git cl 2>&1 | $B tail -n 1; $B cat /tmp/cl/file 2>&1 | $B tail -n 1)"
echo "WT git-clone-log $(cd /tmp/cl && /bin/git log --oneline 2>&1 | $B wc -l)"
echo "WT git-clone-nocert $(cd /tmp && /bin/git clone -q https://10.0.2.2:TLSPORT/repo.git cl2 >/dev/null 2>&1 && echo cloned || echo refused)"
$B mkdir -p /tmp/tt && $B head -c 1048576 /dev/urandom > /tmp/tt/a.bin && $B head -c 200000 /dev/urandom > /tmp/tt/b.bin && echo hi > /tmp/tt/c.txt
$B tar cf /tmp/t.tar -C /tmp tt
for n in 1 2; do $B timeout 30 $B tar tf /tmp/t.tar > /tmp/e$n.out 2>/tmp/e$n.err; echo "WT dbg-tar-early$n rc=$? out=$($B wc -l < /tmp/e$n.out) err=$($B tr '\n' '|' < /tmp/e$n.err | $B cut -c1-120)"; done
$B sync
$B timeout 30 $B tar tf /tmp/t.tar > /tmp/e3.out 2>/tmp/e3.err; echo "WT dbg-tar-aftersync rc=$? out=$($B wc -l < /tmp/e3.out)"
echo "WT tar-list $($B timeout 30 $B tar tf /tmp/t.tar 2>&1 | $B wc -l)"
echo "WT tar-list-exit $($B timeout 30 $B tar tf /tmp/t.tar >/dev/null 2>&1; echo $?)"
echo "WT tar-extract $($B mkdir /tmp/ex && $B timeout 30 $B tar xf /tmp/t.tar -C /tmp/ex && $B sha256sum /tmp/ex/tt/a.bin | $B cut -c1-16)"
echo "WT tar-want $($B sha256sum /tmp/tt/a.bin | $B cut -c1-16)"
echo "WT dbg-tar-err $($B timeout 30 $B tar tf /tmp/t.tar 2>&1 >/dev/null | $B tr '\n' '|' | $B cut -c1-200)"
$B timeout 30 $B tar tf /tmp/t.tar > /tmp/tl.out 2>/tmp/tl.err; echo "WT dbg-tar-redir rc=$? out=$($B wc -l < /tmp/tl.out) err=$($B wc -c < /tmp/tl.err)"
echo "WT dbg-tar-v $($B timeout 30 $B tar tvf /tmp/t.tar 2>&1 | $B wc -l)"
echo "WT dbg-tar-nofork $($B timeout 30 $B tar -t -f /tmp/t.tar 2>&1 | $B wc -l)"
echo "WT dbg-dd-skip $($B dd if=/tmp/t.tar bs=512 skip=2 count=1 2>/dev/null | $B od -A n -t x1 | $B head -n 1)"
echo "WT dbg-dd-want $($B od -A n -t x1 -j 1024 -N 16 /tmp/t.tar | $B head -n 1)"
echo "WT tar-stdin $($B cat /tmp/t.tar | $B timeout 30 $B tar tf - 2>&1 | $B wc -l)"
echo "WT tar-hang-probe $($B sleep 6 | $B timeout 3 $B tar tf - >/dev/null 2>&1; echo $?)"
echo "WT end"
