import os
import socket
import struct
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ssam"))
import ref

FIRMWARE = 0x00030007
KEY_USAGE_A = 4
EVENT_PERIOD_S = 0.15
EVENT_WINDOW_S = 90.0
IID_KEYBOARD = 1
IID_TOUCHPAD = 3


class Parser:
    def __init__(self):
        self.buf = bytearray()

    def feed(self, data):
        self.buf += data
        out = []
        while True:
            i = self.buf.find(ref.SYN)
            if i < 0:
                self.buf = self.buf[-1:]
                break
            del self.buf[:i]
            if len(self.buf) < 10:
                break
            kind, length, seq = struct.unpack_from("<BHB", self.buf, 2)
            if ref.crc16(self.buf[2:6]) != struct.unpack_from("<H", self.buf, 6)[0]:
                del self.buf[:2]
                continue
            total = 8 + length + (2 if kind in (ref.FRAME_DATA_SEQ, ref.FRAME_DATA_NSQ) else 0)
            if kind not in (ref.FRAME_DATA_SEQ, ref.FRAME_DATA_NSQ):
                total = 10
            if len(self.buf) < total:
                break
            payload = bytes(self.buf[8:8 + length])
            out.append((kind, seq, payload))
            del self.buf[:total]
        return out


class Ec:
    def __init__(self, mode):
        self.mode = mode
        self.seq = 0
        self.enabled = set()
        self.last_event = 0.0
        self.started = None
        self.counter = 0

    def next_seq(self):
        self.seq = (self.seq + 1) & 0xFF
        return self.seq

    def reply(self, rqid, tc, tid, iid, cid, data):
        return ref.response_frame(self.next_seq(), rqid, tc, tid, iid, cid, data)

    def descriptor(self, iid, entry, offset, length):
        desc = ref.KEYBOARD_REPORT_DESC if iid == IID_KEYBOARD else ref.TOUCHPAD_REPORT_DESC
        if entry == 0:
            blob = ref.hid_descriptor(len(desc))
        elif entry == 1:
            blob = desc
        else:
            blob = ref.attributes(0x045E, 0x09AF if iid == IID_KEYBOARD else 0x09B0, 1)
        chunk = blob[offset:offset + length]
        return ref.descriptor_slice(entry, offset, chunk, offset + len(chunk) >= len(blob))

    def handle(self, kind, seq, payload):
        out = []
        if kind != ref.FRAME_DATA_SEQ or len(payload) < 8:
            return out
        out.append(ref.ack(seq))
        if self.mode == "mute":
            return []
        _, tc, tid, sid, iid, rqid, cid = struct.unpack_from("<BBBBBHB", payload, 0)
        data = payload[8:]
        if tc == ref.TC_SAM and cid == 0x13:
            out.append(self.reply(rqid, tc, tid, iid, cid, struct.pack("<I", FIRMWARE)))
        elif tc == ref.TC_HID and cid == 4:
            entry, offset, length, _ = struct.unpack_from("<BIIB", data, 0)
            out.append(self.reply(rqid, tc, tid, iid, cid, self.descriptor(iid, entry, offset, length)))
        elif tc == ref.TC_HID and cid == 3:
            out.append(self.reply(rqid, tc, tid, iid, cid, b"\x00"))
        elif tc == ref.TC_REG and cid == 1:
            self.enabled.add(data[4])
            if self.started is None:
                self.started = time.time()
            out.append(self.reply(rqid, tc, tid, iid, cid, b"\x00"))
        return out

    def event(self, iid, report):
        frame = ref.event_frame(self.next_seq(), ref.TC_HID, ref.TID_KIP, iid, 0, report)
        if self.mode == "badevents":
            frame = frame[:-1] + bytes([frame[-1] ^ 0xFF])
        return frame

    def due_events(self, now):
        if self.mode == "mute" or self.started is None or now - self.started > EVENT_WINDOW_S:
            return []
        if now - self.last_event < EVENT_PERIOD_S:
            return []
        self.last_event = now
        self.counter += 1
        out = []
        if IID_KEYBOARD in self.enabled:
            usage = KEY_USAGE_A if self.counter % 2 else 0
            out.append(self.event(IID_KEYBOARD, bytes([0, 0, usage, 0, 0, 0, 0, 0])))
        if IID_TOUCHPAD in self.enabled:
            out.append(self.event(IID_TOUCHPAD, bytes([0, 5, 3])))
        return out


def send(conn, frame, timeout):
    conn.settimeout(timeout)
    try:
        conn.sendall(frame)
    except socket.timeout:
        pass
    conn.settimeout(0.05)


def serve(path, mode):
    if os.path.exists(path):
        os.unlink(path)
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(path)
    srv.listen(1)
    conn, _ = srv.accept()
    conn.settimeout(0.05)
    parser = Parser()
    ec = Ec(mode)
    while True:
        try:
            data = conn.recv(256)
            if not data:
                return
            for kind, seq, payload in parser.feed(data):
                for frame in ec.handle(kind, seq, payload):
                    send(conn, frame, 2.0)
        except socket.timeout:
            pass
        except OSError:
            return
        for frame in ec.due_events(time.time()):
            send(conn, frame, 0.02)


if __name__ == "__main__":
    serve(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "ok")
