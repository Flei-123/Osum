#!/usr/bin/env python3
"""VM test of the new jarvisd (keepalive, supervisor, watchdog, info) against the LIVE bridge with the vm-device key."""
import json, os, subprocess, sys, time, urllib.request, shutil, socket
K = open("/srv/bruecke/verwalter.key").read().strip()
DEV = "osum-3807242d1d62"
W = "/root/dellw/bwvm"
ok = bad = 0
def chk(n, c, extra=""):
    global ok, bad
    if c: ok += 1; print("OK   ", n, flush=True)
    else: bad += 1; print("FAIL ", n, extra, flush=True)
def api(path, obj=None):
    r = urllib.request.Request("http://127.0.0.1:8090" + path, data=json.dumps(obj).encode() if obj is not None else None,
                               headers={"X-Bruecke-Verwalter": K, "Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(r, timeout=15).read() or b"{}")
def warum():
    g = api("/bruecke/warum?geraet=" + DEV)["geraete"]
    return g[0] if g else {}
def job(art, wert="", ziel="", timeout=60):
    t0 = time.time()
    r = api("/bruecke/auftrag", {"geraet": DEV, "art": art, "wert": wert, "ziel": ziel, "ttl_s": 300})
    aid = r["id"]
    end = time.time() + timeout
    while time.time() < end:
        try:
            q = urllib.request.Request("http://127.0.0.1:8090/bruecke/holen?geraet=%s&id=%s" % (DEV, aid), headers={"X-Bruecke-Verwalter": K})
            a = urllib.request.urlopen(q, timeout=30)
            return a.getcode(), a.read().decode("utf-8", "replace"), a.headers.get("X-Bruecke-Status")
        except urllib.error.HTTPError as e:
            if e.code not in (404, 204): return e.code, e.read().decode()[:200], None
        time.sleep(1)
    return None, "", None
def ser():
    try: return open(W + "/ser.txt", errors="replace").read()
    except OSError: return ""
def mon(cmd):
    s = socket.socket(socket.AF_UNIX); s.connect(W + "/mon.sock"); s.settimeout(3)
    try: s.recv(4096)
    except Exception: pass
    s.send((cmd + "\n").encode()); time.sleep(0.5)
    try: out = s.recv(8192).decode(errors="replace")
    except Exception: out = ""
    s.close(); return out
def wait(cond, t, step=2):
    end = time.time() + t
    while time.time() < end:
        v = cond()
        if v: return v
        time.sleep(step)
    return None

before = warum().get("sitzungen_seit_status", 0)
shutil.copy("/root/dellw/bw/orientos-usb.img", W + "/stick.img")
for f in ("ser.txt", "mon.sock", "vars.fd"):
    try: os.remove(W + "/" + f)
    except OSError: pass
vm = subprocess.Popen(["/root/dellw/vmrun.sh", W, "900"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print("VM started; sessions before:", before, flush=True)
try:
    up = wait(lambda: warum().get("zustand") == "online" and warum().get("sitzungen_seit_status", 0) > before, 240)
    chk("A  device signs in (new session)", bool(up), warum().get("kurz"))
    w = warum()
    chk("A2 `info`: MAC reported", bool(w.get("mac")), w.get("mac"))
    print("   mac:", w.get("mac"), "| supervisor line on serial:", "supervisor started" in ser(), flush=True)
    chk("A3 supervisor started (serial)", "supervisor started" in ser())
    c, t, st = job("system")
    chk("B  job `system` works", c == 200 and st == "ok", (c, t[:80], st))

    # --- keepalive: a command that outlasts the server's 90 s silence limit
    s0 = warum().get("sitzungen_seit_status", 0)
    r = api("/bruecke/auftrag", {"geraet": DEV, "art": "befehl", "ziel": "/bin/sleep 130", "ttl_s": 300})
    t0 = time.time(); states = []; maxgap = 0
    while time.time() - t0 < 140:
        x = warum(); states.append(x.get("zustand")); time.sleep(5)
    print("   states during 130 s command:", sorted(set(states)), "max gap", warum().get("laengste_luecke_s"), flush=True)
    chk("C  keepalive: never offline/busy-silent during a 130 s command", set(states) <= {"online"}, sorted(set(states)))
    res = wait(lambda: (lambda x: x if x and x.get("letzter_auftrag", {}).get("status") not in (None, "laeuft") else None)(warum()), 30)
    chk("C2 long command finished ok", bool(res) and res["letzter_auftrag"]["status"] == "ok", res and res["letzter_auftrag"])
    chk("C3 same session throughout (no re-login)", warum().get("sitzungen_seit_status") == s0, (warum().get("sitzungen_seit_status"), s0))

    # --- supervisor: kill the worker
    c, ps, st = job("befehl", ziel="/bin/ps")
    print("   ps:", ps[:600].replace("\n", " | "), flush=True)
    open(W + "/ps.txt", "w").write(ps)
finally:
    pass
print("\n%d OK / %d FAIL (stage 1)" % (ok, bad))
