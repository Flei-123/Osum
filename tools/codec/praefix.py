#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/codec/praefix.py -- DIE CAVLC-TAFELN AUF MEHRDEUTIGKEIT PRUEFEN.

Eine Huffman-Tafel, in der ein Code der ANFANG eines anderen ist, ist
mehrdeutig: der Leser nimmt den kuerzeren und liegt ab da falsch. Der
Fehler faellt nicht dort auf, wo er steht, sondern drei Koeffizienten
spaeter als "Code nicht in der Tafel" -- und dann sucht man ihn an der
falschen Stelle. Genau das ist in dieser Runde passiert, bevor die
Tafeln erzeugt statt abgetippt wurden.

Geprueft wird DIE DATEI, DIE DER KERN BENUTZT (kernel/user/h264tab.fi),
und nicht die Quelle daneben -- sonst prueft man das Falsche.

Zwei Bedingungen je Tafel:
  1. PRAEFIXFREI: kein Code ist der Anfang eines anderen.
  2. KRAFT-UNGLEICHUNG: die Summe der 2^-Laenge ist hoechstens 1.
     Ist sie groesser, kann die Tafel gar nicht praefixfrei sein.

Rueckgabe 0, wenn alles stimmt.
"""
import re, sys

QUELLE = 'kernel/user/h264tab.fi'

def felder(pfad):
    """Die statischen Felder aus der Firn-Datei lesen."""
    s = open(pfad, encoding='utf-8').read()
    out = {}
    for m in re.finditer(r'static mut (\w+): \[u64; (\d+)\] = \[(.*?)\]',
                         s, re.S):
        name, n, body = m.group(1), int(m.group(2)), m.group(3)
        werte = [int(x) for x in re.findall(r'-?\d+', body)]
        if len(werte) != n:
            print("  %s: %d Werte, %d erwartet" % (name, len(werte), n))
            return None
        out[name] = werte
    return out

def pruefe(name, lens, bits):
    codes = [(l, b) for l, b in zip(lens, bits) if l > 0]
    schlecht = 0
    for i in range(len(codes)):
        for j in range(i + 1, len(codes)):
            l1, b1 = codes[i]
            l2, b2 = codes[j]
            if l1 <= l2:
                if (b2 >> (l2 - l1)) == b1: schlecht += 1
            else:
                if (b1 >> (l1 - l2)) == b2: schlecht += 1
    kraft = sum(2.0 ** -l for l, _ in codes)
    return len(codes), schlecht, kraft

def main():
    F = felder(QUELLE)
    if F is None:
        return 1
    tafeln = []
    # coeff_token: vier Klassen zu 68
    for k in range(4):
        tafeln.append(("coeff_token nC-Klasse %d" % k,
                       F['CT_LEN'][k*68:(k+1)*68],
                       F['CT_BITS'][k*68:(k+1)*68]))
    tafeln.append(("chroma_dc_coeff_token", F['CDC_LEN'], F['CDC_BITS']))
    for i in range(15):
        tafeln.append(("total_zeros tz=%d" % (i+1),
                       F['TZ_LEN'][i*16:(i+1)*16],
                       F['TZ_BITS'][i*16:(i+1)*16]))
    for i in range(3):
        tafeln.append(("chromadc_total_zeros %d" % (i+1),
                       F['TZC_LEN'][i*4:(i+1)*4],
                       F['TZC_BITS'][i*4:(i+1)*4]))
    for i in range(7):
        tafeln.append(("run_before zl=%d" % (i+1),
                       F['RUN_LEN'][i*16:(i+1)*16],
                       F['RUN_BITS'][i*16:(i+1)*16]))
    fehler = 0
    ncodes = 0
    for name, lens, bits in tafeln:
        n, schlecht, kraft = pruefe(name, lens, bits)
        ncodes += n
        if schlecht or kraft > 1.0000001:
            fehler += 1
            print("  MEHRDEUTIG %-28s %3d Codes, %d Kollisionen, Kraft %.6f"
                  % (name, n, schlecht, kraft))
    if fehler:
        print("%d von %d Tafeln sind mehrdeutig" % (fehler, len(tafeln)))
        return 1
    print("%d Tafeln, %d Codes, 0 Praefixkollisionen, alle Kraft-Summen <= 1"
          % (len(tafeln), ncodes))
    return 0

if __name__ == '__main__':
    sys.exit(main())
