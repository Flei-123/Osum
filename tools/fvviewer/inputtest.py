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
    ("ASCII tilde stays unicode", 126, 0, tap_uni(126)),
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
    ("Ctrl+Shift+Q: shift+ctrl on a letter", 17, 6, combo([CTRL, SHIFT], 0x51)),
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
# scaling sweep: viewer area (window sizes) x host resolutions, zoom as fit_image() computes it (min of both axes, 5..400 %)
def fit_zoom(bw, bh, iw, ih):
    z = bw * 100 // iw
    zy = bh * 100 // ih
    if zy < z:
        z = zy
    return max(5, min(400, z))


for (bw, bh) in ((836, 530), (640, 400), (400, 300), (1800, 1000)):
    for (rw, rh) in ((640, 480), (1920, 1080), (2560, 1440), (3440, 1440), (800, 1280), (1366, 768)):
        z = fit_zoom(bw, bh, rw, rh)
        zw, zh = rw * z // 100, rh * z // 100
        ox = 12 + int((bw - zw) / 2)
        oy = 40 + int((bh - zh) / 2)
        # first / last picture pixel, the pixel just outside on each side, and the middle
        for px, py in ((ox, oy), (ox + zw - 1, oy + zh - 1), (ox - 1, oy), (ox, oy - 1), (ox + zw, oy), (ox, oy + zh),
                       (ox + zw // 2, oy + zh // 2)):
            ptr.append((px, py, 12, 40, bw, bh, rw, rh, z))
for a in ptr:
    total += 1
    got = run(["ptr", *a])
    want = model(*a)
    if got != want:
        fails += 1
        print(f"  FAIL  ptr {a}: got '{got}' want '{want}'")


def seq(items):
    out = subprocess.run([IT, "seq"] + [f"{c}:{m}" for c, m in items], capture_output=True, text=True, timeout=20).stdout.split("\n")
    return out[:len(items)]


def hx(msgs):
    return " ".join(m.hex() for m in msgs)


# UTF-8: the OrientOS keyboard sends the OCTETS of a character one key event at a time (decoder state is kept)
utf = [
    ("a-umlaut C3 A4 -> U+00E4", [(0xC3, 0), (0xA4, 0)], [hx([]), hx(tap_uni(0xE4))]),
    ("sharp-s C3 9F -> U+00DF", [(0xC3, 0), (0x9F, 0)], [hx([]), hx(tap_uni(0xDF))]),
    ("euro E2 82 AC -> U+20AC (AltGr+E)", [(0xE2, 0), (0x82, 0), (0xAC, 0)], [hx([]), hx([]), hx(tap_uni(0x20AC))]),
    ("emoji F0 9F 98 80 -> U+1F600", [(0xF0, 0), (0x9F, 0), (0x98, 0), (0x80, 0)], [hx([]), hx([]), hx([]), hx(tap_uni(0x1F600))]),
    ("AltGr+Q arrives as @ (64)", [(64, 0)], [hx(tap_uni(64))]),
    ("AltGr+7 arrives as { (123)", [(123, 0)], [hx(tap_uni(123))]),
    ("shift+a-umlaut: shift only stays unicode", [(0xC3, 0), (0x84, 2)], [hx([]), hx(tap_uni(0xC4))]),
    ("Ctrl+a-umlaut: modifier + unicode", [(0xC3, 0), (0xA4, 5)], [hx([]), hx([vk(CTRL, 0, 1), key(0xE4, 0, 1), key(0xE4, 0, 0), vk(CTRL, 0, 0)])]),
    ("lone continuation 0xA4 dropped", [(0xA4, 0), (97, 0)], [hx([]), hx(tap_uni(97))]),
    ("broken sequence: lead then ASCII", [(0xC3, 0), (97, 0)], [hx([]), hx(tap_uni(97))]),
    ("lead then lead: second one wins", [(0xE2, 0), (0xC3, 0), (0xA4, 0)], [hx([]), hx([]), hx(tap_uni(0xE4))]),
    ("overlong C0 80 refused", [(0xC0, 0), (0x80, 0), (97, 0)], [hx([]), hx([]), hx(tap_uni(97))]),
    ("overlong E0 80 80 refused", [(0xE0, 0), (0x80, 0), (0x80, 0)], [hx([]), hx([]), hx([])]),
    ("surrogate ED A0 80 refused", [(0xED, 0), (0xA0, 0), (0x80, 0)], [hx([]), hx([]), hx([])]),
    ("above U+10FFFF F4 90 80 80 refused", [(0xF4, 0), (0x90, 0), (0x80, 0), (0x80, 0)], [hx([]), hx([]), hx([]), hx([])]),
    ("named key during an open sequence", [(0xC3, 0), (13, 0)], [hx([]), hx(tap_named(2))]),
    ("repeat: 5x z", [(122, 0)] * 5, [hx(tap_uni(122))] * 5),
]
for name, items, exp in utf:
    total += 1
    got = seq(items)
    if got != exp:
        fails += 1
        print(f"  FAIL  utf8 {name}: got {got} want {exp}")

# reconnect rules == Rust viewer (src/viewer.rs backoff/next_retry/Fail::retryable); E_* ids of lib/fv/client.fi
E = dict(TCP=1, TLS=2, UPGRADE=3, RELAY=4, AUTH=5, DENIED=6, PROTO=7, IO=8, MEM=9, GONE=10, CRYPTO=11, DNS=12)
BO = [1, 2, 4, 8, 16, 30, 30, 30]
for n, w in enumerate(BO, 1):
    total += 1
    got = subprocess.run([IT, "backoff", str(n)], capture_output=True, text=True, timeout=20).stdout.strip()
    if got != str(w):
        fails += 1
        print(f"  FAIL  backoff({n}): got {got} want {w}")
# (err, ever_live, ask, attempt) -> seconds ; 0 = no retry
rules = []
for att in range(0, 8):
    w = BO[att] if att < 6 else 0
    rules.append(("IO", 1, 0, att, w))
    rules.append(("GONE", 1, 0, att, w))
    rules.append(("TCP", 1, 0, att, w))
    rules.append(("TLS", 1, 0, att, w))
    rules.append(("UPGRADE", 1, 0, att, w))
for e in ("AUTH", "DENIED", "PROTO", "CRYPTO", "MEM"):
    rules.append((e, 1, 0, 0, 0))               # never, even in a live session
for e in ("IO", "GONE", "TCP", "RELAY", "DNS"):
    rules.append((e, 0, 0, 0, 0))               # no session was ever live -> error at once
    rules.append((e, 1, 1, 0, 0))               # ask mode never reconnects silently
rules.append(("RELAY", 1, 0, 0, 1))              # relay "offline" text is checked in the gate (kind needs the text)
for e, live, ask, att, want in rules:
    if e == "RELAY":
        continue                                  # text-dependent: kind_of(RELAY, text) is covered by the gate
    total += 1
    got = subprocess.run([IT, "retry", str(E[e]), str(live), str(ask), str(att)], capture_output=True, text=True, timeout=20).stdout.strip()
    if got != str(want):
        fails += 1
        print(f"  FAIL  retry({e}, live={live}, ask={ask}, attempt={att}): got {got} want {want}")

# clipboard cut: never tear a UTF-8 sequence
trims = [("41", 1), ("c3a4", 2), ("c3", 0), ("41c3", 1), ("e282ac", 3), ("e282", 0), ("41e282", 1), ("f09f9880", 4), ("f09f98", 0), ("c3a4e2", 2), ("80", 1)]
for h, want in trims:
    total += 1
    got = subprocess.run([IT, "trim", h], capture_output=True, text=True, timeout=20).stdout.strip()
    if got != str(want):
        fails += 1
        print(f"  FAIL  utf8_trim({h}): got {got} want {want}")

print(f"INPUTTEST {total - fails}/{total} ok")
sys.exit(1 if fails else 0)
