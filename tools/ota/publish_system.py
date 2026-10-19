#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/ota/publish_system.py -- turn a built image dir into a signed SYSTEM feed stand.

    python3 tools/ota/publish_system.py <imgdir> <feeddir> <channel> --bund <bundle.json>
        [--count N] [--min-from N] [--notes FILE] [--name TEXT] [--bad-hash] [--bad-sig]

<imgdir> holds the kernel `osum.mb` (and `root.img`, listed but not applied on-device
yet). Output: <feeddir>/system/<channel>/{VERZEICHNIS,VERZEICHNIS.sig,kernel-<N>.mb,
CHANGES-<N>.txt,schluessel.pub}. The VERZEICHNIS is the same signed document format
the package feed uses (OTA2: key chain + signature by the existing bundle), plus

    system   <count> <commit7> <min_from> <name>
    sysfile  <role> <sha256> <octets> <file>          role: kernel | notes | root

Old clients ignore both line types. The channel directory is separate from
`aktuell/` (which veroeffentlichen.py rebuilds), so the live package feed is untouched.
--bad-hash / --bad-sig: negative-control stands (kernel hash wrong / signature broken).
"""
import hashlib, os, re, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import veroeffentlichen as vf  # noqa: E402


def main():
    a = sys.argv[1:]
    if len(a) < 3:
        raise SystemExit(__doc__)
    img, feed, chan = a[0], a[1], a[2]
    opt = {"--bund": None, "--count": None, "--min-from": "0", "--notes": None,
           "--name": ""}
    flags = set()
    i = 3
    while i < len(a):
        if a[i] in opt:
            opt[a[i]] = a[i + 1]
            i += 2
        else:
            flags.add(a[i])
            i += 1
    if chan not in ("stable", "dev", "test"):
        raise SystemExit("channel must be stable|dev|test")
    if not opt["--bund"]:
        raise SystemExit("--bund missing")
    kern = os.path.join(img, "osum.mb")
    data = open(kern, "rb").read()
    m = re.search(rb"osum ([0-9a-f]{7})", data)
    if not m:
        raise SystemExit("no `osum <hash>` string in the kernel (built from git?)")
    commit = m.group(1).decode()
    count = int(opt["--count"] or subprocess.check_output(
        ["git", "-C", HERE, "rev-list", "--count", "HEAD"]).decode())
    out = os.path.join(feed, "system", chan)
    os.makedirs(out, exist_ok=True)
    kname = "kernel-%d.mb" % count
    shutil.copyfile(kern, os.path.join(out, kname))
    khash = hashlib.sha256(data).hexdigest()
    if "--bad-hash" in flags:
        khash = ("0" if khash[0] != "0" else "1") + khash[1:]
    notes = opt["--notes"]
    ntext = open(notes, "rb").read() if notes else (
        ("Build %d (%s)\n" % (count, commit)).encode())
    nname = "CHANGES-%d.txt" % count
    open(os.path.join(out, nname), "wb").write(ntext)
    lines = ["system\t%d\t%s\t%s\t%s" % (count, commit, opt["--min-from"],
                                          opt["--name"] or "OrientOS"),
             "sysfile\tkernel\t%s\t%d\t%s" % (khash, len(data), kname),
             "sysfile\tnotes\t%s\t%d\t%s" % (hashlib.sha256(ntext).hexdigest(),
                                             len(ntext), nname)]
    rimg = os.path.join(img, "root.img")
    if os.path.isfile(rimg):
        lines.append("sysfile\troot\t%s\t%d\t%s" % (vf.sha256d(rimg),
                                                    os.path.getsize(rimg), "root.img"))
    b = vf.bund_lesen(opt["--bund"])
    roh = vf.verzeichnis_text(count, b["haupt"]["gen"], [dict(k) for k in b["kette"]],
                              [], []).decode()
    roh += "\n".join(lines) + "\n"
    vz = os.path.join(out, "VERZEICHNIS")
    open(vz, "wb").write(roh.encode("ascii"))
    vf.signieren(opt["--bund"], vz, os.path.join(out, "VERZEICHNIS.sig"))
    if "--bad-sig" in flags:
        sg = bytearray(open(vz + ".sig", "rb").read())
        sg[0] ^= 1
        open(vz + ".sig", "wb").write(bytes(sg))
    open(os.path.join(out, "schluessel.pub"), "wb").write(bytes.fromhex(b["haupt"]["pub"]))
    print("system stand %d (%s) -> %s  [%s]" % (count, commit, out, chan))


main()
