#!/usr/bin/env python3
import os
import subprocess
import sys

LIB_DIRS = ["/usr/lib/x86_64-linux-gnu", "/lib/x86_64-linux-gnu", "/usr/lib", "/lib"]
GUEST_LIB_DIR = "/usr/lib/x86_64-linux-gnu"
LOADER = "ld-linux-x86-64.so.2"
GUEST_DIRS = ["/lib64/", "/usr/lib/x86_64-linux-gnu/", "/opt/", "/usr/share/", "/usr/share/vulkan/", "/usr/share/vulkan/icd.d/"]


def find_host(name):
    for directory in LIB_DIRS:
        path = os.path.join(directory, name)
        if os.path.exists(path):
            return os.path.realpath(path)
    return None


def needed(path):
    out = subprocess.run(["readelf", "-d", path], capture_output=True, text=True).stdout
    return [line.split("[")[1].split("]")[0] for line in out.splitlines() if "NEEDED" in line]


def closure(seeds):
    seen = {}
    queue = list(seeds)
    while queue:
        item = queue.pop()
        name = os.path.basename(item)
        if name in seen:
            continue
        real = item if os.path.isabs(item) else find_host(item)
        if not real:
            print("glibcspec: missing " + item, file=sys.stderr)
            continue
        seen[name] = real
        queue.extend(needed(real))
    return seen


def guest_dirs_for(paths):
    dirs = set()
    for path in paths:
        parent = os.path.dirname(path)
        while parent not in ("/", ""):
            dirs.add(parent + "/")
            parent = os.path.dirname(parent)
    return sorted(dirs, key=lambda d: d.count("/"))


def entries(binaries, extra_libs, pinned):
    libs = closure(list(binaries) + list(extra_libs) + list(pinned) + [LOADER])
    skip = {os.path.abspath(b) for b in binaries}
    pinned_real = {os.path.realpath(p): p for p in pinned}
    dirs = set(GUEST_DIRS) | set(guest_dirs_for(pinned))
    out = ["%s@755" % d for d in sorted(dirs, key=lambda d: d.count("/"))]
    for name, real in sorted(libs.items()):
        if name == LOADER:
            out.append("/lib64/%s=%s@755" % (name, real))
        elif real in pinned_real:
            out.append("%s=%s@755" % (pinned_real[real], real))
        elif os.path.abspath(real) not in skip:
            out.append("%s/%s=%s@755" % (GUEST_LIB_DIR, name, real))
    return out


if __name__ == "__main__":
    args = sys.argv[1:]
    bins = [a[4:] for a in args if a.startswith("bin:")]
    pinned = [a[4:] for a in args if a.startswith("pin:")]
    libs = [a for a in args if not a.startswith(("bin:", "pin:"))]
    print(" ".join(entries(bins, libs, pinned)))
