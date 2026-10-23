#!/usr/bin/env python3
# Independent reference for lib/wlan/iwl_mvm.fi: struct.pack from the uapi header reading (no shared code).
import struct, sys
def hdr(cmd, q, slot): return struct.pack('<BBH', cmd, 0, ((q & 0x1f) << 8) | (slot & 0xff))
mac = bytes([0x02, 0x11, 0x22, 0x33, 0x44, 0x55])
key = bytes(0xA0 + i for i in range(16))
pn = bytes([1, 0, 0, 0, 0, 0])
def sta_key(q, slot, sta, off, keyid, mc):
    fl = 2 | (keyid << 8) | (0x4000 if mc else 0)
    common = struct.pack('<BBH', sta, off, fl) + key.ljust(32, b'\0') + pn.ljust(16, b'\0')
    return hdr(0x17, q, slot) + common + struct.pack('<QQQ', 0, 0, 0)
out = {}
out['nvm'] = hdr(0x88, 9, 3) + struct.pack('<BBHHH', 0, 0, 5, 0x120, 0x200)
out['phy'] = hdr(0x6a, 9, 4) + struct.pack('<III', 0x00330F00, 0xFFFFFFFF, 1)
out['ant'] = hdr(0x98, 9, 5) + struct.pack('<I', 3)
out['ctx'] = hdr(0x08, 0, 6) + struct.pack('<IIII', 1 | (2 << 8), 1, 0, 0) + struct.pack('<IBBBB', 6, 1, 0, 0, 0) + struct.pack('<IIII', 0x6a, 0x6a, 0, 0)
out['sta'] = hdr(0x18, 0, 7) + struct.pack('<BBHI6sHBBHIIBBHHHHHI', 0, 0, 0, 0x0100, mac, 0, 0, 0, 0, 4, 0xFF, 0, 0, 0, 0, 0, 1, 0, 0x10)
out['key'] = sta_key(0, 8, 0, 1, 0, False)
out['gkey'] = sta_key(0, 9, 1, 2, 2, True)
for k in ['nvm', 'phy', 'ant', 'ctx', 'sta', 'key', 'gkey']:
    print(k, out[k].hex())
