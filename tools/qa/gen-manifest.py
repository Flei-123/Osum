#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import glob, os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "tools", "qa", "gates.tsv")
RUNNERS = os.path.join(ROOT, "tools", "qa", "runners.tsv")
HEADER = "gate\ttier\tneeds\tpaths\tsource\tnote"
RUNNERS_HEADER = "gate\tcommand\trequires"
SCRIPT_RE = re.compile(r"tools/[A-Za-z0-9_./-]+\.sh")
NO_RUNNER = "-"

AREAS = {
    "ui":     ["kernel/ui/*", "kernel/gfx/*", "lib/fui/*", "lib/font/*", "assets/schemes/*", "assets/shapes/*",
               "assets/themes/*", "etc/themes/*", "etc/shapes/*", "etc/schemas/*"],
    "apps":   ["kernel/user/*", "assets/apps/*", "assets/icons/*", "etc/orientbus/*"],
    "net":    ["kernel/net/*", "lib/net/*", "lib/httpget/*", "lib/tls/*", "lib/wg/*", "lib/socks/*", "etc/ssl/*", "etc/netview/*"],
    "fs":     ["kernel/fs/*", "kernel/block/*", "lib/disks/*"],
    "core":   ["kernel/arch/*", "kernel/sched/*", "kernel/mm/*", "kernel/sync/*", "kernel/ipc/*", "kernel/core.fi",
               "kernel/kmain.fi", "kernel/init/*", "kernel/kcore.fi", "kernel/tasks.fi", "kernel/klog.fi", "kernel/serial.fi", "kernel/lib/*",
               "firn.toolchain", "tools/lib/firnenv.sh"],
    "drv":    ["kernel/drv/*", "kernel/usb/*", "kernel/pwr/*", "kernel/acpi/*"],
    "libc":   ["lib/libc/*", "kernel/sys/*", "kernel/ldr/*", "lib/std/*"],
    "crypto": ["kernel/crypto/*", "lib/crypto/*", "lib/codec/*", "lib/ssh/*"],
    "bridge": ["etc/jarvis/*", "assets/jarvis/*", "kernel/bus/*", "kernel/app/*"],
    "tools":  ["tools/build-kernel.sh", "tools/kernel/*", "firn.toolchain", "tools/lib/firnenv.sh", "tools/config"],
}
GATE_AREAS = {
    "ui": "wm comp paint look design themestore tiling menualive menuhover startmenu tabstrip midline win11bar barscene barpop "
          "qsfui lockscene loginscene signinlook lockflicker lockseal lockrace loginui fourbugs drag glyph sceneclip softui "
          "aacorner desktop explorer2 k15 overview icons deco display gfx customres toolbench alltag a11y vsync wayland tokens "
          "region clip2 umlaut i18n english rtl guieditor dmodul progsize disklag",
    "apps": "k11 k13 k16 k18 account actionbus presence social store update ota install usbimg stick init logind svclog multiuser "
            "clip2 print handle async entry loader",
    "net": "net keepalive netzplus netzui netview netmon hwnet tunnel sshd wlan sync poll ebpf sockmax",
    "fs": "ofs3 fsrobust fremdfs k14 disks storage mem oom hardening",
    "core": "smp multicore execsmp elfsmp kernel osum core freestanding guard kvm hv pci ahci aml arm metal metal2 caps boot "
            "mem oom zreap time vsync suspend",
    "drv": "hid hidpunkte hidweg hotplug hda s3 s3dev s3smp powermon power gpu3d k17 aesni avx",
    "libc": "posix unix userland dynlader module operation protocol systembus struktur e2e",
    "crypto": "krypto argon vault xtstafel geraetekey codec pdf",
    "bridge": "bridge server",
}
NIGHTLY = set("ota install usbimg fsrobust hv design themestore actionbus vault sync wmplug metal wlan netview k15 k11 k17 "
              "suspend bridge server store stick kvm smp multicore s3smp".split())
HOSTONLY = set("english hardening overview progsize softui tokens update xtstafel region".split())
NETLOCK = set("account actionbus aml bridge ebpf hwnet install net netmon netview netzplus netzui poll print rtl sshd tunnel".split())
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


def read_runners():
    rows = {}
    if not os.path.exists(RUNNERS):
        return rows
    lines = open(RUNNERS, encoding="utf-8").read().splitlines()
    for n, ln in enumerate(lines[1:], 2):
        f = ln.split("\t")
        rows.setdefault(f[0], []).append((n, f))
    return rows


def check_runners(old, cur):
    problems = []
    lines = open(RUNNERS, encoding="utf-8").read().splitlines() if os.path.exists(RUNNERS) else []
    if not lines or lines[0] != RUNNERS_HEADER:
        problems.append(f"runners.tsv: header must be '{RUNNERS_HEADER}'")
    runners = read_runners()
    for g, entries in runners.items():
        if len(entries) > 1:
            problems.append(f"runners.tsv: gate '{g}' listed {len(entries)} times")
        n, f = entries[0]
        if len(f) != 3 or not f[1] or not f[2]:
            problems.append(f"runners.tsv:{n}: '{g}' needs gate<TAB>command<TAB>requires")
            continue
        if g not in old:
            problems.append(f"runners.tsv:{n}: gate '{g}' has no row in gates.tsv")
        if f[1] == NO_RUNNER:
            continue
        script = SCRIPT_RE.search(f[1])
        if not script or not os.path.isfile(os.path.join(ROOT, script.group(0))):
            problems.append(f"runners.tsv:{n}: '{g}' command names no existing tools/*.sh script")
    for g, row in old.items():
        if row[4] == "manual" and g not in cur and g not in runners:
            problems.append(f"gates.tsv: manual gate '{g}' has no tools/{g}/run.sh and no runners.tsv row")
    return problems


def manifest_order(cur, old):
    kept = [g for g in old if g in cur or old[g][4] == "manual"]
    return kept + [g for g in cur if g not in old]


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
        gone = [g for g in old if g not in cur and old[g][4] != "manual"]
        for g in miss:
            print(f"gates.tsv: no row for tools/{g}/run.sh -- run tools/qa/gen-manifest.py")
        for g in gone:
            print(f"gates.tsv: row '{g}' has no tools/{g}/run.sh")
        problems = check_runners(old, cur)
        for p in problems:
            print(p)
        print(f"gates.tsv: {len(cur)} gates, {len(miss)} missing, {len(gone)} stale, {len(problems)} runner problems")
        sys.exit(1 if miss or gone or problems else 0)
    meas = measured_tiers() if "--by-times" in sys.argv else {}
    regenerate = "--refresh" in sys.argv or "--by-times" in sys.argv
    rows = []
    for g in manifest_order(cur, old):
        if g in old and (old[g][4] == "manual" or not regenerate):
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
