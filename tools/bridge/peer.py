#!/usr/bin/env python3

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


class Wire:

    def __init__(self, s):
        self.s = s
        self.puf = b""

    def fuellen(self):
        d = self.s.recv(8192)
        if not d:
            raise EOFError("die Gegenseite ist weg")
        self.puf += d

    def line(self):
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
        z = self.line()
        f = z.split(" ")
        len_ = 0
        if f and f[-1].isdigit():
            len_ = int(f[-1])
            f = f[:-1]
        return f, self.oktette(len_)

    def sende(self, felder, nutz=b""):
        header = " ".join(felder) + " " + str(len(nutz)) + "\n"
        self.s.sendall(header.encode() + nutz)


KIND_WIRE = {"lies": "read", "schreib": "write", "liste": "list", "befehl": "run",
             "foto": "screenshot", "eingabe": "input"}
INPUT_WIRE = {"taste": "key", "maus": "mouse", "knopf": "click"}
STATUS_LOG = {"failed": "nein"}


def wire_kind(art):
    return KIND_WIRE.get(art, art)


def wire_arg(art, arg):
    if art != "eingabe":
        return arg
    head, sep, tail = arg.partition(" ")
    return INPUT_WIRE.get(head, head) + sep + tail


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
    p.add_argument("--kopplung-hex", action="store_true")
    p.add_argument("--kopplung-web", type=int, default=0)
    p.add_argument("--abriss", action="store_true")
    p.add_argument("--kein-beweis", action="store_true")
    p.add_argument("--wartezeit", type=float, default=60.0)
    p.add_argument("--verbindungen", type=int, default=1)
    a = p.parse_args()

    log = open(a.aus, "w")

    def say(*parts):
        log.write(" ".join(str(t) for t in parts) + "\n")
        log.flush()

    auftraege = []
    if a.auftraege and os.path.exists(a.auftraege):
        for line in open(a.auftraege):
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("|")
            while len(parts) < 3:
                parts.append("")
            auftraege.append((parts[0], parts[1], parts[2]))

    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_3
    ctx.load_cert_chain(a.cert, a.key)

    lauscher = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    lauscher.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    lauscher.bind(("0.0.0.0", a.port))
    lauscher.listen(4)
    lauscher.settimeout(a.wartezeit)
    say("BEREIT", a.port)

    ergebnis = 0
    for runde in range(a.verbindungen):
        ergebnis = eine_verbindung(a, ctx, lauscher, say, auftraege, runde)
    lauscher.close()
    log.close()
    return ergebnis


def eine_verbindung(a, ctx, lauscher, say, auftraege, runde):
    try:
        roh, adr = lauscher.accept()
    except socket.timeout:
        say("KEINE-VERBINDUNG")
        return 1
    say("VERBUNDEN", adr[0])
    roh.settimeout(a.wartezeit)
    try:
        s = ctx.wrap_socket(roh, server_side=True)
    except Exception as e:
        say("HANDSCHLAG-GESCHEITERT", type(e).__name__)
        return 1
    say("TLS", s.version(), s.cipher()[0])

    d = Wire(s)
    pub = None
    try:
        f, _ = d.nachricht()
        say("GRUSS", " ".join(f))
        f, _ = d.nachricht()
        if f[0] != "hello":
            say("ERROR no `hello`")
            return 1
        pub = bytes.fromhex(f[1])
        say("PUB", f[1])

        if not a.kein_beweis:
            nonce = os.urandom(32)
            d.sende(["challenge", nonce.hex()])
            f, _ = d.nachricht()
            if f[0] != "proof":
                say("ERROR no `proof`, but", f[0])
                return 1
            sig = bytes.fromhex(f[1])
            say("SIG", f[1])
            if HAT_CRYPTO:
                try:
                    Ed25519PublicKey.from_public_bytes(pub).verify(sig, nonce)
                    say("BEWEIS gut")
                except InvalidSignature:
                    say("BEWEIS FALSCH")
                    return 1
                try:
                    Ed25519PublicKey.from_public_bytes(pub).verify(
                        sig, os.urandom(32))
                    say("GEGENPROBE FALSCH-ANGENOMMEN")
                except InvalidSignature:
                    say("GEGENPROBE gut")
            else:
                say("BEWEIS ungeprueft (python3-cryptography fehlt)")

        if a.kopplung and a.kopplung_web:
            wire_code = hex_von(a.kopplung) if a.kopplung_hex else a.kopplung
            for n in range(abs(a.kopplung_web)):
                d.sende(["pairing-needed", wire_code])
                f, _ = d.nachricht()
                say("KOPPLUNG-WEB", n + 1, " ".join(f[:1]))
                if f[0] != "hello":
                    say("KOPPLUNG-WEB-FALSCH", f[0])
                    return 1
            if a.kopplung_web < 0:
                say("PAIRING-WEB-END without approval")
                return 0
        elif a.kopplung:
            wire_code = hex_von(a.kopplung) if a.kopplung_hex else a.kopplung
            d.sende(["pairing-needed", wire_code])
            f, _ = d.nachricht()
            say("KOPPLUNG", " ".join(f))
            if f[0] == "pair-rejected":
                say("KOPPLUNG-ABGELEHNT")
                return 0
            if f[0] != "pair" or f[1] != wire_code:
                say("KOPPLUNG-FALSCH")
                return 1
        d.sende(["welcome"])
        say("ANGEMELDET")

        for nr, (art, arg1, nutzhex) in enumerate(auftraege, start=1):
            nutz = bytes.fromhex(nutzhex) if nutzhex else b""
            d.sende(["job", str(nr), wire_kind(art), hex_von(wire_arg(art, arg1)), "0"], nutz)
            if a.abriss and nr == 1:
                say("ABRISS nach Auftrag", nr)
                try:
                    s.shutdown(socket.SHUT_RDWR)
                except Exception:
                    pass
                s.close()
                return 0
            f, inhalt = d.nachricht()
            if f[0] != "done":
                say("FEHLER unerwartet", " ".join(f))
                return 1
            dig = hashlib.sha256(inhalt).hexdigest()
            say("ANTWORT", f[1], art, STATUS_LOG.get(f[2], f[2]), len(inhalt), dig)
            with open("%s.%s.bin" % (a.aus, f[1]), "wb") as fh:
                fh.write(inhalt)
            if f[2] == "failed":
                say("GRUND", inhalt.decode("utf-8", "replace").strip())
        d.sende(["bye"])
        say("TSCHUESS")
    except (EOFError, socket.timeout, ConnectionResetError,
            ssl.SSLError, OSError) as e:
        say("ABGERISSEN", type(e).__name__)
    finally:
        try:
            s.close()
        except Exception:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
