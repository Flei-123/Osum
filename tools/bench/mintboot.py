#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/bench/mintboot.py <mint.iso> <workdir> [runs] [vcpu] [mem_mb] -- boot Linux Mint (live ISO) in QEMU/KVM and measure it (prints JSON).
Method (host side only, the live ISO is NOT modified):
  * kernel + initrd are taken out of the ISO and direct-booted (no bootloader menu, like refboot.py alpine); the ISO is the cdrom.
  * desktop_ms = host clock QEMU start -> first screen frame that equals the final settled desktop frame (QMP screendump every 0.5 s,
    mean abs diff of a 96x72 grid <= 1.5 grey levels for all later frames; settled = 10 s without change and not blank: mean>8, stdev>15).
  * idle_cpu_pct = host CPU of the QEMU process (utime+stime) over 30 s, 15 s after the desktop settled, nothing touched.
  * Then Ctrl+Alt+T opens a terminal; the typed command mounts a tiny MEASURE cdrom and runs m.sh, which writes to the serial line:
    memory (MemTotal/MemFree/MemAvailable), squashfs size and app start times (launch -> new window in _NET_CLIENT_LIST).
Median over runs. Memory is taken with one terminal open (it is the measurement shell)."""
import json, os, re, socket, statistics, subprocess, sys, time, zlib

iso, wd = sys.argv[1], sys.argv[2]
runs = int(sys.argv[3]) if len(sys.argv) > 3 else 3
vcpu = sys.argv[4] if len(sys.argv) > 4 else "3"
mem = sys.argv[5] if len(sys.argv) > 5 else "2048"

M_SH = r'''
now() { date +%s%N; }
echo M:$(awk '/^MemTotal/{t=$2}/^MemFree/{f=$2}/^MemAvailable/{a=$2}END{print t,f,a}' /proc/meminfo)
echo S:$(du -m /cdrom/casper/filesystem.squashfs 2>/dev/null | cut -f1)
n() { xprop -root _NET_CLIENT_LIST 2>/dev/null | tr ',' '\n' | grep -c 0x; }
for app in xfce4-terminal thunar xed; do
    b=$(n); t0=$(now); $app >/dev/null 2>&1 &
    pid=$!; ok=0
    for i in $(seq 1 600); do
        if [ "$(n)" -gt "$b" ]; then ok=1; break; fi
        sleep 0.05
    done
    t1=$(now)
    [ $ok = 1 ] && echo APP:$app:$(( (t1 - t0) / 1000000 )) || echo APP:$app:-1
    sleep 2; kill $pid 2>/dev/null; sleep 1
done
echo X:END
'''

KEYS = {" ": "spc", "\n": "ret", "/": "slash", "-": "minus", ".": "dot", ";": "semicolon", "=": "equal", "'": "apostrophe",
        "|": "shift+backslash", "_": "shift+minus", ">": "shift+dot", ":": "shift+semicolon", "$": "shift+4", "&": "shift+7"}


class Qmp:
    def __init__(self, path):
        self.s = socket.socket(socket.AF_UNIX)
        for _ in range(100):
            try:
                self.s.connect(path); break
            except OSError:
                time.sleep(0.1)
        self.f = self.s.makefile("rw")
        self.f.readline(); self.cmd("qmp_capabilities")

    def cmd(self, name, **args):
        self.f.write(json.dumps({"execute": name, "arguments": args}) + "\n"); self.f.flush()
        while True:
            r = json.loads(self.f.readline())
            if "return" in r or "error" in r:
                return r

    def key(self, spec, hold=40):
        ks = [{"type": "qcode", "data": k} for k in spec.split("+")]
        self.cmd("send-key", keys=ks, **{"hold-time": hold})

    def type(self, text):
        for ch in text:
            self.key(KEYS.get(ch, "shift+" + ch.lower() if ch.isupper() else ch)); time.sleep(0.03)


def grid(path):
    """96x72 grey grid + brightness from a PPM screendump (None if unreadable)."""
    try:
        d = open(path, "rb").read()
        m = re.match(rb"P6\s+(\d+)\s+(\d+)\s+255\s", d)
        w, h = int(m.group(1)), int(m.group(2)); o = m.end()
        g = []
        for gy in range(72):
            y = gy * h // 72
            row = d[o + (y * w) * 3: o + (y * w + w) * 3]
            for gx in range(96):
                x = gx * w // 96
                g.append((row[x * 3] + row[x * 3 + 1] + row[x * 3 + 2]) // 3)
        return g, w, h, d[o:]
    except Exception:
        return None


def diff(a, b):
    return sum(abs(x - y) for x, y in zip(a, b)) / len(a)


def png(path, w, h, rgb):
    raw = b"".join(b"\0" + rgb[y * w * 3:(y + 1) * w * 3] for y in range(h))
    def ch(t, c):
        return len(c).to_bytes(4, "big") + t + c + (zlib.crc32(t + c) & 0xffffffff).to_bytes(4, "big")
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", w.to_bytes(4, "big") + h.to_bytes(4, "big") + b"\x08\x02\0\0\0")
                           + ch(b"IDAT", zlib.compress(raw, 6)) + ch(b"IEND", b""))


def cpu_ticks(pid):
    f = open("/proc/%d/stat" % pid).read().rsplit(")", 1)[1].split()
    return int(f[11]) + int(f[12])


def prep():
    ex = wd + "/x"; os.makedirs(ex, exist_ok=True)
    subprocess.run(["xorriso", "-osirrox", "on", "-indev", iso, "-extract", "/casper/vmlinuz", ex + "/vmlinuz",
                    "-extract", "/casper/initrd.lz", ex + "/initrd"], check=True, capture_output=True)
    open(ex + "/m.sh", "w").write(M_SH)
    subprocess.run(["xorriso", "-as", "mkisofs", "-V", "MEASURE", "-o", wd + "/measure.iso", ex + "/m.sh"], check=True, capture_output=True)


def one(i):
    sock = wd + "/qmp.sock"; ser = wd + "/serial.log"; shot = wd + "/s.ppm"
    for p in (sock, ser):
        if os.path.exists(p):
            os.remove(p)
    cmd = ["qemu-system-x86_64", "-enable-kvm", "-cpu", "host", "-smp", vcpu, "-m", mem, "-display", "none", "-vga", "std",
           "-no-reboot", "-net", "none", "-qmp", "unix:%s,server,nowait" % sock, "-serial", "file:" + ser,
           "-kernel", wd + "/x/vmlinuz", "-initrd", wd + "/x/initrd", "-append", "boot=casper console=ttyS0 noprompt",
           "-drive", "file=%s,media=cdrom,readonly=on,if=ide,index=0" % iso,
           "-drive", "file=%s/measure.iso,media=cdrom,readonly=on,if=ide,index=1" % wd]
    t0 = time.time()
    p = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        q = Qmp(sock)
        frames = []  # (t, grid)
        last_g = None; fin = None
        while time.time() - t0 < 240:
            time.sleep(0.5)
            q.cmd("screendump", filename=shot)
            r = grid(shot)
            if not r:
                continue
            g = r[0]; t = time.time() - t0
            frames.append((t, g))
            if sum(g) / len(g) > 8 and statistics.pstdev(g) > 15:  # not a black/blank screen (the Mint wallpaper is dark)
                recent = [x for x in frames if x[0] > t - 10]
                if t > 12 and recent[0][0] < t - 9.5 and all(diff(x[1], g) <= 1.5 for x in recent):
                    fin = r; break
        if not fin:
            sys.stderr.write("no settled desktop\n"); return None
        fg = fin[0]; settle_t = frames[-1][0]
        k = len(frames) - 1
        while k > 0 and diff(frames[k - 1][1], fg) <= 1.5:
            k -= 1
        desktop_ms = frames[k][0] * 1000
        png(wd + "/desktop%d.png" % i, fin[1], fin[2], fin[3])
        time.sleep(15)
        c0, w0 = cpu_ticks(p.pid), time.time(); time.sleep(30); c1, w1 = cpu_ticks(p.pid), time.time()
        idle_cpu = (c1 - c0) / os.sysconf("SC_CLK_TCK") / (w1 - w0) * 100
        q.key("ctrl+alt+t"); time.sleep(5)
        q.type("until sudo mount -o ro /dev/sr1 /mnt;do sleep 1;done;sh /mnt/m.sh|sudo tee /dev/ttyS0\n")
        end = time.time() + 90
        while time.time() < end and "X:END" not in open(ser, errors="replace").read().replace("\r", "").split("tee /dev/ttyS0")[-1]:
            time.sleep(1)
        txt = open(ser, errors="replace").read().replace("\r", "")
        q.cmd("screendump", filename=shot)
        m = re.search(r"M:(\d+) (\d+) (\d+)", txt)
        if not m:
            sys.stderr.write("no M: line\n" + txt[-400:]); return None
        t_, f_, a_ = (int(x) / 1024.0 for x in m.groups())
        s = re.search(r"S:(\d+)", txt)
        out = {"desktop_ms": desktop_ms, "idle_used_mb": t_ - f_, "idle_used_avail_mb": t_ - a_, "mem_total_mb": t_,
               "idle_cpu_pct": idle_cpu, "squashfs_mb": int(s.group(1)) if s else -1}
        for a, ms in re.findall(r"APP:([\w-]+):(-?\d+)", txt):
            out["app_" + a.replace("xfce4-", "") + "_ms"] = int(ms)
        return out
    finally:
        p.kill(); p.wait()


prep()
res = [r for r in (one(i) for i in range(runs)) if r]
if not res:
    sys.exit("all runs failed")
keys = set().union(*[r.keys() for r in res])
out = {k: round(statistics.median(r[k] for r in res if k in r), 1) for k in sorted(keys)}
out["image_mb"] = round(os.path.getsize(iso) / 1048576.0, 1)
out["runs_ok"] = len(res); out["vcpu"] = int(vcpu); out["mem_mb"] = int(mem)
print(json.dumps({"mint_xfce": out}))
if os.environ.get("MINT_KEEP_SHOTS"):
    subprocess.run("cp %s/desktop*.png %s/" % (wd, os.environ["MINT_KEEP_SHOTS"]), shell=True)
