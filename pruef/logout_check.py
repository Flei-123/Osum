#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    logout_check.py <build_dir> [output_dir] -- sign out with real clicks (P-002).
"""
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from click_driver import Maschine

BUILD = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else "/root/lg-img"
OUT = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 \
    else os.path.join(ROOT, "belege", "logind")
os.makedirs(OUT, exist_ok=True)
SERIAL = os.path.join(OUT, "logout-click.txt")
SOCK = "/tmp/logind-logout.sock"
for path in (SERIAL, SOCK):
    if os.path.exists(path):
        os.unlink(path)

PASSES = [0]
FAILS = [0]
ROWS = []
MENU_WINDOW_SECONDS = 15.0
POWER_ROW_HEIGHT = 28
POWER_PAD = 4
POWER_MENU_WIDTH = 220
POWER_MENU_ROWS = 4
FOOTER_MARGIN = 20
FOOTER_BUTTON = 44
GAP_ABOVE_BUTTON = 4
SIGN_OUT_ROW = 2
MENU_PIXELS_MIN = 5000
PASSWORD = "startkennwort"
IMAGE_SAME_LIMIT = 10.0
IMAGE_CHANGED_MIN = 2000


def say(*parts):
    line = " ".join(str(x) for x in parts)
    print(line, flush=True)
    ROWS.append(line)


def ok(*parts):
    PASSES[0] += 1
    say("  OK   ", *parts)


def bad(*parts):
    FAILS[0] += 1
    say("  FAIL ", *parts)


def read_text():
    try:
        return open(SERIAL, "rb").read().decode("utf-8", "replace")
    except OSError:
        return ""


def windows():
    return re.findall(r"wlib: win id=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)",
                      read_text())


def menu_geometry():
    found = re.findall(r"launcher: geom x=(\d+) y=(\d+) w=(\d+) h=(\d+)",
                       read_text())
    return tuple(int(v) for v in found[-1]) if found else None


def menu_toggled_open(pos, deadline):
    start = time.time()
    while time.time() - start < deadline:
        if "taskbar: startmenue auf" in read_text()[pos:]:
            return True
        time.sleep(0.5)
    return False


def read_pixels(path):
    from PIL import Image
    image = Image.open(path).convert("RGB")
    return image.size, image.load()


def sample_diff(path_a, path_b, box=None):
    size_a, px_a = read_pixels(path_a)
    size_b, px_b = read_pixels(path_b)
    if size_a != size_b:
        return None
    x0, y0, x1, y1 = box or (0, 0, size_a[0], size_a[1])
    total = 0
    differing = 0
    for y in range(y0, y1, 4):
        for x in range(x0, x1, 4):
            total += 1
            if px_a[x, y] != px_b[x, y]:
                differing += 1
    return differing, total


cmdline = ("modfs osum gfx wm wig desk wmshell wmdauer herz crashhalt nopuls "
           "tz=120 usb hidgen nosched noproc nofs fbres=1280x800 "
           "lang=de anmeldung")
accel = ["-accel", "kvm", "-cpu", "host"] if os.access("/dev/kvm", os.W_OK) \
    else ["-accel", "tcg"]
qemu_cmd = (["qemu-system-x86_64"] + accel +
            ["-m", "512", "-smp", "2",
             "-kernel", os.path.join(BUILD, "osum.mb"),
             "-initrd", os.path.join(BUILD, "root.img"),
             "-append", cmdline, "-vga", "std",
             "-device", "qemu-xhci,id=xhci",
             "-device", "usb-mouse", "-device", "usb-kbd",
             "-serial", "file:" + SERIAL,
             "-monitor", "unix:%s,server,nowait" % SOCK,
             "-display", "none", "-no-reboot"])
proc = subprocess.Popen(qemu_cmd,
                        stdout=open(os.path.join(OUT, "logout-qemu.txt"), "w"),
                        stderr=subprocess.STDOUT)
say("== QEMU pid %d, image %s" % (proc.pid, BUILD))


def typed_keys():
    return len(re.findall(r"key: [a-z]", read_text()))


def sign_in(machine):
    for attempt in (1, 2, 3):
        before = typed_keys()
        for ch in PASSWORD:
            machine.key_press(ch)
            time.sleep(0.12)
        time.sleep(1.5)
        arrived = typed_keys() - before
        if arrived != len(PASSWORD):
            say("       attempt %d: only %d of %d keys arrived, clearing field"
                % (attempt, arrived, len(PASSWORD)))
            for _ in range(len(PASSWORD) + 4):
                machine.key_press("backspace")
                time.sleep(0.06)
            time.sleep(1)
            continue
        machine.key_press("ret")
        start = time.time()
        while time.time() - start < 60:
            text = read_text()
            if "glogin: uid=1000" in text:
                return attempt
            if "glogin: abgewiesen" in text[-2000:] \
               or "glogin: rejected" in text[-2000:]:
                break
            time.sleep(0.5)
        if "glogin: uid=1000" in read_text():
            return attempt
        say("       attempt %d: rejected, retrying" % attempt)
        time.sleep(2)
    return 0


try:
    start = time.time()
    while time.time() - start < 180:
        if "glogin: ready" in read_text():
            break
        if proc.poll() is not None:
            bad("QEMU exited early, rc=%s" % proc.returncode)
            raise SystemExit(1)
        time.sleep(0.5)
    if "glogin: ready" in read_text():
        ok("the sign-in screen is ready (after %.0fs)" % (time.time() - start))
    else:
        bad("the sign-in screen did not come up")
        raise SystemExit(1)
    time.sleep(3)
    machine = Maschine(SOCK, 1280, 800)
    machine.photo(os.path.join(OUT, "k-10-login-screen.png"))

    attempt = sign_in(machine)
    if attempt:
        if attempt > 1:
            say("       (on attempt %d, earlier ones lost keys)" % attempt)
        ok("signed in as justin, the desktop runs as uid=1000")
    else:
        bad("sign-in failed")
        say("       " + " / ".join(
            re.findall(r"glogin: [^\n]{0,60}", read_text())[-4:]))
        raise SystemExit(1)
    time.sleep(12)
    machine.photo(os.path.join(OUT, "k-20-desktop.png"))

    pos = len(read_text())
    machine.key_press("meta_l")
    opened = menu_toggled_open(pos, MENU_WINDOW_SECONDS)
    time.sleep(3)
    menu_photo = os.path.join(OUT, "k-30-start-menu.png")
    machine.photo(menu_photo)
    geom = menu_geometry()
    if geom is None:
        bad("the start menu window is not in the report")
        raise SystemExit(1)
    gx, gy, gw, gh = geom
    shown = sample_diff(os.path.join(OUT, "k-20-desktop.png"), menu_photo,
                        (gx, gy, gx + gw, gy + gh))
    if opened and shown is not None and shown[0] >= MENU_PIXELS_MIN:
        ok("the start menu is open ('taskbar: startmenue auf', %d of %d "
           "samples changed)" % shown)
    else:
        bad("the start menu did not open (event %s, picture %s)"
            % (opened, shown))

    rects = re.findall(
        r"launcher: rect id=4 kind=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)",
        read_text())
    if rects:
        rx, ry, rw, rh = (int(v) for v in rects[-1])
        ok("the power button position is reported: %d,%d %dx%d"
           % (rx, ry, rw, rh))
        button_x = gx + rx + rw // 2
        button_y = gy + ry + rh // 2
    else:
        bad("no 'launcher: rect id=4' in the report")
        raise SystemExit(1)
    say("== power button at %d,%d (window %d,%d)" % (button_x, button_y, gx, gy))
    machine.klick_auf(button_x, button_y)
    time.sleep(4)
    machine.photo(os.path.join(OUT, "k-40-power-menu.png"))
    if re.search(r"launcher: power open", read_text()):
        ok("the power menu opened ('launcher: power open')")
    else:
        bad("the power menu did not open")
        raise SystemExit(1)

    menu_height = POWER_MENU_ROWS * POWER_ROW_HEIGHT + 2 * POWER_PAD
    popup_x = gx + gw - FOOTER_MARGIN - POWER_MENU_WIDTH
    popup_y = gy + gh - FOOTER_MARGIN - FOOTER_BUTTON - GAP_ABOVE_BUTTON \
        - menu_height
    px = popup_x + POWER_MENU_WIDTH // 2
    py = popup_y + POWER_PAD + SIGN_OUT_ROW * POWER_ROW_HEIGHT \
        + POWER_ROW_HEIGHT // 2
    say("== menu %d,%d %dx%d" % (popup_x, popup_y, POWER_MENU_WIDTH,
                                  menu_height))
    say("== click on 'sign out' at %d,%d" % (px, py))
    machine.klick_auf(px, py)
    time.sleep(6)

    chosen = re.search(r"launcher: power pick=(\d+)", read_text())
    if chosen and int(chosen.group(1)) != SIGN_OUT_ROW:
        bad("the launcher reported the wrong choice (%s)" % chosen.group(1))
    elif re.search(r"launcher: power pick", read_text()):
        ok("the launcher reported the choice from the power menu")
    else:
        bad("the launcher reports no choice")

    start = time.time()
    while time.time() - start < 60:
        if "logout: login restarted" in read_text():
            break
        time.sleep(0.5)
    text = read_text()
    if "logout: session" in text:
        ok("the kernel got the sign-out wish ('logout: session')")
    else:
        bad("'logout: session' missing -- the wish did not arrive")
        say("       " + " / ".join(re.findall(
            r"(?:launcher: power|logout:)[^\n]{0,50}", text)[-5:]))
    killed = re.findall(r"signal: pid=(\d+) SIGKIL", text)
    counted = re.findall(r"logout: killed n=(\d+)", text)
    if killed:
        ok("the session ended -- %d SIGKILL in the capture (pids %s)"
           % (len(killed), ", ".join(killed)))
        if counted:
            say("       the kernel counts n=%s" % counted[-1])
    elif counted and int(counted[-1]) >= 1:
        ok("the session ended (the kernel counts n=%s)" % counted[-1])
    else:
        bad("no task of the session was ended")

    restarted = re.findall(r"logout: login restarted pid=(\d+)", text)
    starts = len(re.findall(r"start /bin/glogin", text))
    last_rect = len(re.findall(r"glogin: rect id=12", text))
    if restarted:
        ok("the sign-in screen was restarted (pid=%s)" % restarted[-1])
    elif "logout: login" in text and starts >= 2:
        ok("the sign-in screen was restarted ('logout: login' + "
           "'start /bin/glogin' %dx)" % starts)
    elif last_rect >= 2:
        ok("the sign-in screen was restarted ('glogin: rect id=12' %dx, "
           "'start /bin/glogin' %dx)" % (last_rect, starts))
    else:
        bad("'logout: login restarted' missing ('start /bin/glogin' %dx, "
            "'rect id=12' %dx)" % (starts, last_rect))
    ready = len(re.findall(r"glogin: ready", text))
    if last_rect >= 2:
        ok("the sign-in screen rebuilt its controls ('glogin: rect id=12' "
           "%dx, ready %dx)" % (last_rect, ready))
    else:
        bad("the sign-in screen did not return ('rect id=12' %dx, ready %dx)"
            % (last_rect, ready))
    signed_in = len(re.findall(r"glogin: signed in as", text))
    if signed_in <= 1:
        ok("CONTROL: nobody is signed in after the sign-out (%dx)" % signed_in)
    else:
        bad("somebody was signed in again after the sign-out (%dx)" % signed_in)
    time.sleep(3)
    machine.photo(os.path.join(OUT, "k-50-relogin.png"))

    try:
        desk = os.path.join(OUT, "k-20-desktop.png")
        after = os.path.join(OUT, "k-50-relogin.png")
        first = os.path.join(OUT, "k-10-login-screen.png")
        if os.path.exists(desk) and os.path.exists(after):
            result = sample_diff(desk, after)
            if result is None:
                bad("IMAGE: the pictures differ in size")
            elif result[0] >= IMAGE_CHANGED_MIN:
                ok("IMAGE: the screen is a different one (%d samples differ)"
                   % result[0])
            else:
                bad("IMAGE: the screen looks as before (%d differ)"
                    % result[0])
        if os.path.exists(first) and os.path.exists(after):
            result = sample_diff(first, after)
            if result is None:
                bad("IMAGE: the pictures differ in size")
            else:
                percent = 100.0 * result[0] / result[1]
                if percent <= IMAGE_SAME_LIMIT:
                    ok("IMAGE: it is the sign-in screen again -- %d of %d "
                       "samples differ (%.2f %%)"
                       % (result[0], result[1], percent))
                else:
                    bad("IMAGE: the screen is not the sign-in screen "
                        "(%d of %d differ, %.1f %%)"
                        % (result[0], result[1], percent))
        else:
            bad("IMAGE: the pictures are missing")
    except ImportError:
        say("       (PIL missing -- the image comparison is skipped)")

finally:
    try:
        proc.kill()
        proc.wait(timeout=10)
    except Exception:
        pass
    for name in sorted(os.listdir(OUT)):
        if name.startswith("k-") and name.endswith(".ppm"):
            try:
                os.unlink(os.path.join(OUT, name))
            except OSError:
                pass
    open(os.path.join(OUT, "logout-click-findings.txt"), "w").write(
        "\n".join(ROWS) + "\n")

say("")
say("LOGOUT: %d passed, %d failed" % (PASSES[0], FAILS[0]))
sys.exit(1 if FAILS[0] else 0)
