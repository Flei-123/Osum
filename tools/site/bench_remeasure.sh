#!/usr/bin/env bash
set -u
S=${BENCH_WORK:?work dir with k0.mb and kw.mb}
L=/root/abbilder/svl/lin
R=$(cd "$(dirname "$0")/../.." && pwd)
cd $R
mkdir -p $S/ap $S/fx $S/mx
matrix() {
  n=$1
  SPEED_SMP=$n SPEED_RUNS=5 SPEED_KERNEL=$S/k0.mb SPEEDCMP_CACHE=/root/abbilder/speedcmp-cache SPEED_KEEP_OUT=$S/mx/m$n /root/jarvis/bin/heavy bash tools/speedcmp/gate.sh --no-write > $S/mx/m$n.log 2>&1
  echo "matrix $n rc=$? $(date +%T) load $(cut -d' ' -f1 /proc/loadavg)" >> $S/progress.txt
}
run_apps() {
  n=$1; o=$S/ap/o-$n; l=$S/ap/l-$n
  mkdir -p $o $l
  ( cd $L && FXIMG=apps.ext4 FXL=apps TMO=900 bash lin.sh apps $n $l > /dev/null 2>&1 ) &
  LP=$!
  SMP=$n KERNEL=$S/kw.mb SPEC=/root/fxhp/lm/run/spec.txt BLOCKS=2400000 INODES=20000 TMO=800 DONE=FX-END DRIVE=ahci KARGS="osum vfs nokbd nosched noproc nofs" /root/jarvis/bin/heavy bash tools/linuxapps/run.sh /root/fxhp/lm $R/tools/site/guest/gapps.sh $o > $S/ap/o-$n.log 2>&1 &
  OP=$!
  ( while kill -0 $OP 2>/dev/null; do grep -aq "AT make_j4 1" $o/ser.txt 2>/dev/null && { sleep 5; for p in $(pgrep -f "ap/o-$n/ser.txt"); do kill $p 2>/dev/null; done; break; }; sleep 3; done ) &
  wait $LP; wait $OP
  echo "apps $n done $(date +%T) load $(cut -d' ' -f1 /proc/loadavg)" >> $S/progress.txt
}
run_fx() {
  v=$1; n=$2; tag=$v$n; o=$S/fx/o-$tag; l=$S/fx/l-$tag
  mkdir -p $o $l
  ( cd $L && bash lin.sh $v $n $l > /dev/null 2>&1 ) &
  LP=$!
  FXWD=/root/abbilder/ffx2/wd NOSAMPLE=1 SMP=$n KERNEL=$S/k0.mb FXGUEST=$R/tools/site/guest/gfx-$v.sh TMO=900 DONE=FX-END /root/jarvis/bin/heavy bash tools/linuxapps/prof/walltime.sh $S/k0.mb $o 3 ahci > $S/fx/o-$tag.log 2>&1 &
  OP=$!
  wait $LP; wait $OP
  echo "fx $tag done $(date +%T) load $(cut -d' ' -f1 /proc/loadavg)" >> $S/progress.txt
}
( matrix 1 ) & ( matrix 4 ) &
( for n in 1 4; do run_apps $n; done ) &
( for v in https data; do for n in 1 4; do run_fx $v $n; done; done ) &
wait
echo "ALL DONE" >> $S/progress.txt
