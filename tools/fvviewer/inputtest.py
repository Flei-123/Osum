#!/usr/bin/env python3 -I
# SPDX-License-Identifier: GPL-2.0-only
"""tools/fvviewer/inputtest.py <it-binary>
lib/fv/input.fi against an independent model of the Rust contract (proto.rs wire
format: Key 0x33 code:le32 named down; KeyVk 0x35 vk:le16 ext down; Special 0x36 code)."""
import subprocess, sys

IT = sys.argv[1]
fails = 0
total = 0


def key(code, named, down):
    return bytes([0x33]) + code.to_bytes(4, "little") + bytes([named, down])


def vk(v, ext, down):
    return bytes([0x35]) + v.to_bytes(2, "little") + bytes([ext, down])


def special(c):
    return bytes([0x36, c])


def tap_named(c):
    return [key(c, 1, 1), key(c, 1, 0)]


def tap_uni(c):
    return [key(c, 0, 1), key(c, 0, 0)]


def combo(mods, v, ext=0):  # mods: list of vk
    return [vk(m, 0, 1) for m in mods] + [vk(v, ext, 1), vk(v, ext, 0)] + [vk(m, 0, 0) for m in mods]


CTRL, ALT, SHIFT = 0x11, 0x12, 0x10
# (name, code, mod, expected messages)
cases = [
    ("a", 97, 0, tap_uni(97)),
    ("A (shift)", 65, 2, tap_uni(65)),
    ("a-umlaut (Latin-1 228)", 228, 0, tap_uni(228)),
    ("space -> named SPACE 15", 32, 0, tap_named(15)),
    ("Enter -> KEY_ENTER 2", 13, 0, tap_named(2)),
    ("Backspace -> 1", 8, 0, tap_named(1)),
    ("Tab -> 3", 9, 0, tap_named(3)),
    ("Esc -> 4", 27, 0, tap_named(4)),
    ("Left 0x103 -> 5", 0x103, 0, tap_named(5)),
    ("Right -> 6", 0x104, 0, tap_named(6)),
    ("Up -> 7", 0x101, 0, tap_named(7)),
    ("Down -> 8", 0x102, 0, tap_named(8)),
    ("Del -> 9", 0x109, 0, tap_named(9)),
    ("Home -> 10", 0x105, 0, tap_named(10)),
    ("End -> 11", 0x106, 0, tap_named(11)),
    ("PgUp -> 12", 0x107, 0, tap_named(12)),
    ("PgDn -> 13", 0x108, 0, tap_named(13)),
    ("F1 -> 30", 0x110, 0, tap_named(30)),
    ("F10 -> 39", 0x119, 0, tap_named(39)),
    ("Ctrl+C (code 3)", 3, 0, combo([CTRL], 0x43)),
    ("Ctrl+V (code 22)", 22, 0, combo([CTRL], 0x56)),
    ("Ctrl+Z (code 26)", 26, 0, combo([CTRL], 0x5A)),
    ("Ctrl+H own code", 0x130, 0, combo([CTRL], 0x48)),
    ("Ctrl+N own code", 0x131, 0, combo([CTRL], 0x4E)),
    ("Ctrl+Left (mod 5)", 0x103, 5, combo([CTRL], 0x25, 1)),
    ("Shift+Left (mod 2)", 0x103, 2, combo([SHIFT], 0x25, 1)),
    ("Ctrl+Shift+End (mod 6)", 0x106, 6, combo([CTRL, SHIFT], 0x23, 1)),
    ("Alt+F4 (mod 3)", 0x113, 3, combo([ALT], 0x73)),
    ("Alt+Enter own code", 0x120, 0, combo([ALT], 0x0D)),
    ("Alt+Left own code", 0x121, 0, combo([ALT], 0x25, 1)),
    ("Shift+Tab own code", 0x10B, 0, combo([SHIFT], 0x09)),
    ("Shift+Del own code", 0x10A, 0, combo([SHIFT], 0x2E, 1)),
    ("Ctrl+Alt+Del -> Special CAD", 0x109, 7, [special(1)]),
    ("Ctrl+Alt+Shift+Del -> Special CAD", 0x109, 8, [special(1)]),
    ("Alt+Tab -> Special ALTTAB", 9, 3, [special(4)]),
    ("Ctrl+Tab stays a key (not ALTTAB)", 9, 5, combo([CTRL], 0x09)),
    ("Alt+a", 97, 3, combo([ALT], 0x41)),
    ("Alt+5", 53, 3, combo([ALT], 0x35)),
    ("Ctrl+Alt+q (AltGr as modifiers)", 113, 7, combo([CTRL, ALT], 0x51)),
    ("unknown 0x7777 ignored", 0x7777, 0, []),
    ("NUL ignored", 0, 0, []),
]


def run(args):
    return subprocess.run([IT] + [str(a) for a in args], capture_output=True, text=True, timeout=20).stdout.strip()


for name, code, mod, exp in cases:
    total += 1
    got = run(["key", code, mod])
    want = " ".join(m.hex() for m in exp)
    if got != want:
        fails += 1
        print(f"  FAIL  {name}: got '{got}' want '{want}'")

# pointer: (px, py, box bx by bw bh, remote rw rh, zoom) -> expected
def model(px, py, bx, by, bw, bh, rw, rh, z):
    zw, zh = rw * z // 100, rh * z // 100
    ox = bx + int((bw - zw) / 2)  # truncation toward zero, like Firn's i64 division
    oy = by + int((bh - zh) / 2)
    rx, ry = px - ox, py - oy
    if rx < 0 or ry < 0 or rx >= zw or ry >= zh:
        return "outside"
    f = lambda p, s: 0 if s <= 1 or p <= 0 else (10000 if p >= s - 1 else p * 10000 // (s - 1))
    return f"{f(rx, zw)} {f(ry, zh)}"


ptr = [
    (50, 50, 0, 0, 100, 100, 200, 200, 50),
    (150, 50, 0, 0, 100, 100, 200, 200, 50),
    (0, 0, 0, 0, 100, 100, 200, 200, 50),
    (99, 99, 0, 0, 100, 100, 200, 200, 50),
    (10, 10, 10, 10, 640, 480, 1920, 1080, 33),   # letterbox: image 633 x 356 centred
    (10, 200, 10, 10, 640, 480, 1920, 1080, 33),
    (320, 250, 10, 10, 640, 480, 1920, 1080, 33),
    (5, 5, 0, 0, 640, 480, 640, 480, 100),
    (639, 479, 0, 0, 640, 480, 640, 480, 100),
    (640, 479, 0, 0, 640, 480, 640, 480, 100),
]
for a in ptr:
    total += 1
    got = run(["ptr", *a])
    want = model(*a)
    if got != want:
        fails += 1
        print(f"  FAIL  ptr {a}: got '{got}' want '{want}'")

print(f"INPUTTEST {total - fails}/{total} ok")
sys.exit(1 if fails else 0)
