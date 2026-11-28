B=/bin/busybox
J=/bin/jarvisd
L=/tmp/fxdl2.log
DUR=${1:-2400}
: > $L
runs() { $B awk '/^Runs:/{print $2}' /proc/$1/status 2>/dev/null; }
state() { $B awk '/^State:/{print $2}' /proc/$1/status 2>/dev/null; }
sysl() { $B awk '/^Syscall:/{print $2" "$3}' /proc/$1/status 2>/dev/null; }
upt() { $B cut -d' ' -f1 /proc/uptime; }
nproc() { /bin/ps 2>/dev/null | $B awk '$NF=="firefox"{n++}END{print n+0}'; }
nthr() { n=0; for t in /proc/[0-9]*/task/[0-9]*; do n=$((n+1)); done; echo $n; }
fxpid() { /bin/xfx status | $B awk '{for(i=1;i<=NF;i++) if ($i ~ /^pid=/) {sub("pid=","",$i); print $i}}'; }
urlbar() { $J -i "scan 29 38 166 157" >/dev/null 2>&1; $B sleep 1; $J -i type "$1" >/dev/null 2>&1; $B sleep 1; $J -i "scan 28 156" >/dev/null 2>&1; }
snap() { $B sh /tmp/fxsnap.sh /tmp/hangsnap-dl-$(upt).txt; echo "SNAP $1 at $(upt)" >> $L; }
T0=$(upt | $B cut -d. -f1)
echo "start $(upt) dur=$DUR" >> $L
urlbar "youtube.com/watch?v=dQw4w9WgXcQ"
n=0; bad=0; snapped=0
while true; do
  now=$(upt | $B cut -d. -f1)
  [ $((now - T0)) -ge $DUR ] && break
  P=$(fxpid)
  if [ -z "$P" ] || [ ! -d /proc/$P ]; then
    echo "$(upt) NO_FIREFOX" >> $L
    $B sleep 5
    continue
  fi
  n=$((n+1))
  s=$(state $P)
  echo "$(upt) n=$n fx=$P $s r=$(runs $P) sys=$(sysl $P) procs=$(nproc) thr=$(nthr)" >> $L
  case "$s" in S) bad=$((bad+1));; *) bad=0; snapped=0;; esac
  if [ $bad -ge 6 ] && [ $snapped = 0 ]; then snapped=1; snap stateS; fi
  case $((n % 12)) in
    1) $J -i "scroll 960 600 0 5" >/dev/null 2>&1 ;;
    3) $J -i "scroll 960 600 1 5" >/dev/null 2>&1 ;;
    5) r0=$(runs $P); $J -i "scan 57 185" >/dev/null 2>&1; $B sleep 1; $J -i "scroll 960 600 0 3" >/dev/null 2>&1; $B sleep 2; r1=$(runs $P); echo "PROBE scroll runs $r0 -> $r1" >> $L ;;
    7) case $(( (n / 12) % 3 )) in
         0) urlbar "example.com" ;;
         1) urlbar "en.wikipedia.org/wiki/Linux" ;;
         2) urlbar "youtube.com/watch?v=dQw4w9WgXcQ" ;;
       esac
       echo "URL_ACTION n=$n" >> $L ;;
  esac
  $B sleep 5
done
echo "end $(upt)" >> $L
echo done > /tmp/fxdl.done
