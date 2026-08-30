#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/ota/server.py -- DIE GEGENSTELLE. Ein HTTPS-Dienst, der ein
signiertes Verzeichnis und Pakete ausliefert.

    server.py --wurzel <verz> --cert <pem> --key <pem> [--port 8443]
              [--abbruch <datei>:<oktette>] [--pid <datei>]
              [--log <datei>] [--einmal]

ES GIBT KEINEN ECHTEN UPDATE-SERVER IM INTERNET, gegen den diese Runde
messen koennte, und das wird hier ausdruecklich gesagt statt umschrieben:
GEMESSEN WIRD GEGEN DIESE GEGENSTELLE, einen lokalen HTTPS-Dienst auf
demselben Wirt. Was daran echt ist:

  * echtes TLS 1.3, ausgehandelt von Pythons `ssl` (OpenSSL) -- also von
    einer Umsetzung, die dieses Repository nicht geschrieben hat;
  * ein echtes Zertifikat mit einer echten Kette, die das Geraet gegen
    seinen Wurzelspeicher prueft;
  * echtes HTTP mit `Content-Length`, `Range`/`206 Partial Content` und
    echten Verbindungsabbruechen;
  * das Geraet spricht ueber eine echte Netzkarte (e1000) und QEMUs
    Benutzernetz, nicht ueber eine Abkuerzung.

Was daran NICHT echt ist: die Leitung ist kurz, die Uhr geht richtig, und
es gibt keinen Zwischenspeicher, keinen Lastverteiler und keine
Mehrfachnamen. Was fuer den Betrieb gegen einen Server im Internet noch
fehlt, steht am Ende von `docs/OTA.md`.

DIE SCHALTER, DIE ETWAS KAPUTT MACHEN, und sie sind der Grund fuer dieses
Programm (ein Server, der immer funktioniert, misst nichts):

  --abbruch <datei>:<oktette>
        Fuer diese Datei wird nur bis zur STELLE <oktette> DER DATEI
        geliefert, dann wird die Verbindung HART geschlossen (RST, kein
        `close_notify`, kein FIN mit Anstand). Das ist der Fall (c):
        mitten im Laden getrennt. `Content-Length` nennt vorher die volle
        Laenge -- der Abbruch ist damit fuer den Empfaenger erkennbar,
        und genau das muss er auch merken.

  --kurz <datei>:<oktette>
        Fuer diese Datei wird nur bis zur STELLE <oktette> DER DATEI
        geliefert und die Verbindung danach ORDENTLICH geschlossen -- der
        Empfaenger sieht ein sauberes Ende, aber weniger Oktette, als
        `Content-Length` angekuendigt hat. Das ist der zweite, mildere
        Abbruch: die Leitung ist gegangen, TCP hat aufgeraeumt, und das
        Bruchstueck liegt beim Empfaenger. Damit laesst sich die
        WIEDERAUFNAHME messen -- der harte Abbruch (--abbruch) laesst
        oft gar nichts zurueck, weil ein RST die Empfangswarteschlange
        mitnimmt.

  --einmal
        nach der ersten Antwort beenden.

WIEDERAUFNAHME. `Range: bytes=<n>-` wird beantwortet, mit `206` und
`Content-Range`. Ein Geraet, dem beim ersten Versuch die Leitung
abgerissen ist, holt damit nur den Rest. Ohne diese Zeile muesste ein
Update nach jedem Abbruch von vorn anfangen.
"""
import http.server
import os
import socket
import ssl
import sys
import threading
import time

WURZEL = "."
ABBRUCH = {}
KURZ = {}
LOG = None
EINMAL = False
GETAN = threading.Event()
ZAEHLER = {"anfragen": 0, "oktette": 0}


def protokoll(*w):
    zeile = " ".join(str(x) for x in w)
    if LOG:
        with open(LOG, "a") as f:
            f.write(zeile + "\n")
            f.flush()
    else:
        sys.stderr.write(zeile + "\n")
        sys.stderr.flush()


class Hand(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, *a):
        pass

    def _hart_zu(self):
        """Die Verbindung abreissen lassen, ohne `close_notify`.

        SO_LINGER mit Zeit 0 macht aus dem `close` ein RST. Ein sauberes
        Zumachen waere hier falsch: ein Empfaenger darf ein sauberes Ende
        als Ende des Rumpfes lesen duerfen. Was gemessen werden soll, ist
        ein RISS -- weniger Oktette als angekuendigt.
        """
        try:
            roh = self.connection
            sock = getattr(roh, "_sock", None) or roh
            import struct
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER,
                            struct.pack("ii", 1, 0))
        except Exception:
            pass
        try:
            self.connection.close()
        except Exception:
            pass

    def do_HEAD(self):
        self.do_GET(nur_kopf=True)

    def do_GET(self, nur_kopf=False):
        ZAEHLER["anfragen"] += 1
        pfad = self.path.split("?")[0]
        name = os.path.basename(pfad)
        datei = os.path.join(WURZEL, name)
        if not name or not os.path.isfile(datei):
            protokoll("404", pfad)
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return

        gesamt = os.path.getsize(datei)
        von = 0
        teil = False
        r = self.headers.get("Range")
        if r and r.startswith("bytes="):
            stueck = r[6:].split("-")[0].strip()
            if stueck.isdigit():
                von = int(stueck)
                teil = von > 0 and von < gesamt
                if von >= gesamt:
                    protokoll("416", name, "von", von, "von", gesamt)
                    self.send_response(416)
                    self.send_header("Content-Range", "bytes */%d" % gesamt)
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return

        laenge = gesamt - von
        grenze = ABBRUCH.get(name)
        self.send_response(206 if teil else 200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(laenge))
        if teil:
            self.send_header("Content-Range",
                             "bytes %d-%d/%d" % (von, gesamt - 1, gesamt))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        if nur_kopf:
            return

        geschrieben = 0
        kgrenze = KURZ.get(name)
        # DIE STELLE, AN DER DIE LEITUNG REISST, IST EINE STELLE IN DER
        # DATEI -- nicht eine Anzahl Oktette dieser einen Antwort. Sonst
        # kaeme ein Geraet, das ab 20000 wieder ansetzt, beim zweiten
        # Versuch einfach durch (13787 Oktett Rest sind ja weniger als
        # 20000), und die Gegenstelle waere nach einer Wiederaufnahme
        # heil -- eine Leitung, die von selbst besser wird, misst nichts.
        # Absolut gerechnet reisst sie IMMER an derselben Stelle, und
        # der erste Lauf scheitert wirklich.
        with open(datei, "rb") as f:
            f.seek(von)
            while geschrieben < laenge:
                stelle = von + geschrieben
                if kgrenze is not None and stelle >= kgrenze:
                    protokoll("KURZ", name, "bei", stelle,
                              "nach", geschrieben,
                              "von", laenge, "angekuendigt")
                    ZAEHLER["oktette"] += geschrieben
                    if EINMAL:
                        GETAN.set()
                    return
                if grenze is not None and stelle >= grenze:
                    protokoll("ABBRUCH", name, "bei", stelle,
                              "nach", geschrieben,
                              "von", laenge, "angekuendigt")
                    ZAEHLER["oktette"] += geschrieben
                    self._hart_zu()
                    if EINMAL:
                        GETAN.set()
                    return
                stueck = 4096
                if grenze is not None:
                    stueck = min(stueck, grenze - stelle)
                if kgrenze is not None:
                    stueck = min(stueck, kgrenze - stelle)
                stueck = min(stueck, laenge - geschrieben)
                b = f.read(stueck)
                if not b:
                    break
                try:
                    self.wfile.write(b)
                except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
                    protokoll("RISS", name, "nach", geschrieben)
                    return
                geschrieben += len(b)
        ZAEHLER["oktette"] += geschrieben
        protokoll("200" if not teil else "206", name, "von", von,
                  "laenge", geschrieben, "gesamt", gesamt)
        if EINMAL:
            GETAN.set()


def main():
    global WURZEL, LOG, EINMAL
    port = 8443
    cert = key = None
    pid = None
    i = 1
    while i < len(sys.argv):
        a = sys.argv[i]
        if a == "--wurzel" and i + 1 < len(sys.argv):
            i += 1
            WURZEL = sys.argv[i]
        elif a == "--cert" and i + 1 < len(sys.argv):
            i += 1
            cert = sys.argv[i]
        elif a == "--key" and i + 1 < len(sys.argv):
            i += 1
            key = sys.argv[i]
        elif a == "--port" and i + 1 < len(sys.argv):
            i += 1
            port = int(sys.argv[i])
        elif a == "--log" and i + 1 < len(sys.argv):
            i += 1
            LOG = sys.argv[i]
        elif a == "--pid" and i + 1 < len(sys.argv):
            i += 1
            pid = sys.argv[i]
        elif a == "--abbruch" and i + 1 < len(sys.argv):
            i += 1
            n, _, o = sys.argv[i].partition(":")
            ABBRUCH[n] = int(o)
        elif a == "--kurz" and i + 1 < len(sys.argv):
            i += 1
            n, _, o = sys.argv[i].partition(":")
            KURZ[n] = int(o)
        elif a == "--einmal":
            EINMAL = True
        else:
            print(__doc__)
            return 2
        i += 1
    if not cert or not key:
        print(__doc__)
        return 2

    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_3
    ctx.load_cert_chain(cert, key)
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", port), Hand)
    srv.daemon_threads = True
    srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    if pid:
        with open(pid, "w") as f:
            f.write(str(os.getpid()))
    protokoll("START port=%d wurzel=%s abbruch=%s kurz=%s"
              % (port, WURZEL, ABBRUCH or "-", KURZ or "-"))
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    try:
        while not GETAN.is_set():
            time.sleep(0.2)
    except KeyboardInterrupt:
        pass
    protokoll("ENDE anfragen=%d oktette=%d"
              % (ZAEHLER["anfragen"], ZAEHLER["oktette"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
