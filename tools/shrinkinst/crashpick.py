#!/usr/bin/env python3
import os, re, shutil, subprocess, sys


def sh(*a):
    return subprocess.run(a, capture_output=True)


def main():
    exe, disk, base, old_psize, target, writes, mode, work = sys.argv[1:9]
    base, old_psize, target, writes = int(base), int(old_psize), int(target), int(writes)
    t = os.path.join(work, "pick.img")
    for k in range(1, writes):
        shutil.copyfile(disk, t)
        sh(exe, t, "r", str(base), t, str(target), str(k), "1" if mode == "torn" else "0")
        v = sh("sgdisk", "-v", t).stdout
        clean = b"No problems found" in v
        m = re.search(rb"Partition size: (\d+) sectors", sh("sgdisk", "-i", "2", t).stdout)
        old_table = bool(m) and int(m.group(1)) == old_psize
        with open(t, "rb") as f:
            f.seek(base * 512 + 0x28)
            total = int.from_bytes(f.read(8), "little")
        committed = total == target - 1
        if mode == "torn" and not clean:
            print(k)
            os.unlink(t)
            return
        if mode == "intent" and clean and old_table and committed:
            print(k)
            os.unlink(t)
            return
    if os.path.exists(t):
        os.unlink(t)
    sys.exit(1)


main()
