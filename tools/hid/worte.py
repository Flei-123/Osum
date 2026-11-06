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
    ("nic", "nicfail"), ("nic", "nicflush"), ("nic", "nicich"),
    ("nofpu", "nofpuswitch"), ("nolock", "nolockall"),
    ("usb", "usbholdticks"), ("usb", "usbloss"), ("usb", "usblossff"),
    ("usb", "usbnorescan"), ("usb", "usbstall"), ("usb", "usbtrace"),
    ("usbhold", "usbholdticks"),
}


def main():
    kdir = sys.argv[1] if len(sys.argv) > 1 else "kernel"
    worte = {}
    prefix_used = set()
    lead_used = set()
    def _all(d):
        aus = []
        for stamm, verz, names in os.walk(d):
            verz[:] = [v for v in verz if v not in ("user", "app")]
            aus += [os.path.join(stamm, n) for n in names if n.endswith(".fi")]
        return sorted(aus)

    for path_2 in _all(kdir):
        source = open(path_2, "r", encoding="utf-8", errors="replace").read()
        for found in re.finditer(
                r'var (w_\w+): \[u8; \d+\] = "([a-z0-9._=/-]+)\\0', source):
            name, w = found.group(1), found.group(2)
            worte.setdefault(w, []).append("%s:%s" % (os.path.basename(path_2),
                                                      name))
            end = source.find("\nfn ", found.end())
            body = source[found.end():end if end >= 0 else len(source)]
            if re.search(
                    r'(?<![\w.])(?:bootscan\.)?find\(\s*\w+\s*,\s*\(&'
                    + re.escape(name) + r'\[0\]\)\s+as\s+u64\s*,\s*\w+\s*\)',
                    body):
                prefix_used.add(w)
            elif re.search(
                    r'bootscan\.find_lead\(\s*\w+\s*,\s*\(&'
                    + re.escape(name) + r'\[0\]\)', body):
                lead_used.add(w)
    bad_2 = 0
    gefunden = set()
    for a in sorted(worte):
        for b in sorted(worte):
            if a != b and ((a in prefix_used and a in b)
                           or (a in lead_used and b.startswith(a))):
                gefunden.add((a, b))
                if (a, b) not in BEKANNT:
                    print("  FALL  %-10s steckt in %-10s (%s / %s)"
                          % (a, b, worte[a][0], worte[b][0]))
                    bad_2 += 1
    tot = BEKANNT - gefunden
    for a, b in sorted(tot):
        print("  NOTE %s/%s is in KNOWN, but no longer exists"
              % (a, b))
    if bad_2:
        print("  %d NEW overlaps among %d mode words"
              % (bad_2, len(worte)))
        return 1
    print("  ok    %d mode words, %d known overlaps, none new"
          % (len(worte), len(gefunden)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
