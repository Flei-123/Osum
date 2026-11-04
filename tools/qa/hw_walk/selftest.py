import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from bridge import Reply
from context import Context
from registry import load_all

CANNED = {
    "/bin/cat /proc/battery": "ende 0\npresent=1 valid=1 percent=95 state=0 full=4229 rem=4055 bif=1 bst=1\n",
    "/bin/cat /proc/thermal": "ende 0\nzone \\_TZ.CPUZ temp_c=46.0 present=1\n",
    "/bin/cat /etc/jarvis/permissions.conf": "ende 0\ncommand_allowed = /bin/ls\ninput = no\n",
}


class FakeBridge:
    device = "fake"

    def __init__(self, leak):
        self.leak = leak

    def request(self, method, path, body=None, key="", timeout=40):
        return (403 if key is None or key == "x" * 32 else 200), {}, b""

    def run(self, command, timeout=90):
        if command in CANNED:
            return Reply(200, "ok", CANNED[command])
        if command.startswith("/bin/cat /etc/") and self.leak:
            return Reply(200, "ok", "ende 0\nsecret-content\n")
        return Reply(200, "failed", "program not allowed by `command_allowed`")

    def read(self, path, timeout=90):
        return Reply(200, "failed", "path not allowed by `read`")

    def job(self, kind, target="", value="", timeout=90):
        return Reply(200, "failed", "not allowed")


def run_group(name, leak=False):
    ctx = Context(FakeBridge(leak), active=True)
    group = [g for g in load_all() if g["name"] == name][0]
    return group["fn"](ctx)


def main():
    passed = failed = 0

    def expect(label, cond):
        nonlocal passed, failed
        print(("OK    " if cond else "FAIL  ") + label)
        passed, failed = passed + cond, failed + (not cond)

    clean = run_group("access")
    expect("clean device: no FAIL in access", not any(r.status == "FAIL" for r in clean))
    expect("counter-proof: leaking cat is caught", sum(r.status == "FAIL" for r in run_group("access", leak=True)) == 3)
    bat = run_group("battery")
    expect("battery percent consistent", any(r.name == "percent consistent" and r.status == "OK" for r in bat))
    print("selftest: %d OK / %d FAIL" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
