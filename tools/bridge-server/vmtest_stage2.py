import sys, time
sys.argv = ["x"]
exec(open("/root/dellw/bwtest.py").read().split("before = warum()")[0])
print(mon("info network")[:400], flush=True)
s0 = warum().get("sitzungen_seit_status", 0)
# --- supervisor: kill the worker (pid 26 under supervisor 25, from ps.txt)
ps = open(W + "/ps.txt").read().split("\n")
jv = [l.split() for l in ps if l.strip().endswith("jarvisd")]
print("jarvisd tasks:", jv, flush=True)
worker = [x for x in jv if x[1] != "1"][0][0]
sup = [x for x in jv if x[1] == "1"][0][0]
r = api("/bruecke/auftrag", {"geraet": DEV, "art": "befehl", "ziel": "/bin/kill " + worker, "ttl_s": 120})
back = wait(lambda: (lambda x: x if x.get("sitzungen_seit_status", 0) > s0 and x.get("zustand") == "online" else None)(warum()), 90, 3)
chk("D  worker killed -> supervisor starts a new one, device signs in again", bool(back), warum().get("kurz"))
ev = " ".join(e[1] for e in warum().get("ereignisse", []))
chk("D2 server saw the new session", "NEUE SITZUNG" in ev, ev[-200:])
c, ps2, st = job("befehl", ziel="/bin/ps")
jv2 = [l.split() for l in ps2.split("\n") if l.strip().endswith("jarvisd")]
print("jarvisd tasks after:", jv2, flush=True)
chk("D3 same supervisor, new worker pid", any(x[0] == sup and x[1] == "1" for x in jv2) and any(x[1] == sup and x[0] != worker for x in jv2), jv2)

# --- watchdog: cut the network for > 30 s (watchdog = 30 in this image)
s1 = warum().get("sitzungen_seit_status", 0)
n0 = ser().count("worker silent too long")
print("link off:", mon("set_link n0 off")[:200], flush=True)
t0 = time.time()
got = wait(lambda: ser().count("worker silent too long") > n0, 90, 3)
print("   watchdog fired after %.0f s" % (time.time() - t0), flush=True)
chk("E  silence > watchdog: supervisor kills the worker (serial line)", bool(got))
print("link on:", mon("set_link n0 on")[:200], flush=True)
back = wait(lambda: (lambda x: x if x.get("sitzungen_seit_status", 0) > s1 and x.get("zustand") == "online" else None)(warum()), 120, 3)
chk("E2 network back -> new worker signs in again", bool(back), warum().get("kurz"))
print("\n%d OK / %d FAIL (stage 2)" % (ok, bad))
mon("quit")
