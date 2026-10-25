#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/hwnet/mkroots.py -- the trust store that goes into the image.

    mkroots.py <out.pem> [<bundle>]

WHERE THE CERTIFICATES COME FROM, and this is the question a system that
speaks HTTPS has to be able to answer:

  They are taken out of `tools/roots/mozilla-subset.pem`, a NAMED SUBSET
  of Mozilla's CA list (NSS `certdata.txt`, MPL-2.0) cut from the bundle
  that curl.se publishes. `tools/roots/refresh.sh` renews it and pins the
  SHA-256 of the bundle it came from in `tools/roots/bundle.sha256`. The
  host's `/etc/ssl/certs/ca-certificates.crt` is only the fallback when
  the subset file is missing. They are DATA and not code. A root whose
  notAfter has passed is NEVER copied into an image (Baltimore CyberTrust
  Root ended 12.05.2025 and still sat in the store on the first HP stick).

WHY A SUBSET AND NOT ALL 142. A process on Osum has 448 KiB of heap
(`kernel/sys/sys.fi`: BRK_BASE 0x40080000, MMAP_TOP 0x400F0000). The full
bundle is 200 KiB of PEM and about 150 KiB of DER after decoding, and
`x509.Store` holds every root in memory at once -- the store alone would
be most of the heap before the handshake starts. A store of eight roots
is 12 KiB and reaches the certificate authorities that actually sign the
public web today.

THE LIST, and what each one is for:

  ISRG Root X1, ISRG Root X2      Let's Encrypt -- most of the web
  DigiCert Global Root G2/G3, TLS RSA4096/ECC P384 Root G5
                                  what most large sites chain to today
  USERTrust RSA                   Sectigo (old chains)
  Sectigo Public Server Authentication Root R46, GlobalSign Root R46
                                  the current roots of those two
  SSL.com TLS ECC Root CA 2022    what example.com chained to (Cloudflare)
  Amazon Root CA 1                AWS endpoints
  Microsoft RSA/ECC Root 2017     Azure and Microsoft services
  GTS Root R1, GTS Root R4        Google Trust Services

Roots that Mozilla no longer lists (DigiCert Global Root CA, GlobalSign
Root CA, AAA Certificate Services) or that have expired (Baltimore) are
not in the list on purpose.

WHAT THIS IS NOT: an update path. The store is baked into the image, and
a root that is withdrawn stays in it until the next image. That is
written down in docs/ROADMAP-UPDATE.md as its own open point, because a
trust store nobody can update is a trust store that gets worse every
month.
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

    # The bundle is PEM blocks; Debian writes no subject lines into it, so
    # the name has to come out of the certificate itself.
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
