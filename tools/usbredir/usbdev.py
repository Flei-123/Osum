#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# Emulated USB network gadgets behind QEMU's usb-redir (QEMU has no CDC-NCM model of its own).
#
#   usbdev.py --sock PATH --profile ncm|ncm-multi|android-rndis|android-ncm|ecm
#             [--net-local PORT --net-remote PORT] [--trigger FILE] [--unplug FILE] [--log FILE]
#
# QEMU:  -chardev socket,id=r0,path=PATH,server=on,wait=off -device usb-redir,chardev=r0
# The script connects, answers the usbredir hello and (after the trigger file appears) presents the device.
# Ethernet frames go over UDP datagrams to a helper QEMU (slirp router: DHCP, DNS, NAT) -- see usbredir/run.sh.
import argparse, os, socket, struct, sys, time, select
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import marke

T_HELLO, T_CONNECT, T_DISCONNECT, T_RESET, T_IFINFO, T_EPINFO, T_SETCFG, T_GETCFG, T_CFGSTAT, T_SETALT, \
    T_GETALT, T_ALTSTAT, T_ISOSTART, T_ISOSTOP, T_ISOSTAT, T_INTSTART, T_INTSTOP, T_INTSTAT = range(18)
T_CANCEL = 21
T_CONTROL, T_BULK, T_ISO, T_INTERRUPT = 100, 101, 102, 103
CAP_STREAMS, CAP_CONNECT_VERSION, CAP_EP_MPS, CAP_IDS64, CAP_BULK32 = 0, 1, 4, 5, 6

ap = argparse.ArgumentParser()
ap.add_argument('--sock', required=True)
ap.add_argument('--profile', default='ncm')
ap.add_argument('--net-local', type=int, default=0)
ap.add_argument('--net-remote', type=int, default=0)
ap.add_argument('--trigger', default='')
ap.add_argument('--unplug', default='')
ap.add_argument('--log', default='')
ap.add_argument('--mac', default='02:11:22:33:44:55')
ap.add_argument('--caps', default='')
ap.add_argument('--max-secs', type=int, default=240)
ap.add_argument('--phy-boot', default='down')
ap.add_argument('--phy-deaf', action='store_true')
ap.add_argument('--intr', default='off')
ap.add_argument('--bt', default='normal')
ap.add_argument('--link', default='up')
ap.add_argument('--usb', default='ss')
ap.add_argument('--rtl-family', default='8153a')
ap.add_argument('--speed', type=int, default=2)
ap.add_argument('--inject', type=int, default=0)
A = ap.parse_args()
MAC = bytes(int(x, 16) for x in A.mac.split(':'))
LOGF = open(A.log, 'w') if A.log else sys.stderr


def log(s):
    LOGF.write('%.2f %s\n' % (time.time() % 1000, s))
    LOGF.flush()


def u16(x): return struct.pack('<H', x)
def u32(x): return struct.pack('<I', x)


def sdesc(text):
    b = text.encode('utf-16-le')
    return bytes([2 + len(b), 3]) + b


STRINGS = {1: marke.PRODUKT + ' Lab', 2: 'Tether Gadget', 3: '0123456789', 4: ''.join('%02X' % x for x in MAC), 5: 'ADB'}


def ep_desc(addr, attr, mps, ival):
    return bytes([7, 5, addr, attr]) + u16(mps) + bytes([ival])


def iface(num, alt, neps, cls, sub, proto, istr=0):
    return bytes([9, 4, num, alt, neps, cls, sub, proto, istr])


def cdc_func(sub, payload):
    return bytes([3 + len(payload), 0x24, sub]) + payload


def build_cfg(value, ifaces):
    body = b''
    for it in ifaces:
        body += iface(it['n'], it['alt'], len(it['eps']), it['cls'], it['sub'], it['proto'])
        body += it.get('extra', b'')
        for e in it['eps']:
            body += ep_desc(*e)
    total = 9 + len(body)
    nif = len({it['n'] for it in ifaces})
    return bytes([9, 2]) + u16(total) + bytes([nif, value, 0, 0xC0, 50]) + body


BULK_IN, BULK_OUT, INT_IN = 0x82, 0x03, 0x81


def ncm_ifaces(first, eps=(0x81, 0x82, 0x03)):
    ci = first
    di = first + 1
    ctl_extra = (cdc_func(0, u16(0x0110)) + cdc_func(6, bytes([ci, di])) +
                 cdc_func(0x0F, bytes([4]) + u32(0) + u16(1514) + u16(0) + bytes([0])) +
                 cdc_func(0x1A, u16(0x0100) + bytes([0])))
    return [
        dict(n=ci, alt=0, cls=2, sub=0x0D, proto=0, extra=ctl_extra, eps=[(eps[0], 3, 16, 9)]),
        dict(n=di, alt=0, cls=0x0A, sub=0, proto=1, eps=[]),
        dict(n=di, alt=1, cls=0x0A, sub=0, proto=1, eps=[(eps[1], 2, 512, 0), (eps[2], 2, 512, 0)]),
    ]


def vendor_ifaces():
    return [dict(n=0, alt=0, cls=0xFF, sub=0xFF, proto=0xFF, eps=[(INT_IN, 3, 16, 1), (BULK_IN, 2, 512, 0), (BULK_OUT, 2, 512, 0)])]


def vendor_alt_ifaces():
    return [dict(n=0, alt=0, cls=0xFF, sub=0xFF, proto=0xFF, eps=[]),
            dict(n=0, alt=1, cls=0xFF, sub=0xFF, proto=0xFF, eps=[(INT_IN, 3, 16, 1), (BULK_IN, 2, 512, 0), (BULK_OUT, 2, 512, 0)])]


def bt_ifaces(proto):
    return [dict(n=0, alt=0, cls=0xE0, sub=0x01, proto=proto, eps=[(INT_IN, 3, 16, 1), (BULK_IN, 2, 64, 0), (0x02, 2, 64, 0)])]


def nic_ifaces():
    return [dict(n=0, alt=0, cls=0xFF, sub=0xFF, proto=0x00, eps=[(INT_IN, 3, 8, 11), (BULK_IN, 2, 512, 0), (BULK_OUT, 2, 512, 0)])]


def ecm_ifaces(first):
    ci = first
    di = first + 1
    ctl_extra = (cdc_func(0, u16(0x0110)) + cdc_func(6, bytes([ci, di])) +
                 cdc_func(0x0F, bytes([4]) + u32(0) + u16(1514) + u16(0) + bytes([0])))
    return [
        dict(n=ci, alt=0, cls=2, sub=6, proto=0, extra=ctl_extra, eps=[(INT_IN, 3, 16, 9)]),
        dict(n=di, alt=0, cls=0x0A, sub=0, proto=0, eps=[]),
        dict(n=di, alt=1, cls=0x0A, sub=0, proto=0, eps=[(BULK_IN, 2, 512, 0), (BULK_OUT, 2, 512, 0)]),
    ]


def rndis_ifaces(first):
    ci = first
    di = first + 1
    ctl_extra = (cdc_func(0, u16(0x0110)) + bytes([5, 0x24, 1, 0, di]) + cdc_func(2, bytes([0, 0])) +
                 cdc_func(6, bytes([ci, di])))
    return [
        dict(n=ci, alt=0, cls=0xE0, sub=1, proto=3, extra=ctl_extra, eps=[(INT_IN, 3, 8, 9)]),
        dict(n=di, alt=0, cls=0x0A, sub=0, proto=0, eps=[(BULK_IN, 2, 512, 0), (BULK_OUT, 2, 512, 0)]),
    ]


def adb_iface(n, in_ep, out_ep):
    return [dict(n=n, alt=0, cls=0xFF, sub=0x42, proto=1, eps=[(in_ep, 2, 512, 0), (out_ep, 2, 512, 0)])]


def msc_iface(n, in_ep, out_ep):
    return [dict(n=n, alt=0, cls=8, sub=6, proto=0x50, eps=[(in_ep, 2, 512, 0), (out_ep, 2, 512, 0)])]


PROFILES = {}
PROFILES['ncm'] = dict(kind='ncm', vid=0x1D6B, pid=0x0121, dcls=0, cfgs=[ncm_ifaces(0)], multi=1)
PROFILES['ncm-multi'] = dict(kind='ncm', vid=0x1D6B, pid=0x0121, dcls=0, cfgs=[ncm_ifaces(0)], multi=3)
PROFILES['ecm'] = dict(kind='ecm', vid=0x1D6B, pid=0x0102, dcls=0, cfgs=[ecm_ifaces(0)], multi=1)
PROFILES['android-rndis'] = dict(kind='rndis', vid=0x18D1, pid=0x4EE4, dcls=0, multi=1, cfgs=[
    adb_iface(0, 0x86, 0x06),
    rndis_ifaces(0) + adb_iface(2, 0x84, 0x04)])
PROFILES['android-rndis-msc'] = dict(kind='rndis', vid=0x18D1, pid=0x4EE4, dcls=0, multi=1, cfgs=[
    msc_iface(0, 0x85, 0x05) + adb_iface(1, 0x86, 0x06),
    rndis_ifaces(0) + adb_iface(2, 0x84, 0x04)])
PROFILES['android-ncm'] = dict(kind='ncm', vid=0x18D1, pid=0x4EE8, dcls=0, multi=1, cfgs=[
    adb_iface(0, 0x84, 0x04) + ncm_ifaces(1)])
PROFILES['ch336'] = dict(kind='ch336', vid=0x1A86, pid=0x5394, dcls=0, multi=1, cfgs=[vendor_ifaces(), ecm_ifaces(0)])
PROFILES['ch336-alt1'] = dict(kind='ch336', vid=0x1A86, pid=0x5394, dcls=0, multi=1, cfgs=[vendor_alt_ifaces(), ecm_ifaces(0)])
PROFILES['ch336-ecmfirst'] = dict(kind='ch336', vid=0x1A86, pid=0x5394, dcls=0, multi=1, cfgs=[ecm_ifaces(0), vendor_ifaces()])
PROFILES['btdongle'] = dict(kind='bt', vid=0x0A12, pid=0x0001, dcls=0xE0, multi=1, cfgs=[bt_ifaces(1)])
PROFILES['btdongle-badclass'] = dict(kind='bt', vid=0x0A12, pid=0x0001, dcls=0xE0, multi=1, cfgs=[bt_ifaces(2)])
PROFILES['ax88179'] = dict(kind='ax179', vid=0x0B95, pid=0x1790, dcls=0, multi=1, cfgs=[nic_ifaces(), ecm_ifaces(0)])
PROFILES['ax88179-multi'] = dict(kind='ax179', vid=0x0B95, pid=0x1790, dcls=0, multi=3, cfgs=[nic_ifaces(), ecm_ifaces(0)])
PROFILES['ax88178a'] = dict(kind='ax179', vid=0x0B95, pid=0x178A, dcls=0, multi=1, cfgs=[nic_ifaces(), ecm_ifaces(0)])
PROFILES['rtl8153'] = dict(kind='rtl', vid=0x0BDA, pid=0x8153, dcls=0, multi=1, cfgs=[nic_ifaces(), ecm_ifaces(0)])
PROFILES['rtl8153-multi'] = dict(kind='rtl', vid=0x0BDA, pid=0x8153, dcls=0, multi=3, cfgs=[nic_ifaces(), ecm_ifaces(0)])
PROFILES['rtl8152'] = dict(kind='rtl', vid=0x0BDA, pid=0x8152, dcls=0, multi=1, cfgs=[nic_ifaces(), ecm_ifaces(0)])
PROFILES['ax88179-ecmfirst'] = dict(kind='ax179', vid=0x0B95, pid=0x1790, dcls=0, multi=1, cfgs=[ecm_ifaces(0), nic_ifaces()])
PROFILES['ax-unknown'] = dict(kind='ax179', vid=0x0B95, pid=0x9999, dcls=0, multi=1, cfgs=[nic_ifaces(), ecm_ifaces(0)])
PROFILES['rtl-unknown'] = dict(kind='rtl', vid=0x0BDA, pid=0x8199, dcls=0, multi=1, cfgs=[nic_ifaces(), ecm_ifaces(0)])
PROF = PROFILES[A.profile]
KIND = PROF['kind']
CFGS = [build_cfg(i + 1, c) for i, c in enumerate(PROF['cfgs'])]


def dev_desc():
    return bytes([18, 1]) + u16(0x0200) + bytes([PROF['dcls'], 0, 0, 64]) + u16(PROF['vid']) + u16(PROF['pid']) + \
        u16(0x0310) + bytes([1, 2, 3, len(CFGS)])


def ep_index(addr):
    return (addr & 0x0F) | (0x10 if addr & 0x80 else 0)


class Link:
    def __init__(self):
        self.s = None
        if A.net_local:
            self.s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.s.bind(('127.0.0.1', A.net_local))
            self.s.setblocking(False)
        self.to_guest = []

    def send(self, frame):
        if self.s and A.net_remote:
            try:
                self.s.sendto(frame, ('127.0.0.1', A.net_remote))
            except OSError:
                pass

    def poll(self):
        if not self.s:
            return
        while True:
            try:
                d, _ = self.s.recvfrom(4096)
            except (BlockingIOError, OSError):
                return
            self.to_guest.append(d)


LINK = Link()
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ch336model import Ch336Model
from ax179model import Ax179Model
from rtl8153model import Rtl8153Model
from btmodel import BtModel
CH = Ch336Model(MAC, A.phy_boot, lambda s: log(s), not A.phy_deaf) if PROF['kind'] == 'ch336' else None
BT = BtModel(lambda s: log(s), A.bt) if PROF['kind'] == 'bt' else None
VN = None
if PROF['kind'] == 'ax179':
    VN = Ax179Model(MAC, lambda s: log(s), A.link, A.usb, PROF['multi'])
elif PROF['kind'] == 'rtl':
    VN = Rtl8153Model(MAC, lambda s: log(s), A.rtl_family, A.link, PROF['multi'])
STAT = dict(tx=0, rx=0)


def ntb_wrap(frames, seq):
    data = b''
    offs = []
    pos = 12
    for f in frames:
        pad = (4 - len(f) % 4) % 4
        offs.append((pos, len(f)))
        data += f + b'\0' * pad
        pos += len(f) + pad
    ndp = b'NCM0' + u16(8 + 4 * (len(frames) + 1)) + u16(0)
    for o, l in offs:
        ndp += u16(o) + u16(l)
    ndp = ndp + u32(0)
    ndp = ndp[:6] + u16(0) + ndp[8:]
    total = pos + len(ndp)
    return b'NCMH' + u16(12) + u16(seq) + u16(total) + u16(pos) + data + ndp


def ntb_unwrap(b):
    out = []
    if len(b) < 12 or b[:4] != b'NCMH':
        return None
    ndp = struct.unpack_from('<H', b, 10)[0]
    if ndp + 8 > len(b) or b[ndp:ndp + 4] != b'NCM0':
        return None
    p = ndp + 8
    while p + 4 <= len(b):
        o, l = struct.unpack_from('<HH', b, p)
        if o == 0 and l == 0:
            break
        out.append(b[o:o + l])
        p += 4
    return out


def rndis_pkt(frame):
    return u32(1) + u32(44 + len(frame)) + u32(36) + u32(len(frame)) + b'\0' * 28 + frame


def rndis_unwrap(b):
    out = []
    p = 0
    while p + 44 <= len(b):
        t, l, off, dl = struct.unpack_from('<IIII', b, p)
        if t != 1 or l < 44 or p + l > len(b):
            break
        out.append(b[p + 8 + off:p + 8 + off + dl])
        p += l
    return out


class Dev:
    def __init__(self, sock):
        self.sock = sock
        self.buf = b''
        self.cfg = 0
        self.alt = {}
        self.pend_in = []
        self.int_rx = set()
        self.seq = 0
        self.rndis_resp = []
        self.n_ctrl = 0
        self.got_hello = False
        self.intr_last = None
        self.intr_t = 0.0
        self.injected = False

    def tx(self, typ, rid, payload=b''):
        self.sock.setblocking(True)
        hdr = struct.pack('<III', typ, len(payload), rid) if typ == T_HELLO else struct.pack('<IIQ', typ, len(payload), rid)
        self.sock.sendall(hdr + payload)
        self.sock.setblocking(False)

    def connect_dev(self):
        self.cfg = 1
        self.alt = {}
        self.send_info()
        self.tx(T_CONNECT, 0, bytes([A.speed, PROF['dcls'], 0, 0]) + u16(PROF['vid']) + u16(PROF['pid']) + u16(0x0310))
        log('device_connect profile=%s' % A.profile)

    def active_ifaces(self):
        if not self.cfg:
            return []
        return [it for it in PROF['cfgs'][self.cfg - 1] if it['alt'] == self.alt.get(it['n'], 0)]

    def ep_active(self, ep):
        return any(e[0] == ep for it in self.active_ifaces() for e in it['eps'])

    def send_info(self):
        ifs = self.active_ifaces()
        seen = []
        n = 0
        a = [0] * 32
        c = [0] * 32
        s = [0] * 32
        p = [0] * 32
        for it in ifs:
            if it['n'] in seen:
                continue
            seen.append(it['n'])
            a[n], c[n], s[n], p[n] = it['n'], it['cls'], it['sub'], it['proto']
            n += 1
        self.tx(T_IFINFO, 0, u32(n) + bytes(a) + bytes(c) + bytes(s) + bytes(p))
        ty = [255] * 32
        iv = [0] * 32
        inf = [0] * 32
        mp = [0] * 32
        ty[0] = ty[16] = 0
        mp[0] = mp[16] = 64
        for it in ifs:
            for (addr, attr, mps, ival) in it['eps']:
                i = ep_index(addr)
                ty[i] = {2: 2, 3: 3}[attr]
                iv[i] = ival
                inf[i] = it['n']
                mp[i] = mps
        self.tx(T_EPINFO, 0, bytes(ty) + bytes(iv) + bytes(inf) + b''.join(u16(x) for x in mp) + bytes(128))

    def ctl_reply(self, rid, h, status, data=b''):
        ep, req, rt, _, val, idx, ln = h
        self.tx(T_CONTROL, rid, struct.pack('<BBBBHHH', ep, req, rt, status, val, idx, len(data)) + data)

    def handle_control(self, rid, h, data):
        ep, req, rt, _, val, idx, ln = h
        self.n_ctrl += 1
        if rt == 0x80 and req == 6:
            t, i = val >> 8, val & 255
            if t == 1:
                return self.ctl_reply(rid, h, 0, dev_desc()[:ln])
            if t == 2:
                if i < len(CFGS):
                    return self.ctl_reply(rid, h, 0, CFGS[i][:ln])
                return self.ctl_reply(rid, h, 4)
            if t == 3:
                if i == 0:
                    return self.ctl_reply(rid, h, 0, bytes([4, 3, 9, 4])[:ln])
                if i in STRINGS:
                    return self.ctl_reply(rid, h, 0, sdesc(STRINGS[i])[:ln])
            return self.ctl_reply(rid, h, 4)
        if KIND == 'ncm' and rt == 0xA1 and req == 0x80:
            mx = 16384
            par = (u16(28) + u16(1) + u32(mx) + u16(4) + u16(0) + u16(4) + u16(0) + u32(mx) + u16(4) + u16(0) +
                   u16(4) + u16(PROF['multi'] if PROF['multi'] > 1 else 0))
            return self.ctl_reply(rid, h, 0, par[:ln])
        if KIND == 'ncm' and rt == 0x21 and req == 0x86:
            return self.ctl_reply(rid, h, 0)
        if KIND in ('ncm', 'ecm') and rt == 0x21 and req in (0x43, 0x84, 0x8A):
            return self.ctl_reply(rid, h, 0)
        if KIND == 'rndis' and rt == 0x21 and req == 0:
            self.rndis_cmd(data)
            return self.ctl_reply(rid, h, 0)
        if KIND == 'rndis' and rt == 0xA1 and req == 1:
            if self.rndis_resp:
                return self.ctl_reply(rid, h, 0, self.rndis_resp.pop(0)[:ln])
            return self.ctl_reply(rid, h, 0, b'')
        if KIND == 'ch336':
            out = CH.control(rt, req, val, idx, data, ln)
            if out is not None:
                return self.ctl_reply(rid, h, 0, out)
        if BT is not None:
            out = BT.control(rt, req, val, idx, data, ln)
            if out is not None:
                return self.ctl_reply(rid, h, 0, out)
        if VN is not None:
            out = VN.control(rt, req, val, idx, data, ln)
            if out is not None:
                return self.ctl_reply(rid, h, 0, out)
        log('ctl STALL rt=%02x req=%02x val=%04x idx=%04x' % (rt, req, val, idx))
        return self.ctl_reply(rid, h, 4)

    def rndis_cmd(self, d):
        if len(d) < 12:
            return
        t, l, rid = struct.unpack_from('<III', d)
        if t == 2:
            r = (u32(0x80000002) + u32(52) + u32(rid) + u32(0) + u32(1) + u32(0) + u32(1) + u32(0) + u32(1) +
                 u32(0x4000) + u32(3) + u32(0) + u32(0))
        elif t == 4:
            oid = struct.unpack_from('<I', d, 12)[0]
            val = MAC if oid in (0x01010101, 0x01010102) else u32(0)
            r = u32(0x80000004) + u32(24 + len(val)) + u32(rid) + u32(0) + u32(len(val)) + u32(16) + val
        elif t == 5:
            r = u32(0x80000005) + u32(16) + u32(rid) + u32(0)
        elif t == 8:
            r = u32(0x80000008) + u32(16) + u32(rid) + u32(0)
        elif t == 6:
            r = u32(0x80000006) + u32(16) + u32(0) + u32(1)
        else:
            return
        log('rndis msg %x -> %x' % (t, struct.unpack_from('<I', r)[0]))
        self.rndis_resp.append(r)

    def bulk_out(self, ep, data):
        if KIND == 'ncm':
            frames = ntb_unwrap(data)
            if frames is None:
                log('ncm: bad NTB from guest (%d octets)' % len(data))
                frames = []
        elif KIND == 'rndis':
            frames = rndis_unwrap(data)
        elif KIND == 'ch336':
            frames = CH.unwrap_out(data)
        elif VN is not None:
            frames = VN.unwrap_out(data)
        else:
            frames = [data]
        if KIND == 'ch336' and not CH.started:
            frames = []
        for f in frames:
            STAT['tx'] += 1
            LINK.send(f)

    def pack_in(self):
        n = PROF['multi'] if KIND in ('ncm', 'ax179', 'rtl') else 1
        if KIND == 'rtl' and not VN.aggregate():
            n = 1
        take = []
        if KIND == 'ch336' and not CH.started:
            LINK.to_guest.clear()
        if VN is not None and not VN.can_rx():
            LINK.to_guest.clear()
            return None
        while LINK.to_guest and len(take) < n:
            take.append(LINK.to_guest.pop(0))
        if not take:
            return None
        STAT['rx'] += len(take)
        if VN is not None:
            if len(take) > 1:
                log('pack n=%d' % len(take))
            log('rx total %d' % STAT['rx'])
        if KIND == 'ncm':
            self.seq += 1
            return ntb_wrap(take, self.seq)
        if KIND == 'rndis':
            return rndis_pkt(take[0])
        if KIND == 'ch336':
            return CH.wrap_in(take[0])
        if VN is not None:
            return VN.wrap_in(take)
        return take[0]

    def inject_burst(self):
        if not A.inject or self.injected or VN is None or not VN.can_rx():
            return
        self.injected = True
        for i in range(A.inject):
            body = bytes((i * 7 + k) & 255 for k in range(46 + i * 3))
            LINK.to_guest.append(b'\xff' * 6 + bytes([0x02, 0xAA, 0xBB, 0xCC, 0xDD, i]) + b'\x88\xb5' + body)
        log('inject %d frames' % A.inject)

    def serve_in(self):
        if self.pend_in:
            self.inject_burst()
        while self.pend_in and LINK.to_guest:
            rid, ep, ln = self.pend_in.pop(0)
            b = self.pack_in()
            if b is None:
                self.pend_in.insert(0, (rid, ep, ln))
                return
            self.tx(T_BULK, rid, struct.pack('<BBHIH', ep, 0, len(b) & 0xFFFF, 0, len(b) >> 16) + b)

    def serve_bt_intr(self):
        if INT_IN not in self.int_rx:
            return
        for chunk in BT.packets(16):
            self.tx(T_INTERRUPT, 0, struct.pack('<BBH', INT_IN, 0, len(chunk)) + chunk)

    def serve_intr(self):
        if BT is not None:
            return self.serve_bt_intr()
        if KIND != 'ch336' or INT_IN not in self.int_rx:
            return
        pkt = CH.intr_packet(A.intr)
        if pkt is None:
            return
        now = time.time()
        if pkt == self.intr_last and now - self.intr_t < 1.0:
            return
        self.intr_last = pkt
        self.intr_t = now
        self.tx(T_INTERRUPT, 0, struct.pack('<BBH', INT_IN, 0, len(pkt)) + pkt)
        log('interrupt packet %s' % pkt[:1].hex())

    def handle(self, typ, rid, p):
        if typ == T_HELLO:
            return
        if typ == T_RESET:
            self.cfg = 0
            self.alt = {}
            return
        if typ == T_SETCFG:
            self.cfg = p[0]
            self.alt = {}
            self.tx(T_CFGSTAT, rid, bytes([0, self.cfg]))
            self.send_info()
            log('set_configuration %d' % self.cfg)
            return
        if typ == T_GETCFG:
            self.tx(T_CFGSTAT, rid, bytes([0, self.cfg]))
            return
        if typ == T_SETALT:
            self.alt[p[0]] = p[1]
            self.tx(T_ALTSTAT, rid, bytes([0, p[0], p[1]]))
            self.send_info()
            log('set_alt_setting if=%d alt=%d' % (p[0], p[1]))
            return
        if typ == T_GETALT:
            self.tx(T_ALTSTAT, rid, bytes([0, p[0], self.alt.get(p[0], 0)]))
            return
        if typ == T_INTSTART:
            self.int_rx.add(p[0])
            self.tx(T_INTSTAT, rid, bytes([0, p[0]]))
            return
        if typ == T_INTSTOP:
            self.int_rx.discard(p[0])
            self.tx(T_INTSTAT, rid, bytes([0, p[0]]))
            return
        if typ == T_CANCEL:
            self.pend_in = [x for x in self.pend_in if x[0] != rid]
            return
        if typ == T_CONTROL:
            h = struct.unpack_from('<BBBBHHH', p)
            self.handle_control(rid, h, p[10:])
            return
        if typ == T_BULK:
            ep, st, ln, sid, lnh = struct.unpack_from('<BBHIH', p)
            if KIND == 'ch336' and not self.ep_active(ep):
                STAT['stall'] = STAT.get('stall', 0) + 1
                log('bulk STALL ep=%02x (endpoint not in the active alt setting)' % ep)
                self.tx(T_BULK, rid, struct.pack('<BBHIH', ep, 4, 0, 0, 0))
                return
            if ep & 0x80:
                self.pend_in.append((rid, ep, ln))
                self.serve_in()
            else:
                self.bulk_out(ep, p[10:])
                self.tx(T_BULK, rid, struct.pack('<BBHIH', ep, 0, 0, 0, 0))
            return
        log('unhandled type %d' % typ)

    def feed(self, data):
        self.buf += data
        while True:
            hl = 12 if not self.got_hello else 16
            if len(self.buf) < hl:
                return
            typ, ln = struct.unpack_from('<II', self.buf)
            if len(self.buf) < hl + ln:
                return
            p = self.buf[hl:hl + ln]
            rid = struct.unpack_from('<I' if hl == 12 else '<Q', self.buf, 8)[0]
            self.buf = self.buf[hl + ln:]
            if typ == T_HELLO:
                self.got_hello = True
            self.handle(typ, rid, p)


def main():
    t0 = time.time()
    while not os.path.exists(A.sock):
        if time.time() - t0 > 60:
            sys.exit('no socket')
        time.sleep(0.1)
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    for _ in range(100):
        try:
            s.connect(A.sock)
            break
        except OSError:
            time.sleep(0.1)
    d = Dev(s)
    caps = u32((1 << CAP_STREAMS) | (1 << CAP_CONNECT_VERSION) | (1 << CAP_EP_MPS) | (1 << CAP_IDS64) | (1 << CAP_BULK32))
    if A.caps:
        caps = u32(int(A.caps, 0))
    d.tx(T_HELLO, 0, b'usbdev-lab'.ljust(64, b'\0') + caps)
    s.setblocking(False)
    plugged = False
    unplugged = False
    log('connected profile=%s' % A.profile)
    while time.time() - t0 < A.max_secs:
        LINK.poll()
        r, _, _ = select.select([s], [], [], 0.02)
        if r:
            try:
                data = s.recv(65536)
            except BlockingIOError:
                data = None
            if data == b'':
                log('qemu closed')
                break
            if data:
                d.feed(data)
        if not plugged and (not A.trigger or os.path.exists(A.trigger)):
            d.connect_dev()
            plugged = True
        if plugged and not unplugged and A.unplug and os.path.exists(A.unplug):
            d.tx(T_DISCONNECT, 0)
            unplugged = True
            log('device_disconnect')
        if plugged and not unplugged:
            d.serve_in()
            d.serve_intr()
    log('stats tx=%d rx=%d ctrl=%d' % (STAT['tx'], STAT['rx'], d.n_ctrl))
    if BT is not None:
        log('bt violations=%d commands=%d scanning=%d' % (BT.violations, len(BT.cmds), int(BT.scanning)))
    if VN is not None:
        log('model violations=%d bad_tx=%d' % (VN.violations, VN.bad_tx))


main()
