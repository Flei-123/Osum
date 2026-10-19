#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/bench/refboot.py <kind> <workdir> <artifact> [runs] -- boot a reference distro in QEMU/KVM and measure it (prints JSON).
kind: alpine (virt ISO, kernel+initramfs taken from the ISO), tinycore (CorePure64 ISO + a tiny extra initrd that reports from
/opt/bootlocal.sh), debian (cloud nocloud qcow2 prepared by debprep.sh). Same machine as tools/bench/measure.sh: KVM, 2 vCPU, 1536 MiB, headless, COM1 on stdio.
Measured per run: boot_prompt_ms (host clock QEMU start -> login prompt / init-done marker), idle memory 20 s later from
/proc/meminfo (used = MemTotal - MemFree; used_avail = MemTotal - MemAvailable), rootfs used MB (df /). Median over runs."""
import json, os, re, shutil, statistics, subprocess, sys, threading, time

kind, wd, art = sys.argv[1], sys.argv[2], sys.argv[3]
runs = int(sys.argv[4]) if len(sys.argv) > 4 else 3
MEMSH = "echo M:$(awk '/^MemTotal/{t=$2}/^MemFree/{f=$2}/^MemAvailable/{a=$2}END{print t,f,a}' /proc/meminfo); echo D:$(df -m / | awk 'NR==2{print $3}'); echo X:END"
base = ["qemu-system-x86_64", "-enable-kvm", "-cpu", "host", "-smp", "2", "-m", "1536", "-display", "none", "-no-reboot",
        "-nographic", "-serial", "stdio", "-monitor", "none", "-net", "none"]


def prep():
    if kind == "alpine":
        subprocess.run(["xorriso", "-osirrox", "on", "-indev", art, "-extract", "/boot/vmlinuz-virt", wd + "/vmlinuz",
                        "-extract", "/boot/initramfs-virt", wd + "/initrd"], check=True, capture_output=True)
        return base + ["-kernel", wd + "/vmlinuz", "-initrd", wd + "/initrd", "-cdrom", art,
                       "-append", "console=ttyS0 modules=loop,squashfs,sd-mod,sr_mod,isofs,usb-storage"], r"login:"
    if kind == "tinycore":
        subprocess.run(["xorriso", "-osirrox", "on", "-indev", art, "-extract", "/boot/vmlinuz64", wd + "/vmlinuz",
                        "-extract", "/boot/corepure64.gz", wd + "/core.gz"], check=True, capture_output=True)
        os.makedirs(wd + "/x/opt", exist_ok=True)
        open(wd + "/x/opt/bootlocal.sh", "w").write(
            "#!/bin/sh\necho BENCHREADY >/dev/ttyS0\nsleep 20\n( " + MEMSH + " ) >/dev/ttyS0 2>&1\n")
        os.chmod(wd + "/x/opt/bootlocal.sh", 0o755)
        subprocess.run("cd %s/x && find . | cpio -o -H newc 2>/dev/null | gzip -9 > ../extra.gz && cat ../core.gz ../extra.gz > ../init.gz" % wd,
                       shell=True, check=True)
        return base + ["-kernel", wd + "/vmlinuz", "-initrd", wd + "/init.gz", "-append", "console=ttyS0"], r"BENCHREADY"
    if kind == "debian":
        return base + ["-drive", "file=%s/disk.qcow2,if=virtio,format=qcow2"], r"login:"
    sys.exit("unknown kind")


def one(i):
    cmd, ready = prep()
    if kind == "debian":
        shutil.copy(art, wd + "/disk.qcow2")  # art = debprep.sh output (no first-boot wizard, empty root password)
        cmd = [c.replace("%s/disk.qcow2", wd + "/disk.qcow2") if "%s" in c else c for c in cmd]
    buf = bytearray()
    t0 = time.time()
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    mark = {}

    def rd():
        while True:
            b = p.stdout.read(1)
            if not b:
                return
            buf.extend(b)
            if "ready" not in mark and re.search(ready.encode(), bytes(buf[-200:]).replace(b"\r", b"")):
                mark["ready"] = time.time() - t0
    th = threading.Thread(target=rd, daemon=True); th.start()
    end = time.time() + 300
    while "ready" not in mark and time.time() < end and p.poll() is None:
        time.sleep(0.05)
    if "ready" not in mark:
        p.kill(); sys.stderr.write(bytes(buf[-400:]).decode("latin1")); return None
    time.sleep(20)
    for attempt in range(4 if kind != "tinycore" else 1):
        if kind != "tinycore":
            p.stdin.write(b"\nroot\n"); p.stdin.flush(); time.sleep(2)
            p.stdin.write(b"\n"); p.stdin.flush(); time.sleep(3)  # empty password prompt (debian); a bare newline at a shell is harmless
            p.stdin.write((MEMSH + "\n").encode()); p.stdin.flush()
        end = time.time() + 12
        while b"X:END" not in bytes(buf).replace(b"echo X:END", b"") and time.time() < end:
            time.sleep(0.2)
        if b"X:END" in bytes(buf).replace(b"echo X:END", b""):
            break
    txt = bytes(buf).decode("latin1")
    txt = re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", "", txt).replace("\r", "")  # debian: bracketed-paste escapes sit right before "M:"
    p.kill(); p.wait()
    m = re.search(r"^M:(\d+) (\d+) (\d+)", txt, re.M); d = re.search(r"^D:(\d+)", txt, re.M)
    if not m:
        sys.stderr.write("no M: line\n" + txt[-500:]); return None
    t, f, a = (int(x) / 1024.0 for x in m.groups())
    return {"boot_prompt_ms": mark["ready"] * 1000, "idle_used_mb": t - f, "idle_used_avail_mb": t - a,
            "mem_total_mb": t, "rootfs_used_mb": int(d.group(1)) if d else -1}


res = [r for r in (one(i) for i in range(runs)) if r]
if not res:
    sys.exit("all runs failed")
out = {k: round(statistics.median(r[k] for r in res), 1) for k in res[0]}
out["image_mb"] = round(os.path.getsize(art.replace("-primed", "")) / 1048576.0, 1)
out["runs_ok"] = len(res)
print(json.dumps({kind: out}))
