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
/bin/tcc -o /tmp/hello /tmp/hello.c 2>&1 | $B tail -n 2
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
for v in plain plain timeout timeout plain; do
if [ $v = timeout ]; then T="$B timeout 30"; else T=; fi
L=$( ($T $B tar tf /tmp/t.tar 2>/tmp/p.err; echo $? > /tmp/p.rc) | $B wc -l)
echo "WT tar-warm-$v lines=$L rc=$($B cat /tmp/p.rc) err=$($B wc -c < /tmp/p.err)"
done
echo "WT tar-list $($B timeout 30 $B tar tf /tmp/t.tar 2>&1 | $B wc -l)"
echo "WT tar-list-exit $($B timeout 30 $B tar tf /tmp/t.tar >/dev/null 2>&1; echo $?)"
echo "WT tar-extract $($B mkdir /tmp/ex && $B timeout 30 $B tar xf /tmp/t.tar -C /tmp/ex && $B sha256sum /tmp/ex/tt/a.bin | $B cut -c1-16)"
echo "WT tar-want $($B sha256sum /tmp/tt/a.bin | $B cut -c1-16)"
echo "WT tar-stdin $($B cat /tmp/t.tar | $B timeout 30 $B tar tf - 2>&1 | $B wc -l)"
echo "WT tar-hang-probe $($B sleep 6 | $B timeout 3 $B tar tf - >/dev/null 2>&1; echo $?)"
echo "WT end"
