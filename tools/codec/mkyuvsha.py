#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import hashlib, sys

path_2, w, h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
big = w * h * 3 // 2
d = open(path_2, 'rb').read()
if len(d) % big:
    print("WARNING: %d octets are not a multiple of %d" % (len(d), big),
          file=sys.stderr)
n = len(d) // big
for i in range(n):
    print("%d %s" % (i, hashlib.sha256(d[i*big:(i+1)*big]).hexdigest()))
