#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/anbfleitec/book.py -- mock address book for the broker swap (r115b).

    book.py --listen 127.0.0.1:18471 --jwks http://127.0.0.1:18470/oidc/jwks.json
            --issuer https://10.9.0.1:8443 --ctl DIR

Stands in for firnchat-web + fleikontakte in tools/anbfleitec/interop.sh. It
implements the SAME contract as FirnChat (docs/LOGIN-OIDC.md, "Broker-Token
gegen fkt1 tauschen"), including a REAL Ed25519 check against the JWKS of the
REAL broker (python3-cryptography):

  POST /api/kontakte/zugang-broker   Authorization: Bearer <access token>
       -> 200 {"token":"fkt1.<uid>.<64 hex>"}   or 401 {"error":"token refused"}
  GET  /api/kontakte/liste           Authorization: Bearer <that fkt1>
       -> 200 {"items":[...]}                   or 401

Checks (like fl_jwt in firnchat-web): alg exactly EdDSA, kid in the JWKS,
signature, iss exact, aud = wanted (a list only with azp = wanted), exp, nbf,
sub, jti REQUIRED (a broker id_token has none), the account (claim uid, else
sub) must already exist, an Origin header is refused (403, not for browsers).

The test steers it through files in --ctl (read on every request):
  aud       the audience wanted (default: orientos)
  clock     seconds added to "now" (default 0; 200000 = tokens are expired)
  accounts  comma separated accounts that exist (default: none)
It appends one line per swap/list to --ctl/book.log ("swap ok uid=..." or
"swap refused <reason>"); the reason never contains the token.
"""
import argparse
import base64
import json
import os
import secrets
import sys
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

ARGS = None
ISSUED = set()


def b64d(s):
    if not s or any(c not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_" for c in s):
        raise ValueError("base64url")
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def ctl(name, default=""):
    try:
        with open(os.path.join(ARGS.ctl, name)) as f:
            return f.read().strip()
    except OSError:
        return default


def log(line):
    with open(os.path.join(ARGS.ctl, "book.log"), "a") as f:
        f.write(line + "\n")


def verify(token):
    """Return (uid, None) or (None, reason)."""
    parts = token.split(".")
    if len(parts) != 3:
        return None, "not a JWT"
    try:
        hdr = json.loads(b64d(parts[0]))
        clm = json.loads(b64d(parts[1]))
        sig = b64d(parts[2])
    except (ValueError, json.JSONDecodeError):
        return None, "undecodable"
    if hdr.get("alg") != "EdDSA":
        return None, "alg"
    kid = hdr.get("kid")
    if not kid:
        return None, "no kid"
    try:
        with urllib.request.urlopen(ARGS.jwks, timeout=5) as r:
            keys = json.load(r)["keys"]
    except Exception:
        return None, "jwks unreachable"
    jwk = next((k for k in keys if k.get("kid") == kid and k.get("kty") == "OKP" and k.get("crv") == "Ed25519"), None)
    if jwk is None:
        return None, "unknown kid"
    try:
        Ed25519PublicKey.from_public_bytes(b64d(jwk["x"])).verify(sig, (parts[0] + "." + parts[1]).encode())
    except (InvalidSignature, ValueError, KeyError):
        return None, "signature"
    now = time.time() + float(ctl("clock", "0") or 0)
    want = ctl("aud", "orientos")
    if clm.get("iss") != ARGS.issuer:
        return None, "iss"
    aud = clm.get("aud")
    if isinstance(aud, list):
        if want not in aud or clm.get("azp") != want:
            return None, "aud"
    elif aud != want:
        return None, "aud"
    if not isinstance(clm.get("exp"), (int, float)) or clm["exp"] <= now:
        return None, "exp"
    if "nbf" in clm and clm["nbf"] > now:
        return None, "nbf"
    if not clm.get("sub"):
        return None, "sub"
    if not clm.get("jti"):
        return None, "jti"
    uid = clm.get("uid") or clm.get("sub")
    if uid not in [a for a in ctl("accounts").split(",") if a]:
        return None, "unknown account"
    return uid, None


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, *a):
        pass

    def send_json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def bearer(self):
        h = self.headers.get("Authorization", "")
        return h[7:] if h.startswith("Bearer ") else ""

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n:
            self.rfile.read(n)
        if self.path.split("?")[0] != "/api/kontakte/zugang-broker":
            return self.send_json(404, {"error": "not found"})
        if self.headers.get("Origin") is not None:
            log("swap refused origin")
            return self.send_json(403, {"error": "not for browsers"})
        tok = self.bearer()
        if not tok:
            log("swap refused no bearer")
            return self.send_json(401, {"error": "Bearer token needed"})
        uid, why = verify(tok)
        if why:
            log("swap refused " + why)
            return self.send_json(401, {"error": "token refused"})
        fkt = "fkt1.%s.%s" % (uid, secrets.token_hex(32))
        ISSUED.clear()  # a new swap replaces the old broker token
        ISSUED.add(fkt)
        with open(os.path.join(ARGS.ctl, "issued"), "w") as f:
            f.write(fkt + "\n")
        log("swap ok uid=" + uid)
        return self.send_json(200, {"token": fkt})

    def do_GET(self):
        if self.path.split("?")[0] != "/api/kontakte/liste":
            return self.send_json(404, {"error": "not found"})
        if self.bearer() not in ISSUED:
            log("list refused")
            return self.send_json(401, {"error": "token refused"})
        log("list ok")
        return self.send_json(200, {"items": [{"konto": "u_anna", "name": "Anna"}]})


def main():
    global ARGS
    ap = argparse.ArgumentParser()
    ap.add_argument("--listen", required=True)
    ap.add_argument("--jwks", required=True)
    ap.add_argument("--issuer", required=True)
    ap.add_argument("--ctl", required=True)
    ARGS = ap.parse_args()
    host, port = ARGS.listen.rsplit(":", 1)
    ThreadingHTTPServer((host, int(port)), H).serve_forever()


if __name__ == "__main__":
    sys.exit(main())
