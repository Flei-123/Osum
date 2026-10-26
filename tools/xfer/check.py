#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/xfer/check.py -- reads the serial output of tools/xfer/guest.sh and judges the transfer service.

    check.py <serial.txt>            prints `CHECK <name> ok|fail <note>` for every check
"""
import re
import sys

FNV_OFFSET = 0xCBF29CE484222325
FNV_PRIME = 0x100000001B3
MASK = (1 << 64) - 1


def fnv(data):
    h = FNV_OFFSET
    for b in data:
        h = ((h ^ b) * FNV_PRIME) & MASK
    return "%016x" % h


def pattern(n):
    return bytes(((i * 31 + (i >> 8) * 7 + 13) & 255) for i in range(n))


def sections(text):
    out = {}
    cur = None
    for ln in text.splitlines():
        m = re.search(r"^MARK-([a-z]+)\s*$", ln.strip())
        if m:
            cur = m.group(1)
            out[cur] = []
            continue
        if cur and "xclip:" in ln:
            out[cur].append(ln[ln.index("xclip:"):].strip())
    return out


def kv(line):
    return dict(re.findall(r"(\w+)=(\S+)", line))


def main():
    text = open(sys.argv[1], errors="replace").read()
    sec = sections(text)
    res = []

    def chk(name, cond, note=""):
        res.append((name, bool(cond), note))

    t = sec.get("text", [])
    gens = [kv(l) for l in t if l.startswith("xclip: gen ")]
    gots = [kv(l) for l in t if l.startswith("xclip: got ")]
    for i, n in enumerate([100, 192, 193, 4096, 4097, 1048576, 2097152]):
        g = gens[i] if i < len(gens) else {}
        r = gots[i] if i < len(gots) else {}
        want = fnv(pattern(n))
        chk("roundtrip_%d" % n, g.get("sum") == want and r.get("sum") == want and r.get("n") == str(n) and g.get("rc") == "0",
            "gen=%s got=%s want=%s" % (g.get("sum"), r.get("sum"), want))
    chk("too_big_refused", any(l.startswith("xclip: toobig") for l in t))

    z = sec.get("lazy", [])
    stats = [kv(l) for l in z if l.startswith("xclip: stat ")]
    s0 = stats[0] if len(stats) > 0 else {}
    s1 = stats[1] if len(stats) > 1 else {}
    s2 = stats[2] if len(stats) > 2 else {}
    s3 = stats[3] if len(stats) > 3 else {}
    chk("lazy_offer_counted", len(stats) >= 4 and int(s1.get("offers", 0)) == int(s0.get("offers", 0)) + 1)
    chk("lazy_no_fill_before_paste", len(stats) >= 4 and s1.get("fills") == s0.get("fills"),
        "fills %s -> %s" % (s0.get("fills"), s1.get("fills")))
    chk("lazy_wrong_type_no_fill", len(stats) >= 4 and s2.get("fills") == s0.get("fills"))
    wanted = [kv(l) for l in z if l.startswith("xclip: wanted ")]
    got = [kv(l) for l in z if l.startswith("xclip: got ")]
    want = fnv(pattern(300000))
    chk("lazy_fill_on_paste", len(stats) >= 4 and int(s3.get("fills", 0)) == int(s0.get("fills", 0)) + 1,
        "fills %s -> %s" % (s0.get("fills"), s3.get("fills")))
    chk("lazy_data_exact", bool(got) and got[-1].get("sum") == want and got[-1].get("n") == "300000" and
        bool(wanted) and wanted[-1].get("sum") == want)
    chk("lazy_wrong_type_refused", any(l.startswith("xclip: get fail") for l in z))

    m = sec.get("multi", [])
    wm = [kv(l) for l in m if l.startswith("xclip: wanted ")]
    tg = [kv(l) for l in m if l.startswith("xclip: got ")]
    hello = fnv(b"hello")
    chk("multi_each_type_asked_separately", [w.get("mime") for w in wm] == ["4", "1"], str([w.get("mime") for w in wm]))
    chk("multi_both_served", len(tg) == 2 and all(g.get("sum") == hello and g.get("n") == "5" for g in tg))

    e = sec.get("expiry", [])
    ty = [kv(l) for l in e if l.startswith("xclip: types")]
    chk("unserved_offer_gone_with_owner", bool(ty) and ty[-1].get("mask") != "8" and ty[-1].get("have") != "0", str(ty))

    c = sec.get("custom", [])
    mm = [l for l in c if l.startswith("xclip: mime ")]
    masks = [kv(l).get("mask") for l in mm]
    chk("custom_mime_stable", len(masks) >= 2 and masks[0] == masks[1] == "4294967296", str(masks))
    chk("custom_mime_second_bit", len(masks) >= 3 and masks[2] == "8589934592", str(masks))
    chk("custom_mime_name_roundtrip", any("application/x-osum-test mask=4294967296 application/x-osum-test" in l for l in mm))
    chk("invalid_mime_refused", any("nonsense" in l and kv(l).get("mask") == "0" for l in mm))
    cg = [kv(l) for l in c if l.startswith("xclip: got ")]
    chk("custom_mime_transfer", bool(cg) and cg[-1].get("sum") == fnv(pattern(5000)) and cg[-1].get("n") == "5000")

    p = sec.get("primary", [])
    texts = [l for l in p if l.startswith("xclip: text ")]
    chk("primary_separate_from_clipboard", len(texts) == 2 and texts[0].endswith("AAAA") and texts[1].endswith("BBBB"), str(texts))

    h = sec.get("history", [])
    ht = [l for l in h if l.startswith("xclip: text ")]
    hy = [kv(l) for l in h if l.startswith("xclip: types")]
    chk("history_newest_first", bool(ht) and ht[0].endswith("h25"))
    chk("history_ring_of_20", bool(hy) and hy[0].get("count") == "20")
    chk("history_oldest_kept_is_6", len(ht) >= 2 and ht[1].endswith("h06"), str(ht))
    chk("history_past_ring_refused", any(l.startswith("xclip: text fail") for l in h))

    v = sec.get("evict", [])
    vs = [kv(l) for l in v if l.startswith("xclip: stat ")]
    chk("eviction_frees_segments", len(vs) >= 2 and int(vs[1].get("freed", 0)) >= int(vs[0].get("freed", 0)) + 20 and
        int(vs[1].get("adopted", 0)) - int(vs[1].get("freed", 0)) <= 20,
        str([(x.get("adopted"), x.get("freed")) for x in vs]))

    u = sec.get("uris", [])
    uy = [kv(l) for l in u if l.startswith("xclip: types")]
    paths = [l[len("xclip: uri "):] for l in u if l.startswith("xclip: uri ")]
    chk("uri_list_type", bool(uy) and uy[0].get("mask") == "16", str(uy))
    chk("uri_list_paths_decoded", paths == ["/data/a b.txt", "/x/y"], str(paths))
    ut = [l for l in u if l.startswith("xclip: text ")]
    chk("uri_list_as_plain_text", bool(ut) and "/data/a b.txt" in ut[0])

    d = sec.get("drag", [])
    dty = [kv(l) for l in d if l.startswith("xclip: types")]
    nt = [l for l in d if l.startswith("xclip: noti ")]
    dt = [l for l in d if l.startswith("xclip: text ")]
    chk("drag_slot_independent", len(dty) >= 2 and dty[0].get("count") == "1" and dty[0].get("mask") == "2" and
        dty[-1].get("count") == "0", str(dty))
    chk("drag_replaced_by_second_source", bool(dt) and dt[0].endswith("/data/file2"), str(dt))
    chk("drag_does_not_clobber_notifications", bool(nt) and "probe-noti" in nt[-1], str(nt))

    k = sec.get("leak", [])
    ks = [kv(l) for l in k if l.startswith("xclip: stat ")]
    kt = [kv(l) for l in k if l.startswith("xclip: types")]
    chk("clipboard_emptied", bool(kt) and kt[-1].get("count") == "0")
    chk("no_segment_leak", bool(ks) and ks[-1].get("adopted") == ks[-1].get("freed") and ks[-1].get("adopted") != "0",
        str(ks[-1:] ))

    for name, okv, note in res:
        print("CHECK %s %s %s" % (name, "ok" if okv else "fail", note))


if __name__ == "__main__":
    main()
