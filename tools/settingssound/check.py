#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re, sys

serial = sys.argv[1]
raw = open(serial, "rb").read().decode("latin1")
CTL = re.compile(r"^settings: controls page=(\d+) n=(\d+)$", re.M)
SND = re.compile(r"^settings: sound (\d) v=(\d+) rc=(\d+)", re.M)
RES = re.compile(r"^settings: results n=(\d+) top=(\d+)((?: r\d+=\d+)*)", re.M)
RECT = re.compile(r"settings: rect name=(\w+) ")
SOUND_PAGE = 29


def judge(txt):
    res = []

    def ok(c, m):
        res.append((bool(c), m))

    ctl = [int(m.group(2)) for m in CTL.finditer(txt) if int(m.group(1)) == SOUND_PAGE]
    ok(ctl, "Sound page built (page=29)")
    ok(ctl and max(ctl) == 3, "Sound page has 3 controls with a sound card (%s)" % ctl)
    names = set(RECT.findall(txt))
    for n in ("svol", "smute", "smic"):
        ok(n in names, "control rect %s reported" % n)
    snd = [(int(m.group(1)), int(m.group(2)), int(m.group(3))) for m in SND.finditer(txt)]
    vol = [s for s in snd if s[0] == 0]
    mute = [s for s in snd if s[0] == 1]
    mic = [s for s in snd if s[0] == 2]
    ok(vol and 0 < vol[-1][1] < 100, "volume slider click sets a value between 0 and 100 (%s)" % vol[-1:])
    ok(vol and vol[-1][2] == 0, "volume syscall result 0")
    ok(mute and mute[-1][1] == 1 and mute[-1][2] == 0, "speaker mute on, syscall result 0 (%s)" % mute[-1:])
    ok(mic and mic[-1][1] == 1 and mic[-1][2] == 0, "microphone mute on, syscall result 0 (%s)" % mic[-1:])
    rs = [(int(m.group(1)), int(m.group(2)), m.group(3)) for m in RES.finditer(txt)]
    hit = [r for r in rs if r[0] > 0]
    ok(hit, "search lists results")
    if hit:
        n, top, rest = hit[-1]
        ok(top == SOUND_PAGE, "top result of 'sound' is the Sound page (top=%d)" % top)
        ok(" r0=%d" % SOUND_PAGE in rest, "first row of the result list is the Sound page (%s)" % rest.strip())
        ok(n <= 12, "result list within its cap (%d)" % n)
    ok(not re.search(r"ABSTURZ|EXCEPTION", txt), "no crash lines")
    return res


def main():
    res = judge(raw)
    for c, m in res:
        print("  %s  %s" % ("OK  " if c else "FAIL", m))
    bad = sum(1 for c, _ in res if not c)
    ok_n = len(res) - bad
    doctored = {
        "no sound lines": "\n".join(l for l in raw.splitlines() if not l.startswith("settings: sound ")),
        "mute result failed": SND.sub(lambda m: "settings: sound %s v=%s rc=1" % (m.group(1), m.group(2)), raw),
        "no results": "\n".join(l for l in raw.splitlines() if not l.startswith("settings: results ")),
        "other top": re.sub(r"(settings: results n=\d+) top=\d+", r"\1 top=3", raw),
        "no volume rect": re.sub(r"settings: rect name=svol ", "settings: rect name=zzz ", raw),
    }
    for name, d in doctored.items():
        if all(c for c, _ in judge(d)):
            print("  FAIL  counter-proof not red: %s" % name)
            bad += 1
        else:
            print("  OK    counter-proof red: %s" % name)
            ok_n += 1
    print("SETTINGSSOUND: %d passed, %d failed" % (ok_n, bad))
    sys.exit(1 if bad else 0)


main()
