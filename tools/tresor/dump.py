#!/usr/bin/env python3
"""tools/tresor/dump.py -- den ECHTEN Speicher der Maschine holen.

    dump.py <kernelabbild> <ausgabe.bin> [serielle-ausgabe]

Startet QEMU genau so, wie die Testlaeufer es tun, laesst der Firmware
Zeit, ihre Tabellen abzulegen, und schreibt danach ueber den QEMU-Monitor
(`pmemsave`) das erste Megaoktett des physischen Speichers in eine Datei.

WOZU. Der Kernel behauptet, er lese SMBIOS. Diese Datei besorgt dem WIRT
denselben Speicher, damit `tools/tresor/smbios.py` ihn mit einer zweiten,
unabhaengigen Umsetzung entschluesseln kann. Erst dann ist "der Kernel
liest die Tabelle richtig" gemessen und nicht behauptet.

DIE WARTEZEIT IST NICHT WILLKUERLICH. Beim ersten Versuch wurde sofort
nach dem Start abgezogen, und im F-Segment stand nichts als das
Zeichenkettenfeld von SeaBIOS -- die Firmware war noch gar nicht so weit.
Ein Abzug ohne Wartezeit misst den Zustand VOR dem, was man messen will.
"""
import os
import subprocess
import sys
import tempfile
import time

WARTE = 6.0


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
        # Der Monitor kennt kein `sleep`; die Pausen macht dieses Programm,
        # indem es die Zeilen langsam nachschiebt.
        time.sleep(WARTE)
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
