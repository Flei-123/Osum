# SPDX-License-Identifier: GPL-2.0-only
import ctypes
import ctypes.util
import os
import sys

SHIFT_EVDEV = 42
ALTGR_EVDEV = 100
CAPS_EVDEV = 58
SCAN_TO_EVDEV = {0x73: 89}
DEAD_FIRST = 0xFE50
DEAD_LAST = 0xFE8C
MULTI_KEY = 0xFF20
COMPOSE_LOCALE = b"en_US.UTF-8"


class _Names(ctypes.Structure):
    _fields_ = [(n, ctypes.c_char_p) for n in ("rules", "model", "layout", "variant", "options")]


def _load():
    lib = ctypes.CDLL(ctypes.util.find_library("xkbcommon"))
    lib.xkb_context_new.restype = ctypes.c_void_p
    lib.xkb_keymap_new_from_names.restype = ctypes.c_void_p
    lib.xkb_keymap_new_from_names.argtypes = [ctypes.c_void_p, ctypes.POINTER(_Names), ctypes.c_int]
    lib.xkb_state_new.restype = ctypes.c_void_p
    lib.xkb_state_new.argtypes = [ctypes.c_void_p]
    lib.xkb_state_unref.argtypes = [ctypes.c_void_p]
    lib.xkb_state_update_key.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_int]
    lib.xkb_state_key_get_one_sym.restype = ctypes.c_uint32
    lib.xkb_state_key_get_one_sym.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    lib.xkb_keysym_to_utf32.restype = ctypes.c_uint32
    lib.xkb_keysym_to_utf32.argtypes = [ctypes.c_uint32]
    lib.xkb_utf32_to_keysym.restype = ctypes.c_uint32
    lib.xkb_utf32_to_keysym.argtypes = [ctypes.c_uint32]
    lib.xkb_keysym_from_name.restype = ctypes.c_uint32
    lib.xkb_keysym_from_name.argtypes = [ctypes.c_char_p, ctypes.c_int]
    lib.xkb_compose_table_new_from_locale.restype = ctypes.c_void_p
    lib.xkb_compose_table_new_from_locale.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
    lib.xkb_compose_state_new.restype = ctypes.c_void_p
    lib.xkb_compose_state_new.argtypes = [ctypes.c_void_p, ctypes.c_int]
    lib.xkb_compose_state_reset.argtypes = [ctypes.c_void_p]
    lib.xkb_compose_state_feed.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    lib.xkb_compose_state_feed.restype = ctypes.c_int
    lib.xkb_compose_state_get_status.argtypes = [ctypes.c_void_p]
    lib.xkb_compose_state_get_status.restype = ctypes.c_int
    lib.xkb_compose_state_get_utf8.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t]
    return lib


LIB = _load()
CTX = LIB.xkb_context_new(0)
COMPOSED = 2
CANCELLED = 3


def keysym_cp(sym):
    if DEAD_FIRST <= sym <= DEAD_LAST:
        return 0
    cp = LIB.xkb_keysym_to_utf32(sym)
    if cp < 32 or cp == 127:
        return 0
    return cp


def keysym_named(name):
    return LIB.xkb_keysym_from_name(name.encode(), 0)


def cp_keysym(cp):
    return LIB.xkb_utf32_to_keysym(cp)


class Keymap:
    def __init__(self, layout, variant=""):
        names = _Names(b"evdev", b"pc105", layout.encode(), variant.encode(), b"")
        self.km = LIB.xkb_keymap_new_from_names(CTX, ctypes.byref(names), 0)
        if not self.km:
            sys.exit("xkb: cannot compile layout %s(%s)" % (layout, variant))

    def sym(self, scan, shift, altgr, caps):
        ev = SCAN_TO_EVDEV.get(scan, scan)
        st = LIB.xkb_state_new(self.km)
        if caps:
            LIB.xkb_state_update_key(st, CAPS_EVDEV + 8, 1)
            LIB.xkb_state_update_key(st, CAPS_EVDEV + 8, 0)
        if shift:
            LIB.xkb_state_update_key(st, SHIFT_EVDEV + 8, 1)
        if altgr:
            LIB.xkb_state_update_key(st, ALTGR_EVDEV + 8, 1)
        s = LIB.xkb_state_key_get_one_sym(st, ev + 8)
        LIB.xkb_state_unref(st)
        return s


class Compose:
    def __init__(self):
        table = LIB.xkb_compose_table_new_from_locale(CTX, COMPOSE_LOCALE, 0)
        if not table:
            sys.exit("xkb: no compose table")
        self.state = LIB.xkb_compose_state_new(table, 0)

    def run(self, syms):
        LIB.xkb_compose_state_reset(self.state)
        for s in syms:
            LIB.xkb_compose_state_feed(self.state, s)
        status = LIB.xkb_compose_state_get_status(self.state)
        buf = ctypes.create_string_buffer(64)
        LIB.xkb_compose_state_get_utf8(self.state, buf, 64)
        return status, buf.value.decode("utf-8", "replace")

    def single(self, syms):
        status, text = self.run(syms)
        if status == COMPOSED and len(text) == 1:
            return ord(text)
        return 0


def compose_file():
    for base in (os.environ.get("XLOCALEDIR", ""), "/usr/share/X11/locale"):
        path = os.path.join(base, COMPOSE_LOCALE.decode(), "Compose")
        if base and os.path.exists(path):
            return path
    sys.exit("xkb: Compose file not found")
