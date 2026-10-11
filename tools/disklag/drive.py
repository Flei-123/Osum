#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/disklag/drive.py -- boot a kernel with an OFS root on a THROTTLED
AHCI disk (a stand-in for a rotating laptop disk) and time shell commands.

usage: drive.py <kernel.mb> <root.img> <iops> <workdir> [cmdline] [--keys]

Output: one line per measurement, "M name=value".  The shell is driven over
a serial pipe; the QEMU monitor is used for `sendkey` (lost-key test).
"""
import os, sys, time, subprocess, threading, socket, re

kernel, img, iops, work = sys.argv[1:5]
cmdline = sys.argv[5] if len(sys.argv) > 5 and not sys.argv[5].startswith("--") else "osum"
KEYS = "--keys" in sys.argv
WRITES = int(next((a.split("=")[1] for a in sys.argv if a.startswith("--writes=")), "10"))
os.makedirs(work, exist_ok=True)
for f in ("ser.in", "ser.out"):
    try: os.unlink(os.path.join(work, f))
    except FileNotFoundError: pass
os.mkfifo(os.path.join(work, "ser.in")); os.mkfifo(os.path.join(work, "ser.out"))
mon = os.path.join(work, "mon.sock")
try: os.unlink(mon)
except FileNotFoundError: pass
disk = os.path.join(work, "disk.img")
subprocess.check_call(["cp", "--reflink=auto", img, disk])
drive = f"file={disk},format=raw,if=none,id=d0"
if int(iops) > 0:
    drive += f",throttling.iops-total={iops}"
acc = ["-accel", "kvm", "-cpu", "host"] if os.access("/dev/kvm", os.W_OK) else ["-accel", "tcg"]
cmd = ["qemu-system-x86_64", "-machine", "q35", *acc, "-kernel", kernel, "-m", "256",
       "-append", cmdline, "-display", "none", "-no-reboot",
       "-serial", f"pipe:{os.path.join(work, 'ser')}",
       "-monitor", f"unix:{mon},server,nowait",
       "-drive", drive, "-device", "ahci,id=a0", "-device", "ide-hd,drive=d0,bus=a0.0",
       "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"]
q = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
buf = bytearray(); lock = threading.Lock(); t0 = time.time()
def reader():
    with open(os.path.join(work, "ser.out"), "rb", buffering=0) as f:
        while True:
            d = f.read(4096)
            if not d: break
            with lock: buf.extend(d)
            with open(os.path.join(work, "serial.log"), "ab") as lg: lg.write(d)
threading.Thread(target=reader, daemon=True).start()
sin = open(os.path.join(work, "ser.in"), "wb", buffering=0)

def text():
    with lock: return bytes(buf).decode("latin1")
def wait_for(pat, timeout, start=0):
    end = time.time() + timeout
    while time.time() < end:
        m = re.search(pat, text()[start:])
        if m: return time.time(), start + m.end()
        if q.poll() is not None: break
        time.sleep(0.05)
    return None, start
def out(k, v): print(f"M {k}={v}", flush=True)

try:
    t, pos = wait_for(r"sh:1|\$ |# ", 240)
    if t is None:
        out("boot", "FAIL"); print(text()[-600:]); sys.exit(1)
    out("boot_to_shell_s", f"{t - t0:.1f}")
    m = re.search(r"ahci:[^\n]*", text()); 
    time.sleep(1)
    ms = socket.socket(socket.AF_UNIX); ms.connect(mon); time.sleep(0.2); ms.recv(65536)
    def stats():
        ms.settimeout(0.2)
        try:
            while ms.recv(65536): pass
        except socket.timeout:
            pass
        ms.send(b"info blockstats\n")
        d = ""; end = time.time() + 5
        while time.time() < end and d.count("idle_time_ns") < 2:
            try: d += ms.recv(65536).decode("latin1")
            except socket.timeout: pass
        m = re.search(r"\nd0: [^\n]*", d)
        line = m.group(0) if m else ""
        g = lambda k: int((re.search(k + r"=(\d+)", line) or [0, 0])[1])
        return g("rd_operations"), g("wr_operations"), g("flush_operations")
    def timed_n(name, line, k, timeout=900):
        s0 = stats(); p0 = len(text()); t1 = time.time()
        sin.write((line + "\n").encode())
        end = time.time() + timeout; done = False
        while time.time() < end:
            if text()[p0:].count("-> ") >= k: done = True; break
            time.sleep(0.05)
        t2 = time.time()
        out(name + "_s", f"{(t2 - t1):.2f}" if done else "TIMEOUT")
        s1 = stats()
        out(name + "_rd_wr_flush", "/".join(str(b - a) for a, b in zip(s0, s1)))
    def timed(name, line, marker, timeout=600):
        s0 = stats()
        p0 = len(text())
        t1 = time.time()
        sin.write((line + "\n").encode())
        t, _ = wait_for(re.escape(marker), timeout, p0 + len(line) + 1)
        out(name + "_s", f"{(t - t1):.2f}" if t else "TIMEOUT")
        s1 = stats()
        out(name + "_rd_wr_flush", "/".join(str(b - a) for a, b in zip(s0, s1)))
    timed("echo", "echo M1", "M1")
    timed("ls_etc", "ls /etc", "f300.conf", 600)
    timed("ls_etc_again", "ls /etc", "f300.conf", 600)
    for i in range(1, WRITES + 1):
        timed_n(f"write{i}", f"echo hello{i} > /etc/w{i}.txt", 1)
    timed_n("ls_after_write", "ls /etc", 1)
    if KEYS:
        # lost-key test: start a disk-heavy command, type a word through the
        # monitor (PS/2) with 40 ms gaps while it runs, press return after,
        # and see how much of the word reached the shell's line buffer.
        word = "abdeghijkpqrvyz"
        p0 = len(text())
        sin.write(b"ls /etc\n")
        time.sleep(0.3)
        ms.settimeout(0.2)
        for ch in word:
            ms.send(f"sendkey {ch}\n".encode()); time.sleep(0.04)
        t, _ = wait_for(r"f300\.conf", 600, p0)
        time.sleep(4)
        p1 = len(text())
        ms.send(b"sendkey ret\n"); time.sleep(2)
        tail = text()[p1:]
        toks = re.findall(r"[abdeghijkpqrvyz]{2,}", tail)
        got = max((len(x) for x in toks), default=0)
        out("keys_sent", len(word)); out("keys_in_line", got)
        out("tail", repr(tail[-160:]))
finally:
    q.kill(); q.wait()
    open(os.path.join(work,'serial.log'),'w').write(text())
