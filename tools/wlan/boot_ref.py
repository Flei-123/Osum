#!/usr/bin/env python3
import struct

def fnv(b):
    h = 0x811C9DC5
    for x in b:
        h = ((h ^ x) * 0x01000193) & 0xFFFFFFFF
    return h

def hdr(cmd, slot):
    return struct.pack("<BBH", cmd, 0, slot & 0xFF)

def sec_size(s):
    return {1: 3000, 3: 100, 5: 2048, 11: 6, 12: 40}.get(s, 0)

def sec_data(s, off, n):
    return bytes(((s * 7 + off + i) & 255) for i in range(n))

def expected():
    cmds = []
    nvm = b""
    slot = 0
    for s in (1, 3, 4, 5, 11, 12):
        off = 0
        while True:
            cmds.append(hdr(0x88, slot) + struct.pack("<BBHHH", 0, 0, s, off, 2048))
            slot += 1
            size = sec_size(s)
            if off >= size:
                break
            n = min(2048, size - off)
            nvm += sec_data(s, off, n)
            off += n
            if n < 2048:
                break
    cmds.append(hdr(0x98, slot) + struct.pack("<I", 3))
    slot += 1
    cmds.append(hdr(0x6A, slot) + struct.pack("<III", 0x00330F00, 1, 2))
    slot += 1
    cfg = bytes((0x10 + i) & 255 for i in range(8))
    nch = bytes((0x30 + i) & 255 for i in range(12))
    papd1 = struct.pack("<H", 1) + bytes((0x40 + i) & 255 for i in range(2, 6))
    papd0 = struct.pack("<H", 0) + bytes((0x50 + i) & 255 for i in range(2, 6))
    seen = bytes([7, 0, 0, 0, 0, 0, 0, 0, 0x2a, 0x14, 0, 0, 0x28, 0x48, 0, 0, 0x26, 0x78, 0, 0, 0x06, 0xb4, 0, 0, 0x04, 0xe0, 0, 0])
    txp = seen + bytes((0x60 + i) & 255 for i in range(28, 2056))
    for typ, data in ((1, cfg), (2, nch), (4, papd0), (4, papd1), (5, txp)):
        cmds.append(hdr(0x6C, slot) + struct.pack("<HH", typ, len(data)) + data)
        slot += 1
    cmds.append(hdr(0x98, slot) + struct.pack("<I", 3))
    slot += 1
    cmds.append(hdr(0x6A, slot) + struct.pack("<III", 0x00330F00, 0, 4))
    return cmds, nvm, len(cfg) + len(nch) + len(papd0) + len(papd1) + len(txp)

cmds, nvm, cb = expected()
print("S full init=0 rt=0 phase=ready failed_at=idle err=0 cmds=%d notifs=17 nvm=1 nbytes=%d/5 calib=5/%d replayed=5 fnv=%08x" % (len(cmds), len(nvm), cb, fnv(nvm)))
for c in cmds:
    print("cmd " + c.hex())
empty = fnv(b"")
f3000 = fnv(sec_data(1, 0, 2048) + sec_data(1, 2048, 952))
print("S nocmdq init=0 rt=0 phase=rt_alive failed_at=idle err=0 cmds=0 notifs=0 nvm=2 nbytes=0/0 calib=0/0 replayed=0 fnv=%08x" % empty)
print("S require init=-60 rt=0 phase=failed failed_at=nvm err=-60 cmds=0 notifs=0 nvm=3 nbytes=0/0 calib=0/0 replayed=0 fnv=%08x" % empty)
print("S badnvm1 init=-63 rt=0 phase=failed failed_at=nvm err=-63 cmds=1 notifs=1 nvm=3 nbytes=0/0 calib=0/0 replayed=0 fnv=%08x" % empty)
print("S noinitc init=-62 rt=0 phase=failed failed_at=init_complete err=-62 cmds=10 notifs=16 nvm=1 nbytes=%d/5 calib=5/%d replayed=0 fnv=%08x" % (len(nvm), cb, fnv(nvm)))
print("S shortn init=-69 rt=0 phase=failed failed_at=nvm err=-69 cmds=3 notifs=3 nvm=3 nbytes=3000/0 calib=0/0 replayed=0 fnv=%08x" % f3000)
print("S sendbad init=-61 rt=0 phase=failed failed_at=nvm err=-61 cmds=5 notifs=4 nvm=3 nbytes=3100/0 calib=0/0 replayed=0 fnv=%08x" % fnv(f3000 and (sec_data(1, 0, 2048) + sec_data(1, 2048, 952) + sec_data(3, 0, 100))))
print("S rxbad init=-68 rt=0 phase=failed failed_at=nvm err=-68 cmds=1 notifs=0 nvm=3 nbytes=0/0 calib=0/0 replayed=0 fnv=%08x" % empty)
print("S nvmfull init=-65 rt=0 phase=failed failed_at=nvm err=-65 cmds=3 notifs=3 nvm=3 nbytes=3000/0 calib=0/0 replayed=0 fnv=%08x" % f3000)
print("S poolfull init=-66 rt=0 phase=failed failed_at=init_complete err=-66 cmds=10 notifs=12 nvm=1 nbytes=%d/5 calib=3/18 replayed=0 fnv=%08x" % (len(nvm), fnv(nvm)))
print("S offbad init=-64 rt=0 phase=failed failed_at=nvm err=-64 cmds=3 notifs=3 nvm=3 nbytes=3000/0 calib=0/0 replayed=0 fnv=%08x" % f3000)
print("S oldtype init=-71 rt=0 phase=failed failed_at=init_complete err=-71 cmds=10 notifs=16 nvm=1 nbytes=%d/5 calib=5/38 replayed=0 fnv=%08x" % (len(nvm), fnv(nvm)))
