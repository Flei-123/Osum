# SPDX-License-Identifier: GPL-2.0-only
def check_range(length, offset, width):
    if offset < 0 or width <= 0 or offset + width > length * 8:
        raise ValueError("bit range %d+%d outside %d bytes" % (offset, width, length))


def get_bit(data, position):
    return (data[position >> 3] >> (position & 7)) & 1


def read_bits(data, offset, width):
    check_range(len(data), offset, width)
    value = 0
    for index in range(width):
        value |= get_bit(data, offset + index) << index
    return value


def read_bits_shift(data, offset, width):
    check_range(len(data), offset, width)
    return (int.from_bytes(data, "little") >> offset) & ((1 << width) - 1)


def write_bits(buffer, offset, width, value):
    check_range(len(buffer), offset, width)
    if value < 0 or value >> width:
        raise ValueError("value %d does not fit in %d bits" % (value, width))
    for index in range(width):
        position = offset + index
        if (value >> index) & 1:
            buffer[position >> 3] |= 1 << (position & 7)
        else:
            buffer[position >> 3] &= ~(1 << (position & 7)) & 0xFF
