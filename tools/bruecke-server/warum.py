#!/usr/bin/env python3
"""warum.py [kennung] -- why is a bridge device offline? (reads /bruecke/warum from the local service)"""
import json, sys, urllib.request
K = open("/srv/bruecke/verwalter.key").read().strip()
q = ("?geraet=" + sys.argv[1]) if len(sys.argv) > 1 else ""
r = urllib.request.Request("http://127.0.0.1:8090/bruecke/warum" + q, headers={"X-Bruecke-Verwalter": K})
for g in json.loads(urllib.request.urlopen(r, timeout=10).read())["geraete"]:
    print("%s  [%s]\n  %s" % (g["kennung"], g["zustand"], g["kurz"]))
    print("  last contact: %s  (%s)  vor %s s" % (g["letzter_kontakt_utc"], g["letzter_kontakt_wien"], g["vor_s"]))
    if g.get("mac"): print("  MAC:", g["mac"])
    for t, e in g["ereignisse"][-6:]:
        print("   ", t, e[:200])
