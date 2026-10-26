# SPDX-License-Identifier: GPL-2.0-only
import dataclasses
import os

import caps2desc
import corpus_checks
import hidcaps
import layouts
import refparser
import reportfile

TP = "touchpad-045e-09af"
TS = "touchscreen-045e-0c32"
PEN = "pen-045e-0c32"


def read(path):
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def replace_caps(caps, predicate, **changes):
    return dataclasses.replace(caps, caps=tuple(dataclasses.replace(c, **changes) if predicate(c) else c for c in caps.caps))


def drop_caps(caps, predicate, **header):
    return dataclasses.replace(caps, caps=tuple(c for c in caps.caps if not predicate(c)), **header)


def swap_xy(caps):
    def flip(cap):
        if cap.link == 1 and cap.page == 1 and cap.usage in (0x30, 0x31):
            return dataclasses.replace(cap, usage=0x61 - cap.usage)
        return cap
    return dataclasses.replace(caps, caps=tuple(flip(c) for c in caps.caps))


def finger_x(link):
    return lambda c: c.page == 1 and c.usage == 0x30 and c.link == link


def device_controls():
    touchpad, touchscreen, pen = TP, TS, PEN
    return [
        ("wrong bit width (contact id 4 bits, finger 2)", touchpad,
         lambda c: replace_caps(c, lambda x: x.usage == 0x51 and x.link == 2, bits=4), None),
        ("wrong bit width (X 12 bits, finger 3)", touchpad,
         lambda c: replace_caps(c, finger_x(3), bits=12), None),
        ("missing field (Scan Time dropped from caps)", touchpad,
         lambda c: drop_caps(c, lambda x: x.usage == 0x56), None),
        ("missing field (Scan Time dropped, header counts adjusted)", touchpad,
         lambda c: drop_caps(c, lambda x: x.usage == 0x56, counts=dict(c.counts, inval=c.counts["inval"] - 1)), None),
        ("missing field (Tip Switch of finger 4 dropped)", touchpad,
         lambda c: drop_caps(c, lambda x: x.usage == 0x42 and x.link == 4), None),
        ("wrong input length (29 instead of 30)", touchpad, lambda c: dataclasses.replace(c, inlen=29), None),
        ("wrong feature length (33 instead of 34)", touchpad, lambda c: dataclasses.replace(c, featlen=33), None),
        ("swapped X/Y of finger 1", touchpad, swap_xy, None),
        ("wrong rid (vendor blob 0xc7 in rid 6)", touchpad,
         lambda c: replace_caps(c, lambda x: x.usage == 0xC7, rid=6), None),
        ("wrong rid (X of finger 3 in rid 5)", touchpad,
         lambda c: replace_caps(c, finger_x(3), rid=5), None),
        ("wrong logical max (X of finger 2)", touchpad,
         lambda c: replace_caps(c, finger_x(2), lmax=2228), None),
        ("wrong physical max (X of finger 4)", touchpad,
         lambda c: replace_caps(c, finger_x(4), pmax=1114), None),
        ("wrong unit (X of finger 5 in seconds)", touchpad,
         lambda c: replace_caps(c, finger_x(5), unit=4097), None),
        ("wrong link (X of finger 5 in link 6)", touchpad,
         lambda c: replace_caps(c, finger_x(5), link=6), None),
        ("only four fingers in caps", touchpad,
         lambda c: drop_caps(c, lambda x: x.link == 5, nlink=5), None),
        ("descriptor report size flipped (16 -> 15 bits)", touchpad, None,
         lambda d: d.replace(b"\x75\x10", b"\x75\x0f", 1)),
        ("descriptor truncated by 3 bytes", touchpad, None, lambda d: d[:-3]),
        ("touchscreen rid 64 -> 65 in caps", touchscreen,
         lambda c: replace_caps(c, lambda x: True, rid=65), None),
        ("pen length 16 -> 15 in caps", pen, lambda c: dataclasses.replace(c, inlen=15), None),
    ]


def run_device_control(case, devices):
    name, device, caps_fn, desc_fn = case
    caps, desc = devices[device]
    caps = caps_fn(caps) if caps_fn else caps
    desc = desc_fn(desc) if desc_fn else desc
    return corpus_checks.check_device(caps, desc, None, regen=False)


def report_controls(lines):
    first = next(l for l in lines if l.name == "1finger-down")
    flipped = bytearray(bytes.fromhex(first.hex))
    flipped[3] ^= 0x01
    wrong_value = dict(first.values, **{"contact0.x": 1001})
    return [
        ("report bit flipped in X", [dataclasses.replace(first, hex=bytes(flipped).hex())]),
        ("report expected value wrong (x 1001)", [dataclasses.replace(first, values=wrong_value)]),
        ("report one byte too short", [dataclasses.replace(first, hex=first.hex[:-2])]),
        ("report unknown field name", [dataclasses.replace(first, values=dict(first.values, bogus=1))]),
        ("report padding bit set", [dataclasses.replace(first, hex=first.hex[:4] + "2b" + first.hex[6:])]),
    ]


def swapped_order_descriptor(touchpad_caps):
    saved = layouts.FINGER_BIT_ORDER
    layouts.FINGER_BIT_ORDER = tuple(reversed(saved))
    try:
        desc, _, _ = caps2desc.synthesize(touchpad_caps)
    finally:
        layouts.FINGER_BIT_ORDER = saved
    return desc


def run(directory):
    devices = {}
    refs = {}
    for name in (TP, TS, PEN):
        caps = hidcaps.load(os.path.join(directory, name + ".caps"))
        desc = bytes.fromhex(read(os.path.join(directory, name + ".desc.hex")).strip())
        devices[name] = (caps, desc)
        refs[name] = refparser.expand(refparser.parse(desc)[1])
    lines = reportfile.parse_file(read(os.path.join(directory, "reports.txt")))
    baseline = [corpus_checks.check_device(c, d, None, regen=False) for c, d in devices.values()]
    baseline.append(corpus_checks.check_reports([l for l in lines if l.device in refs], refs))
    clean = sum(len(r.fails) for r in baseline)
    print("baseline: %d fail (must be 0)" % clean)
    detected = missed = 0
    outcomes = []
    for case in device_controls():
        outcomes.append((case[0], run_device_control(case, devices).fails))
    for name, mutated in report_controls(lines):
        outcomes.append((name, corpus_checks.check_reports(mutated, refs).fails))
    swapped = dict(refs)
    swapped[TP] = refparser.expand(refparser.parse(swapped_order_descriptor(devices[TP][0]))[1])
    first = [l for l in lines if l.device == TP and l.name == "1finger-down"]
    outcomes.append(("descriptor with Tip/Confidence order swapped vs report layout",
                     corpus_checks.check_reports(first, swapped).fails))
    for name, fails in outcomes:
        if fails:
            detected += 1
            print("CONTROL OK   %s -> detected (%d fail, first: %s)" % (name, len(fails), fails[0][1]))
        else:
            missed += 1
            print("CONTROL MISS %s -> not detected" % name)
    print("selftest: %d detected, %d missed, baseline fail %d" % (detected, missed, clean))
    return 1 if (missed or clean) else 0
