import json, subprocess, sys

media, serial = sys.argv[1], sys.argv[2]
out = subprocess.run(
    ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
     "packet=pos,size,pts_time,dts_time,flags", "-of", "json", media],
    capture_output=True, text=True, check=True).stdout
packets = json.loads(out)["packets"]
items = []
for line in open(serial, errors="replace"):
    line = line.replace("\r", "").replace("\0", "")
    if line.startswith("vdec: item "):
        items.append([int(x) for x in line.split()[2:]])
if len(items) != len(packets):
    print("count %d != %d" % (len(items), len(packets)))
    sys.exit(1)
bad = 0
for it, pk in zip(items, packets):
    _, off, size, dts, cts, key = it
    want_dts = int(float(pk["dts_time"]) * 1000 + 0.5)
    want_cts = int(float(pk["pts_time"]) * 1000 + 0.5)
    ok = (off == int(pk["pos"]) and size == int(pk["size"])
          and abs(dts - want_dts) <= 1 and abs(cts - want_cts) <= 1
          and key == (1 if "K" in pk["flags"] else 0))
    if not ok:
        bad += 1
        print("item %d: got %s want %s" % (it[0], it[1:], pk))
print("%d items, %d wrong" % (len(items), bad))
sys.exit(1 if bad else 0)
