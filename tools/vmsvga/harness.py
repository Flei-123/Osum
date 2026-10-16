# SPDX-License-Identifier: GPL-2.0-only
# tools/vmsvga/harness.py -- QEMU monitor + minimal VNC client for tools/vmsvga/run.sh.
#
# usage: harness.py <monitor sock> <vnc sock> <base> <serial file> <mode full|short|frames> <vga>
#   full   : wait for the five `vmsvga: panel=` lines; after each one: screendump <base>.p<i>.ppm, size file, VNC compare
#   short  : wait 25 s only (control: nothing should appear)
#   frames : wait for the `vmsvga: frames hw=` line only
# VNC client: applies ONLY what the server sends (Raw rects, DesktopSize), keeps the last RichCursor shape.
import os
import socket
import struct
import sys
import threading
import time

mon_sock, vnc_sock, base, serial, mode, vga = sys.argv[1:7]


def read_serial():
    try:
        return open(serial, errors="replace").read()
    except OSError:
        return ""


def wait_for(pred, timeout):
    end = time.time() + timeout
    while time.time() < end:
        if pred(read_serial()):
            return True
        time.sleep(0.2)
    return False


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
                    sys.exit(0)
                time.sleep(0.2)
        self.s.settimeout(3.0)
        time.sleep(0.3)
        try:
            self.s.recv(65536)
        except OSError:
            pass

    def dump(self, name):
        f = "%s.%s.ppm" % (base, name)
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
        try:
            self.s.recv(65536)
        except OSError:
            pass
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


def main():
    mon = Mon(mon_sock)
    if mode == "short":
        wait_for(lambda t: "vmsvga: panel=" in t, 25)
        mon.quit()
        return
    if mode == "frames":
        wait_for(lambda t: "vmsvga: frames hw=" in t, 60)
        mon.quit()
        return
    vnc = None
    if vga == "vmware":
        try:
            vnc = Vnc(vnc_sock)
        except Exception:
            vnc = None
    for i in range(5):
        if not wait_for(lambda t, i=i: t.count("vmsvga: panel=") >= i + 1, 90):
            break
        time.sleep(1.5)
        f = mon.dump("p%d" % i)
        try:
            w, h, body = ppm_rgb(f)
        except Exception:
            continue
        open("%s.p%d.size" % (base, i), "w").write("%dx%d" % (w, h))
        if vnc is not None:
            time.sleep(0.5)
            with vnc.lock:
                same = (vnc.w == w and vnc.h == h)
                buf = bytes(vnc.buf)
            if not same:
                diff = -1
            else:
                r = buf[2::4]
                g = buf[1::4]
                b = buf[0::4]
                diff = sum(1 for a, c in zip(r, body[0::3]) if a != c)
                diff += sum(1 for a, c in zip(g, body[1::3]) if a != c)
                diff += sum(1 for a, c in zip(b, body[2::3]) if a != c)
            open("%s.p%d.vncdiff" % (base, i), "w").write(str(diff))
    if vnc is not None and vnc.cursor is not None:
        open("%s.cursor" % base, "w").write("%d %d %d %d" % vnc.cursor)
    if vnc is not None:
        vnc.stop = True
    mon.quit()


main()
