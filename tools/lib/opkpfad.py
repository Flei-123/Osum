#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/lib/opkpfad.py -- where the package tool `opk.py` lives.

Prints ONE path. Order:

  1. $OPK, if set (the caller knows best).
  2. /root/orientos-install/pkg/opk.py, if it still exists (the old
     default; that folder was only a git WORKTREE of the OrientOS repo
     and was removed in the cleanup of 21.09.2026 -- since then
     ota, install, module, loader and dynlader failed with
     "can't open file .../opk.py" before measuring anything).
  3. `pkg/opk.py` from the OrientOS repo at ref $ORIENTOS_REF (default
     `main`), read with `git show` and cached under ~/.cache/osum/ by
     its blob hash. `git show` and not the checked-out file: the repo's
     working copy sits on whatever branch someone is working on, and a
     measurement must not depend on that.
  4. Otherwise the old default, so the caller's error message still
     names a concrete path.

Usable from shell (`OPK=${OPK:-$(python3 tools/lib/opkpfad.py)}`) and
from Python (`import opkpfad; opkpfad.pfad()`).
"""
import os
import subprocess
import sys

ALT = "/root/orientos-install/pkg/opk.py"
REPO = os.environ.get("ORIENTOS_REPO",
                      "/root/jarvis/projects/u_DiS4in7esMF1/orientos")
REF = os.environ.get("ORIENTOS_REF", "main")


def pfad():
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
    ablage = os.path.join(os.path.expanduser("~"), ".cache", "osum")
    ziel = os.path.join(ablage, "opk-%s.py" % blob[:12])
    if not os.path.isfile(ziel):
        try:
            inhalt = subprocess.run(["git", "-C", REPO, "cat-file", "blob",
                                     blob], capture_output=True,
                                    check=True).stdout
        except (OSError, subprocess.CalledProcessError):
            return ALT
        os.makedirs(ablage, exist_ok=True)
        tmp = "%s.%d" % (ziel, os.getpid())
        with open(tmp, "wb") as f:
            f.write(inhalt)
        os.chmod(tmp, 0o755)
        os.replace(tmp, ziel)          # atomic: parallel runners are fine
    return ziel


if __name__ == "__main__":
    print(pfad())
    sys.exit(0)
