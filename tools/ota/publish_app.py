#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Add or replace ONE system app revision in an existing signed system feed stand.

    python3 tools/ota/publish_app.py <feeddir> <channel> --name NAME --elf FILE --rev N
        (--bund BUNDLE.json | --key SECRET.key) [--abi N] [--probe] [--bad-hash] [--bad-sig]

The kernel, the stand count and every other line of the live list stay untouched. The device
reads `sysapp <name> <rev> <abi> <sha256> <octets> <file> <probe>` lines independently of the count.
"""
import argparse
import gzip
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import listdoc  # noqa: E402
import publish as vf  # noqa: E402
from publish_system import check_list_size  # noqa: E402

KEPT_KINDS = ("system", "sysfile", "sysgz", "syslink", "sysapp")
NAME_OK = re.compile(r"[A-Za-z0-9_-][A-Za-z0-9._-]{0,59}")


def read_list(path):
    rows = open(path, "rb").read().decode("ascii").splitlines()
    revision = int(rows[1].split("\t")[1])
    kept = [r for r in rows[3:] if r.split("\t")[0] in KEPT_KINDS]
    return revision, None, kept


def drop_app(rows, name):
    out = []
    for row in rows:
        f = row.split("\t")
        if f[0] in ("sysapp", "sysgz") and f[1] == name:
            continue
        if f[0] == "sysfile" and f[1] == "file" and f[-1] == name:
            continue
        out.append(row)
    return out


def make_signer(args):
    if args.key:
        import listing
        m = listing.load_opk()
        sk = open(args.key, "rb").read()
        pub = m.ed25519_public(sk)

        def sign(doc, sig_path):
            raw = open(doc, "rb").read()
            open(sig_path, "wb").write(m.ed25519_sign(sk, raw))
        return sign, pub, 0, []
    b = vf.bund_read(args.bund)

    def sign(doc, sig_path):
        vf.signieren(args.bund, doc, sig_path)
    return sign, bytes.fromhex(b["haupt"]["pub"]), b["haupt"]["gen"], [dict(k) for k in b["kette"]]


def flip_first_nibble(hexdigest):
    return ("0" if hexdigest[0] != "0" else "1") + hexdigest[1:]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("feed")
    ap.add_argument("channel")
    ap.add_argument("--name", required=True)
    ap.add_argument("--elf", required=True)
    ap.add_argument("--rev", type=int, required=True)
    ap.add_argument("--abi", type=int, default=1)
    ap.add_argument("--probe", action="store_true")
    ap.add_argument("--bund")
    ap.add_argument("--key")
    ap.add_argument("--bad-hash", action="store_true")
    ap.add_argument("--bad-sig", action="store_true")
    args = ap.parse_args()
    if not NAME_OK.fullmatch(args.name):
        raise SystemExit("app name not allowed: %r" % args.name)
    if not args.bund and not args.key:
        raise SystemExit("--bund or --key missing")
    out = os.path.join(args.feed, "system", args.channel)
    text_name, sig_name = listdoc.STYLES["legacy"]["files"]
    revision, _, rows = read_list(os.path.join(out, text_name))
    raw = open(args.elf, "rb").read()
    if not raw:
        raise SystemExit("app file is empty")
    srv = "a%d-%s" % (args.rev, args.name)
    gz = gzip.compress(raw, 9, mtime=0)
    open(os.path.join(out, srv), "wb").write(raw)
    open(os.path.join(out, srv + ".gz"), "wb").write(gz)
    digest = hashlib.sha256(raw).hexdigest()
    if args.bad_hash:
        digest = flip_first_nibble(digest)
    rows = drop_app(rows, args.name)
    rows.append("sysapp\t%s\t%d\t%d\t%s\t%d\t%s\t%s" % (
        args.name, args.rev, args.abi, digest, len(raw), srv, "1" if args.probe else "-"))
    rows.append("sysgz\t%s\t%s\t%d\t%s.gz" % (args.name, hashlib.sha256(gz).hexdigest(), len(gz), srv))
    sign, pub, key_gen, chain = make_signer(args)
    stage = os.path.join(out, ".stage-%d" % os.getpid())
    os.makedirs(stage)
    written = listdoc.write_signed(stage, sign, revision, key_gen, chain=chain, extra_lines=rows)
    for path in written.values():
        check_list_size(path)
    if args.bad_sig:
        for style in listdoc.active_styles():
            sig_path = os.path.join(stage, listdoc.STYLES[style]["files"][1])
            sg = bytearray(open(sig_path, "rb").read())
            sg[0] ^= 1
            open(sig_path, "wb").write(bytes(sg))
    for style in listdoc.active_styles():
        for name in listdoc.STYLES[style]["files"]:
            os.replace(os.path.join(stage, name), os.path.join(out, name))
    os.rmdir(stage)
    print("sysapp %s rev %d abi %d (%d octets, gz %d) -> %s" % (args.name, args.rev, args.abi, len(raw), len(gz), out))


if __name__ == "__main__":
    main()
