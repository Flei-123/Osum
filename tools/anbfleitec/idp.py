#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/anbfleitec/idp.py -- mock Fleitec-ID (OIDC, device flow) for run.sh.

A stand-in for the real service (fleitec-id, projects/.../fleitec-id), so that
cases can be forced that a real server never produces on request: a token with
the wrong issuer, an HS256 token MACed with the public key, a flipped
signature, an id_token naming another subject, a dead refresh token.

Speaks HTTPS (TLS 1.3, like tools/account/attrappe.py) and answers exactly the
paths kernel/app/anb_fleitec.fi uses:

    POST /oidc/device_authorization   client_id, scope
    POST /oidc/token                  device_code | refresh_token grant
    POST /oidc/revoke                 token, token_type_hint
    GET  /oidc/userinfo               Authorization: Bearer
    GET  /oidc/jwks.json

SCENARIO = the content of <dir>/szenario, read at every device_authorization
and baked into the device code ("dc-<scenario>-<n>"). Scenarios:

    approve     pending, pending, then valid tokens
    slowdown    slow_down, pending, then valid tokens
    deny        pending, then access_denied
    expired     pending, then expired_token
    bad_iss     valid shape, iss has a trailing slash
    bad_aud     aud is another product
    hs256       alg HS256, MAC key = raw public key bytes (key confusion)
    algnone     alg none, empty signature
    exp_old     exp in the past
    bad_sig     one bit of the signature flipped
    bad_kid     kid not in the JWKS
    id_other    access token fine, id_token names another sub
    norefresh   fine, but refresh answers carry no new refresh token

Times are issued relative to the HOST clock (the guest reads the wall clock).
Every request (method, path, headers, form body) goes to <dir>/protokoll.jsonl.
The tokens handed out are written to <dir>/refresh.txt and <dir>/access.txt
(host side only, so run.sh can search the disk image for them).
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
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization

KID = "test-key-A"
CLIENT = "orientos-device"
AUD = "orientos"
SUB = "0b6f1c1e-5a7e-4d2c-9a4b-2f1d3c4b5a69"
OTHER_SUB = "11111111-2222-4333-8444-555555555555"

KEY = Ed25519PrivateKey.from_private_bytes(bytes(range(32)))
PUB = KEY.public_key().public_bytes(
    serialization.Encoding.Raw, serialization.PublicFormat.Raw)

state = {
    "dir": ".",
    "issuer": "",
    "interval": 1,
    "lock": threading.Lock(),
    "n": 0,
    "devices": {},      # device_code -> {"scen", "polls"}
    "refresh": {},      # refresh_token -> {"fam", "alive"}
    "fam_dead": set(),
    "revoked": set(),
    "access_ttl": 3600,
}


def b64u(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def jwt_make(header, payload, sig=None, mac=None):
    h = b64u(json.dumps(header, separators=(",", ":")).encode())
    p = b64u(json.dumps(payload, separators=(",", ":")).encode())
    inp = (h + "." + p).encode()
    if mac is not None:
        s = hmac.new(mac, inp, hashlib.sha256).digest()
    elif sig == "none":
        s = b""
    else:
        s = KEY.sign(inp)
        if sig == "flip":
            s = bytes([s[0] ^ 1]) + s[1:]
    return h + "." + p + "." + b64u(s)


def tokens_for(scen, aud_default=True):
    now = int(time.time())
    iss = state["issuer"]
    claims = {"iss": iss, "aud": AUD, "sub": SUB, "acc": SUB,
              "uid": "u_TESTuser0001", "name": "Justin",
              "iat": now, "exp": now + state["access_ttl"]}
    idc = dict(claims)
    idc["aud"] = CLIENT
    hdr = {"alg": "EdDSA", "typ": "JWT", "kid": KID}
    sig = None
    mac = None
    if scen == "bad_iss":
        claims["iss"] = iss + "/"
    elif scen == "bad_aud":
        claims["aud"] = "some-other-product"
    elif scen == "hs256":
        hdr["alg"] = "HS256"
        mac = PUB
    elif scen == "algnone":
        hdr["alg"] = "none"
        sig = "none"
    elif scen == "exp_old":
        claims["exp"] = now - 3600
    elif scen == "bad_sig":
        sig = "flip"
    elif scen == "bad_kid":
        hdr["kid"] = "test-key-X"
    elif scen == "id_other":
        idc["sub"] = OTHER_SUB
    access = jwt_make(hdr, claims, sig=sig, mac=mac)
    idt = jwt_make({"alg": "EdDSA", "typ": "JWT", "kid": KID}, idc)
    return access, idt, claims["exp"] - now


def log(entry):
    with state["lock"]:
        with open(os.path.join(state["dir"], "protokoll.jsonl"), "a",
                  encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _form(self):
        n = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(n) if n else b""
        return raw, {k: v[0] for k, v in urllib.parse.parse_qs(
            raw.decode("utf-8", "replace"), keep_blank_values=True).items()}

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _log(self, form=None):
        log({"t": time.time(), "metode": self.command, "pfad": self.path,
             "kopfzeilen": {k.lower(): v for k, v in self.headers.items()},
             "form": form})

    def do_GET(self):
        self._log()
        if self.path == "/oidc/jwks.json":
            self._send(200, {"keys": [{"kty": "OKP", "crv": "Ed25519",
                "alg": "EdDSA", "use": "sig", "kid": KID, "x": b64u(PUB)}]})
        elif self.path == "/oidc/userinfo":
            a = self.headers.get("Authorization", "")
            if not a.startswith("Bearer ") or a[7:] in state["revoked"]:
                self._send(401, {"error": "invalid_token"})
            else:
                self._send(200, {"sub": SUB, "name": "Justin"})
        else:
            self._send(404, {"error": "not_found"})

    def do_POST(self):
        raw, f = self._form()
        ct = self.headers.get("Content-Type", "")
        self._log({k: ("<secret>" if k in ("refresh_token", "token") else v)
                   for k, v in f.items()})
        if not ct.startswith("application/x-www-form-urlencoded"):
            self._send(400, {"error": "invalid_request"})
            return
        if self.path == "/oidc/device_authorization":
            return self.device(f)
        if self.path == "/oidc/token":
            return self.token(f)
        if self.path == "/oidc/revoke":
            return self.revoke(f)
        self._send(404, {"error": "not_found"})

    def device(self, f):
        if f.get("client_id") != CLIENT:
            self._send(400, {"error": "invalid_client"})
            return
        try:
            scen = open(os.path.join(state["dir"], "szenario"),
                        encoding="utf-8").read().strip() or "approve"
        except OSError:
            scen = "approve"
        with state["lock"]:
            state["n"] += 1
            dc = "dc-%s-%d" % (scen, state["n"])
            state["devices"][dc] = {"scen": scen, "polls": 0}
        self._send(200, {
            "device_code": dc, "user_code": "ABCD-EFGH",
            "verification_uri": state["issuer"] + "/device",
            "verification_uri_complete":
                state["issuer"] + "/device?user_code=ABCD-EFGH",
            "expires_in": 600, "interval": state["interval"]})

    def token(self, f):
        g = f.get("grant_type", "")
        if g == "urn:ietf:params:oauth:grant-type:device_code":
            return self.token_device(f)
        if g == "refresh_token":
            return self.token_refresh(f)
        self._send(400, {"error": "unsupported_grant_type"})

    def issue(self, scen, fam):
        access, idt, ttl = tokens_for(scen)
        with open(os.path.join(state["dir"], "access.txt"), "a",
                  encoding="utf-8") as fh:
            fh.write(access + "\n")
        out = {"access_token": access, "id_token": idt,
               "token_type": "Bearer", "expires_in": ttl}
        if scen != "norefresh" or fam is None:
            rt = "rt-" + b64u(os.urandom(24))
            with state["lock"]:
                state["refresh"][rt] = {"fam": fam or rt, "alive": True,
                                        "scen": scen}
            out["refresh_token"] = rt
            with open(os.path.join(state["dir"], "refresh.txt"), "a",
                      encoding="utf-8") as fh:
                fh.write(rt + "\n")
        return out

    def token_device(self, f):
        dc = f.get("device_code", "")
        with state["lock"]:
            d = state["devices"].get(dc)
            if d is None:
                self._send(400, {"error": "invalid_grant"})
                return
            d["polls"] += 1
            n = d["polls"]
            scen = d["scen"]
        if scen == "slowdown":
            if n == 1:
                return self._send(400, {"error": "slow_down"})
            if n == 2:
                return self._send(400, {"error": "authorization_pending"})
        elif scen in ("deny", "expired"):
            if n < 2:
                return self._send(400, {"error": "authorization_pending"})
            return self._send(400, {"error": "access_denied" if scen == "deny"
                                    else "expired_token"})
        elif n <= 2:
            return self._send(400, {"error": "authorization_pending"})
        with state["lock"]:
            state["devices"].pop(dc, None)   # a device code is single use
        self._send(200, self.issue(scen, None))

    def token_refresh(self, f):
        rt = f.get("refresh_token", "")
        with state["lock"]:
            e = state["refresh"].get(rt)
            if e is None or e["fam"] in state["fam_dead"]:
                self._send(400, {"error": "invalid_grant"})
                return
            if not e["alive"]:
                # replay of a rotated token: the whole family dies
                state["fam_dead"].add(e["fam"])
                self._send(400, {"error": "invalid_grant"})
                return
            e["alive"] = False
            fam, scen = e["fam"], e["scen"]
        self._send(200, self.issue(scen, fam))

    def revoke(self, f):
        rt = f.get("token", "")
        with state["lock"]:
            e = state["refresh"].get(rt)
            if e is not None:
                state["fam_dead"].add(e["fam"])
        self._send(200, {})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8443)
    ap.add_argument("--zertifikat", required=True)
    ap.add_argument("--schluessel", required=True)
    ap.add_argument("--verzeichnis", default=".")
    ap.add_argument("--issuer", required=True,
                    help="e.g. https://10.9.0.1:8443 (no trailing slash)")
    ap.add_argument("--interval", type=int, default=1)
    ap.add_argument("--access-ttl", type=int, default=3600)
    a = ap.parse_args()
    state["dir"] = a.verzeichnis
    state["issuer"] = a.issuer.rstrip("/")
    state["interval"] = a.interval
    state["access_ttl"] = a.access_ttl
    srv = ThreadingHTTPServer(("0.0.0.0", a.port), H)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(a.zertifikat, a.schluessel)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_3
    srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    sys.stderr.write("idp: ready on %d\n" % a.port)
    sys.stderr.flush()
    srv.serve_forever()


if __name__ == "__main__":
    main()
