import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "livedesign"))
from bridge import Bridge

REMOTE_DIR = "/tmp"
PACKAGE = "xremote.opk"


def push(bridge, local_dir, name):
    with open(os.path.join(local_dir, name), "rb") as handle:
        data = handle.read()
    status, answer = bridge.write_file("%s/%s" % (REMOTE_DIR, name), data)
    if status not in ("ok", ""):
        raise SystemExit("hp_install: write %s failed: %s %s" % (name, status, answer.strip()[:120]))
    print("hp_install: wrote %s (%d bytes)" % (name, len(data)))


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: hp_install.py <dir with xremote.opk and xremote.opk.sig>")
    local_dir = sys.argv[1]
    bridge = Bridge()
    push(bridge, local_dir, PACKAGE)
    push(bridge, local_dir, PACKAGE + ".sig")
    status, answer = bridge.command("/bin/opk install %s/%s" % (REMOTE_DIR, PACKAGE))
    print(answer.strip())
    if "opk: installed xremote" not in answer:
        raise SystemExit("hp_install: install did not report success")


main()
