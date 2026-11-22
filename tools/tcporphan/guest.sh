echo "TO start"
export HOME=/root
mkdir -p /root /tmp
PEER=10.0.2.2
count_rows() { n=0; while read a b c d rest; do n=$((n + 1)); done < /proc/net/tcp; echo $((n - 1)); }
pids=""
i=0
while [ $i -lt 16 ]; do
    sleep 600 | nc $PEER @PORT@ > /dev/null 2>&1 &
    pids="$pids $!"
    i=$((i + 1))
    sleep 1
done
sleep 3
echo "TO-OPEN rows=$(count_rows)"
echo "TO-BLACKHOLE"
sleep 4
for p in $pids; do kill $p; done
sleep 2
echo "TO-CLOSED rows=$(count_rows)"
nc -w 4 $PEER @PORT@ < /dev/null > /tmp/new1.txt 2>&1 &
sleep 1
echo "TO-NEW1 rows=$(count_rows) msg=$(cat /tmp/new1.txt)"
sleep 5
sleep 25
nc -w 4 $PEER @PORT@ < /dev/null > /tmp/new2.txt 2>&1 &
sleep 1
echo "TO-NEW2 rows=$(count_rows) msg=$(cat /tmp/new2.txt)"
sleep 5
echo "TO-END"
