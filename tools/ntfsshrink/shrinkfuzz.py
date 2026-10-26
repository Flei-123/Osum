#!/usr/bin/env python3
import hashlib, os, re, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor


def sh(*a):
    return subprocess.run(a, capture_output=True)


def kv(out, key):
    m = re.search(rb"^" + key + rb"=(\d+)", out, re.M)
    return int(m.group(1)) if m else -1


def main():
    exe, pristine, clean, scheme, base, old_psize, new_psize, writes, hashdir, work = sys.argv[1:11]
    modes = sys.argv[11:]
    base, old_psize, new_psize, writes = int(base), int(old_psize), int(new_psize), int(writes)
    want = open(clean, "rb").read()
    names = sorted(os.listdir(hashdir))
    hashes = {n: hashlib.sha256(open(os.path.join(hashdir, n), "rb").read()).hexdigest() for n in names}
    old_s = old_psize - 1

    def old_volume_ok(path):
        raw = open(path, "rb").read(512 * (base + old_psize))
        part = os.path.join(work, os.path.basename(path) + ".part")
        open(part, "wb").write(raw[base * 512:(base + old_psize) * 512])
        try:
            r = sh("ntfsfix", "-n", part)
            if r.returncode != 0 or b"Checking the alternate boot sector... OK" not in r.stdout:
                return "ntfsfix"
            for n in names:
                if hashlib.sha256(sh("ntfscat", "-f", part, n).stdout).hexdigest() != hashes[n]:
                    return "hash " + n
            return ""
        finally:
            os.unlink(part)

    def case(args):
        k, tear, nest = args
        t = os.path.join(work, "t_%d_%d_%d.img" % (k, tear, nest))
        shutil.copyfile(pristine, t)
        try:
            r = sh(exe, t, "r", str(base), t, str(new_psize), str(k), str(tear))
            code = kv(r.stdout, b"code")
            if k < writes and code == 0:
                return "k=%d tear=%d: crash not noticed" % (k, tear)
            if k >= writes and code != 0:
                return "k=%d tear=%d: code %d without crash" % (k, tear, code)
            boot = open(t, "rb").read((base + 1) * 512)[base * 512:]
            s_now = int.from_bytes(boot[0x28:0x30], "little")
            if s_now == old_s:
                if "reloc" in modes:
                    sh(exe, t, "c", str(base), t)
                why = old_volume_ok(t)
                if why:
                    return "k=%d tear=%d: old volume damaged before commit (%s)" % (k, tear, why)
            if "noheal" in modes:
                return "" if open(t, "rb").read() == want else "k=%d: differs" % k
            if nest:
                sh(exe, t, "c", str(base), t, str(nest - 1), str(tear))
            r = sh(exe, t, "c", str(base), t)
            if kv(r.stdout, b"code") != 0:
                return "k=%d tear=%d nest=%d: recover code %d" % (k, tear, nest, kv(r.stdout, b"code"))
            r = sh(exe, t, "r", str(base), t, str(new_psize))
            code = kv(r.stdout, b"code")
            if code not in (0, 14):
                return "k=%d tear=%d nest=%d: second run code %d" % (k, tear, nest, code)
            if open(t, "rb").read() != want:
                return "k=%d tear=%d nest=%d: image differs from the undisturbed run (recover code %d)" % (k, tear, nest, code)
            return ""
        finally:
            if os.path.exists(t):
                os.unlink(t)

    jobs = []
    tears = [0, 1] if scheme == "gpt" else [0]
    for tear in tears:
        for k in range(0, writes + 1):
            jobs.append((k, tear, 0))
    if "nested" in modes:
        for k in range(1, writes):
            for j in (1, 2, 4):
                jobs.append((k, 0, j))
    if "noheal" in modes:
        jobs = [j for j in jobs if j[0] < writes]
    with ThreadPoolExecutor(max_workers=4) as ex:
        res = list(ex.map(case, jobs))
    fails = [x for x in res if x]
    print("fuzz %s: %d crash points, %d failed" % (scheme, len(jobs), len(fails)))
    for f in fails[:12]:
        print("  " + f)
    sys.exit(1 if fails else 0)


main()
