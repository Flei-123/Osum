#!/usr/bin/env python3
import os
import re
import sys

ALIAS = re.compile(r'^const ([A-Za-z0-9_]+): ([a-z0-9]+) = ([a-z0-9_]+)\.([A-Za-z0-9_]+)\s*$')
LITERAL = re.compile(r'^const ([A-Za-z0-9_]+): [a-z0-9]+ = (0x[0-9A-Fa-f]+|[0-9]+)\s*$')


def read_lines(path):
    with open(path, encoding='latin1') as f:
        return f.read().split('\n')


def literals(path):
    table = {}
    for line in read_lines(path):
        m = LITERAL.match(line)
        if m:
            table[m.group(1)] = m.group(2)
    return table


INDEX_DIRS = ('', 'fui', 'hostui', 'uitheme', 'osa', 'std', 'font')


def build_index(bau):
    index = {}
    for sub in INDEX_DIRS:
        base = os.path.join(bau, sub)
        if os.path.isdir(base):
            for name in sorted(os.listdir(base)):
                if name.endswith('.fi'):
                    index.setdefault(name[:-3], os.path.join(base, name))
    return index


def find_module(index, mod):
    return index.get(mod)


def inline_file(path, cache, index):
    lines = read_lines(path)
    changed = 0
    for i, line in enumerate(lines):
        m = ALIAS.match(line)
        if not m:
            continue
        name, ty, mod, target = m.groups()
        src = find_module(index, mod)
        if src is None:
            continue
        if mod not in cache:
            cache[mod] = literals(src)
        value = cache[mod].get(target)
        if value is not None:
            lines[i] = 'const %s: %s = %s' % (name, ty, value)
            changed += 1
    if changed:
        if os.path.islink(path):
            os.unlink(path)
        with open(path, 'w', encoding='latin1') as f:
            f.write('\n'.join(lines))
    return changed


def main():
    bau = sys.argv[1]
    total = 0
    while True:
        cache = {}
        index = build_index(bau)
        changed = 0
        for rel in sys.argv[2:]:
            changed += inline_file(os.path.join(bau, rel), cache, index)
        total += changed
        if not changed:
            break
    print('inlineconsts: %d aliases replaced' % total)


if __name__ == '__main__':
    main()
