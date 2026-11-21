import os, sys, time, glob

def threads(pid):
    out = {}
    for t in glob.glob("/proc/%d/task/*" % pid):
        try:
            name = open(t + "/comm").read().strip()
            f = open(t + "/stat").read().rsplit(")", 1)[1].split()
            out[os.path.basename(t)] = (name, int(f[11]) + int(f[12]))
        except OSError:
            pass
    return out

def find(marker):
    for p in glob.glob("/proc/[0-9]*"):
        try:
            cmd = open(p + "/cmdline").read()
        except OSError:
            continue
        argv = cmd.split("\0")
        if argv and os.path.basename(argv[0]).startswith("qemu-system") and marker in cmd:
            return int(os.path.basename(p))
    return 0

def main():
    marker, serial, settle, window = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
    deadline = time.time() + 600
    while time.time() < deadline:
        try:
            if b"launcher: ready" in open(serial, "rb").read():
                break
        except OSError:
            pass
        time.sleep(0.5)
    time.sleep(settle)
    pid = find(marker)
    if not pid:
        print("no qemu")
        return 1
    hz = os.sysconf("SC_CLK_TCK")
    a = threads(pid)
    t0 = time.time()
    time.sleep(window)
    b = threads(pid)
    dt = time.time() - t0
    for tid in sorted(b):
        if tid in a:
            print("%s %s %.1f" % (b[tid][0], tid, 100.0 * (b[tid][1] - a[tid][1]) / hz / dt))
    return 0

sys.exit(main())
