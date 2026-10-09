#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/wayland/genkeys.py -- the key tables of wayd, GENERATED from libxkbcommon.

    python3 tools/wayland/genkeys.py > kernel/user/wl_keytab.fi        (the Firn tables)
    python3 tools/wayland/genkeys.py --keymaps <dir>                    (keymap-us.xkb, keymap-de.xkb)

The window server hands wayd a CHARACTER ("a", "A", "@", an arrow code). A Wayland client wants a Linux evdev key code and the
modifier state, and it turns both into a symbol with the xkb keymap wayd sends it. So the reverse table "character -> (evdev
code, modifiers)" has to come from the SAME keymap the client gets, or the two would drift apart. This script asks the real
libxkbcommon of the host (the very library GTK, Qt and weston-terminal use) for both: the keymap text and, for every key and
every level, the character it produces. Nothing here is typed in by hand.

Output of the table mode: for each layout ("us", "de") a function `<layout>_find(cp) -> code | mods << 16` (0 = no such key)
where mods is 1 = Shift, 4 = AltGr (Level3). Control is NOT in the table: the window server delivers Ctrl+letter as 1..26.
The xkb modifier masks the keymap uses (Shift, Control, Mod5 = AltGr) are written as constants, read from the keymap.
"""
import ctypes
import ctypes.util
import os
import sys

LIB = ctypes.CDLL(ctypes.util.find_library("xkbcommon") or "libxkbcommon.so.0")

LIB.xkb_context_new.restype = ctypes.c_void_p
LIB.xkb_context_new.argtypes = [ctypes.c_int]


class Names(ctypes.Structure):
    _fields_ = [("rules", ctypes.c_char_p), ("model", ctypes.c_char_p),
                ("layout", ctypes.c_char_p), ("variant", ctypes.c_char_p),
                ("options", ctypes.c_char_p)]


LIB.xkb_keymap_new_from_names.restype = ctypes.c_void_p
LIB.xkb_keymap_new_from_names.argtypes = [ctypes.c_void_p, ctypes.POINTER(Names), ctypes.c_int]
LIB.xkb_keymap_new_from_string.restype = ctypes.c_void_p
LIB.xkb_keymap_new_from_string.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int, ctypes.c_int]
LIB.xkb_keymap_get_as_string.restype = ctypes.c_void_p
LIB.xkb_keymap_get_as_string.argtypes = [ctypes.c_void_p, ctypes.c_int]
LIB.xkb_keymap_mod_get_index.restype = ctypes.c_uint
LIB.xkb_keymap_mod_get_index.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
LIB.xkb_state_new.restype = ctypes.c_void_p
LIB.xkb_state_new.argtypes = [ctypes.c_void_p]
LIB.xkb_state_update_mask.restype = ctypes.c_int
LIB.xkb_state_update_mask.argtypes = [ctypes.c_void_p] + [ctypes.c_uint] * 6
LIB.xkb_state_key_get_utf32.restype = ctypes.c_uint32
LIB.xkb_state_key_get_utf32.argtypes = [ctypes.c_void_p, ctypes.c_uint]
LIB.xkb_state_unref.argtypes = [ctypes.c_void_p]
libc = ctypes.CDLL(None)
libc.free.argtypes = [ctypes.c_void_p]


def keymap_of(layout):
    ctx = LIB.xkb_context_new(0)
    names = Names(b"evdev", b"pc105", layout.encode(), None, None)
    km = LIB.xkb_keymap_new_from_names(ctx, ctypes.byref(names), 0)
    if not km:
        sys.exit("libxkbcommon cannot compile layout " + layout)
    return ctx, km


def keymap_text(km):
    p = LIB.xkb_keymap_get_as_string(km, 1)  # XKB_KEYMAP_FORMAT_TEXT_V1
    s = ctypes.string_at(p)
    libc.free(p)
    return s


def mod_mask(km, name):
    i = LIB.xkb_keymap_mod_get_index(km, name.encode())
    if i == 0xFFFFFFFF:
        sys.exit("modifier %s missing" % name)
    return 1 << i


def table_of(km):
    shift, ctrl, level3 = mod_mask(km, "Shift"), mod_mask(km, "Control"), mod_mask(km, "Mod5")
    alt = mod_mask(km, "Mod1")
    st = LIB.xkb_state_new(km)
    best = {}
    # fewest modifiers first, then the lowest key code
    combos = [(0, 0), (shift, 1), (level3, 4), (shift | level3, 5)]
    for mask, bits in combos:
        for ev in range(1, 128):
            LIB.xkb_state_update_mask(st, mask, 0, 0, 0, 0, 0)
            cp = LIB.xkb_state_key_get_utf32(st, ev + 8)
            if cp < 32 or cp == 127:
                continue
            key = (bin(bits).count("1"), ev)
            if cp not in best or key < best[cp][0]:
                best[cp] = (key, ev | (bits << 16))
    LIB.xkb_state_unref(st)
    return shift, ctrl, level3, alt, {cp: v[1] for cp, v in best.items()}


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "--keymaps":
        out = sys.argv[2]
        os.makedirs(out, exist_ok=True)
        for lay in ("us", "de"):
            ctx, km = keymap_of(lay)
            txt = keymap_text(km)
            # the text must compile again, as a client does it (from a string, no files)
            km2 = LIB.xkb_keymap_new_from_string(ctx, txt, 1, 0)
            if not km2:
                sys.exit("keymap %s does not compile from its own text" % lay)
            with open("%s/keymap-%s.xkb" % (out, lay), "wb") as f:
                f.write(txt)
            sys.stderr.write("keymap-%s.xkb: %d octets\n" % (lay, len(txt)))
        return 0

    w = sys.stdout.write
    w("// SPDX-License-Identifier: GPL-2.0-only\n")
    w("// kernel/user/wl_keytab.fi -- GENERATED by tools/wayland/genkeys.py from libxkbcommon. DO NOT EDIT BY HAND.\n")
    w("//\n// character (Unicode code point) -> evdev key code | modifiers << 16, for the layouts `us` and `de` of the\n")
    w("// keymaps wayd sends (rules evdev, model pc105). modifiers: 1 = Shift, 4 = AltGr. 0 = the layout has no such key.\n")
    w("// The xkb masks of the modifiers are those of the keymap (read from it, not assumed).\n\n")
    w("profile kernel\n\n")
    consts = []
    funcs = []
    for lay in ("us", "de"):
        ctx, km = keymap_of(lay)
        shift, ctrl, level3, alt, tab = table_of(km)
        consts.append((shift, ctrl, level3, alt))
        funcs.append((lay, tab))
        sys.stderr.write("%s: %d characters, Shift=%#x Control=%#x AltGr(Mod5)=%#x Alt(Mod1)=%#x\n" % (lay, len(tab), shift, ctrl, level3, alt))
    if consts[0] != consts[1]:
        sys.exit("the layouts disagree on the modifier masks")
    w("export { XKB_MOD_SHIFT, XKB_MOD_CTRL, XKB_MOD_ALTGR, XKB_MOD_ALT, us_find, de_find }\n\n")
    w("const XKB_MOD_SHIFT: u64 = %d\nconst XKB_MOD_CTRL: u64 = %d\nconst XKB_MOD_ALTGR: u64 = %d\nconst XKB_MOD_ALT: u64 = %d\n\n" % consts[0])
    for lay, tab in funcs:
        asc = [tab.get(c, 0) for c in range(32, 127)]
        w("fn %s_find(cp: u64) -> u64 {\n" % lay)
        w("    if cp >= 32 && cp < 127 {\n")
        w("        var codes: [u8; 95] = [%s]\n" % ", ".join(str(v & 0xFFFF) for v in asc))
        w("        var mods: [u8; 95] = [%s]\n" % ", ".join(str(v >> 16) for v in asc))
        w("        let i: u64 = cp - 32\n")
        w("        let code: u64 = codes[i as usize] as u64\n")
        w("        if code == 0 {\n            return 0\n        }\n")
        w("        return code | ((mods[i as usize] as u64) << 16)\n")
        w("    }\n")
        for cp in sorted(c for c in tab if c >= 127):
            w("    if cp == %d {\n        return %d\n    }\n" % (cp, tab[cp]))
        w("    return 0\n}\n\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
