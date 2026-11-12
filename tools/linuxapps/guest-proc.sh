echo "APPS start"
export HOME=/root TERM=xterm PATH=/usr/bin:/bin
echo "PROC ls: $(ls /proc | tr '\n' ' ' | cut -c1-300)"
echo "PROC stat: $(head -3 /proc/stat | tr '\n' '|')"
echo "PROC cpuinfo: $(grep -c processor /proc/cpuinfo)"
echo "PROC self: $(ls /proc/self | tr '\n' ' ' | cut -c1-300)"
echo "PROC self-stat: $(cat /proc/self/stat | cut -c1-200)"
echo "PROC self-statm: $(cat /proc/self/statm)"
echo "PROC self-status: $(head -8 /proc/self/status | tr '\n' '|')"
echo "PROC self-comm: $(cat /proc/self/comm)"
echo "PROC meminfo: $(head -3 /proc/meminfo | tr '\n' '|')"
echo "PROC uptime: $(cat /proc/uptime)"
echo "PROC loadavg: $(cat /proc/loadavg)"
python3 - <<'PY'
import os
n = 0
for e in os.scandir('/proc'):
    if e.name.isdigit():
        n += 1
        print("PROC dirent", e.name, e.is_dir(follow_symlinks=False), e.is_dir())
print("PROC pids", n)
for f in ('stat', 'statm', 'status', 'cmdline', 'comm', 'io', 'smaps_rollup', 'exe', 'cwd', 'fd', 'maps', 'environ', 'cgroup', 'oom_score'):
    p = '/proc/%d/%s' % (os.getpid(), f)
    try:
        if f in ('exe', 'cwd'):
            print("PROC", f, os.readlink(p))
        elif f == 'fd':
            print("PROC fd", len(os.listdir(p)))
        else:
            print("PROC", f, len(open(p).read()))
    except Exception as e:
        print("PROC", f, "ERR", e)
PY
echo "PROC statall: $(grep -c '^cpu' /proc/stat) cpu lines"
echo "PROC uid: $(grep -E '^(Uid|Gid)' /proc/self/status | tr '\t' ' ' | tr '\n' '|')"
timeout 8 htop -d 5 < /dev/null > /tmp/h.out 2>&1
echo "PROC htop rc=$?"
echo "PROC htop-tasks: $(tr -d '\033' < /tmp/h.out | grep -o 'Tasks:[^,]*,[^,]*,' | head -1)"
echo "PROC htop-cpu: $(tr -d '\033' < /tmp/h.out | grep -c 'offline')"
echo APPS-END
echo FX-END
