echo "FX start"
export HOME=/root XDG_RUNTIME_DIR=/tmp MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_DISABLE_SOCKET_PROCESS_SANDBOX=1 MOZ_DISABLE_RDD_SANDBOX=1 MOZ_DISABLE_GMP_SANDBOX=1 MOZ_CRASHREPORTER_DISABLE=1
up() { read u _ < /proc/uptime; echo $u; }
sample() {
    echo "FXS sample $1 t=$(up)"
    for f in /proc/[0-9]*/task/[0-9]*/status; do [ -e "$f" ] && while IFS= read -r l; do echo "$l"; done < "$f"; done 2>/dev/null | awk 'function out(){if(t!="")print "FXT","/proc/"p"/status",g,t,r,n} /^Name:/{out(); sub(/^Name:[ \t]*/,""); n=$0; t=""; g=""; r=""; p=""} /^Pid:/{p=$2} /^Ticks:/{t=$2} /^Runs:/{r=$2} /^Tgid:/{g=$2} END{out()}'
}
mkdir -p /tmp/p
echo 'user_pref("gfx.webrender.software", true);' > /tmp/p/user.js
echo "FX18 launch t=$(up)"
/usr/bin/firefox --headless --window-size=1024,768 --profile /tmp/p ${FX18_URL:-https://example.com} > /tmp/e.log 2>&1 &
sleep ${FX18_LOAD:-60}
if [ -n "${FX18_SMAPS:-}" ]; then
    for p in $(pidof firefox); do
        for f in smaps maps smaps_rollup; do
            t0=$(up); b=$(dd if=/proc/$p/$f bs=32768 2>/dev/null | wc -c); t1=$(up)
            echo "FX18 file pid=$p $f bytes=$b t0=$t0 t1=$t1"
        done
    done
fi
n=0
while [ $n -le ${FX18_SAMPLES:-8} ]; do
    sample $n
    sleep ${FX18_GAP:-30}
    n=$((n + 1))
done
cat /proc/cpus 2>/dev/null
tail -c 600 /tmp/e.log
echo FX-END
