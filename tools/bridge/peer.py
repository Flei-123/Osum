#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/bridge/peer.py -- DIE GEGENSTELLE FUER DEN PRUEFSTAND.
#
# DAS IST NICHT DER ECHTE JARVIS-SERVER. Der laeuft anderswo, spricht
# ein anderes Protokoll und ist nicht Teil dieses Repos. Dieses Programm
# ist ein TLS-1.3-Server in Python, der GENAU das Protokoll aus
# kernel/app/jarvisd.fi spricht, damit `tools/bridge/run.sh` etwas hat,
# gegen das es messen kann -- und damit jede Zusage dieser Runde gegen
# Software geprueft wird, die dieses Repo nicht geschrieben hat
# (Pythons ssl-Modul, OpenSSL darunter, `cryptography` fuer Ed25519).
#
# Was hier steht und was in run.sh steht, ist damit ausdruecklich
# getrennt: die Zahlen kommen von aussen, nicht aus Osum.
#
# Aufruf:
#   peer.py --cert C --key K --port P --auftraege A --aus D
#                  [--kopplung CODE] [--abriss] [--kein-beweis]
#                  [--wartezeit S]
#
# Die Auftragsdatei traegt eine Zeile je Auftrag:
#   <art>|<arg1>|<nutzlast-hex>
# zum Beispiel
#   system||
#   lies|/var/jarvis/gruss.txt|
#   schreib|/var/jarvis/neu.txt|68616c6c6f
#
# In die Ausgabedatei kommt eine Zeile je Antwort:
#   ANTWORT <id> <art> <status> <laenge> <sha256>
# und die Nutzlast selbst als <aus>.<id>.bin daneben.

import argparse
import hashlib
import os
import socket
import ssl
import sys

try:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import (
        Ed25519PublicKey,
    )
    from cryptography.exceptions import InvalidSignature
    HAT_CRYPTO = True
except Exception:
    HAT_CRYPTO = False


class Draht:
    """Zeilen und Nutzlasten auf einem TLS-Strom."""

    def __init__(self, s):
        self.s = s
        self.puf = b""

    def fuellen(self):
        d = self.s.recv(8192)
        if not d:
            raise EOFError("die Gegenseite ist weg")
        self.puf += d

    def zeile(self):
        while b"\n" not in self.puf:
            self.fuellen()
        i = self.puf.index(b"\n")
        z = self.puf[:i]
        self.puf = self.puf[i + 1:]
        return z.decode("utf-8", "replace")

    def oktette(self, n):
        while len(self.puf) < n:
            self.fuellen()
        d = self.puf[:n]
        self.puf = self.puf[n:]
        return d

    def nachricht(self):
        """Eine Zeile plus ihre Nutzlast. Die Laenge ist immer das
        letzte Feld -- so steht es im Protokoll."""
        z = self.zeile()
        f = z.split(" ")
        laenge = 0
        if f and f[-1].isdigit():
            laenge = int(f[-1])
            f = f[:-1]
        return f, self.oktette(laenge)

    def sende(self, felder, nutz=b""):
        kopf = " ".join(felder) + " " + str(len(nutz)) + "\n"
        self.s.sendall(kopf.encode() + nutz)


def hex_von(s):
    return s.encode("utf-8").hex()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--cert", required=True)
    p.add_argument("--key", required=True)
    p.add_argument("--port", type=int, default=8443)
    p.add_argument("--auftraege", default="")
    p.add_argument("--aus", default="/tmp/bridge-aus")
    p.add_argument("--kopplung", default="")
    p.add_argument("--abriss", action="store_true")
    p.add_argument("--kein-beweis", action="store_true")
    p.add_argument("--wartezeit", type=float, default=60.0)
    p.add_argument("--verbindungen", type=int, default=1)
    a = p.parse_args()

    log = open(a.aus, "w")

    def sag(*teile):
        log.write(" ".join(str(t) for t in teile) + "\n")
        log.flush()

    auftraege = []
    if a.auftraege and os.path.exists(a.auftraege):
        for zeile in open(a.auftraege):
            zeile = zeile.rstrip("\n")
            if not zeile or zeile.startswith("#"):
                continue
            teile = zeile.split("|")
            while len(teile) < 3:
                teile.append("")
            auftraege.append((teile[0], teile[1], teile[2]))

    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_3
    ctx.load_cert_chain(a.cert, a.key)

    lauscher = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    lauscher.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    lauscher.bind(("0.0.0.0", a.port))
    lauscher.listen(4)
    lauscher.settimeout(a.wartezeit)
    sag("BEREIT", a.port)

    ergebnis = 0
    for runde in range(a.verbindungen):
        ergebnis = eine_verbindung(a, ctx, lauscher, sag, auftraege, runde)
    lauscher.close()
    log.close()
    return ergebnis


# Eine einzelne Sitzung. Getrennt, damit der Pruefstand ZWEI verlangen
# kann: die Kopplung braucht einen ersten Anlauf, der abgelehnt wird,
# und einen zweiten, der nach der Bestaetigung durchgeht.
def eine_verbindung(a, ctx, lauscher, sag, auftraege, runde):
    try:
        roh, adr = lauscher.accept()
    except socket.timeout:
        sag("KEINE-VERBINDUNG")
        return 1
    sag("VERBUNDEN", adr[0])
    roh.settimeout(a.wartezeit)
    try:
        s = ctx.wrap_socket(roh, server_side=True)
    except Exception as e:
        sag("HANDSCHLAG-GESCHEITERT", type(e).__name__)
        return 1
    sag("TLS", s.version(), s.cipher()[0])

    d = Draht(s)
    pub = None
    try:
        # ---------------------------------------------------- Anmeldung
        f, _ = d.nachricht()
        sag("GRUSS", " ".join(f))
        f, _ = d.nachricht()
        if f[0] != "ich":
            sag("FEHLER kein `ich`")
            return 1
        pub = bytes.fromhex(f[1])
        sag("PUB", f[1])

        if not a.kein_beweis:
            nonce = os.urandom(32)
            d.sende(["frage", nonce.hex()])
            f, _ = d.nachricht()
            if f[0] != "beweis":
                sag("FEHLER kein `beweis`, sondern", f[0])
                return 1
            sig = bytes.fromhex(f[1])
            sag("SIG", f[1])
            if HAT_CRYPTO:
                try:
                    Ed25519PublicKey.from_public_bytes(pub).verify(sig, nonce)
                    sag("BEWEIS gut")
                except InvalidSignature:
                    sag("BEWEIS FALSCH")
                    return 1
                # Die Gegenprobe: dieselbe Signatur ueber ANDERE Oktette
                # muss durchfallen. Sonst prueft die Pruefung nichts.
                try:
                    Ed25519PublicKey.from_public_bytes(pub).verify(
                        sig, os.urandom(32))
                    sag("GEGENPROBE FALSCH-ANGENOMMEN")
                except InvalidSignature:
                    sag("GEGENPROBE gut")
            else:
                sag("BEWEIS ungeprueft (python3-cryptography fehlt)")

        if a.kopplung:
            d.sende(["kopplung-noetig", a.kopplung])
            f, _ = d.nachricht()
            sag("KOPPLUNG", " ".join(f))
            if f[0] == "kopplung-abgelehnt":
                sag("KOPPLUNG-ABGELEHNT")
                return 0
            if f[0] != "kopplung" or f[1] != a.kopplung:
                sag("KOPPLUNG-FALSCH")
                return 1
        d.sende(["willkommen"])
        sag("ANGEMELDET")

        # ---------------------------------------------------- Auftraege
        for nr, (art, arg1, nutzhex) in enumerate(auftraege, start=1):
            nutz = bytes.fromhex(nutzhex) if nutzhex else b""
            d.sende(["auftrag", str(nr), art, hex_von(arg1), "0"], nutz)
            if a.abriss and nr == 1:
                # MITTEN IM AUFTRAG die Verbindung wegnehmen. Der Helfer
                # darf daran nicht sterben und nichts liegenlassen.
                sag("ABRISS nach Auftrag", nr)
                try:
                    s.shutdown(socket.SHUT_RDWR)
                except Exception:
                    pass
                s.close()
                return 0
            f, inhalt = d.nachricht()
            if f[0] != "fertig":
                sag("FEHLER unerwartet", " ".join(f))
                return 1
            dig = hashlib.sha256(inhalt).hexdigest()
            sag("ANTWORT", f[1], art, f[2], len(inhalt), dig)
            with open("%s.%s.bin" % (a.aus, f[1]), "wb") as fh:
                fh.write(inhalt)
            if f[2] == "nein":
                sag("GRUND", inhalt.decode("utf-8", "replace").strip())
        d.sende(["tschuess"])
        sag("TSCHUESS")
    except (EOFError, socket.timeout, ConnectionResetError,
            ssl.SSLError, OSError) as e:
        sag("ABGERISSEN", type(e).__name__)
    finally:
        try:
            s.close()
        except Exception:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
