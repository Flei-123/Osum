B=/bin/busybox
O=${1:-/tmp/fxsnap.txt}
{
$B echo "== uptime $($B cat /proc/uptime)"
$B ps
$B echo "== threads: tgid tid name state ticks runs syscall(nr a0 a2 futex)"
for t in /proc/[0-9]*/task/[0-9]*; do
  $B awk '/^Name:/{n=$2}/^Tgid:/{g=$2}/^Pid:/{p=$2}/^State:/{s=$2}/^Ticks:/{k=$2}/^Runs:/{r=$2}/^Syscall:/{y=$2" "$3" "$4" "$5}END{print g, p, n, s, k, r, y}' $t/status
done
$B echo "== frames"
$B cat /proc/frames
$B echo "== meminfo"
$B cat /proc/meminfo
$B echo "== unix"
$B cat /proc/net/unix
} > $O 2>&1
