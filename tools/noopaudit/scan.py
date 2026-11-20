import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "kernel/user"
CREATORS = (
    "button", "button_main", "icon_button", "toggle", "button_danger", "link",
    "tile", "ftile_nb", "chip", "menu_item", "checkbox", "switch",
)
CALL = re.compile(r"fuiscene\.(?:%s)\((.*)$" % "|".join(CREATORS), re.M)
CONST = re.compile(r"^const\s+([A-Z][A-Z0-9_]*)\s*:", re.M)
USE = r"(?:==|!=|>=|<=|>|<)\s*(?:[a-z0-9_]+\.)?%s\b|\b%s\s*(?:==|!=|>=|<=)"
ALLOW_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "allow.txt")


def fui_files(root):
    for base, _dirs, names in os.walk(root):
        for name in names:
            if name.endswith(".fi"):
                yield os.path.join(base, name)


def created_keys(text):
    keys = set()
    for match in CALL.finditer(text):
        for token in re.findall(r"\b[A-Z][A-Z0-9_]{1,}\b", match.group(1)):
            keys.add(token)
    return keys


def handled(text, key):
    pattern = re.compile(USE % (key, key))
    uses = [m for m in pattern.finditer(text)]
    return len(uses) > 0


def load_allow():
    allowed = set()
    if not os.path.exists(ALLOW_FILE):
        return allowed
    for line in open(ALLOW_FILE, encoding="utf-8"):
        fields = line.split()
        if len(fields) >= 2 and not line.startswith("#"):
            allowed.add((fields[0], fields[1]))
    return allowed


def audit(root):
    missing = []
    allowed = load_allow()
    texts = {}
    for path in sorted(fui_files(root)):
        texts[path] = open(path, encoding="utf-8", errors="replace").read()
    everything = "\n".join(texts.values())
    for path, text in texts.items():
        consts = set(CONST.findall(text))
        relative = os.path.relpath(path, root)
        for key in sorted(created_keys(text) & consts):
            if not key.startswith(("K_", "KEY_")):
                continue
            if handled(text, key) or handled(everything, key):
                continue
            if (relative, key) in allowed:
                continue
            missing.append((path, key))
    return missing


def main():
    missing = audit(ROOT)
    for path, key in missing:
        print("NOOP %s %s" % (path, key))
    print("noop-audit: %d unhandled controls" % len(missing))
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
