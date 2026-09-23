#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/ota/schluesselbund.py -- WO DER GEHEIME SCHLUESSEL LIEGT.

    schluesselbund.py <bund> anlegen                 Haupt- und Ersatzschluessel
    schluesselbund.py <bund> zeigen
    schluesselbund.py <bund> oeffentlich haupt|ersatz [-o datei]
    schluesselbund.py <bund> signieren <datei> -o <sig>  [--wer haupt|ersatz]
    schluesselbund.py <bund> wechseln                neuer Hauptschluessel,
                                                     Kettensatz mit dem alten
    schluesselbund.py <bund> kette                   die Kettensaetze ausgeben

DIE ENTSCHEIDUNG, DIE `docs/OTA.md` OFFENGELASSEN HAT.

Dort steht: "Der geheime Schluessel liegt unverschluesselt auf der
Baumaschine (`$OUT/geheim.key`); wo er auf Dauer liegen soll -- Tresor,
HSM, getrennte Signiermaschine --, hat noch niemand entschieden."

ENTSCHIEDEN WIRD: **verschluesselte Datei mit Passphrase, und der
Signierschritt ist vom Bauschritt GETRENNT.** Begruendung, in der
Reihenfolge, in der sie zaehlt:

1. **Getrennte Signiermaschine ist das Ziel, aber sie ist eine
   ORGANISATION und kein Programm.** Was ein Programm dafuer liefern
   muss, ist eine SCHNITTSTELLE, hinter der der Schluessel steckt:
   "hier sind Oktette, gib mir eine Signatur". Genau die ist
   `signieren`. `veroeffentlichen.py` ruft sie auf und braucht selbst
   keinen Schluessel; wer die Signiermaschine trennen will, kopiert die
   drei zu signierenden Dateien hinueber und die drei Signaturen
   zurueck. Der Bau aendert sich dafuer nicht um eine Zeile.

2. **HSM waere gelogen.** Auf diesem Wirt steckt kein YubiKey und kein
   TPM-gestuetzter Schluessel, und eine Umsetzung, die nur so tut,
   waere schlechter als keine. Was fuer die naechste Stufe fehlt, steht
   unten und ist kurz, WEIL diese Stufe die Naht schon an der richtigen
   Stelle hat.

3. **Unverschluesselt auf der Baumaschine ist das, was heute da ist,
   und das ist das eigentliche Problem.** Wer die Baumaschine hat, hat
   damit jedes Geraet. Eine Passphrase aendert das nicht vollstaendig
   (wer die Maschine WAEHREND eines Baus hat, sieht den Schluessel im
   Speicher), aber sie nimmt den haeufigsten Fall weg: eine Sicherung,
   ein Abbild, eine weggeworfene Platte.

WIE VERSCHLUESSELT WIRD: scrypt (n=2^15, r=8, p=1, 16 Oktett Salz) aus
`hashlib` der Standardbibliothek fuer die Ableitung, und
ChaCha20-Poly1305 aus `cryptography` fuer die Huelle. Die Passphrase
kommt aus `OSUM_SIGN_PASS` oder von der Tastatur. Der Bund ist eine
JSON-Datei; alles darin ist Text, damit man ihn sichern kann, ohne ein
Werkzeug zu brauchen.

DER ERSATZSCHLUESSEL wird beim Anlegen erzeugt und danach NIE wieder
zum Signieren einer gewoehnlichen Auslieferung benutzt. Er hat eine
eigene Passphrase (`OSUM_ERSATZ_PASS`), damit die Trennung nicht nur
gemeint, sondern gebaut ist -- er gehoert auf einen anderen Datentraeger
als der Hauptschluessel, und dieses Programm zwingt niemanden dazu, aber
es macht es moeglich.

WAS FUER DIE NAECHSTE STUFE FEHLT (ehrlich, kurz):
  * ein Geraet, das den Schluessel NICHT herausgibt (PKCS#11/YubiKey).
    `signieren` waere dann ein Aufruf statt einer Rechnung; alles
    darueber bliebe gleich.
  * ein Protokoll, das jede Signatur mit Zeit, Datei und Grund festhaelt.
    Heute schreibt `veroeffentlichen.py` das in `journal.txt`, aber auf
    derselben Maschine.
  * Vier-Augen: zwei Passphrasen fuer eine Auslieferung. Das ist eine
    Aenderung an DIESER Datei und keine am Format.
"""
import base64
import getpass
import hashlib
import importlib.util
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import opkpfad  # noqa: E402  -- A-025: der alte Standardpfad war ein Arbeitsbaum
OPK = opkpfad.pfad()
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


def pass_holen(umgebung, frage):
    p = os.environ.get(umgebung)
    if p is not None:
        return p.encode("utf-8")
    return getpass.getpass(frage).encode("utf-8")


def huelle(geheim, passphrase):
    salz = os.urandom(16)
    schl = hashlib.scrypt(passphrase, salt=salz, n=SCRYPT_N, r=SCRYPT_R,
                          p=SCRYPT_P, dklen=32, maxmem=134217728)
    nonce = os.urandom(12)
    ct = chacha()(schl).encrypt(nonce, geheim, None)
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


def laden(bund):
    if not os.path.isfile(bund):
        raise SystemExit("schluesselbund: %s gibt es nicht -- erst `anlegen`"
                         % bund)
    with open(bund) as f:
        return json.load(f)


def sichern(bund, d):
    tmp = bund + ".neu"
    with open(tmp, "w") as f:
        json.dump(d, f, indent=1)
    os.chmod(tmp, 0o600)
    os.replace(tmp, bund)


def anlegen(bund, aus=None):
    """`aus` uebernimmt einen VORHANDENEN geheimen Schluessel als Haupt-
    schluessel. Das ist kein Bequemlichkeitsschalter: die Pruefstaende
    dieses Repos (tools/install/pakete.sh) erzeugen ihren Schluessel
    selbst und signieren damit die Pakete, die schon im Abbild liegen.
    Ohne diesen Weg muesste eine Messung entweder das Abbild neu bauen
    oder mit zwei verschiedenen Vertrauensankern arbeiten -- beides
    waere eine Aenderung an dem, was gemessen wird."""
    if os.path.exists(bund):
        raise SystemExit("schluesselbund: %s gibt es schon" % bund)
    m = opkmod()
    hp = pass_holen("OSUM_SIGN_PASS", "Passphrase Hauptschluessel: ")
    ep = pass_holen("OSUM_ERSATZ_PASS", "Passphrase Ersatzschluessel: ")
    haupt = open(aus, "rb").read() if aus else os.urandom(32)
    if len(haupt) != 32:
        raise SystemExit("schluesselbund: %s ist nicht 32 Oktett" % aus)
    ersatz = os.urandom(32)
    d = {"fassung": 1,
         "haupt": {"gen": 0,
                   "pub": m.ed25519_public(haupt).hex(),
                   "huelle": huelle(haupt, hp)},
         "ersatz": {"pub": m.ed25519_public(ersatz).hex(),
                    "huelle": huelle(ersatz, ep)},
         "kette": []}
    sichern(bund, d)
    print("schluesselbund %s angelegt" % bund)
    print("  haupt  gen 0  %s" % d["haupt"]["pub"])
    print("  ersatz        %s" % d["ersatz"]["pub"])
    return 0


def zeigen(bund):
    d = laden(bund)
    print("haupt  gen %d  %s" % (d["haupt"]["gen"], d["haupt"]["pub"]))
    print("ersatz        %s" % d["ersatz"]["pub"])
    for k in d["kette"]:
        print("kette  gen %d  %s  sig %s...  (von %s)"
              % (k["gen"], k["pub"], k["sig"][:16], k["von"]))
    return 0


def geheim_holen(d, wer):
    if wer == "ersatz":
        return entkapseln(d["ersatz"]["huelle"],
                          pass_holen("OSUM_ERSATZ_PASS",
                                     "Passphrase Ersatzschluessel: "))
    return entkapseln(d["haupt"]["huelle"],
                      pass_holen("OSUM_SIGN_PASS",
                                 "Passphrase Hauptschluessel: "))


# DIE NACHRICHT EINES KETTENSATZES. Sie faengt mit einem eigenen Wort an,
# das in keiner anderen signierten Sache dieses Systems vorkommt --
# damit eine Wechselsignatur niemals als Signatur ueber ein VERZEICHNIS
# oder ein Paket durchgehen kann und umgekehrt.
def kette_nachricht(gen, pub_hex):
    return ("osum-schluessel\t%d\t%s" % (gen, pub_hex)).encode("ascii")


def wechseln(bund, mit_ersatz=False):
    """Ein neuer Hauptschluessel, und der Kettensatz, der ihn beglaubigt.

    Der Satz wird mit dem ALTEN Hauptschluessel signiert (oder, wenn die
    Kette gerissen ist, mit dem Ersatzschluessel -- `--ersatz`). Ein
    Geraet nimmt den neuen Schluessel erst an, wenn diese Signatur
    stimmt; deshalb ist ein Wechsel ein VORGANG und kein Austausch.
    """
    d = laden(bund)
    m = opkmod()
    alt_geheim = geheim_holen(d, "ersatz" if mit_ersatz else "haupt")
    hp = pass_holen("OSUM_SIGN_PASS", "Passphrase Hauptschluessel (neu): ")
    neu = os.urandom(32)
    neu_pub = m.ed25519_public(neu)
    gen = d["haupt"]["gen"] + 1
    sig = m.ed25519_sign(alt_geheim, kette_nachricht(gen, neu_pub.hex()))
    d["kette"].append({"gen": gen, "pub": neu_pub.hex(), "sig": sig.hex(),
                       "von": "ersatz" if mit_ersatz else "haupt"})
    d["haupt"] = {"gen": gen, "pub": neu_pub.hex(),
                  "huelle": huelle(neu, hp)}
    sichern(bund, d)
    print("Schluesselwechsel auf gen %d: %s (signiert vom %s)"
          % (gen, neu_pub.hex(), "Ersatzschluessel" if mit_ersatz
             else "Schluessel gen %d" % (gen - 1)))
    return 0


def signieren(bund, datei, aus, wer):
    d = laden(bund)
    m = opkmod()
    sk = geheim_holen(d, wer)
    roh = open(datei, "rb").read()
    sig = m.ed25519_sign(sk, roh)
    pk = m.ed25519_public(sk)
    if not m.ed25519_verify(pk, roh, sig):
        raise SystemExit("schluesselbund: die eigene Signatur gilt nicht")
    with open(aus, "wb") as f:
        f.write(sig)
    print("   signiert  %s  (%d Oktett) mit %s %s..."
          % (os.path.basename(datei), len(roh), wer, pk.hex()[:12]))
    return 0


def oeffentlich(bund, wer, aus):
    d = laden(bund)
    pub = bytes.fromhex(d[wer]["pub"])
    if aus:
        with open(aus, "wb") as f:
            f.write(pub)
    else:
        print(pub.hex())
    return 0


def kette(bund):
    d = laden(bund)
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
        return anlegen(bund, aus)
    if was == "zeigen":
        return zeigen(bund)
    if was == "kette":
        return kette(bund)
    if was == "wechseln":
        return wechseln(bund, "--ersatz" in rest)
    if was == "oeffentlich":
        wer = rest[0] if rest else "haupt"
        aus = None
        if "-o" in rest:
            aus = rest[rest.index("-o") + 1]
        return oeffentlich(bund, wer, aus)
    if was == "signieren":
        datei = rest[0]
        aus = rest[rest.index("-o") + 1]
        wer = "haupt"
        if "--wer" in rest:
            wer = rest[rest.index("--wer") + 1]
        return signieren(bund, datei, aus, wer)
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
