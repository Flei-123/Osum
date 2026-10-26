#!/usr/bin/env python3
import os, random, subprocess, sys

OUT, NAME, PSIZE = sys.argv[1], sys.argv[2], int(sys.argv[3])

VARIANTS = {
    "tail4k": dict(cs=4096, filler=30, small=60, holes=0, big=700000),
    "tail512": dict(cs=512, filler=24, small=40, holes=0, big=700000),
    "tail64k": dict(cs=65536, filler=30, small=12, holes=0, big=700000),
    "frag4k": dict(cs=4096, filler=30, small=24, holes=24, big=700000),
    "inst4k": dict(cs=4096, filler=90, filler2=62, small=30, holes=0, big=700000),
    "fuzz4k": dict(cs=4096, filler=16, small=6, holes=8, big=200000),
}


def sh(*a):
    r = subprocess.run(a, capture_output=True)
    if r.returncode != 0:
        print("endmake: %s failed: %s" % (a[0], r.stderr.decode()[:300]))
        sys.exit(1)


def main():
    cfg = VARIANTS[NAME]
    rnd = random.Random(7 + cfg["cs"])
    part = os.path.join(OUT, NAME + ".part")
    files = os.path.join(OUT, NAME + ".files")
    os.makedirs(files, exist_ok=True)
    with open(part, "wb") as f:
        f.seek(PSIZE * 512 - 1)
        f.write(b"\0")
    sh("mkntfs", "-F", "-q", "-s", "512", "-c", str(cfg["cs"]), part)

    def put(name, data, final=True):
        path = os.path.join(OUT, NAME + ".tmp")
        with open(path, "wb") as f:
            f.write(data)
        sh("ntfscp", "-f", part, path, "/" + name)
        os.unlink(path)
        if final:
            with open(os.path.join(files, name), "wb") as f:
                f.write(data)

    put("filler.bin", rnd.randbytes(cfg["filler"] * 1048576), final=False)
    if cfg.get("filler2"):
        put("filler2.bin", rnd.randbytes(cfg["filler2"] * 1048576), final=False)
    for i in range(1, cfg["small"] + 1):
        put("s%d.dat" % i, rnd.randbytes(700 + i * 37 + rnd.randrange(600)))
    put("big.bin", rnd.randbytes(cfg["big"]))
    if cfg["holes"]:
        n = cfg["holes"]
        for i in range(1, n + 1):
            put("p%d.dat" % i, rnd.randbytes(90000 + i * 111))
        for i in range(2, n + 1, 2):
            put("p%d.dat" % i, rnd.randbytes(600))
        put("frag.bin", rnd.randbytes(n * 40000))
    put("filler.bin", b"x", final=False)
    if cfg.get("filler2"):
        put("filler2.bin", b"x", final=False)
    print("ok")


main()
