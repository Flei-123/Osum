# SPDX-License-Identifier: GPL-2.0-only
import socket
import sys
import time

SETTLE_SECONDS = 0.4


def send(sock_path, commands):
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(3.0)
    s.connect(sock_path)
    time.sleep(SETTLE_SECONDS)
    try:
        s.recv(65536)
    except OSError:
        pass
    for command in commands:
        s.sendall((command + "\n").encode())
        time.sleep(SETTLE_SECONDS)
    s.close()


def main():
    sock_path = sys.argv[1]
    steps = int(sys.argv[2])
    send(sock_path, ["mouse_move %d %d" % (30 if i % 2 == 0 else -30, 20 if i % 2 == 0 else -20) for i in range(steps)])
    return 0


if __name__ == "__main__":
    sys.exit(main())
