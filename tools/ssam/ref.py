import binascii
import struct

SYN = b"\xaa\x55"
FRAME_DATA_SEQ = 0x80
FRAME_DATA_NSQ = 0x00
FRAME_ACK = 0x40
FRAME_NAK = 0x04
PLD_CMD = 0x80
TC_SAM = 0x01
TC_HID = 0x15
TC_REG = 0x21
TID_HOST = 0
TID_SAM = 1
TID_KIP = 2


def crc16(data):
    return binascii.crc_hqx(bytes(data), 0xFFFF)


def frame(kind, seq, payload=b""):
    head = struct.pack("<BHB", kind, len(payload), seq)
    return SYN + head + struct.pack("<H", crc16(head)) + payload + struct.pack("<H", crc16(payload))


def ack(seq):
    return frame(FRAME_ACK, seq)


def nak():
    return frame(FRAME_NAK, 0)


def command(tc, tid, sid, iid, rqid, cid, data=b""):
    return struct.pack("<BBBBBHB", PLD_CMD, tc, tid, sid, iid, rqid, cid) + bytes(data)


def request_frame(seq, rqid, tc, tid, iid, cid, data=b""):
    return frame(FRAME_DATA_SEQ, seq, command(tc, tid, TID_HOST, iid, rqid, cid, data))


def response_frame(seq, rqid, tc, tid, iid, cid, data=b""):
    return frame(FRAME_DATA_SEQ, seq, command(tc, TID_HOST, tid, iid, rqid, cid, data))


def event_frame(seq, tc, sid, iid, cid, data, sequenced=True):
    kind = FRAME_DATA_SEQ if sequenced else FRAME_DATA_NSQ
    return frame(kind, seq, command(tc, TID_HOST, sid, iid, tc, cid, data))


def descriptor_request(entry, offset, length):
    return struct.pack("<BIIB", entry, offset, length, 0)


def descriptor_slice(entry, offset, data, end):
    return struct.pack("<BIIB", entry, offset, len(data), 1 if end else 0) + bytes(data)


def event_params(tc, iid, flags=0):
    return struct.pack("<BBHB", tc, flags, tc, iid)


def hid_descriptor(report_len):
    return struct.pack("<BBHBBBH", 9, 0x21, 0x0100, 0, 1, 0x22, report_len)


def attributes(vendor, product, version):
    return struct.pack("<IHHH", 32, vendor, product, version) + bytes(22)


KEYBOARD_REPORT_DESC = bytes([
    0x05, 0x01, 0x09, 0x06, 0xA1, 0x01, 0x05, 0x07, 0x19, 0xE0, 0x29, 0xE7, 0x15, 0x00, 0x25, 0x01,
    0x75, 0x01, 0x95, 0x08, 0x81, 0x02, 0x95, 0x01, 0x75, 0x08, 0x81, 0x01, 0x95, 0x05, 0x75, 0x01,
    0x05, 0x08, 0x19, 0x01, 0x29, 0x05, 0x91, 0x02, 0x95, 0x01, 0x75, 0x03, 0x91, 0x01, 0x95, 0x06,
    0x75, 0x08, 0x15, 0x00, 0x25, 0x65, 0x05, 0x07, 0x19, 0x00, 0x29, 0x65, 0x81, 0x00, 0xC0,
])

TOUCHPAD_REPORT_DESC = bytes([
    0x05, 0x01, 0x09, 0x02, 0xA1, 0x01, 0x09, 0x01, 0xA1, 0x00, 0x05, 0x09, 0x19, 0x01, 0x29, 0x03,
    0x15, 0x00, 0x25, 0x01, 0x95, 0x03, 0x75, 0x01, 0x81, 0x02, 0x95, 0x01, 0x75, 0x05, 0x81, 0x01,
    0x05, 0x01, 0x09, 0x30, 0x09, 0x31, 0x15, 0x81, 0x25, 0x7F, 0x75, 0x08, 0x95, 0x02, 0x81, 0x06,
    0xC0, 0xC0,
])


def hexs(b):
    return " ".join("%02X" % x for x in b)


if __name__ == "__main__":
    print("ack5", hexs(ack(5)))
    print("nak", hexs(nak()))
    print("req", hexs(request_frame(0, 39, TC_HID, TID_KIP, 1, 4, descriptor_request(1, 0, 0x76))))
    print("evt", hexs(event_frame(7, TC_HID, TID_KIP, 1, 0, bytes([0, 0, 4, 0, 0, 0, 0, 0]))))
    print("rsp", hexs(response_frame(9, 39, TC_HID, TID_KIP, 1, 4, descriptor_slice(1, 0, b"\x01\x02\x03", True))))
    print("evparams", hexs(event_params(TC_HID, 1)))
    print("hiddesc", hexs(hid_descriptor(0x3B)))
    print("evreq", hexs(request_frame(0, 39, TC_REG, TID_KIP, 0, 1, event_params(TC_HID, 1))))
