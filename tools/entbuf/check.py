import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
SKIP = ("vendor", ".git", "tools")
CALL = re.compile(r"\bfs\.(entry_at|entry_slot)\(")


def read(path):
    with open(path, "rb") as handle:
        return handle.read().decode("latin-1")


def source_files():
    for base, dirs, names in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP]
        for name in names:
            if name.endswith(".fi"):
                yield os.path.join(base, name)


def consts(text):
    found = {}
    for match in re.finditer(r"^const (\w+): u64 = (0x[0-9A-Fa-f]+|\d+)", text, re.M):
        found[match.group(1)] = int(match.group(2), 0)
    return found


def split_args(text, start):
    depth = 1
    args = []
    cur = ""
    for ch in text[start:]:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
            if depth == 0:
                args.append(cur.strip())
                return args
        if ch == "," and depth == 1:
            args.append(cur.strip())
            cur = ""
        else:
            cur += ch
    return args


def evaluate(expr, scope):
    expr = re.sub(r"\b(?:fs|kstate)\.(\w+)", r"\1", expr)
    for key in sorted(scope, key=len, reverse=True):
        expr = re.sub(r"\b%s\b" % key, str(scope[key]), expr)
    if not re.fullmatch(r"[0-9xXa-fA-F+\-* ()]+", expr):
        return None
    return eval(expr)


def resolve_var(text, pos, name):
    best = None
    for match in re.finditer(r"\b(?:let|var) %s: u64 = ([^\n]+)" % re.escape(name), text[:pos]):
        best = match.group(1).strip()
    return best


def k14_windows(scope, files):
    windows = []
    mnt = scope["MNT_OFF"]
    windows.append(("mnt", mnt, mnt + scope["MAX_MNT"] * scope["MNT_BYTES"]))
    windows.append(("part", scope["PART_OFF"], scope["PART_OFF"] + scope["MAX_PARTS"] * scope["PART_BYTES"]))
    windows.append(("devfs", 0x740, 0x980))
    windows.append(("sect", scope["SECT_OFF"], scope["SECT_OFF"] + 512))
    return windows


def main():
    ok = 0
    bad = 0

    def good(msg):
        nonlocal ok
        ok += 1
        print("  OK    " + msg)

    def fail(msg):
        nonlocal bad
        bad += 1
        print("  FAIL  " + msg)

    paths = list(source_files())
    texts = {p: read(p) for p in paths}
    fs_text = texts[os.path.join(ROOT, "kernel/fs/fs.fi")]
    fs_consts = consts(fs_text)
    ks_consts = consts(texts[os.path.join(ROOT, "kernel/lib/kstate.fi")])
    scope = {}
    for rel in ("kernel/fs/mnt.fi", "kernel/block/part.fi", "kernel/fs/fs.fi"):
        scope.update(consts(texts[os.path.join(ROOT, rel)]))
    scope.update(ks_consts)
    scope["MAX_MNT"] = 8
    entry_max = fs_consts.get("ENTRY_MAX", 0)
    if entry_max >= fs_consts.get("DIRENT_V3", 1) and entry_max >= fs_consts.get("NAME_V3", 0) + 8:
        good("fs.ENTRY_MAX %d covers the largest entry" % entry_max)
    else:
        fail("fs.ENTRY_MAX %d is smaller than DIRENT_V3 %s" % (entry_max, fs_consts.get("DIRENT_V3")))
    for sig in ("fn entry_at(state: u64, dir: u64, index: u64, out: u64, cap: u64)",
                "fn entry_slot(state: u64, dir: u64, slot: u64, out: u64, cap: u64)"):
        if sig in fs_text:
            good("signature carries cap: " + sig.split("(")[0])
        else:
            fail("signature lacks cap: " + sig.split("(")[0])
    guards = len(re.findall(r"if dirent_size\(state\) > cap \{\s*return 0", fs_text))
    if guards >= 2:
        good("entry_at and entry_slot refuse a too small cap")
    else:
        fail("cap guard missing in fs.fi (%d of 2)" % guards)
    if re.search(r"dent > ENTRY_MAX && dent <= BS \{[^}]*return false", fs_text) and "dent > ENTRY_MAX ||" in fs_text:
        good("mount refuses a directory entry size above ENTRY_MAX")
    else:
        fail("mount does not bound the directory entry size by ENTRY_MAX")
    windows = k14_windows(scope, paths)
    sites = 0
    for path in paths:
        text = texts[path]
        local = dict(scope)
        local.update(consts(text))
        for match in CALL.finditer(text):
            sites += 1
            line = text.count("\n", 0, match.start()) + 1
            where = "%s:%d" % (os.path.relpath(path, ROOT), line)
            args = split_args(text, match.end())
            if len(args) != 5:
                fail("%s %s has %d args, expected 5" % (where, match.group(1), len(args)))
                continue
            cap = evaluate(args[4], local)
            if cap is None or cap < entry_max:
                fail("%s cap '%s' = %s < ENTRY_MAX %d" % (where, args[4], cap, entry_max))
                continue
            out = args[3]
            sized = re.fullmatch(r"\(&(\w+)\[0\]\) as u64", out)
            if sized:
                decl = re.search(r"static mut %s: \[u8; (\d+)\]" % sized.group(1), text)
                if decl and int(decl.group(1)) >= cap:
                    good("%s static %s %s >= cap %d" % (where, sized.group(1), decl.group(1), cap))
                else:
                    fail("%s static %s too small for cap %d" % (where, sized.group(1), cap))
                continue
            expr = out
            if re.fullmatch(r"\w+", out):
                expr = resolve_var(text, match.start(), out) or out
            lowered = re.search(r"kstate\.K14_OFF \+ (.+)$", expr)
            name_off = re.search(r"kstate\.NAME_OFF \+ (.+)$", expr)
            page = re.search(r"nameb\(state\) \+ (.+)$", expr)
            if lowered:
                off = evaluate(lowered.group(1), local)
                end = None if off is None else off + cap
                clash = [w[0] for w in windows if off is not None and off < w[2] and end > w[1]]
                if off is None or clash or end > ks_consts["K14_MAX"]:
                    fail("%s K14 scratch +%s..%s overlaps %s" % (where, off, end, clash or "end of page"))
                else:
                    good("%s K14 scratch 0x%X..0x%X free" % (where, off, end))
            elif name_off:
                off = evaluate(name_off.group(1), local)
                if off is not None and off + cap <= ks_consts["NAME_MAX"]:
                    good("%s name page +%d..%d inside page" % (where, off, off + cap))
                else:
                    fail("%s name page +%s + cap %d leaves the page" % (where, off, cap))
            elif page:
                off = evaluate(page.group(1), local)
                marks = sorted(set([1024, 2048, local.get("NB_ENT", 0), local.get("NB_FSTYPE", 0), 4096]))
                nxt = min([m for m in marks if off is not None and m > off] or [0])
                if off is not None and off + cap <= nxt:
                    good("%s per-cpu name page +%d..%d before +%d" % (where, off, off + cap, nxt))
                else:
                    fail("%s per-cpu name page +%s + cap %d reaches +%s" % (where, off, cap, nxt))
            else:
                fail("%s unknown out buffer '%s'" % (where, out))
    if sites < 6:
        fail("only %d call sites found, expected at least 6" % sites)
    else:
        good("%d call sites checked" % sites)
    print("ENTBUF: %d passed, %d failed" % (ok, bad))
    return 0 if bad == 0 else 1


sys.exit(main())
