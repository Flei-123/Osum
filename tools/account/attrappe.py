#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
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

SECRET = b"attrappe-geheimnis-nur-fuer-den-testaufbau"

ACCOUNTS = {
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

JARVIS = {"justin": "richtig", "zweiter": "auchrichtig"}

state = {
    "verzeichnis": ".",
    "gesperrt": set(),
    "fehlversuche": {},
    "temp": {},
    "refresh_verweigern": False,
    "own_new_keys": False,
    "own_old_only": False,
    "access_sekunden": 604800,
    "sperre": threading.Lock(),
}


def b64u(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def jwt(payload):
    header = b64u(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    body = b64u(json.dumps(payload).encode())
    data = (header + "." + body).encode()
    sig = b64u(hmac.new(SECRET, data, hashlib.sha256).digest())
    return header + "." + body + "." + sig


def jwt_read(tok):
    try:
        parts = tok.split(".")
        roh = parts[1] + "=" * (-len(parts[1]) % 4)
        return json.loads(base64.urlsafe_b64decode(roh))
    except Exception:
        return None


def protokoll(entry):
    path_2 = os.path.join(state["verzeichnis"], "protokoll.jsonl")
    with state["sperre"]:
        with open(path_2, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")


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

    def _reply(self, code, obj, kekse=None):
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

    def do_GET(self):
        self._mitschreiben()
        p = self.path.split("?")[0]
        if p == "/api/auth/health":
            tok = self._bearer()
            if not tok or tok in state["gesperrt"]:
                return self._reply(401, {"success": False,
                                           "detail": "kein Token"})
            return self._reply(200, {"success": True, "status": "healthy"})
        if p == "/api/health":
            return self._reply(200, {"success": True, "status": "healthy",
                                       "backend": {"framework": "FastAPI"}})
        if p == "/api/me":
            tok = self._bearer()
            if not tok:
                cookie = self.headers.get("Cookie") or ""
                for part in cookie.split(";"):
                    if part.strip().startswith("fleitec_session="):
                        tok = part.strip()[16:]
            an = jwt_read(tok or "")
            if not an or (tok in state["gesperrt"]):
                return self._reply(401, {"error": "Nicht angemeldet"})
            return self._reply(200, {"username": an.get("name"),
                                       "admin": False})
        p = self.own_path(p)
        if p == "/konto/pruefen":
            tok = self._bearer()
            an = jwt_read(tok or "")
            if not an or tok in state["gesperrt"]:
                return self._reply(401, {"fehler": "kein Token"})
            return self._reply(200, {"gueltig": True})
        return self._reply(404, {"fehler": "unbekannt"})

    def do_POST(self):
        self._mitschreiben()
        p = self.path.split("?")[0]
        b = self._koerper()
        p = self.own_path(p)
        if p == "/api/auth/login":
            return self.xoffi_login(b)
        if p == "/api/auth/mfa/verify":
            return self.xoffi_mfa(b)
        if p == "/api/auth/refresh":
            return self.xoffi_refresh(b)
        if p == "/api/auth/logout":
            tok = self._bearer()
            if tok:
                state["gesperrt"].add(tok)
            return self._reply(200, {"success": True})
        if p == "/api/login":
            return self.jarvis_login(b)
        if p == "/api/logout":
            return self._reply(200, {"ok": True})
        if p == "/konto/anmelden":
            return self.own_login(b)
        if p == "/konto/erneuern":
            return self.own_refresh(b)
        if p == "/konto/abmelden":
            tok = self._bearer()
            if tok:
                state["gesperrt"].add(tok)
            return self._reply(200, {"ok": True})
        return self._reply(404, {"fehler": "unbekannt"})

    def own_path(self, p):
        names = {"/account/login": "/konto/anmelden",
                 "/account/renew": "/konto/erneuern",
                 "/account/logout": "/konto/abmelden",
                 "/account/check": "/konto/pruefen"}
        if p in names:
            return "/unknown" if state["own_old_only"] else names[p]
        return p

    def bremse(self, kennung):
        now = time.time()
        with state["sperre"]:
            list_2 = [t for t in state["fehlversuche"].get(kennung, [])
                     if now - t < 60]
            state["fehlversuche"][kennung] = list_2
            return len(list_2) >= 10

    def fehlschlag(self, kennung):
        with state["sperre"]:
            state["fehlversuche"].setdefault(kennung, []).append(time.time())

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
        treffer = [o for (k, o) in ACCOUNTS if k == kennung]
        if not org:
            if len(treffer) > 1:
                return self._reply(409, {"success": False,
                                           "organisations": sorted(treffer)})
            org = treffer[0] if treffer else "alpha"
        account = ACCOUNTS.get((kennung, org))
        if not account or account["passwort"] != (b.get("password") or ""):
            self.fehlschlag(kennung)
            return self._reply(401, {"success": False,
                                       "detail": "Anmeldung fehlgeschlagen"})
        if account.get("mfa"):
            temp = b64u(os.urandom(12))
            state["temp"][temp] = (kennung, org, time.time() + 600)
            return self._reply(200, {"success": True, "mfa_required": True,
                                       "temp_token": temp})
        return self.xoffi_session(kennung, org, account)

    def xoffi_session(self, kennung, org, account):
        now = int(time.time())
        claims = {
            "id": account["id"], "email": kennung,
            "username": account["username"], "organisation": org,
            "menu_group_id": 1, "is_admin": bool(account.get("is_admin")),
            "nexus_core_access": bool(account.get("nexus")),
            "nexus_developer": False, "type": "access",
            "iat": now, "exp": now + state["access_sekunden"],
        }
        if account.get("master"):
            claims["master_session"] = True
        zugriff = jwt(claims)
        erneuerung = jwt({"id": account["id"], "organisation": org,
                          "type": "refresh", "iat": now,
                          "exp": now + 2592000})
        reply = {"success": True, "data": {
            "user": {"id": account["id"], "email": kennung,
                     "username": account["username"]},
            "token": zugriff, "refresh_token": erneuerung,
            "organisation": org, "domain": org + ".example.test"}}
        return self._reply(200, reply,
                             kekse=["xoffi_jwt=%s; HttpOnly; Path=/"
                                    % zugriff])

    def xoffi_mfa(self, b):
        temp = b.get("temp_token") or ""
        entry = state["temp"].get(temp)
        if not entry:
            return self._reply(410, {"success": False,
                                       "detail": "temp_token unbekannt"})
        kennung, org, ablauf = entry
        if time.time() > ablauf:
            del state["temp"][temp]
            return self._reply(410, {"success": False,
                                       "detail": "temp_token abgelaufen"})
        if (b.get("code") or "") != "123456":
            return self._reply(401, {"success": False,
                                       "detail": "Code falsch"})
        del state["temp"][temp]
        return self.xoffi_session(kennung, org, ACCOUNTS[(kennung, org)])

    def xoffi_refresh(self, b):
        if state["refresh_verweigern"]:
            return self._reply(401, {"success": False,
                                       "detail": "abgelehnt"})
        tok = b.get("refresh_token") or ""
        an = jwt_read(tok)
        if not an or an.get("type") != "refresh" or tok in state["gesperrt"]:
            return self._reply(401, {"success": False,
                                       "detail": "kein Erneuerungstoken"})
        org = an.get("organisation")
        account = None
        kennung = None
        for (k, o), v in ACCOUNTS.items():
            if v["id"] == an.get("id") and o == org:
                account, kennung = v, k
        if not account:
            return self._reply(401, {"success": False})
        return self.xoffi_session(kennung, org, account)

    def jarvis_login(self, b):
        name = (b.get("username") or "").strip()
        if self.bremse("jarvis:" + name):
            return self._bremszeile({"error": "Zu viele Fehlversuche."})
        if JARVIS.get(name) != (b.get("password") or ""):
            self.fehlschlag("jarvis:" + name)
            return self._reply(401, {
                "error": "Falscher Benutzername oder Passwort"})
        now = int(time.time())
        tok = jwt({"uid": "u_" + name, "name": name, "iat": now,
                   "exp": now + state["access_sekunden"]})
        return self._reply(200, {"username": name, "token": tok},
                             kekse=["fleitec_session=%s; HttpOnly; Path=/"
                                    % tok])

    def own_login(self, b):
        protokoll({"pfad": "own-body", "kopfzeilen": {},
                   "keys": sorted(b.keys())})
        if state["own_old_only"]:
            kennung = b.get("kennung") or ""
            given_secret = b.get("geheim") or ""
        else:
            kennung = b.get("identity") or b.get("kennung") or ""
            given_secret = b.get("secret") or b.get("geheim") or ""
        if JARVIS.get(kennung) != given_secret:
            return self._reply(401, {"fehler": "falsch"})
        now = int(time.time())
        tok = jwt({"uid": "e_" + kennung, "type": "access", "iat": now,
                   "exp": now + state["access_sekunden"]})
        erneu = jwt({"uid": "e_" + kennung, "type": "refresh", "iat": now,
                     "exp": now + 2592000})
        if state["own_new_keys"]:
            return self._reply(200, {
                "subject": "e_" + kennung, "display_name": kennung,
                "access": tok, "renewal": erneu,
                "expires_at": now + state["access_sekunden"],
                "data_home": "eigen"})
        return self._reply(200, {
            "subjekt": "e_" + kennung, "anzeige": kennung,
            "zugriff": tok, "erneuerung": erneu,
            "ablauf": now + state["access_sekunden"],
            "datenort": "eigen"})

    def own_refresh(self, b):
        protokoll({"pfad": "own-body", "kopfzeilen": {},
                   "keys": sorted(b.keys())})
        if state["refresh_verweigern"]:
            return self._reply(401, {"fehler": "abgelehnt"})
        an = jwt_read(b.get("renewal") or b.get("erneuerung") or "")
        if not an:
            return self._reply(401, {"fehler": "kein Token"})
        now = int(time.time())
        tok = jwt({"uid": an.get("uid"), "type": "access", "iat": now,
                   "exp": now + 604800})
        return self._reply(200, {
            "subjekt": an.get("uid"), "anzeige": an.get("uid"),
            "zugriff": tok, "erneuerung": b.get("renewal") or b.get("erneuerung"),
            "ablauf": now + 604800, "datenort": "eigen"})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8443)
    ap.add_argument("--zertifikat")
    ap.add_argument("--key")
    ap.add_argument("--directory", default=".")
    ap.add_argument("--kein-tls", action="store_true")
    ap.add_argument("--own-new-keys", action="store_true")
    ap.add_argument("--own-old-only", action="store_true")
    ap.add_argument("--refresh-verweigern", action="store_true")
    ap.add_argument("--access-secs", type=int, default=604800)
    a = ap.parse_args()
    state["verzeichnis"] = a.directory
    state["refresh_verweigern"] = a.refresh_verweigern
    state["own_new_keys"] = a.own_new_keys
    state["own_old_only"] = a.own_old_only
    state["access_sekunden"] = a.access_secs
    srv = ThreadingHTTPServer(("0.0.0.0", a.port), Griff)
    if not a.kein_tls:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(a.zertifikat, a.key)
        ctx.minimum_version = ssl.TLSVersion.TLSv1_3
        srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    sys.stderr.write("attrappe: bereit auf %d\n" % a.port)
    sys.stderr.flush()
    srv.serve_forever()


if __name__ == "__main__":
    main()
