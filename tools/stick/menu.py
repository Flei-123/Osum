#!/usr/bin/env python3
import socket
import sys
import time

path = sys.argv[1]
n = int(sys.argv[2])
wait = float(sys.argv[3]) if len(sys.argv) > 3 else 8.0
spacing = float(sys.argv[4]) if len(sys.argv) > 4 else 0.8

s = None
for _ in range(600):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(path)
        break
    except OSError:
        s = None
        time.sleep(0.05)
if s is None:
    print("keine Monitor-Steckdose: %s" % path)
    raise SystemExit(1)
s.settimeout(0.3)

time.sleep(wait)
try:
    s.recv(65536)
except OSError:
    pass
for i in range(n):
    s.sendall(b"sendkey down\n")
    time.sleep(spacing)
time.sleep(0.6)
s.sendall(b"sendkey ret\n")
time.sleep(0.4)
s.close()
print("menu: %d x down, then enter (after %.1fs, interval %.1fs)"
      % (n, wait, spacing))
