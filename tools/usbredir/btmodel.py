import struct

OP_RESET = 0x0C03
OP_VERSION = 0x1001
OP_ADDR = 0x1009
OP_INQUIRY_MODE = 0x0C45
OP_INQUIRY = 0x0401
OP_INQUIRY_CANCEL = 0x0402

EV_INQUIRY_COMPLETE = 0x01
EV_INQUIRY_RESULT = 0x02
EV_COMMAND_COMPLETE = 0x0E
EV_COMMAND_STATUS = 0x0F
EV_INQUIRY_RSSI = 0x22
EV_EXTENDED = 0x2F

HCI_VERSION = 9
MANUFACTURER = 0x0002
EIR_LEN = 240


def addr_bytes(text):
    return bytes(int(x, 16) for x in text.split(':'))[::-1]


def cod_bytes(cod):
    return struct.pack('<I', cod)[:3]


def event(code, params):
    return bytes([code, len(params)]) + params


class BtModel:
    def __init__(self, log, mode='normal', addr='00:1A:7D:DA:71:13'):
        self.log = log
        self.mode = mode
        self.addr = addr_bytes(addr)
        self.events = []
        self.cmds = []
        self.violations = 0
        self.inquiry_modes = []
        self.scanning = False

    def complete(self, op, ret):
        self.events.append(event(EV_COMMAND_COMPLETE, bytes([1]) + struct.pack('<H', op) + ret))

    def status(self, op, status):
        self.events.append(event(EV_COMMAND_STATUS, bytes([status, 1]) + struct.pack('<H', op)))

    def rows(self):
        a1 = addr_bytes('AA:BB:CC:00:00:01')
        a2 = addr_bytes('11:22:33:44:55:66')
        a3 = addr_bytes('DE:AD:BE:EF:00:07')
        e1 = a1 + bytes([1, 0]) + cod_bytes(0x240404) + struct.pack('<H', 0x1234) + bytes([(-45) & 255])
        self.events.append(event(EV_INQUIRY_RSSI, bytes([1]) + e1))
        e2 = a2 + bytes([1, 0, 0]) + cod_bytes(0x5A020C) + struct.pack('<H', 0x2345)
        self.events.append(event(EV_INQUIRY_RESULT, bytes([1]) + e2))
        name = b'Test Laptop'
        eir = (bytes([len(name) + 1, 0x09]) + name).ljust(EIR_LEN, b'\0')
        e3 = a3 + bytes([1, 0]) + cod_bytes(0x000104) + struct.pack('<H', 0x3456) + bytes([(-60) & 255])
        self.events.append(event(EV_EXTENDED, bytes([1]) + e3 + eir))
        e1b = a1 + bytes([1, 0]) + cod_bytes(0x240404) + struct.pack('<H', 0x1234) + bytes([(-40) & 255])
        self.events.append(event(EV_INQUIRY_RSSI, bytes([1]) + e1b))
        self.events.append(event(EV_INQUIRY_COMPLETE, bytes([0])))

    def control(self, rt, req, val, idx, data, ln):
        if rt != 0x20 or req != 0:
            return None
        if len(data) < 3 or len(data) != 3 + data[2]:
            self.violations += 1
            self.log('bt: malformed command length %d' % len(data))
            return None
        op = struct.unpack_from('<H', data)[0]
        params = data[3:]
        self.cmds.append(op)
        self.log('bt: command %04x params=%s' % (op, params.hex()))
        if op == OP_RESET:
            if self.mode == 'badstatus':
                self.complete(op, bytes([0x01]))
            elif self.mode != 'noreply':
                self.complete(op, bytes([0]))
        elif op == OP_VERSION:
            self.complete(op, bytes([0, HCI_VERSION]) + struct.pack('<HBHH', 0x0100, 9, MANUFACTURER, 0x0200))
        elif op == OP_ADDR:
            self.complete(op, bytes([0]) + self.addr)
        elif op == OP_INQUIRY_MODE:
            self.inquiry_modes.append(params[0] if params else 0xFF)
            self.complete(op, bytes([0]))
        elif op == OP_INQUIRY:
            if self.mode == 'noinquiry' or len(params) != 5:
                self.status(op, 0x0C)
            else:
                self.scanning = True
                self.status(op, 0)
                self.rows()
        elif op == OP_INQUIRY_CANCEL:
            self.scanning = False
            self.complete(op, bytes([0]))
        else:
            self.violations += 1
            self.complete(op, bytes([0x01]))
        return b''

    def packets(self, mps):
        if not self.events:
            return []
        ev = self.events.pop(0)
        chunks = [ev[i:i + mps] for i in range(0, len(ev), mps)]
        if len(ev) % mps == 0:
            chunks.append(b'')
        return chunks
