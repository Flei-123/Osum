import struct
import subprocess
import sys

SECTOR = 512
DISK_SECTORS = 131072
ESP_FIRST = 2048
ESP_LAST = 34815
OWN_FIRST = 34816
TAIL_RESERVE = 4096 + 33
OWN_TYPE = "4F53554D-4F46-5301-8E75-6D6F72694F53"
OFS_MAGIC = b"SFO-MUSO"
BLOCKS_OFFSET = 16
ENTRY_TABLE_LBA = 2
ENTRY_SIZE = 128
LAST_USABLE = DISK_SECTORS - 34
NEW_LAST = DISK_SECTORS - 1 - TAIL_RESERVE
FS_BLOCKS_OLD_FIT = 50000
FS_BLOCKS_FOREIGN = 1000


def sgdisk(image, *args):
    subprocess.run(["sgdisk", *args, image], check=True, stdout=subprocess.DEVNULL)


def write_superblock(image, first, blocks):
    block = bytearray(SECTOR)
    block[0:8] = OFS_MAGIC
    struct.pack_into("<Q", block, BLOCKS_OFFSET, blocks)
    with open(image, "r+b") as f:
        f.seek(first * SECTOR)
        f.write(block)


def make(image, case):
    with open(image, "wb") as f:
        f.seek(DISK_SECTORS * SECTOR - 1)
        f.write(b"\0")
    sgdisk(image, "-o")
    sgdisk(image, "-n", f"1:{ESP_FIRST}:{ESP_LAST}", "-t", "1:EF00", "-c", "1:EFI System Partition")
    last = NEW_LAST if case == "new" else LAST_USABLE
    type_code = "0700" if case == "foreign" else OWN_TYPE
    sgdisk(image, "-n", f"2:{OWN_FIRST}:{last}", "-t", f"2:{type_code}", "-c", "2:root")
    full = last - OWN_FIRST + 1
    blocks = {"new": full, "oldfit": FS_BLOCKS_OLD_FIT, "oldfull": full, "foreign": FS_BLOCKS_FOREIGN}[case]
    write_superblock(image, OWN_FIRST, blocks)
    return last


def second_entry(image):
    with open(image, "rb") as f:
        f.seek(ENTRY_TABLE_LBA * SECTOR + ENTRY_SIZE)
        entry = f.read(ENTRY_SIZE)
    return struct.unpack_from("<QQ", entry, 32)


def expected_state(image):
    first, last = second_entry(image)
    if last <= NEW_LAST:
        return "ok"
    with open(image, "rb") as f:
        f.seek(first * SECTOR)
        sb = f.read(SECTOR)
    blocks = struct.unpack_from("<Q", sb, BLOCKS_OFFSET)[0]
    if sb[0:8] == OFS_MAGIC and blocks and first + blocks - 1 <= NEW_LAST:
        return "trimmable"
    return "overlap"


if __name__ == "__main__":
    action, image = sys.argv[1], sys.argv[2]
    if action == "make":
        print(make(image, sys.argv[3]))
    elif action == "state":
        print(expected_state(image))
    elif action == "end":
        print(second_entry(image)[1])
