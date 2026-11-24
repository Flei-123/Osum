import sys


def build(width_mm, height_mm, hres=1920, vres=1080):
    block = bytearray(128)
    block[0:8] = bytes([0, 255, 255, 255, 255, 255, 255, 0])
    block[8:10] = bytes([0x06, 0xAF])
    block[10:12] = bytes([0x3D, 0x14])
    block[16] = 1
    block[17] = 30
    block[18] = 1
    block[19] = 4
    block[20] = 0x95
    block[21] = width_mm // 10
    block[22] = height_mm // 10
    block[23] = 0x78
    hblank, vblank = 160, 31
    clock = 141000
    hfront, hsync, vfront, vsync = 48, 32, 3, 5
    d = bytearray(18)
    d[0] = (clock // 10) & 255
    d[1] = (clock // 10) >> 8
    d[2] = hres & 255
    d[3] = hblank & 255
    d[4] = ((hres >> 8) << 4) | (hblank >> 8)
    d[5] = vres & 255
    d[6] = vblank & 255
    d[7] = ((vres >> 8) << 4) | (vblank >> 8)
    d[8] = hfront & 255
    d[9] = hsync & 255
    d[10] = ((vfront & 15) << 4) | (vsync & 15)
    d[11] = 0
    d[12] = width_mm & 255
    d[13] = height_mm & 255
    d[14] = ((width_mm >> 8) << 4) | (height_mm >> 8)
    d[17] = 0x18
    block[54:72] = d
    name = bytearray([0, 0, 0, 0xFC, 0]) + b"FRACSCALE\n" + b"   "
    block[72:90] = name[:18]
    block[127] = (256 - sum(block[:127]) % 256) % 256
    return bytes(block)


if __name__ == "__main__":
    mm_w = int(sys.argv[1]) if len(sys.argv) > 1 else 293
    mm_h = int(sys.argv[2]) if len(sys.argv) > 2 else 165
    print(build(mm_w, mm_h).hex())
