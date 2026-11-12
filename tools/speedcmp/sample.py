import os
import re
import socket
import sys
import time

CONNECT_TIMEOUT = 180
CHAIN_DEPTH = 10
SCAN_WORDS = 48
KERNEL_MIN = 0x1000
KERNEL_MAX = 0x100000000


def read_reply(sock):
    data = b""
    while not data.endswith(b"(qemu) "):
        part = sock.recv(65536)
        if not part:
            raise EOFError
        data += part
    return data.decode(errors="ignore")


def command(sock, text):
    sock.sendall((text + "\n").encode())
    return read_reply(sock)


def connect(path):
    start = time.time()
    while not os.path.exists(path):
        time.sleep(0.2)
        if time.time() - start > CONNECT_TIMEOUT:
            sys.exit(1)
    sock = socket.socket(socket.AF_UNIX)
    while True:
        try:
            sock.connect(path)
            break
        except OSError:
            time.sleep(0.2)
    sock.settimeout(3)
    return sock


def walk_chain(sock, rbp):
    chain = []
    frame = rbp
    for _ in range(CHAIN_DEPTH):
        if frame < KERNEL_MIN or frame > KERNEL_MAX:
            break
        reply = command(sock, "x /2gx 0x%x" % frame)
        match = re.search(r":\s+0x([0-9a-f]+)\s+0x([0-9a-f]+)", reply)
        if not match:
            break
        next_frame = int(match[1], 16)
        chain.append(int(match[2], 16))
        if next_frame <= frame:
            break
        frame = next_frame
    return chain


def scan_stack(sock, rsp):
    words = []
    reply = command(sock, "x /%dgx 0x%x" % (SCAN_WORDS, rsp))
    for match in re.finditer(r"0x([0-9a-f]{16})", reply):
        value = int(match[1], 16)
        if KERNEL_MIN < value < KERNEL_MAX:
            words.append(value)
    return words


def sample_cpu(sock, cpu, now, out):
    command(sock, "cpu %d" % cpu)
    reply = command(sock, "info registers")
    rip = re.search(r"RIP=([0-9a-f]+)", reply)
    cs = re.search(r"CS =([0-9a-f]+)", reply)
    rbp = re.search(r"RBP=([0-9a-f]+)", reply)
    if not (rip and cs and rbp):
        return
    chain = []
    if int(cs[1], 16) & 3 == 0:
        chain = walk_chain(sock, int(rbp[1], 16))
    rsp = re.search(r"RSP=([0-9a-f]+)", reply)
    scan = scan_stack(sock, int(rsp[1], 16)) if rsp and int(cs[1], 16) & 3 == 0 else []
    out.write("%.2f %d %s %s %s %s\n" % (now, cpu, cs[1], rip[1], ",".join("%x" % x for x in chain) or "-", ",".join("%x" % x for x in scan)))


def main():
    path, out_path, limit, cpus = sys.argv[1], sys.argv[2], float(sys.argv[3]), int(sys.argv[4])
    sock = connect(path)
    start = time.time()
    try:
        command(sock, "")
    except OSError:
        pass
    with open(out_path, "w") as out:
        while time.time() - start < limit:
            try:
                for cpu in range(cpus):
                    sample_cpu(sock, cpu, time.time() - start, out)
            except (EOFError, OSError):
                break
            out.flush()


main()
