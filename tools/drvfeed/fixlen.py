#!/usr/bin/env python3
import re
import sys

PATTERN = re.compile(r'\[u8; (\d+)\] = "((?:[^"\\]|\\.)*)"')


def logical_length(text):
    return len(re.sub(r"\\.", "x", text))


for path in sys.argv[1:]:
    source = open(path).read()
    fixed = PATTERN.sub(lambda m: "[u8; %d] = \"%s\"" % (logical_length(m.group(2)), m.group(2)), source)
    if fixed != source:
        open(path, "w").write(fixed)
