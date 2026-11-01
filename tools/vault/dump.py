#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    dump.py <kernelabbild> <output.bin> [serielle-output]
"""
import os
import subprocess
import sys
import tempfile
import time

WAIT = 6.0


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    kernel, out = argv[1], argv[2]
    seriell = argv[3] if len(argv) > 3 else os.path.join(
        tempfile.mkdtemp(), "ser.txt")
    out = os.path.abspath(out)
    if os.path.exists(out):
        os.unlink(out)

    qemu = [
        "qemu-system-x86_64", "-kernel", kernel, "-m", "256",
        "-append", "nokbd nosched noproc nofs noring3",
        "-serial", "file:" + seriell,
        "-display", "none", "-no-reboot",
        "-monitor", "stdio",
    ]
    p = subprocess.Popen(qemu, stdin=subprocess.PIPE,
                         stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL)
    try:
        time.sleep(WAIT)
        p.stdin.write(('pmemsave 0x0 0x100000 "%s"\n' % out).encode())
        p.stdin.flush()
        time.sleep(2.0)
        p.stdin.write(b"quit\n")
        p.stdin.flush()
        time.sleep(1.0)
    except (BrokenPipeError, OSError):
        pass
    try:
        p.wait(timeout=20)
    except subprocess.TimeoutExpired:
        p.kill()
        p.wait()

    if not os.path.exists(out) or os.path.getsize(out) == 0:
        print("dump: kein Speicherabzug entstanden")
        return 1
    print("dump: %d Oktette in %s" % (os.path.getsize(out), out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
