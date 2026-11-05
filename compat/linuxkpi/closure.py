#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import argparse
import re
import struct
import subprocess
import sys

MAX_SECTIONS = 64
MAX_IMAGE = 0x80000
MAX_ALIGN = 4096
MAX_EXPORT_NAME = 63
ALLOWED_RELOCS = {1: "R_X86_64_64", 2: "R_X86_64_PC32", 4: "R_X86_64_PLT32", 10: "R_X86_64_32", 11: "R_X86_64_32S"}
SHF_ALLOC = 2
SHT_SYMTAB = 2
SHT_RELA = 4
SHT_NOBITS = 8
SHN_UNDEF = 0
SHN_ABS = 0xFFF1
SHN_COMMON = 0xFFF2
STB_GLOBAL = 1
STB_WEAK = 2
ENTRY_POINTS = ("module_init", "module_exit")
FORBIDDEN_SECTIONS = re.compile(r"^\.(init_array|fini_array|preinit_array|ctors|dtors|tdata|tbss)")
FORBIDDEN_INSN = re.compile(r"%(xmm|ymm|zmm|mm[0-7]\b|st\b|st\()|%[fg]s:")


class Section:
    def __init__(self, name, kind, flags, offset, size, link, info, align, entsize):
        self.name = name
        self.kind = kind
        self.flags = flags
        self.offset = offset
        self.size = size
        self.link = link
        self.info = info
        self.align = align
        self.entsize = entsize


class Symbol:
    def __init__(self, name, bind, kind, shndx, value):
        self.name = name
        self.bind = bind
        self.kind = kind
        self.shndx = shndx
        self.value = value


class Reloc:
    def __init__(self, target, offset, kind, symbol):
        self.target = target
        self.offset = offset
        self.kind = kind
        self.symbol = symbol


class ElfObject:
    def __init__(self, path):
        self.path = path
        with open(path, "rb") as handle:
            self.data = handle.read()
        if self.data[:4] != b"\x7fELF" or self.data[4] != 2 or self.data[5] != 1:
            raise ValueError("%s: not a little-endian ELF64 file" % path)
        self.kind, self.machine = struct.unpack_from("<HH", self.data, 16)
        self.shoff = struct.unpack_from("<Q", self.data, 0x28)[0]
        self.shentsize, self.shnum, self.shstrndx = struct.unpack_from("<HHH", self.data, 0x3A)
        self.sections = self.read_sections()
        self.symbols = self.read_symbols()
        self.relocs = self.read_relocs()

    def string(self, table, offset):
        base = self.sections[table].offset + offset
        return self.data[base:self.data.index(b"\0", base)].decode("ascii", "replace")

    def read_sections(self):
        raw = []
        for i in range(self.shnum):
            fields = struct.unpack_from("<IIQQQQIIQQ", self.data, self.shoff + i * self.shentsize)
            raw.append(fields)
        sections = []
        for fields in raw:
            name, kind, flags, _, offset, size, link, info, align, entsize = fields
            sections.append(Section(name, kind, flags, offset, size, link, info, align, entsize))
        self.sections = sections
        for section in sections:
            section.name = self.string(self.shstrndx, section.name)
        return sections

    def read_symbols(self):
        symbols = []
        for section in self.sections:
            if section.kind != SHT_SYMTAB:
                continue
            for pos in range(section.offset, section.offset + section.size, 24):
                name, info, _, shndx, value, _ = struct.unpack_from("<IBBHQQ", self.data, pos)
                symbols.append(Symbol(self.string(section.link, name) if name else "", info >> 4, info & 15, shndx, value))
            break
        return symbols

    def read_relocs(self):
        relocs = []
        for section in self.sections:
            if section.kind != SHT_RELA:
                continue
            for pos in range(section.offset, section.offset + section.size, 24):
                offset, info, _ = struct.unpack_from("<QQq", self.data, pos)
                relocs.append(Reloc(section.info, offset, info & 0xFFFFFFFF, info >> 32))
        return relocs

    def allocated(self, index):
        return 0 < index < len(self.sections) and bool(self.sections[index].flags & SHF_ALLOC)

    def defined(self, symbol):
        return symbol.shndx not in (SHN_UNDEF, SHN_ABS, SHN_COMMON) and symbol.shndx < len(self.sections)

    def exports(self):
        names = set()
        for symbol in self.symbols:
            if symbol.name and symbol.bind in (STB_GLOBAL, STB_WEAK) and self.defined(symbol) and self.allocated(symbol.shndx):
                if symbol.name not in ENTRY_POINTS:
                    names.add(symbol.name)
        return names

    def undefined(self):
        return {s.name for s in self.symbols if s.name and s.shndx == SHN_UNDEF}

    def image_size(self):
        total = 0
        for section in self.sections[1:]:
            if not section.flags & SHF_ALLOC:
                continue
            align = max(section.align, 1)
            total += (-total) % align
            total += section.size
        return total


def kernel_symbols(header):
    with open(header, encoding="utf-8") as handle:
        text = handle.read()
    match = re.search(r"#define\s+OSUM_KERNEL_SYMBOLS((?:[^\n]*\\\n)*[^\n]*)", text)
    if not match:
        raise ValueError("%s: OSUM_KERNEL_SYMBOLS not found" % header)
    return set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", match.group(1).replace("\\\n", " ")))


def ksym_names(path):
    with open(path, "rb") as handle:
        return handle.read()


def text_violations(path):
    result = subprocess.run(["objdump", "-d", "-w", "--no-show-raw-insn", path], capture_output=True, text=True, check=True)
    return sum(1 for line in result.stdout.splitlines() if FORBIDDEN_INSN.search(line))


def check_object(obj, label, allowed_undefined, fails):
    if obj.kind != 1:
        fails.append("%s: not a relocatable object" % label)
    if obj.machine != 62:
        fails.append("%s: not x86-64" % label)
    if obj.shnum > MAX_SECTIONS:
        fails.append("%s: %d sections, loader limit %d" % (label, obj.shnum, MAX_SECTIONS))
    for section in obj.sections:
        if section.kind in (SHT_SYMTAB, SHT_RELA) and section.entsize != 24:
            fails.append("%s: section %s entry size %d" % (label, section.name, section.entsize))
        if section.flags & SHF_ALLOC:
            if section.align > MAX_ALIGN or (section.align & (section.align - 1)):
                fails.append("%s: section %s alignment %d" % (label, section.name, section.align))
            if FORBIDDEN_SECTIONS.match(section.name):
                fails.append("%s: section %s is never executed or set up by the loader" % (label, section.name))
    size = obj.image_size()
    if size == 0:
        fails.append("%s: no allocated section" % label)
    if size > MAX_IMAGE:
        fails.append("%s: image %d bytes, loader limit %d" % (label, size, MAX_IMAGE))
    for reloc in obj.relocs:
        if not obj.allocated(reloc.target):
            continue
        if reloc.kind not in ALLOWED_RELOCS:
            fails.append("%s: relocation type %d is not supported by the loader" % (label, reloc.kind))
            continue
        symbol = obj.symbols[reloc.symbol] if reloc.symbol < len(obj.symbols) else None
        if symbol is None:
            fails.append("%s: relocation against missing symbol %d" % (label, reloc.symbol))
        elif symbol.shndx == SHN_COMMON:
            fails.append("%s: common symbol %s" % (label, symbol.name))
        elif symbol.shndx not in (SHN_UNDEF, SHN_ABS) and not obj.allocated(symbol.shndx):
            fails.append("%s: relocation against %s in a section that is not loaded" % (label, symbol.name))
    for symbol in obj.symbols:
        if symbol.shndx == SHN_COMMON:
            fails.append("%s: common symbol %s" % (label, symbol.name))
    exports = obj.exports()
    for name in sorted(exports):
        if len(name) > MAX_EXPORT_NAME:
            fails.append("%s: export name longer than %d: %s" % (label, MAX_EXPORT_NAME, name[:40] + "..."))
    for entry in ENTRY_POINTS:
        count = sum(1 for s in obj.symbols if s.name == entry and s.bind in (STB_GLOBAL, STB_WEAK) and obj.defined(s) and obj.allocated(s.shndx))
        if count != 1:
            fails.append("%s: %d definitions of %s" % (label, count, entry))
    for name in sorted(obj.undefined() - allowed_undefined):
        fails.append("%s: undefined symbol %s is provided by nothing" % (label, name))
    bad = text_violations(obj.path)
    if bad:
        fails.append("%s: %d instructions use vector, x87 or segment registers" % (label, bad))
    return exports


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--header", required=True)
    parser.add_argument("--ksym")
    parser.add_argument("provider")
    parser.add_argument("consumer")
    args = parser.parse_args()
    fails = []
    kernel = kernel_symbols(args.header)
    if args.ksym:
        table = ksym_names(args.ksym)
        for name in sorted(kernel):
            if not re.search(rb'"' + re.escape(name.encode()) + rb'(?:\\0|\x00| )"', table):
                fails.append("kernel: export %s is not in the kernel symbol table" % name)
    provider = ElfObject(args.provider)
    consumer = ElfObject(args.consumer)
    provided = check_object(provider, "provider", kernel, fails)
    check_object(consumer, "consumer", kernel | provided, fails)
    for name in sorted(provided & consumer.exports()):
        fails.append("both objects export %s" % name)
    for line in fails:
        print("closure: FAIL " + line, file=sys.stderr)
    if fails:
        return 1
    print("closure: ok provider sections=%d image=%d exports=%d undefined=%d, consumer sections=%d image=%d needs=%d"
          % (provider.shnum, provider.image_size(), len(provided), len(provider.undefined()),
             consumer.shnum, consumer.image_size(), len(consumer.undefined())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
