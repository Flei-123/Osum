# SPDX-License-Identifier: GPL-2.0-only
import collections
import os
import socket
import sys
import time

BORDER = 8
COLORS = {
    "border": (255, 255, 0),
    "tl": (255, 0, 0),
    "tr": (0, 255, 0),
    "bl": (0, 0, 255),
    "br": (255, 255, 255),
}


def dump(sock_path, out_path, quit_after):
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(3.0)
    s.connect(sock_path)
    time.sleep(0.4)
    try:
        s.recv(65536)
    except OSError:
        pass
    s.sendall(("screendump %s\n" % out_path).encode())
    last = -1
    end = time.time() + 8
    while time.time() < end:
        try:
            size = os.path.getsize(out_path)
        except OSError:
            size = -1
        if size > 0 and size == last:
            break
        last = size
        time.sleep(0.25)
    if quit_after:
        try:
            s.sendall(b"quit\n")
        except OSError:
            pass
    s.close()
    return 0 if last > 0 else 1


def load_ppm(path):
    data = open(path, "rb").read()
    parts = data.split(b"\n", 3)
    width, height = map(int, parts[1].split())
    return width, height, parts[3]


def expected_counts(width, height):
    inner_w = width - 2 * BORDER
    inner_h = height - 2 * BORDER
    half_w = width // 2
    half_h = height // 2
    left = half_w - BORDER
    right = width - BORDER - half_w
    top = half_h - BORDER
    bottom = height - BORDER - half_h
    counts = {
        "tl": left * top,
        "tr": right * top,
        "bl": left * bottom,
        "br": right * bottom,
    }
    counts["border"] = width * height - inner_w * inner_h
    return counts


def verify(path, want_w, want_h):
    width, height, body = load_ppm(path)
    seen = collections.Counter(zip(body[0::3], body[1::3], body[2::3]))
    if (width, height) != (want_w, want_h):
        print("screen: %dx%d exact=0 other=%d" % (width, height, sum(seen.values())))
        return 1
    want = expected_counts(width, height)
    known = 0
    exact = True
    for name, rgb in COLORS.items():
        got = seen.get(rgb, 0)
        known += got
        if got != want[name]:
            exact = False
    other = sum(seen.values()) - known
    print("screen: %dx%d exact=%d other=%d" % (width, height, 1 if exact and other == 0 else 0, other))
    return 0 if exact and other == 0 else 1


def main():
    cmd = sys.argv[1]
    if cmd == "dump":
        return dump(sys.argv[2], sys.argv[3], len(sys.argv) > 4 and sys.argv[4] == "quit")
    if cmd == "verify":
        return verify(sys.argv[2], int(sys.argv[3]), int(sys.argv[4]))
    return 2


sys.exit(main())
