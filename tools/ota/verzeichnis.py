#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/ota/verzeichnis.py -- das signierte VERZEICHNIS einer Quelle.

    verzeichnis.py <quellverzeichnis> --fassung <n> --schluessel <geheim.key>
                   [--kaputt <datei>]

WAS EIN VERZEICHNIS IST UND WARUM ES NEBEN DEM INDEX STEHT.

`opk quelle` schreibt seit Runde UPDATE einen `INDEX` und eine
`INDEX.sig`. Der INDEX nennt je Paket den STORE-Streuwert -- den
Streuwert ueber Metadaten und Daten INNERHALB des Pakets. Das ist das
richtige Glied fuer die Frage "ist das Paket, das ich ausgepackt habe,
das gemeinte?", und `opk` prueft es.

Es ist NICHT das richtige Glied fuer die Frage, die ein Update ueber das
Netz zuerst stellen muss: "sind die Oktette, die ueber die Leitung kamen,
vollstaendig und unveraendert -- BEVOR ich irgendetwas damit tue?" Dafuer
braucht es den Streuwert ueber die DATEI, so wie sie auf der Leitung
liegt, und die Laenge, damit ein Abbruch als Abbruch erkennbar ist und
nicht als Inhalt.

Dazu kommt die Fassungsnummer der QUELLE. Sie ist der
Rueckschrittsschutz: `/system/FASSUNG` auf dem Geraet darf nur steigen.
Ohne sie kann jeder, der eine alte, richtig signierte Antwort
aufgehoben hat, ein Geraet auf eine Fassung mit bekannter Luecke
zuruecksetzen -- und jede Signatur waere dabei gueltig.

DAS FORMAT, ASCII, mit Tabulatoren getrennt, Zeilenende LF:

    OTA1
    fassung\t<dezimal>
    paket\t<name>\t<fassung>\t<sha256 der Datei, 64 hex>\t<oktette>\t<datei>\t<plattform>
    ...

Die erste Zeile ist die Kennung. Die zweite MUSS die Fassung sein --
das Geraet liest sie, bevor es irgendeine Paketzeile ansieht.

`VERZEICHNIS.sig` sind 64 rohe Oktette: die Ed25519-Signatur ueber ALLE
Oktette von `VERZEICHNIS`. Gerechnet wird sie mit derselben Umsetzung,
die `pkg/opk.py` benutzt, und danach mit einer FREMDEN (libsodium ueber
pynacl, sonst `cryptography`) nachgeprueft -- eine Signatur, die nur ihr
eigener Erzeuger anerkennt, sagt nichts.

`--kaputt <datei>` schreibt ein Verzeichnis, das RICHTIG signiert ist und
in dem der Streuwert genau eines Pakets veraendert wurde. Das ist der
Fall (g) des Laeufers: die Signatur stimmt, der Inhalt nicht, und das
Geraet muss trotzdem ablehnen -- weil die Kette an jedem Glied geprueft
wird und nicht nur am ersten.
"""
import hashlib
import importlib.util
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import plattform as PLT   # noqa: E402

OPK = os.environ.get("OPK", "/root/orientos-install/pkg/opk.py")


def load_opk():
    spec = importlib.util.spec_from_file_location("opkpy", OPK)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def fremd_prueft(pk, msg, sig):
    """Eine zweite Meinung zur eigenen Signatur. None = keine da."""
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


def meta_aus_opk(pfad):
    """name und fassung aus dem Kopf einer .opk-Datei.

    Der Kopf ist `OPKG0001`, dann zwei Laengen zu acht Oktetten und der
    SHA-256; die Metadaten stehen als `schluessel=wert` je Zeile dahinter.
    Das ist dasselbe Format, das `kernel/user/opk.fi` liest -- hier wird
    es nur gelesen, nirgends ein zweites geschrieben.
    """
    with open(pfad, "rb") as f:
        kopf = f.read(64)
        if kopf[:8] != b"OPKG0001":
            raise SystemExit("verzeichnis: %s ist keine OPKG-Datei" % pfad)
        ml = int.from_bytes(kopf[8:16], "little")
        meta = f.read(ml).decode("utf-8", "replace")
    name = fassung = None
    for zeile in meta.split("\n"):
        if zeile.startswith("name="):
            name = zeile[5:].strip()
        elif zeile.startswith("fassung="):
            fassung = zeile[8:].strip()
    if not name:
        raise SystemExit("verzeichnis: %s hat keinen Namen" % pfad)
    return name, fassung or "0"


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    quelle = sys.argv[1]
    fassung = None
    schluessel = None
    kaputt = None
    i = 2
    while i < len(sys.argv):
        a = sys.argv[i]
        if a == "--fassung" and i + 1 < len(sys.argv):
            i += 1
            fassung = int(sys.argv[i])
        elif a == "--schluessel" and i + 1 < len(sys.argv):
            i += 1
            schluessel = sys.argv[i]
        elif a == "--kaputt" and i + 1 < len(sys.argv):
            i += 1
            kaputt = sys.argv[i]
        else:
            raise SystemExit("verzeichnis: unbekanntes Wort %s" % a)
        i += 1
    if fassung is None or schluessel is None:
        print(__doc__)
        return 2

    dateien = sorted(f for f in os.listdir(quelle) if f.endswith(".opk"))
    if not dateien:
        raise SystemExit("verzeichnis: %s hat keine .opk-Datei" % quelle)

    # RUNDE BETRIEB: OTA2. Dieses Werkzeug bleibt der einfache
    # Pruefstand-Erzeuger (eine Fassung, ein Schluessel, keine Kette,
    # keine Sperrliste); die Betriebsfassung mit Register, Vorrat,
    # Sperrliste und Schluesselwechsel ist
    # `tools/ota/veroeffentlichen.py`. Die Kennung muss trotzdem
    # mitziehen, weil ein Geraet dieser Runde ein OTA1-Verzeichnis
    # ABLEHNT -- sonst waere die Sperrliste durch ein altes, richtig
    # signiertes Verzeichnis abzuschalten.
    zeilen = ["OTA2", "fassung\t%d" % fassung, "schluesselgen\t0"]
    for d in dateien:
        p = os.path.join(quelle, d)
        roh = open(p, "rb").read()
        h = hashlib.sha256(roh).hexdigest()
        if kaputt == d:
            # RICHTIG SIGNIERT, FALSCHER STREUWERT. Ein Bit im Streuwert
            # gekippt: die Signatur ueber das Verzeichnis bleibt gueltig,
            # die Kette zum Paket ist gebrochen.
            h = ("%x" % (int(h, 16) ^ 1)).rjust(64, "0")
        name, pf = meta_aus_opk(p)
        # RUNDE STORE-MOBIL: die sechste Spalte, siehe plattform.py.
        plattform = PLT.plattform_von_roh(roh, d)
        zeilen.append("paket\t%s\t%s\t%s\t%d\t%s\t%s"
                      % (name, pf, h, len(roh), d, plattform))
    text = "\n".join(zeilen) + "\n"
    roh = text.encode("ascii")

    m = load_opk()
    sk = open(schluessel, "rb").read()
    pk = m.ed25519_public(sk)
    sig = m.ed25519_sign(sk, roh)
    if not m.ed25519_verify(pk, roh, sig):
        raise SystemExit("verzeichnis: die eigene Signatur gilt nicht")
    anders = fremd_prueft(pk, roh, sig)
    if anders is False:
        raise SystemExit("verzeichnis: eine FREMDE Umsetzung erkennt die "
                         "Signatur nicht an")

    with open(os.path.join(quelle, "VERZEICHNIS"), "wb") as f:
        f.write(roh)
    with open(os.path.join(quelle, "VERZEICHNIS.sig"), "wb") as f:
        f.write(sig)
    print("   VERZEICHNIS  fassung %d, %d Paket(e), %d Oktette, sig %s...%s"
          % (fassung, len(dateien), len(roh), sig.hex()[:12],
             "" if anders else " (KEINE zweite Meinung verfuegbar)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
