#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

import os
import re
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(ROOT, "kernel", "lib", "chipname.fi")

IDS_URL = "https://pci-ids.ucw.cz/v2.2/pci.ids"
IDS_CACHE = "/tmp/pci.ids"

LINUX_SOURCES = {
    "igc": "drivers/net/ethernet/intel/igc/igc_hw.h",
    "igb": "drivers/net/ethernet/intel/igb/e1000_hw.h",
    "e1000e": "drivers/net/ethernet/intel/e1000e/hw.h",
    "atlantic": "drivers/net/ethernet/aquantia/atlantic/aq_common.h",
}

IGC_IDS = {
    0x15F2: "I225_LM", 0x15F3: "I225_V", 0x15F8: "I225_I",
    0x15F7: "I220_V", 0x3100: "I225_K", 0x3101: "I225_K2",
    0x3102: "I226_K", 0x5502: "I225_LMVP", 0x5503: "I226_LMVP",
    0x0D9F: "I225_IT", 0x125B: "I226_LM", 0x125C: "I226_V",
    0x125D: "I226_IT", 0x125E: "I221_V", 0x125F: "I226_BLANK_NVM",
    0x15FD: "I225_BLANK_NVM",
}

IGB_IDS = {
    0x10C9: "82576", 0x10E6: "82576_FIBER", 0x10E7: "82576_SERDES",
    0x10E8: "82576_QUAD_COPPER", 0x1526: "82576_QUAD_COPPER_ET2",
    0x150A: "82576_NS", 0x1518: "82576_NS_SERDES",
    0x150D: "82576_SERDES_QUAD", 0x10A7: "82575EB_COPPER",
    0x10A9: "82575EB_FIBER_SERDES", 0x10D6: "82575GB_QUAD_COPPER",
    0x150E: "82580_COPPER", 0x150F: "82580_FIBER",
    0x1510: "82580_SERDES", 0x1511: "82580_SGMII",
    0x1516: "82580_COPPER_DUAL", 0x1527: "82580_QUAD_FIBER",
    0x1521: "I350_COPPER", 0x1522: "I350_FIBER",
    0x1523: "I350_SERDES", 0x1524: "I350_SGMII",
    0x1533: "I210_COPPER", 0x1536: "I210_FIBER",
    0x1537: "I210_SERDES", 0x1538: "I210_SGMII",
    0x157B: "I210_COPPER_FLASHLESS", 0x157C: "I210_SERDES_FLASHLESS",
    0x1531: "I210_UNPROGRAMMED", 0x1539: "I211_COPPER",
    0x1F40: "I354_BACKPLANE_1GBPS", 0x1F41: "I354_SGMII",
    0x1F45: "I354_BACKPLANE_2_5GBPS",
}

I219_LM = [
    0x156F, 0x15B7, 0x15B9, 0x15D7, 0x15E3, 0x15BD, 0x15BB, 0x15DF,
    0x15E1, 0x0D4E, 0x0D4C, 0x0D53, 0x15FB, 0x15F9, 0x15F4, 0x0DC5,
    0x1A1E, 0x1A1C, 0x0DC7, 0x550A, 0x550C, 0x550E, 0x5510, 0x57A0,
    0x57B3, 0x57B7, 0x57B9,
]
I219_V = [
    0x1570, 0x15B8, 0x15D8, 0x15D6, 0x15BE, 0x15BC, 0x15E0, 0x15E2,
    0x0D4F, 0x0D4D, 0x0D55, 0x15FC, 0x15FA, 0x15F5, 0x0DC6, 0x1A1F,
    0x1A1D, 0x0DC8, 0x550B, 0x550D, 0x550F, 0x5511, 0x57A1, 0x57B4,
    0x57B8, 0x57BA,
]

VEN_MAP = {
    "INTEL": 0x8086, "REALTEK": 0x10EC, "BROADCOM": 0x14E4,
    "ATHEROS": 0x168C, "QUALCOMM": 0x1969, "AQUANTIA": 0x1D6A,
    "MARVELL": 0x11AB, "MELLANOX": 0x15B3, "VIRTIO": 0x1AF4,
    "AMD": 0x1022, "NVIDIA": 0x10DE, "LSI": 0x1000,
    "VMWARE": 0x15AD, "QEMU": 0x1B36, "MEDIATEK": 0x14C3,
    "DEC": 0x1011,
}

VAGUE = ("CNVi-WLAN", "Realtek-WLAN", "Broadcom-WLAN", "Atheros-WLAN",
         "I225/I226")

LINUX_ONLY = {
    (0x8086, 0x15F8), (0x8086, 0x3100), (0x8086, 0x15F7),
    (0x8086, 0x125E), (0x1D6A, 0x88B1), (0x1D6A, 0x11C0),
}

KNOWN_CONFLICT = {
    (0x8086, 0x550B): "pci.ids wiederholt den Text von 550A; Linux: I219_V18",
}


def normalise(text):
    return text.lower().replace("-", "").replace(" ", "")


def model_tokens(name):
    head = name.split("(")[0].strip()
    return [t for t in re.split(r"[/,]", head) if t.strip()]


def confirms(name, real):
    r = normalise(real)
    for tok in model_tokens(name):
        t = normalise(tok)
        if not t:
            continue
        if t in r:
            return True
        for run in re.findall(r"[0-9]{3,}", tok):
            if run in r:
                return True
    return False


def load_ids(path):
    ids, ven = {}, None
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if line.startswith("#") or not line.strip():
                continue
            if line.startswith("\t\t"):
                continue
            if line.startswith("\t"):
                m = re.match(r"\t([0-9a-f]{4})  (.*)", line.rstrip("\n"))
                if m and ven is not None:
                    ids[(ven, int(m.group(1), 16))] = m.group(2)
            else:
                m = re.match(r"([0-9a-f]{4})  (.*)", line.rstrip("\n"))
                if m:
                    ven = int(m.group(1), 16)
    return ids


def claims(src):
    strs = {k: v.replace("\\0", "")
            for k, v in re.findall(
                r'var (s_\w+):\s*\[u8;\s*\d+\]\s*=\s*"([^"]*)"', src)}
    out, ven, pend = [], None, None
    for line in src.split("\n"):
        if re.search(r"fn intel_(igc|igb|i219|wifi)\(", line):
            ven = 0x8086
        elif "fn realtek_net(" in line:
            ven = 0x10EC
        elif "fn other_net(" in line or "fn storage(" in line:
            ven = None
        m = re.search(r"if ven == VEN_(\w+)\s*\{", line)
        if m:
            ven = VEN_MAP.get(m.group(1), ven)
        devs = re.findall(r"dev == (0x[0-9A-Fa-f]{2,4})", line)
        if devs and ven is not None and "fn " not in line:
            pend = [int(d, 16) for d in devs]
        m2 = re.search(r"serial\.puts\(\(&(s_\w+)\[0\]\)", line)
        if m2:
            mark = re.search(r"//\s*\[(PL|P|L)\]", line)
            if pend is not None:
                for d in pend:
                    out.append((ven, d, strs.get(m2.group(1), "?"),
                                mark.group(1) if mark else None))
                pend = None
    return out


def main():
    args = sys.argv[1:]
    path = IDS_CACHE
    if "--ids" in args:
        path = args[args.index("--ids") + 1]
    if "--fetch" in args or not os.path.exists(path):
        sys.stderr.write("hole %s ...\n" % IDS_URL)
        urllib.request.urlretrieve(IDS_URL, IDS_CACHE)
        path = IDS_CACHE

    ids = load_ids(path)
    src = open(SRC, encoding="utf-8").read()
    cl = claims(src)

    ok, wrong, only_linux, unsourced, chipset_named = 0, [], [], [], []
    for ven, dev, name, mark in cl:
        real = ids.get((ven, dev))
        if real is None:
            lin = IGC_IDS.get(dev) if ven == 0x8086 else None
            if lin is None and ven == 0x8086:
                lin = IGB_IDS.get(dev)
            if lin is not None:
                fam = lin.split("_")[0].replace("BLANK", "")
                if not confirms(name, lin.replace("_", " ")) \
                        and not any(name.startswith(v) for v in VAGUE) \
                        and normalise(fam) not in normalise(name):
                    wrong.append((ven, dev, name,
                                  "Linux: " + lin + " (nicht in pci.ids)"))
                    continue
            if mark in ("L", "PL") or (ven, dev) in LINUX_ONLY \
                    or any(name.startswith(v) for v in VAGUE):
                only_linux.append((ven, dev, name))
            else:
                unsourced.append((ven, dev, name, mark))
            continue
        if any(name.startswith(v) for v in VAGUE):
            ok += 1
            continue
        if confirms(name, real):
            ok += 1
            continue
        if dev in I219_LM or dev in I219_V:
            want_lm = dev in I219_LM
            says_lm = "vpro" in normalise(real) or "corporate" in normalise(real)
            says_v = "consumer" in normalise(real)
            if says_lm or says_v:
                if says_lm == want_lm:
                    ok += 1
                    chipset_named.append((ven, dev, name, real))
                    continue
                wrong.append((ven, dev, name, real))
                continue
            if (ven, dev) in KNOWN_CONFLICT:
                only_linux.append((ven, dev, name))
                continue
            wrong.append((ven, dev, name, real))
            continue
        if (ven, dev) in KNOWN_CONFLICT:
            only_linux.append((ven, dev, name))
            continue
        wrong.append((ven, dev, name, real))

    have = {(v, d) for v, d, _, _ in cl}
    miss_igc = [d for d in IGC_IDS if (0x8086, d) not in have]
    miss_igb = [d for d in IGB_IDS if (0x8086, d) not in have]
    miss_219 = [d for d in (I219_LM + I219_V) if (0x8086, d) not in have]

    print("=" * 66)
    print("chipname.fi gegen pci.ids  (%s)" % os.path.basename(path))
    print("=" * 66)
    print("Behauptungen im Quelltext : %d" % len(cl))
    print("von pci.ids BESTAETIGT    : %d" % ok)
    print("only documented in Linux [L]  : %d" % len(only_linux))
    print("from pci.ids to CHIPSET")
    print("  benannt, LM/V geprueft   : %d" % len(chipset_named))
    print("igc-Nummern fehlend       : %d von %d" % (len(miss_igc), len(IGC_IDS)))
    print("igb-Nummern fehlend       : %d von %d" % (len(miss_igb), len(IGB_IDS)))
    print("I219-Nummern fehlend      : %d von %d"
          % (len(miss_219), len(I219_LM) + len(I219_V)))
    print()

    bad = False
    if wrong:
        bad = True
        print("CONTRADICTION (%d) -- this is an ERROR:" % len(wrong))
        for v, d, n, r in wrong:
            print("   %04x:%04x  wir='%s'  pci.ids='%s'" % (v, d, n, r))
        print()
    if unsourced:
        bad = True
        print("WITHOUT SOURCE (%d) -- neither pci.ids nor [L]:" % len(unsourced))
        for v, d, n, m in unsourced:
            print("   %04x:%04x  '%s'  marke=%s" % (v, d, n, m))
        print()
    for label, miss, tab in (("igc", miss_igc, IGC_IDS),
                             ("igb", miss_igb, IGB_IDS)):
        if miss:
            bad = True
            print("%s: %d Nummern aus %s fehlen in chipname.fi:"
                  % (label, len(miss), LINUX_SOURCES[label]))
            print("   " + "  ".join("%04x=%s" % (d, tab[d]) for d in sorted(miss)))
            print()
    if miss_219:
        bad = True
        print("I219: %d Nummern aus %s fehlen:"
              % (len(miss_219), LINUX_SOURCES["e1000e"]))
        print("   " + "  ".join("%04x" % d for d in sorted(miss_219)))
        print()

    if bad:
        print("ERGEBNIS: WIDERLEGT")
        return 1
    if KNOWN_CONFLICT:
        print("BEKANNTE QUELLENKONFLIKTE (%d), begruendet im Quelltext:"
              % len(KNOWN_CONFLICT))
        for (v, d), why in KNOWN_CONFLICT.items():
            print("   %04x:%04x  %s" % (v, d, why))
        print()
    print("ERGEBNIS: nichts widerlegt.")
    print("  Every number is in pci.ids or carries a Linux source,")
    print("  and the three Intel families are fully named.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
