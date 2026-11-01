#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    signpak.py <secret.key> <file.opk> [<file.opk> ...]
"""
import importlib.util
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import opkpfad  # noqa: E402  -- A-025
OPK = opkpfad.path_2()


def load_opk():
    spec = importlib.util.spec_from_file_location("opkpy", OPK)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def foreign(pk, msg, sig):
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


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    m = load_opk()
    sk = open(sys.argv[1], "rb").read()
    pk = m.ed25519_public(sk)
    for path_2 in sys.argv[2:]:
        roh = open(path_2, "rb").read()
        sig = m.ed25519_sign(sk, roh)
        with open(path_2 + ".sig", "wb") as f:
            f.write(sig)
        own = m.ed25519_verify(pk, roh, sig)
        changed = foreign(pk, roh, sig)
        if not own or changed is False:
            raise SystemExit("signpak: die eigene Signatur wird nicht "
                             "anerkannt (eigen=%s fremd=%s)" % (own, changed))
        print("   signiert  %-40s %d Oktette, %s..."
              % (os.path.basename(path_2), len(roh), sig.hex()[:16]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
