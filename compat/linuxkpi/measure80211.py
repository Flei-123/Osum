import json
import lzma
import os
import re
import sys
import tempfile

import measure

WL = "drivers/net/wireless/"
STACKS = {
    "iwlwifi": {"modules": [WL + "intel/iwlwifi/iwlwifi", WL + "intel/iwlwifi/mvm/iwlmvm"],
                "sources": [WL + "intel/iwlwifi", WL + "intel/iwlwifi/fw", WL + "intel/iwlwifi/cfg",
                            WL + "intel/iwlwifi/pcie", WL + "intel/iwlwifi/mvm"]},
    "rtw88": {"modules": [WL + "realtek/rtw88/rtw88_core", WL + "realtek/rtw88/rtw88_pci",
                          WL + "realtek/rtw88/rtw88_8822c", WL + "realtek/rtw88/rtw88_8822ce"],
              "sources": [WL + "realtek/rtw88"]},
    "rtw89": {"modules": [WL + "realtek/rtw89/rtw89_core", WL + "realtek/rtw89/rtw89_pci",
                          WL + "realtek/rtw89/rtw89_8852c", WL + "realtek/rtw89/rtw89_8852ce"],
              "sources": [WL + "realtek/rtw89"]},
    "mt76": {"modules": [WL + "mediatek/mt76/mt76", WL + "mediatek/mt76/mt76-connac-lib",
                         WL + "mediatek/mt76/mt792x-lib", WL + "mediatek/mt76/mt7921/mt7921-common",
                         WL + "mediatek/mt76/mt7921/mt7921e"],
             "sources": [WL + "mediatek/mt76", WL + "mediatek/mt76/mt7921"]},
    "ath10k": {"modules": [WL + "ath/ath", WL + "ath/ath10k/ath10k_core", WL + "ath/ath10k/ath10k_pci"],
               "sources": [WL + "ath", WL + "ath/ath10k"]},
    "ath11k": {"modules": [WL + "ath/ath", WL + "ath/ath11k/ath11k", WL + "ath/ath11k/ath11k_pci"],
               "sources": [WL + "ath", WL + "ath/ath11k"]},
}
PROVIDERS = {"mac80211": "net/mac80211/mac80211", "cfg80211": "net/wireless/cfg80211"}
NET_RULES = [("net/core", "net core (skb/netdev/napi)"), ("net/ethernet", "net core (skb/netdev/napi)"),
             ("net/", "net other"), ("crypto", "crypto")]
WIFI_HEADERS = re.compile(r"^(net/(mac80211|cfg80211|ieee80211_radiotap|regulatory)\.h|linux/ieee80211\.h)$")
INCLUDE = re.compile(r'^\s*#\s*include\s*<([^>]+)>', re.M)
OPS_BLOCK = re.compile(r"struct ieee80211_ops\s+\w+\s*=\s*\{(.*?)\n\};", re.S)
OPS_FIELD = re.compile(r"^\s*\.(\w+)\s*=", re.M)


def load_ko(ko_dir, rel, tmp):
    src = os.path.join(ko_dir, rel + ".ko.xz")
    if not os.path.exists(src):
        return None
    out = os.path.join(tmp, rel.replace("/", "_") + ".ko")
    with lzma.open(src) as fin, open(out, "wb") as fout:
        fout.write(fin.read())
    return out


def symbols(paths):
    undef, defined = set(), set()
    for path in paths:
        undef |= measure.nm_undefined(path)
        defined |= measure.nm_defined(path)
    return {s for s in undef - defined if not measure.ARTIFACT.match(s)}, defined


def base_group(path):
    if path:
        for prefix, name in NET_RULES:
            if path.startswith(prefix):
                return name
    return measure.group_of(path)


def source_files(root, dirs):
    for rel in dirs:
        base = os.path.join(root, rel)
        if not os.path.isdir(base):
            continue
        for name in sorted(os.listdir(base)):
            if name.endswith((".c", ".h")):
                yield os.path.join(base, name)


def scan_sources(root, dirs):
    headers, ops, lines, files = set(), set(), 0, 0
    for path in source_files(root, dirs):
        with open(path, "r", errors="replace") as fh:
            text = fh.read()
        files += 1
        lines += text.count("\n")
        headers |= set(INCLUDE.findall(text))
        for block in OPS_BLOCK.findall(text):
            ops |= set(OPS_FIELD.findall(block))
    wifi = sorted(h for h in headers if WIFI_HEADERS.match(h))
    linux = sorted(h for h in headers if h.startswith(("linux/", "asm/", "net/", "crypto/", "uapi/")) and h not in wifi)
    return {"files": files, "lines": lines, "wifi_headers": wifi, "base_headers": len(linux),
            "base_header_names": linux, "ieee80211_ops": sorted(ops)}


def measure_stack(need, mods, provider_defs, mapping, wl_src, cfg):
    split = {p: sorted(need & d) for p, d in provider_defs.items()}
    base = sorted(need - set().union(*provider_defs.values()))
    groups = {}
    for sym in base:
        groups.setdefault(base_group(mapping.get(sym)), []).append(sym)
    result = {"modules": len(mods), "needed": len(need), "mac80211": len(split["mac80211"]),
              "cfg80211": len(split["cfg80211"]), "base": len(base),
              "base_groups": {g: len(v) for g, v in sorted(groups.items(), key=lambda kv: -len(kv[1]))},
              "base_names": {g: sorted(v) for g, v in groups.items()},
              "mac80211_names": split["mac80211"], "cfg80211_names": split["cfg80211"],
              "ko_bytes": sum(os.path.getsize(m) for m in mods)}
    result["source"] = scan_sources(wl_src, cfg["sources"])
    return result


def main():
    ko_dir, src, wl_src, out_json = sys.argv[1:5]
    with tempfile.TemporaryDirectory() as tmp:
        provider_paths = {p: load_ko(ko_dir, rel, tmp) for p, rel in PROVIDERS.items()}
        provider_defs = {p: measure.nm_defined(path) for p, path in provider_paths.items()}
        own_need, _ = symbols(list(provider_paths.values()))
        report = {"linux_mac80211_cfg80211_need": len(own_need - set().union(*provider_defs.values())),
                  "mac80211_exports": len(provider_defs["mac80211"]), "cfg80211_exports": len(provider_defs["cfg80211"])}
        loaded = {}
        for name, cfg in STACKS.items():
            mods = [load_ko(ko_dir, rel, tmp) for rel in cfg["modules"]]
            if None in mods:
                report[name] = {"missing": [r for r, m in zip(cfg["modules"], mods) if m is None]}
                continue
            loaded[name] = (mods, symbols(mods)[0])
        known = set().union(*provider_defs.values())
        mapping = measure.export_map(src, set().union(*[need - known for _, need in loaded.values()]))
        for name, (mods, need) in loaded.items():
            report[name] = measure_stack(need, mods, provider_defs, mapping, wl_src, STACKS[name])
    stacks = [n for n in STACKS if "needed" in report[n]]
    for p in PROVIDERS:
        sets = [set(report[n][p + "_names"]) for n in stacks]
        report["union_" + p] = len(set().union(*sets))
        report["intersection_" + p] = len(set.intersection(*sets))
    with open(out_json, "w") as fh:
        json.dump(report, fh, indent=1, sort_keys=True)
    for n in stacks:
        r = report[n]
        print(f"{n}: needed={r['needed']} mac80211={r['mac80211']} cfg80211={r['cfg80211']} base={r['base']} "
              f"ops={len(r['source']['ieee80211_ops'])} lines={r['source']['lines']} ko_kb={r['ko_bytes'] // 1024}")
    print("union mac80211", report["union_mac80211"], "intersection", report["intersection_mac80211"],
          "| union cfg80211", report["union_cfg80211"], "intersection", report["intersection_cfg80211"])


if __name__ == "__main__":
    main()
