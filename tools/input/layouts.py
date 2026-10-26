# SPDX-License-Identifier: GPL-2.0-only
from descbuild import AlignByte, Coll, Group, PadTo

PHYSICAL, APPLICATION, LOGICAL = 0, 1, 2
PAGE_DIGITIZER = 0xD
PAGE_DESKTOP = 0x1
PAGE_BUTTON = 0x9

FINGER_BIT_ORDER = (0x47, 0x42)
PEN_BUTTON_ORDER = (0x44, 0x3C, 0x45, 0x42, 0x32)
PEN_TILT_ORDER = (0x3D, 0x3E)


class CapSet:
    def __init__(self, caps):
        self.caps = caps
        self.used = set()

    def take(self, kind, typ, page, usage, link=0):
        found = [c for c in self.caps.caps
                 if (c.kind, c.type, c.page, c.usage, c.link) == (kind, typ, page, usage, link)]
        if len(found) != 1:
            raise ValueError("expected exactly one caps line for %s %s page=0x%x usage=0x%x link=%d, found %d"
                             % (kind, typ, page, usage, link, len(found)))
        self.used.add(found[0])
        return found[0]

    def links(self):
        return sorted({c.link for c in self.caps.caps if c.link > 0})

    def unused(self):
        return [c for c in self.caps.caps if c not in self.used]


def single(cs, kind, page, usage, link=0, typ="VAL"):
    return Group((cs.take(kind, typ, page, usage, link),))


def touchpad(cs, notes):
    notes += [
        "finger collection order: Confidence at bit 0, Tip Switch at bit 1 (Windows Precision Touchpad "
        "sample descriptor; the task text listed Tip first; switch via FINGER_BIT_ORDER in layouts.py)",
        "finger collections are Logical collections of usage Finger (0x0d/0x22); HidP exposes only the link index",
        "padding after Contact ID aligns each finger block to a byte boundary",
        "top-level item order: Scan Time, Contact Count, Button 1 + padding, then feature reports",
        "feature rid 4 packs Contact Count Maximum (0x55) low nibble and usage 0x59 (Pad Type in HID Usage "
        "Tables 1.3; the task text calls it Surface Switch) high nibble; caps list 0x59 first, the order "
        "follows the Microsoft sample descriptor",
        "feature rid 6 Latency Mode (0x60) is padded to a byte",
        "vendor feature rid 5 uses usage page 0xff00, usages 0xc6 (1 byte) and 0xc7 (32 bytes) as two items",
        "physical min/max/unit of Button, Scan Time, Contact Count and feature fields are copied from the "
        "caps; the values 0..65535 / exponent -4 / seconds on non-time fields are an inherited HidP artifact",
    ]
    fingers = []
    for link in cs.links():
        bits = tuple(cs.take("IN", "BTN", PAGE_DIGITIZER, usage, link) for usage in FINGER_BIT_ORDER)
        ident = cs.take("IN", "VAL", PAGE_DIGITIZER, 0x51, link)
        fingers.append(Coll(LOGICAL, PAGE_DIGITIZER, 0x22, (
            Group(bits),
            Group((ident,)),
            AlignByte("IN", ident.rid),
            single(cs, "IN", PAGE_DESKTOP, 0x30, link),
            single(cs, "IN", PAGE_DESKTOP, 0x31, link),
        )))
    scan = cs.take("IN", "VAL", PAGE_DIGITIZER, 0x56)
    count = cs.take("IN", "VAL", PAGE_DIGITIZER, 0x54)
    button = cs.take("IN", "BTN", PAGE_BUTTON, 0x01)
    pair = (cs.take("FEAT", "VAL", PAGE_DIGITIZER, 0x55), cs.take("FEAT", "VAL", PAGE_DIGITIZER, 0x59))
    latency = cs.take("FEAT", "VAL", PAGE_DIGITIZER, 0x60)
    blob_mode = cs.take("FEAT", "VAL", 0xFF00, 0xC6)
    blob = cs.take("FEAT", "VAL", 0xFF00, 0xC7)
    return (Coll(APPLICATION, PAGE_DIGITIZER, 0x05, tuple(fingers) + (
        Group((scan,)), Group((count,)), Group((button,)), AlignByte("IN", button.rid),
        Group(pair), Group((latency,)), AlignByte("FEAT", latency.rid),
        Group((blob_mode,)), Group((blob,)),
    )),)


def touchscreen(cs, notes):
    notes += [
        "single contact at top-level (nlink=1): no Finger collection is declared",
        "padding after Tip Switch aligns to a byte boundary",
    ]
    tip = cs.take("IN", "BTN", PAGE_DIGITIZER, 0x42)
    return (Coll(APPLICATION, PAGE_DIGITIZER, 0x04, (
        Group((tip,)), AlignByte("IN", tip.rid),
        single(cs, "IN", PAGE_DESKTOP, 0x30), single(cs, "IN", PAGE_DESKTOP, 0x31),
    )),)


def pen(cs, notes, caps):
    notes += [
        "pen sits in a Physical collection of usage Stylus (0x0d/0x20), assumed for link 1",
        "button bit order Barrel, Invert, Eraser, Tip Switch, In Range as given in the task text; "
        "HidP lists them in a different order and the real bit positions are unknown",
        "field order: X, Y, Tip Pressure, X Tilt, Y Tilt, Scan Time, vendor 0xff00/1",
        "vendor field is 8 bits with logical max 4096 exactly as measured (does not fit 8 bits)",
        "tilt fields use logical 0..18000 mapped to physical -9000..9000 with unit raw 20 as measured",
    ]
    buttons = tuple(cs.take("IN", "BTN", PAGE_DIGITIZER, usage, 1) for usage in PEN_BUTTON_ORDER)
    rid = buttons[0].rid
    tilt = tuple(cs.take("IN", "VAL", PAGE_DIGITIZER, usage, 1) for usage in PEN_TILT_ORDER)
    return (Coll(APPLICATION, PAGE_DIGITIZER, 0x02, (
        Coll(PHYSICAL, PAGE_DIGITIZER, 0x20, (
            Group(buttons), AlignByte("IN", rid),
            single(cs, "IN", PAGE_DESKTOP, 0x30, 1), single(cs, "IN", PAGE_DESKTOP, 0x31, 1),
            single(cs, "IN", PAGE_DIGITIZER, 0x30, 1),
            Group(tilt),
            single(cs, "IN", PAGE_DIGITIZER, 0x56, 1),
            single(cs, "IN", 0xFF00, 0x01, 1),
            PadTo("IN", rid, caps.inlen),
        )),
    )),)


def config(cs, notes):
    notes += [
        "Input Mode (0x52) sits in a Logical Finger collection (0x0d/0x22) = link 1",
        "Surface Switch (0x57) and Button Switch (0x58) sit in a Logical collection of usage "
        "Device Settings (0x0d/0x23) = link 2; bit order 0x57 then 0x58",
        "feature items of rid 7 and rid 8 are padded to a byte; rid 7 declared before rid 8",
    ]
    mode = cs.take("FEAT", "VAL", PAGE_DIGITIZER, 0x52, 1)
    switches = (cs.take("FEAT", "BTN", PAGE_DIGITIZER, 0x57, 2), cs.take("FEAT", "BTN", PAGE_DIGITIZER, 0x58, 2))
    return (Coll(APPLICATION, PAGE_DIGITIZER, 0x0E, (
        Coll(LOGICAL, PAGE_DIGITIZER, 0x22, (Group((mode,)), AlignByte("FEAT", mode.rid))),
        Coll(LOGICAL, PAGE_DIGITIZER, 0x23, (Group(switches), AlignByte("FEAT", switches[0].rid))),
    )),)


REGISTRY = {
    (PAGE_DIGITIZER, 0x05): lambda cs, notes, caps: touchpad(cs, notes),
    (PAGE_DIGITIZER, 0x04): lambda cs, notes, caps: touchscreen(cs, notes),
    (PAGE_DIGITIZER, 0x02): pen,
    (PAGE_DIGITIZER, 0x0E): lambda cs, notes, caps: config(cs, notes),
}


def layout_for(caps):
    key = (caps.top_page, caps.top_usage)
    if key not in REGISTRY:
        raise ValueError("no layout for top-level 0x%x/0x%x" % key)
    cs = CapSet(caps)
    notes = []
    nodes = REGISTRY[key](cs, notes, caps)
    leftover = cs.unused()
    if leftover:
        raise ValueError("caps lines not used by the layout: %s" % ", ".join(c.label() for c in leftover))
    return nodes, notes
