import struct
import sys

STAGE2_LBA = 256
ESP_GUID = bytes.fromhex("28732ac11ff8d211ba4b00a0c93ec93b")
FAT_TYPES = (0x0B, 0x0C, 0xEF)
PARAM_OFFSET = 424
MAGIC = 0x3042534F


def find_esp(f):
    f.seek(512)
    header = f.read(512)
    if header[:8] == b"EFI PART":
        entries_lba, count, size = struct.unpack_from("<QII", header, 72)
        f.seek(entries_lba * 512)
        table = f.read(count * size)
        for i in range(count):
            entry = table[i * size:(i + 1) * size]
            if entry[:16] == ESP_GUID:
                return struct.unpack_from("<Q", entry, 32)[0]
    f.seek(446)
    for i in range(4):
        entry = f.read(16)
        if entry[4] in FAT_TYPES:
            return struct.unpack_from("<I", entry, 8)[0]
    return None


def install(image, stage0_path, stage2_path):
    stage0 = open(stage0_path, "rb").read()
    stage2 = open(stage2_path, "rb").read()
    if len(stage0) != 440:
        raise SystemExit("biosinstall: stage0 must be 440 bytes")
    sectors = (len(stage2) + 511) // 512
    with open(image, "r+b") as f:
        esp = find_esp(f)
        if esp is None:
            raise SystemExit("biosinstall: no FAT system partition found")
        if esp < STAGE2_LBA + sectors:
            raise SystemExit("biosinstall: gap before first partition too small")
        patched = bytearray(stage0)
        struct.pack_into("<IIII", patched, PARAM_OFFSET, esp, STAGE2_LBA, sectors, MAGIC)
        f.seek(STAGE2_LBA * 512)
        f.write(stage2.ljust(sectors * 512, b"\0"))
        f.seek(0)
        f.write(patched)
    print("biosinstall: esp lba %d, stage2 lba %d, %d sectors" % (esp, STAGE2_LBA, sectors))


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("usage: biosinstall.py <image> <stage0.bin> <stage2.bin>")
    install(*sys.argv[1:])
