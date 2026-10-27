#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

BAD_RE = re.compile(r"pixelguard: BAD level=([AB]) px=(\d+) bbox=(\d+),(\d+),(\d+),(\d+)")
STAT_RE = re.compile(
    r"pixelguard: stat checks=(\d+) bad=(\d+) unstable=(\d+) pending=(\d+) skipped=(\d+) card_bad=(\d+) renders=(\d+) us=(\d+)"
)
SET_RE = re.compile(r"pixelguard: set mode=(\d+)")
PANIC_RE = re.compile(r"ABSTURZ|EXCEPTION|panic|KERNSTAPEL UEBERGELAUFEN")

results = []


def check(ok, text):
    results.append(ok)
    print("  %s  %s" % ("OK  " if ok else "FAIL", text))


def read(path):
    with open(path, "rb") as f:
        return f.read().decode("latin1")


def bads(text):
    return [(m.group(1), int(m.group(2)), tuple(int(m.group(i)) for i in range(3, 7))) for m in BAD_RE.finditer(text)]


def last_stat(text):
    found = STAT_RE.findall(text)
    if not found:
        return None
    keys = ("checks", "bad", "unstable", "pending", "skipped", "card_bad", "renders", "us")
    return dict(zip(keys, (int(v) for v in found[-1])))


def judge_clean(path, min_checks, max_us):
    text = read(path)
    st = last_stat(text)
    check(st is not None, "stat line present")
    if st is None:
        return
    print("  INFO  %s" % st)
    check(st["checks"] >= min_checks, "checks %d >= %d" % (st["checks"], min_checks))
    found = bads(text)
    check(not found and st["bad"] == 0, "no BAD (lines=%d, stat bad=%d) %s" % (len(found), st["bad"], found[:3]))
    check(st["card_bad"] == 0, "card level clean (card_bad=%d)" % st["card_bad"])
    check(st["skipped"] * 4 <= st["checks"] + 4, "few skipped checks (%d of %d)" % (st["skipped"], st["checks"]))
    check(st["us"] <= max_us, "last check %d us <= %d" % (st["us"], max_us))
    check(not PANIC_RE.search(text), "no crash lines")


def judge_probe(path, number):
    text = read(path)
    found = bads(text)
    want_level = "B" if number == 4 else "A"
    check(len(found) > 0, "probe %d detected (%d BAD lines)" % (number, len(found)))
    if found:
        check(found[0][0] == want_level, "probe %d level %s (got %s)" % (number, want_level, found[0][0]))
        check(found[0][1] > 0, "probe %d px=%d bbox=%s" % (number, found[0][1], found[0][2]))
    check("pixelguard: frozen" in text, "probe %d froze the compositor" % number)
    check(not PANIC_RE.search(text), "probe %d no crash lines" % number)


def judge_switch(path):
    text = read(path)
    modes = [int(m.group(1)) for m in SET_RE.finditer(text)]
    print("  INFO  set modes %s" % modes)
    check(modes[:3] == [1, 0, 1], "switch on, off, on -> modes 1, 0, 1")
    check("pixelguard: on mode=" not in text, "boot without the pixelguard word stays off")
    st = last_stat(text)
    check(st is not None and st["checks"] > 0, "checks ran after the switch went on (%s)" % (st and st["checks"]))
    check(not PANIC_RE.search(text), "no crash lines")


def judge_counter(path):
    text = read(path)
    check("pixelguard:" not in text, "default boot prints no pixelguard line")
    check(not PANIC_RE.search(text), "no crash lines")


def main():
    mode = sys.argv[1]
    if mode == "clean":
        judge_clean(sys.argv[2], int(sys.argv[3]), int(sys.argv[4]))
    elif mode == "probe":
        judge_probe(sys.argv[3], int(sys.argv[2]))
    elif mode == "switch":
        judge_switch(sys.argv[2])
    elif mode == "counter":
        judge_counter(sys.argv[2])
    else:
        sys.exit(2)
    sys.exit(0 if all(results) else 1)


main()
