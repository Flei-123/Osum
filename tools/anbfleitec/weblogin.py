#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/anbfleitec/weblogin.py -- the person's BROWSER login at firnchat-web via the broker.

    weblogin.py <web-base> <issuer> <ca.pem> [user] [password]

GET <web-base>/api/oidc/start, follow the redirects to the broker (https, own CA), sign in
(form + CSRF + Origin), allow the consent, come back to firnchat-web. Exit 0 and "ok" if the
session cookie fc_sess was set -- that login is what CREATES the account jarvis:<uid>
(auto-konto = ja), which `zugang-broker` needs (it never creates one).
"""
import html as htmllib
import http.cookiejar
import re
import ssl
import sys
import urllib.parse
import urllib.request


def main():
    web, issuer, ca = sys.argv[1:4]
    user = sys.argv[4] if len(sys.argv) > 4 else "justin"
    pw = sys.argv[5] if len(sys.argv) > 5 else "test-password-1"
    ctx = ssl.create_default_context(cafile=ca)
    ctx.check_hostname = False
    jar = http.cookiejar.CookieJar()
    op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar), urllib.request.HTTPSHandler(context=ctx))
    origin = issuer.rstrip("/")

    def hidden(html, name):
        m = re.search(r'name="%s" value="([^"]*)"' % name, html)
        return htmllib.unescape(m.group(1)) if m else ""

    def post(path, form):
        req = urllib.request.Request(origin + path, urllib.parse.urlencode(form).encode(),
                                     {"Origin": origin, "Referer": origin + path})
        r = op.open(req, timeout=20)
        return r.geturl(), r.read().decode("utf-8", "replace")

    r = op.open(web.rstrip("/") + "/api/oidc/start", timeout=20)
    url, html = r.geturl(), r.read().decode("utf-8", "replace")
    for _ in range(6):
        path = urllib.parse.urlparse(url).path
        if path == "/oidc/login":
            url, html = post("/oidc/login", {"csrf": hidden(html, "csrf"), "return": hidden(html, "return"),
                                              "username": user, "password": pw})
        elif path == "/oidc/consent":
            url, html = post("/oidc/consent", {"csrf": hidden(html, "csrf"), "return": hidden(html, "return"),
                                                "decision": "allow"})
        else:
            break
    if any(c.name == "fc_sess" for c in jar):
        print("ok")
        return
    print("no session; ended at", url, re.sub(r"<[^>]+>", " ", html)[:100].strip())
    sys.exit(1)


if __name__ == "__main__":
    main()
