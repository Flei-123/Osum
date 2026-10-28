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
out['pc3'] = hdr(0x6a, 9, 4) + struct.pack('<IIIIIII', 0x00330F00, 0xFFFFFFFF, 1, 0, 0, 0, 0)
out['sfc'] = hdr(0xd1, 9, 12) + struct.pack('<III', 3, 4096, 8192) + struct.pack('<10I', *([1000000] * 10)) + struct.pack('<10I', *([400, 160] * 5))
out['btc'] = hdr(0x9b, 9, 13) + struct.pack('<II', 1, 0x14)
out['ant'] = hdr(0x98, 9, 5) + struct.pack('<I', 3)
out['ctx'] = hdr(0x08, 0, 6) + struct.pack('<IIII', 1 | (2 << 8), 1, 0, 0) + struct.pack('<BBBB', 1, 6, 0, 0) + struct.pack('<IIII', 3, 0x1406, 0, 0)
out['ctw'] = hdr(0x08, 0, 17) + struct.pack('<IIII', 1 | (2 << 8), 1, 0, 0) + struct.pack('<IBBBB', 6, 1, 0, 0, 0) + struct.pack('<IIII', 3, 0x1406, 0, 0)
out['sta'] = hdr(0x18, 0, 7) + struct.pack('<BBHI6sHBBHIIBBHHHHHI', 0, 0, 0, 0x0100, mac, 0, 0, 0, 0, 4, 0xFF, 0, 0, 0, 0, 0, 1, 0, 0x10)
out['key'] = sta_key(0, 8, 0, 1, 0, False)
out['gkey'] = sta_key(0, 9, 1, 2, 2, True)
bssid = bytes([0x10, 0x20, 0x30, 0x40, 0x50, 0x60])
chans = bytes([1, 6, 11, 36])
probe = bytes(0x40 + i for i in range(40))
frame = bytes(0x80 + i for i in range(30))
acs = b''.join(struct.pack('<HHBBH', 15 + a, 1023 - a, 2 + a, 1 << (a & 3), 47 * a) for a in range(5))
mac_common = struct.pack('<IIII', 1 | (2 << 8), 1, 5, 0) + mac + b'\0\0' + bssid + b'\0\0' + struct.pack('<IIIIIII', 0xF, 0x15F, 3, 1, 1, 0x4C, 3) + acs
mac_sta = struct.pack('<IIQIIIIIII', 1, 100, 0x0102030405060708, 100, 0, 3, 1, 10, 7, 55)
out['mac'] = hdr(0x28, 0, 10) + mac_common + mac_sta.ljust(48, b'\0')
out['bnd'] = hdr(0x2b, 0, 11) + struct.pack('<IIIIII', 2 | (1 << 8), 1, 1 | (2 << 8), 0xffffffff, 0xffffffff, 1 | (2 << 8))
out['scf'] = hdr(0x0c, 0, 12) + struct.pack('<IIIIII', 0x1 | 0x100 | 0x200 | 0x800 | 0x8000 | (4 << 26), 3, 3, 0xFF, 50, 120) + struct.pack('<BBBB', 20, 110, 40, 0) + mac + struct.pack('<BB', 2, 1) + chans
chcfg = b''.join(struct.pack('<IBBH', f, c, 1, 0) for f, c in [(0x40000000, 1), (0x40000000, 6), (0x80000000, 36)])
head = struct.pack('<IIIHBB', 2, 5, 4, 0x20 | 0x40, 0, 0) + struct.pack('<BBBBIII', 0, 20, 110, 40, 50, 120, 2) + struct.pack('<BBH', 1, 3, 0)
buf = (probe[:24] + probe[24:30] + probe[30:34] + probe[34:40]).ljust(512, b'\0')
preq = struct.pack('<HHHHHHHH', 0, 24, 24, 6, 30, 4, 34, 6) + buf
sched = struct.pack('<HBBHBB', 0, 1, 0, 0, 0, 0)
tail = sched + struct.pack('<HH', 0, 0) + preq + (bytes([0, 4]) + b'HPAP').ljust(34, b'\0') + bytes(34 * 19)
out['srq'] = hdr(0x0d, 0, 13) + head + chcfg + tail
head7 = struct.pack('<IIIHBB', 2, 5, 0, 0x20 | 0x40, 0, 0) + struct.pack('<BBBBBB', 10, 110, 44, 2, 10, 0) + struct.pack('<HIIIII', 300, 50, 50, 120, 120, 6) + struct.pack('<BBH', 1, 3, 0)
assert len(head7) == 48
out['sr7'] = hdr(0x0d, 0, 16) + head7 + chcfg + tail
out['sab'] = hdr(0x0e, 0, 14) + struct.pack('<II', 5, 0)
txc = struct.pack('<HHIIIBBBB', 30, 0, 0x8 | 0x2000, 0, 0x4001, 1, 0, 0, 0) + key + struct.pack('<IIIBBBBHH', 0, 0xFFFF, 0x34ABCD00, 0x12, 15, 7, 0, 0, 0)
out['tx'] = hdr(0x1c, 2, 15) + txc + frame
for k in ['nvm', 'phy', 'pc3', 'sfc', 'btc', 'ant', 'ctx', 'ctw', 'sta', 'key', 'gkey', 'mac', 'bnd', 'scf', 'srq', 'sr7', 'sab', 'tx']:
    print(k, out[k].hex())
