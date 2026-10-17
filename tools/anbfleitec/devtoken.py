#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/anbfleitec/devtoken.py -- a device sign-in at the broker WITHOUT a guest.

    devtoken.py <issuer> <ca.pem> <client_id> <scope> <out-prefix>

Runs the device flow like OrientOS does (device_authorization, "the person" confirms
with approve.py, token poll) and writes the broker's answer to <out-prefix>.access,
<out-prefix>.id and <out-prefix>.refresh (one value per file, no newline). interop-real.sh
uses it to get as many fresh access tokens as it needs (the address book will take a token only once).
"""
import json
import os
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def main():
    issuer, ca, client, scope, out = sys.argv[1:6]
    ctx = ssl.create_default_context(cafile=ca)
    ctx.check_hostname = False
    here = os.path.dirname(os.path.abspath(__file__))

    def post(path, form):
        req = urllib.request.Request(issuer.rstrip("/") + path, urllib.parse.urlencode(form).encode())
        try:
            r = urllib.request.urlopen(req, timeout=15, context=ctx)
            return json.loads(r.read())
        except urllib.error.HTTPError as e:
            return json.loads(e.read() or b"{}")

    da = post("/oidc/device_authorization", {"client_id": client, "scope": scope})
    if "user_code" not in da:
        print("device_authorization failed:", da)
        sys.exit(2)
    p = subprocess.run([sys.executable, "-I", os.path.join(here, "approve.py"), issuer, ca, da["user_code"], "allow"],
                       capture_output=True, text=True)
    if p.returncode != 0:
        print("approve failed:", p.stdout.strip(), p.stderr.strip())
        sys.exit(3)
    for _ in range(40):
        t = post("/oidc/token", {"grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                                 "client_id": client, "device_code": da["device_code"]})
        if "access_token" in t:
            for k, ext in (("access_token", "access"), ("id_token", "id"), ("refresh_token", "refresh")):
                with open(out + "." + ext, "w") as f:
                    f.write(t.get(k, ""))
            print("ok")
            return
        if t.get("error") not in ("authorization_pending", "slow_down"):
            print("token failed:", t)
            sys.exit(4)
        time.sleep(1.2)
    print("token poll timed out")
    sys.exit(5)


if __name__ == "__main__":
    main()
