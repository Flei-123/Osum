#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    mkroots.py <out.pem> [<bundle>]
"""
import datetime
import os
import sys

WANTED = [
    "ISRG Root X1",
    "ISRG Root X2",
    "DigiCert Global Root G2",
    "DigiCert Global Root G3",
    "DigiCert TLS RSA4096 Root G5",
    "DigiCert TLS ECC P384 Root G5",
    "USERTrust RSA Certification Authority",
    "SSL.com TLS ECC Root CA 2022",
    "GlobalSign Root R46",
    "Sectigo Public Server Authentication Root R46",
    "Amazon Root CA 1",
    "Microsoft RSA Root Certificate Authority 2017",
    "Microsoft ECC Root Certificate Authority 2017",
    "GTS Root R1",
    "GTS Root R4",
]


HERE = os.path.dirname(os.path.abspath(__file__))
SUBSET = os.path.join(HERE, "..", "roots", "mozilla-subset.pem")
HOST_BUNDLE = "/etc/ssl/certs/ca-certificates.crt"


def default_bundle():
    return SUBSET if os.path.exists(SUBSET) else HOST_BUNDLE


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    out = argv[1]
    bundle = argv[2] if len(argv) > 2 else default_bundle()
    header = argv[3].encode() + b"\n" if len(argv) > 3 else b""
    if not os.path.exists(bundle):
        print("mkroots: no bundle at %s" % bundle, file=sys.stderr)
        return 1

    try:
        from cryptography import x509
        from cryptography.hazmat.primitives import serialization
    except ImportError:
        print("mkroots: python3-cryptography is needed", file=sys.stderr)
        return 1

    blob = open(bundle, "rb").read()
    blocks = []
    start = b"-----BEGIN CERTIFICATE-----"
    end = b"-----END CERTIFICATE-----"
    i = 0
    while True:
        a = blob.find(start, i)
        if a < 0:
            break
        b = blob.find(end, a)
        if b < 0:
            break
        blocks.append(blob[a:b + len(end)] + b"\n")
        i = b + len(end)

    taken = []
    seen = set()
    dropped = []
    now = datetime.datetime.utcnow()
    for pem in blocks:
        try:
            c = x509.load_pem_x509_certificate(pem)
        except Exception:
            continue
        cn = ""
        for at in c.subject:
            if at.oid.dotted_string == "2.5.4.3":
                cn = at.value
        if cn in WANTED and cn not in seen:
            if c.not_valid_after < now or c.not_valid_before > now:
                dropped.append(cn)
                continue
            seen.add(cn)
            taken.append((cn, pem))

    with open(out, "wb") as f:
        f.write(header)
        for cn, pem in taken:
            f.write(b"# " + cn.encode() + b"\n")
            f.write(pem)
    missing = [w for w in WANTED if w not in seen]
    print("mkroots: %d roots -> %s (%d octets)%s%s"
          % (len(taken), out, os.path.getsize(out),
             ", missing: " + ", ".join(missing) if missing else "",
             ", dropped expired: " + ", ".join(dropped) if dropped else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
