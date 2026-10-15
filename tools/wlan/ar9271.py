#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/wlan/ar9271.py -- independent check of the AR9271 host test.

Runs the Firn test (tools/wlan/ar9271.fi, built as argv[1]) with a blob on
stdin and re-derives every logged wire frame with struct.pack from the
layouts in the Linux ath9k sources (htc_hst.h / wmi.h / hif_usb.c).
The Firn code and this script share no code, so a wrong byte order or a
wrong field offset shows up as a mismatch, not as two equal mistakes.

usage: ar9271.py <binary> <blob> [--real]
exit 0 = all OK. Prints OK/FAIL lines like the other wlan sections.
"""
import hashlib
import struct
import subprocess
import sys

ok = fail = 0


def check(name, cond):
    global ok, fail
    if cond:
        ok += 1
        print("  OK    " + name)
    else:
        fail += 1
        print("  FAIL  " + name)


def htc(ep, payload):
    return struct.pack(">BBH4x", ep, 0, len(payload)) + payload


def main():
    binary, blob_path = sys.argv[1], sys.argv[2]
    blob = open(blob_path, "rb").read()
    p = subprocess.run([binary], input=blob, capture_output=True, timeout=60)
    out = p.stdout.decode("ascii", "replace").splitlines()
    check("test binary exit code 0 (rc=%d)" % p.returncode, p.returncode == 0)
    inner_fail = [l for l in out if l.startswith("FAIL ")]
    check("no FAIL line inside the Firn test", not inner_fail)
    for l in inner_fail:
        print("        " + l)
    summary = [l for l in out if l.startswith("AR9271: ")]
    check("summary line present", len(summary) == 1)

    # --- firmware download requests -------------------------------------
    ctrl = [l.split()[1:] for l in out if l.startswith("CTRL ")]
    exp = []
    addr, off = 0x501000, 0
    while off < len(blob):
        n = min(4096, len(blob) - off)
        exp.append(["48", str(addr >> 8), "0", str(n)])
        addr += n
        off += n
    exp.append(["49", str(0x903000 >> 8), "0", "0"])
    check("control transfers = 0x30 chunks + 0x31 (%d)" % len(exp),
          ctrl == exp)

    # --- the firmware hash the simulated chip saw -----------------------
    fh = [l.split()[1] for l in out if l.startswith("FWHASH ")]
    check("chip received the blob bit-exact (sha256)",
          fh == [hashlib.sha256(blob).hexdigest()])

    # --- HTC/WMI frames the driver sent ---------------------------------
    tx = [bytes.fromhex(l.split()[1]) for l in out if l.startswith("TX ")]
    want = [
        # connect WMI control: msg 2, service 0x0100, flags 0, dl pipe 3,
        # ul pipe 4, meta 0, pad 0
        htc(0, struct.pack(">HHHBBBB", 2, 0x0100, 0, 3, 4, 0, 0)),
        # config pipe: msg 5, pipe 1, credits 8 (from READY)
        htc(0, struct.pack(">HBB", 5, 1, 8)),
        # setup complete: msg 4
        htc(0, struct.pack(">H", 4)),
        # WMI REG_READ (id 20) on endpoint 2, seq 1, reg 0x4020
        htc(2, struct.pack(">HHI", 20, 1, 0x4020)),
    ]
    check("4 frames sent during boot", len(tx) == 4)
    for i, (g, w) in enumerate(zip(tx, want)):
        check("frame %d bytes identical to struct.pack layout" % (i + 1),
              g == w)

    # --- WMI command ids: recount the enum from wmi.h order --------------
    names = ("ECHO ACCESS_MEMORY GET_FW_VERSION DISABLE_INTR ENABLE_INTR "
             "ATH_INIT ABORT_TXQ STOP_TX_DMA ABORT_TX_DMA DRAIN_TXQ "
             "DRAIN_TXQ_ALL START_RECV STOP_RECV FLUSH_RECV SET_MODE "
             "NODE_CREATE NODE_REMOVE VAP_REMOVE VAP_CREATE REG_READ "
             "REG_WRITE RC_STATE_CHANGE RC_RATE_UPDATE TARGET_IC_UPDATE "
             "TX_AGGR_ENABLE TGT_DETACH NODE_UPDATE INT_STATS TX_STATS "
             "RX_STATS BITRATE_MASK REG_RMW").split()
    ids = {n: i + 1 for i, n in enumerate(names)}
    check("WMI REG_READ id 20 / REG_WRITE 21 / REG_RMW 32 (enum order)",
          (ids["REG_READ"], ids["REG_WRITE"], ids["REG_RMW"]) == (20, 21, 32))

    print("AR9271-PY: %d Zusagen, %d Fehler" % (ok, fail))
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
