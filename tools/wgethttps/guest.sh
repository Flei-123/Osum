B=/bin/busybox
$B sleep 3
echo "WT http $($B timeout 30 $B wget -q -O - http://10.0.2.2:HTTPPORT/h.txt 2>&1 | $B tail -n 1)"
echo "WT https $($B timeout 40 $B wget -q -O - https://10.0.2.2:TLSPORT/h.txt 2>&1 | $B tail -n 1)"
echo "WT https-file $($B timeout 40 $B wget -q -O /tmp/h.out https://10.0.2.2:TLSPORT/h.txt >/dev/null 2>&1; $B cat /tmp/h.out 2>&1 | $B tail -n 1)"
echo "WT https-big $($B timeout 60 $B wget -q -O - https://10.0.2.2:TLSPORT/big.bin 2>&1 | $B sha256sum | $B cut -c1-16)"
echo "WT https-twice $($B timeout 40 $B wget -q -O - https://10.0.2.2:TLSPORT/h.txt 2>&1 | $B tail -n 1)"
echo "WT ssl-client-applet $($B ssl_client 2>&1 | $B head -n 1 | $B cut -c1-30)"
echo "WT curl-https $(/bin/curl -sSk --max-time 30 https://10.0.2.2:TLSPORT/h.txt 2>&1 | $B tail -n 1)"
/bin/t_eof HTTPPORT
/bin/t_relay HTTPPORT
echo "WT end"
