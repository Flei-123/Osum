import struct

OP_SET_EVENT_MASK = 0x0C01
OP_RESET = 0x0C03
OP_VERSION = 0x1001
OP_ADDR = 0x1009
OP_INQUIRY_MODE = 0x0C45
OP_INQUIRY = 0x0401
OP_INQUIRY_CANCEL = 0x0402
OP_LE_SCAN_PARAMS = 0x200B
OP_LE_SCAN_ENABLE = 0x200C

EV_INQUIRY_COMPLETE = 0x01
EV_INQUIRY_RESULT = 0x02
EV_COMMAND_COMPLETE = 0x0E
EV_COMMAND_STATUS = 0x0F
EV_INQUIRY_RSSI = 0x22
EV_EXTENDED = 0x2F
EV_LE_META = 0x3E
LE_MASK_BIT = 61

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
        self.event_mask = 0
        self.le_scanning = False
        self.le_params = []
        self.le_enables = []

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

    def le_event(self, reports):
        n = len(reports)
        body = bytes([2, n])
        body += bytes(r[0] for r in reports)
        body += bytes(r[1] for r in reports)
        body += b''.join(addr_bytes(r[2]) for r in reports)
        body += bytes(len(r[3]) for r in reports)
        body += b''.join(r[3] for r in reports)
        body += bytes(r[4] & 255 for r in reports)
        if self.event_mask >> LE_MASK_BIT & 1:
            self.events.append(event(EV_LE_META, body))
        else:
            self.violations += 1
            self.log('bt: LE meta event withheld, event mask lacks bit %d' % LE_MASK_BIT)

    def le_rows(self):
        kbd = bytes([2, 1, 6, 3, 3, 0x12, 0x18]) + bytes([13, 0x09]) + b'BLE Keyboard'
        self.le_event([(0, 1, 'C0:11:22:33:44:55', kbd, -50)])
        flags = bytes([2, 1, 6])
        thermo = bytes([7, 0x09]) + b'Thermo'
        self.le_event([(0, 0, 'F1:00:00:00:00:01', flags, -70), (0, 0, 'F2:00:00:00:00:02', thermo, -80)])
        self.le_event([(4, 0, 'F1:00:00:00:00:01', bytes([7, 0x09]) + b'Tag F1', -68)])
        self.le_event([(0, 1, 'C0:11:22:33:44:55', kbd, -42)])

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
        elif op == OP_SET_EVENT_MASK:
            if len(params) != 8:
                self.violations += 1
            else:
                self.event_mask = struct.unpack('<Q', params)[0]
            self.complete(op, bytes([0]))
        elif op == OP_LE_SCAN_PARAMS:
            self.le_params.append(params)
            if len(params) != 7:
                self.violations += 1
            self.complete(op, bytes([0]))
        elif op == OP_LE_SCAN_ENABLE:
            if len(params) != 2:
                self.violations += 1
                self.complete(op, bytes([0x12]))
            elif self.mode == 'lefail':
                self.complete(op, bytes([0x0C]))
            else:
                self.le_enables.append(params[0])
                self.le_scanning = params[0] == 1
                self.complete(op, bytes([0]))
                if self.le_scanning:
                    self.le_rows()
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
