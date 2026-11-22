import glob
import os
import re
import subprocess
import sys
import tempfile

RUNTIME_OWNER = "kernel/user/appreg.fi"
FORBIDDEN_RUNTIME = re.compile(r"\.osp/symbol|symbol64\.osym|symbol44\.osym|symbol\.osym|appglyph")
ICON_USE = re.compile(r"icons\.[A-Z][A-Z_]+|icon_id\(")
NOT_PROGRAMS = {"run", "top", "zip", "edit", "trash"}
WINDOW = 2
SITE_ROOT = "/root/projects/osum-site"
SITE_ICON_DIR = "src/assets/icons"
SITE_TEXT_DIRS = ("src/partials", "src/bench")
SITE_TEXT_FILES = ("src/index.template.html",)
SITE_ICON_REF = re.compile(r"\{\{icon:([a-z0-9-]+)\}\}")
SITE_INLINE_SVG = re.compile(r"<svg\b")


def read_rows(path):
    for line in open(path, encoding="utf-8").read().splitlines():
        if line.strip() and not line.startswith("#"):
            yield line.split("\t")


def manifest(root):
    return [(row[0], row[1], row[5]) for row in read_rows(os.path.join(root, "tools/svg/apps.tsv"))]


def source_of(root, spec):
    kind, name = spec[0], spec[1:]
    folder = "assets/icons/app" if kind == "=" else "assets/icons/brand"
    return os.path.join(root, folder, name + ".svg")


def source_files(root):
    for pattern in ("kernel/**/*.fi", "lib/**/*.fi"):
        for path in glob.glob(os.path.join(root, pattern), recursive=True):
            yield path, os.path.relpath(path, root)


def program_ids(root):
    ids = {row[0] for row in manifest(root)}
    ids |= {os.path.basename(p)[:-4] for p in glob.glob(os.path.join(root, "assets/apps/*.osp"))}
    return sorted(ids - NOT_PROGRAMS)


def runtime_paths(root):
    bad = []
    for path, rel in source_files(root):
        if rel == RUNTIME_OWNER:
            continue
        code = [ln for ln in open(path, errors="replace").read().splitlines() if not ln.lstrip().startswith("//")]
        if any(FORBIDDEN_RUNTIME.search(ln) for ln in code):
            bad.append(rel)
    return bad


def hardcoded_tables(root):
    names = program_ids(root)
    bad = []
    for path, rel in source_files(root):
        lines = open(path, errors="replace").read().splitlines()
        for i, line in enumerate(lines):
            if not ICON_USE.search(line):
                continue
            window = "\n".join(lines[max(0, i - WINDOW):i + WINDOW + 1])
            hit = next((n for n in names if re.search(r'"%s\\0"' % re.escape(n), window)), None)
            if hit:
                bad.append("%s:%d %s" % (rel, i + 1, hit))
                break
    return bad


def divergent_copies(root):
    bad = []
    for app, spec, folder in manifest(root):
        source = source_of(root, spec)
        if not os.path.isfile(source):
            bad.append("%s: no central source %s" % (app, os.path.relpath(source, root)))
            continue
        copy = os.path.join(root, folder, "symbol.svg")
        if not os.path.isfile(copy) or open(copy, "rb").read() != open(source, "rb").read():
            bad.append("%s: %s differs from the central source" % (app, os.path.relpath(copy, root)))
    return bad


def registry_gaps(root):
    sys.path.insert(0, os.path.join(root, "tools/appreg"))
    import build
    covered = {}
    for app, _kind, folder, _title in build.entries(root):
        covered[app] = folder
    bad = ["%s: no registry entry" % n for n in program_ids(root) if n not in covered]
    bad += ["%s: registry source has no symbol.osym" % a for a, d in covered.items() if d is None or not os.path.isfile(os.path.join(d, "symbol.osym"))]
    with tempfile.TemporaryDirectory() as out:
        rc = subprocess.run([sys.executable, "-I", os.path.join(root, "tools/appreg/build.py"), root, out], capture_output=True).returncode
        if rc != 0:
            bad.append("registry build failed rc=%d" % rc)
        for app in covered:
            path = os.path.join(out, "usr/share/appreg", app, "symbol")
            if not os.path.isfile(path) or os.path.getsize(path) != 44900:
                bad.append("%s: baked registry symbol missing or wrong size" % app)
    return bad


def site_texts(site):
    for rel in SITE_TEXT_FILES:
        yield rel
    for folder in SITE_TEXT_DIRS:
        for path in sorted(glob.glob(os.path.join(site, folder, "**/*.html"), recursive=True)):
            yield os.path.relpath(path, site)


def homepage_copies(root):
    site = os.environ.get("ICONREG_SITE", SITE_ROOT)
    if not os.path.isdir(site):
        return []
    bad = ["%s: icon file outside the registry" % os.path.relpath(p, site)
           for p in sorted(glob.glob(os.path.join(site, SITE_ICON_DIR, "*")))]
    ids = {row[0] for row in manifest(root)}
    for rel in site_texts(site):
        text = open(os.path.join(site, rel), encoding="utf-8").read()
        bad += ["%s: icon id %s is not in the registry" % (rel, i) for i in sorted(set(SITE_ICON_REF.findall(text))) if i not in ids]
        if SITE_INLINE_SVG.search(text):
            bad.append("%s: inline svg" % rel)
    return bad


CHECKS = (
    ("runtime reads icons only through appreg", runtime_paths),
    ("no per-program icon table in code", hardcoded_tables),
    ("every program has one central source, copies identical", divergent_copies),
    ("every program resolves in the registry", registry_gaps),
    ("homepage takes icons only from the registry", homepage_copies),
)


def main(argv):
    root = argv[0]
    total = 0
    for title, check in CHECKS:
        bad = check(root)
        total += len(bad)
        print("%s  %s" % ("OK  " if not bad else "FAIL", title))
        for line in bad[:12]:
            print("      " + line)
    print("icons outside registry: %d" % total)
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
