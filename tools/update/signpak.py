#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/update/signpak.py -- ein Paket signieren, auf dem WIRT.

    signpak.py <geheim.key> <datei.opk> [<datei.opk> ...]

Schreibt neben jede Datei `<datei>.sig`: 64 rohe Oktette, die
Ed25519-Signatur ueber ALLE Oktette der Datei.

WARUM DER WIRT SIGNIERT UND NICHT DAS GERAET: der geheime Schluessel
gehoert auf die Baumaschine und nirgendwo sonst. Das Geraet hat nur den
oeffentlichen (`/system/schluessel.pub`) und kann damit pruefen, aber
nicht unterschreiben. Genau das ist der Sinn der Uebung.

DIE UMSETZUNG IST DIE VON `pkg/opk.py` -- dieselbe Ed25519-Rechnung, die
das Format seit Runde PLAN2 benutzt, damit hier kein zweiter Signierer
entsteht, der leicht anders rechnet. Zusaetzlich wird jede erzeugte
Signatur SOFORT mit einer FREMDEN Umsetzung nachgeprueft (libsodium ueber
pynacl, sonst `cryptography`); eine Signatur, die nur ihr eigener Erzeuger
anerkennt, sagt nichts.
"""
import importlib.util
import os
import sys

OPK = os.environ.get("OPK", "/root/orientos-install/pkg/opk.py")


def load_opk():
    spec = importlib.util.spec_from_file_location("opkpy", OPK)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def fremd(pk, msg, sig):
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
    for pfad in sys.argv[2:]:
        roh = open(pfad, "rb").read()
        sig = m.ed25519_sign(sk, roh)
        with open(pfad + ".sig", "wb") as f:
            f.write(sig)
        eigen = m.ed25519_verify(pk, roh, sig)
        anders = fremd(pk, roh, sig)
        if not eigen or anders is False:
            raise SystemExit("signpak: die eigene Signatur wird nicht "
                             "anerkannt (eigen=%s fremd=%s)" % (eigen, anders))
        print("   signiert  %-40s %d Oktette, %s..."
              % (os.path.basename(pfad), len(roh), sig.hex()[:16]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
