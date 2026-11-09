#!/usr/bin/env python3
import re, sys, os

ROOT = sys.argv[1] if len(sys.argv) > 1 else "/root/osum-probe7"
RULES = {
    "kernel/sched/proc.fi":       ["head"],
    "kernel/sys/sys.fi":        ["union", "both", "bothclose"],
    "lib/libc/kcall.fi":    ["union", "both"],
    "kernel/user/fuiapp/wlib.fi":  ["union", "both", "keysdel", "both", "both", "both"],
    "tools/loader/apps.tab": ["both"],
    "tools/loader/build.sh": ["buildsh"],
}
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")

def idents(lines):
    out = []
    for l in lines:
        s = l.split("//")[0]
        for m in IDENT.finditer(s):
            out.append(m.group(0))
    return out

def resolve(path, rules):
    src = open(os.path.join(ROOT, path), encoding="utf-8").read().split("\n")
    out, i, k = [], 0, 0
    while i < len(src):
        if src[i].startswith("<<<<<<< "):
            j = i + 1; head = []
            while not src[j].startswith("======="):
                head.append(src[j]); j += 1
            j += 1; other = []
            while not src[j].startswith(">>>>>>> "):
                other.append(src[j]); j += 1
            rule = rules[k]; k += 1
            if rule == "head":
                out += head
            elif rule == "both":
                out += head + other
            elif rule == "bothclose":
                out += head + ["    }"] + other
            elif rule == "union":
                have = set(idents(head))
                new = [x for x in idents(other) if x not in have]
                out += head
                if new:
                    out.append("    " + ", ".join(new) + ",")
            elif rule == "keysdel":
                out += ["    KEY_SDEL,"] + head
            elif rule == "buildsh":
                for l in head:
                    if l.startswith("GUI="):
                        l = l[:-2] + ' rechner trashbin viewer snip lock"}'
                    elif l.startswith("CLI="):
                        l = l[:-2] + ' zip"}'
                    out.append(l)
            else:
                raise SystemExit("unbekannte Regel " + rule)
            i = j + 1
            continue
        out.append(src[i]); i += 1
    if k != len(rules):
        raise SystemExit(f"{path}: {k} Konflikte, {len(rules)} Regeln")
    text = "\n".join(out)
    if path in ("kernel/sys/sys.fi", "lib/libc/kcall.fi"):
        text = text.replace("const SYS_OSUM_SPERRE: u64 = 1850", "const SYS_OSUM_SPERRE: u64 = 1870")
        text = text.replace("//   1850  osum_sperre", "//   1870  osum_sperre")
        text = text.replace("SYS_OSUM_SPERRE: kernel 1850", "SYS_OSUM_SPERRE: kernel 1870")
        text = text.replace("RUNDE ALLTAG: 1850, DIE SPERRE", "RUNDE ALLTAG: 1870, DIE SPERRE (1850 gehoert seit Runde TON dem AUDGET)")
    if path == "kernel/user/fuiapp/wlib.fi":
        text = text.replace("const K_BILD: u64 = 15", "const K_BILD: u64 = 16")
        text = text.replace("const K_SLIDER: u64 = 16", "const K_SLIDER: u64 = 17")
    open(os.path.join(ROOT, path), "w", encoding="utf-8").write(text)
    print(f"{path}: {k} Konflikte aufgeloest ({', '.join(rules)})")

for p, r in RULES.items():
    resolve(p, r)
lp = os.path.join(ROOT, "kernel/user/lock.fi")
t = open(lp, encoding="utf-8").read()
n = t.count("const SYS_SPERRE: u64 = 1850")
open(lp, "w", encoding="utf-8").write(t.replace("const SYS_SPERRE: u64 = 1850", "const SYS_SPERRE: u64 = 1870"))
print(f"kernel/user/lock.fi: {n} Nummer(n) 1850 -> 1870")
