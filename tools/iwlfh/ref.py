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


def extra_tlvs():
    api = R.tlv(29, R.u32(1) + R.u32(0x1))
    capa = R.tlv(30, R.u32(0) + R.u32((1 << 2) | (1 << 12)))
    cmdv = R.tlv(48, bytes([0, 0x0D, 7, 7, 0, 0x0C, 2, 2, 0, 0x18, 10, 0, 0, 0x1C, 5, 0, 0, 0x1D, 1, 0]))
    nscan = R.tlv(31, R.u32(52))
    return api + capa + cmdv + nscan


def gen(d):
    R.mk()
    init = [(0x0, R.data(2000, 7)), (R.SEP_CPU, b''), (0x60000, R.data(1000, 9))]
    secs, _b, _m, _p = R.CASES['c1_big']
    open(os.path.join(d, 'two.bin'), 'wb').write(R.build(secs) + b''.join(R.tlv(20, R.u32(a) + dd) for a, dd in init))
    open(os.path.join(d, 'v7.bin'), 'wb').write(R.build(R.CASES['c1_big'][0]) + b''.join(R.tlv(20, R.u32(a) + dd) for a, dd in init) + extra_tlvs())
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
