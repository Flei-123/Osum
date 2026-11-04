import json
import os
import re
import subprocess
import sys

DRIVERS = ["bochs", "i915", "xe", "amdgpu", "nouveau"]
SUPPORT = ["drm", "drm_kms_helper", "drm_display_helper", "ttm", "drm_ttm_helper", "gpu-sched", "drm_exec",
           "drm_buddy", "drm_gpuvm", "drm_suballoc_helper", "drm_shmem_helper", "drm_vram_helper", "amdxcp",
           "i2c-algo-bit"]
GROUP_RULES = [
    ("mm/", "memory"), ("kernel/locking", "locks"), ("kernel/workqueue", "workqueue"),
    ("kernel/sched", "sched/wait"), ("kernel/time", "time/timers"), ("kernel/rcu", "rcu/srcu"),
    ("kernel/irq", "irq"), ("lib/", "lib (idr/xarray/kref/string/sg/sort/list)"),
    ("drivers/base/firmware", "firmware"), ("drivers/base", "device model/devres"), ("drivers/pci", "pci"),
    ("drivers/dma-buf", "dma-buf/fence/sync_file"), ("drivers/i2c", "i2c"), ("drivers/acpi", "acpi"),
    ("drivers/video", "video/aperture/fbdev"), ("drivers/char", "char/agp"), ("drivers/gpu", "gpu other"),
    ("arch/x86", "x86 arch"), ("fs/", "vfs/file/debugfs"), ("net/", "net/netlink"), ("kernel/", "kernel misc"),
    ("crypto", "crypto"), ("security", "security"), ("block", "block"), ("drivers/", "other drivers"),
]
ARTIFACT = re.compile(r"^(__x86_|__fentry__|__stack_chk|__ubsan|__sanitizer|__kcfi|__cfi|__asan|__tsan|__kasan|"
                      r"__sancov|__gcov|_GLOBAL_OFFSET|__fortify|__sw_hweight|__ref_stack)")


def run(args):
    return subprocess.run(args, capture_output=True, text=True).stdout


def nm_undefined(path):
    return {line.split()[-1] for line in run(["nm", "-u", path]).splitlines() if line.strip().startswith("U ")}


def nm_defined(path):
    out = set()
    for line in run(["nm", "--defined-only", path]).splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[1] in "TDRBWVC":
            out.add(parts[2])
    return out


def firmware_count(path):
    return len(set(re.findall(r"^firmware=(\S+)", run(["strings", "-a", path]), re.M)))


def export_map(src, wanted):
    pat = re.compile(r"EXPORT_SYMBOL(?:_GPL|_NS|_NS_GPL)?\(\s*([A-Za-z0-9_]+)")
    found = {}
    for top in ("lib", "kernel", "mm", "drivers", "arch/x86", "fs", "net", "block", "security", "crypto"):
        for root, _dirs, files in os.walk(os.path.join(src, top)):
            for name in files:
                if not name.endswith((".c", ".S")):
                    continue
                path = os.path.join(root, name)
                try:
                    with open(path, "r", errors="replace") as fh:
                        text = fh.read()
                except OSError:
                    continue
                for sym in pat.findall(text):
                    if sym in wanted and sym not in found:
                        found[sym] = os.path.relpath(path, src)
    return found


def group_of(path):
    if path is None:
        return "unmapped (macro/alias/builtin)"
    for prefix, name in GROUP_RULES:
        if path.startswith(prefix):
            return name
    return "other"


def license_info(src, rel):
    base = os.path.join(src, rel)
    paths = []
    if os.path.isfile(base):
        paths = [base]
    elif os.path.isdir(base):
        for root, _dirs, files in os.walk(base):
            paths += [os.path.join(root, f) for f in files if f.endswith((".c", ".h"))]
    counts = {}
    lines = 0
    for path in paths:
        with open(path, "r", errors="replace") as fh:
            text = fh.read()
        lines += text.count("\n")
        m = re.search(r"SPDX-License-Identifier:\s*([^\n*]+)", text[:600])
        if m:
            tag = m.group(1).strip()
        elif "Permission is hereby granted" in text[:3000]:
            tag = "MIT-text"
        elif "GNU General Public License" in text[:3000]:
            tag = "GPL-text"
        else:
            tag = "unknown"
        counts[tag] = counts.get(tag, 0) + 1
    return {"files": len(paths), "lines": lines, "spdx": dict(sorted(counts.items(), key=lambda kv: -kv[1])[:5])}


def main():
    ko_dir, src, out_json = sys.argv[1], sys.argv[2], sys.argv[3]
    ko = lambda n: os.path.join(ko_dir, n + ".ko")
    undef = {n: nm_undefined(ko(n)) for n in DRIVERS + SUPPORT if os.path.exists(ko(n))}
    defined = {n: nm_defined(ko(n)) for n in undef}
    support_defined = set().union(*[defined[n] for n in SUPPORT if n in defined])
    support_undef = set().union(*[undef[n] for n in SUPPORT if n in undef])
    surfaces = {d: (undef[d] | support_undef) - defined[d] - support_defined for d in DRIVERS}
    everything = set().union(*surfaces.values())
    mapping = export_map(src, {s for s in everything if not ARTIFACT.match(s)})
    result = {"support_modules": len([n for n in SUPPORT if n in undef])}
    for d in DRIVERS:
        closed = surfaces[d]
        api = {s for s in closed if not ARTIFACT.match(s)}
        groups = {}
        for sym in api:
            groups.setdefault(group_of(mapping.get(sym)), []).append(sym)
        result[d] = {
            "direct_undefined": len(undef[d]), "direct_from_drm_stack": len({s for s in undef[d] if s in support_defined}),
            "closed_surface": len(closed), "artifacts": len(closed) - len(api), "core_api": len(api),
            "groups": {g: len(v) for g, v in sorted(groups.items(), key=lambda kv: -len(kv[1]))},
            "examples": {g: sorted(v)[:5] for g, v in groups.items()},
            "firmware_files": firmware_count(ko(d)), "ko_bytes": os.path.getsize(ko(d)),
        }
    union_api = {s for s in everything if not ARTIFACT.match(s)}
    big = [surfaces[d] for d in DRIVERS if d != "bochs"]
    result["union_core_api"] = len(union_api)
    result["intersection_big4"] = len({s for s in set.intersection(*big) if not ARTIFACT.match(s)})
    result["bochs_direct_undefined_names"] = sorted(undef["bochs"])
    g = "drivers/gpu/drm/"
    rels = (g + "i915", g + "xe", g + "amd/amdgpu", g + "amd/display", g + "nouveau", g + "ttm", g + "scheduler",
            g + "display", g + "tiny/bochs.c", "drivers/dma-buf", "lib/idr.c", "lib/xarray.c",
            "kernel/workqueue.c", "include/drm")
    result["licenses"] = {rel: license_info(src, rel) for rel in rels}
    core = {"files": 0, "lines": 0, "spdx": {}}
    for name in sorted(os.listdir(os.path.join(src, g))):
        if name.endswith((".c", ".h")):
            info = license_info(src, g + name)
            core["files"] += 1
            core["lines"] += info["lines"]
            for k, v in info["spdx"].items():
                core["spdx"][k] = core["spdx"].get(k, 0) + v
    result["licenses"]["drm core (drivers/gpu/drm/*.c|h)"] = core
    with open(out_json, "w") as fh:
        json.dump(result, fh, indent=1, sort_keys=True)


main()
