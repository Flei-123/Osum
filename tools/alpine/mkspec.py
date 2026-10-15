#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/alpine/mkspec.py -- turn an Alpine minirootfs tarball into mkfs.py specs.

    python3 -I mkspec.py <rootfs.tar.gz> <extract-dir> <spec-out> [--prefix=/alpine]

Files are extracted into <extract-dir> (regular files only; symlinks are NOT
created on the host, they become `path->target` specs, so a hostile tarball
cannot write outside <extract-dir>). <spec-out> gets one mkfs spec per line,
parents first:

    /alpine/bin/@755                  directory
    /alpine/bin/busybox=<host>@755    file with mode
    /alpine/bin/ls->/bin/busybox      symlink (absolute targets stay absolute)
"""
import os
import sys
import tarfile


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    tarball, out_dir, spec_out = sys.argv[1:4]
    prefix = ""
    for a in sys.argv[4:]:
        if a.startswith("--prefix="):
            prefix = a[len("--prefix="):].rstrip("/")
    os.makedirs(out_dir, exist_ok=True)
    dirs, files, links = [], [], []
    stats = {"file": 0, "dir": 0, "link": 0, "hard": 0, "skip": 0, "bytes": 0}
    with tarfile.open(tarball, "r:*") as tf:
        members = tf.getmembers()
        by_name = {}
        for m in members:
            by_name[os.path.normpath("/" + m.name)] = m
        for m in members:
            name = os.path.normpath("/" + m.name)
            if name == "/":
                continue
            if m.isdir():
                dirs.append((name, m.mode & 0o7777))
                stats["dir"] += 1
            elif m.isreg() or m.islnk():
                src = m
                if m.islnk():
                    src = by_name.get(os.path.normpath("/" + m.linkname))
                    stats["hard"] += 1
                    if src is None or not src.isreg():
                        stats["skip"] += 1
                        continue
                host = os.path.join(out_dir, "f%06d" % len(files))
                data = tf.extractfile(src).read()
                with open(host, "wb") as o:
                    o.write(data)
                stats["bytes"] += len(data)
                stats["file"] += 1
                files.append((name, host, src.mode & 0o7777))
            elif m.issym():
                links.append((name, m.linkname))
                stats["link"] += 1
            else:
                stats["skip"] += 1
    dirs.sort(key=lambda d: (d[0].count("/"), d[0]))
    files.sort(key=lambda d: d[0])
    links.sort(key=lambda d: d[0])
    with open(spec_out, "w") as o:
        if prefix:
            o.write(prefix + "/\n")
        for name, mode in dirs:
            o.write("%s%s/@%o\n" % (prefix, name, mode or 0o755))
        for name, host, mode in files:
            o.write("%s%s=%s@%o\n" % (prefix, name, host, mode or 0o644))
        for name, tgt in links:
            o.write("%s%s->%s\n" % (prefix, name, tgt))
    print("mkspec: %(file)d files (%(bytes)d bytes), %(dir)d dirs, %(link)d symlinks, %(hard)d hardlinks, %(skip)d skipped" % stats)
    return 0


if __name__ == "__main__":
    sys.exit(main())
