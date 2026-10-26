#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import importlib.util
import os
import re
import sys

HEADER_BYTES = 36
LENGTH_AT = 4
CHECKSUM_AT = 9
TABLE_LIMIT = 65535
CHUNK_BODY = 60000
PKG_OPS = (0x10, 0x14, 0xA0, 0xA1, 0xA2)
EXT_PKG_OPS = (0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87)
SCOPE_OP = 0x10
EXT_PREFIX = 0x5B
EXT_DEVICE = 0x82
EXT_THERMAL = 0x85
PKG_THRESHOLDS = (64, 4096, 1 << 20, 1 << 28)
CONTAINER_BODY = 30000


def load_disasm():
    here = os.path.dirname(os.path.abspath(__file__))
    spec = importlib.util.spec_from_file_location("disasm", os.path.join(here, "..", "aml", "disasm.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def skip_term(parser, body, i):
    op = body[i]
    if op in PKG_OPS:
        length, at = parser.pkglen(i + 1)
        return i + 1 + length
    if op == 0x5B and body[i + 1] in EXT_PKG_OPS:
        length, at = parser.pkglen(i + 2)
        return i + 2 + length
    sink = []
    return parser.term(i, "\\", sink)


def top_terms(body, disasm):
    parser = disasm.Aml(body, {})
    spans = []
    i = 0
    while i < len(body):
        j = skip_term(parser, body, i)
        if j <= i:
            raise ValueError("no progress at %d" % i)
        spans.append((i, j))
        i = j
    return spans


def encode_pkglen(payload):
    for extra, limit in enumerate(PKG_THRESHOLDS):
        total = payload + extra + 1
        if total < limit:
            break
    if extra == 0:
        return bytes([total])
    first = (extra << 6) | (total & 0x0F)
    rest = [(total >> (4 + 8 * k)) & 0xFF for k in range(extra)]
    return bytes([first] + rest)


def container_parts(parser, term):
    if term[0] == SCOPE_OP:
        op = term[:1]
        length, at = parser.pkglen(1)
    elif term[0] == EXT_PREFIX and term[1] in (EXT_DEVICE, EXT_THERMAL):
        op = term[:2]
        length, at = parser.pkglen(2)
    else:
        return None
    name, after = parser.namestring(at)
    return op, term[at:after], term[after:]


def explode(term, scope, disasm, limit):
    if len(term) <= limit:
        return [term]
    parser = disasm.Aml(term, {})
    parts = container_parts(parser, term)
    if parts is None:
        raise ValueError("oversized term that cannot be split (opcode 0x%02x, %d bytes)" % (term[0], len(term)))
    op, name_bytes, body = parts
    inner = []
    for a, b in top_terms(body, disasm):
        inner.extend(explode(body[a:b], scope, disasm, limit))
    groups = [[]]
    size = 0
    for child in inner:
        if size + len(child) > CONTAINER_BODY and groups[-1]:
            groups.append([])
            size = 0
        groups[-1].append(child)
        size += len(child)
    out = []
    for k, group in enumerate(groups):
        payload = name_bytes + b"".join(group)
        head = op if k == 0 else bytes([SCOPE_OP])
        out.append(head + encode_pkglen(len(payload)) + payload)
    return out


def seal(header, body):
    out = bytearray(header[:HEADER_BYTES]) + bytearray(body)
    out[0:4] = b"SSDT"
    out[LENGTH_AT:LENGTH_AT + 4] = len(out).to_bytes(4, "little")
    out[CHECKSUM_AT] = 0
    out[CHECKSUM_AT] = (-sum(out)) & 0xFF
    return bytes(out)


def chunks(data, disasm):
    length = int.from_bytes(data[LENGTH_AT:LENGTH_AT + 4], "little")
    if length <= TABLE_LIMIT:
        return [seal(data, data[HEADER_BYTES:length])]
    body = data[HEADER_BYTES:length]
    terms = []
    for a, b in top_terms(body, disasm):
        terms.extend(explode(body[a:b], "\\", disasm, CHUNK_BODY))
    out = []
    current = []
    size = 0
    for term in terms:
        if size + len(term) > CHUNK_BODY and current:
            out.append(seal(data, b"".join(current)))
            current = []
            size = 0
        current.append(term)
        size += len(term)
    out.append(seal(data, b"".join(current)))
    return out


def table_order(names):
    def key(n):
        m = re.match(r"([A-Z]+)(\d*)$", n)
        return (0 if m.group(1) == "DSDT" else 1, int(m.group(2) or 0))
    return sorted((n for n in names if re.match(r"(DSDT|SSDT\d*)$", n)), key=key)


def main(argv):
    if len(argv) != 3:
        print("usage: prep_corpus.py CORPUS_DIR OUT_DIR", file=sys.stderr)
        return 2
    disasm = load_disasm()
    os.makedirs(argv[2], exist_ok=True)
    count = 0
    for name in table_order(os.listdir(argv[1])):
        with open(os.path.join(argv[1], name), "rb") as f:
            data = f.read()
        for part in chunks(data, disasm):
            with open(os.path.join(argv[2], "%02d-%s.aml" % (count, name)), "wb") as f:
                f.write(part)
            count += 1
    print(count)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
