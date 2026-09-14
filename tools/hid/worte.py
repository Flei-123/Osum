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
    # RUNDE BLECH-ECHT.  Acht Einschluesse, die erst durch das
    # Zusammenfuehren entstanden sind -- alle acht vom erlaubten
    # Bauplan "breiter Schalter + Verfeinerung", keiner davon ein
    # ABSCHALTER in einem fremden Wort:
    #   disp*   `vmode.fi` sucht diese vier mit `find_word`, also MIT
    #           Wortgrenze -- der Einschluss kann dort gar nicht
    #           zuschlagen.  Sie stehen hier trotzdem, weil worte.py
    #           den ganzen Baum prueft und nicht den Finder kennt.
    #   ehcitest / nicself / nictab  brauchen den breiten Schalter
    #           wirklich: wer die Selbstpruefung des Netztreibers
    #           fahren will, will den Treiber.  Dieselbe Lage wie bei
    #           `nic`/`nicintx`, das seit Runde K17 hier steht.
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
    # RUNDE BLECH-HID.  Zwei weitere Verfeinerungen von `usb`, und
    # beide vom erlaubten Bauplan -- wer den USB-Bericht stehen lassen
    # (`usbstop`) oder die Uebernahme pruefen (`usbleg`) will, will
    # USB.  Kein Abschalter, keiner von beiden hebt etwas Fremdes auf.
    ("usb", "usbstop"), ("usb", "usbleg"),
    # RUNDE ROTABSCHNITTE.  Vier Einschluesse, die durch das
    # Zusammenfuehren der fuenf Runden entstanden sind.  Jeder einzeln
    # nachgesehen, keiner ist der gefaehrliche Fall:
    #
    #   audio / noaudio   Derselbe Bauplan wie `usb`/`nousb` und
    #       `share`/`noshare`, und kmain.fi sagt es woertlich:
    #       "`noaudio` loescht kein Bit, es setzt ein zweites, und
    #       `audio_stage` sieht beide an -- ein Schalter, den sein
    #       eigenes Argument aufhebt, ist keiner."  Wer `noaudio`
    #       schreibt, setzt also BEIDE Bits, und das ist gewollt.
    #
    #   flip / noflip     Dasselbe, nachgerechnet in fb.fi:985:
    #       `if want(state, M_FLIP) && !want(state, M_NOFLIP)`.
    #       Beide Bits werden angesehen, die Gegenprobe gewinnt.
    #
    #   self / blkself, self / nicself   KEIN Einschluss im Betrieb.
    #       `self` ist gar kein Moduswort, sondern ein PFADSEGMENT in
    #       procfs.fi:1207, und es wird mit `streq` verglichen --
    #       exakte Gleichheit auf einem Segment, nicht `find` auf der
    #       ganzen Befehlszeile.  `/proc/self` kann in `blkself` oder
    #       `nicself` nicht zuschlagen; die beiden stehen ausserdem in
    #       anderen Dateien (kmain.fi, hw.fi) und meinen etwas anderes.
    ("audio", "noaudio"),
    ("flip", "noflip"),
    ("self", "blkself"), ("self", "nicself"),
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
