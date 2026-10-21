#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/iwlfh/ref.py -- blobs + expected kernel lines for tools/iwlfh/run.sh (HP-9b).

usage: python3 -I tools/iwlfh/ref.py gen <dir>
Writes <name>.bin (synthetic family-8000 ucode) and <name>.exp (the five summary lines the kernel
prints after `iwl: fh `) for the cases of tools/wlan/fh8000_ref.py that fit the kernel bring-up
(bounce buffer 0x20000). The expected text comes from the INDEPENDENT Python reference."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'wlan'))
import fh8000_ref as R  # noqa: E402

PICK = {'big': ('c1_big', 0), 'edges': ('cc_edges', 0), 'empty': ('c6_empty', 0), 'lost': ('c1_big', 1)}


def gen(d):
    R.mk()
    for name, (case, mode) in PICK.items():
        secs, bsize, _m, phys = R.CASES[case]
        assert bsize == 0x20000
        blob = R.build(secs)
        open(os.path.join(d, name + '.bin'), 'wb').write(blob)
        lines = [l for l in R.expected(secs, bsize, mode, phys) if l.split(' ')[0] in ('RC', 'STAT', 'LOADSTAT', 'CHICK', 'VIOL')]
        open(os.path.join(d, name + '.exp'), 'w').write('\n'.join(lines) + '\n')


if __name__ == '__main__':
    if len(sys.argv) != 3 or sys.argv[1] != 'gen':
        sys.exit('usage: ref.py gen <dir>')
    gen(sys.argv[2])
