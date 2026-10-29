#!/usr/bin/env python3
import socket
import sys
import time


def send(path, command, settle):
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(5)
    sock.connect(path)
    time.sleep(0.2)
    try:
        sock.recv(4096)
    except socket.timeout:
        pass
    sock.sendall(command.encode() + b"\n")
    time.sleep(settle)
    try:
        sock.recv(4096)
    except socket.timeout:
        pass
    sock.close()


if __name__ == "__main__":
    send(sys.argv[1], sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else 0.5)
