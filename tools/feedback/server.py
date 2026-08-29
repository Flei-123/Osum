#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/feedback/server.py -- der Gegenpart zu `feedback.php`, zum Messen.

    server.py <cert.pem> <key.pem> <port> <ablage>

Nimmt POST auf /feedback.php an, liest den JSON-Rumpf, legt ihn unter
<ablage>/<n>.json ab und ein etwaiges Bild als <ablage>/<n>.png -- und
antwortet mit demselben Rumpf, den der echte Endpunkt antwortet:

    {"ok":true,"id":"..."}                       ohne Bild
    {"ok":true,"id":"...","image":true}          mit Bild

WARUM NICHT GEGEN DEN ECHTEN SERVER MESSEN. Weil eine Abnahme, die das
Internet braucht, keine Abnahme ist: sie ist rot, wenn jemand anderes
ein Kabel zieht. Der echte Endpunkt wird in einem eigenen Abschnitt
EINMAL zusaetzlich angefasst, und wenn er nicht da ist, wird der
Abschnitt uebersprungen und nicht rot.

Das hier ist bewusst DUMM: keine Begrenzung, keine Pruefung. Gemessen
wird, was Osum SENDET.
"""
import base64
import http.server
import json
import os
import ssl
import sys

CERT, KEY, PORT, ABLAGE = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
os.makedirs(ABLAGE, exist_ok=True)

# WEITERZAEHLEN, NICHT VON VORN. Der Testlauf legt den Netzraum zwischen
# Abschnitt 5 und 6 nieder und wieder auf, und damit startet auch dieser
# Server neu. Ein Zaehler, der bei 0 wieder anfaengt, hat die erste
# Meldung UEBERSCHRIEBEN -- die nachgereichte Meldung war da, sie lag nur
# unter dem Namen der ersten, und der Testlauf sah sie nicht mehr.
_da = [int(f.split(".")[0]) for f in os.listdir(ABLAGE)
       if f.split(".")[0].isdigit()]
ZAHL = [max(_da) if _da else 0]


class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(n)
        ZAHL[0] += 1
        k = ZAHL[0]
        with open(os.path.join(ABLAGE, f"{k}.raw"), "wb") as f:
            f.write(raw)
        with open(os.path.join(ABLAGE, f"{k}.head"), "w") as f:
            f.write(f"{self.command} {self.path}\n")
            for a, b in self.headers.items():
                f.write(f"{a}: {b}\n")
        antwort = {"ok": False, "error": "no json"}
        try:
            d = json.loads(raw.decode("utf-8"))
            with open(os.path.join(ABLAGE, f"{k}.json"), "w") as f:
                json.dump({a: (b if a != "image" else f"<{len(b)} Zeichen>")
                           for a, b in d.items()}, f, indent=1, ensure_ascii=False)
            antwort = {"ok": True, "id": f"{k:012x}"}
            if "image" in d:
                bild = base64.b64decode(d["image"], validate=True)
                with open(os.path.join(ABLAGE, f"{k}.png"), "wb") as f:
                    f.write(bild)
                antwort["image"] = True
        except Exception as e:  # noqa: BLE001
            antwort = {"ok": False, "error": str(e)[:120]}
        body = json.dumps(antwort).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        body = b'{"ok":false,"error":"POST only"}'
        self.send_response(405)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(CERT, KEY)
srv = http.server.HTTPServer(("0.0.0.0", PORT), H)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
srv.serve_forever()
