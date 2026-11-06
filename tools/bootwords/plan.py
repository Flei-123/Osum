#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

FIND_IF = re.compile(
    r"if cmdword\.(find|find_lead)\(cmd, \(&(\w+)\[0\]\) as u64, (\d+)\) != 0 \{\s*\n\s*kstate\.mode_add\(state, kstate\.(M_\w+)\)")
WORD_DECL = re.compile(r'var (\w+): \[u8; \d+\] = "([a-z0-9._=/-]+)\\0')
MODE_CONST = re.compile(r"^const (M_\w+): u64 = (\d+)", re.M)
SLEEPERS = ("s3",)
NAMED = [("usb", "usbpoll"), ("wm", "wmplug"), ("a11y", "a11ymag"), ("wig", "wigfiles"), ("aml", "noaml")]


def read(path):
    return open(path, "rb").read().decode("latin1")


def mode_bits(root):
    return {n: int(v) for n, v in MODE_CONST.findall(read(os.path.join(root, "kernel/lib/kstate.fi")))}


def word_map(root):
    bits = mode_bits(root)
    words = {}
    for base, dirs, names in os.walk(os.path.join(root, "kernel")):
        dirs[:] = [d for d in dirs if d not in ("user", "app")]
        for name in names:
            if not name.endswith(".fi"):
                continue
            text = read(os.path.join(base, name))
            decl = dict(WORD_DECL.findall(text))
            for kind, var, length, const in FIND_IF.findall(text):
                word = decl.get(var)
                if word and const in bits and len(word) == int(length) and not word.startswith(SLEEPERS):
                    words.setdefault(word, (kind, bits[const]))
    return words


def plan(root, limit):
    words = word_map(root)
    chosen = []
    seen = set()

    def add(a, b):
        if a in words and b in words and (a, b) not in seen and words[a][1] != words[b][1]:
            seen.add((a, b))
            chosen.append((a, b))

    for a, b in NAMED:
        add(a, b)
    shorts = sorted((w for w in words if any(w != o and w in o for o in words)), key=lambda w: (len(w), w))
    for a in shorts:
        if len(chosen) >= limit:
            break
        longer = sorted((o for o in words if o != a and a in o), key=lambda o: (len(o), o))
        if longer and not any(p[0] == a for p in chosen):
            add(a, longer[0])
    for a, b in chosen:
        print("%s %s %d %d %s" % (a, b, words[a][1], words[b][1], words[a][0]))


def bits(path):
    line = ""
    for l in read(path).splitlines():
        if l.startswith("boot: modes "):
            line = l
    if not line:
        return 1
    out = []
    for w, tok in enumerate(line[len("boot: modes "):].split()):
        v = int(tok, 16)
        out += [w * 64 + i for i in range(64) if v >> i & 1]
    print(" ".join(str(b) for b in out))
    return 0


if __name__ == "__main__":
    if sys.argv[1] == "plan":
        plan(sys.argv[2], int(sys.argv[3]))
    elif sys.argv[1] == "bits":
        sys.exit(bits(sys.argv[2]))
