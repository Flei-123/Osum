#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""straceset.py -- summarise a `strace -f` log of a real Linux run (the reference for what Osum must offer).

  strace -f -qq -o app.strace -s 80 <cmd>
  python3 tools/linuxapps/straceset.py app.strace [--after <exec path substring>] [--files out.txt] [--top N]

Prints: distinct syscalls with counts, clone flags, mmap flag combinations, socket/prctl/ioctl/fcntl/futex variants,
failing calls grouped by (syscall, errno, path) and the list of files opened successfully (for building a minimal image).
"""
import re, sys, collections

LINE = re.compile(r'^(\d+)\s+(\w+)\((.*)\)\s+=\s+(-?\d+|\?)(?:\s+(\w+))?')


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    path = argv[0]
    after = None
    files_out = None
    top = 25
    i = 1
    while i < len(argv):
        if argv[i] == '--after':
            after = argv[i + 1]; i += 2
        elif argv[i] == '--files':
            files_out = argv[i + 1]; i += 2
        elif argv[i] == '--top':
            top = int(argv[i + 1]); i += 2
        else:
            i += 1
    lines = open(path, errors='replace').read().splitlines()
    start = 0
    if after:
        for n, l in enumerate(lines):
            if ' execve(' in l and after in l and '= 0' in l:
                start = n
    calls = collections.Counter()
    clone = collections.Counter()
    mmapf = collections.Counter()
    sock = collections.Counter()
    prctl = collections.Counter()
    ioctl = collections.Counter()
    fcntl = collections.Counter()
    futex = collections.Counter()
    fails = collections.Counter()
    opened = collections.OrderedDict()
    pids = set()
    for l in lines[start:]:
        m = LINE.match(l)
        if not m:
            continue
        pid, name, args, ret, err = m.groups()
        pids.add(pid)
        calls[name] += 1
        if name in ('clone', 'clone3'):
            fl = re.search(r'flags=([A-Z_|]+)', args)
            clone[fl.group(1) if fl else args[:60]] += 1
        elif name in ('mmap', 'mmap2'):
            parts = [p.strip() for p in args.split(',')]
            if len(parts) >= 4:
                mmapf[parts[2] + ' ' + parts[3]] += 1
        elif name == 'socket':
            sock[args] += 1
        elif name == 'prctl':
            prctl[args.split(',')[0]] += 1
        elif name == 'ioctl':
            ioctl[','.join(args.split(',')[:2])] += 1
        elif name == 'fcntl':
            fcntl[','.join(args.split(',')[1:2])] += 1
        elif name == 'futex':
            futex[args.split(',')[1].strip() if ',' in args else args] += 1
        if ret.startswith('-') or ret == '?':
            if err and err.startswith('E'):
                key = (name, err, re.sub(r'\s+', ' ', args)[:90])
                fails[key] += 1
        elif name in ('open', 'openat'):
            q = re.search(r'"([^"]*)"', args)
            if q and q.group(1) not in opened:
                opened[q.group(1)] = 1
    print('processes: %d  syscalls: %d  distinct: %d' % (len(pids), sum(calls.values()), len(calls)))
    print('syscalls:', ' '.join('%s:%d' % kv for kv in calls.most_common()))
    for title, c in (('clone flags', clone), ('mmap prot/flags', mmapf), ('socket', sock), ('prctl', prctl), ('ioctl', ioctl), ('fcntl', fcntl), ('futex ops', futex)):
        if c:
            print('%s:' % title)
            for k, v in c.most_common(top):
                print('  %5d  %s' % (v, k))
    print('failing calls (syscall errno args), top %d:' % top)
    for (name, err, args), v in fails.most_common(top * 2):
        print('  %5d  %-10s %-14s %s' % (v, name, err, args))
    if files_out:
        with open(files_out, 'w') as f:
            for p in opened:
                f.write(p + '\n')
        print('opened files: %d -> %s' % (len(opened), files_out))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
