#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re, sys, os, subprocess
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

def source(path):
    return subprocess.run(["bash", "tools/structure/srcview.sh", path], capture_output=True, check=True).stdout.decode("latin-1")

def consts(path):
    out = {}
    for m in re.finditer(r'^const ([A-Z0-9_]+): u64 = (0x[0-9A-Fa-f]+|\d+)', source(path), re.M):
        out[m.group(1)] = int(m.group(2), 0)
    return out

ax = consts("kernel/ui/ax.fi")
sy = consts("kernel/sys/sys.fi")
wl = consts("kernel/user/fuiapp/hostax.fi")
ad = consts("kernel/user/axd.fi")
bad = []
def same(what, a, b):
    if a != b:
        bad.append(f"{what}: {a} != {b}")

for k in ("PUSH", "READ", "EVENT", "PERM", "INFO", "SET", "PRESS"):
    same(f"AX_{k} sys/host", sy.get("AX_" + k), wl.get("AX_" + k))
for k in ("READ", "PERM", "INFO", "SET", "PRESS"):
    same(f"AX_{k} sys/axd", sy.get("AX_" + k), ad.get("AX_" + k))
same("NODE_BYTES ax/host", ax["NODE_BYTES"], wl["AXN_BYTES"])
same("NODE_BYTES ax/axd", ax["NODE_BYTES"], ad["NODE_BYTES"])
same("NAME_OFF", ax["NAME_OFF"], wl["AXN_NAME"])
same("NAME_MAX", ax["NAME_MAX"], wl["AXN_NAMEMAX"])
same("ACT_OFF", ax["ACT_OFF"], wl["AXN_ACT"])
same("ACT_MAX", ax["ACT_MAX"], wl["AXN_ACTMAX"])
same("MAX_NODES ax/host", ax["MAX_NODES"], wl["AXN_MAX"])
same("MAX_NODES ax/axd", ax["MAX_NODES"], ad["MAXN"])
for k, v in ax.items():
    if k.startswith("R_") and k not in ("R_NONE", "R_ROLES"):
        same(k + " ax/host", v, wl.get("AXR_" + k[2:]))
    if k.startswith("S_"):
        same(k + " ax/host", v, wl.get("AXS_" + k[2:]))
        same(k + " ax/axd", v, ad.get(k))
    if k.startswith("AI_") and k != "AI_FIELDS":
        same(k + " ax/hostc", v, wl.get("AXI_" + k[3:]))
        if k in ad:
            same(k + " ax/axd", v, ad[k])
    if k.startswith("C_") and k != "C_FIELDS":
        same(k + " ax/hostc", v, wl.get("AXC_" + k[2:]))
same("AX_DUMP", sy.get("AX_DUMP"), wl.get("AXC_DUMP"))
same("P_READ", ax["P_READ"], wl["AXP_READ"])
same("P_ACT", ax["P_ACT"], wl["AXP_ACT"])
same("E_AXPRESS", consts("kernel/ui/wm/wmlayout.fi").get("E_AXPRESS"), wl.get("EV_AXPRESS"))
if bad:
    print("fields: " + "; ".join(bad))
    sys.exit(1)
print("fields: node %d octets, %d roles, %d state bits, %d info fields -- all agree" % (
    ax["NODE_BYTES"], ax["R_ROLES"] - 1, len([k for k in ax if k.startswith("S_")]),
    len([k for k in ax if k.startswith("AI_")]) - 1))
