import struct

REG_MAC_CFG = 0x40000700
REG_MAC_H = 0x40000710
REG_MAC_L = 0x40000714
BMSR_NO_LINK = 0x7809
BMSR_LINK = 0x782D
FW_VERSION = 0x39
ANAR_VALUE = 0x01E1
LPA_VALUE = 0x45E1
KICK_WORD = 0xFA00


class Ch336Model:
    def __init__(self, mac, boot, log, allow_kick=True):
        self.mac = mac
        self.log = log
        self.allow_kick = allow_kick
        self.bmcr = {'down': 0x0800, 'an': 0x1000, 'iso': 0x0400}.get(boot, 0x0800)
        self.started = False
        self.maccfg = 0
        self.kicks = 0
        self.regs = {}

    def start_phy(self, how):
        self.kicks += 1
        self.log('phy kick #%d via %s' % (self.kicks, how))
        if self.allow_kick:
            self.started = True
            self.bmcr = 0x1000
            self.log('phy autoneg running, link up')

    def phy_read(self, reg):
        if reg == 0:
            return self.bmcr
        if reg == 1:
            return BMSR_LINK if self.started else BMSR_NO_LINK
        if reg == 2:
            return 0x0141
        if reg == 3:
            return 0x0E40
        if reg == 4:
            return ANAR_VALUE
        if reg == 5:
            return LPA_VALUE if self.started else 0
        if reg == 6:
            return 0x0001 if self.started else 0
        return 0

    def phy_write(self, reg, val):
        self.log('phy write reg=%d val=%04x' % (reg, val))
        if reg == 0:
            if (val & 0x1000) and (val & 0x0200) and not (val & 0x0800):
                self.start_phy('bmcr')
            else:
                self.bmcr = val

    def reg_read(self, reg, ln):
        if reg == REG_MAC_L:
            return self.mac[0:4]
        if reg == REG_MAC_H:
            return self.mac[4:6] + b'\0\0'
        if reg == REG_MAC_CFG:
            return struct.pack('<I', self.maccfg)
        return bytes(ln)

    def control(self, rt, req, val, idx, data, ln):
        if rt == 0xC0 and req == 0x10:
            return bytes([0x01, 0x00, FW_VERSION, 0, 0, 0, 0, 0])[:ln]
        if rt == 0xC0 and req == 0x11:
            return self.reg_read(val | (idx << 16), ln)[:ln]
        if rt == 0x40 and req == 0x12:
            reg = val | (idx << 16)
            if reg == REG_MAC_CFG and len(data) >= 4:
                self.maccfg = struct.unpack_from('<I', data)[0]
            return b''
        if rt == 0x40 and req == 0x1E:
            self.maccfg = val | (idx << 16)
            self.log('maccfg=%08x' % self.maccfg)
            return b''
        if rt == 0xC0 and req == 0x15:
            return struct.pack('<H', self.phy_read(idx))[:ln]
        if rt == 0x40 and req == 0x16:
            self.phy_write(idx, struct.unpack_from('<H', data)[0] if len(data) >= 2 else 0)
            return b''
        if rt == 0x40 and req == 0x1F:
            if val == KICK_WORD:
                self.start_phy('0x1F')
            return b''
        return None

    @staticmethod
    def unwrap_out(data):
        frames = []
        pos = 0
        while pos + 8 <= len(data):
            hl = struct.unpack_from('<H', data, pos)[0]
            if hl == 0 or pos + 8 + hl > len(data):
                break
            frames.append(data[pos + 8:pos + 8 + hl])
            pos += 8 + hl
        return frames

    @staticmethod
    def wrap_in(frame):
        n = max(len(frame), 60)
        padded = frame.ljust((n + 3) & ~3, b'\0')
        return struct.pack('<I', n) + bytes(4) + padded
