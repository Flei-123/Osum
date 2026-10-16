#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/vgpuhw/vncresize.py -- ask QEMU to resize its display like a host window drag would.
#
#   vncresize.py <vnc-unix-socket> <width> <height>
#
# Speaks just enough RFB 3.8 (security "None") to send a SetDesktopSize request. QEMU turns that into
# dpy_set_ui_info() on the console behind the VNC display; virtio-gpu answers with a config-change event
# (VIRTIO_GPU_EVENT_DISPLAY) and a new GET_DISPLAY_INFO size -- the same path a GTK/SDL window resize takes.
# Exit 0 = request sent, 1 = could not connect / handshake failed.
import socket
import struct
import sys
import time


def rd(s, n):
    b = b""
    while len(b) < n:
        c = s.recv(n - len(b))
        if not c:
            raise OSError("closed")
        b += c
    return b


def main():
    path, w, h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(5)
    for _ in range(40):
        try:
            s.connect(path)
            break
        except OSError:
            time.sleep(0.25)
    else:
        print("vncresize: cannot connect")
        return 1
    rd(s, 12)
    s.sendall(b"RFB 003.008\n")
    n = rd(s, 1)[0]
    if n == 0:
        print("vncresize: server refused")
        return 1
    types = rd(s, n)
    if 1 not in types:
        print("vncresize: no 'None' security type")
        return 1
    s.sendall(bytes([1]))
    if struct.unpack(">I", rd(s, 4))[0] != 0:
        print("vncresize: security failed")
        return 1
    s.sendall(bytes([1]))  # ClientInit: shared
    sw, sh = struct.unpack(">HH", rd(s, 4))
    rd(s, 16)
    nl = struct.unpack(">I", rd(s, 4))[0]
    rd(s, nl)
    # SetEncodings: ExtendedDesktopSize (-308), DesktopSize (-223), Raw (0)
    encs = [-308, -223, 0]
    s.sendall(struct.pack(">BxH", 2, len(encs)) + b"".join(struct.pack(">i", e) for e in encs))
    s.sendall(struct.pack(">BBHHHH", 3, 0, 0, 0, 64, 64))
    time.sleep(0.5)
    # SetDesktopSize: type 251, pad, w, h, nscreens, pad, screen{id, x, y, w, h, flags}
    msg = struct.pack(">BxHHBx", 251, w, h, 1) + struct.pack(">IHHHHI", 1, 0, 0, w, h, 0)
    s.sendall(msg)
    print("vncresize: server %dx%d -> requested %dx%d" % (sw, sh, w, h))
    s.settimeout(1.0)
    end = time.time() + 3
    try:
        while time.time() < end:
            if not s.recv(65536):
                break
    except OSError:
        pass
    return 0


sys.exit(main())
