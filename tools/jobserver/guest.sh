echo "APPS start"
export HOME=/root TMPDIR=/tmp PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
up() { read u _ < /proc/uptime; echo $u; }
mkdir -p /tmp/w; cd /tmp/w
i=0; while [ $i -lt 8 ]; do printf 'int f%d(int x){int s=0;for(int i=0;i<x;i++)s+=i*%d;return s;}\n' $i $i > m$i.c; i=$((i+1)); done
printf 'all: m0.o m1.o m2.o m3.o m4.o m5.o m6.o m7.o\n%%.o: %%.c\n\tsleep 1; echo built > $@\nclean:\n\trm -f *.o\n' > Makefile
mj() { nm=$1; shift; s=$(up); timeout 40 "$@" > /tmp/o.$nm 2>&1; rc=$?; e=$(up); echo "AT $nm 1 $s $e rc=$rc"; }
mj make_j1 sh -c 'make clean; make'
mj make_j2_pipe sh -c 'make clean; make -j2 --jobserver-style=pipe'
tail -n 5 /tmp/o.make_j2_pipe
mj make_j4 sh -c "make clean; make -j4"
tail -n 5 /tmp/o.make_j4
mj make_j2_fifo sh -c "make clean; make -j2 --jobserver-style=fifo"
echo "AT-END"
echo FX-END
