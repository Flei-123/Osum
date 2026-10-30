import hashlib
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bridge import Bridge


CHUNK = int(os.environ.get("LIVEDESIGN_CHUNK", "65536"))


def stamp(label, t0):
    print("livedesign: %-8s %5.1f s" % (label, time.time() - t0), flush=True)


def main():
    if len(sys.argv) < 4:
        raise SystemExit("usage: push.py <program> <elf> <out.png> [--no-run] [--no-photo]")
    prog, elf, out = sys.argv[1:4]
    flags = sys.argv[4:]
    bridge = Bridge()
    remote = "/tmp/ld-" + prog
    with open(elf, "rb") as f:
        data = f.read()
    t0 = time.time()
    source = remote
    if len(data) > CHUNK:
        source = remote + ".p0"
        for index in range(0, (len(data) + CHUNK - 1) // CHUNK):
            part = data[index * CHUNK:(index + 1) * CHUNK]
            status, answer = bridge.write_file("%s.p%02d" % (remote, index), part)
            if status not in ("ok", ""):
                raise SystemExit("livedesign: part %d write status %s: %s" % (index, status, answer.strip()[:120]))
    else:
        status, answer = bridge.write_file(remote, data)
        if status not in ("ok", ""):
            raise SystemExit("livedesign: write status %s: %s" % (status, answer.strip()[:120]))
    stamp("upload", t0)
    run = "" if "--no-run" in flags else " --run"
    status, answer = bridge.command("/bin/jarvisctl swap %s /bin/%s%s" % (source, prog, run))
    stamp("swap", t0)
    print(answer.strip())
    want = hashlib.sha256(data).hexdigest()
    if want not in answer:
        raise SystemExit("livedesign: swap did not report sha256 %s" % want)
    if "--no-photo" in flags:
        return
    time.sleep(float(os.environ.get("LIVEDESIGN_SETTLE", "1.5")))
    size = bridge.photo(out)
    stamp("photo", t0)
    print("livedesign: %s (%d bytes)" % (out, size))


main()
