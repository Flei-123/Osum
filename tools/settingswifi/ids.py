#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
SHIFT = int(sys.argv[2]) if len(sys.argv) > 2 else 0

EXPECTED_ID = {
    "wifi-pass": "K_WPW",
    "wifi-scan": "K_WSC",
    "wifi-connect": "K_WCO",
    "wifi-nets": "K_WNETS",
    "presets-file": "K_EVF",
    "presets-export": "K_BV3",
    "presets-import": "K_BV4",
    "presets-link": "K_BV5",
    "presets-restore": "K_BV6",
    "about-export": "K_IN_BEXP",
}
EXPECTED_BUF = {
    "wifi-status": "l_wstat",
    "wifi-pass": "e_wpw",
    "wifi-nets": "setwifi.blob()",
    "presets-file": "e_vfile",
    "presets-account": "l_vkonto",
    "about-status": "l_instat",
}
EXPECTED_COND = {
    "wifi-need": "setwifi.needs_password(",
    "wifi-adapter": "setwifi.has_adapter()",
}
BUTTON_NAMES = ("wifi-scan", "wifi-connect", "presets-export", "presets-import", "presets-link", "presets-restore", "about-export")


def read(path):
    with open("%s/%s" % (ROOT, path), encoding="utf-8", errors="surrogateescape") as handle:
        return handle.read()


def function_body(text, name):
    start = text.index("fn %s(" % name)
    end = text.find("\nfn ", start + 1)
    return text[start:end if end >= 0 else len(text)]


def table(body, pattern):
    return {int(m.group(1)): m.group(2) for m in re.finditer(pattern, body)}


def main():
    names = [line for line in read("kernel/user/settings.d/personal.bind").split("\n") if line]
    device = read("kernel/user/settings/setdevice.fi")
    system = read("kernel/user/settings/setsystem.fi")
    ids = table(function_body(device, "per_id"), r"if ix == (\d+) \{ return setbase\.(\w+) \}")
    bufs = {}
    for m in re.finditer(r"if ix == (\d+) \{ return (.+?) \}\n", function_body(device, "per_buf")):
        found = re.search(r"setbase\.(\w+)\[|setwifi\.blob\(\)", m.group(2))
        bufs[int(m.group(1))] = found.group(1) if found and found.group(1) else (found.group(0) if found else m.group(2))
    buttons = function_body(device, "per_bk")
    failures = []
    for label, expected in EXPECTED_ID.items():
        index = names.index(label) + SHIFT
        if ids.get(index) != expected:
            failures.append("per_id[%s=%d] is %s, expected %s" % (label, index, ids.get(index), expected))
    for label, expected in EXPECTED_BUF.items():
        index = names.index(label) + SHIFT
        if bufs.get(index) != expected:
            failures.append("per_buf[%s=%d] is %s, expected %s" % (label, index, bufs.get(index), expected))
    for label, expected in EXPECTED_COND.items():
        index = names.index(label) + SHIFT
        pattern = r"w == 3 && ix == %d \{\s*return %s" % (index, re.escape(expected))
        if not re.search(pattern, function_body(system, "man_cond")):
            failures.append("man_cond[%s=%d] does not call %s" % (label, index, expected))
    for label in BUTTON_NAMES:
        index = names.index(label) + SHIFT
        if not re.search(r"ix == %d\b[^\n]*\{ return [12] \}" % index, buttons):
            failures.append("per_bk[%s=%d] is not a button" % (label, index))
    for failure in failures:
        print("  " + failure)
    if failures:
        return 1
    print("wifi bindings line up with the adapter tables (%d names)" % len(names))
    return 0


sys.exit(main())
