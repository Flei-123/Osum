#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/ota/mkcerts.py -- die Zertifikate der Gegenstelle.

    mkcerts.py <verzeichnis> [<name>] [<ip>]

Schreibt mit Pythons `cryptography` -- also NICHT mit dem Code, der sie
danach prueft; genau das ist der Sinn:

    ca.pem        eine Wurzel, RSA-2048, ein Jahr gueltig
    srv.pem/.key  das Serverzertifikat fuer <name> (Vorgabe ota.test),
                  mit SAN dNSName UND iPAddress <ip> (Vorgabe 10.0.2.2 --
                  die Adresse, unter der QEMUs Benutzernetz den Wirt
                  zeigt), von dieser Wurzel unterschrieben
    fremd-ca.pem  eine ZWEITE Wurzel, die NICHT im Vertrauensspeicher
                  liegt
    fremd.pem/.key ein Zertifikat fuer denselben Namen, von der zweiten
                  Wurzel unterschrieben -- der Fall "unbekannter
                  Aussteller"

WOZU DIE ZWEITE WURZEL. Ein Update-Weg, von dem nur der gute Fall
gemessen ist, ist nicht gemessen. `tools/ota/run.sh` haelt dem Geraet das
fremde Zertifikat hin und verlangt, dass es die Verbindung ABLEHNT und
danach NICHTS geschrieben hat.

DIESE ZERTIFIKATE SIND PRUEFSTANDSZERTIFIKATE. Sie liegen im
Temporaerbereich eines Laufs und werden danach weggeworfen; nichts davon
gehoert in ein Abbild.
"""
import datetime
import ipaddress
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
    k = key()
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


def make_srv(cak, cac, cn, ip):
    k = key()
    san = [x509.DNSName(cn)]
    try:
        san.append(x509.IPAddress(ipaddress.IPv4Address(ip)))
    except ValueError:
        pass
    c = (x509.CertificateBuilder()
         .subject_name(name(cn)).issuer_name(cac.subject)
         .public_key(k.public_key())
         .serial_number(x509.random_serial_number())
         .not_valid_before(NOW - datetime.timedelta(days=1))
         .not_valid_after(NOW + datetime.timedelta(days=365))
         .add_extension(x509.SubjectAlternativeName(san), critical=False)
         .add_extension(x509.BasicConstraints(ca=False, path_length=None),
                        critical=True)
         .sign(cak, hashes.SHA256()))
    return k, c


def schreiben(pfad, obj, privat=False):
    with open(pfad, "wb") as f:
        if privat:
            f.write(obj.private_bytes(
                serialization.Encoding.PEM,
                serialization.PrivateFormat.TraditionalOpenSSL,
                serialization.NoEncryption()))
        else:
            f.write(obj.public_bytes(serialization.Encoding.PEM))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    d = sys.argv[1]
    cn = sys.argv[2] if len(sys.argv) > 2 else "ota.test"
    ip = sys.argv[3] if len(sys.argv) > 3 else "10.0.2.2"
    os.makedirs(d, exist_ok=True)

    cak, cac = make_ca("OTA Pruefstand Wurzel")
    sk, sc = make_srv(cak, cac, cn, ip)
    schreiben(os.path.join(d, "ca.pem"), cac)
    schreiben(os.path.join(d, "srv.pem"), sc)
    schreiben(os.path.join(d, "srv.key"), sk, privat=True)

    fak, fac = make_ca("OTA Fremde Wurzel")
    fk, fc = make_srv(fak, fac, cn, ip)
    schreiben(os.path.join(d, "fremd-ca.pem"), fac)
    schreiben(os.path.join(d, "fremd.pem"), fc)
    schreiben(os.path.join(d, "fremd.key"), fk, privat=True)

    print("   ca.pem, srv.pem (%s / %s) und die fremde Wurzel" % (cn, ip))
    return 0


if __name__ == "__main__":
    sys.exit(main())
