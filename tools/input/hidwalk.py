# SPDX-License-Identifier: GPL-2.0-only
KIND_BY_TAG = {0x8: "IN", 0x9: "OUT", 0xB: "FEAT"}
SIZES = (0, 1, 2, 4)
GLOBAL_NAMES = {0: "page", 3: "pmin", 4: "pmax", 5: "unitexp", 6: "unit", 7: "size", 8: "rid", 9: "count"}


class WalkError(Exception):
    pass


class State:
    def __init__(self):
        self.g = {"page": 0, "lmin": 0, "lmax": 0, "pmin": 0, "pmax": 0, "unitexp": 0,
                  "unit": 0, "size": 0, "rid": 0, "count": 0}
        self.usages = []
        self.umin = None
        self.umax = None
        self.link_stack = []
        self.collections = []
        self.elements = []
        self.bits = {}

    def clear_locals(self):
        self.usages = []
        self.umin = None
        self.umax = None

    def usage_list(self, count):
        if self.umin is not None and self.umax is not None:
            return [(self.g["page"], u) for u in range(self.umin, self.umax + 1)]
        return self.usages

    def add_collection(self, kind):
        link = len(self.collections)
        usage = self.usages[0] if self.usages else (self.g["page"], 0)
        self.collections.append({"link": link, "kind": kind, "page": usage[0], "usage": usage[1],
                                 "depth": len(self.link_stack) + 1})
        self.link_stack.append(link)

    def add_main(self, kind, flags):
        g = self.g
        key = (kind, g["rid"])
        offset = self.bits.get(key, 0)
        const = bool(flags & 1)
        if not const and not flags & 2:
            raise WalkError("array items are not supported")
        usages = [] if const else self.usage_list(g["count"])
        for index in range(g["count"]):
            if const:
                page, usage = None, None
            elif usages:
                page, usage = usages[min(index, len(usages) - 1)]
            else:
                page, usage = g["page"], 0
            self.elements.append({
                "kind": kind, "rid": g["rid"], "page": page, "usage": usage,
                "bitoff": offset + index * g["size"], "bits": g["size"],
                "lmin": g["lmin"], "lmax": g["lmax"], "pmin": g["pmin"], "pmax": g["pmax"],
                "unitexp": g["unitexp"], "unit": g["unit"],
                "link": self.link_stack[-1] if self.link_stack else None, "const": const,
            })
        self.bits[key] = offset + g["size"] * g["count"]


def read_item(data, pos):
    prefix = data[pos]
    if prefix == 0xFE:
        raise WalkError("long item at %d" % pos)
    size = SIZES[prefix & 3]
    if pos + 1 + size > len(data):
        raise WalkError("truncated item at %d" % pos)
    raw = data[pos + 1:pos + 1 + size]
    unsigned = int.from_bytes(raw, "little")
    signed = int.from_bytes(raw, "little", signed=True) if size else 0
    return (prefix >> 2) & 3, prefix >> 4, size, unsigned, signed, pos + 1 + size


def apply_global(state, tag, unsigned, signed):
    g = state.g
    if tag == 1:
        g["lmin"] = signed
    elif tag == 2:
        g["lmax"] = signed if g["lmin"] < 0 else unsigned
    elif tag in (3, 4):
        g[GLOBAL_NAMES[tag]] = signed
    elif tag in GLOBAL_NAMES:
        g[GLOBAL_NAMES[tag]] = unsigned
    else:
        raise WalkError("unsupported global tag %d" % tag)


def apply_local(state, tag, size, unsigned):
    if tag == 0:
        full = (unsigned >> 16, unsigned & 0xFFFF) if size == 4 else (state.g["page"], unsigned)
        state.usages.append(full)
    elif tag == 1:
        state.umin = unsigned & 0xFFFF
    elif tag == 2:
        state.umax = unsigned & 0xFFFF


def apply_main(state, tag, unsigned):
    if tag == 0xA:
        state.add_collection(unsigned)
    elif tag == 0xC:
        if not state.link_stack:
            raise WalkError("unbalanced end collection")
        state.link_stack.pop()
    elif tag in KIND_BY_TAG:
        state.add_main(KIND_BY_TAG[tag], unsigned)
    else:
        raise WalkError("unsupported main tag %d" % tag)
    state.clear_locals()


def walk(data):
    state = State()
    pos = 0
    while pos < len(data):
        item_type, tag, size, unsigned, signed, pos = read_item(data, pos)
        if item_type == 1:
            apply_global(state, tag, unsigned, signed)
        elif item_type == 2:
            apply_local(state, tag, size, unsigned)
        elif item_type == 0:
            apply_main(state, tag, unsigned)
        else:
            raise WalkError("reserved item type")
    if state.link_stack:
        raise WalkError("unclosed collection")
    return state
