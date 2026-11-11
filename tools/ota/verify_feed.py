#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage: verify_feed.py <feed-base-url> [channel] [--count N]
Fetches system/<channel>/VERZEICHNIS(.sig) and aktuell/schluessel.pub from the base URL (https:// or file://),
checks the Ed25519 signature and the hash and size of every sysfile/sysgz entry. --count N also demands that stand."""
import hashlib
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import listing

FETCH_TIMEOUT_SECONDS = 120


def fetch(url):
    with urllib.request.urlopen(url, timeout=FETCH_TIMEOUT_SECONDS) as response:
        return response.read()


def parse_args(argv):
    expected = None
    rest = []
    it = iter(argv)
    for arg in it:
        if arg == "--count":
            expected = int(next(it))
        else:
            rest.append(arg)
    if not rest:
        raise SystemExit(__doc__)
    return rest[0].rstrip("/"), (rest[1] if len(rest) > 1 else "dev"), expected


def main():
    base, channel, expected = parse_args(sys.argv[1:])
    root = base + "/system/" + channel
    doc = fetch(root + "/VERZEICHNIS")
    sig = fetch(root + "/VERZEICHNIS.sig")
    pub = fetch(base + "/aktuell/schluessel.pub")
    if not listing.load_opk().ed25519_verify(pub, doc, sig):
        raise SystemExit("verify_feed: signature INVALID")
    lines = doc.decode().splitlines()
    stand = int(next(l.split("\t")[1] for l in lines if l.startswith("system\t")))
    if expected is not None and stand != expected:
        raise SystemExit("verify_feed: stand %d, expected %d" % (stand, expected))
    checked = 0
    for line in lines:
        f = line.split("\t")
        if f[0] not in ("sysfile", "sysgz"):
            continue
        data = fetch(root + "/" + f[4])
        if len(data) != int(f[3]) or hashlib.sha256(data).hexdigest() != f[2]:
            raise SystemExit("verify_feed: hash or size mismatch: " + f[4])
        checked += 1
    print("verify_feed OK: stand %d, signature valid, %d files match (%s)" % (stand, checked, root))


if __name__ == "__main__":
    main()
