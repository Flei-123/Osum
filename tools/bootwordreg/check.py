#!/usr/bin/env python3
import re
import sys
from pathlib import Path

ROOT = Path(".").resolve()
MODES = ROOT / "kernel/lib/modes"
FIND_CALL = re.compile(r"cmdword\.find\w*\(\w+, \(&(\w+)\[0\]\) as u64")
STRING_VAR = re.compile(r'var (\w+): \[u8; \d+\] = "([^"]*)"')
BIT_CONST = re.compile(r"^const (M_\w+): u64 = (\d+)", re.M)
ALIAS_CONST = re.compile(r"^const (M_\w+): u64 = (\w+)\.(M_\w+)", re.M)


def decode(blob):
    return [part for part in blob.replace("\\0", "\0").split("\0")[:-1]]


def read_group(path):
    text = path.read_text()
    group = {"file": path, "bits": dict(BIT_CONST.findall(text))}
    group["count"] = int(re.search(r"^const COUNT: u64 = (\d+)", text, re.M).group(1))
    for key in ("names", "docs"):
        match = re.search(r'^static mut %s: \[u8; (\d+)\] = "([^"]*)"' % key, text, re.M)
        blob = match.group(2).replace("\\0", "\0")
        group[key + "_size"] = int(match.group(1))
        group[key] = decode(match.group(2))
        group[key + "_blob_len"] = len(blob)
    for key in ("bits", "meta"):
        match = re.search(r"^static mut %s: \[u64; (\d+)\] = \[(.*)\]" % key, text, re.M)
        group[key + "_size"] = int(match.group(1))
        group[key + "_list"] = [item.strip() for item in match.group(2).split(",")]
    return group


def check_group(group, problems):
    name = group["file"].name
    count = group["count"]
    for key in ("names", "docs"):
        if len(group[key]) != count:
            problems.append("%s: %d %s for COUNT %d" % (name, len(group[key]), key, count))
        if group[key + "_size"] != group[key + "_blob_len"]:
            problems.append("%s: %s declared %d bytes, blob has %d" % (name, key, group[key + "_size"], group[key + "_blob_len"]))
    for key in ("bits", "meta"):
        if group[key + "_size"] != count or len(group[key + "_list"]) != count:
            problems.append("%s: %s has %d entries for COUNT %d" % (name, key, len(group[key + "_list"]), count))
    for item in group["bits_list"]:
        if item not in group["bits"]:
            problems.append("%s: bits entry %s has no constant" % (name, item))
    for word in group["names"]:
        if not re.fullmatch(r"[a-z0-9=]+", word):
            problems.append("%s: bad word name %r" % (name, word))


def handwritten_words():
    words = {}
    for path in sorted((ROOT / "kernel").rglob("*.fi")):
        if "lib/modes" in str(path):
            continue
        text = path.read_bytes().decode("latin-1")
        used = set(FIND_CALL.findall(text))
        for var, literal in STRING_VAR.findall(text):
            if var in used:
                words.setdefault(re.sub(r"(\\0)+$", "", literal), str(path.relative_to(ROOT)))
    return words


def check_unique_bits(groups, problems):
    seen = {}
    kstate = (ROOT / "kernel/lib/kstate.fi").read_text()
    sources = [("kstate", dict(BIT_CONST.findall(kstate)))]
    sources += [(g["file"].name, g["bits"]) for g in groups]
    for owner, bits in sources:
        for const, value in bits.items():
            if value in seen and seen[value][1] != const:
                problems.append("bit %s used by %s (%s) and %s (%s)" % (value, seen[value][1], seen[value][0], const, owner))
            seen[value] = (owner, const)
    return seen


def check_registry(groups, problems):
    text = (ROOT / "kernel/init/bootwords.fi").read_text()
    for group in groups:
        module = group["file"].stem
        for needle in ("import lib.modes.%s" % module, "bootword.parse(state, cmd, (&%s.names[0])" % module, "bootword.render(state, (&%s.names[0])" % module):
            if needle not in text:
                problems.append("init/bootwords.fi: missing '%s'" % needle)


def check_no_duplicates(groups, handwritten, problems):
    registered = {}
    for group in groups:
        for word in group["names"]:
            if word in registered:
                problems.append("word %s registered twice (%s, %s)" % (word, registered[word], group["file"].name))
            registered[word] = group["file"].name
            if word in handwritten:
                problems.append("word %s is registered and still handwritten in %s" % (word, handwritten[word]))
    return registered


def report_unknown(cmdline, known):
    unknown = [token for token in cmdline.split() if token not in known and token.split("=")[0] + "=" not in known]
    for token in unknown:
        print("UNKNOWN word: %s" % token)
    return unknown


def main():
    groups = [read_group(path) for path in sorted(MODES.glob("words_*.fi"))]
    problems = []
    for group in groups:
        check_group(group, problems)
    check_unique_bits(groups, problems)
    check_registry(groups, problems)
    handwritten = handwritten_words()
    registered = check_no_duplicates(groups, handwritten, problems)
    known = set(registered) | set(handwritten)
    if len(sys.argv) > 2 and sys.argv[1] == "--unknown":
        return 1 if report_unknown(sys.argv[2], known) else 0
    if len(sys.argv) > 1 and sys.argv[1] == "--words":
        print(" ".join(word for word in registered if "=" not in word))
        return 0
    for line in problems:
        print("FAIL", line)
    print("bootwords: groups=%d registered=%d handwritten=%d problems=%d" % (len(groups), len(registered), len(handwritten), len(problems)))
    return 1 if problems else 0


sys.exit(main())
