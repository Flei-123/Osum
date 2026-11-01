#!/usr/bin/env python3

import re
import sys

FALLBACK = [
    (r'\(\*\(\*v\)\.m\)\.mem', 'mem_p'),
    (r'mem_bound\(v, ([^,]+), ([^)]+)\)', r'mem_ok(\1, \2)'),
    (r'g_ld32\(v, ', 'mem_ld32('),
    (r'g_ld8\(v, ', 'mem_ld8('),
    (r'g_ld64\(v, ', 'mem_ld64('),
    (r'g_st32\(v, ', 'mem_st32('),
    (r'g_st8\(v, ', 'mem_st8('),
    (r'g_st64\(v, ', 'mem_st64('),
    (r'g_st16\(v, ', 'mem_st16('),
    (r'\(\*v\)\.argv_von', 'wasi_argv_von'),
    (r'\(\*v\)\.argc', 'wasi_argc'),
    (r'\(\*v\)\.start', 'wasi_start'),
    (r'\(\*v\)\.spur', 'wasi_spur'),
    (r'iov_ptr\(v, ', 'iov_ptr('),
    (r'iov_len\(v, ', 'iov_len('),
    (r'fn ([a-z_0-9]+)\(v: \*mut VM, ', r'fn \1('),
    (r'fn ([a-z_0-9]+)\(v: \*mut VM\)', r'fn \1()'),
    (r'(?<![\w.])([a-z_][a-z_0-9]*)\(v, ', r'\1('),
]


def ziehen(source):
    lines = open(source).read().split('\n')
    start = next(i for i, l in enumerate(lines) if l.startswith('const E_OK'))
    end = next(i for i, l in enumerate(lines) if l.startswith('fn wasi_rufen'))
    txt = '\n'.join(lines[start:end])
    for pat, rep in FALLBACK:
        txt = re.sub(pat, rep, txt)
    if '(*v)' in txt or '*mut VM' in txt:
        rest = [l for l in txt.split('\n') if '(*v)' in l or '*mut VM' in l]
        raise SystemExit('nicht ersetzte VM-Zugriffe:\n  ' + '\n  '.join(rest))
    uebrig = sorted(set(re.findall(r'(?<![\w.])([a-z_][a-z_0-9]*)\(v[,)]', txt)))
    if uebrig:
        raise SystemExit('Rufe mit VM-Argument nicht ersetzt: '
                         + ', '.join(uebrig))
    return txt


if __name__ == '__main__':
    sys.stdout.write(ziehen(sys.argv[1]))
