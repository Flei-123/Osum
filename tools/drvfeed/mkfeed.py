#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import argparse
import hashlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "module"))
sys.path.insert(0, HERE)
from mkomod import ed25519_sign  # noqa: E402
import bundle  # noqa: E402

HEADER = "OSUM-DRIVERS 1\n"
SIG_NAME = "drivers.tsv.sig"
TSV_NAME = "drivers.tsv"


def read_inf(pkgdir):
    fields = {"match": []}
    for line in open(os.path.join(pkgdir, "driver.inf")).read().split("\n"):
        if "=" not in line or line.startswith("#"):
            continue
        key, value = line.split("=", 1)
        if key == "match":
            fields["match"].append(value)
        else:
            fields[key] = value
    return fields


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def clean(text):
    return text.replace("\t", " ").replace("\n", " ")


def build_entry(outdir, pkgdir, title, firmware_paths, tamper_fw):
    inf = read_inf(pkgdir)
    name, version = inf["name"], inf["version"]
    tier = inf.get("tier", "native")
    fw_line = inf.get("fw", "")
    fw_files = []
    if fw_line:
        fw_name, fw_hash = fw_line.split(":")
        path = firmware_paths.get(fw_name)
        if path is None:
            raise SystemExit("mkfeed: no firmware file for %s" % fw_name)
        data = open(path, "rb").read()
        if sha256(data) != fw_hash:
            raise SystemExit("mkfeed: firmware %s does not match the manifest hash" % fw_name)
        fw_files.append((fw_name, data))
    blob = bundle.pack(pkgdir, [])
    bundle_file = "drv-%s-%s.drv" % (name, version)
    open(os.path.join(outdir, bundle_file), "wb").write(blob)
    lines = ["D\t%s\t%s\t%s\t%d\t%s\t%s\t%s\n" % (
        name, version, tier, len(blob), sha256(blob), bundle_file, clean(title or name))]
    for match in inf["match"]:
        lines.append("M\t%s\t%s\n" % (name, match))
    for fw_name, data in fw_files:
        fw_file = "fw-%s" % fw_name
        stored = data[:-1] + bytes([data[-1] ^ 1]) if tamper_fw else data
        open(os.path.join(outdir, fw_file), "wb").write(stored)
        lines.append("W\t%s\t%s\t%d\t%s\t%s\n" % (name, fw_name, len(data), sha256(data), fw_file))
    return lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("outdir")
    ap.add_argument("--seed", required=True, help="raw 32-byte Ed25519 seed of the catalog key")
    ap.add_argument("--pkg", action="append", default=[], help="package dir (driver.inf, .sig, modules)")
    ap.add_argument("--title", action="append", default=[], help="NAME=TITLE")
    ap.add_argument("--fw", action="append", default=[], help="FWNAME=PATH")
    ap.add_argument("--tamper-fw", action="store_true", help="serve a flipped firmware file (gate only)")
    ap.add_argument("--tamper-catalog", action="store_true", help="flip a catalog byte after signing (gate only)")
    args = ap.parse_args()
    os.makedirs(args.outdir, exist_ok=True)
    titles = dict(item.split("=", 1) for item in args.title)
    firmware = dict(item.split("=", 1) for item in args.fw)
    body = HEADER
    for pkgdir in args.pkg:
        name = read_inf(pkgdir)["name"]
        body += "".join(build_entry(args.outdir, pkgdir, titles.get(name, ""), firmware, args.tamper_fw))
    raw = body.encode()
    seed = open(args.seed, "rb").read()
    if len(seed) != 32:
        raise SystemExit("mkfeed: seed must be 32 raw bytes")
    signature = ed25519_sign(seed, raw)
    if args.tamper_catalog:
        raw = raw.replace(b"\tnative\t", b"\tcompat\t", 1)
    open(os.path.join(args.outdir, TSV_NAME), "wb").write(raw)
    open(os.path.join(args.outdir, SIG_NAME), "wb").write(signature)
    print("mkfeed: %d packages" % len(args.pkg))
    return 0


if __name__ == "__main__":
    sys.exit(main())
