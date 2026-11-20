import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "kernel/user"
TAB = sys.argv[2] if len(sys.argv) > 2 else "tools/loader/apps.tab"


def read(path):
    return open(path, encoding="utf-8", errors="replace").read()


def function_body(text, name):
    start = text.index("fn %s(" % name)
    nxt = text.find("\nfn ", start + 1)
    return text[start:nxt if nxt > 0 else len(text)]


def check(condition, label, failures):
    print("%s %s" % ("ok  " if condition else "FAIL", label))
    if not condition:
        failures.append(label)


def catalog_packages(tab):
    names = []
    for line in read(tab).splitlines():
        if line and not line.startswith("#"):
            names.append(line.split("|")[0])
    return names


def main():
    failures = []
    store = read(os.path.join(ROOT, "store.fi"))
    opener = function_body(store, "open_app")
    check('"/apps/' in store and 'P_START' in opener, "open_app builds /apps/<name>.osp/start", failures)
    check("P_BIN" not in store, "open_app no longer guesses /bin/<name>", failures)
    check("appreg.launch(" in opener, "open_app launches through appreg.launch", failures)
    check("notice(" in opener and "T_OPENFAIL" in opener, "open failure shows a message with the app title", failures)
    check(len(re.findall(r"open_app\(", store)) >= 3, "grid button and detail button both call open_app", failures)
    check("static mut T_OPENFAIL" in store, "open failure text is declared", failures)
    for lang in ("en", "de"):
        messages = read("locale/%s/messages" % lang)
        check(re.search(r"^store\.openfail = ", messages, re.M) is not None, "locale %s has store.openfail" % lang, failures)
    packages = catalog_packages(TAB)
    check(len(packages) > 0, "catalog packages found: %d" % len(packages), failures)
    loader = read("tools/loader/pakete.sh")
    check("/apps/$paket.osp" in loader, "packages install as /apps/<package>.osp", failures)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
