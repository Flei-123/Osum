#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
import datetime
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID

ROOTSCTL = os.path.abspath(sys.argv[1])
TLS_MAIN = os.path.abspath(sys.argv[2])
PASS = 0
FAIL = []
NOW = datetime.datetime.now(datetime.timezone.utc)


def ok(title, good, got=""):
    global PASS
    if good:
        PASS += 1
    else:
        FAIL.append((title, got))


def make_root(name, start_days, end_days):
    key = ec.generate_private_key(ec.SECP256R1())
    nm = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, name)])
    cert = (x509.CertificateBuilder().subject_name(nm).issuer_name(nm)
            .public_key(key.public_key()).serial_number(x509.random_serial_number())
            .not_valid_before(NOW + datetime.timedelta(days=start_days))
            .not_valid_after(NOW + datetime.timedelta(days=end_days))
            .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
            .sign(key, hashes.SHA256()))
    return key, cert


def pem(cert):
    return cert.public_bytes(serialization.Encoding.PEM)


def ctl(*args):
    p = subprocess.run([ROOTSCTL] + [str(a) for a in args], capture_output=True, text=True)
    fields = {}
    for ln in p.stdout.splitlines():
        parts = ln.split(" ")
        if len(parts) == 2 and parts[1].isdigit():
            fields[parts[0]] = int(parts[1])
    return p.returncode, fields, p.stdout


def count_blocks(path):
    return open(path, "rb").read().count(b"-----BEGIN CERTIFICATE-----")


def tls_verify(d, root_cert, root_key):
    leaf_key = ec.generate_private_key(ec.SECP256R1())
    leaf = (x509.CertificateBuilder()
            .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "localhost")]))
            .issuer_name(root_cert.subject).public_key(leaf_key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(NOW - datetime.timedelta(days=1))
            .not_valid_after(NOW + datetime.timedelta(days=30))
            .add_extension(x509.SubjectAlternativeName([x509.DNSName("localhost")]), critical=False)
            .sign(root_key, hashes.SHA256()))
    open(os.path.join(d, "leaf.crt"), "wb").write(pem(leaf))
    open(os.path.join(d, "leaf.key"), "wb").write(leaf_key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL,
        serialization.NoEncryption()))
    open(os.path.join(d, "store.pem"), "wb").write(pem(root_cert))
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    srv = subprocess.Popen(["openssl", "s_server", "-accept", str(port), "-cert", os.path.join(d, "leaf.crt"),
                            "-key", os.path.join(d, "leaf.key"), "-www", "-quiet", "-tls1_3"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(100):
        try:
            socket.create_connection(("127.0.0.1", port), timeout=0.2).close()
            break
        except OSError:
            time.sleep(0.05)
    try:
        p = subprocess.run([TLS_MAIN, "127.0.0.1", str(port), "localhost", os.path.join(d, "store.pem"), "/"],
                           capture_output=True, text=True, timeout=30)
    finally:
        srv.terminate()
    return p.stdout


def main():
    d = tempfile.mkdtemp()
    good_k, good = make_root("Good Root", -30, 365)
    _, good2 = make_root("Good Root Two", -30, 700)
    _, soon = make_root("Soon Root", -300, 30)
    exp_k, expired = make_root("Expired Root", -400, -10)
    _, future = make_root("Future Root", 20, 400)

    def bundle(name, *certs, extra=b""):
        path = os.path.join(d, name)
        open(path, "wb").write(b"".join(pem(c) for c in certs) + extra)
        return path

    b_good = bundle("good.pem", good, good2)
    rc, f, out = ctl("check", b_good)
    ok("check: healthy store exits 0", rc == 0 and f.get("VALID") == 2 and f.get("EXPIRED") == 0, out)

    rc, f, out = ctl("check", bundle("exp.pem", good, expired))
    ok("check: expired root exits 3 with a warning",
       rc == 3 and f.get("EXPIRED") == 1 and "warning" in out, out)

    b_soon = bundle("soon.pem", good, soon)
    rc, f, out = ctl("check", b_soon, 90)
    ok("check: root expiring inside the window exits 4", rc == 4 and f.get("SOON") == 1, out)
    rc, f, out = ctl("check", b_soon, 10)
    ok("check counter: same store with a 10 day window exits 0", rc == 0 and f.get("SOON") == 0, out)
    ok("check: next expiry is the soon root",
       abs(f.get("NEXT_EXPIRY", 0) - int((NOW + datetime.timedelta(days=30)).timestamp())) < 120, out)

    rc, f, out = ctl("check", bundle("fut.pem", good, future))
    ok("check: not-yet-valid root is counted, not trusted", f.get("NOT_YET") == 1 and f.get("VALID") == 1, out)

    junk = os.path.join(d, "junk.pem")
    open(junk, "wb").write(b"not a certificate bundle\n")
    rc, f, out = ctl("check", junk)
    ok("check counter: garbage store exits 3", rc == 3 and f.get("VALID", 0) == 0, out)
    rc, f, out = ctl("check", os.path.join(d, "missing.pem"))
    ok("check counter: missing store exits 6", rc == 6, out)

    target = os.path.join(d, "roots.pem")
    shutil.copy(b_good, target)
    old = open(target, "rb").read()
    cand = bundle("cand.pem", good, expired, soon, future)
    rc, f, out = ctl("apply", cand, target)
    ok("apply: bundle with expired roots is filtered and installed",
       rc == 0 and f.get("APPLIED") == 2 and f.get("DROPPED") == 2 and count_blocks(target) == 2, out)
    ok("apply: previous store kept as .prev", os.path.exists(target + ".prev") and open(target + ".prev", "rb").read() == old)
    ok("apply: no temp file left behind", not os.path.exists(target + ".new"))
    rc, f, out = ctl("check", target)
    ok("apply: installed store checks clean of expired roots", f.get("EXPIRED") == 0 and f.get("VALID") == 2, out)

    before = open(target, "rb").read()
    rc, f, out = ctl("apply", bundle("onlyexp.pem", expired), target)
    ok("apply counter: all-expired candidate refused", rc == 5 and open(target, "rb").read() == before, out)
    rc, f, out = ctl("apply", junk, target)
    ok("apply counter: garbage candidate refused", rc == 5 and open(target, "rb").read() == before, out)
    broken = bundle("broken.pem", good, extra=b"-----BEGIN CERTIFICATE-----\n!!!!\n-----END CERTIFICATE-----\n")
    rc, f, out = ctl("apply", broken, target)
    ok("apply counter: candidate with a corrupt block refused", rc == 5 and open(target, "rb").read() == before, out)
    rc, f, out = ctl("apply", b_good, target, 5)
    ok("apply counter: too few valid roots refused", rc == 5 and open(target, "rb").read() == before, out)
    rc, f, out = ctl("apply", os.path.join(d, "missing.pem"), target)
    ok("apply counter: missing candidate exits 6", rc == 6 and open(target, "rb").read() == before, out)

    out = tls_verify(d, good, good_k)
    ok("tls: chain to a valid root verifies", "VERIFY OK" in out, out)
    out = tls_verify(d, expired, exp_k)
    ok("tls counter: chain to an expired root refused as EXPIRED", "VERIFY EXPIRED" in out and "ERR" in out, out)

    for t, g in FAIL:
        print("  FAIL", t, "|", g.strip().replace("\n", " ; ")[:200])
    print("  roots: %d ok, %d failed" % (PASS, len(FAIL)))
    return 1 if FAIL else 0


sys.exit(main())
