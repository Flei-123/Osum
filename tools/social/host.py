#!/usr/bin/env python3
# tools/social/host.py -- the Fleitec side of tools/social/run.sh.
#
#   host.py setup <port> <secret> <workdir>   -> prints the device token
#   host.py watch <port> <secret> <serial> <out>
#
# setup: justin, anna, bert, carla and dora get profiles; anna and bert
# are justin's friends (anna online, playing), carla asks justin, justin
# asked dora; justin's DEVICE ACCESS TOKEN (fkz1) is made and printed.
# watch: follows the guest's serial output and does at a marker what a
# person at another computer would do, and checks what they see:
#   ==CHECK1==   what anna sees of justin (dnd, 'Im Spiel', an activity)
#   ==BERTON==   bert comes online (the guest should get an event)
#   ==CHECK2==   justin is invisible: anna sees offline, no activity
import base64, hashlib, hmac, json, sys, time, urllib.request

def b64(b): return base64.urlsafe_b64encode(b).rstrip(b'=').decode()

def mint(secret, uid, name):
    now = int(time.time())
    h = b64(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(',', ':')).encode())
    p = b64(json.dumps({"uid": uid, "name": name, "iat": now, "exp": now + 7200}, separators=(',', ':')).encode())
    s = b64(hmac.new(secret.encode(), f"{h}.{p}".encode(), hashlib.sha256).digest())
    return f"{h}.{p}.{s}"

def api(port, tok, path, body=None):
    req = urllib.request.Request(f"http://127.0.0.1:{port}{path}",
        data=None if body is None else json.dumps(body).encode(),
        method="GET" if body is None else "POST",
        headers={"Cookie": "fleitec_session=" + tok, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, {}

def people(secret):
    return {u: mint(secret, "u_" + u.upper(), n) for u, n in
            [("justin", "Justin"), ("anna", "Anna Berger"), ("bert", "Bert Huber"),
             ("carla", "Carla Rossi"), ("dora", "Dora Klein")]}

def justin_seen_by_anna(port, t):
    st, j = api(port, t["anna"], "/api/kontakte/liste")
    for it in j.get("items", []):
        if it.get("konto") == "u_JUSTIN":
            return it.get("profil", {})
    return {}

def setup(port, secret):
    t = people(secret)
    for tok in t.values():
        api(port, tok, "/api/kontakte/profil")
    api(port, t["bert"], "/api/kontakte/profil", {"status": "unsichtbar"})
    for f in ("anna", "bert"):
        api(port, t["justin"], "/api/kontakte/anfragen", {"konto": "u_" + f.upper()})
        api(port, t[f], "/api/kontakte/annehmen", {"konto": "u_JUSTIN"})
    api(port, t["carla"], "/api/kontakte/anfragen", {"konto": "u_JUSTIN"})
    api(port, t["justin"], "/api/kontakte/anfragen", {"konto": "u_DORA"})
    api(port, t["anna"], "/api/kontakte/da", {})
    api(port, t["anna"], "/api/kontakte/aktivitaet", {"spiel": "Counter-Strike 2"})
    st, j = api(port, t["justin"], "/api/kontakte/zugang", {})
    print(j.get("token", ""))

def watch(port, secret, serial, out):
    t = people(secret)
    done = set()
    res = open(out, "a")
    def say(ok, text):
        res.write(("OK    " if ok else "FAIL  ") + text + "\n"); res.flush()
    t0 = time.time()
    while time.time() - t0 < 600:
        try:
            s = open(serial, "rb").read().decode("latin-1")
        except OSError:
            s = ""
        if "==CHECK1==" in s and "c1" not in done:
            done.add("c1")
            p = justin_seen_by_anna(port, t)
            say(p.get("praesenz") == "dnd" and p.get("status_text") == "Im Spiel",
                f"anna sees justin 'do not disturb' with 'Im Spiel' (set on OrientOS): {p.get('praesenz')!r} {p.get('status_text')!r}")
            say((p.get("aktivitaet") or {}).get("name") == "Counter-Strike 2",
                f"anna sees what the game on OrientOS said it plays: {(p.get('aktivitaet') or {}).get('name')!r}")
            st, j = api(port, t["justin"], "/api/kontakte/liste")
            rel = {i.get("konto"): i.get("status") for i in j.get("items", [])}
            say(rel.get("u_CARLA") == "freunde", f"carla is justin's friend in the book (accepted on OrientOS): {rel.get('u_CARLA')!r}")
            say(rel.get("u_DORA") in (None, "", "keiner"), f"the request to dora is withdrawn: {rel.get('u_DORA')!r}")
        if "==BERTON==" in s and "b" not in done:
            done.add("b")
            api(port, t["bert"], "/api/kontakte/profil", {"status": "online"})
            api(port, t["bert"], "/api/kontakte/da", {})
        if "==CHECK2==" in s and "c2" not in done:
            done.add("c2")
            p = justin_seen_by_anna(port, t)
            say(p.get("praesenz") == "offline" and not p.get("aktivitaet"),
                f"justin went invisible on OrientOS: anna sees offline and no game: {p.get('praesenz')!r} {p.get('aktivitaet')!r}")
        if "==FERTIG==" in s or "c2" in done:
            break
        time.sleep(0.2)
    res.close()

if __name__ == "__main__":
    if sys.argv[1] == "setup":
        setup(int(sys.argv[2]), sys.argv[3])
    else:
        watch(int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5])
