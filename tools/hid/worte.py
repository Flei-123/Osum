#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/hid/worte.py -- KEIN MODUSWORT DARF IN EINEM ANDEREN STECKEN.

`mode_of` in kernel/kmain.fi sucht die Woerter der Kommandozeile mit
einem reinen OKTETTVERGLEICH (`find`); es gibt keine Wortgrenze.  Steckt
ein Moduswort in einem anderen, schaltet der eine Schalter den anderen
stillschweigend mit.

Runde K17 hat das im Kommentar zu `nousb` beschrieben ("ein Schalter, den
sein eigenes Argument aufhebt, ist keiner").  RUNDE HID IST TROTZDEM
HINEINGELAUFEN: die Gegenprobe zum generischen Weg hiess `nohidrep`, und
darin steckt `nohid` -- der Schalter der Runde K17, der die ganze
HID-Eingabe abschaltet.  Damit hatte der Lauf, der beweisen sollte, dass
OHNE den Zerleger alles weiterlaeuft, ueberhaupt kein Eingabegeraet mehr.
Aufgefallen ist es an einer einzigen gefallenen Zusage in
tools/hid/run.sh; ohne die waere der Kernel mit einer Gegenprobe
ausgeliefert worden, die etwas anderes misst, als sie behauptet.

Seitdem wird das mechanisch geprueft -- fuer JEDES Wort im Baum und nicht
nur fuer die dieser Runde.

Aufruf:  python3 tools/hid/worte.py [kernelverzeichnis]
Rueckgabe 0, wenn kein Wort in einem anderen steckt.
"""
import glob
import os
import re
import sys

#
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
    #
    #
    #
    ("audio", "noaudio"),
    ("flip", "noflip"),
    ("self", "blkself"), ("self", "nicself"),
}


def main():
    kdir = sys.argv[1] if len(sys.argv) > 1 else "kernel"
    worte = {}
    def _alle(d):
        aus = []
        for stamm, verz, namen in os.walk(d):
            verz[:] = [v for v in verz if v not in ("user", "app")]
            aus += [os.path.join(stamm, n) for n in namen if n.endswith(".fi")]
        return sorted(aus)

    for pfad in _alle(kdir):
        quelle = open(pfad, "r", encoding="utf-8", errors="replace").read()
        for name, w in re.findall(
                r'var (w_\w+): \[u8; \d+\] = "([a-z0-9._=/-]+)\\0', quelle):
            worte.setdefault(w, []).append("%s:%s" % (os.path.basename(pfad),
                                                      name))
    schlecht = 0
    gefunden = set()
    for a in sorted(worte):
        for b in sorted(worte):
            if a != b and a in b:
                gefunden.add((a, b))
                if (a, b) not in BEKANNT:
                    print("  FALL  %-10s steckt in %-10s (%s / %s)"
                          % (a, b, worte[a][0], worte[b][0]))
                    schlecht += 1
    tot = BEKANNT - gefunden
    for a, b in sorted(tot):
        print("  NOTE %s/%s is in KNOWN, but no longer exists"
              % (a, b))
    if schlecht:
        print("  %d NEW overlaps among %d mode words"
              % (schlecht, len(worte)))
        return 1
    print("  ok    %d mode words, %d known overlaps, none new"
          % (len(worte), len(gefunden)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
