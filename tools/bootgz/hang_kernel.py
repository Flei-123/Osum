import struct
import sys

PT_LOAD = 1
JMP_SELF = b"\xeb\xfe"


def entry_offset(data):
    entry = struct.unpack_from("<I", data, 24)[0]
    phoff = struct.unpack_from("<I", data, 28)[0]
    phentsize, phnum = struct.unpack_from("<HH", data, 42)
    for i in range(phnum):
        ptype, off, vaddr, paddr, filesz = struct.unpack_from("<IIIII", data, phoff + i * phentsize)
        if ptype == PT_LOAD and vaddr <= entry < vaddr + filesz:
            return off + entry - vaddr
    raise SystemExit("entry point is not inside a PT_LOAD segment")


def main():
    src, dst = sys.argv[1], sys.argv[2]
    pad = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    data = bytearray(open(src, "rb").read())
    at = entry_offset(data)
    data[at:at + len(JMP_SELF)] = JMP_SELF
    data += bytes(pad)
    open(dst, "wb").write(data)


main()
