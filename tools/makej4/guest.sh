export HOME=/root TMPDIR=/tmp PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
CL=$(cat /proc/cmdline 2>/dev/null)
ITERS=$(echo "$CL" | sed -n 's/.*iters=\([0-9]*\).*/\1/p')
[ -z "$ITERS" ] && ITERS=3
mkdir -p /tmp/w && cd /tmp/w
i=0; while [ $i -lt 8 ]; do printf 'int f%d(int x){int s=0;for(int i=0;i<x;i++)s+=i*%d;return s;}\n' $i $i > m$i.c; i=$((i+1)); done
printf 'all: m0.o m1.o m2.o m3.o m4.o m5.o m6.o m7.o\n%%.o: %%.c\n\tcc -O1 -c -o $@ $<\nclean:\n\trm -f *.o\n' > Makefile
n=1
while [ $n -le $ITERS ]; do
    make clean > /dev/null 2>&1
    timeout 60 make -j4 > /tmp/o.mj4 2>&1
    rc=$?
    objs=$(ls /tmp/w/*.o 2>/dev/null | wc -l)
    echo "MJ4 $n rc=$rc objs=$objs"
    [ $rc -ne 0 ] && head -c 400 /tmp/o.mj4 | sed 's/^/MJ4ERR /'
    n=$((n + 1))
done
echo
echo "MJ4-END"
echo FX-END
