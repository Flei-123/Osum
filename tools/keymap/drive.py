#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/keymap/drive.py -- keyboard engine scenario through QMP (USB keyboard).

    drive.py <qmp-socket> <serial.txt> <outdir> [timeout-seconds]

The image boots with /etc/keyboard.conf = `keyboard.layout=de`. Every step is event driven: a serial line, never a fixed sleep for a result.
Writes `scenes.txt` (key=value, 1 = the step did what the layout promises).
"""
import importlib.util
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("alttab_drive", os.path.join(HERE, "..", "alttab", "drive.py"))
ad = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ad)


class Scene:
    def __init__(self, q, ser, tmo):
        self.q = q
        self.ser = ser
        self.tmo = tmo
        self.facts = []

    def text(self):
        return ad.serial_text(self.ser)

    def keys(self):
        return len(re.findall(r"(?m)^key: ", self.text()))

    def step(self, name, taps, pattern, timeout=None):
        start = len(self.text())
        for t in taps:
            self.q.tap(*t)
            time.sleep(0.25)
        _end, hit = ad.wait_for(self.ser, pattern, start, timeout or self.tmo)
        self.facts.append("%s=%d" % (name, 1 if hit else 0))
        return hit

    def seen(self, name, pattern):
        self.facts.append("%s=%d" % (name, 1 if re.search(pattern, self.text()) else 0))

    def wait_seen(self, name, pattern, timeout):
        end = time.time() + timeout
        while time.time() < end and not re.search(pattern, self.text()):
            time.sleep(0.3)
        self.facts.append("%s=%d" % (name, 1 if re.search(pattern, self.text()) else 0))

    def silent(self, name, taps, wait=1.5):
        before = self.keys()
        for t in taps:
            self.q.tap(*t)
            time.sleep(0.25)
        time.sleep(wait)
        self.facts.append("%s=%d" % (name, 1 if self.keys() == before else 0))

    def exact(self, name, taps, pattern, count):
        before = self.keys()
        start = len(self.text())
        for t in taps:
            self.q.tap(*t)
            time.sleep(0.25)
        ad.wait_for(self.ser, pattern, start, self.tmo)
        time.sleep(0.8)
        ok = re.search(pattern, self.text()[start:]) is not None and self.keys() - before == count
        self.facts.append("%s=%d" % (name, 1 if ok else 0))


def main():
    qmp_path, ser, out = sys.argv[1:4]
    tmo = float(sys.argv[4]) if len(sys.argv) > 4 else 8.0
    q = ad.Qmp(qmp_path)
    ad.wait_for(ser, r"eingabe: ber=", 0, 120)
    time.sleep(1.0)
    q.tap("shift")
    time.sleep(1.0)
    s = Scene(q, ser, tmo)

    s.seen("conf_applied", r"kbdconf: apply de")
    s.wait_seen("tray_shows_de", r"taskbar: text lang [^\n]*t=DEU", 10)
    s.step("altgr_q_at", [("alt_r", "q")], r"key: @")
    s.silent("dead_circumflex_waits", [("grave_accent",)])
    s.step("circumflex_e", [("e",)], r"key: [^\n]* U\+00EA")
    s.silent("dead_acute_waits", [("equal",)])
    s.step("acute_e", [("e",)], r"key: [^\n]* U\+00E9")
    s.silent("dead_grave_waits", [("shift", "equal")])
    s.exact("grave_space_is_grave", [("spc",)], r"key: `", 1)
    s.silent("dead_then_x_waits", [("grave_accent",)])
    s.exact("dead_then_x_two_keys", [("x",)], r"key: \^\s+key: x", 2)
    s.silent("dead_twice_waits", [("grave_accent",)])
    s.exact("dead_twice_accent", [("grave_accent",)], r"key: \^", 1)
    s.silent("dead_diaeresis_waits", [("alt_r", "bracket_left")])
    s.step("diaeresis_u", [("u",)], r"key: [^\n]* U\+00FC")
    s.step("caps_a", [("caps_lock",), ("a",)], r"key: A")
    s.step("caps_umlaut", [("apostrophe",)], r"key: [^\n]* U\+00C4")
    s.step("caps_off", [("caps_lock",), ("a",)], r"key: a")
    s.silent("compose_armed", [("ctrl_r",)])
    s.silent("compose_first", [("o",)])
    s.step("compose_o_c", [("c",)], r"key: [^\n]* U\+00A9")
    s.silent("menu_armed", [("menu",)])
    s.silent("menu_compose_first", [("o",)])
    s.step("menu_compose_o_c", [("c",)], r"key: [^\n]* U\+00A9")
    s.exact("iso_key_less", [("less",)], r"key: <", 1)
    s.step("combo_next_uk", [("ctrl", "alt", "l")], r"kbd: layout=uk")
    s.step("combo_next_fr", [("ctrl", "alt", "l")], r"kbd: layout=fr")
    s.step("azerty_q_is_a", [("q",)], r"key: a")
    s.step("azerty_a_is_q", [("a",)], r"key: q")
    s.step("azerty_2_is_eacute", [("2",)], r"key: [^\n]* U\+00E9")
    s.wait_seen("tray_shows_fr", r"taskbar: text lang [^\n]*t=FR", 12)
    s.step("win_space_next_es", [("meta_l", "spc")], r"kbd: layout=es")
    s.step("es_ntilde", [("semicolon",)], r"key: [^\n]* U\+00F1")
    s.wait_seen("tray_shows_es", r"taskbar: text lang [^\n]*t=ES", 12)
    with open(os.path.join(out, "scenes.txt"), "w") as fh:
        fh.write("\n".join(s.facts) + "\n")
    print("\n".join(s.facts))


if __name__ == "__main__":
    main()
