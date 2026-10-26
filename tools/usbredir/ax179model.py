import struct
import time

ACCESS_MAC = 1
ACCESS_PHY = 2
PHYPWR = 0x26
CLK = 0x33
NODE_ID = 0x10
RX_CTL = 0x0B
MEDIUM = 0x22
QCTRL = 0x2E
LINK_STATUS = 0x02
PHY_BMCR = 0
PHY_PHYSR = 0x11
IPRL = 0x20


def pad_frame(f):
    return f.ljust(60, b'\0')


class Ax179Model:
    def __init__(self, mac, log, link='up', usb='ss', multi=1, giga=True):
        self.mac = mac
        self.log = log
        self.link = link
        self.usb = usb
        self.multi = multi
        self.giga = giga
        self.regs = {}
        self.pwr_stage = 0
        self.nodeid_valid = False
        self.an_started = None
        self.violations = 0
        self.bad_tx = 0
        self.frames_out = 0

    def violation(self, text):
        self.violations += 1
        self.log('VIOLATION %s' % text)

    def reg_get(self, reg, size):
        return int.from_bytes(self.regs.get(reg, bytes(size))[:size].ljust(size, b'\0'), 'little')

    def link_is_up(self):
        if self.an_started is None or self.link == 'down':
            return False
        if self.link == 'late':
            return time.time() - self.an_started >= 4.0
        return True

    def physr(self):
        if not self.link_is_up():
            return 0
        speed = 0x8000 if self.giga else 0x4000
        return speed | 0x2000 | 0x0400

    def can_rx(self):
        rx_ctl = self.reg_get(RX_CTL, 2)
        medium = self.reg_get(MEDIUM, 2)
        return bool(rx_ctl & 0x80) and bool(medium & 0x100) and self.link_is_up()

    def mac_write(self, reg, size, data):
        data = bytes(data[:size])
        self.log('W mac %02x %d %s' % (reg, size, data.hex()))
        if reg == PHYPWR:
            v = int.from_bytes(data, 'little')
            if v == 0:
                self.pwr_stage = 1
            elif v == IPRL and self.pwr_stage == 1:
                self.pwr_stage = 2
        elif reg == CLK:
            if data[0] & 0x03 == 0x03:
                if self.pwr_stage != 2:
                    self.violation('clock select before PHY reset')
                self.nodeid_valid = True
        elif reg == RX_CTL and size != 2:
            self.violation('rx control width %d' % size)
        elif reg == NODE_ID and not self.nodeid_valid:
            self.violation('node id written before clock select')
        if reg == MEDIUM:
            self.log('medium=%04x' % int.from_bytes(data, 'little'))
        self.regs[reg] = data

    def mac_read(self, reg, size):
        if reg == NODE_ID:
            if not self.nodeid_valid:
                self.violation('node id read before clock select')
                return bytes(size)
            return self.mac[:size]
        if reg == LINK_STATUS:
            return bytes([0x04 if self.usb == 'ss' else 0x02])[:size]
        return self.regs.get(reg, bytes(size))[:size].ljust(size, b'\0')

    def phy_read(self, reg):
        if reg == PHY_BMCR:
            return 0x1140
        if reg == PHY_PHYSR:
            return self.physr()
        return 0

    def phy_write(self, reg, val):
        self.log('W phy %02x 2 %04x' % (reg, val))
        if reg == PHY_BMCR and (val & 0x1200) == 0x1200:
            self.an_started = time.time()
            self.log('phy autoneg restarted')

    def control(self, rt, req, val, idx, data, ln):
        if req == ACCESS_MAC and rt == 0xC0:
            if idx != ln:
                self.violation('mac read index %d != length %d' % (idx, ln))
            self.log('R mac %02x %d' % (val, ln))
            return self.mac_read(val, ln)
        if req == ACCESS_MAC and rt == 0x40:
            if idx != ln or len(data) != ln:
                self.violation('mac write index %d length %d data %d' % (idx, ln, len(data)))
            self.mac_write(val, ln, data)
            return b''
        if req == ACCESS_PHY and rt == 0xC0:
            if val != 3:
                self.violation('phy id %d' % val)
            return struct.pack('<H', self.phy_read(idx))[:ln]
        if req == ACCESS_PHY and rt == 0x40:
            if val != 3:
                self.violation('phy id %d' % val)
            self.phy_write(idx, struct.unpack_from('<H', data)[0])
            return b''
        return None

    def unwrap_out(self, data):
        if len(data) < 8:
            self.bad_tx += 1
            self.log('bad tx: %d octets' % len(data))
            return []
        n, h2 = struct.unpack_from('<II', data)
        pad = 1 if (h2 & 0x80008000) == 0x80008000 else 0
        if n == 0 or n > 1536 or len(data) != 8 + n + pad:
            self.bad_tx += 1
            self.log('bad tx: len=%d h2=%08x total=%d' % (n, h2, len(data)))
            return []
        if pad == 0 and (len(data) % 512) == 0:
            self.bad_tx += 1
            self.log('bad tx: multiple of the packet size without padding flag')
            return []
        if pad == 1 and ((n + 8) % 512) != 0:
            self.bad_tx += 1
            self.log('bad tx: padding flag on a frame that needs none')
            return []
        if not self.can_rx():
            self.log('tx dropped: link or receive path not enabled')
            return []
        self.frames_out += 1
        return [data[8:8 + n]]

    def wrap_in(self, frames):
        if not self.can_rx():
            self.log('rx held back: receive path not enabled')
            return None
        body = b''
        meta = b''
        for f in frames:
            f = pad_frame(f)
            pkt = b'\0\0' + f
            body += pkt.ljust((len(pkt) + 7) & ~7, b'\0')
            meta += struct.pack('<I', len(pkt) << 16)
            meta += struct.pack('<I', 0x80000000)
        tail = bytes(4) + struct.pack('<HH', 2 * len(frames), len(body))
        return body + meta + tail
