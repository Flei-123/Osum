#!/usr/bin/env python3
"""tools/kernel/karte.py -- DIE SPEICHERKARTE VON `kdata` MECHANISCH PRUEFEN.

Der Kernel hat EINEN zusammenhaengenden Datenbereich (`kernel/boot.s`,
Symbol `kdata`, KDATA_SIZE Oktette), und jede Runde nimmt sich daraus
Seiten: die Aufgabentabelle, die Seitentabellen, das PCI-Geraeteverzeichnis,
die NVMe-Warteschlangen, die Deskriptoren, die Signale, die Terminals, der
Rahmenpuffer-Zustand samt Zeichensatz.  Wer sich welche Seite nimmt, steht
als `const ..._OFF: u64 = 0x....` im Quelltext -- verteilt ueber sechs
Dateien.

DAS IST DIE STELLE, AN DER DIESES PROJEKT VIERMAL DENSELBEN FEHLER GEMACHT
HAT, und dreimal stand er hinterher als Kommentar in `kstate.fi`:

  Runde K4  legte `exec`-Argumente auf 0x10000 -- dort lag schon das
            PCI-Geraeteverzeichnis aus Runde K2.
  Runde K5  legte die Kernregister auf 0x12000 -- dort lagen schon die
            Zaehler von Runde K2.
  Runde K6  legte das Arbeitsverzeichnis auf 0x1C000 -- dort lagen schon
            die Skalare von Runde K5.
  Runde K7  legte den Rahmenpuffer-Zustand und den ZEICHENSATZ auf
            0x2F000; Runde K9 legte die Signaltabelle auf dieselbe
            Adresse.  Beide Zweige waren FUER SICH gruen -- die Dateien
            ueberschnitten sich nicht, nur die Adressen.  Nach dem
            Verschmelzen loeschte der Signalblock der Aufgabe 1 die
            Oktette 0x300..0x600 des Zeichensatzes, also die Glyphen
            0x40..0x6F: '@' bis 'o'.  Auf dem Schirm blieben Ziffern und
            Satzzeichen stehen, Buchstaben verschwanden.

Ein Textverschmelzer kann so etwas nicht sehen: die Kollision steht in
keiner gemeinsamen Zeile.  Also rechnet dieses Programm sie aus.

Verwendung:
    python3 tools/kernel/karte.py [kernelverzeichnis]

Ausgabe: eine Zeile je Bereich (nur mit -v), am Ende die Zahl der Bereiche
und der Kollisionen.  Rueckgabe 0, wenn sich nichts ueberschneidet und
alles in KDATA_SIZE passt.
"""
import os
import re
import sys


# Ein Bereich: (Name, Datei, Ausdruck fuer den Anfang, Ausdruck fuer die
# Groesse).  Beides sind Ausdruecke ueber KONSTANTEN AUS DEM QUELLTEXT --
# hier steht keine Zahl, die nicht auch dort steht.  Wer eine Konstante
# aendert, aendert damit diese Karte mit; wer einen Bereich hinzufuegt,
# ohne ihn hier einzutragen, faellt beim naechsten Punkt auf: die Summe
# der Bereiche wird gegen die Liste der `_OFF`-Konstanten gehalten.
BEREICHE = [
    ("IDT",        "kstate.fi", "IDT_OFF",        "0x1000"),
    ("BITMAP",     "kstate.fi", "BITMAP_OFF",     "BITMAP_BYTES"),
    ("PT",         "kstate.fi", "PT_OFF",         "0x2000"),
    ("TASK",       "kstate.fi", "TASK_OFF",       "TASK_BYTES * MAX_TASKS"),
    ("BLOCK",      "kstate.fi", "BLOCK_OFF",      "BLOCK_MAX"),
    ("NAME",       "kstate.fi", "NAME_OFF",       "NAME_MAX"),
    ("FS",         "kstate.fi", "FS_OFF",         "FS_MAX"),
    ("ELF",        "kstate.fi", "ELF_OFF",        "ELF_MAX"),
    ("PCI_TABLE",  "pci.fi",    "TABLE_OFF",      "0x2000"),
    ("PCI_SCALARS","pci.fi",    "K2_SCALARS",     "0x2000"),
    ("NVME_ASQ",   "nvme.fi",   "ASQ_OFF",        "0x1000"),
    ("NVME_ACQ",   "nvme.fi",   "ACQ_OFF",        "0x1000"),
    ("NVME_IOSQ",  "nvme.fi",   "IOSQ_OFF",       "0x1000"),
    ("NVME_IOCQ",  "nvme.fi",   "IOCQ_OFF",       "0x1000"),
    ("NVME_ID",    "nvme.fi",   "ID_OFF",         "0x1000"),
    ("NVME_BUF_A", "nvme.fi",   "BUF_A",          "0x1000"),
    ("NVME_BUF_B", "nvme.fi",   "BUF_B",          "0x1000"),
    ("CPU",        "kstate.fi", "CPU_OFF",        "CPU_BYTES * MAX_CPUS"),
    ("LOCK",       "kstate.fi", "LOCK_OFF",       "LOCK_BYTES * LOCK_COUNT"),
    ("TCPU",       "kstate.fi", "TCPU_OFF",       "TCPU_BYTES * MAX_TASKS"),
    ("SMP",        "kstate.fi", "SMP_OFF",        "SMP_MAX"),
    ("OFILE",      "kstate.fi", "OFILE_OFF",      "OFILE_MAX"),
    ("FDTAB",      "kstate.fi", "FDTAB_OFF",      "FDTAB_MAX"),
    ("CTX",        "kstate.fi", "CTX_OFF",        "CTX_MAX"),
    ("PIPEBUF",    "kstate.fi", "PIPEBUF_OFF",    "PIPEBUF_MAX"),
    ("PIPEHDR",    "kstate.fi", "PIPEHDR_OFF",    "PIPEHDR_MAX"),
    ("TRACE",      "kstate.fi", "TRACE_OFF",      "TRACE_MAX"),
    ("CONSOLE",    "kstate.fi", "CONSOLE_OFF",    "CONSOLE_MAX"),
    ("EARG",       "kstate.fi", "EARG_OFF",       "EARG_MAX"),
    ("LOAD",       "kstate.fi", "LOAD_OFF",       "LOAD_MAX"),
    ("UIO",        "kstate.fi", "UIO_OFF",        "UIO_MAX"),
    ("CAP",        "kstate.fi", "CAP_OFF",        "CAP_MAX"),
    ("CAP_NONCE",  "kstate.fi", "CAP_NONCE_OFF",  "CAP_NONCE_MAX"),
    ("SIG",        "kstate.fi", "SIG_OFF",        "SIGCTX_OFF - SIG_OFF"),
    ("SIGCTX",     "kstate.fi", "SIGCTX_OFF",     "SIGCTX_BYTES * MAX_TASKS"),
    ("TTY",        "kstate.fi", "TTY_OFF",        "TTY_MAX"),
    ("RAND",       "kstate.fi", "RAND_OFF",       "RAND_MAX"),
    # RUNDE K7B: der Rahmenpuffer-Zustand samt Zeichensatz.  Er stand bis
    # zu dieser Runde als einziger Bereich NICHT in `kstate.fi`, sondern
    # nur in `fb.fi` -- und genau deshalb ging er bei K9 unter.
    ("FB",         "kstate.fi", "FB_OFF",         "FB_MAX"),
    # RUNDE K10: die Oberflaeche.  Sie liegt in den beiden Luecken, die
    # Runde K7B als frei ausgewiesen hat -- und sie steht HIER, weil
    # genau das der Fehler war, an dem Runde K7 gescheitert ist.
    ("MOUSE",      "kstate.fi", "MOUSE_OFF",      "MOUSE_MAX"),
    ("WM",         "kstate.fi", "WM_OFF",         "WM_MAX"),
    ("TTF",        "kstate.fi", "TTF_OFF",        "TTF_MAX"),
]

# `_OFF`-Konstanten, die KEINE Bereiche in `kdata` sind -- Offsets
# innerhalb eines anderen Puffers oder innerhalb von Geraetespeicher.
# Wer hier etwas eintraegt, sagt damit ausdruecklich: das ist kein Stueck
# `kdata`.  Alles andere MUSS in BEREICHE stehen.
KEINE_KDATA = {
    ("fb.fi", "FB_OFF"),        # Spiegel von kstate.FB_OFF, s. u.
    ("fb.fi", "FONT_OFF"),      # liegt IN FB_OFF
    ("inet.fi", "SOCK_OFF"),    # Offsets im Netzbereich von netsvc.fi
    ("inet.fi", "ARP_OFF"),
    ("inet.fi", "ICMP_OFF"),
    ("virtio.fi", "RXD_OFF"),   # Offsets im DMA-Bereich der Karte
    ("virtio.fi", "RXA_OFF"),
    ("virtio.fi", "RXU_OFF"),
    ("virtio.fi", "TXD_OFF"),
    ("virtio.fi", "TXA_OFF"),
    ("virtio.fi", "TXU_OFF"),
    ("virtio.fi", "RXB_OFF"),
    ("virtio.fi", "TXB_OFF"),
    ("pci.fi", "K2_OFF"),       # derselbe Wert wie TABLE_OFF
    ("ttf.fi", "A_HEAP"),       # Versatz IM Glyphenspeicher, nicht kdata
    ("wm.fi", "W_OFF"),         # Versatz IN der Fenstertafel
    ("virtio.fi", "C_QNOTIFY_OFF"),  # ein Register im Konfigurationsraum
}


def konstanten(pfad):
    """Alle `const NAME: u64 = <ausdruck>` einer Firn-Datei."""
    quelle = open(pfad, "r", encoding="utf-8").read()
    werte = {}
    for name, rest in re.findall(
            r"^const ([A-Za-z_0-9]+): u64 = (.+)$", quelle, re.M):
        rest = rest.split("//")[0].strip()
        werte[name] = rest
    return werte


def wert(werte, ausdruck, tiefe=0):
    """Einen Ausdruck ueber Konstanten ausrechnen (nur + - * und Zahlen)."""
    if tiefe > 8:
        raise ValueError("Konstanten laufen im Kreis: %s" % ausdruck)
    t = ausdruck.strip()
    if re.fullmatch(r"(0x[0-9A-Fa-f]+|\d+)", t):
        return int(t, 0)
    if re.fullmatch(r"[A-Za-z_0-9]+", t):
        if t not in werte:
            raise ValueError("unbekannte Konstante %s" % t)
        return wert(werte, werte[t], tiefe + 1)
    if not re.fullmatch(r"[A-Za-z_0-9 +\-*()x]+", t):
        raise ValueError("kein rechenbarer Ausdruck: %s" % ausdruck)
    ersetzt = re.sub(r"[A-Za-z_][A-Za-z_0-9]*",
                     lambda m: str(wert(werte, m.group(0), tiefe + 1)), t)
    return int(eval(ersetzt, {"__builtins__": {}}, {}))  # noqa: S307


def main():
    kdir = sys.argv[1] if len(sys.argv) > 1 else "kernel"
    laut = "-v" in sys.argv

    dateien = {}
    for d in ("kstate.fi", "pci.fi", "nvme.fi", "fb.fi", "inet.fi",
              "virtio.fi"):
        p = os.path.join(kdir, d)
        if os.path.exists(p):
            dateien[d] = konstanten(p)

    kdata = wert(dateien["kstate.fi"], "KDATA_SIZE")

    # 1. Alles ausrechnen.
    stuecke = []
    for name, datei, anf, gr in BEREICHE:
        w = dateien[datei]
        a = wert(w, anf)
        n = wert(w, gr)
        stuecke.append((a, a + n, name, datei, anf))

    fehler = []

    # 2. Ueberschneidungen -- der eigentliche Zweck.
    stuecke.sort()
    for i in range(len(stuecke)):
        a1, e1, n1, d1, k1 = stuecke[i]
        if e1 > kdata:
            fehler.append("%s (%s:%s) endet bei 0x%X, KDATA_SIZE ist 0x%X"
                          % (n1, d1, k1, e1, kdata))
        for j in range(i + 1, len(stuecke)):
            a2, e2, n2, d2, k2 = stuecke[j]
            if a2 >= e1:
                break
            fehler.append(
                "KOLLISION: %s (%s:%s) 0x%X..0x%X  ueberschneidet  "
                "%s (%s:%s) 0x%X..0x%X"
                % (n1, d1, k1, a1, e1, n2, d2, k2, a2, e2))

    # 3. Vollstaendigkeit: jede `_OFF`-Konstante ist entweder ein Bereich
    #    dieser Karte oder ausdruecklich als Nicht-kdata erklaert.  Ohne
    #    diesen Punkt schuetzt die Karte nur das, woran jemand gedacht hat.
    benannt = {(d, k) for _, _, _, d, k in stuecke}
    benannt |= {(datei, anf) for _, datei, anf, _ in BEREICHE}
    for datei, w in dateien.items():
        for k in w:
            if not k.endswith("_OFF"):
                continue
            if (datei, k) in benannt or (datei, k) in KEINE_KDATA:
                continue
            fehler.append("%s:%s steht in keiner Karte -- Bereich oder "
                          "ausdruecklich kein kdata?" % (datei, k))

    # 4. `fb.fi` fuehrt einen SPIEGEL von kstate.FB_OFF, weil es die
    #    Konstante zur Uebersetzungszeit braucht und Firn keine Konstante
    #    aus einem anderen Modul in einen `const` einsetzt.  Die beiden
    #    muessen gleich sein, und das wird hier nachgerechnet statt
    #    gehofft.
    if "fb.fi" in dateien:
        a = wert(dateien["kstate.fi"], "FB_OFF")
        b = wert(dateien["fb.fi"], "FB_OFF")
        if a != b:
            fehler.append("fb.FB_OFF ist 0x%X, kstate.FB_OFF ist 0x%X"
                          % (b, a))
        f = wert(dateien["fb.fi"], "FONT_OFF")
        n = wert(dateien["fb.fi"], "FB_MAX")
        if not (b < f < b + n):
            fehler.append("FONT_OFF 0x%X liegt nicht in FB_OFF 0x%X + 0x%X"
                          % (f, b, n))

    if laut:
        vor = 0
        for a, e, n, d, k in stuecke:
            if a > vor:
                print("       ---- frei 0x%05X..0x%05X (%d KiB)"
                      % (vor, a, (a - vor) // 1024))
            print("  0x%05X..0x%05X  %-12s %s:%s" % (a, e, n, d, k))
            vor = max(vor, e)
        if vor < kdata:
            print("       ---- frei 0x%05X..0x%05X (%d KiB)"
                  % (vor, kdata, (kdata - vor) // 1024))

    for f in fehler:
        print("  " + f)
    print("%d Bereiche in 0x%X Oktetten kdata, %d Kollisionen"
          % (len(stuecke), kdata, len(fehler)))
    return 1 if fehler else 0


if __name__ == "__main__":
    sys.exit(main())
