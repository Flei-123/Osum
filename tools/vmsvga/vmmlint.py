#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re, sys

src = open(sys.argv[1], encoding="latin1").read()
bad = 0

def const(name):
    m = re.search(r"^const %s: u64 = (0x[0-9A-Fa-f]+|\d+)" % name, src, re.M)
    return int(m.group(1), 0) if m else None

def body(fn):
    m = re.search(r"^fn %s\(.*?^}" % fn, src, re.M | re.S)
    return m.group(0) if m else ""

def check(label, cond):
    global bad
    print(("  OK    " if cond else "  FAIL  ") + label)
    if not cond:
        bad += 1

want = {"VMMREQ_REPORT_GUEST_INFO": 50, "VMMREQ_GET_DISPLAY_CHANGE2": 54, "VMMREQ_SET_GUEST_CAPS": 56,
        "VMMREQ_REPORT_GUEST_INFO2": 58, "VMMREQ_REPORT_GUEST_STATUS": 59, "VMM_CAP_GRAPHICS": 4, "VMM_EVENT_DISPLAY": 4,
        "VMM_FAC_GRAPHICS": 1100, "VMM_FAC_DRIVER": 20, "VMM_ST_ACTIVE": 50, "VMM_HDR_VERSION": 0x10001, "VMM_VERSION": 0x10004}
for k, v in want.items():
    check("vmmdev const %s == %d" % (k, v), const(k) == v)

init = body("vmm_init")
hint = body("vmm_hint_locked")
stat = body("vmm_status")
sizes = [("VMMREQ_REPORT_GUEST_INFO", 32, init), ("VMMREQ_REPORT_GUEST_INFO2", 24 + 144, init), ("VMMREQ_SET_GUEST_CAPS", 32, init),
         ("VMMREQ_GET_DISPLAY_CHANGE2", 44, hint), ("VMMREQ_REPORT_GUEST_STATUS", 36, stat)]
for name, size, fn in sizes:
    m = re.search(r"vmm_call\(state, %s, ([0-9 +]+)\)" % name, fn)
    val = eval(m.group(1)) if m else None
    check("request %s has size %s (header 24 + body)" % (name, size), val == size)

check("GetDisplayChangeRequest2: event_ack (offset 36) = VMM_EVENT_DISPLAY", re.search(r"regio\.write32_at\(rq, 36, VMM_EVENT_DISPLAY\)", hint) is not None)
check("GetDisplayChangeRequest2: display index (offset 40) = 0", re.search(r"regio\.write32_at\(rq, 40, 0\)", hint) is not None)
check("GetDisplayChangeRequest2: xres/yres read at offsets 24/28", "regio.read32_at(rq, 24)" in hint and "regio.read32_at(rq, 28)" in hint)
check("guest info 2: name at offset 40, additions version major in the low half of word 24",
      "regio.write32_at(p, 40," in init and re.search(r"regio\.write32_at\(p, 24, \(2 << 16\) \| 7\)", init) is not None)
check("capabilities: graphics bit announced (set mask offset 24)", re.search(r"regio\.write32_at\(p, 24, VMM_CAP_GRAPHICS\)", init) is not None)
check("no event filter mask (the host would raise the VMMDev interrupt, no handler: VM froze after a resize hint)", "CTL_FILTER" not in init and "VMM_EVENT_DISPLAY)" not in init)
print("vmmlint: %d fail" % bad)
sys.exit(1 if bad else 0)
