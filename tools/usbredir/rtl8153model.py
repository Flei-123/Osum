import struct
import time

PLA = 0x0100
USB = 0x0000
VERSIONS = {'8152': 0x4C10, '8153a': 0x5C10, '8153b': 0x6010, 'unknown': 0x7410}
TCR0 = 0xE610
BOOT_CTRL = 0xE004
IDR = 0xC000
GPHY_BASE = 0xE86C
CR = 0xE813
MISC_1 = 0xE85A
OOB_CTRL = 0xE84F
RCR = 0xC010
PHYSTATUS = 0xE908
USB_CTRL = 0xD406


def pad_frame(f):
    return f.ljust(60, b'\0')


class Rtl8153Model:
    def __init__(self, mac, log, family='8153a', link='up', multi=1):
        self.mac = mac
        self.log = log
        self.family = family
        self.link = link
        self.multi = multi
        self.dw = {}
        self.reads = {}
        self.violations = 0
        self.bad_tx = 0
        self.an_started = None
        self.phy = {0: 0x1940, 4: 0x0001, 9: 0x0000}
        self.frames_out = 0
        self.dw[(PLA, TCR0)] = VERSIONS[family] << 16
        self.put(PLA, MISC_1, 2, 0x0008)
        self.put(PLA, OOB_CTRL, 1, 0x82)
        self.put(USB, USB_CTRL, 2, 0x0090)

    def violation(self, text):
        self.violations += 1
        self.log('VIOLATION %s' % text)

    def put(self, ty, addr, size, value):
        base = addr & 0xFFFC
        sh = (addr & 3) * 8
        mask = ((1 << (8 * size)) - 1) << sh
        old = self.dw.get((ty, base), 0)
        self.dw[(ty, base)] = (old & ~mask) | ((value << sh) & mask)

    def val(self, ty, addr, size):
        d = self.dw.get((ty, addr & 0xFFFC), 0)
        return (d >> ((addr & 3) * 8)) & ((1 << (8 * size)) - 1)

    def autoload_done(self):
        return self.reads.get('boot', 0) >= 3

    def phy_powered(self):
        return not (self.phy[0] & 0x0800)

    def link_is_up(self):
        if self.an_started is None or self.link == 'down' or not self.phy_powered():
            return False
        if self.link == 'late':
            return time.time() - self.an_started >= 4.0
        return True

    def phystatus(self):
        return 0x13 if self.link_is_up() else 0

    def aggregate(self):
        return not (self.val(USB, USB_CTRL, 2) & 0x0090)

    def can_rx(self):
        cr = self.val(PLA, CR, 1)
        rcr = self.val(PLA, RCR, 4)
        gated = self.val(PLA, MISC_1, 2) & 0x0008
        return bool(cr & 0x08) and bool(rcr & 0x08) and not gated and self.link_is_up()

    def can_tx(self):
        return bool(self.val(PLA, CR, 1) & 0x04) and self.link_is_up()

    def ocp_base(self):
        return self.val(PLA, GPHY_BASE, 2)

    def phy_reg_of(self, addr):
        if self.ocp_base() != 0xA000 or (addr & 0xF000) != 0xB000:
            return None
        return ((0xA000 | (addr & 0x0FFF)) - 0xA400) // 2

    def phy_word(self, addr):
        reg = self.phy_reg_of(addr)
        if reg is None:
            return 0
        if reg == 0x10:
            return 3 if self.phy_powered() else 5
        return self.phy.get(reg, 0)

    def read_dword(self, ty, a):
        if ty == PLA and a == (BOOT_CTRL & 0xFFFC):
            self.reads['boot'] = self.reads.get('boot', 0) + 1
            return 0x0002 if self.autoload_done() else 0
        if ty == PLA and a in (IDR, IDR + 4):
            if not self.autoload_done():
                self.violation('IDR read before autoload done')
                return 0
            return struct.unpack_from('<I', self.mac + bytes(2), a - IDR)[0]
        if ty == PLA and a == (CR & 0xFFFC):
            v = self.val(PLA, CR, 1)
            if v & 0x10:
                n = self.reads.get('cr', 0) + 1
                self.reads['cr'] = n
                if n >= 2:
                    self.put(PLA, CR, 1, v & ~0x10)
                    self.reads['cr'] = 0
        if ty == PLA and a == PHYSTATUS:
            return self.phystatus()
        if ty == PLA and (a & 0xF000) == 0xB000:
            return self.phy_word(a) | (self.phy_word(a + 2) << 16)
        return self.dw.get((ty, a), 0)

    def write_dword(self, ty, a, mask, value):
        tag = 'pla' if ty == PLA else 'usb'
        self.log('W %s %04x m=%x %08x' % (tag, a, mask, value))
        old = self.dw.get((ty, a), 0)
        new = old
        for i in range(4):
            if mask & (1 << i):
                new = (new & ~(0xFF << (8 * i))) | (value & (0xFF << (8 * i)))
        self.dw[(ty, a)] = new
        if ty == PLA and (a & 0xF000) == 0xB000:
            for half in (0, 2):
                if mask & (3 << half):
                    self.phy_write(a + half, (value >> (8 * half)) & 0xFFFF)

    def phy_write(self, addr, v):
        reg = self.phy_reg_of(addr)
        if reg is None:
            return
        self.phy[reg] = v
        if reg == 0 and (v & 0x1200) == 0x1200 and not (v & 0x0800):
            self.an_started = time.time()
            self.log('phy autoneg restarted')

    def control(self, rt, req, val, idx, data, ln):
        if req != 5:
            return None
        ty = idx & 0xFF00
        if rt == 0xC0:
            out = b''
            a = val
            while len(out) < ln:
                out += struct.pack('<I', self.read_dword(ty, a & 0xFFFC))
                a += 4
            return out[:ln]
        if rt == 0x40:
            mask = idx & 0x0F
            a = val
            pos = 0
            while pos < len(data):
                chunk = data[pos:pos + 4].ljust(4, b'\0')
                m = mask if len(data) == 4 else 0xF
                self.write_dword(ty, a & 0xFFFC, m, struct.unpack('<I', chunk)[0])
                a += 4
                pos += 4
            return b''
        return None

    def unwrap_out(self, data):
        frames = []
        pos = 0
        while pos + 8 <= len(data):
            opts1, opts2 = struct.unpack_from('<II', data, pos)
            n = opts1 & 0x3FFFF
            if (opts1 & 0xC0000000) != 0xC0000000 or n == 0 or pos + 8 + n > len(data):
                self.bad_tx += 1
                self.log('bad tx desc %08x at %d of %d' % (opts1, pos, len(data)))
                return frames
            if not self.can_tx():
                self.log('tx dropped: transmitter or link not enabled')
            else:
                frames.append(data[pos + 8:pos + 8 + n])
                self.frames_out += 1
            pos = (pos + 8 + n + 3) & ~3
        return frames

    def wrap_in(self, frames):
        if not self.can_rx():
            self.log('rx held back: receiver not enabled')
            return None
        out = b''
        for f in frames:
            pkt = pad_frame(f) + bytes(4)
            out = out.ljust((len(out) + 7) & ~7, b'\0')
            out += struct.pack('<IIIIII', len(pkt) & 0x7FFF, 0, 0, 0, 0, 0)
            out += pkt
        return out
