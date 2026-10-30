#!/usr/bin/env python3
import struct
import sys
import uuid
import zlib

SECTOR = 512
ESP_GUID = uuid.UUID("C12A7328-F81F-11D2-BA4B-00A0C93EC93B")
OFS_GUID = uuid.UUID("4F53554D-4F46-5301-8E75-6D6F72694F53")
BASIC_GUID = uuid.UUID("EBD0A0A2-B9E5-4433-87C0-68B6B72699C7")
ESP_FIRST = 34
ESP_LAST = 1023
OFS_FIRST = 2048


def entry(type_guid, first, last, index):
    raw = type_guid.bytes_le + uuid.UUID(int=index + 1).bytes_le
    raw += struct.pack("<QQQ", first, last, 0)
    return raw.ljust(128, b"\0")


def build(ofs_path, out_path, ofs_type):
    data = open(ofs_path, "rb").read()
    if len(data) % SECTOR:
        data += b"\0" * (SECTOR - len(data) % SECTOR)
    ofs_sectors = len(data) // SECTOR
    total = OFS_FIRST + ofs_sectors + 64
    entries = entry(ESP_GUID, ESP_FIRST, ESP_LAST, 0)
    entries += entry(ofs_type, OFS_FIRST, OFS_FIRST + ofs_sectors - 1, 1)
    entries = entries.ljust(128 * 128, b"\0")
    header = bytearray(92)
    header[0:8] = b"EFI PART"
    struct.pack_into("<IIIIQQQQ", header, 8, 0x10000, 92, 0, 0, 1,
                     total - 1, ESP_FIRST, total - 34)
    header[56:72] = uuid.UUID(int=7).bytes_le
    struct.pack_into("<QIII", header, 72, 2, 128, 128,
                     zlib.crc32(entries) & 0xFFFFFFFF)
    struct.pack_into("<I", header, 16, zlib.crc32(bytes(header)) & 0xFFFFFFFF)
    mbr = bytearray(SECTOR)
    struct.pack_into("<B3sB3sII", mbr, 446, 0, b"\x00\x02\x00", 0xEE,
                     b"\xff\xff\xff", 1, min(total - 1, 0xFFFFFFFF))
    mbr[510:512] = b"\x55\xaa"
    with open(out_path, "wb") as f:
        f.seek(total * SECTOR - 1)
        f.write(b"\0")
        f.seek(0)
        f.write(bytes(mbr))
        f.write(bytes(header).ljust(SECTOR, b"\0"))
        f.write(entries)
        f.seek(OFS_FIRST * SECTOR)
        f.write(data)
    print("gptdisk: ofs_first=%d ofs_sectors=%d total=%d"
          % (OFS_FIRST, ofs_sectors, total))


def main(argv):
    if len(argv) < 3:
        print("usage: gptdisk.py <ofs.img> <out.img> [ofs|basic]")
        return 2
    kind = argv[3] if len(argv) > 3 else "ofs"
    build(argv[1], argv[2], OFS_GUID if kind == "ofs" else BASIC_GUID)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
