#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/wayland/keycheck.py <us|de> < wlin-log-lines

What a real client does with the events wayd sent: it feeds the modifier events and the key events into libxkbcommon (the keymap of
the layout, compiled from the same text wayd sent) and asks for the keysym of every key press. Reads `wlin[X]: ...` lines on stdin
(lines `mods ... depressed=N` and `key ... key=N state=S`) and prints the keysyms as the client would see them, in order:

    syms: a A 1 exclam Ctrl+c Up

Shift, Control and AltGr key presses themselves are not listed. An `us` or `de` layout is compiled by name (rules evdev, model pc105).
"""
import ctypes
import ctypes.util
import re
import sys

lib = ctypes.CDLL(ctypes.util.find_library("xkbcommon") or "libxkbcommon.so.0")
lib.xkb_context_new.restype = ctypes.c_void_p
lib.xkb_context_new.argtypes = [ctypes.c_int]


class Names(ctypes.Structure):
    _fields_ = [("rules", ctypes.c_char_p), ("model", ctypes.c_char_p), ("layout", ctypes.c_char_p),
                ("variant", ctypes.c_char_p), ("options", ctypes.c_char_p)]


lib.xkb_keymap_new_from_names.restype = ctypes.c_void_p
lib.xkb_keymap_new_from_names.argtypes = [ctypes.c_void_p, ctypes.POINTER(Names), ctypes.c_int]
lib.xkb_state_new.restype = ctypes.c_void_p
lib.xkb_state_new.argtypes = [ctypes.c_void_p]
lib.xkb_state_update_mask.argtypes = [ctypes.c_void_p] + [ctypes.c_uint] * 6
lib.xkb_state_key_get_one_sym.restype = ctypes.c_uint32
lib.xkb_state_key_get_one_sym.argtypes = [ctypes.c_void_p, ctypes.c_uint]
lib.xkb_keysym_get_name.restype = ctypes.c_int
lib.xkb_keysym_get_name.argtypes = [ctypes.c_uint32, ctypes.c_char_p, ctypes.c_size_t]


def main():
    lay = sys.argv[1] if len(sys.argv) > 1 else "us"
    ctx = lib.xkb_context_new(0)
    km = lib.xkb_keymap_new_from_names(ctx, ctypes.byref(Names(b"evdev", b"pc105", lay.encode(), None, None)), 0)
    if not km:
        print("no keymap")
        return 1
    st = lib.xkb_state_new(km)
    out = []
    mods = 0
    for line in sys.stdin:
        m = re.search(r"mods serial=\d+ depressed=(\d+)", line)
        if m:
            mods = int(m.group(1))
            lib.xkb_state_update_mask(st, mods, 0, 0, 0, 0, 0)
            continue
        m = re.search(r"\bkey serial=\d+ key=(\d+) state=(\d)", line)
        if m and m.group(2) == "1":
            sym = lib.xkb_state_key_get_one_sym(st, int(m.group(1)) + 8)
            buf = ctypes.create_string_buffer(64)
            lib.xkb_keysym_get_name(sym, buf, 64)
            name = buf.value.decode()
            if name.startswith(("Shift_", "Control_", "ISO_Level3", "Alt_", "Super_")):
                continue
            out.append(("Ctrl+" if mods & 4 else "") + name)
    print("syms: " + " ".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
