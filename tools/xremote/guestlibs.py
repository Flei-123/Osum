#!/usr/bin/env python3
import os, subprocess, sys

root, spec = sys.argv[1], sys.argv[2]
seeds = sys.argv[3:]
dirs = ["usr/lib", "lib"]
present = set()
for line in open(spec):
    path = line.split("@")[0].split("=")[0].split("->")[0]
    present.add(os.path.basename(path))

def find(name):
    for d in dirs:
        p = os.path.join(root, d, name)
        if os.path.exists(p):
            return os.path.realpath(p), "/" + d + "/" + name
    return None

def needed(path):
    out = subprocess.run(["readelf", "-d", path], capture_output=True, text=True).stdout
    return [l.split("[")[1].split("]")[0] for l in out.splitlines() if "NEEDED" in l]

seen, queue, entries = set(), list(seeds), []
while queue:
    name = queue.pop()
    if name in seen or name.startswith(("libc.musl", "ld-musl")):
        continue
    seen.add(name)
    hit = find(name)
    if not hit:
        continue
    real, guest = hit
    if name not in present:
        entries.append("%s=%s@755" % (guest, real))
    queue.extend(needed(real))
print(" ".join(entries))
