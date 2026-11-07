#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    listing.py <quellverzeichnis> --revision <n> --key <secret.key>
    [--broken <file>]
    revision	<dezimal>
"""
import hashlib
import importlib.util
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import listdoc   # noqa: E402
import plattform as PLT   # noqa: E402

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import opkpfad
OPK = opkpfad.path_2()


def load_opk():
    spec = importlib.util.spec_from_file_location("opkpy", OPK)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def foreign_prueft(pk, msg, sig):
    try:
        from nacl.signing import VerifyKey
        from nacl.exceptions import BadSignatureError
        try:
            VerifyKey(pk).verify(msg, sig)
            return True
        except BadSignatureError:
            return False
    except ImportError:
        pass
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 \
            import Ed25519PublicKey
        from cryptography.exceptions import InvalidSignature
        try:
            Ed25519PublicKey.from_public_bytes(pk).verify(sig, msg)
            return True
        except InvalidSignature:
            return False
    except ImportError:
        return None


def meta_aus_opk(path_2):
    with open(path_2, "rb") as f:
        header = f.read(64)
        if header[:8] != b"OPKG0001":
            raise SystemExit("verzeichnis: %s ist not an OPKG file" % path_2)
        ml = int.from_bytes(header[8:16], "little")
        meta = f.read(ml).decode("utf-8", "replace")
    name = revision = None
    for line in meta.split("\n"):
        if line.startswith("name="):
            name = line[5:].strip()
        elif line.startswith("version="):
            revision = line[8:].strip()
        elif line.startswith("fassung=") and revision is None:
            revision = line[8:].strip()
    if not name:
        raise SystemExit("verzeichnis: %s hat keinen Namen" % path_2)
    return name, revision or "0"


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    source = sys.argv[1]
    revision = None
    key = None
    broken = None
    i = 2
    while i < len(sys.argv):
        a = sys.argv[i]
        if a == "--revision" and i + 1 < len(sys.argv):
            i += 1
            revision = int(sys.argv[i])
        elif a == "--key" and i + 1 < len(sys.argv):
            i += 1
            key = sys.argv[i]
        elif a == "--broken" and i + 1 < len(sys.argv):
            i += 1
            broken = sys.argv[i]
        else:
            raise SystemExit("verzeichnis: unbekanntes Wort %s" % a)
        i += 1
    if revision is None or key is None:
        print(__doc__)
        return 2

    dateien = sorted(f for f in os.listdir(source) if f.endswith(".opk"))
    if not dateien:
        raise SystemExit("verzeichnis: %s hat keine .opk-Datei" % source)

    packages = []
    for d in dateien:
        p = os.path.join(source, d)
        roh = open(p, "rb").read()
        h = hashlib.sha256(roh).hexdigest()
        if broken == d:
            h = ("%x" % (int(h, 16) ^ 1)).rjust(64, "0")
        name, pf = meta_aus_opk(p)
        plattform = PLT.plattform_von_roh(roh, d)
        packages.append((name, pf, h, len(roh), d, plattform))

    m = load_opk()
    sk = open(key, "rb").read()
    pk = m.ed25519_public(sk)
    second_opinion = [True]

    def sign(doc, sig_path):
        roh = open(doc, "rb").read()
        sig = m.ed25519_sign(sk, roh)
        if not m.ed25519_verify(pk, roh, sig):
            raise SystemExit("verzeichnis: die eigene Signatur gilt nicht")
        changed = foreign_prueft(pk, roh, sig)
        if changed is False:
            raise SystemExit("verzeichnis: eine FREMDE Umsetzung erkennt die "
                             "Signatur nicht an")
        if not changed:
            second_opinion[0] = False
        with open(sig_path, "wb") as f:
            f.write(sig)

    written = listdoc.write_signed(source, sign, revision, 0, packages=packages)
    first = next(iter(written.values()))
    size = os.path.getsize(first)
    print("   listing  revision %d, %d Paket(e), %d Oktette, styles %s%s"
          % (revision, len(dateien), size, ",".join(written),
             "" if second_opinion[0] else " (KEINE zweite Meinung verfuegbar)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
