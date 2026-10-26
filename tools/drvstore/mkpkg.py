#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import argparse
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODDIR = os.path.join(HERE, "..", "module")
sys.path.insert(0, MODDIR)
from mkomod import ed25519_sign  # noqa: E402

SEED_PATH = os.path.join(MODDIR, "pruef.seed")
PUB_PATH = os.path.join(MODDIR, "pruef.pub")
MAX_INF = 1536
MAX_MATCH = 8
KEYS = ("name", "version", "abi", "rank", "module", "rights", "fw", "slot", "match")
RIGHTS = ("pci-cfg", "mmio", "irq", "dma", "fw", "usb", "acpi", "mouse-slot")
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,22}$")
MOD_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,30}$")
HEX = r"[0-9A-Fa-f]"
MATCH_RES = (
    re.compile(r"^pci %s{4}:%s{4}(:%s{4}:%s{4})?$" % (HEX, HEX, HEX, HEX)),
    re.compile(r"^pciclass %s{4}(:%s{2})?$" % (HEX, HEX)),
    re.compile(r"^usb %s{4}:%s{4}$" % (HEX, HEX)),
    re.compile(r"^acpi [A-Z0-9]{3,8}$"),
)


def lint(text):
    errors = []
    seen = {}
    matches = 0
    if len(text.encode()) > MAX_INF:
        errors.append("manifest larger than %d bytes" % MAX_INF)
    for no, line in enumerate(text.split("\n"), 1):
        if line == "" or line.startswith("#"):
            continue
        if "=" not in line:
            errors.append("line %d: no key=value" % no)
            continue
        key, value = line.split("=", 1)
        if key not in KEYS:
            errors.append("line %d: unknown key %s" % (no, key))
            continue
        if key == "match":
            matches += 1
            if not any(r.match(value) for r in MATCH_RES):
                errors.append("line %d: bad match %s" % (no, value))
            continue
        if key in seen:
            errors.append("line %d: duplicate key %s" % (no, key))
        seen[key] = value
        if key == "name" and not NAME_RE.match(value):
            errors.append("line %d: bad name" % no)
        if key in ("version", "abi", "rank") and not value.isdigit():
            errors.append("line %d: %s is not a decimal number" % (no, key))
        if key == "rank" and value.isdigit() and int(value) > 255:
            errors.append("line %d: rank above 255" % no)
        if key == "module" and not MOD_RE.match(value):
            errors.append("line %d: bad module file name" % no)
        if key == "rights":
            for r in value.split(","):
                if r not in RIGHTS:
                    errors.append("line %d: unknown right %s" % (no, r))
        if key == "fw" and not re.match(r"^[A-Za-z0-9._-]{1,31}:[0-9a-f]{64}$", value):
            errors.append("line %d: bad fw (name:sha256hex)" % no)
        if key == "slot" and value not in ("mouse", "aux"):
            errors.append("line %d: unknown slot %s" % (no, value))
    for need in ("name", "version", "abi", "module"):
        if need not in seen:
            errors.append("missing key %s" % need)
    if matches == 0:
        errors.append("no match line")
    if matches > MAX_MATCH:
        errors.append("more than %d match lines" % MAX_MATCH)
    return errors


def build(args):
    lines = [
        "name=%s" % args.name,
        "version=%d" % args.version,
        "abi=%d" % args.abi,
        "rank=%d" % args.rank,
        "module=%s" % os.path.basename(args.module),
    ]
    if args.rights:
        lines.append("rights=%s" % args.rights)
    if args.fw:
        lines.append("fw=%s" % args.fw)
    if args.slot:
        lines.append("slot=%s" % args.slot)
    for m in args.match:
        lines.append("match=%s" % m)
    if args.garbage:
        lines.append("this line is not valid")
    text = "\n".join(lines) + "\n"
    if not args.garbage:
        errors = lint(text)
        if errors:
            sys.exit("mkpkg: " + "; ".join(errors))
    data = text.encode()
    with open(args.seed, "rb") as f:
        seed = f.read()
    sig = ed25519_sign(seed, data)
    if args.bad_sig:
        sig = bytes([sig[0] ^ 1]) + sig[1:]
    if args.tamper:
        data = data.replace(b"rank=%d" % args.rank, b"rank=%d" % ((args.rank + 1) % 256), 1)
    pkg = os.path.join(args.outdir, args.dirname or args.name)
    os.makedirs(pkg, exist_ok=True)
    with open(os.path.join(pkg, "driver.inf"), "wb") as f:
        f.write(data)
    with open(os.path.join(pkg, "driver.inf.sig"), "wb") as f:
        f.write(sig)
    if not args.no_module:
        shutil.copyfile(args.module, os.path.join(pkg, os.path.basename(args.module)))
    print(pkg)


def check(args):
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    from cryptography.exceptions import InvalidSignature
    inf = os.path.join(args.pkgdir, "driver.inf")
    with open(inf, "rb") as f:
        data = f.read()
    with open(inf + ".sig", "rb") as f:
        sig = f.read()
    with open(PUB_PATH, "rb") as f:
        pub = Ed25519PublicKey.from_public_bytes(f.read())
    text = data.decode(errors="replace")
    problems = lint(text)
    try:
        pub.verify(sig, data)
    except InvalidSignature:
        problems.append("signature invalid")
    modname = None
    for line in text.split("\n"):
        if line.startswith("module="):
            modname = line[7:]
    if modname and not os.path.exists(os.path.join(args.pkgdir, modname)):
        problems.append("module file %s missing" % modname)
    if problems:
        print("INVALID: " + "; ".join(problems))
        return 1
    print("OK")
    return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("outdir")
    b.add_argument("--name", required=True)
    b.add_argument("--dirname")
    b.add_argument("--version", type=int, default=1)
    b.add_argument("--abi", type=int, default=1)
    b.add_argument("--rank", type=int, default=10)
    b.add_argument("--module", required=True)
    b.add_argument("--rights", default="")
    b.add_argument("--fw", default="")
    b.add_argument("--slot", default="")
    b.add_argument("--match", action="append", default=[])
    b.add_argument("--seed", default=SEED_PATH)
    b.add_argument("--bad-sig", action="store_true")
    b.add_argument("--tamper", action="store_true")
    b.add_argument("--garbage", action="store_true")
    b.add_argument("--no-module", action="store_true")
    c = sub.add_parser("check")
    c.add_argument("pkgdir")
    args = ap.parse_args()
    if args.cmd == "build":
        build(args)
        return 0
    return check(args)


if __name__ == "__main__":
    sys.exit(main())
