import hashlib
import os
import re
import collections

HEADER = re.compile(r"^(?:export\s+)?fn\s+([A-Za-z0-9_]+)\s*\(", re.M)
LINE_COMMENT = re.compile(r"//[^\n]*")
GIANT_LINES = 2000
ROOT_ALLOWED = {
    "README.md", "COPYING", "LICENSE", "LICENSE.MIT", "LICENSES", "LICENSING.md",
    "THIRD_PARTY.md", "marke.conf", "test.sh", "firn.toolchain", "RUN.md", "PLAN.md", "GAUNTLET.md",
}


def giants(root, files):
    out = []
    for path in files:
        with open(os.path.join(root, path), "rb") as handle:
            if handle.read().count(b"\n") > GIANT_LINES:
                out.append(path)
    return sorted(out)


def loose_root(root):
    out = []
    for name in sorted(os.listdir(root)):
        if name.startswith(".") or name in ROOT_ALLOWED:
            continue
        if os.path.isfile(os.path.join(root, name)):
            out.append(name)
    return out


def function_blocks(text):
    for match in HEADER.finditer(text):
        start = text.find("{", match.end())
        if start < 0:
            continue
        depth = 0
        pos = start
        while pos < len(text):
            if text[pos] == "{":
                depth += 1
            elif text[pos] == "}":
                depth -= 1
                if depth == 0:
                    break
            pos += 1
        body = re.sub(r"\s+", " ", text[match.start():pos + 1])
        if body.count(" ") >= 8:
            yield match.group(1), body


def duplicates(root, files):
    groups = collections.defaultdict(set)
    for path in files:
        with open(os.path.join(root, path), "rb") as handle:
            text = LINE_COMMENT.sub("", handle.read().decode("utf8", "replace"))
        for name, body in function_blocks(text):
            groups[(name, hashlib.md5(body.encode()).hexdigest()[:10])].add(path)
    return sorted(
        (f"{name}:{digest}", sorted(paths))
        for (name, digest), paths in groups.items()
        if len(paths) > 1
    )


def shared_in_app_dir(files, edges, prefix="kernel/user/"):
    users = collections.defaultdict(set)
    for src, targets in edges.items():
        for target in targets:
            users[target].add(src)
    out = []
    for path in files:
        parent = os.path.dirname(path) + "/"
        if parent == prefix and len(users.get(path, ())) >= 2:
            out.append(path)
    return sorted(out)
