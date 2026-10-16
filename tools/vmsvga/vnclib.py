# SPDX-License-Identifier: GPL-2.0-only
# tools/vmsvga/vnclib.py -- minimal VNC client (applies ONLY the rectangles the server sends) + QEMU monitor helper for desktop.py.
import os
import socket
import struct
import sys
import threading
import time


class Vnc:
    def __init__(self, path):
        self.lock = threading.Lock()
        self.w = self.h = 0
        self.buf = bytearray()
        self.cursor = None  # (w, h, opaque, transparent)
        self.updates = 0
        self.stop = False
        self.s = socket.socket(socket.AF_UNIX)
        deadline = time.time() + 20
        while True:
            try:
                self.s.connect(path)
                break
            except OSError:
                if time.time() > deadline:
                    raise
                time.sleep(0.2)
        self.s.settimeout(10)
        self.rx(12)
        self.s.sendall(b"RFB 003.008\n")
        n = self.rx(1)[0]
        self.rx(n)
        self.s.sendall(b"\x01")
        self.rx(4)
        self.s.sendall(b"\x01")
        w, h = struct.unpack(">HH", self.rx(4))
        self.rx(16)
        (nl,) = struct.unpack(">I", self.rx(4))
        self.rx(nl)
        self.resize(w, h)
        # 32 bpp little endian true colour: bytes B G R X
        self.s.sendall(struct.pack(">BxxxBBBBHHHBBBxxx", 0, 32, 24, 0, 1, 255, 255, 255, 16, 8, 0))
        encs = [0, -239, -223]
        self.s.sendall(struct.pack(">BxH", 2, len(encs)) + b"".join(struct.pack(">i", e) for e in encs))
        self.request(0)
        self.t = threading.Thread(target=self.loop, daemon=True)
        self.t.start()

    def rx(self, n):
        out = b""
        while len(out) < n:
            c = self.s.recv(n - len(out))
            if not c:
                raise EOFError
            out += c
        return out

    def resize(self, w, h):
        with self.lock:
            self.w, self.h = w, h
            self.buf = bytearray(w * h * 4)

    def request(self, inc):
        self.s.sendall(struct.pack(">BBHHHH", 3, inc, 0, 0, self.w, self.h))

    def loop(self):
        try:
            while not self.stop:
                t = self.rx(1)[0]
                if t != 0:
                    if t == 2:
                        continue
                    if t == 3:
                        self.rx(3)
                        (n,) = struct.unpack(">I", self.rx(4))
                        self.rx(n)
                        continue
                    return
                self.rx(1)
                (nr,) = struct.unpack(">H", self.rx(2))
                resized = False
                for _ in range(nr):
                    x, y, w, h, enc = struct.unpack(">HHHHi", self.rx(12))
                    if enc == 0:
                        data = self.rx(w * h * 4)
                        with self.lock:
                            if x + w <= self.w and y + h <= self.h:
                                for r in range(h):
                                    o = ((y + r) * self.w + x) * 4
                                    self.buf[o:o + w * 4] = data[r * w * 4:(r + 1) * w * 4]
                    elif enc == -239:
                        pix = self.rx(w * h * 4)
                        mask = self.rx(((w + 7) // 8) * h)
                        op = sum(bin(b).count("1") for b in mask)
                        tr = (((w + 7) // 8) * 8 * h) - op
                        # padding bits of each row are zero: count transparent only inside the width
                        pad = (((w + 7) // 8) * 8 - w) * h
                        self.cursor = (w, h, op, tr - pad)
                    elif enc == -223:
                        self.resize(w, h)
                        resized = True
                    else:
                        return
                self.updates += 1
                self.request(0 if resized else 1)
        except (EOFError, OSError):
            return



class Mon:
    def __init__(self, path):
        self.s = socket.socket(socket.AF_UNIX)
        deadline = time.time() + 30
        while True:
            try:
                self.s.connect(path)
                break
            except OSError:
                if time.time() > deadline:
                    raise
                time.sleep(0.2)
        self.s.settimeout(3.0)
        time.sleep(0.3)
        self.drain()

    def drain(self):
        try:
            while self.s.recv(65536):
                pass
        except OSError:
            pass

    def cmd(self, c, wait=0.15):
        try:
            self.s.sendall((c + "\n").encode())
        except OSError:
            return
        time.sleep(wait)
        self.drain()

    def dump(self, f):
        try:
            os.unlink(f)
        except OSError:
            pass
        self.s.sendall(("screendump %s\n" % f).encode())
        last = -1
        end = time.time() + 10
        while time.time() < end:
            try:
                g = os.path.getsize(f)
            except OSError:
                g = -1
            if g > 0 and g == last:
                break
            last = g
            time.sleep(0.3)
        self.drain()
        return f

    def quit(self):
        try:
            self.s.sendall(b"quit\n")
        except OSError:
            pass


def ppm_rgb(f):
    d = open(f, "rb").read()
    parts = d.split(b"\n", 3)
    w, h = map(int, parts[1].split())
    return w, h, parts[3]
