#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import subprocess
import sys

ALT = "/root/orientos-install/pkg/opk.py"
REPO = os.environ.get("ORIENTOS_REPO",
                      "/root/jarvis/projects/u_DiS4in7esMF1/orientos")
REF = os.environ.get("ORIENTOS_REF", "main")


def path_2():
    if os.environ.get("OPK"):
        return os.environ["OPK"]
    if os.path.isfile(ALT):
        return ALT
    try:
        blob = subprocess.run(
            ["git", "-C", REPO, "rev-parse", "%s:pkg/opk.py" % REF],
            capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return ALT
    clipboard = os.path.join(os.path.expanduser("~"), ".cache", "osum")
    target = os.path.join(clipboard, "opk-%s.py" % blob[:12])
    if not os.path.isfile(target):
        try:
            inhalt = subprocess.run(["git", "-C", REPO, "cat-file", "blob",
                                     blob], capture_output=True,
                                    check=True).stdout
        except (OSError, subprocess.CalledProcessError):
            return ALT
        os.makedirs(clipboard, exist_ok=True)
        tmp = "%s.%d" % (target, os.getpid())
        with open(tmp, "wb") as f:
            f.write(inhalt)
        os.chmod(tmp, 0o755)
        os.replace(tmp, target)
    return target


if __name__ == "__main__":
    print(path_2())
    sys.exit(0)
