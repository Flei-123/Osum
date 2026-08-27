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
    # RUNDE K18: die Energieschicht.  Ihr Vorrat ist 0x58000..0x60000 --
    # er liegt HINTER der alten Grenze KDATA_SIZE (0x50000), und deshalb
    # hat diese Runde `kdata` von 0x50000 auf 0x60000 wachsen lassen
    # (kstate.fi UND kernel/boot.s, beide Zahlen muessen gleich sein).
    # Belegt sind zwei Seiten: die Skalare der Energieschicht und das,
    # was aus den ACPI-Tabellen ueber Akku, Netzteil und Thermalzone
    # gelesen wurde.  Der Rest des Vorrats bleibt frei.
    ("K18",        "kstate.fi", "K18_OFF",        "K18_MAX"),
    ("K18BATT",    "kstate.fi", "BATT_OFF",       "BATT_MAX"),
    # RUNDE TRESOR: die Geraeteidentitaet, zwei Seiten (0x5A000..0x5C000).
    # Die erste traegt die Merkmale, die zweite ist das DMA-Ziel des
    # `identify controller` von NVMe -- und deshalb MUSS sie eine eigene,
    # seitenausgerichtete Seite sein und darf nicht in der ersten liegen.
    ("HWID",       "kstate.fi", "HWID_OFF",       "HWID_MAX"),
    # RUNDE K15, ZWEITER NACHTRAG.  Die erste Seite dieses Vorrats wird
    # geteilt: `wig.fi` braucht davon 0x40 Oktette, der Rest gehoert der
    # Geometrie des Dateisystems (FSG, zwei Woerter aus dem Superblock)
    # und dem Aenderungsjournal (JRNL).  Beide liegen INNERHALB von
    # WIG_OFF und sind deshalb hier keine eigenen Bereiche -- sie stehen
    # unten bei den Unterversaetzen.  Was hier zaehlt, ist: derselbe
    # Vorrat, keine neue Seite.
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
    ("wig.fi", "CLIP_OFF"),     # Versatz IN WIG_OFF (Runde K15)
    ("wig.fi", "STAGE_OFF"),    # dito
    ("kstate.fi", "FSG_OFF"),   # Versatz IN WIG_OFF (K15, zweiter Nachtrag)
    ("kstate.fi", "JRNL_OFF"),  # dito -- das Aenderungsjournal
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
              # RUNDE K14 -- sonst pruefte die Karte diese Dateien gar
              # nicht, und ein vergessener Bereich fiele nie auf.
              "vfs.fi", "mnt.fi", "fat.fi", "procfs.fi", "devfs.fi",
              "part.fi", "ofs.fi"):
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
    vektoren = {}
    for pfad in sorted(glob.glob(os.path.join(kdir, "*.fi"))):
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
    print("%d Bereiche in 0x%X Oktetten kdata, %d Vektoren, %d Kollisionen"
          % (len(stuecke), kdata, len(vektoren), len(fehler)))
    return 1 if fehler else 0


if __name__ == "__main__":
    sys.exit(main())
