#!/usr/bin/env python3
import json, os, subprocess, sys, tempfile, time, urllib.request, urllib.error, secrets, shutil
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization

PORT = 18093
W = tempfile.mkdtemp(prefix="bridge-pairing-test-")
ok = bad = 0

def chk(name, cond, extra=""):
    global ok, bad
    if cond:
        ok += 1
        print("OK   ", name)
    else:
        bad += 1
        print("FAIL ", name, extra)

env = dict(os.environ, BRIDGE_CODE_TTL_S="3", BRIDGE_PENDING_MAX="4", BRIDGE_WRONG_MAX="5", BRIDGE_WATCHDOG_S="0.4")
srv = subprocess.Popen([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "bridge_server.py"), "--port", str(PORT), "--bind", "127.0.0.1", "--root", W],
                       env=env, stderr=open(W + "/log.txt", "a"), stdout=subprocess.DEVNULL)
time.sleep(1.2)
KEY = open(W + "/admin.key").read().strip()
URL = "http://127.0.0.1:%d" % PORT

def api(path, obj=None, admin=True):
    h = {"Content-Type": "application/json"}
    if admin:
        h["X-Bridge-Admin"] = KEY
    data = json.dumps(obj).encode() if obj is not None else None
    r = urllib.request.Request(URL + path, data=data, headers=h, method="POST" if data is not None else "GET")
    try:
        resp = urllib.request.urlopen(r, timeout=10)
        return json.loads(resp.read() or b"{}"), resp.status
    except urllib.error.HTTPError as e:
        return {"body": e.read().decode()[:200]}, e.code

class Dev:
    def __init__(self):
        self.k = Ed25519PrivateKey.generate()
        self.pub = self.k.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw).hex()
        self.device_id = "osum-" + self.pub[:12]
        self.sid = secrets.token_hex(8)
    def send(self, head, payload=b""):
        body = (head + " " + str(len(payload))).encode() + b"\n" + payload
        r = urllib.request.Request(URL + "/bridge/wire", data=body, headers={"X-Bridge-Wire": self.sid})
        return urllib.request.urlopen(r, timeout=10).read()
    def hello(self):
        self.sid = secrets.token_hex(8)
        self.send("osum-bridge 1")
        return self.send("hello " + self.pub).decode().split()
    def code(self):
        a = self.hello()
        return bytes.fromhex(a[1]).decode() if a[0] == "pairing-needed" else None
    def login(self):
        a = self.hello()
        if a[0] != "challenge":
            return a[0]
        sig = self.k.sign(bytes.fromhex(a[1])).hex()
        return self.send("proof " + sig).decode().split()[0]

def pending_ids():
    return [x["id"] for x in api("/bridge/pending")[0]["pending"]]

try:
    d = Dev()
    c = d.code()
    chk("hello of unknown device -> 6-digit code", c is not None and len(c) == 6 and c.isdigit(), c)
    chk("same code on re-ask", d.code() == c)
    body, st = api("/bridge/pending")
    chk("pending lists device", d.device_id in [x["id"] for x in body["pending"]] and st == 200)
    chk("pending carries no code", c not in json.dumps(body) and all("code" not in x for x in body["pending"]))
    chk("pending needs admin key", api("/bridge/pending", admin=False)[1] == 403)
    chk("pair by code needs admin key", api("/bridge/pair", {"code": c}, admin=False)[1] == 403)
    body, st = api("/bridge/pair", {"code": c, "peek": True})
    chk("peek returns id without pairing", st == 200 and body.get("id") == d.device_id and not body.get("paired"), str(body))
    chk("peek leaves device pending", d.code() == c)
    body, st = api("/bridge/pair", {"code": c})
    chk("pair by code ok", st == 200 and body.get("paired") is True and body.get("id") == d.device_id, str(body))
    chk("paired device gets challenge and welcome", d.login() == "welcome")
    chk("paired device left pending list", d.device_id not in pending_ids())
    chk("used code does not match again", api("/bridge/pair", {"code": c})[1] == 404)
    dl = [x for x in api("/bridge/devices")[0]["devices"] if x["device_id"] == d.device_id]
    chk("devices shows paired", bool(dl) and dl[0]["paired"] is True and "code" not in dl[0])

    e = Dev()
    ce = e.code()
    body, st = api("/bridge/pair", {"device": e.device_id, "code": ce})
    chk("legacy device+code pairing still works", st == 200 and body.get("paired") is True, str(body))

    body, st = api("/bridge/forget", {"device": d.device_id})
    chk("forget ok", st == 200 and body.get("ok") is True)
    c2 = d.code()
    chk("forgotten device must pair again", c2 is not None and len(c2) == 6)
    chk("forgotten device cannot log in", d.login() != "welcome")
    chk("forget unknown device 404", api("/bridge/forget", {"device": "osum-000000000000"})[1] == 404)
    chk("forget needs admin key", api("/bridge/forget", {"device": d.device_id}, admin=False)[1] == 403)
    body, st = api("/bridge/pair", {"code": c2})
    chk("re-pair by new code", st == 200 and body.get("paired") is True)

    x = Dev()
    cx = x.code()
    time.sleep(3.6)
    chk("expired code not in pending", x.device_id not in pending_ids())
    chk("expired code rejected", api("/bridge/pair", {"code": cx})[1] == 404)
    cx2 = x.code()
    chk("new code issued after expiry", cx2 is not None and x.device_id in pending_ids())
    chk("fresh code pairs", api("/bridge/pair", {"code": cx2})[1] == 200)

    h = Dev()
    body, st = api("/bridge/login", {"device_id": h.device_id, "pubkey": h.pub}, admin=False)
    hc = body.get("code", "")
    chk("http login of unknown device gives 6-digit code", st == 200 and len(hc) == 6 and hc.isdigit(), str(body))
    chk("http login device is pending", h.device_id in pending_ids())
    chk("http login code pairs", api("/bridge/pair", {"code": hc})[1] == 200)
    h2 = Dev()
    hc2 = api("/bridge/login", {"device_id": h2.device_id, "pubkey": h2.pub}, admin=False)[0].get("code", "")
    time.sleep(3.6)
    chk("http login code expires", len(hc2) == 6 and h2.device_id not in pending_ids())

    batch = []
    for _ in range(6):
        b = Dev()
        b.code()
        batch.append(b)
        time.sleep(0.05)
    ids = pending_ids()
    chk("pending capped at 4", len(ids) == 4, str(len(ids)))
    chk("newest pending kept", batch[-1].device_id in ids and batch[0].device_id not in ids)
    codes = [b.code() for b in batch[-4:]]
    chk("pending codes unique", len(set(codes)) == 4)

    target = batch[-1]
    before = target.code()
    for i in range(5):
        _, st = api("/bridge/pair", {"code": "abcdef"})
        chk("wrong code %d -> 404" % (i + 1), st == 404, str(st))
    body, st = api("/bridge/pair", {"code": before})
    chk("limiter locks after 5 wrong", st == 429, "%s %s" % (st, body))
    after = target.code()
    chk("pending codes re-rolled on lockout", after is not None and after != before)
    chk("limiter still locked for new code", api("/bridge/pair", {"code": after})[1] == 429)
    chk("target still unpaired", target.device_id in pending_ids())
finally:
    srv.terminate()
    srv.wait(5)
    shutil.rmtree(W, ignore_errors=True)

print("\n%d OK, %d FAIL" % (ok, bad))
sys.exit(1 if bad else 0)
