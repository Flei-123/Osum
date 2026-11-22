echo "APPS start"
echo "CPUS proc=$(grep -c ^processor /proc/cpuinfo 2>/dev/null) osum=$(grep -o "cpus_online=[0-9]*" /proc/cpus 2>/dev/null)"
export HOME=/root TMPDIR=/tmp PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
up() { read u _ < /proc/uptime; echo $u; }
T() { nm=$1; shift; r=1; while [ $r -le 3 ]; do s=$(up); "$@" > /tmp/o.$nm 2>&1; rc=$?; e=$(up); echo "AT $nm $r $s $e rc=$rc"; r=$((r+1)); done; }
mkdir -p /tmp/w && cd /tmp/w
printf '#include <stdio.h>\nint main(void){puts("hi");return 0;}\n' > h.c
i=0; while [ $i -lt 8 ]; do printf 'int f%d(int x){int s=0;for(int i=0;i<x;i++)s+=i*%d;return s;}\n' $i $i > m$i.c; i=$((i+1)); done
printf 'all: m0.o m1.o m2.o m3.o m4.o m5.o m6.o m7.o\n%%.o: %%.c\n\tcc -O1 -c -o $@ $<\nclean:\n\trm -f *.o\n' > Makefile
printf 'create table t(a integer, b text);\nbegin;\nwith recursive c(x) as (select 1 union all select x+1 from c where x<150000) insert into t select x, hex(x) from c;\ncommit;\nselect count(*), sum(a) from t;\nselect b from t where a=12345;\n' > q.sql
printf 'i=0; while [ $i -lt 300 ]; do /bin/true; i=$((i+1)); done\n' > loop.sh
printf 'seq 1 100000 | awk "{print \\$1 %% 97, \\$1}" | sort -n | uniq -c | sort -rn | head -3 | wc -l\n' > pipe.sh
git init -q /tmp/g > /dev/null 2>&1; cd /tmp/g; i=0; while [ $i -lt 40 ]; do echo $i > f$i; i=$((i+1)); done
git add . > /dev/null 2>&1; git -c user.email=a@b -c user.name=n commit -qm m > /dev/null 2>&1; cd /tmp/w
T true_loop300 sh loop.sh
T pipe_awk_sort sh pipe.sh
T gcc_hello_x10 sh -c 'i=0; while [ $i -lt 10 ]; do cc -O0 -o /tmp/w/h h.c; i=$((i+1)); done'
T python_start_x10 sh -c 'i=0; while [ $i -lt 10 ]; do python3 -c pass; i=$((i+1)); done'
T python_loop python3 -c 'print(sum(i*i for i in range(2000000)))'
T node_start_x5 sh -c 'i=0; while [ $i -lt 5 ]; do node -e 0; i=$((i+1)); done'
T node_loop node -e 'let s=0;for(let i=0;i<20000000;i++)s+=i%7;console.log(s)'
T git_status_x30 sh -c 'cd /tmp/g; i=0; while [ $i -lt 30 ]; do git status; i=$((i+1)); done'
T sqlite_150k sh -c 'rm -f /tmp/t.db; sqlite3 /tmp/t.db < /tmp/w/q.sql'
T sha256_64mib sh -c 'head -c 67108864 /dev/zero | sha256sum'
T make_j1 sh -c 'make clean; make'
s=$(up); timeout 60 sh -c 'make clean; make -j4' > /tmp/o.mj4 2>&1; rc=$?; e=$(up); echo "AT make_j4 1 $s $e rc=$rc"
echo "AT-END"
echo FX-END
