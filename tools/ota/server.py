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

ROOT = "."
NORANGE = False
ABBRUCH = {}
SHORT = {}
LOG = None
EINMAL = False
GETAN = threading.Event()
COUNTER = {"anfragen": 0, "oktette": 0}


def protokoll(*w):
    line = " ".join(str(x) for x in w)
    if LOG:
        with open(LOG, "a") as f:
            f.write(line + "\n")
            f.flush()
    else:
        sys.stderr.write(line + "\n")
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
        self.do_GET(only_header=True)

    def do_GET(self, only_header=False):
        COUNTER["anfragen"] += 1
        path_2 = self.path.split("?")[0]
        name = os.path.basename(path_2)
        file_2 = os.path.join(ROOT, name)
        rel = path_2.lstrip("/")
        if rel and ".." not in rel.split("/"):
            tief = os.path.join(ROOT, rel)
            if os.path.isfile(tief):
                file_2 = tief
                name = rel
        if not name or not os.path.isfile(file_2):
            protokoll("404", path_2)
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return

        gesamt = os.path.getsize(file_2)
        von = 0
        part = False
        r = None if NORANGE else self.headers.get("Range")
        if r and r.startswith("bytes="):
            chunk = r[6:].split("-")[0].strip()
            if chunk.isdigit():
                von = int(chunk)
                part = von > 0 and von < gesamt
                if von >= gesamt:
                    protokoll("416", name, "von", von, "von", gesamt)
                    self.send_response(416)
                    self.send_header("Content-Range", "bytes */%d" % gesamt)
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return

        len_2 = gesamt - von
        limit = ABBRUCH.get(name, ABBRUCH.get(os.path.basename(name)))
        self.send_response(206 if part else 200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len_2))
        if part:
            self.send_header("Content-Range",
                             "bytes %d-%d/%d" % (von, gesamt - 1, gesamt))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        if only_header:
            return

        geschrieben = 0
        kgrenze = SHORT.get(name, SHORT.get(os.path.basename(name)))
        with open(file_2, "rb") as f:
            f.seek(von)
            while geschrieben < len_2:
                pos = von + geschrieben
                if kgrenze is not None and pos >= kgrenze:
                    protokoll("KURZ", name, "bei", pos,
                              "nach", geschrieben,
                              "von", len_2, "angekuendigt")
                    COUNTER["oktette"] += geschrieben
                    if EINMAL:
                        GETAN.set()
                    return
                if limit is not None and pos >= limit:
                    protokoll("ABBRUCH", name, "bei", pos,
                              "nach", geschrieben,
                              "von", len_2, "angekuendigt")
                    COUNTER["oktette"] += geschrieben
                    self._hart_zu()
                    if EINMAL:
                        GETAN.set()
                    return
                chunk = 4096
                if limit is not None:
                    chunk = min(chunk, limit - pos)
                if kgrenze is not None:
                    chunk = min(chunk, kgrenze - pos)
                chunk = min(chunk, len_2 - geschrieben)
                b = f.read(chunk)
                if not b:
                    break
                try:
                    self.wfile.write(b)
                except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
                    protokoll("RISS", name, "nach", geschrieben)
                    return
                geschrieben += len(b)
        COUNTER["oktette"] += geschrieben
        protokoll("200" if not part else "206", name, "von", von,
                  "laenge", geschrieben, "gesamt", gesamt)
        if EINMAL:
            GETAN.set()


def main():
    global ROOT, LOG, EINMAL, NORANGE
    port = 8443
    cert = key = None
    pid = None
    i = 1
    while i < len(sys.argv):
        a = sys.argv[i]
        if a == "--wurzel" and i + 1 < len(sys.argv):
            i += 1
            ROOT = sys.argv[i]
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
            SHORT[n] = int(o)
        elif a == "--norange":
            NORANGE = True
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
              % (port, ROOT, ABBRUCH or "-", SHORT or "-"))
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    try:
        while not GETAN.is_set():
            time.sleep(0.2)
    except KeyboardInterrupt:
        pass
    protokoll("ENDE anfragen=%d oktette=%d"
              % (COUNTER["anfragen"], COUNTER["oktette"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
