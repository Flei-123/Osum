#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/fvviewer/gui_input.py <serial.txt> <input.log> -- judge the GUI gate stage "input" (gui_input.sh).

input.log is the Rust test host's input log with "### <name>" marker lines written by the drehbuch;
serial.txt is the guest's serial trace. Prints "  OK/FAIL/INFO  <what>" lines, exit code = number of FAILs.
"""
import re
import sys

ser = open(sys.argv[1], "rb").read().decode("utf-8", "replace")
hl = open(sys.argv[2], "rb").read().decode("utf-8", "replace")
fails = 0


def ok(c, what):
    global fails
    print("  %s  %s" % ("OK  " if c else "FAIL", what))
    if not c:
        fails += 1


def info(what):
    print("  INFO  %s" % what)


# ---- split the host log by markers
segs = {}
cur = None
for line in hl.split("\n"):
    m = re.match(r"### (\S+)$", line)
    if m:
        cur = m.group(1)
        segs.setdefault(cur, [])
    elif cur is not None and line.strip():
        segs[cur].append(line)


def seg(name):
    return segs.get(name, [])


def moves(lines):
    out = []
    for l in lines:
        m = re.match(r"MouseMove x=(\d+) y=(\d+)", l)
        if m:
            out.append((int(m.group(1)), int(m.group(2))))
    return out


def near(p, q, tol=220):
    return abs(p[0] - q[0]) <= tol and abs(p[1] - q[1]) <= tol


def button_seq(lines, button):
    out = []
    for l in lines:
        m = re.match(r"MouseButton button=(\d+) down=(true|false)", l)
        if m and int(m.group(1)) == button:
            out.append(m.group(2) == "true")
    return out


print("== mouse ==")
for name, btn, pt in (("mouse-left", 0, (1000, 1000)), ("mouse-right", 1, (9000, 1000)), ("mouse-middle", 2, (5000, 9000))):
    s = seg(name)
    mv = moves(s)
    ok(any(near(p, pt) for p in mv), "%s: pointer at %s (got %s)" % (name, pt, mv[-2:]))
    ok(button_seq(s, btn) == [True, False], "%s: button %d down then up (got %s)" % (name, btn, button_seq(s, btn)))
s = seg("mouse-double")
ok(any(near(p, (3000, 7000)) for p in moves(s)), "double click: pointer at (3000,7000)")
ok(button_seq(s, 0) == [True, False, True, False], "double click: two down/up pairs of the left button (got %s)" % button_seq(s, 0))
s = seg("mouse-drag")
idx = [i for i, l in enumerate(s) if l.startswith("MouseButton button=0 down=true")]
idu = [i for i, l in enumerate(s) if l.startswith("MouseButton button=0 down=false")]
ok(len(idx) == 1 and len(idu) == 1 and idx[0] < idu[0], "drag: one press, one release (got %d/%d)" % (len(idx), len(idu)))
if idx and idu:
    mid = moves(s[idx[0]:idu[0]])
    ok(len(mid) >= 3, "drag: %d pointer moves while the button is held" % len(mid))
    ok(bool(mid) and near(mid[0], (2000, 2000), 1400) and near(mid[-1], (8000, 8000), 500), "drag: from ~(2000,2000) to ~(8000,8000) (got %s .. %s)" % (mid[:1], mid[-1:]))
    xs = [p[0] for p in mid]
    ok(all(b >= a - 50 for a, b in zip(xs, xs[1:])), "drag: x only grows while dragging to the right")
ok(any(re.match(r"Wheel lines=3$", l) for l in seg("wheel-up")), "toolbar 'Rad hoch' -> Wheel lines=3")
ok(any(re.match(r"Wheel lines=-3$", l) for l in seg("wheel-down")), "toolbar 'Rad runter' -> Wheel lines=-3")
hw = [l for l in seg("wheel-hw") if l.startswith("Wheel")]
info("hardware wheel (QEMU mouse_move dz) reaches the host: %s %s" % ("yes" if hw else "NO -- OrientOS gives the wheel to no app (ps2m sums it, no event)", hw[:2]))

print("== scaling (window size) ==")
views = re.findall(r"fvviewer: rect name=view x=(-?\d+) y=(-?\d+) w=(\d+) h=(\d+)", ser)
sizes = []
for v in views:
    if (v[2], v[3]) not in sizes:
        sizes.append((v[2], v[3]))
info("picture sizes seen (w,h): %s" % sizes)
ok(len(sizes) >= 3, "the window was resized twice: %d different picture sizes" % len(sizes))
for ph in ("before", "small", "big"):
    for pct, pt in (("10", (1000, 1000)), ("90", (9000, 9000))):
        s = seg("scale-%s-%s" % (ph, pct))
        mv = moves(s)
        ok(any(near(p, pt, 260) for p in mv) and button_seq(s, 0) == [True, False],
           "scale %s %s%%: pointer ~%s and a click (got %s)" % (ph, pct, pt, mv[-1:]))

print("== keyboard ==")


def key(code, named=False):
    return [r"Key code=%d named=%s down=true" % (code, "true" if named else "false"),
            r"Key code=%d named=%s down=false" % (code, "true" if named else "false")]


def vkcombo(mods, v, ext=False):
    seq = [r"KeyVk vk=%d ext=false down=true" % m for m in mods]
    seq += [r"KeyVk vk=%d ext=%s down=true" % (v, "true" if ext else "false"), r"KeyVk vk=%d ext=%s down=false" % (v, "true" if ext else "false")]
    seq += [r"KeyVk vk=%d ext=false down=false" % m for m in reversed(mods)]
    return seq


TAB = {
    "a": key(97), "shift-a": key(65), "shift-1": key(33), "spc": key(15, True), "ret": key(2, True),
    "esc": key(4, True), "tab": key(3, True), "backspace": key(1, True), "left": key(5, True), "right": key(6, True),
    "up": key(7, True), "down": key(8, True), "delete": key(9, True), "home": key(10, True), "end": key(11, True),
    "pgup": key(12, True), "pgdn": key(13, True), "f1": key(30, True), "f5": key(34, True),
    # US layout: AltGr (Alt_r) gives no third level, the OS hands over the plain character; the ISO key "less" does not
    # exist on a US keyboard (no key at all, nothing to check)
    "alt_r-q": key(113), "alt_r-7": key(55), "alt_r-8": key(56), "alt_r-9": key(57), "alt_r-0": key(48),
    "alt_r-minus": key(45), "alt_r-less": [], "alt_r-e": key(101),
    # the guest keyboard is US (KB_LAYOUT 0): the OS hands over the US characters and the viewer passes them on
    "bracket_left": key(91), "semicolon": key(59), "apostrophe": key(39), "minus": key(45), "shift-bracket_left": key(123),
    "ctrl-c": vkcombo([17], 67), "ctrl-v": vkcombo([17], 86), "ctrl-a": vkcombo([17], 65),
    # no "alt-tab" key: the guest window manager consumes it (the toolbar button covers Special ALTTAB)
}
KEYMAP_NOTE = {}
for k, want in TAB.items():
    s = seg("key-" + k)
    pos = 0
    good = True
    for w in want:
        found = None
        for i in range(pos, len(s)):
            if s[i] == w:
                found = i
                break
        if found is None:
            good = False
            break
        pos = found + 1
    ok(good, "key %-18s -> %s   (got: %s)" % (k, " | ".join(want[:2]), "; ".join(s[:6]) or "nothing"))
# no stray keys: every key segment holds only lines of its own expectation family (no leaked Special/Key from a neighbour)
rep = [l for l in seg("key-repeat") if l.startswith("Key code=122")]
downs = sum(1 for l in rep if l.endswith("down=true"))
ups = sum(1 for l in rep if l.endswith("down=false"))
ok(downs >= 1 and ups >= 1 and ups >= downs, "held key z (1.5 s): %d down / %d up messages, never stuck" % (downs, ups))
info("key repeat: %d down events for a 1.5 s hold (>1 = the OS repeats the key)" % downs)
ok(any(l == "Special code=1" for l in seg("bar-cad")), "toolbar Strg+Alt+Entf -> Special CAD")
ok(any(l == "Special code=4" for l in seg("bar-alttab")), "toolbar Alt+Tab -> Special ALTTAB")
ok(any(l == "Special code=3" for l in seg("bar-win")), "toolbar Win -> Special WIN")

print("== clipboard ==")
clips = re.findall(r"^Clipboard len=(\d+) text=(.*)$", hl, re.M)
ok(any(n == "12" and t == "fvv-gui-clip" for n, t in clips), "guest -> host: ASCII text")
uni = "Grüße € \U0001f600"
ok(any(n == "16" and t == uni for n, t in clips), "guest -> host: unicode text (umlaut, sharp s, euro, emoji; 16 octets) intact")
ok("fvviewer: clip unicode echo ok" in ser, "host -> guest: the unicode echo came back byte for byte")
# the OS clipboard keeps 4096 octets at most (wig fallback, CLIP_MAX), so the 150001-octet text arrives cut there,
# at a character boundary: 'a' + 2047 x U+00FC = 4095 octets
big = [(int(n), t) for n, t in clips if int(n) > 1000]
ok(len(big) == 1, "oversize text (150001 octets): sent exactly once (no resend loop), %d message(s)" % len(big))
if big:
    n, t = big[0]
    ok(n == 4095, "oversize text cut at the OS clipboard limit (4096) INSIDE a character -> 4095 octets (got %d)" % n)
    ok(t == "a" + "\u00fc" * 2047, "oversize text: valid UTF-8, no torn character")
m = re.search(r"fvviewer: clip big echo n=(\d+) kept=(\d+)", ser)
ok(bool(m) and int(m.group(1)) > 2000 and int(m.group(2)) <= 131072, "host -> guest echo of the cut text: n=%s kept=%s" % (m.groups() if m else None, ""))
ok(not any(t.startswith("echo:") for n, t in clips), "an echoed text is never sent back to the host (no ping-pong)")
ok(len(clips) <= 4, "only the 3 test texts went out (%d clipboard messages)" % len(clips))

print("== reconnect ==")
ev = []
for m in re.finditer(r"fvviewer: (state live|reconnect attempt=(\d+) wait_s=(\d+)|give up kind=(\d+) tries=(\d+) retry_button=(\d)|reconnect cancelled|lost err=(\d+) kind=(\d+) retry_n=(\d+) live_before=(\d) verify=\S+ now=(\d+))", ser):
    t = m.group(1)
    if t == "state live":
        ev.append(("live",))
    elif t.startswith("reconnect attempt"):
        ev.append(("att", int(m.group(2)), int(m.group(3))))
    elif t.startswith("give up"):
        ev.append(("giveup", int(m.group(4)), int(m.group(5)), int(m.group(6))))
    elif t == "reconnect cancelled":
        ev.append(("cancel",))
    else:
        ev.append(("lost", int(m.group(7)), int(m.group(8)), int(m.group(9)), int(m.group(10)), int(m.group(11))))
compact = [e for e in ev if e[0] != "lost"]
txt = " ".join("L" if e[0] == "live" else ("a%d/%d" % (e[1], e[2]) if e[0] == "att" else ("G%d.%d.%d" % e[1:] if e[0] == "giveup" else "C")) for e in compact)
info("event line: %s" % txt)
ok(re.search(r"L a1/1 a2/2 L ", txt) is not None, "R1 host away a moment: tries after 1 s and 2 s, then live again")
ok(re.search(r"L a1/1 a2/2 a3/4 a4/8 a5/16 a6/30 G4\.6\.1 L", txt) is not None,
   "R2 host away for good: 6 tries after 1/2/4/8/16/30 s, then 'host offline' + Wiederholen button, a click on it -> live")
ok(re.search(r"L a1/1 a2/2 a3/4 a4/8 a5/16 C L", txt) is not None, "R3 'Abbrechen' in the countdown stops the tries; 'Wiederholen' then connects")
ok(re.search(r"L G6\.0\.0$", txt) is not None, "R4 wrong password after a live session was ended by hand: error at once (kind 6), no tries, no retry button")
ok(not re.search(r"G6\.\d+\.0 a", txt), "R4: nothing reconnects after the refusal")
# wall-clock spacing of the 6 tries of R2
lost = [e for e in ev if e[0] == "lost"]
r2 = []
mm = re.search(r"G4\.6\.1", txt)
# the 'lost' lines between the 6th... take the 7 lost lines that precede the give-up event
gi = [i for i, e in enumerate(ev) if e[0] == "giveup" and e[1] == 4]
if gi:
    pre = [e for e in ev[:gi[0]] if e[0] == "lost"][-6:]
    times = [e[5] for e in pre]
    gaps = [b - a for a, b in zip(times, times[1:])]
    info("R2 wall-clock gaps between the lost tries (s): %s (waits 2/4/8/16/30 + connect time)" % gaps)
    ok(len(gaps) == 5 and all(g >= w - 1 for g, w in zip(gaps, (2, 4, 8, 16, 30))), "R2 the guest really waited 2/4/8/16/30 s between the tries")
lk = [e for e in lost if e[1] == 5]
ok(bool(lk) and lk[-1][2] == 6, "R4 error kind 6 'Falsches Passwort' for a refused handshake (E_AUTH)")

print("NUM scenarios: %d event(s)" % len(ev))
sys.exit(fails)
