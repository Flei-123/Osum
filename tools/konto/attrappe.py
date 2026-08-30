#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/konto/attrappe.py -- RUNDE KONTO: die Server im Testaufbau.

WARUM EIN NACHBAU UND NICHT DAS ECHTE SYSTEM. Xoffi gehoert einer
anderen Firma. Justin hat die Nutzung der API erlaubt; erlaubt ist nicht
dasselbe wie zumutbar. Ein Abschnitt, der zwanzigmal ein falsches
Passwort schickt, um die Bremse zu messen, ist ein Rateangriff auf ein
Produktivsystem, auch wenn er gut gemeint ist. Also ein Nachbau, der
GENAU die Antworten gibt, die der Betreiber beschrieben hat -- und gegen
das echte System nur ein einzelner, harmloser GET /api/health.

Der Nachbau ist ausserdem das einzige, womit sich die Faelle messen
lassen, auf die es ankommt: abgelaufenes Zwischentoken, dieselbe
E-Mail in zwei Organisationen, ein Token mit `master_session`, ein
abgelehntes Erneuern. An keinen davon kaeme man auf einem echten Server
heran, ohne ihn dafuer praeparieren zu lassen.

Drei Server in einem Programm, weil sie sich einen Anschluss teilen
duerfen -- der Pfad sagt, wer gemeint ist:

    /api/auth/...          Xoffi (die Beschreibung des Betreibers)
    /api/login|logout|me   JARVIS (aus server.js und lib/auth.js gelesen)
    /konto/...             der eigene Server (unser eigenes Protokoll)

JEDE ANFRAGE WIRD MITGESCHRIEBEN -- Methode, Pfad und ALLE Kopfzeilen --
nach <verzeichnis>/protokoll.jsonl. Daran misst der Laeufer, dass nie
ein Keks hinausging, wo keiner hingehoert, und dass das Token als
`Authorization: Bearer` kam.
"""
import argparse
import base64
import hashlib
import hmac
import json
import os
import ssl
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

GEHEIM = b"attrappe-geheimnis-nur-fuer-den-testaufbau"

# Die Konten des Nachbaus. `justin@example.test` gibt es ZWEIMAL -- in
# zwei Organisationen, mit VERSCHIEDENEN Daten. Das ist Fall (d) des
# Auftrags, und ohne zwei Eintraege waere er nicht messbar.
KONTEN = {
    ("justin@example.test", "alpha"): {
        "id": "1001", "username": "justin", "passwort": "richtig",
        "mfa": False, "daten": "alpha-geheimnis"},
    ("justin@example.test", "beta"): {
        "id": "2002", "username": "justin", "passwort": "richtig",
        "mfa": False, "daten": "beta-geheimnis"},
    ("mfa@example.test", "alpha"): {
        "id": "1003", "username": "mfamensch", "passwort": "richtig",
        "mfa": True, "daten": "alpha-geheimnis"},
    ("chef@example.test", "alpha"): {
        "id": "1004", "username": "chef", "passwort": "richtig",
        "mfa": False, "master": True, "daten": "alpha-geheimnis"},
    ("admin@example.test", "alpha"): {
        "id": "1005", "username": "adminmensch", "passwort": "richtig",
        "mfa": False, "is_admin": True, "nexus": True,
        "daten": "alpha-geheimnis"},
}

# JARVIS kennt keine Organisationen.
JARVIS = {"justin": "richtig", "zweiter": "auchrichtig"}

zustand = {
    "verzeichnis": ".",
    "gesperrt": set(),
    "fehlversuche": {},
    "temp": {},
    "refresh_verweigern": False,
    "access_sekunden": 604800,
    "sperre": threading.Lock(),
}


def b64u(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def jwt(payload):
    kopf = b64u(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    rumpf = b64u(json.dumps(payload).encode())
    daten = (kopf + "." + rumpf).encode()
    sig = b64u(hmac.new(GEHEIM, daten, hashlib.sha256).digest())
    return kopf + "." + rumpf + "." + sig


def jwt_lesen(tok):
    try:
        teile = tok.split(".")
        roh = teile[1] + "=" * (-len(teile[1]) % 4)
        return json.loads(base64.urlsafe_b64decode(roh))
    except Exception:
        return None


def protokoll(eintrag):
    pfad = os.path.join(zustand["verzeichnis"], "protokoll.jsonl")
    with zustand["sperre"]:
        with open(pfad, "a", encoding="utf-8") as f:
            f.write(json.dumps(eintrag) + "\n")


class Griff(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _koerper(self):
        n = int(self.headers.get("Content-Length") or 0)
        roh = self.rfile.read(n) if n else b""
        try:
            return json.loads(roh.decode() or "{}")
        except Exception:
            return {}

    def _antwort(self, code, obj, kekse=None):
        roh = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(roh)))
        for k in (kekse or []):
            self.send_header("Set-Cookie", k)
        self.end_headers()
        self.wfile.write(roh)

    def _mitschreiben(self):
        protokoll({
            "methode": self.command,
            "pfad": self.path,
            "kopfzeilen": {k.lower(): v for k, v in self.headers.items()},
            "zeit": time.time(),
        })

    def _bearer(self):
        h = self.headers.get("Authorization") or ""
        if h.lower().startswith("bearer "):
            return h[7:].strip()
        return None

    # Der Keks wird MITGESCHRIEBEN und von den Xoffi-Wegen ABSICHTLICH
    # NIE AUSGEWERTET. Ein Nachbau, der ihn akzeptiert, koennte nicht
    # messen, dass das Geraet ohne ihn auskommt.
    def do_GET(self):
        self._mitschreiben()
        p = self.path.split("?")[0]
        if p == "/api/auth/health":
            tok = self._bearer()
            if not tok or tok in zustand["gesperrt"]:
                return self._antwort(401, {"success": False,
                                           "detail": "kein Token"})
            return self._antwort(200, {"success": True, "status": "healthy"})
        if p == "/api/health":
            return self._antwort(200, {"success": True, "status": "healthy",
                                       "backend": {"framework": "FastAPI"}})
        if p == "/api/me":
            tok = self._bearer()
            if not tok:
                keks = self.headers.get("Cookie") or ""
                for teil in keks.split(";"):
                    if teil.strip().startswith("fleitec_session="):
                        tok = teil.strip()[16:]
            an = jwt_lesen(tok or "")
            if not an or (tok in zustand["gesperrt"]):
                return self._antwort(401, {"error": "Nicht angemeldet"})
            return self._antwort(200, {"username": an.get("name"),
                                       "admin": False})
        if p == "/konto/pruefen":
            tok = self._bearer()
            an = jwt_lesen(tok or "")
            if not an or tok in zustand["gesperrt"]:
                return self._antwort(401, {"fehler": "kein Token"})
            return self._antwort(200, {"gueltig": True})
        return self._antwort(404, {"fehler": "unbekannt"})

    def do_POST(self):
        self._mitschreiben()
        p = self.path.split("?")[0]
        b = self._koerper()
        if p == "/api/auth/login":
            return self.xoffi_login(b)
        if p == "/api/auth/mfa/verify":
            return self.xoffi_mfa(b)
        if p == "/api/auth/refresh":
            return self.xoffi_refresh(b)
        if p == "/api/auth/logout":
            tok = self._bearer()
            if tok:
                zustand["gesperrt"].add(tok)
            return self._antwort(200, {"success": True})
        if p == "/api/login":
            return self.jarvis_login(b)
        if p == "/api/logout":
            # JARVIS loescht NUR den Keks -- das ausgestellte JWT bleibt
            # gueltig. Der Nachbau tut dasselbe, damit der Bericht die
            # Wahrheit sagen kann und nicht die Wunschfassung.
            return self._antwort(200, {"ok": True})
        if p == "/konto/anmelden":
            return self.eigen_login(b)
        if p == "/konto/erneuern":
            return self.eigen_refresh(b)
        if p == "/konto/abmelden":
            tok = self._bearer()
            if tok:
                zustand["gesperrt"].add(tok)
            return self._antwort(200, {"ok": True})
        return self._antwort(404, {"fehler": "unbekannt"})

    # ------------------------------------------------------------- Xoffi
    def bremse(self, kennung):
        """Die Bremse. Sie sagt NICHT, ob es das Konto gibt -- gezaehlt
        wird der VERSUCH, nicht der Treffer."""
        jetzt = time.time()
        with zustand["sperre"]:
            liste = [t for t in zustand["fehlversuche"].get(kennung, [])
                     if jetzt - t < 60]
            zustand["fehlversuche"][kennung] = liste
            return len(liste) >= 10

    def fehlschlag(self, kennung):
        with zustand["sperre"]:
            zustand["fehlversuche"].setdefault(kennung, []).append(time.time())

    def _bremszeile(self, obj):
        self.send_response(429)
        self.send_header("Retry-After", "30")
        roh = json.dumps(obj).encode()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(roh)))
        self.end_headers()
        self.wfile.write(roh)

    def xoffi_login(self, b):
        kennung = b.get("login") or b.get("email") or ""
        org = b.get("organisation")
        if self.bremse(kennung):
            return self._bremszeile({"success": False,
                                     "detail": "zu viele Versuche"})
        treffer = [o for (k, o) in KONTEN if k == kennung]
        if not org:
            if len(treffer) > 1:
                # ES WIRD GEFRAGT. Genau hier waere Raten ein
                # Mandantenleck.
                return self._antwort(409, {"success": False,
                                           "organisations": sorted(treffer)})
            org = treffer[0] if treffer else "alpha"
        konto = KONTEN.get((kennung, org))
        if not konto or konto["passwort"] != (b.get("password") or ""):
            self.fehlschlag(kennung)
            # DIESELBE ANTWORT FUER "gibt es nicht" UND "falsches
            # Kennwort". Ein Unterschied waere ein Kontoverzeichnis.
            return self._antwort(401, {"success": False,
                                       "detail": "Anmeldung fehlgeschlagen"})
        if konto.get("mfa"):
            temp = b64u(os.urandom(12))
            zustand["temp"][temp] = (kennung, org, time.time() + 600)
            return self._antwort(200, {"success": True, "mfa_required": True,
                                       "temp_token": temp})
        return self.xoffi_sitzung(kennung, org, konto)

    def xoffi_sitzung(self, kennung, org, konto):
        jetzt = int(time.time())
        ansprueche = {
            "id": konto["id"], "email": kennung,
            "username": konto["username"], "organisation": org,
            "menu_group_id": 1, "is_admin": bool(konto.get("is_admin")),
            "nexus_core_access": bool(konto.get("nexus")),
            "nexus_developer": False, "type": "access",
            "iat": jetzt, "exp": jetzt + zustand["access_sekunden"],
        }
        if konto.get("master"):
            ansprueche["master_session"] = True
        zugriff = jwt(ansprueche)
        erneuerung = jwt({"id": konto["id"], "organisation": org,
                          "type": "refresh", "iat": jetzt,
                          "exp": jetzt + 2592000})
        antwort = {"success": True, "data": {
            "user": {"id": konto["id"], "email": kennung,
                     "username": konto["username"]},
            "token": zugriff, "refresh_token": erneuerung,
            "organisation": org, "domain": org + ".example.test"}}
        return self._antwort(200, antwort,
                             kekse=["xoffi_jwt=%s; HttpOnly; Path=/"
                                    % zugriff])

    def xoffi_mfa(self, b):
        temp = b.get("temp_token") or ""
        eintrag = zustand["temp"].get(temp)
        if not eintrag:
            return self._antwort(410, {"success": False,
                                       "detail": "temp_token unbekannt"})
        kennung, org, ablauf = eintrag
        if time.time() > ablauf:
            del zustand["temp"][temp]
            return self._antwort(410, {"success": False,
                                       "detail": "temp_token abgelaufen"})
        if (b.get("code") or "") != "123456":
            return self._antwort(401, {"success": False,
                                       "detail": "Code falsch"})
        del zustand["temp"][temp]
        return self.xoffi_sitzung(kennung, org, KONTEN[(kennung, org)])

    def xoffi_refresh(self, b):
        if zustand["refresh_verweigern"]:
            return self._antwort(401, {"success": False,
                                       "detail": "abgelehnt"})
        tok = b.get("refresh_token") or ""
        an = jwt_lesen(tok)
        if not an or an.get("type") != "refresh" or tok in zustand["gesperrt"]:
            return self._antwort(401, {"success": False,
                                       "detail": "kein Erneuerungstoken"})
        org = an.get("organisation")
        konto = None
        kennung = None
        for (k, o), v in KONTEN.items():
            if v["id"] == an.get("id") and o == org:
                konto, kennung = v, k
        if not konto:
            return self._antwort(401, {"success": False})
        return self.xoffi_sitzung(kennung, org, konto)

    # ------------------------------------------------------------ JARVIS
    def jarvis_login(self, b):
        name = (b.get("username") or "").strip()
        if self.bremse("jarvis:" + name):
            return self._bremszeile({"error": "Zu viele Fehlversuche."})
        if JARVIS.get(name) != (b.get("password") or ""):
            self.fehlschlag("jarvis:" + name)
            return self._antwort(401, {
                "error": "Falscher Benutzername oder Passwort"})
        jetzt = int(time.time())
        tok = jwt({"uid": "u_" + name, "name": name, "iat": jetzt,
                   "exp": jetzt + zustand["access_sekunden"]})
        return self._antwort(200, {"username": name, "token": tok},
                             kekse=["fleitec_session=%s; HttpOnly; Path=/"
                                    % tok])

    # ------------------------------------------------------------- eigen
    def eigen_login(self, b):
        kennung = b.get("kennung") or ""
        if JARVIS.get(kennung) != (b.get("geheim") or ""):
            return self._antwort(401, {"fehler": "falsch"})
        jetzt = int(time.time())
        tok = jwt({"uid": "e_" + kennung, "type": "access", "iat": jetzt,
                   "exp": jetzt + zustand["access_sekunden"]})
        erneu = jwt({"uid": "e_" + kennung, "type": "refresh", "iat": jetzt,
                     "exp": jetzt + 2592000})
        return self._antwort(200, {
            "subjekt": "e_" + kennung, "anzeige": kennung,
            "zugriff": tok, "erneuerung": erneu,
            "ablauf": jetzt + zustand["access_sekunden"],
            "datenort": "eigen"})

    def eigen_refresh(self, b):
        if zustand["refresh_verweigern"]:
            return self._antwort(401, {"fehler": "abgelehnt"})
        an = jwt_lesen(b.get("erneuerung") or "")
        if not an:
            return self._antwort(401, {"fehler": "kein Token"})
        jetzt = int(time.time())
        tok = jwt({"uid": an.get("uid"), "type": "access", "iat": jetzt,
                   "exp": jetzt + 604800})
        return self._antwort(200, {
            "subjekt": an.get("uid"), "anzeige": an.get("uid"),
            "zugriff": tok, "erneuerung": b.get("erneuerung"),
            "ablauf": jetzt + 604800, "datenort": "eigen"})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8443)
    ap.add_argument("--zertifikat")
    ap.add_argument("--schluessel")
    ap.add_argument("--verzeichnis", default=".")
    ap.add_argument("--kein-tls", action="store_true")
    ap.add_argument("--refresh-verweigern", action="store_true")
    ap.add_argument("--access-sekunden", type=int, default=604800)
    a = ap.parse_args()
    zustand["verzeichnis"] = a.verzeichnis
    zustand["refresh_verweigern"] = a.refresh_verweigern
    zustand["access_sekunden"] = a.access_sekunden
    srv = ThreadingHTTPServer(("0.0.0.0", a.port), Griff)
    if not a.kein_tls:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(a.zertifikat, a.schluessel)
        ctx.minimum_version = ssl.TLSVersion.TLSv1_3
        srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    sys.stderr.write("attrappe: bereit auf %d\n" % a.port)
    sys.stderr.flush()
    srv.serve_forever()


if __name__ == "__main__":
    main()
