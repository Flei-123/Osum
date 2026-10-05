#!/usr/bin/env python3
"""Test of the why-offline additions (bruecke_server.py, 05.10.2026) against a throw-away instance."""
import json, os, shutil, socket, subprocess, sys, tempfile, time, urllib.request, secrets
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization

PORT = 18090
W = tempfile.mkdtemp(prefix="bruecke-test-")
ok = bad = 0
def chk(name, cond, extra=""):
    global ok, bad
    if cond: ok += 1; print("OK   ", name)
    else: bad += 1; print("FAIL ", name, extra)

env = dict(os.environ, BRUECKE_TOT_S="3", BRUECKE_WAECHTER_S="0.4", BRUECKE_JOB_TTL_S="4", BRUECKE_BUSY_GRACE_S="7")
def start():
    return subprocess.Popen([sys.executable, "/root/bruecke/bruecke_server.py", "--port", str(PORT), "--bind", "127.0.0.1", "--wurzel", W],
                            env=env, stderr=open(W + "/log.txt", "a"), stdout=subprocess.DEVNULL)
srv = start()
time.sleep(1.2)
KEY = open(W + "/verwalter.key").read().strip()
URL = "http://127.0.0.1:%d" % PORT

def api(path, obj=None, admin=True, raw=None, headers=None):
    h = {"Content-Type": "application/json"}
    if admin: h["X-Bruecke-Verwalter"] = KEY
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
        self.kennung = "osum-" + self.pub[:12]
        self.sid = secrets.token_hex(8)
    def send(self, kopf, nutz=b""):
        body = (kopf + " " + str(len(nutz))).encode() + b"\n" + nutz
        r = urllib.request.Request(URL + "/bruecke/draht", data=body, headers={"X-Draht": self.sid})
        return urllib.request.urlopen(r, timeout=10).read()
    def prepair(self):
        api("/bruecke/koppeln", {"was": "vorab", "pubkey": self.pub})
    def login(self):
        self.sid = secrets.token_hex(8)
        self.send("osum-bruecke 1")
        a = self.send("ich " + self.pub).decode().split()
        ford = a[1]
        sig = self.k.sign(bytes.fromhex(ford)).hex()
        return self.send("beweis " + sig).decode().split()[0]
    def puls(self):
        return self.send("puls")

def warum(d):
    r = api("/bruecke/warum?geraet=" + d.kennung)
    return r["geraete"][0] if r.get("geraete") else {}
def wait_event(d, word, t=4):
    end = time.time() + t
    while time.time() < end:
        if any(word in e[1] for e in warum(d)["ereignisse"]): return True
        time.sleep(0.2)
    return False
def wait_state(d, want, t=12):
    end = time.time() + t
    while time.time() < end:
        z = warum(d).get("zustand")
        if z == want: return True
        time.sleep(0.3)
    return False

# ---- A: online, then silent -> stumm, with an event
d = Dev(); d.prepair()
chk("login ok", d.login() == "willkommen")
for _ in range(3): d.puls(); time.sleep(0.2)
chk("online", warum(d)["zustand"] == "online")
chk("silent -> stumm", wait_state(d, "stumm", 10))
wait_event(d, "STUMM"); w = warum(d)
chk("STUMM event written", any("STUMM" in e[1] for e in w["ereignisse"]), w["ereignisse"])
chk("text says cause not determinable", "NICHT bestimmbar" in w["kurz"])
chk("verbunden false in /geraete", [g for g in api("/bruecke/geraete")["geraete"] if g["kennung"] == d.kennung][0]["verbunden"] is False)

# ---- B: new session after silence -> logged, then busy job, keepalive
chk("relogin", d.login() == "willkommen")
chk("event NEUE SITZUNG", any("NEUE SITZUNG" in e[1] for e in warum(d)["ereignisse"]))
api("/bruecke/auftrag", {"geraet": d.kennung, "art": "befehl", "ziel": "sleep 99"})
a = d.puls().decode()
chk("job handed out", a.startswith("auftrag "), a[:40])
chk("busy after silence > TOT_S", wait_state(d, "beschaeftigt", 8))
chk("BESCHAEFTIGT event", wait_event(d, "BESCHAEFTIGT"))
d.send("lebt"); 
chk("keepalive `lebt` -> online again", warum(d)["zustand"] == "online")
chk("`lebt` hands out no job", d.send("lebt") == b"")
# busy -> stumm after grace
chk("busy -> stumm after grace", wait_state(d, "stumm", 14))
wait_event(d, "unbeantwortet"); w = warum(d)
chk("stumm names the unanswered job", "unbeantwortet" in " ".join(e[1] for e in w["ereignisse"]), w["ereignisse"][-2:])

# ---- C: result clears the running job; goodbye
d.login()
api("/bruecke/auftrag", {"geraet": d.kennung, "art": "liste", "ziel": "/"})
a = d.puls().decode().split()
d.send("fertig %s ok" % a[1], b"x")
w = warum(d)
chk("job done recorded", w["letzter_auftrag"]["status"] == "ok" and w["laufender_auftrag"] is None, w["letzter_auftrag"])
d.send("tschuess")
chk("goodbye -> sauber_beendet", wait_state(d, "sauber_beendet", 10))
wait_event(d, "GETRENNT"); chk("sauber ende_grund", "tschuess" in warum(d)["ende_grund"])

# ---- D: stale job dropped (TTL 4 s), kept with ttl_s 0
api("/bruecke/auftrag", {"geraet": d.kennung, "art": "system"})
api("/bruecke/auftrag", {"geraet": d.kennung, "art": "system", "ttl_s": 0})
time.sleep(5)
d.login()
r = d.puls().decode()
chk("stale job dropped, ttl_s 0 job survives", r.startswith("auftrag ") and warum(d)["offene_auftraege"] == 0
    and any("VERWORFEN" in e[1] for e in warum(d)["ereignisse"]), (r[:30], warum(d)["ereignisse"][-3:]))

# ---- E: info -> MAC, WoL packet on loopback
mac = "aa:bb:cc:dd:ee:01"
d.send("info", ("mac=%s;commit=abc1234" % mac).encode())
chk("MAC learned", warum(d)["mac"] == mac, warum(d)["mac"])
u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); u.bind(("127.0.0.1", 9)); u.settimeout(3)
r = api("/bruecke/wol", {"geraet": d.kennung, "broadcast": ["127.0.0.1"]})
try:
    pk = u.recvfrom(2048)[0]
except Exception as e:
    pk = b""
chk("magic packet = ff*6 + mac*16", pk == b"\xff" * 6 + bytes.fromhex(mac.replace(":", "")) * 16, r)
d.send("info", b"mac=AABBCCDDEE02")
chk("MAC in 12-hex form is normalised", warum(d)["mac"] == "aa:bb:cc:dd:ee:02", warum(d)["mac"])
chk("wol without admin key refused", api("/bruecke/wol", {"mac": mac}, admin=False).get("http") == 403)
chk("wol bad mac refused", api("/bruecke/wol", {"mac": "xyz"}).get("http") == 400)
chk("admin sets MAC", api("/bruecke/koppeln", {"was": "mac", "geraet": d.kennung, "mac": "11:22:33:44:55:66"}).get("mac") == "11:22:33:44:55:66")
chk("warum needs admin key", api("/bruecke/warum", admin=False).get("http") == 403)

# ---- F: restart keeps last contact + MAC; event about the restart
time.sleep(0.5)
srv.terminate(); srv.wait(5)
srv = start(); time.sleep(1.5)
w = warum(d)
chk("after restart: last contact survives", w.get("letzter_kontakt_utc") is not None, w)
chk("after restart: MAC survives", w.get("mac") == "11:22:33:44:55:66", w.get("mac"))
chk("after restart: SERVER NEU GESTARTET event", any("SERVER NEU GESTARTET" in e[1] for e in w["ereignisse"]), w["ereignisse"][-3:])
chk("after restart: not reported online", w["zustand"] != "online")
chk("old marke -> device is told to log in again", d.puls().startswith(b"weg "))
chk("fresh login after restart works", d.login() == "willkommen")
chk("ERSTE SITZUNG event", any("ERSTE SITZUNG" in e[1] for e in warum(d)["ereignisse"]))
srv.terminate(); srv.wait(5)

# ---- G: a device that only knocks (greeting, never `ich`) -> "klopft", then recovers
srv = start(); time.sleep(1.2)
d2 = Dev(); d2.prepair()
d2.sid = secrets.token_hex(8); d2.sid = d2.pub[:24]       # the real client uses the key prefix as wire id
for _ in range(3):
    d2.send("osum-bruecke 1"); time.sleep(0.3)
chk("knock only -> klopft", wait_state(d2, "klopft", 6), warum(d2).get("zustand"))
chk("KLOPFT event", wait_event(d2, "KLOPFT NUR AN"))
w2 = warum(d2)
chk("klopft text says device lives", "LEBT" in w2["kurz"] and w2["klopfen"] >= 3, w2["kurz"])
d2.sid = d2.pub[:24]; d2.send("osum-bruecke 1")
a = d2.send("ich " + d2.pub).decode().split()
chk("`ich` ends the knock state", warum(d2)["zustand"] != "klopft")
chk("login after knocking works", d2.login() == "willkommen" and wait_state(d2, "online", 4))
chk("unpaired knocker creates no entry", api("/bruecke/warum?geraet=osum-ffffffffffff")["geraete"] == [])
Dev().send("osum-bruecke 1")
srv.terminate(); srv.wait(5)
print("\n%d OK / %d FAIL" % (ok, bad))
shutil.rmtree(W, ignore_errors=True)
sys.exit(1 if bad else 0)
