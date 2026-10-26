# SPDX-License-Identifier: GPL-2.0-only
import importlib.util
import os

REFERENCE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "hid", "descs.py")
KIND_NAMES = {1: "IN", 2: "OUT", 3: "FEAT"}
FLAG_CONST = 1


def load_reference():
    spec = importlib.util.spec_from_file_location("hid_descs_reference", os.path.normpath(REFERENCE))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MODULE = load_reference()


def signed64(value):
    value &= 0xFFFFFFFFFFFFFFFF
    return value - (1 << 64) if value >> 63 else value


def parse(desc):
    return MODULE.zerlege(bytes(desc))


def expand_field(field):
    kind = KIND_NAMES[field["kind"]]
    const = bool(field["flags"] & FLAG_CONST)
    count = field["count"]
    first = field["usage"]
    last = field["umax"]
    for index in range(count):
        if const:
            usage = None
        elif count > 1 and last == 0:
            usage = first
        else:
            usage = first + index
        yield {
            "kind": kind, "rid": field["rid"], "page": field["page"], "usage": usage,
            "bitoff": field["bitoff"] + index * field["bitsz"], "bits": field["bitsz"],
            "lmin": signed64(field["lmin"]), "lmax": signed64(field["lmax"]), "const": const,
        }


def expand(fields):
    out = []
    for field in fields:
        out.extend(expand_field(field))
    return out


def report_bytes(head):
    out = {"IN": 0, "OUT": 0, "FEAT": 0}
    rids = {"IN": set(), "OUT": set(), "FEAT": set()}
    for rid, in_bits, out_bits, feat_bits in head["ridtab"]:
        for kind, bits in (("IN", in_bits), ("OUT", out_bits), ("FEAT", feat_bits)):
            if bits:
                out[kind] = max(out[kind], (1 if head["hasid"] else 0) + (bits + 7) // 8)
                rids[kind].add(rid)
    return out, rids
