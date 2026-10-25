#!/usr/bin/env python3
import hashlib, os, re, shutil, subprocess, sys, tempfile


def sh(*a):
    return subprocess.run(a, capture_output=True)


def le(b, o, n):
    return int.from_bytes(b[o:o + n], "little")


def part_info(disk, n):
    out = sh("sgdisk", "-i", str(n), disk).stdout.decode()
    m = re.search(r"First sector: (\d+)", out)
    s = re.search(r"Partition size: (\d+) sectors", out)
    t = re.search(r"Partition GUID code: (\S+)", out)
    nm = re.search(r"Partition name: '([^']*)'", out)
    if not (m and s):
        return None
    return int(m.group(1)), int(s.group(1)), t.group(1) if t else "", nm.group(1) if nm else ""


def main():
    disk, new_psize, hashdir = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    installed = "--installed" in sys.argv[4:]
    bad = []

    def need(name, ok):
        if not ok:
            bad.append(name)

    need("sgdisk -v", b"No problems found" in sh("sgdisk", "-v", disk).stdout)
    pi = part_info(disk, 2)
    need("partition 2 exists", pi is not None)
    if pi is None:
        print("\n".join(bad))
        sys.exit(1)
    base, size, typ, _ = pi
    need("partition 2 size %d != %d" % (size, new_psize), size == new_psize)
    need("partition 2 type", typ.upper().startswith("EBD0A0A2"))
    if installed:
        p3 = part_info(disk, 3)
        need("partition 3 exists", p3 is not None)
        if p3:
            need("partition 3 named OSUM", p3[3] == "OSUM")
            need("partition 3 after partition 2", p3[0] >= base + size)
    tmp = tempfile.mkdtemp(prefix="shrinkinst.", dir=os.environ.get("TMPDIR", "/tmp"))
    try:
        q = os.path.join(tmp, "q.img")
        with open(disk, "rb") as f:
            f.seek(base * 512)
            part = f.read(size * 512)
        open(q, "wb").write(part)
        s_new = new_psize - 1
        need("boot sector total", le(part, 0x28, 8) == s_new)
        need("backup boot at S", part[s_new * 512:s_new * 512 + 512] == part[:512])
        spc = part[13]
        c_new = s_new // spc
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
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("\n".join(bad) if bad else "ALLOK")
    sys.exit(1 if bad else 0)


main()
