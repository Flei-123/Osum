#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import hashlib, sys

pfad, w, h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
gross = w * h * 3 // 2
d = open(pfad, 'rb').read()
if len(d) % gross:
    print("WARNING: %d octets are not a multiple of %d" % (len(d), gross),
          file=sys.stderr)
n = len(d) // gross
for i in range(n):
    print("%d %s" % (i, hashlib.sha256(d[i*gross:(i+1)*gross]).hexdigest()))
