import struct
import sys
import zlib

SECTOR = 512


def read_sector(f, lba):
    f.seek(lba * SECTOR)
    return bytearray(f.read(SECTOR))


def write_sector(f, lba, data):
    f.seek(lba * SECTOR)
    f.write(bytes(data))


def header_crc(h):
    size = struct.unpack_from('<I', h, 12)[0]
    tmp = bytearray(h[:size])
    tmp[16:20] = b'\0\0\0\0'
    return zlib.crc32(bytes(tmp)) & 0xFFFFFFFF


def refresh_header_crc(h):
    struct.pack_into('<I', h, 16, header_crc(h))


def table_crc(f, h):
    lba = struct.unpack_from('<Q', h, 72)[0]
    count = struct.unpack_from('<I', h, 80)[0]
    size = struct.unpack_from('<I', h, 84)[0]
    f.seek(lba * SECTOR)
    return zlib.crc32(f.read(count * size)) & 0xFFFFFFFF


def total_sectors(f):
    f.seek(0, 2)
    return f.tell() // SECTOR


def main():
    path, case = sys.argv[1], sys.argv[2]
    with open(path, 'r+b') as f:
        total = total_sectors(f)
        h = read_sector(f, 1)
        expect = ''
        if case == 'hsize':
            struct.pack_into('<I', h, 12, 65535)
            expect = 'dual: gpt header size bad got=65535 want=92'
        elif case == 'hcrc':
            h[56] ^= 0xFF
            stored = struct.unpack_from('<I', h, 16)[0]
            expect = 'dual: gpt header crc bad got=%d want=%d' % (stored, header_crc(h))
        elif case == 'esize':
            struct.pack_into('<I', h, 84, 64)
            refresh_header_crc(h)
            expect = 'dual: gpt entry size bad got=64 want=128'
        elif case == 'count':
            struct.pack_into('<I', h, 80, 200)
            refresh_header_crc(h)
            expect = 'dual: gpt entry count bad got=200 want=128'
        elif case == 'tcrc':
            lba = struct.unpack_from('<Q', h, 72)[0]
            e = read_sector(f, lba)
            e[5] ^= 0xFF
            write_sector(f, lba, e)
            stored = struct.unpack_from('<I', h, 88)[0]
            expect = 'dual: gpt table crc bad got=%d want=%d' % (stored, table_crc(f, h))
        else:
            raise SystemExit('unknown case')
        write_sector(f, 1, h)
        b = read_sector(f, total - 1)
        b[0:8] = b'\0' * 8
        write_sector(f, total - 1, b)
        print(expect)


main()
