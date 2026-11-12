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
check() {
    n=$1; want=$2; shift 2
    if "$@" > /tmp/c.$n 2>&1 && grep -q -- "$want" /tmp/c.$n; then echo "PROC-CHECK $n ok"; else echo "PROC-CHECK $n red: $(head -c 120 /tmp/c.$n | tr '\n' '|')"; fi
}
cat > /tmp/pt.py <<'PY'
import os, threading
ev = threading.Event()
th = threading.Thread(target=ev.wait)
th.start()
pid = os.getpid()
tids = sorted(os.listdir('/proc/self/task'))
assert str(pid) in tids and len(tids) >= 2, tids
for tid in tids:
    d = '/proc/self/task/' + tid
    assert os.path.isdir(d)
    assert open(d + '/stat').read().split()[0] == tid
    status = open(d + '/status').read()
    tgid = [l for l in status.split('\n') if l.startswith('Tgid:')]
    assert tgid and int(tgid[0].split()[1]) == pid, status
    assert open(d + '/comm').read().strip()
assert os.path.isdir('/proc/%d/task/%d' % (pid, pid))
assert not os.path.exists('/proc/self/task/999999')
ev.set()
th.join()
print("PROC-TASK-OK", len(tids))
PY
check proc-task-threads PROC-TASK-OK python3 /tmp/pt.py
check proc-task-ls "^$$\$" ls /proc/$$/task
check proc-task-stat "^$$ " cat /proc/$$/task/$$/stat
check sys-class-net-lo "^lo$" ls /sys/class/net
check sys-lo-mtu 65536 cat /sys/class/net/lo/mtu
check sys-node-online "^0$" cat /sys/devices/system/node/online
check sys-thp-enabled "never" cat /sys/kernel/mm/transparent_hugepage/enabled
check sys-boot-id "-" cat /sys/kernel/random/boot_id
check sys-cgroup-dir "cgroup" ls /sys/fs
check sys-cpu-online "^0" cat /sys/devices/system/cpu/online
check sys-root-ls "kernel" ls /sys
check sys-devices-system "node" ls /sys/devices/system
timeout 8 htop -d 5 < /dev/null > /tmp/h.out 2>&1
echo "PROC htop rc=$?"
echo "PROC htop-tasks: $(tr -d '\033' < /tmp/h.out | sed 's/\[[0-9;?]*[a-zA-Z]//g; s/(B//g' | grep -o 'Tasks:[^,]*,[^,]*,' | head -1)"
check htop-tasks-nonzero "Tasks: *[1-9]" sh -c "tr -d '\033' < /tmp/h.out | sed 's/\[[0-9;?]*[a-zA-Z]//g; s/(B//g'"
echo "PROC htop-cpu: $(tr -d '\033' < /tmp/h.out | grep -c 'offline')"
echo APPS-END
echo FX-END
