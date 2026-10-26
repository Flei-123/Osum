echo MARK-text
xclip gen -g 100
xclip get
xclip gen -g 192
xclip get
xclip gen -g 193
xclip get
xclip gen -g 4096
xclip get
xclip gen -g 4097
xclip get
xclip gen -g 1048576
xclip get
xclip gen -g 2097152
xclip get
xclip gen -g 2097153
echo MARK-lazy
xclip stat
xclip offer -t image/png -g 300000 -k 1 -m 8000 &
sleep 1
xclip stat
xclip get -t text/plain
xclip stat
xclip get -t image/png
xclip stat
wait
echo MARK-multi
xclip offer -t text/plain,text/html -w hello -k 2 -m 8000 &
sleep 1
xclip get -t text/html
xclip get -t text/plain
wait
echo MARK-expiry
xclip offer -t image/png -g 1000 -k 1 -m 500
xclip types
echo MARK-custom
xclip mime application/x-osum-test
xclip mime application/x-osum-test
xclip mime application/x-osum-other
xclip mime nonsense
xclip offer -t application/x-osum-test -g 5000 -k 1 -m 8000 &
sleep 1
xclip get -t application/x-osum-test
wait
echo MARK-primary
xclip put -s primary AAAA
xclip put BBBB
xclip text -s primary
xclip text
echo MARK-history
for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do xclip put h$i; done
xclip text
xclip types
xclip text -b 19
xclip text -b 20
echo MARK-evict
xclip stat
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22; do xclip gen -g 300; done
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22; do xclip gen -g 300; done
xclip stat
echo MARK-uris
xclip puturis "/data/a b.txt" /x/y
xclip types
xclip uris
xclip text
echo MARK-drag
xclip put -s drag -t text/x-osum-path -m 5000 /data/file1 &
sleep 1
xclip types -s drag
xclip noti post probe-noti
xclip put -s drag -t text/x-osum-path -m 3000 /data/file2 &
sleep 1
xclip noti peek
xclip text -s drag
xclip clear -s drag
xclip types -s drag
wait
echo MARK-leak
xclip clear
xclip clear -s primary
xclip types
xclip stat
echo MARK-end
