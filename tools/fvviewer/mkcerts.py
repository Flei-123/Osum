#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import datetime, sys
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

d = sys.argv[1]
now = datetime.datetime.utcnow()
nb, na = now - datetime.timedelta(days=2), now + datetime.timedelta(days=3)

def name(cn):
    return x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, cn)])

ca_key = ec.generate_private_key(ec.SECP256R1())
ca = (x509.CertificateBuilder().subject_name(name("fvv test CA")).issuer_name(name("fvv test CA"))
      .public_key(ca_key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(nb).not_valid_after(na)
      .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
      .sign(ca_key, hashes.SHA256()))
sk = ec.generate_private_key(ec.SECP256R1())
srv = (x509.CertificateBuilder().subject_name(name("localhost")).issuer_name(ca.subject)
       .public_key(sk.public_key()).serial_number(x509.random_serial_number()).not_valid_before(nb).not_valid_after(na)
       .add_extension(x509.SubjectAlternativeName([x509.DNSName("localhost")]), critical=False)
       .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=False)
       .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
       .sign(ca_key, hashes.SHA256()))
pem = serialization.Encoding.PEM
open(d + "/ca.pem", "wb").write(ca.public_bytes(pem))
open(d + "/srv.pem", "wb").write(srv.public_bytes(pem))
open(d + "/chain.pem", "wb").write(srv.public_bytes(pem))
open(d + "/srv.key", "wb").write(sk.private_bytes(pem, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
