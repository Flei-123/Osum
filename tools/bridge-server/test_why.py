#!/usr/bin/env python3
"""Test of the why-offline features (current English dialect) against a throw-away instance."""
import json, os, shutil, socket, subprocess, sys, tempfile, time, urllib.request, secrets
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization

PORT = 18092
W = tempfile.mkdtemp(prefix="bridge-test-")
ok = bad = 0
def chk(name, cond, extra=""):
    global ok, bad
    if cond: ok += 1; print("OK   ", name)
    else: bad += 1; print("FAIL ", name, extra)

env = dict(os.environ, BRIDGE_DEAD_S="3", BRIDGE_WATCHDOG_S="0.4", BRIDGE_JOB_TTL_S="4", BRIDGE_BUSY_GRACE_S="7")
def start():
    return subprocess.Popen([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "bridge_server.py"), "--port", str(PORT), "--bind", "127.0.0.1", "--root", W],
                            env=env, stderr=open(W + "/log.txt", "a"), stdout=subprocess.DEVNULL)
srv = start()
time.sleep(1.2)
KEY = open(W + "/admin.key").read().strip()
URL = "http://127.0.0.1:%d" % PORT

def api(path, obj=None, admin=True, raw=None, headers=None):
    h = {"Content-Type": "application/json"}
    if admin: h["X-Bridge-Admin"] = KEY
    h.update(headers or {})
    data = raw if raw is not None else (json.dumps(obj).encode() if obj is not None else None)
    r = urllib.request.Request(URL + path, data=data, headers=h, method="POST" if data is not None else "GET")
    try:
        return json.loads(urllib.request.urlopen(r, timeout=10).read() or b"{}")
    except urllib.error.HTTPError as e:
        return {"http": e.code, "body": e.read().decode()[:200]}

class Dev:
    def __init__(self):
        self.k = Ed25519PrivateKey.generate()
        self.pub = self.k.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw).hex()
        self.device_id = "osum-" + self.pub[:12]
        self.sid = secrets.token_hex(8)
    def send(self, kopf, nutz=b""):
        body = (kopf + " " + str(len(nutz))).encode() + b"\n" + nutz
        r = urllib.request.Request(URL + "/bridge/wire", data=body, headers={"X-Bridge-Wire": self.sid})
        return urllib.request.urlopen(r, timeout=10).read()
    def prepair(self):
        api("/bridge/pair", {"what": "preauth", "pubkey": self.pub})
    def login(self):
        self.sid = secrets.token_hex(8)
        self.send("osum-bridge 1")
        a = self.send("hello " + self.pub).decode().split()
        ford = a[1]
        sig = self.k.sign(bytes.fromhex(ford)).hex()
        return self.send("proof " + sig).decode().split()[0]
    def puls(self):
        return self.send("poll")

def why(d):
    r = api("/bridge/why?geraet=" + d.device_id)
    return r["devices"][0] if r.get("devices") else {}
def wait_event(d, word, t=4):
    end = time.time() + t
    while time.time() < end:
        if any(word in e[1] for e in why(d)["events"]): return True
        time.sleep(0.2)
    return False
def wait_state(d, want, t=12):
    end = time.time() + t
    while time.time() < end:
        z = why(d).get("state")
        if z == want: return True
        time.sleep(0.3)
    return False

# ---- A: online, then silent -> stumm, with an event
d = Dev(); d.prepair()
chk("login ok", d.login() == "welcome")
for _ in range(3): d.puls(); time.sleep(0.2)
chk("online", why(d)["state"] == "online")
chk("silent -> stumm", wait_state(d, "silent", 10))
wait_event(d, "SILENT"); w = why(d)
chk("SILENT event written", any("SILENT" in e[1] for e in w["events"]), w["events"])
chk("text says cause not determinable", "cannot be determined" in w["summary"])
chk("verbunden false in /geraete", [g for g in api("/bridge/devices")["devices"] if g["device_id"] == d.device_id][0]["connected"] is False)

# ---- B: new session after silence -> logged, then busy job, keepalive
chk("relogin", d.login() == "welcome")
chk("event NEW SESSION", any("NEW SESSION" in e[1] for e in why(d)["events"]))
api("/bridge/job", {"device": d.device_id, "kind": "run", "target": "sleep 99"})
a = d.puls().decode()
chk("job handed out", a.startswith("job "), a[:40])
chk("busy after silence > TOT_S", wait_state(d, "busy", 8))
chk("BUSY event", wait_event(d, "BUSY"))
d.send("alive"); 
chk("keepalive `lebt` -> online again", why(d)["state"] == "online")
chk("`lebt` hands out no job", d.send("alive") == b"")
# busy -> stumm after grace
chk("busy -> stumm after grace", wait_state(d, "silent", 14))
wait_event(d, "unanswered"); w = why(d)
chk("stumm names the unanswered job", "unanswered" in " ".join(e[1] for e in w["events"]), w["events"][-2:])

# ---- C: result clears the running job; goodbye
d.login()
api("/bridge/job", {"device": d.device_id, "kind": "list", "target": "/"})
a = d.puls().decode().split()
d.send("done %s ok" % a[1], b"x")
w = why(d)
chk("job done recorded", w["last_job"]["status"] == "ok" and w["running_job"] is None, w["last_job"])
d.send("bye")
chk("goodbye -> sauber_beendet", wait_state(d, "clean_exit", 10))
wait_event(d, "DISCONNECTED"); chk("sauber ende_grund", "bye" in why(d)["end_reason"])

# ---- D: stale job dropped (TTL 4 s), kept with ttl_s 0
api("/bridge/job", {"device": d.device_id, "kind": "system"})
api("/bridge/job", {"device": d.device_id, "kind": "system", "ttl_s": 0})
time.sleep(5)
d.login()
r = d.puls().decode()
chk("stale job dropped, ttl_s 0 job survives", r.startswith("job ") and why(d)["open_jobs"] == 0
    and any("JOB DROPPED" in e[1] for e in why(d)["events"]), (r[:30], why(d)["events"][-3:]))

# ---- E: info -> MAC, WoL packet on loopback
mac = "aa:bb:cc:dd:ee:01"
d.send("info", ("mac=%s;commit=abc1234" % mac).encode())
chk("MAC learned", why(d)["mac"] == mac, why(d)["mac"])
u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); u.bind(("127.0.0.1", 9)); u.settimeout(3)
r = api("/bridge/wol", {"device": d.device_id, "broadcast": ["127.0.0.1"]})
try:
    pk = u.recvfrom(2048)[0]
except Exception as e:
    pk = b""
chk("magic packet = ff*6 + mac*16", pk == b"\xff" * 6 + bytes.fromhex(mac.replace(":", "")) * 16, r)
d.send("info", b"mac=AABBCCDDEE02")
chk("MAC in 12-hex form is normalised", why(d)["mac"] == "aa:bb:cc:dd:ee:02", why(d)["mac"])
chk("wol without admin key refused", api("/bridge/wol", {"mac": mac}, admin=False).get("http") == 403)
chk("wol bad mac refused", api("/bridge/wol", {"mac": "xyz"}).get("http") == 400)
chk("admin sets MAC", api("/bridge/pair", {"what": "mac", "device": d.device_id, "mac": "11:22:33:44:55:66"}).get("mac") == "11:22:33:44:55:66")
chk("warum needs admin key", api("/bridge/why", admin=False).get("http") == 403)

# ---- F: restart keeps last contact + MAC; event about the restart
time.sleep(0.5)
srv.terminate(); srv.wait(5)
srv = start(); time.sleep(1.5)
w = why(d)
chk("after restart: last contact survives", w.get("last_contact_utc") is not None, w)
chk("after restart: MAC survives", w.get("mac") == "11:22:33:44:55:66", w.get("mac"))
chk("after restart: SERVER RESTARTED event", any("SERVER RESTARTED" in e[1] for e in w["events"]), w["events"][-3:])
chk("after restart: not reported online", w["state"] != "online")
chk("old marke -> device is told to log in again", d.puls().startswith(b"drop "))
chk("fresh login after restart works", d.login() == "welcome")
chk("FIRST SESSION event", any("FIRST SESSION" in e[1] for e in why(d)["events"]))
srv.terminate(); srv.wait(5)

# ---- G: a device that only knocks (greeting, never `ich`) -> "knocking", then recovers
srv = start(); time.sleep(1.2)
d2 = Dev(); d2.prepair()
d2.sid = secrets.token_hex(8); d2.sid = d2.pub[:24]       # the real client uses the key prefix as wire id
for _ in range(3):
    d2.send("osum-bridge 1"); time.sleep(0.3)
chk("knock only -> klopft", wait_state(d2, "knocking", 6), why(d2).get("state"))
chk("KLOPFT event", wait_event(d2, "ONLY KNOCKING"))
w2 = why(d2)
chk("klopft text says device lives", "ALIVE" in w2["summary"] and w2["knocks"] >= 3, w2["summary"])
d2.sid = d2.pub[:24]; d2.send("osum-bridge 1")
a = d2.send("hello " + d2.pub).decode().split()
chk("`ich` ends the knock state", why(d2)["state"] != "knocking")
chk("login after knocking works", d2.login() == "welcome" and wait_state(d2, "online", 4))
chk("unpaired knocker creates no entry", api("/bridge/why?geraet=osum-ffffffffffff")["devices"] == [])
Dev().send("osum-bridge 1")
srv.terminate(); srv.wait(5)
print("\n%d OK / %d FAIL" % (ok, bad))
print(open(W + "/log.txt").read()[-1500:]) if bad else None
shutil.rmtree(W, ignore_errors=True)
sys.exit(1 if bad else 0)
