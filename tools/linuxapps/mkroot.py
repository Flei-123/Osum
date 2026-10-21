#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""mkroot.py -- turn a directory root filesystem (e.g. an Alpine root with `apk add firefox`) into a mkfs.py spec.

    python3 -I mkroot.py <rootdir> <spec-out> [--files list.txt]... [--tree /usr/lib/firefox]... [--base]
                         [--skip /usr/lib/firefox/libgkcodecs.so]... [--probe /etc/probe.sh=host.sh]...

  --base   take /bin /sbin /etc /usr/bin /usr/sbin /lib (without /lib/apk) completely, plus the base directories
  --files  a list of absolute guest paths (e.g. from `straceset.py --files`); each existing path is taken with its
           symlink chain (link kept as `path->target`, the real file is taken too)
  --tree   take a whole directory tree
  --skip   leave this path out
Output: one spec per line, parents first: `/dir/@755`, `/f=<host>@mode`, `/l->target`. Hostile paths are not followed
outside <rootdir>. Prints a size summary.
"""
import os
import sys


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    root = os.path.realpath(argv[0])
    out = argv[1]
    lists, trees, skips, extra = [], [], set(), []
    base = False
    i = 2
    while i < len(argv):
        a = argv[i]
        if a == '--files':
            lists.append(argv[i + 1]); i += 2
        elif a == '--tree':
            trees.append(argv[i + 1]); i += 2
        elif a == '--skip':
            skips.add(os.path.normpath(argv[i + 1])); i += 2
        elif a == '--probe':
            extra.append(argv[i + 1]); i += 2
        elif a == '--base':
            base = True; i += 1
        else:
            i += 1
    want = {}

    def host(p):
        return os.path.join(root, p.lstrip('/'))

    def add(p, depth=0):
        p = os.path.normpath(p)
        if p == '/' or p in want or p in skips or depth > 12:
            return
        h = host(p)
        if not os.path.lexists(h):
            return
        # a path whose parent chain contains a symlink is resolved through the parent first
        par = os.path.dirname(p)
        if os.path.islink(host(par)):
            real = os.path.realpath(host(par))
            if real.startswith(root + '/'):
                add(os.path.join(real[len(root):], os.path.basename(p)), depth + 1)
            return
        if par != '/':
            add(par, depth + 1)
        if os.path.islink(h):
            t = os.readlink(h)
            want[p] = ('l', t)
            tp = t if t.startswith('/') else os.path.join(os.path.dirname(p), t)
            add(tp, depth + 1)
        elif os.path.isdir(h):
            want[p] = ('d', None)
        elif os.path.isfile(h):
            want[p] = ('f', h)

    def add_tree(p):
        add(p)
        h = host(p)
        if os.path.isdir(h) and not os.path.islink(h):
            for dp, dn, fn in os.walk(h):
                rel = '/' + os.path.relpath(dp, root)
                for n in sorted(dn) + sorted(fn):
                    add(os.path.join(rel, n))

    if base:
        for d in ('/bin', '/sbin', '/etc', '/usr/bin', '/usr/sbin', '/lib', '/root', '/var', '/tmp', '/proc', '/sys', '/run', '/dev', '/w', '/usr/lib', '/usr/share'):
            add(d)
        for d in ('/bin', '/sbin', '/etc', '/usr/bin', '/usr/sbin'):
            add_tree(d)
        for n in sorted(os.listdir(host('/lib'))):
            if n != 'apk':
                add_tree('/lib/' + n)
    for t in trees:
        add_tree(t)
    for lf in lists:
        for l in open(lf, errors='replace'):
            l = l.strip()
            if l.startswith('/') and not l.startswith(('/proc', '/dev', '/sys')):
                add(l)
    dirs = sorted(p for p, (k, _) in want.items() if k == 'd')
    # directories that only exist because /proc /dev /sys /run /tmp /w are mount points / scratch
    for d in ('/proc', '/dev', '/sys', '/run', '/tmp', '/w', '/var/log', '/root'):
        if d not in want:
            dirs.append(d)
    dirs = sorted(set(dirs), key=lambda p: (p.count('/'), p))
    total = 0
    nfile = nlink = 0
    with open(out, 'w') as f:
        for d in dirs:
            f.write(d.rstrip('/') + '/@755\n')
        for p in sorted(want):
            k, v = want[p]
            if k == 'f':
                st = os.stat(v)
                mode = st.st_mode & 0o777
                f.write('%s=%s@%o\n' % (p, v, mode if mode else 0o644))
                total += st.st_size
                nfile += 1
            elif k == 'l':
                f.write('%s->%s\n' % (p, v))
                nlink += 1
        for e in extra:
            g, h = e.split('=', 1)
            f.write('%s=%s@755\n' % (g, h))
    print('mkroot: %d dirs, %d files (%.1f MiB), %d symlinks -> %s' % (len(dirs), nfile, total / 1048576.0, nlink, out))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
