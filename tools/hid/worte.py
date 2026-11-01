#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import glob
import os
import re
import sys

BEKANNT = {
    ("disp", "dispeigen"), ("disp", "dispeigenbad"),
    ("disp", "dispeigenfrist"),
    ("dispeigen", "dispeigenbad"), ("dispeigen", "dispeigenfrist"),
    ("ehci", "ehcitest"),
    ("nic", "nicself"), ("nic", "nictab"),
    ("bench", "dispbench"), ("bench", "netmonbench"),
    ("disp", "dispback"), ("disp", "dispbad"), ("disp", "dispbench"),
    ("disp", "dispbig"), ("disp", "dispconfirm"), ("disp", "dispedid"),
    ("disp", "disprot"),
    ("nic", "nicintx"), ("nic", "nicnobm"), ("nic", "nicnoirq"),
    ("nobm", "nicnobm"),
    ("noirq", "nicnoirq"), ("noirq", "usbnoirq"),
    ("share", "noshare"),
    ("usb", "nousb"), ("usb", "usbhold"), ("usb", "usbnoirq"),
    ("usb", "usbpoll"), ("usb", "usbstick"),
    ("usb", "usbstop"), ("usb", "usbleg"),
    ("audio", "noaudio"),
    ("flip", "noflip"),
    ("self", "blkself"), ("self", "nicself"),
}


def main():
    kdir = sys.argv[1] if len(sys.argv) > 1 else "kernel"
    worte = {}
    def _all(d):
        aus = []
        for stamm, verz, names_2 in os.walk(d):
            verz[:] = [v for v in verz if v not in ("user", "app")]
            aus += [os.path.join(stamm, n) for n in names_2 if n.endswith(".fi")]
        return sorted(aus)

    for pfad in _all(kdir):
        quelle = open(pfad, "r", encoding="utf-8", errors="replace").read()
        for name, w in re.findall(
                r'var (w_\w+): \[u8; \d+\] = "([a-z0-9._=/-]+)\\0', quelle):
            worte.setdefault(w, []).append("%s:%s" % (os.path.basename(pfad),
                                                      name))
    bad = 0
    gefunden = set()
    for a in sorted(worte):
        for b in sorted(worte):
            if a != b and a in b:
                gefunden.add((a, b))
                if (a, b) not in BEKANNT:
                    print("  FALL  %-10s steckt in %-10s (%s / %s)"
                          % (a, b, worte[a][0], worte[b][0]))
                    bad += 1
    tot = BEKANNT - gefunden
    for a, b in sorted(tot):
        print("  NOTE %s/%s is in KNOWN, but no longer exists"
              % (a, b))
    if bad:
        print("  %d NEW overlaps among %d mode words"
              % (bad, len(worte)))
        return 1
    print("  ok    %d mode words, %d known overlaps, none new"
          % (len(worte), len(gefunden)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
