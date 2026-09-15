#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/codec/mkyuvsha.py -- die SHA-256 JE BILD aus einer rohen
YUV-4:2:0-Datei, so wie ffmpeg sie schreibt.

Das ist die Wahrheit, gegen die Osum verglichen wird: dieselbe Datei,
dieselbe Reihenfolge (Y, dann U, dann V), dieselbe Pruefsumme.

    python3 tools/codec/mkyuvsha.py DATEI BREITE HOEHE
"""
import hashlib, sys

pfad, w, h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
gross = w * h * 3 // 2
d = open(pfad, 'rb').read()
if len(d) % gross:
    print("WARNUNG: %d Oktette sind kein Vielfaches von %d" % (len(d), gross),
          file=sys.stderr)
n = len(d) // gross
for i in range(n):
    print("%d %s" % (i, hashlib.sha256(d[i*gross:(i+1)*gross]).hexdigest()))
