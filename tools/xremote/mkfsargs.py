import os
import sys

PROVIDED_DIRS = {"store", "apps", "system"}
EXECUTABLE = {"start", "bin/freeviewer-host", "bin/xremoted", "bin/xremote", "lib/ld-musl-x86_64.so.1"}


def walk(root, top):
    for base, dirs, files in os.walk(os.path.join(root, top)):
        dirs.sort()
        yield os.path.relpath(base, root), sorted(files)


def store_dir(root):
    entries = sorted(os.listdir(os.path.join(root, "store")))
    if len(entries) != 1:
        raise SystemExit("mkfsargs: expected exactly one package in the store, found %d" % len(entries))
    return entries[0]


def emit_tree(root, top, as_link_of=None):
    for rel_dir, files in walk(root, top):
        if rel_dir not in PROVIDED_DIRS:
            print("/%s/" % rel_dir)
        for name in files:
            rel = os.path.join(rel_dir, name)
            inner = os.path.relpath(rel, top)
            if as_link_of:
                print("/%s@/%s" % (rel, os.path.join(as_link_of, inner)))
                continue
            mode = "755" if inner in EXECUTABLE else "644"
            print("/%s=%s@%s" % (rel, os.path.join(root, rel), mode))


def main():
    root = sys.argv[1]
    package = store_dir(root)
    emit_tree(root, os.path.join("store", package))
    emit_tree(root, os.path.join("apps", "xremote.osp"), os.path.join("store", package))
    emit_tree(root, "system")


main()
