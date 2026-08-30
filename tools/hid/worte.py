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

# DIE BEKANNTEN UEBERSCHNEIDUNGEN.  Sie sind alle vom selben Bauplan:
# ein BREITER Schalter und eine Verfeinerung davon (`usb` und
# `usbhold`, `disp` und `dispbench`, `nic` und `nicnoirq`).  Dort ist
# das GEWOLLT -- wer `usbhold` schreibt, will USB.  Der Fall `usb` /
# `nousb` ist derselbe und in kmain.fi seit Runde K17 ausdruecklich
# beschrieben: BEIDE Bits werden gesetzt und `usb.stage` sieht beide an.
#
# Was hier NICHT stehen darf, ist der Fall, in den Runde HID gelaufen
# ist: ein ABSCHALTER, der in einem fremden Wort steckt und dort etwas
# ganz anderes ausschaltet (`nohid` in `nohidrep`).  Wer ein neues Wort
# einfuehrt, das hier auftaucht, muss sich das ueberlegen und es
# eintragen -- oder das Wort umbenennen, so wie diese Runde es getan hat.
BEKANNT = {
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
}


def main():
    kdir = sys.argv[1] if len(sys.argv) > 1 else "kernel"
    worte = {}
    for pfad in sorted(glob.glob(os.path.join(kdir, "*.fi"))):
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
    # Und andersherum: verschwindet ein bekanntes Paar, gehoert es aus
    # der Liste heraus -- sonst deckt sie irgendwann etwas zu, das gar
    # nicht mehr da ist.
    tot = BEKANNT - gefunden
    for a, b in sorted(tot):
        print("  HINWEIS %s/%s steht in BEKANNT, gibt es aber nicht mehr"
              % (a, b))
    if schlecht:
        print("  %d NEUE Ueberschneidungen unter %d Moduswoertern"
              % (schlecht, len(worte)))
        return 1
    print("  ok    %d Moduswoerter, %d bekannte Ueberschneidungen, keine neue"
          % (len(worte), len(gefunden)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
