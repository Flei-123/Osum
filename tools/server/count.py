#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/server/count.py -- WIE VIELE STELLEN IM KERNEL AUF DIE GRAFIK
GREIFEN.

Die Aufgabe der Runde SERVERBUILD verlangt diese Zahl ausdruecklich:
sie sagt, wie sauber der Schnitt ist. Vor der Runde waren es 745
Stellen in acht Dateien, danach null -- ausser in `kernel/gfx/gfx.fi`, und
das ist die Naht selbst.

GEZAEHLT WIRD NUR CODE. Kommentare fliegen raus, bevor gesucht wird;
in diesem Repo steht in den Kommentaren mehr ueber `fb.fi` als in
manchen Modulen an Code, und eine Zahl, die Prosa mitzaehlt, ist keine.

    count.py <kernelverzeichnis> [--je-datei]

Ohne `--je-datei` kommt genau eine Zahl heraus, damit ein Testlaeufer
sie ohne `sed` weiterverwenden kann.
"""
import collections
import os
import re
import sys

GRAFIK = ["fb", "wm", "wig", "font", "ttf", "tile", "vmode", "ansi", "ps2m"]
# Die Dateien, DENEN die Grafik gehoert: die Module selbst, die Naht und
# die beiden Ausbauten aus `kmain.fi` und `sys.fi`.
EIGEN = set(g + ".fi" for g in GRAFIK) | {
    "gfx.fi", "gfx-aus.fi", "kgui.fi", "sysgui.fi",
    # MERGE-2 18 (customres): der gespeicherte Bildmodus. Sie ist selbst
    # eine Grafikdatei und wird bei --gui off mit geloescht.
    "dispsave.fi",
    # RUNDE ROTABSCHNITTE: `zeiger.fi` stand in `build-kernel.sh` schon
    # in GFX_DATEIEN (Zeile 213) und wird bei `--gui off` mit geloescht
    # -- nur hier fehlte sie. Eine Datei, die der Bau als Grafikdatei
    # behandelt, muss auch hier eine sein, sonst zaehlt der Pruefer eine
    # Stelle, die es im Serverbau gar nicht gibt.
    "zeiger.fi",
    # A-039 (24.09.2026): `drv/gpu/vgpu.fi`, der virtio-gpu-Treiber,
    # rechnet auf dem Rahmenpuffer (`fb.back`, `fb.rect_take`, ...) und
    # wird NUR aus Grafikdateien geholt (fb.fi, gfx.fi, wm.fi, kgui.fi).
    # GEMESSEN: im Serverabbild 0 Symbole `vgpu__`, im GUI-Abbild 64.
    # Die 6 "Stellen" waren also Grafik in einer Grafikdatei, und der
    # Serverbau loescht sie seitdem ausdruecklich (GFX_DATEIEN).
    "vgpu.fi",
    # RUNDE ROTABSCHNITTE: `shot.fi` (Runde FEEDBACK) ist das
    # Bildschirmfoto VON INNEN und liest dafuer den Rahmenpuffer -- 15
    # Stellen `fb.*`. Sie gehoert damit zur Grafik wie die zwoelf davor.
    #
    # GEMESSEN und nicht behauptet: im Serverabbild steht KEIN einziges
    # ihrer Symbole.
    #
    #     nm /tmp/rot-srv.mb.elf | grep -c '_F0\.shot__'   ->  0
    #     nm /tmp/rot-srv.mb.elf | grep -c '_F0\.fb__'     ->  0
    #     nm /tmp/rot-srv.mb.elf | grep -c '_F0\.gfx__'    -> 70
    #
    # Der Grund: `shot.fi` wird NUR von `kgui.fi` und `sysgui.fi`
    # eingebunden, und beide loescht `--gui off`. Der Binder nimmt sie
    # damit gar nicht erst mit. Die Zusage dieses Abschnitts -- "kein
    # Modul ausser der Naht greift noch auf die Grafik zu" -- gilt also
    # im ABBILD, und das ist die Ebene, auf der sie etwas heisst.
    "shot.fi",
    # RUNDE ROADMAP-5 (K-008): `kernel/app/drucke.fi` is a ring-3 PROGRAM
    # (--profile=app, its own ELF, /bin/drucke), not a kernel module. It
    # rasterises text with the TrueType reader (`ttf.*`, `raster.*`) --
    # that is its job, and none of it is linked into any kernel image:
    # nothing in kernel/ imports it, build-kernel.sh does not name it.
    "drucke.fi",
    # RUNDE FUI-TEXT (24.09.2026): `kernel/user/fuiglyph.fi` is RING-3
    # code as well -- fUi's font engine (`lib/font/ttf.fi`, `raster.fi`)
    # rasterising the glyphs for `wlibc`. Only ring-3 programs import it
    # (wlib.fi, desktop.fi, taskbar.fi); nothing in the kernel image does,
    # build-kernel.sh does not name it. Its 18 "places" are `ttf.*` calls
    # into lib/, not the kernel's frame buffer. Same case as drucke.fi.
    "fuiglyph.fi"}
MUSTER = re.compile(
    r"(?<![A-Za-z0-9_.])(" + "|".join(GRAFIK) + r")\.([A-Za-z_][A-Za-z0-9_]*)")


def ohne_kommentare(text):
    aus = []
    for zeile in text.split("\n"):
        i = zeile.find("//")
        aus.append(zeile[:i] if i >= 0 else zeile)
    return "\n".join(aus)


def ohne_importe(text):
    """`import font.metrics` ist kein Zugriff auf die Grafik.

    RUNDE ROTABSCHNITTE.  `kernel/user/fuib.fi:72` stand mit genau einer
    Stelle in der Liste, und diese Stelle war die Zeile `import
    font.metrics` -- der Name eines MODULS aus `lib/`, nicht der Aufruf
    von `kernel/gfx/font.fi`.  Eine Einbindung sagt nichts darueber, ob
    jemand den Rahmenpuffer anfasst; sie nennt nur, woher ein Name
    kommt.  Gezaehlt werden soll der ZUGRIFF.
    """
    aus = []
    for zeile in text.split("\n"):
        if re.match(r"\s*import\s", zeile):
            aus.append("")
        else:
            aus.append(zeile)
    return "\n".join(aus)


def zaehle(wurzel):
    je_datei = collections.Counter()
    namen = collections.Counter()
    for pfad, _, dateien in os.walk(wurzel):
        for d in sorted(dateien):
            if not d.endswith(".fi") or d in EIGEN:
                continue
            p = os.path.join(pfad, d)
            with open(p, "rb") as f:
                roh = f.read().decode("utf8", "replace")
            treffer = MUSTER.findall(ohne_importe(ohne_kommentare(roh)))
            if treffer:
                je_datei[os.path.relpath(p, wurzel)] = len(treffer)
                for a, b in treffer:
                    namen[a + "." + b] += 1
    return je_datei, namen


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    wurzel = sys.argv[1]
    if not os.path.isdir(wurzel):
        print(-1)
        return 1
    je_datei, namen = zaehle(wurzel)
    if "--je-datei" in sys.argv:
        for k, v in je_datei.most_common():
            print("  %-26s %d" % (k, v))
        print("  SUMME %d Stellen, %d verschiedene Funktionen, in %d Dateien"
              % (sum(je_datei.values()), len(namen), len(je_datei)))
    else:
        print(sum(je_datei.values()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
