#!/usr/bin/env python3
"""tools/kernel/karte.py -- DIE SPEICHERKARTE VON `kdata` MECHANISCH PRUEFEN.

Der Kernel hat EINEN zusammenhaengenden Datenbereich (`kernel/arch/x86_64/boot.s`,
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
import glob
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
    ("K11",        "kstate.fi", "K11_OFF",        "K11_MAX"),
    # RUNDE K10: die Oberflaeche.  Sie liegt in den beiden Luecken, die
    # Runde K7B als frei ausgewiesen hat -- und sie steht HIER, weil
    # genau das der Fehler war, an dem Runde K7 gescheitert ist.
    ("MOUSE",      "kstate.fi", "MOUSE_OFF",      "MOUSE_MAX"),
    ("WM",         "kstate.fi", "WM_OFF",         "WM_MAX"),
    ("TTF",        "kstate.fi", "TTF_OFF",        "TTF_MAX"),
    # RUNDE K16: die Dateiarten (0x49000..0x4C000).  Der Vorrat dieser
    # Runde ist VOR dem Bauen verteilt worden, weil am 26.08.2026 vier
    # Runden gleichzeitig liefen und drei dieselbe Seite genommen haben.
    ("K16",        "kstate.fi", "K16_OFF",        "K16_MAX"),
    # RUNDE K17: DER USB-BAUM (0x50000..0x58000).  Diese Runde hat kdata
    # von 0x50000 auf 0x58000 wachsen lassen -- der zweite Zuwachs nach
    # Runde K12, und aus demselben Grund: ein xHCI liest seine Ringe,
    # seine Zusammenhangstafel und seine Puffer SELBST aus dem Speicher,
    # und die muessen ausgerichtet und ortsfest liegen.  EIN Bereich fuer
    # die ganze Runde; wie er innen aufgeteilt ist, steht in `xhci.fi`
    # und `usb.fi` und wird unten (Punkt 5) nachgerechnet.
    ("K17",        "kstate.fi", "K17_OFF",        "K17_MAX"),
    # RUNDE K12: die Gastmaschinen des Hypervisors.  Der Bereich steht
    # in `hv.fi` und nicht in `kstate.fi` -- absichtlich, denn er ist die
    # EINZIGE Seite, die diese Runde in `kdata` braucht; alles andere
    # (Steuerbloecke, verschachtelte Seitentabellen, Bitkarten, der
    # Speicher der Gaeste) kommt aus dem Rahmenverwalter.  Eingetragen
    # ist er hier, damit der Kollisionspruefer ihn trotzdem sieht.
    ("HV",         "hv.fi",     "HV_OFF",         "HV_MAX"),
    # RUNDE K13: die Zaehler der Benutzer- und Rechteschicht. Zwei
    # Seiten, 0x41000 und 0x42000 -- die ersten hinter dem Bereich des
    # Hypervisors, so wie kstate.fi es fuer die naechste Runde
    # ausgewiesen hat. Die zweite Seite ist der Ausgabepuffer von
    # SYS_OSUM_USERINFO; sie steht hier mit, damit die Runde danach bei
    # 0x43000 anfaengt und nicht mitten drin.
    ("K13",        "kstate.fi", "K13_OFF",        "K13_MAX"),
    # RUNDE K14: die VFS-Schicht und die fremden Dateisysteme. Der
    # Auftrag dieser Runde hat 0x43000..0x46000 zugeteilt, weil weitere
    # Runden GLEICHZEITIG an diesem Baum arbeiten -- genau die Lage, aus
    # der die vier Kollisionen oben entstanden sind. Drei Seiten, drei
    # Eintraege, und der Pruefer rechnet nach.
    ("K14",        "kstate.fi", "K14_OFF",        "K14_MAX"),
    ("K14FAT",     "kstate.fi", "FAT_OFF",        "FAT_MAX"),
    ("K14PROC",    "kstate.fi", "PROCFS_OFF",     "PROCFS_MAX"),
    # RUNDE K15: die Naht zwischen Fensterserver und Widget-Bibliothek.
    # Drei Seiten -- Skalare, Zwischenablage, Umschlagpuffer.  Sie liegen
    # in dem Vorrat, den diese Runde zugeteilt bekommen hat
    # (0x46000..0x49000), und in keinem anderen: drei Runden liefen
    # gleichzeitig, und genau daran waeren die Merges beinahe
    # gescheitert.  Der Rest der Bibliothek liegt in Ring 3 und kommt in
    # `kdata` gar nicht vor.
    ("WIG",        "kstate.fi", "WIG_OFF",        "WIG_MAX"),
    # RUNDE OFS3: die Pfadpuffer des Dateisystems.  Sie sind hier ein
    # EIGENER Bereich und kein Versatz -- die zwei Seiten gehoeren
    # dieser Runde allein, und genau das soll die Karte nachrechnen.
    ("OFS3",       "kstate.fi", "OFS3_OFF",       "OFS3_MAX"),
    # RUNDE K18: die Energieschicht.  Ihr Vorrat ist 0x58000..0x60000 --
    # er liegt HINTER der alten Grenze KDATA_SIZE (0x50000), und deshalb
    # hat diese Runde `kdata` von 0x50000 auf 0x60000 wachsen lassen
    # (kstate.fi UND kernel/arch/x86_64/boot.s, beide Zahlen muessen gleich sein).
    # Belegt sind zwei Seiten: die Skalare der Energieschicht und das,
    # was aus den ACPI-Tabellen ueber Akku, Netzteil und Thermalzone
    # gelesen wurde.  Der Rest des Vorrats bleibt frei.
    # RUNDE K17: DIE SEITE DES MODUSVEKTORS (0x4C000..0x4D000).  Bis zu
    # dieser Runde stand der ganze Modus in EINEM Skalar (Versatz 88);
    # er ist voll gelaufen, und seitdem liegt er als Feld aus
    # MODE_WORDS Woertern hier.  Er steht in dieser Karte, weil er eine
    # Seite `kdata` belegt wie jeder andere Bereich auch -- und weil die
    # naechste Runde sonst genau diese Seite naehme.
    ("MODE",       "kstate.fi", "MODE_OFF",       "MODE_MAX"),
    ("K18",        "kstate.fi", "K18_OFF",        "K18_MAX"),
    ("K18BATT",    "kstate.fi", "BATT_OFF",       "BATT_MAX"),
    # RUNDE DESKTOP: die Fenstertafel und die Ereignisringe des
    # Fensterservers.  Sie standen bis zu dieser Runde in WM_OFF (zwei
    # Seiten); mit MAX_WIN 16 statt 8 sind das 0x1000 Oktette Tafel und
    # 0x2000 Oktette Ringe und passen dort nicht mehr hinein.  Der
    # Vorrat dieser Runde ist 0x54000..0x58000, und er liegt ABSICHTLICH
    # am oberen Ende des freien Bereichs: wer sequentiell greift, greift
    # 0x4C000, und am 27.08.2026 laufen wieder mehrere Runden.
    ("DESK",       "kstate.fi", "DSK_OFF",        "DSK_MAX"),
    # RUNDE K15, ZWEITER NACHTRAG.  Die erste Seite dieses Vorrats wird
    # geteilt: `wig.fi` braucht davon 0x40 Oktette, der Rest gehoert der
    # Geometrie des Dateisystems (FSG, zwei Woerter aus dem Superblock).
    # FSG liegt INNERHALB von WIG_OFF und ist deshalb hier kein eigener
    # Bereich -- es steht unten bei den Unterversaetzen.  Was hier zaehlt,
    # ist: derselbe Vorrat, keine neue Seite.
    # RUNDE SPEICHER: das Aenderungsjournal ist aus dieser geteilten Seite
    # AUSGEZOGEN und hat jetzt zwei eigene (0x5E000..0x60000).  Es traegt
    # seit dieser Runde auch die Groessenaenderungen, und 56 Saetze waren
    # dafuer zu wenig -- die Begruendung steht bei JRNL_OFF in kstate.fi.
    # Damit ist es ein Bereich in `kdata` wie jeder andere und steht
    # NICHT mehr unten in KEINE_KDATA.
    ("JRNL",       "kstate.fi", "JRNL_OFF",       "JRNL_MAX"),
]

# `_OFF`-Konstanten, die KEINE Bereiche in `kdata` sind -- Offsets
# innerhalb eines anderen Puffers oder innerhalb von Geraetespeicher.
# Wer hier etwas eintraegt, sagt damit ausdruecklich: das ist kein Stueck
# `kdata`.  Alles andere MUSS in BEREICHE stehen.
# RUNDE K17: die Untergliederung des USB-Bereichs.  Jeder dieser Versaetze
# liegt INNERHALB von kstate.K17_OFF; Punkt 5 unten rechnet das nach und
# prueft ausserdem, dass sich die Stuecke nicht gegenseitig ueberschneiden.
K17_STUECKE = [
    ("xhci.fi", "SCAL_OFF",   0x400),
    ("xhci.fi", "EPTAB_OFF",  0x400),
    ("xhci.fi", "DCBAA_OFF",  0x400),
    ("xhci.fi", "ERST_OFF",   0x40),
    ("xhci.fi", "CMD_OFF",    0x800),
    ("xhci.fi", "EVT_OFF",    0x1000),
    ("xhci.fi", "INCTX_OFF",  0x1000),
    ("xhci.fi", "DEVCTX_OFF", 0x1000),
    ("xhci.fi", "RING_OFF",   0x1000),
    ("xhci.fi", "SPARE_OFF",  0x1000),
    ("usb.fi",  "USCAL_OFF",  0x100),
    ("usb.fi",  "UDEV_OFF",   0x300),
    ("usb.fi",  "DESC_OFF",   0x200),
    ("usb.fi",  "REPORT_OFF", 0x100),
    ("usb.fi",  "CBW_OFF",    0x40),
    ("usb.fi",  "CSW_OFF",    0x40),
    ("usb.fi",  "BLK_OFF",    0x200),
]

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
    ("wig.fi", "CLIP_OFF"),     # Versatz IN WIG_OFF (Runde K15)
    ("wig.fi", "STAGE_OFF"),    # dito
    ("kstate.fi", "FSG_OFF"),   # Versatz IN WIG_OFF (K15, zweiter Nachtrag)
    ("kstate.fi", "JRNL_OFF"),  # dito -- das Aenderungsjournal
    # RUNDE OFS3: Versaetze INNERHALB von OFS3_OFF, kein eigenes kdata.
    ("kstate.fi", "OP_NAME"),
    ("kstate.fi", "OP_NAME2"),
    ("kstate.fi", "OP_OLD"),
    ("kstate.fi", "OP_NEW"),
    ("kstate.fi", "OP_PATH"),
    ("kstate.fi", "OP_WORK"),
    ("kstate.fi", "OP_BUILD"),
    ("kstate.fi", "OP_LINK"),
    ("kstate.fi", "OP_TMP"),
    ("kstate.fi", "OP_ENT"),
    ("fs.fi", "G_INODES"),      # Versaetze IN FSG_OFF (Runde OFS3)
    ("fs.fi", "G_DATA"),
    ("fs.fi", "G_BMSTART"),
    ("fs.fi", "G_BMBLOCKS"),
    ("fs.fi", "G_ITABLE"),
    ("fs.fi", "G_ISIZE"),
    ("fs.fi", "G_IPB"),
    ("fs.fi", "G_DIRENT"),
    ("fs.fi", "G_NAMELEN"),
    ("fs.fi", "G_HINT"),
    ("nidx.fi", "H_BASE"),      # Versatz IM Journal, nicht kdata
    ("hv.fi", "CNT_OFF"),       # Versaetze INNERHALB von HV_OFF (Runde K12)
    ("hv.fi", "VAL_OFF"),
    ("hv.fi", "VM_OFF"),
    ("hv.fi", "GPR_OFF"),
    ("virtio.fi", "C_QNOTIFY_OFF"),  # ein Register im Konfigurationsraum
    # RUNDE K14: Versaetze INNERHALB der drei Seiten oben, kein eigenes
    # kdata. Sie stehen hier, damit Punkt 3 unten sie sieht und nicht
    # als vergessenen Bereich meldet.
    ("mnt.fi", "MNT_OFF"),      # in K14_OFF
    ("part.fi", "PART_OFF"),    # in K14_OFF
    ("part.fi", "SECT_OFF"),    # in K14_OFF
    ("fat.fi", "SB_OFF"),       # in FAT_OFF
    ("fat.fi", "NODE_OFF"),     # in FAT_OFF
}
# Die K17-Stuecke sind ebenfalls kein eigenes kdata -- sie liegen alle in
# K17_OFF.  Eingetragen wird das mechanisch, damit die beiden Listen
# nicht auseinanderlaufen koennen.
for _d, _k, _n in K17_STUECKE:
    KEINE_KDATA.add((_d, _k))


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
              "virtio.fi", "hv.fi",
              # RUNDE K17 -- sonst pruefte die Karte den USB-Bereich gar
              # nicht, und ein vergessener Versatz fiele nie auf.
              "xhci.fi", "usb.fi",
              # RUNDE K14 -- sonst pruefte die Karte diese Dateien gar
              # nicht, und ein vergessener Bereich fiele nie auf.
              "vfs.fi", "mnt.fi", "fat.fi", "procfs.fi", "devfs.fi",
              "part.fi", "ofs.fi",
              # RUNDE OFS3 -- die Geometriewoerter stehen hier.
              "fs.fi"):
        # RUNDE ARM: die Maschine hat seit dem Trennschnitt ein eigenes
        # Verzeichnis (`kernel/arch/x86_64/`).  `hv.fi` liegt dort, und
        # diese Schleife hat es vorher schlicht nicht mehr gefunden --
        # KeyError 'hv.fi', mitten in der Abnahme.  Gesucht wird jetzt an
        # beiden Stellen, in dieser Reihenfolge.
        p = None
        for kand in (os.path.join(kdir, d),
                     os.path.join(kdir, "arch", "x86_64", d)):
            if os.path.exists(kand):
                p = kand
                break
        if p is not None:
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

    # 5. RUNDE K17: die Untergliederung des USB-Bereichs.  Sie ist kein
    #    eigener kdata-Bereich, aber sie kann sich SELBST ueberschneiden
    #    und aus ihrem Bereich herauslaufen -- und beides faende sonst
    #    niemand, weil die Karte oben nur EINEN Block sieht.
    if "xhci.fi" in dateien and "usb.fi" in dateien:
        a0 = wert(dateien["kstate.fi"], "K17_OFF")
        e0 = a0 + wert(dateien["kstate.fi"], "K17_MAX")
        k17 = []
        for datei, k, n in K17_STUECKE:
            if datei not in dateien or k not in dateien[datei]:
                fehler.append("%s:%s fehlt -- die K17-Karte ist veraltet"
                              % (datei, k))
                continue
            a = wert(dateien[datei], k)
            if a < a0 or a + n > e0:
                fehler.append(
                    "%s:%s 0x%X..0x%X liegt AUSSERHALB von K17 0x%X..0x%X"
                    % (datei, k, a, a + n, a0, e0))
            k17.append((a, a + n, datei, k))
        k17.sort()
        for i in range(len(k17)):
            a1, e1, d1, k1 = k17[i]
            for j in range(i + 1, len(k17)):
                a2, e2, d2, k2 = k17[j]
                if a2 >= e1:
                    break
                fehler.append(
                    "KOLLISION IN K17: %s:%s 0x%X..0x%X ueberschneidet "
                    "%s:%s 0x%X..0x%X" % (d1, k1, a1, e1, d2, k2, a2, e2))
        if laut:
            print("  ---- die Untergliederung von K17 ----")
            vor17 = a0
            for a, e, dd, kk in k17:
                if a > vor17:
                    print("       ---- frei 0x%05X..0x%05X" % (vor17, a))
                print("  0x%05X..0x%05X  %s:%s" % (a, e, dd, kk))
                vor17 = max(vor17, e)
            if vor17 < e0:
                print("       ---- frei 0x%05X..0x%05X" % (vor17, e0))

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

    # ------------------------------------------------ die Vektortabelle
    #
    # RUNDE K10 HAT DENSELBEN FEHLER EINE EBENE HOEHER GEMACHT.  Der
    # Maustreiber bekam `VEC_MOUSE = 44` -- und 44 ist seit Runde K2 der
    # Vektor des NVMe-Reglers.  Die Weiche in `trap.fi` ist eine Kette
    # von `if`s; die Mausbedingung stand vor der NVMe-Bedingung, und
    # damit gingen alle Abschlussmeldungen des Reglers an den
    # Maustreiber.  `nvme: irqs=0` statt `irqs=5`, in jedem Lauf, auch
    # OHNE das Wort `wm`.
    #
    # Die Regel ist dieselbe wie oben: DERSELBE Name darf mehrfach
    # dastehen (`trap.fi` und `nvme.fi` fuehren VEC_NVME beide, weil
    # Firn keine Konstante eines anderen Moduls in einen `const`
    # einsetzt), ZWEI VERSCHIEDENE Namen duerfen nicht auf derselben
    # Zahl liegen.
    # ------------------------------------------- der Modusvektor
    #
    # RUNDE K17 HAT DENSELBEN FEHLER EINE DRITTE EBENE HOEHER GEFUNDEN,
    # UND DIESMAL ZWEIMAL.
    #
    # (a) DIE KOLLISION.  `kstate.MODE` war EIN Wort, in dem jede Runde
    #     ihre Schalter als Bit ablegte -- und die Runden K13, K14 und
    #     K16 haben alle drei bei 1 << 31 angefangen.  Folge: `novfs`
    #     schaltete auch die Rechtepruefung ab (M_NOPERM) und das
    #     Stapelwachstum (M_NOSTACK), und die Gegenprobe `novfs` von
    #     Runde K14 starb daran, dass der Uebersetzer in Ring 3 keine
    #     Stapelseite mehr bekam.  Beide Zweige waren FUER SICH gruen;
    #     die Kollision stand in keiner gemeinsamen Zeile.  Genau wie bei
    #     `kdata` und bei der Vektortafel.
    #
    # (b) DAS ENDE DES VORRATS.  Nach dem Auseinanderziehen waren von 64
    #     Bits 60 belegt und vier frei (38, 61, 62, 63); Runde K17
    #     brauchte neun.  Ein zweites Wort haette die Rechnung nur
    #     verschoben und gegen (a) nichts getan.
    #
    # SEIT RUNDE K17 IST DER MODUS EIN VEKTOR: eine Seite `kdata` mit
    # MODE_WORDS Woertern, EIN WORT JE UNTERSYSTEM, und ein Modusname
    # ist ein BITINDEX darueber:
    #
    #     Index = Wort * 64 + Bit
    #
    # Weil der Index das Wort enthaelt, prueft diese Karte den neuen Raum
    # mit DERSELBEN Regel wie den alten -- derselbe Name darf mehrfach
    # dastehen, ZWEI VERSCHIEDENE Namen duerfen nicht auf demselben Wert
    # liegen -- und zusaetzlich mit zwei neuen:
    #
    #   * jeder Index bleibt unter MODE_WORDS * 64.  Eine vergessene alte
    #     Maske (2147483648) faellt damit sofort auf, statt still in ein
    #     Wort zu greifen, das es nicht gibt.
    #   * die Seite des Vektors steht oben in BEREICHE, damit die
    #     naechste Runde sie nicht als frei nimmt.
    #
    # NUR `kstate.fi` UND `kmain.fi`.  Seit Runde K17 stehen alle Namen
    # des gemeinsamen Modus in `kstate.fi`; `kmain.fi` wird trotzdem
    # weiter gelesen, damit eine dort neu angelegte zweite Liste sofort
    # auffaellt -- genau diese zweite Liste war der Grund, warum ein zu
    # enger `grep` die Kollisionen nicht fand.  Andere Module (`hw.fi`,
    # `fb.fi`, `hv.fi`, `guard.fi`, `smp.fi`, `bootmod.fi`) fuehren ein
    # EIGENES Wort mit eigenen Bits; dort faengt jede Runde zu Recht
    # wieder bei 1 an.
    mode_words = wert(dateien["kstate.fi"], "MODE_WORDS")
    modi = {}
    for datei in ("kstate.fi", "kmain.fi"):
        pfad = os.path.join(kdir, datei)
        if not os.path.exists(pfad):
            continue
        for k, roh in konstanten(pfad).items():
            if not k.startswith("M_") or k == "M_MODE":
                continue
            try:
                v = int(roh.split("//")[0].strip(), 0)
            except ValueError:
                continue
            modi.setdefault(v, {}).setdefault(k, []).append(datei)
    for v in sorted(modi):
        if len(modi[v]) > 1:
            wer = ", ".join("%s (%s)" % (k, "+".join(dd))
                            for k, dd in sorted(modi[v].items()))
            fehler.append("KOLLISION: den Modusindex %d haben zwei Namen: %s"
                          % (v, wer))
        if v >= mode_words * 64:
            wer = ", ".join(sorted(modi[v]))
            fehler.append(
                "%s: Modusindex %d liegt hinter dem Vektor (MODE_WORDS * 64 "
                "= %d) -- eine alte Maske?" % (wer, v, mode_words * 64))
    if laut:
        print("  ---- der Modusvektor, %d Woerter zu 64 Bits ----" % mode_words)
        for w in range(mode_words):
            drin = sorted((v % 64, n)
                          for v in modi if v // 64 == w
                          for n in modi[v])
            if not drin:
                continue
            print("  Wort %-2d  %2d von 64 belegt, hoechstes Bit %d"
                  % (w, len(set(b for b, _ in drin)),
                     max(b for b, _ in drin)))
            for b, n in drin:
                print("     %3d = %d*64+%-2d  %s" % (w * 64 + b, w, b, n))
        leer = [w for w in range(mode_words)
                if not any(v // 64 == w for v in modi)]
        print("  freie Woerter: %s"
              % (", ".join(str(w) for w in leer) or "keins"))

    vektoren = {}
    # RUNDE ARM: auch hier beide Verzeichnisse -- `trap.fi` fuehrt die
    # Vektornummern und liegt seit dem Trennschnitt unter arch/x86_64/.
    for pfad in sorted(glob.glob(os.path.join(kdir, "*.fi"))
                       + glob.glob(os.path.join(kdir, "arch", "x86_64", "*.fi"))):
        datei = os.path.basename(pfad)
        for k, roh in konstanten(pfad).items():
            if not k.startswith("VEC_"):
                continue
            try:
                v = int(roh, 0)
            except ValueError:
                continue
            vektoren.setdefault(v, {}).setdefault(k, []).append(datei)
    vfehler = []
    for v in sorted(vektoren):
        if len(vektoren[v]) > 1:
            wer = ", ".join("%s (%s)" % (k, "+".join(d))
                            for k, d in sorted(vektoren[v].items()))
            vfehler.append("KOLLISION: Vektor %d haben zwei Namen: %s"
                           % (v, wer))
    fehler += vfehler
    if laut:
        print("  ---- die Vektortabelle ----")
        for v in sorted(vektoren):
            print("  %3d  %s" % (v, ", ".join(sorted(vektoren[v]))))

    for f in fehler:
        print("  " + f)
    print("%d Bereiche in 0x%X Oktetten kdata, %d Vektoren, "
          "%d Modusnamen in %d Woertern, %d Kollisionen"
          % (len(stuecke), kdata, len(vektoren),
             sum(len(x) for x in modi.values()), mode_words, len(fehler)))
    return 1 if fehler else 0


if __name__ == "__main__":
    sys.exit(main())
