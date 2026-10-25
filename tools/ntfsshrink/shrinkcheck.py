#!/usr/bin/env python3
import hashlib, os, re, subprocess, sys, tempfile


def sh(*a):
    return subprocess.run(a, capture_output=True)


def le(b, o, n):
    return int.from_bytes(b[o:o + n], "little")


def main():
    disk, scheme, base, old_psize, new_psize, orig_part, hashdir, unit, checkpy = sys.argv[1:10]
    base, old_psize, new_psize = int(base), int(old_psize), int(new_psize)
    bad = []

    def need(name, ok):
        if not ok:
            bad.append(name)

    raw = open(disk, "rb").read()
    if scheme == "gpt":
        r = sh("sgdisk", "-v", disk)
        need("sgdisk -v", b"No problems found" in r.stdout)
        m = re.search(rb"Partition size: (\d+) sectors", sh("sgdisk", "-i", "1", disk).stdout)
        need("gpt size", bool(m) and int(m.group(1)) == new_psize)
    else:
        r = sh("sfdisk", "-V", disk)
        need("sfdisk -V", r.returncode == 0)
        m = re.search(rb'"size":\s*(\d+)', sh("sfdisk", "-J", disk).stdout)
        need("mbr size", bool(m) and int(m.group(1)) == new_psize)
    part = raw[base * 512:(base + new_psize) * 512]
    s_new = new_psize - 1
    need("boot S", le(part, 0x28, 8) == s_new)
    need("backup boot at S", part[s_new * 512:s_new * 512 + 512] == part[:512])
    spc = part[13]
    c_new = s_new // spc
    old_s = old_psize - 1
    need("old backup zeroed", raw[(base + old_s) * 512:(base + old_s + 1) * 512] == b"\0" * 512)
    need("intent zeroed", raw[(base + s_new + 1) * 512:(base + s_new + 2) * 512] == b"\0" * 512)
    tmp = tempfile.mkdtemp(prefix="shrinkchk.", dir=os.environ.get("TMPDIR", "/tmp"))
    try:
        q = os.path.join(tmp, "q.img")
        open(q, "wb").write(part)
        r = sh("ntfsresize", "-i", "-f", q)
        out = (r.stdout + r.stderr).decode(errors="replace")
        m = re.search(r"Current volume size: (\d+) bytes", out)
        need("ntfsresize -i -f rc", r.returncode == 0)
        need("ntfsresize volume size", bool(m) and int(m.group(1)) == c_new * spc * 512 + 512)
        r = sh("ntfsfix", "-n", q)
        need("ntfsfix -n", r.returncode == 0 and b"Checking the alternate boot sector... OK" in r.stdout)
        r = sh("ntfsinfo", "-m", q)
        need("volume flags clean", r.returncode == 0 and b"Volume Flags: 0x0000" in r.stdout)
        names = sorted(os.listdir(hashdir))
        got = sorted(x for x in sh("ntfsls", q).stdout.decode().split("\n") if x and not x.startswith("$"))
        got = [x for x in got if x in names or x == "System Volume Information"]
        need("file list", got == names)
        for n in names:
            want = hashlib.sha256(open(os.path.join(hashdir, n), "rb").read()).hexdigest()
            have = hashlib.sha256(sh("ntfscat", "-f", q, n).stdout).hexdigest()
            need("sha256 " + n, want == have)
        ref = os.path.join(tmp, "ref.img")
        open(ref, "wb").write(open(orig_part, "rb").read())
        r = sh("ntfsresize", "-f", "-s", str(new_psize * 512), ref)
        need("oracle ntfsresize -s", r.returncode == 0)
        cat = lambda img: sh("ntfscat", "-f", img, "$Bitmap").stdout
        mine, rs, orig = cat(q), cat(ref), cat(orig_part)
        d = (((c_new + 7) // 8) + 7) // 8 * 8
        lo = c_new // 8
        need("bitmap length", len(mine) == d)
        need("bitmap below new end", mine[:lo] == orig[:lo])
        need("bitmap padding equals ntfsresize", rs[lo:d] == mine[lo:d])
        need("padding bits set", all(mine[b // 8] >> (b % 8) & 1 for b in range(c_new, 8 * d)))
        uo = os.path.join(tmp, "unit.out")
        with open(uo, "w") as f:
            subprocess.run([unit, q, "info", "x"], stdout=f, stderr=subprocess.STDOUT, cwd=tmp)
        r = sh("python3", "-I", checkpy, q, uo)
        need("check.py: " + r.stdout.decode().replace("\n", ";"), r.returncode == 0)
    finally:
        subprocess.run(["rm", "-rf", tmp])
    print("\n".join(bad) if bad else "ALLOK")
    sys.exit(1 if bad else 0)


main()
