#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/anbfleitec/approve.py -- the human at the other device, in code.

    approve.py <issuer> <ca.pem> <user_code> <allow|deny> [user] [password]

Does what a browser does against fleitec-id: open the confirm page, get sent
to the login page, sign in (form + CSRF cookie + Origin), confirm or refuse
the device code. Prints the title of the final page. Exit 0 if the page
title is "Device connected" (allow) or "Cancelled" (deny).
"""
import http.cookiejar
import re
import ssl
import sys
import urllib.parse
import urllib.request


def main():
    issuer, ca, code, decision = sys.argv[1:5]
    user = sys.argv[5] if len(sys.argv) > 5 else "justin"
    pw = sys.argv[6] if len(sys.argv) > 6 else "test-password-1"
    ctx = ssl.create_default_context(cafile=ca)
    ctx.check_hostname = False  # the CA vouches for the name konto.test, the URL is an IP
    jar = http.cookiejar.CookieJar()
    op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar),
                                     urllib.request.HTTPSHandler(context=ctx))
    origin = issuer.rstrip("/")

    def get(path):
        r = op.open(origin + path, timeout=15)
        return r.geturl(), r.read().decode("utf-8", "replace")

    def post(path, form):
        req = urllib.request.Request(origin + path, urllib.parse.urlencode(form).encode(),
                                     {"Origin": origin, "Referer": origin + path})
        r = op.open(req, timeout=15)
        return r.geturl(), r.read().decode("utf-8", "replace")

    def hidden(html, name):
        m = re.search(r'name="%s" value="([^"]*)"' % name, html)
        return m.group(1) if m else ""

    confirm = "/oidc/device/confirm?user_code=" + urllib.parse.quote(code)
    url, html = get(confirm)
    if "/oidc/login" in url:
        ret = hidden(html, "return")
        url, html = post("/oidc/login", {"csrf": hidden(html, "csrf"), "return": ret,
                                          "username": user, "password": pw})
        if "/oidc/device/confirm" not in url:
            url, html = get(confirm)
    csrf = hidden(html, "csrf")
    if not csrf:
        print("no confirm page:", re.sub(r"<[^>]+>", " ", html)[:120].strip())
        sys.exit(2)
    _, html = post("/oidc/device/decision", {"csrf": csrf, "user_code": code,
                                             "decision": "allow" if decision == "allow" else "deny"})
    title = re.search(r"<h1>([^<]*)</h1>", html)
    title = title.group(1) if title else "?"
    print(title)
    sys.exit(0 if title == ("Device connected" if decision == "allow" else "Cancelled") else 1)


if __name__ == "__main__":
    main()
