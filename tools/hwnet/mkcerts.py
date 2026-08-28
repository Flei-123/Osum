#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/hwnet/mkcerts.py -- the certificates round HWNET is measured with.

    mkcerts.py <dir> [<name>]

Writes into <dir>, with Python's `cryptography` (which is NOT this
repository -- that is the point: the certificates the client is held
against were not made by the same code that checks them):

    ca.pem        a root, 4096-bit RSA, valid for a year
    good.pem      a server certificate for <name> (default osum.test),
                  signed by that root, with SAN dNSName AND iPAddress
                  10.9.0.1, valid now
    good.key
    expired.pem   the same, but notAfter is in the past
    expired.key
    other-ca.pem  a SECOND root that is NOT in the trust store
    rogue.pem     a certificate for the same name, signed by that second
                  root -- the "unknown issuer" case
    rogue.key
    wrong.pem     a certificate for a DIFFERENT name (other.test),
                  signed by the good root -- the "wrong name" case
    wrong.key

Every one of the four is a case `/bin/fetch` has to answer differently,
and three of the four have to be REFUSED. A TLS client that accepts
everything is worse than no TLS at all, so the refusals are the
measurement and the success is only the control.
"""
import datetime
import os
import sys

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

NOW = datetime.datetime.utcnow()


def key(bits=2048):
    return rsa.generate_private_key(public_exponent=65537, key_size=bits)


def name(cn):
    return x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, cn)])


def make_ca(cn):
    k = key(2048)
    n = name(cn)
    c = (x509.CertificateBuilder()
         .subject_name(n).issuer_name(n).public_key(k.public_key())
         .serial_number(x509.random_serial_number())
         .not_valid_before(NOW - datetime.timedelta(days=1))
         .not_valid_after(NOW + datetime.timedelta(days=365))
         .add_extension(x509.BasicConstraints(ca=True, path_length=None),
                        critical=True)
         .sign(k, hashes.SHA256()))
    return k, c


def make_leaf(ca_key, ca_cert, cn, san_names, not_before, not_after):
    k = key(2048)
    alt = [x509.DNSName(s) for s in san_names]
    import ipaddress
    alt.append(x509.IPAddress(ipaddress.ip_address("10.9.0.1")))
    c = (x509.CertificateBuilder()
         .subject_name(name(cn)).issuer_name(ca_cert.subject)
         .public_key(k.public_key())
         .serial_number(x509.random_serial_number())
         .not_valid_before(not_before).not_valid_after(not_after)
         .add_extension(x509.SubjectAlternativeName(alt), critical=False)
         .add_extension(x509.BasicConstraints(ca=False, path_length=None),
                        critical=True)
         .sign(ca_key, hashes.SHA256()))
    return k, c


def write(path, blob):
    with open(path, "wb") as f:
        f.write(blob)


def pem(c):
    return c.public_bytes(serialization.Encoding.PEM)


def pem_key(k):
    return k.private_bytes(serialization.Encoding.PEM,
                           serialization.PrivateFormat.TraditionalOpenSSL,
                           serialization.NoEncryption())


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    d = argv[1]
    cn = argv[2] if len(argv) > 2 else "osum.test"
    os.makedirs(d, exist_ok=True)

    ca_key, ca = make_ca("HWNET Test Root")
    write(os.path.join(d, "ca.pem"), pem(ca))

    k, c = make_leaf(ca_key, ca, cn, [cn],
                     NOW - datetime.timedelta(days=1),
                     NOW + datetime.timedelta(days=30))
    write(os.path.join(d, "good.pem"), pem(c) + pem(ca))
    write(os.path.join(d, "good.key"), pem_key(k))

    k, c = make_leaf(ca_key, ca, cn, [cn],
                     NOW - datetime.timedelta(days=40),
                     NOW - datetime.timedelta(days=10))
    write(os.path.join(d, "expired.pem"), pem(c) + pem(ca))
    write(os.path.join(d, "expired.key"), pem_key(k))

    k, c = make_leaf(ca_key, ca, "other.test", ["other.test"],
                     NOW - datetime.timedelta(days=1),
                     NOW + datetime.timedelta(days=30))
    write(os.path.join(d, "wrong.pem"), pem(c) + pem(ca))
    write(os.path.join(d, "wrong.key"), pem_key(k))

    o_key, o_ca = make_ca("HWNET Rogue Root")
    write(os.path.join(d, "other-ca.pem"), pem(o_ca))
    k, c = make_leaf(o_key, o_ca, cn, [cn],
                     NOW - datetime.timedelta(days=1),
                     NOW + datetime.timedelta(days=30))
    write(os.path.join(d, "rogue.pem"), pem(c) + pem(o_ca))
    write(os.path.join(d, "rogue.key"), pem_key(k))

    print("mkcerts: root + good/expired/wrong/rogue for %s in %s" % (cn, d))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
