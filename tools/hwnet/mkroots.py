#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/hwnet/mkroots.py -- the trust store that goes into the image.

    mkroots.py <out.pem> [<bundle>]

WHERE THE CERTIFICATES COME FROM, and this is the question a system that
speaks HTTPS has to be able to answer:

  They are taken out of the host's `/etc/ssl/certs/ca-certificates.crt`,
  which Debian builds from Mozilla's CA list (the `ca-certificates`
  package, source `certdata.txt` from NSS, MPL-2.0). They are DATA and
  not code; this file copies a NAMED SUBSET of them and writes down
  which ones and why.

WHY A SUBSET AND NOT ALL 142. A process on Osum has 448 KiB of heap
(`kernel/sys.fi`: BRK_BASE 0x40080000, MMAP_TOP 0x400F0000). The full
bundle is 200 KiB of PEM and about 150 KiB of DER after decoding, and
`x509.Store` holds every root in memory at once -- the store alone would
be most of the heap before the handshake starts. A store of eight roots
is 12 KiB and reaches the certificate authorities that actually sign the
public web today.

THE LIST, and what each one is for:

  ISRG Root X1, ISRG Root X2      Let's Encrypt -- most of the web
  DigiCert Global Root CA/G2/G3   what most large sites still chain to
  Baltimore CyberTrust Root       Microsoft/Azure services
  USERTrust RSA Certification Authority   Sectigo
  GlobalSign Root CA              older but still very widely used
  SSL.com TLS ECC Root CA 2022    what example.com chained to when this
                                  round was measured (Cloudflare)
  AAA Certificate Services        the cross-signer of that root
  GTS Root R1, GTS Root R4        Google Trust Services

WHAT THIS IS NOT: an update path. The store is baked into the image, and
a root that is withdrawn stays in it until the next image. That is
written down in docs/ROADMAP-UPDATE.md as its own open point, because a
trust store nobody can update is a trust store that gets worse every
month.
"""
import os
import sys

WANTED = [
    "ISRG Root X1",
    "ISRG Root X2",
    "DigiCert Global Root CA",
    "DigiCert Global Root G2",
    "DigiCert Global Root G3",
    "Baltimore CyberTrust Root",
    "USERTrust RSA Certification Authority",
    "GlobalSign Root CA",
    # Cloudflare's chain for example.com ends here (measured with
    # `openssl s_client`, 28.08.2026): SSL.com TLS ECC Root CA 2022,
    # cross-signed by Comodo's AAA Certificate Services.
    "SSL.com TLS ECC Root CA 2022",
    "AAA Certificate Services",
    # Google Trust Services, which signs a large part of the rest.
    "GTS Root R1",
    "GTS Root R4",
]


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    out = argv[1]
    bundle = argv[2] if len(argv) > 2 else "/etc/ssl/certs/ca-certificates.crt"
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
            seen.add(cn)
            taken.append((cn, pem))

    with open(out, "wb") as f:
        for cn, pem in taken:
            f.write(b"# " + cn.encode() + b"\n")
            f.write(pem)
    missing = [w for w in WANTED if w not in seen]
    print("mkroots: %d roots -> %s (%d octets)%s"
          % (len(taken), out, os.path.getsize(out),
             ", missing: " + ", ".join(missing) if missing else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
