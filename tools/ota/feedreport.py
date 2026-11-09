#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage: feedreport.py <stand-dir> <pubkey-file> [--target PATH]
Verifies the signed listing of one system feed stand (every listing style present, signature
against <pubkey-file>, hash and size of every sysfile/sysgz entry) and prints the files with hashes."""
import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import listdoc
import listing

FILE_ROLES = ("sysfile", "sysgz")


def fail(message):
    raise SystemExit("feedreport: " + message)


def parse_args(argv):
    target = None
    rest = []
    it = iter(argv)
    for arg in it:
        if arg == "--target":
            target = next(it)
        else:
            rest.append(arg)
    if len(rest) != 2:
        raise SystemExit(__doc__)
    return rest[0].rstrip("/"), rest[1], target


def verify_styles(stand, pub):
    opk = listing.load_opk()
    docs = []
    for style in listdoc.STYLES.values():
        text_name, sig_name = style["files"]
        text_path = os.path.join(stand, text_name)
        if not os.path.isfile(text_path):
            continue
        sig_path = os.path.join(stand, sig_name)
        if not os.path.isfile(sig_path):
            fail("signature file missing: " + sig_name)
        text = open(text_path, "rb").read()
        if not opk.ed25519_verify(pub, text, open(sig_path, "rb").read()):
            fail("signature INVALID: " + text_name)
        docs.append(text.decode())
    if not docs:
        fail("no listing in " + stand)
    return docs[0].splitlines()


def check_files(stand, lines):
    rows = []
    for line in lines:
        fields = line.split("\t")
        if fields[0] not in FILE_ROLES:
            continue
        name, want, size = fields[4], fields[2], int(fields[3])
        path = os.path.join(stand, name)
        if not os.path.isfile(path):
            fail("file missing: " + name)
        data = open(path, "rb").read()
        if len(data) != size or hashlib.sha256(data).hexdigest() != want:
            fail("hash or size mismatch: " + name)
        rows.append((fields[0] + ":" + fields[1], want, size, name))
    return rows


def main():
    stand, pub_path, target = parse_args(sys.argv[1:])
    pub = open(pub_path, "rb").read()
    lines = verify_styles(stand, pub)
    rows = check_files(stand, lines)
    head = next((l.split("\t") for l in lines if l.startswith("system\t")), None)
    if head is None:
        fail("listing has no system line")
    print("stand %s commit %s" % (head[1], head[2]))
    for role, digest, size, name in rows:
        print("  %-14s %s %9d %s" % (role, digest, size, name))
    if target:
        print("target %s" % target)
    print("feedreport OK: signature valid, %d files match" % len(rows))


if __name__ == "__main__":
    main()
