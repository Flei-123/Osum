# SPDX-License-Identifier: GPL-2.0-only
import importlib.util
import os
import struct
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('fh8000_ref', os.path.join(HERE, 'fh8000_ref.py'))
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)

LEGACY_MODE = 32
CASES = {}


def case(name, secs, ncpu=2, bsize=0x20000, mode=0, phys=0x1000):
    CASES[name] = (secs, ncpu, bsize, mode | LEGACY_MODE, phys)


def mk():
    sep, pag, data = base.SEP_CPU, base.SEP_PAGING, base.data
    dual = [(0x0, data(100, 1)), (0x10000, data(5000, 2)), (sep, b''), (0x60000, data(3000, 4)), (0x57000, data(0x3000, 5)), (pag, b''), (0x70000, data(4000, 6))]
    case('d1_dual', dual)
    case('d1_page', dual, bsize=4096, phys=0x300001000)
    case('d2_single', [(0x100, data(300, 1)), (0x5000, data(777, 2))], ncpu=1)
    case('d3_single_with_sep', dual, ncpu=1)
    case('d4_ext', [(0x3FFFF, data(5, 1)), (0x40000, data(5, 2)), (0x57FFF, data(5, 3)), (0x58000, data(5, 4))])
    case('d5_nocpu1', [(sep, b''), (0x2000, data(40, 2))])
    case('d6_empty', [(0x0, data(40, 1)), (sep, b''), (0x2000, data(40, 2)), (0x3000, b'')])
    case('d7_tiny', dual, bsize=100)
    case('d8_lost_irq', dual, mode=1)
    case('da_17', [(0x1000 * i, data(10, i)) for i in range(17)] + [(sep, b''), (0x20000, data(10, 9))])


def gen(d):
    mk()
    for name, (secs, ncpu, bsize, mode, phys) in CASES.items():
        blob = base.build(secs, ncpu)
        open(os.path.join(d, name + '.case'), 'wb').write(struct.pack('<IIQ', bsize, mode, phys) + blob)
        exp = base.expected(secs, bsize, mode & ~LEGACY_MODE, phys, legacy=True, ncpu=ncpu)
        open(os.path.join(d, name + '.exp'), 'w').write('\n'.join(exp) + '\n')


if __name__ == '__main__' and sys.argv[1] == 'gen':
    gen(sys.argv[2])
