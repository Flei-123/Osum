#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    keyring.py <bund> create                 primary- und Ersatzschluessel
    keyring.py <bund> display
    keyring.py <bund> oeffentlich primary|fallback [-o file]
    keyring.py <bund> signieren <file> -o <sig>  [--wer primary|fallback]
    keyring.py <bund> wechseln                neuer Hauptschluessel,
    keyring.py <bund> chain                   die Kettensaetze ausgeben
"""
import base64
import getpass
import hashlib
import importlib.util
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import opkpfad
OPK = opkpfad.path_2()
SCRYPT_N = 1 << 15
SCRYPT_R = 8
SCRYPT_P = 1


def opkmod():
    spec = importlib.util.spec_from_file_location("opkpy", OPK)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def chacha():
    from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
    return ChaCha20Poly1305


def pass_get(umgebung, ask):
    p = os.environ.get(umgebung)
    if p is not None:
        return p.encode("utf-8")
    return getpass.getpass(ask).encode("utf-8")


def shell(secret, passphrase):
    salz = os.urandom(16)
    schl = hashlib.scrypt(passphrase, salt=salz, n=SCRYPT_N, r=SCRYPT_R,
                          p=SCRYPT_P, dklen=32, maxmem=134217728)
    nonce = os.urandom(12)
    ct = chacha()(schl).encrypt(nonce, secret, None)
    return {"salz": base64.b64encode(salz).decode(),
            "nonce": base64.b64encode(nonce).decode(),
            "geheim": base64.b64encode(ct).decode(),
            "kdf": "scrypt", "n": SCRYPT_N, "r": SCRYPT_R, "p": SCRYPT_P}


def entkapseln(e, passphrase):
    schl = hashlib.scrypt(passphrase, salt=base64.b64decode(e["salz"]),
                          n=e["n"], r=e["r"], p=e["p"], dklen=32,
                          maxmem=134217728)
    return chacha()(schl).decrypt(base64.b64decode(e["nonce"]),
                                  base64.b64decode(e["geheim"]), None)


def load_2(bund):
    if not os.path.isfile(bund):
        raise SystemExit("schluesselbund: %s gibt es nicht -- erst `anlegen`"
                         % bund)
    with open(bund) as f:
        return json.load(f)


def save(bund, d):
    tmp = bund + ".neu"
    with open(tmp, "w") as f:
        json.dump(d, f, indent=1)
    os.chmod(tmp, 0o600)
    os.replace(tmp, bund)


def create(bund, aus=None):
    if os.path.exists(bund):
        raise SystemExit("schluesselbund: %s gibt es schon" % bund)
    m = opkmod()
    hp = pass_get("OSUM_SIGN_PASS", "Passphrase Hauptschluessel: ")
    ep = pass_get("OSUM_ERSATZ_PASS", "Passphrase Ersatzschluessel: ")
    primary = open(aus, "rb").read() if aus else os.urandom(32)
    if len(primary) != 32:
        raise SystemExit("schluesselbund: %s ist nicht 32 Oktett" % aus)
    ersatz = os.urandom(32)
    d = {"fassung": 1,
         "haupt": {"gen": 0,
                   "pub": m.ed25519_public(primary).hex(),
                   "huelle": shell(primary, hp)},
         "ersatz": {"pub": m.ed25519_public(ersatz).hex(),
                    "huelle": shell(ersatz, ep)},
         "kette": []}
    save(bund, d)
    print("schluesselbund %s angelegt" % bund)
    print("  haupt  gen 0  %s" % d["haupt"]["pub"])
    print("  ersatz        %s" % d["ersatz"]["pub"])
    return 0


def display(bund):
    d = load_2(bund)
    print("haupt  gen %d  %s" % (d["haupt"]["gen"], d["haupt"]["pub"]))
    print("ersatz        %s" % d["ersatz"]["pub"])
    for k in d["kette"]:
        print("chain  gen %d  %s  sig %s...  (from %s)"
              % (k["gen"], k["pub"], k["sig"][:16], k["von"]))
    return 0


def secret_get(d, wer):
    if wer == "ersatz":
        return entkapseln(d["ersatz"]["huelle"],
                          pass_get("OSUM_ERSATZ_PASS",
                                     "Passphrase Ersatzschluessel: "))
    return entkapseln(d["haupt"]["huelle"],
                      pass_get("OSUM_SIGN_PASS",
                                 "Passphrase Hauptschluessel: "))


def chain_nachricht(gen, pub_hex):
    return ("osum-schluessel\t%d\t%s" % (gen, pub_hex)).encode("ascii")


def wechseln(bund, mit_fallback=False):
    d = load_2(bund)
    m = opkmod()
    alt_secret = secret_get(d, "ersatz" if mit_fallback else "haupt")
    hp = pass_get("OSUM_SIGN_PASS", "Passphrase Hauptschluessel (neu): ")
    new = os.urandom(32)
    new_pub = m.ed25519_public(new)
    gen = d["haupt"]["gen"] + 1
    sig = m.ed25519_sign(alt_secret, chain_nachricht(gen, new_pub.hex()))
    d["kette"].append({"gen": gen, "pub": new_pub.hex(), "sig": sig.hex(),
                       "von": "ersatz" if mit_fallback else "haupt"})
    d["haupt"] = {"gen": gen, "pub": new_pub.hex(),
                  "huelle": shell(new, hp)}
    save(bund, d)
    print("Schluesselwechsel auf gen %d: %s (signiert vom %s)"
          % (gen, new_pub.hex(), "Ersatzschluessel" if mit_fallback
             else "Schluessel gen %d" % (gen - 1)))
    return 0


def signieren(bund, file_2, aus, wer):
    d = load_2(bund)
    m = opkmod()
    sk = secret_get(d, wer)
    roh = open(file_2, "rb").read()
    sig = m.ed25519_sign(sk, roh)
    pk = m.ed25519_public(sk)
    if not m.ed25519_verify(pk, roh, sig):
        raise SystemExit("schluesselbund: die eigene Signatur gilt nicht")
    with open(aus, "wb") as f:
        f.write(sig)
    print("   signiert  %s  (%d Oktett) mit %s %s..."
          % (os.path.basename(file_2), len(roh), wer, pk.hex()[:12]))
    return 0


def oeffentlich(bund, wer, aus):
    d = load_2(bund)
    pub = bytes.fromhex(d[wer]["pub"])
    if aus:
        with open(aus, "wb") as f:
            f.write(pub)
    else:
        print(pub.hex())
    return 0


def chain(bund):
    d = load_2(bund)
    for k in d["kette"]:
        print("kette\t%d\t%s\t%s" % (k["gen"], k["pub"], k["sig"]))
    return 0


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    bund = sys.argv[1]
    was = sys.argv[2]
    rest = sys.argv[3:]
    if was == "anlegen":
        aus = None
        if "--aus" in rest:
            aus = rest[rest.index("--aus") + 1]
        return create(bund, aus)
    if was == "zeigen":
        return display(bund)
    if was == "kette":
        return chain(bund)
    if was == "wechseln":
        return wechseln(bund, "--ersatz" in rest)
    if was == "oeffentlich":
        wer = rest[0] if rest else "haupt"
        aus = None
        if "-o" in rest:
            aus = rest[rest.index("-o") + 1]
        return oeffentlich(bund, wer, aus)
    if was == "signieren":
        file_2 = rest[0]
        aus = rest[rest.index("-o") + 1]
        wer = "haupt"
        if "--wer" in rest:
            wer = rest[rest.index("--wer") + 1]
        return signieren(bund, file_2, aus, wer)
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
