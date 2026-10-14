#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/qa/gen-manifest.py -- (re)generate tools/qa/gates.tsv from tools/*/run.sh.

The manifest is the single list of gates: which paths trigger a gate, which
tier it belongs to (quick / full / nightly) and what it needs (net lock, kvm).
Hand edits survive: rows whose 'source' column is 'manual' are kept as they are.
New run.sh scripts get a guessed row with source 'auto' (tier from a size/qemu
heuristic, paths = their own directory + the area of their name) -- review them.

  gen-manifest.py            write tools/qa/gates.tsv
  gen-manifest.py --check    exit 1 if a run.sh has no row or a row has no script
  gen-manifest.py --by-times re-tier 'auto' rows from measured wall times (gates.sh --times file,
                             GATES_TIMES): fastest valid run <= 300 s quick, <= 1200 s full, else
                             nightly. Runs killed by a limit (rc 124/137/143) are not measurements.
                             Gates without a valid measurement keep their heuristic tier.
"""
import glob, os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "tools", "qa", "gates.tsv")
HEADER = "gate\ttier\tneeds\tpaths\tsource\tnote"

# area -> path globs (ERE-free shell-style globs, matched with fnmatch on repo paths)
AREAS = {
    "ui":     ["kernel/ui/*", "kernel/gfx/*", "lib/fui/*", "lib/font/*", "assets/schemes/*", "assets/shapes/*",
               "assets/themes/*", "etc/themes/*", "etc/shapes/*", "etc/schemas/*"],
    "apps":   ["kernel/user/*", "assets/apps/*", "assets/icons/*", "etc/orientbus/*"],
    "net":    ["kernel/net/*", "lib/net/*", "lib/tls/*", "lib/wg/*", "lib/socks/*", "etc/ssl/*", "etc/netview/*"],
    "fs":     ["kernel/fs/*", "kernel/block/*", "lib/disks/*"],
    "core":   ["kernel/arch/*", "kernel/sched/*", "kernel/mm/*", "kernel/sync/*", "kernel/ipc/*", "kernel/core.fi",
               "kernel/kmain.fi", "kernel/kcore.fi", "kernel/tasks.fi", "kernel/klog.fi", "kernel/serial.fi", "kernel/lib/*"],
    "drv":    ["kernel/drv/*", "kernel/usb/*", "kernel/pwr/*", "kernel/acpi/*"],
    "libc":   ["lib/libc/*", "kernel/sys/*", "kernel/ldr/*", "lib/std/*"],
    "crypto": ["kernel/crypto/*", "lib/crypto/*", "lib/ssh/*"],
    "bridge": ["etc/jarvis/*", "assets/jarvis/*", "kernel/bus/*", "kernel/app/*"],
    "tools":  ["tools/build-kernel.sh", "tools/kernel/*", "vendor/firn/*", "tools/config"],
}
GATE_AREAS = {
    "ui": "wm comp paint look design themestore tiling menualive menuhover startmenu tabstrip midline win11bar barscene barpop "
          "qsfui lockscene loginscene signinlook lockflicker lockseal lockrace loginui fourbugs drag glyph sceneclip softui "
          "aacorner desktop explorer2 k15 overview icons deco display gfx customres toolbench alltag a11y vsync wayland tokens "
          "region clip2 umlaut i18n english rtl guieditor dmodul progsize disklag",
    "apps": "k11 k13 k16 k18 account actionbus presence social store update ota install usbimg stick init logind svclog multiuser "
            "clip2 print handle async entry loader",
    "net": "net keepalive netzplus netzui netview netmon hwnet tunnel sshd wlan sync poll ebpf",
    "fs": "ofs3 fsrobust fremdfs k14 disks storage mem oom hardening",
    "core": "smp multicore execsmp elfsmp kernel osum core freestanding guard kvm hv pci ahci aml arm metal metal2 caps boot "
            "mem oom zreap time vsync suspend",
    "drv": "hid hidpunkte hidweg hotplug hda s3 s3dev s3smp powermon gpu3d k17 aesni avx",
    "libc": "posix unix userland dynlader module operation protocol systembus struktur e2e",
    "crypto": "krypto argon vault xtstafel geraetekey codec pdf",
    "bridge": "bridge server",
}
# gates that are expensive or need the whole system: nightly only (full run = before a big merge)
NIGHTLY = set("ota install usbimg fsrobust hv design themestore actionbus vault sync wmplug metal wlan netview k15 k11 k17 "
              "suspend bridge server store stick kvm smp multicore s3smp".split())
# cheap + broad: run at 'quick' level when their area changed (host-only gates, small scripts)
HOSTONLY = set("english hardening overview progsize softui tokens update xtstafel region".split())
NETLOCK = set("account actionbus aml bridge ebpf hwnet install net netmon netview netzplus netzui poll print rtl sshd tunnel".split())
# representative per-area smoke gates that run at quick level for any change in their area
QUICK_REP = set("tokens softui aacorner wm kernel userland posix pci net ofs3 krypto hid k13 midline lockscene".split())


def gates():
    return sorted(os.path.basename(os.path.dirname(p)) for p in glob.glob(os.path.join(ROOT, "tools", "*", "run.sh")))


def area_of(g):
    out = []
    for a, names in GATE_AREAS.items():
        if g in names.split():
            out.append(a)
    return out or ["apps"]


def tier_of(g):
    if g in NIGHTLY:
        return "nightly"
    if g in HOSTONLY or g in QUICK_REP:
        return "quick"
    return "full"


def row(g):
    areas = area_of(g)
    paths = [f"tools/{g}/*"]
    for a in areas:
        paths += AREAS[a]
    needs = []
    if g in NETLOCK:
        needs.append("netlock")
    if g not in HOSTONLY:
        needs.append("qemu")
    return [g, tier_of(g), ",".join(needs) or "-", ",".join(dict.fromkeys(paths)), "auto", "areas=" + "+".join(areas)]


QUICK_MAX_S = 300
FULL_MAX_S = 1200


def measured_tiers():
    path = os.environ.get("GATES_TIMES") or os.path.join(
        os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache"), "osum-gates", "times.tsv")
    best = {}
    if not os.path.exists(path):
        return best
    for ln in open(path, encoding="utf-8").read().splitlines():
        f = ln.split("\t")
        if len(f) < 4 or not f[1].isdigit():
            continue
        rc = f[3].replace("rc=", "")
        if rc in ("124", "137", "143"):
            continue
        t = int(f[1])
        if f[0] not in best or t < best[f[0]]:
            best[f[0]] = t
    return {g: ("quick" if t <= QUICK_MAX_S else "full" if t <= FULL_MAX_S else "nightly") for g, t in best.items()}


def read_old():
    old = {}
    if os.path.exists(OUT):
        for ln in open(OUT, encoding="utf-8").read().splitlines()[1:]:
            f = ln.split("\t")
            if len(f) >= 6:
                old[f[0]] = f
    return old


def main():
    cur = gates()
    old = read_old()
    if "--check" in sys.argv:
        miss = [g for g in cur if g not in old]
        gone = [g for g in old if g not in cur]
        for g in miss:
            print(f"gates.tsv: no row for tools/{g}/run.sh -- run tools/qa/gen-manifest.py")
        for g in gone:
            print(f"gates.tsv: row '{g}' has no tools/{g}/run.sh")
        print(f"gates.tsv: {len(cur)} gates, {len(miss)} missing, {len(gone)} stale")
        sys.exit(1 if miss or gone else 0)
    meas = measured_tiers() if "--by-times" in sys.argv else {}
    rows = []
    for g in cur:
        if g in old and old[g][4] == "manual":
            rows.append(old[g])
        else:
            r = row(g)
            if g in meas:
                r[1] = meas[g]
            elif g in old and "--by-times" in sys.argv:
                r[1] = old[g][1]
            rows.append(r)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(HEADER + "\n")
        for r in rows:
            f.write("\t".join(r) + "\n")
    print(f"wrote {OUT}: {len(rows)} gates")


if __name__ == "__main__":
    main()
