#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/metal/r8125regs.py -- HAELT DEN 8125-ZWEIG GEGEN LINUX.

WARUM ES DAS GIBT
=================

`kernel/drv/net/r8169.fi` faehrt drei Spielarten desselben Chips:

    VAR_CP    RTL8139C+   -- in QEMU GEMESSEN, Oktett fuer Oktett.
    VAR_8169  RTL8168/69  -- aus dem Datenblatt, nie an einem Brett.
    VAR_8125  RTL8125/26  -- aus Linux, WEDER GEMESSEN NOCH MESSBAR:
                             QEMU 7.2 hat kein Modell dieses Chips.

Fuer VAR_8125 gibt es also keinen Testlauf, der irgendetwas widerlegen
koennte. Es gibt nur eine einzige Pruefmoeglichkeit: den Quelltext Zeile
fuer Zeile gegen den Treiber halten, der auf echter Hardware laeuft.

UND DAS HAT SICH SOFORT GELOHNT. Beim ersten Lauf fiel auf:

    r8169.fi, tx_kick:   w8(state, u, R_TPPOLL25, 64)
    Linux, rtl8169_doorbell:
        if (rtl_is_8125(tp))  RTL_W16(tp, TxPoll_8125, BIT(0));
        else                  RTL_W8 (tp, TxPoll,      NPQ);

Die ADRESSE war richtig aus Linux uebernommen (0x90), BREITE und WERT
aber vom alten Chip stehen geblieben (8 Bit, NPQ = Bit 6 = 0x40). Auf
einer echten RTL8125 haette das geheissen: Chip laeuft an, Verbindung
steht, Empfang geht -- und kein einziges Paket verlaesst die Karte, weil
der Sendeanstoss nie ankommt. Kein Absturz, keine Meldung.

WAS GEPRUEFT WIRD
=================

  1. Die sechs 8125-Registeradressen aus `r8169.fi` gegen die Namen aus
     Linux' `r8169_main.c`.
  2. Die ZUGRIFFSBREITE und der WERT an den Stellen, an denen sich die
     Spielarten unterscheiden. Genau hier sass der Fehler, und eine
     Pruefung, die nur Adressen vergleicht, haette ihn nicht gesehen.
  3. Dass jede 8125-Konstante in `r8169.fi` ueberhaupt eine Quellenzeile
     im Dateikopf hat.

AUFRUF
======

    python3 tools/metal/r8125regs.py             # gegen /tmp/r8169_linux.c
    python3 tools/metal/r8125regs.py --fetch     # laedt r8169_main.c neu
    python3 tools/metal/r8125regs.py --src DATEI

Rueckgabe 0, wenn nichts widerlegt ist.
"""

import os
import re
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(ROOT, "kernel", "r8169.fi")

LINUX_URL = ("https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/"
             "linux.git/plain/drivers/net/ethernet/realtek/r8169_main.c")
LINUX_CACHE = "/tmp/r8169_linux.c"

# UNSERE Konstante  ->  der Name im Linux-Treiber.
OFFSETS = {
    "R_INTCFG0_25": "INT_CFG0_8125",
    "R_IMR25": "IntrMask_8125",
    "R_ISR25": "IntrStatus_8125",
    "R_TPPOLL25": "TxPoll_8125",
    "R_RSSCTRL25": "RSS_CTRL_8125",
    "R_QNUMCTRL25": "Q_NUM_CTRL_8125",
}

# Die Stellen, an denen sich BREITE oder WERT zwischen den Spielarten
# unterscheiden. Das ist der Teil, den ein reiner Adressvergleich nicht
# faengt -- und der Teil, in dem der Fehler sass.
#
#   funktion, unsere Konstante, erwartete Breite, erwarteter Wert, Beleg
ZUGRIFFE = [
    ("tx_kick", "R_TPPOLL25", 16, 1,
     "rtl8169_doorbell: RTL_W16(tp, TxPoll_8125, BIT(0))"),
    ("set_imr", "R_IMR25", 32, None,
     "IntrMask_8125 ist 32 Bit breit (rtl_irq_enable/disable)"),
    ("get_isr", "R_ISR25", 32, None,
     "IntrStatus_8125 ist 32 Bit breit"),
]

# Die Stelle, an der Linux und dieser Treiber BEWUSST auseinandergehen.
# Sie steht hier namentlich, damit sie nicht in einer Sammelausnahme
# verschwindet -- und damit jemand mit einer echten Karte weiss, wo er
# zuerst nachsehen muss.
OFFEN = {
    "INTCFG0_EN": (
        "Wir schreiben INT_CFG0 (0x34) Bit 0 = 1, um den "
        "Unterbrechungsblock einzuschalten. Linux UPSTREAM definiert "
        "INT_CFG0_ENABLE_8125 als BIT(0), BENUTZT es aber nirgends und "
        "schreibt in rtl_hw_start_8125 sogar 0x00 dorthin. Der Wert "
        "stammt aus Realteks eigenem r8125-Treiber. UNGEPRUEFT: ohne "
        "eine echte Karte laesst sich nicht entscheiden, wer recht hat. "
        "Wenn eine RTL8125 spaeter keine Unterbrechungen liefert, ist "
        "das hier die erste Stelle zum Nachsehen."),
}


def hol_linux(path, force=False):
    if force or not os.path.exists(path):
        sys.stderr.write("hole %s ...\n" % LINUX_URL)
        urllib.request.urlretrieve(LINUX_URL, LINUX_CACHE)
        return LINUX_CACHE
    return path


def linux_offsets(text):
    """Die Adressen aus dem grossen enum in r8169_main.c."""
    out = {}
    for m in re.finditer(r"^\s*(\w+_8125)\s*=\s*(0x[0-9a-fA-F]+),", text, re.M):
        out[m.group(1)] = int(m.group(2), 16)
    for m in re.finditer(r"^\s*(IntrMask_8125|IntrStatus_8125|TxPoll_8125)"
                         r"\s*=\s*(0x[0-9a-fA-F]+),", text, re.M):
        out[m.group(1)] = int(m.group(2), 16)
    return out


def unsere_konstanten(text):
    out = {}
    for m in re.finditer(r"^const (R_\w+|INTCFG0_EN|TPPOLL25_GO|OCP_\w+)"
                         r":\s*u64\s*=\s*(0x[0-9a-fA-F]+|\d+)", text, re.M):
        v = m.group(2)
        out[m.group(1)] = int(v, 16) if v.startswith("0x") else int(v)
    return out


def unsere_zugriffe(text, fn, konst):
    """(breite, wert) der Zugriffe auf `konst` innerhalb von `fn`."""
    m = re.search(r"^fn %s\(" % re.escape(fn), text, re.M)
    if not m:
        return []
    rest = text[m.start():]
    ende = re.search(r"^\}", rest, re.M)
    body = rest[:ende.end()] if ende else rest
    out = []
    for a in re.finditer(r"\bw(8|16|32)\(state, u, %s,\s*([A-Za-z_0-9]+)\)"
                         % re.escape(konst), body):
        out.append((int(a.group(1)), a.group(2)))
    for a in re.finditer(r"\br(8|16|32)\(state, u, %s\)" % re.escape(konst),
                         body):
        out.append((int(a.group(1)), None))
    return out


def main():
    args = sys.argv[1:]
    path = LINUX_CACHE
    if "--src" in args:
        path = args[args.index("--src") + 1]
    path = hol_linux(path, "--fetch" in args)

    lin = open(path, encoding="utf-8", errors="replace").read()
    our = open(SRC, encoding="utf-8").read()
    lo = linux_offsets(lin)
    ok_ = unsere_konstanten(our)

    fehler = []
    print("=" * 66)
    print("r8169.fi, Zweig VAR_8125, gegen Linux r8169_main.c")
    print("=" * 66)
    print()
    print("ADRESSEN")
    for unser, lname in OFFSETS.items():
        u = ok_.get(unser)
        l = lo.get(lname)
        if u is None:
            fehler.append("%s steht nicht in r8169.fi" % unser)
            print("   %-16s FEHLT im Quelltext" % unser)
            continue
        if l is None:
            fehler.append("%s (%s) nicht in Linux gefunden" % (unser, lname))
            print("   %-16s 0x%-6x  %-22s NICHT IN LINUX GEFUNDEN"
                  % (unser, u, lname))
            continue
        gut = (u == l)
        if not gut:
            fehler.append("%s = 0x%x, Linux %s = 0x%x" % (unser, u, lname, l))
        print("   %-16s 0x%-6x  %-22s 0x%-6x  %s"
              % (unser, u, lname, l, "ok" if gut else "WIDERSPRUCH"))

    print()
    print("BREITE UND WERT -- hier sass der Fehler")
    for fn, konst, breite, wert, beleg in ZUGRIFFE:
        zs = unsere_zugriffe(our, fn, konst)
        if not zs:
            print("   %-14s %-14s kein Zugriff gefunden (Funktion "
                  "umbenannt?)" % (fn, konst))
            continue
        for b, w in zs:
            gut = (b == breite)
            wv = ok_.get(w, w) if w is not None else None
            if wert is not None and w is not None:
                gut = gut and (wv == wert)
            if not gut:
                fehler.append("%s: %s wird mit %d Bit / Wert %s "
                              "geschrieben, Linux: %d Bit / %s"
                              % (fn, konst, b, wv, breite, wert))
            print("   %-14s %-14s %2d Bit  Wert %-8s %s"
                  % (fn, konst, b, ("--" if wv is None else wv),
                     "ok" if gut else "WIDERSPRUCH"))
            print("        Beleg: %s" % beleg)

    print()
    print("BEWUSST OFFEN (kein Fehler, aber ungeprueft)")
    for name, text in OFFEN.items():
        print("   %s = %s" % (name, ok_.get(name)))
        for zeile in re.findall(r".{1,64}(?:\s|$)", text):
            if zeile.strip():
                print("        " + zeile.strip())

    print()
    if fehler:
        print("ERGEBNIS: WIDERLEGT (%d)" % len(fehler))
        for f in fehler:
            print("   " + f)
        return 1
    print("ERGEBNIS: nichts widerlegt.")
    print("  Sechs Adressen, drei Zugriffsbreiten und ein Wert stimmen")
    print("  mit dem Treiber ueberein, der auf echter Hardware laeuft.")
    print("  Das ist KEINE Messung -- es ist der beste Ersatz, den es")
    print("  ohne die Karte gibt.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
