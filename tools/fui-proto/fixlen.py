#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
import re
import sys

PAT = re.compile(r'(\[u8;\s*)(\d+)(\s*\]\s*=\s*")((?:[^"\\]|\\.)*)(")')


def blen(s: str) -> int:
    out = []
    i = 0
    while i < len(s):
        if s[i] == '\\' and i + 1 < len(s):
            c = s[i + 1]
            if c == 'n':
                out.append('\n')
            elif c == 't':
                out.append('\t')
            elif c == 'r':
                out.append('\r')
            elif c == '0':
                out.append('\0')
            elif c == '\\':
                out.append('\\')
            elif c == '"':
                out.append('"')
            else:
                out.append(c)
            i += 2
        else:
            out.append(s[i])
            i += 1
    return len(''.join(out).encode('utf-8'))


def fix(path: str) -> int:
    src = open(path, encoding='utf-8').read()
    n = [0]

    def repl(m):
        want = blen(m.group(4))
        if int(m.group(2)) != want:
            n[0] += 1
        return f'{m.group(1)}{want}{m.group(3)}{m.group(4)}{m.group(5)}'

    out = PAT.sub(repl, src)
    if out != src:
        open(path, 'w', encoding='utf-8').write(out)
    return n[0]


if __name__ == '__main__':
    total = 0
    for p in sys.argv[1:]:
        c = fix(p)
        total += c
        if c:
            print(f'{p}: {c} length(s) corrected')
    print(f'{total} corrected')
