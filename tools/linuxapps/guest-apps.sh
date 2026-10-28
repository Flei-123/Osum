echo "APPS start"
export HOME=/root TERM=xterm XDG_RUNTIME_DIR=/tmp LANG=C
mkdir -p /tmp /root
t() { n=$1; shift; echo "APPS $n begin"; timeout ${APP_TMO:-60} "$@" > /tmp/o.$n 2>&1; rc=$?; echo "APPS $n rc=$rc"; head -${APP_LINES:-6} /tmp/o.$n; }
t busybox busybox --list
t bb-tar sh -c 'echo hello > /tmp/h.txt && tar cf /tmp/h.tar -C /tmp h.txt && tar tf /tmp/h.tar'
t bb-gzip sh -c 'echo hello | gzip -c | gunzip -c'
t bb-sed sh -c 'echo abc | sed s/b/X/'
t bb-awk sh -c 'echo "1 2" | awk "{print \$1+\$2}"'
t bb-find find /etc -maxdepth 1 -name 'p*'
t bb-grep sh -c 'echo abc | grep -c b'
t bb-sort sh -c 'printf "b\na\n" | sort'
t bb-ps ps
t bb-top top -b -n 1
t bb-wget wget -q -O - http://127.0.0.1/
t htop-version htop --version
t htop-run htop -d 5
t nano-version nano --version
t vim-version vim --version
t vim-batch sh -c 'vim -es -u NONE -c "call setline(1,\"hi\")" -c "w /tmp/v.txt" -c q; cat /tmp/v.txt'
t ffmpeg-version ffmpeg -version
t ffmpeg-video ffmpeg -nostdin -f lavfi -i testsrc=d=1:s=64x64:r=5 -f null -
t ffmpeg-audio ffmpeg -nostdin -f lavfi -i sine=d=1 -c:a pcm_s16le /tmp/a.wav
t mpv-version mpv --version
t mpv-play mpv --no-config --vo=null --ao=null /tmp/a.wav
t pcmanfm-version pcmanfm --version
echo APPS-END
echo FX-END
