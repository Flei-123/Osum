#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/a11y/fields.py -- ONE PACKING, FOUR PLACES, HELD AGAINST EACH OTHER.

The node of the accessibility tree (96 octets), its roles, its state bits,
the AX_INFO fields and the call numbers are written in four files:

    kernel/ui/ax.fi        the store (NODE_BYTES, R_*, S_*, AI_*, C_*)
    kernel/sys/sys.fi      the call numbers (AX_*)
    kernel/user/wlibc.fi   ring 3's calls and fields (AX_*, AXI_*, AXC_*)
    kernel/user/wlib.fi    the builder (AXN_*, AXR_*, AXS_*)
    kernel/user/axd.fi     the reader on the bus (its own copies)

A number written in two places drifts; this program is the third place
that does nothing but compare. Exit 0 = all agree.
"""
import re, sys, os
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

def consts(path):
    out = {}
    for m in re.finditer(r'^const ([A-Z0-9_]+): u64 = (0x[0-9A-Fa-f]+|\d+)', open(path, encoding='latin-1').read(), re.M):
        out[m.group(1)] = int(m.group(2), 0)
    return out

ax = consts("kernel/ui/ax.fi")
sy = consts("kernel/sys/sys.fi")
wc = consts("kernel/user/wlibc.fi")
wl = consts("kernel/user/wlib.fi")
ad = consts("kernel/user/axd.fi")
bad = []
def same(what, a, b):
    if a != b:
        bad.append(f"{what}: {a} != {b}")

for k in ("PUSH", "READ", "EVENT", "PERM", "INFO", "SET", "PRESS"):
    same(f"AX_{k} sys/wlibc", sy.get("AX_" + k), wc.get("AX_" + k))
for k in ("READ", "PERM", "INFO", "SET", "PRESS"):
    same(f"AX_{k} sys/axd", sy.get("AX_" + k), ad.get("AX_" + k))
same("NODE_BYTES ax/wlib", ax["NODE_BYTES"], wl["AXN_BYTES"])
same("NODE_BYTES ax/axd", ax["NODE_BYTES"], ad["NODE_BYTES"])
same("NAME_OFF", ax["NAME_OFF"], wl["AXN_NAME"])
same("NAME_MAX", ax["NAME_MAX"], wl["AXN_NAMEMAX"])
same("ACT_OFF", ax["ACT_OFF"], wl["AXN_ACT"])
same("ACT_MAX", ax["ACT_MAX"], wl["AXN_ACTMAX"])
same("MAX_NODES ax/wlib", ax["MAX_NODES"], wl["AXN_MAX"])
same("MAX_NODES ax/axd", ax["MAX_NODES"], ad["MAXN"])
for k, v in ax.items():
    if k.startswith("R_") and k not in ("R_NONE", "R_ROLES"):
        same(k + " ax/wlib", v, wl.get("AXR_" + k[2:]))
    if k.startswith("S_"):
        same(k + " ax/wlib", v, wl.get("AXS_" + k[2:]))
        same(k + " ax/axd", v, ad.get(k))
    if k.startswith("AI_") and k != "AI_FIELDS":
        same(k + " ax/wlibc", v, wc.get("AXI_" + k[3:]))
        if k in ad:
            same(k + " ax/axd", v, ad[k])
    if k.startswith("C_") and k != "C_FIELDS":
        same(k + " ax/wlibc", v, wc.get("AXC_" + k[2:]))
same("AX_DUMP", sy.get("AX_DUMP"), wc.get("AXC_DUMP"))
same("P_READ", ax["P_READ"], wc["AXP_READ"])
same("P_ACT", ax["P_ACT"], wc["AXP_ACT"])
same("E_AXPRESS", consts("kernel/ui/wm.fi").get("E_AXPRESS"), wc.get("EV_AXPRESS"))
if bad:
    print("fields: " + "; ".join(bad))
    sys.exit(1)
print("fields: node %d octets, %d roles, %d state bits, %d info fields -- all agree" % (
    ax["NODE_BYTES"], ax["R_ROLES"] - 1, len([k for k in ax if k.startswith("S_")]),
    len([k for k in ax if k.startswith("AI_")]) - 1))
