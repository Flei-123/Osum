import os

DB = "lib/apk/db/installed"
BASE_PACKAGES = ("musl", "busybox", "alpine-baselayout", "alpine-baselayout-data", "alpine-keys", "apk-tools", "scanelf", "ssl_client", "libc-utils", "musl-utils", "musl-fts", "libcrypto3", "libssl3", "zlib")


def parse(root):
    packages = {}
    current = None
    directory = ""
    with open(os.path.join(root, DB), encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line:
                current = None
                continue
            tag, value = line[0], line[2:]
            if tag == "P":
                current = {"name": value, "deps": [], "provides": [], "files": [], "version": ""}
                packages[value] = current
                directory = ""
            elif current is None:
                continue
            elif tag == "V":
                current["version"] = value
            elif tag == "D":
                current["deps"] = value.split()
            elif tag == "p":
                current["provides"] = value.split()
            elif tag == "F":
                directory = value
            elif tag == "R":
                current["files"].append(os.path.join(directory, value))
    return packages


def provider_map(packages):
    mapping = {}
    for name, package in packages.items():
        mapping[name] = name
        for item in package["provides"]:
            mapping.setdefault(item.split("=")[0], name)
    return mapping


def closure(packages, roots):
    providers = provider_map(packages)
    seen = []
    pending = list(roots)
    while pending:
        name = pending.pop()
        if name in seen or name not in packages:
            continue
        seen.append(name)
        for dep in packages[name]["deps"]:
            if dep.startswith("!"):
                continue
            target = providers.get(dep.split("=")[0].split(">")[0].split("<")[0].split("~")[0])
            if target:
                pending.append(target)
    return seen
