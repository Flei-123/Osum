import os
import sys


def rows(path, sep):
    out = []
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if line and not line.startswith("#"):
            out.append(line.split(sep))
    return out


def base_programs(root):
    owners = {}
    apps = os.path.join(root, "assets/apps")
    for bundle in sorted(os.listdir(apps)):
        start = os.path.join(apps, bundle, "start.txt")
        if not bundle.endswith(".osp") or not os.path.isfile(start):
            continue
        for line in open(start, encoding="utf-8"):
            if line.startswith("/bin/"):
                owners.setdefault(line.strip()[5:], []).append(bundle[:-4])
    return owners


def dev_programs(root):
    path = os.path.join(root, "tools/usbimg/devparts.conf")
    return {l.split()[1] for l in open(path, encoding="utf-8") if l.startswith("prog ")}


def package_problems(root, tab):
    owners = base_programs(root)
    dev = dev_programs(root)
    seen = set()
    for row in rows(tab, "|"):
        name, program = row[0], row[1]
        if name in seen:
            yield "duplicate package name %s" % name
        seen.add(name)
        twins = [b for b in owners.get(program, []) if b != name]
        if twins and name not in owners.get(program, []):
            yield "package %s runs /bin/%s which base bundle %s already ships" % (name, program, twins[0])
        if program in dev or name in dev:
            yield "package %s is a dev profile program" % name
    return


NOT_STORE_APPS = {"nedit": "internal twin of the editor"}


def catalog_problems(root, tab, view):
    console = {r[0] for r in rows(tab, "|") if len(r) > 6 and r[6] == "konsole"}
    for row in rows(view, "\t"):
        if row[0] != "A":
            continue
        short = row[1].rsplit(".", 1)[-1]
        if short in console:
            yield "catalog shows console tool %s in the app grid" % short
        if short in NOT_STORE_APPS:
            yield "catalog shows %s (%s) in the app grid" % (short, NOT_STORE_APPS[short])


def feed_problems(tab, feed):
    packages = {r[0] for r in rows(tab, "|")}
    index = [r[0] for r in rows(os.path.join(feed, "INDEX"), "\t")]
    for name in index:
        if name not in packages:
            yield "feed package %s is not in apps.tab" % name
    view = os.path.join(feed, "apps.tsv")
    titles = {}
    if os.path.isfile(view):
        for row in rows(view, "\t"):
            if row[0] == "A":
                key = row[3].strip().lower()
                if key in titles:
                    yield "catalog shows %s and %s under the same name %s" % (titles[key], row[1], row[3])
                titles[key] = row[1]


def main(argv):
    root, tab = argv[0], argv[1]
    feed = argv[2] if len(argv) > 2 else ""
    problems = list(package_problems(root, tab))
    if feed:
        problems += list(feed_problems(tab, feed))
        view = os.path.join(feed, "apps.tsv")
        if os.path.isfile(view):
            problems += list(catalog_problems(root, tab, view))
    for p in problems:
        print("PROBLEM " + p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
