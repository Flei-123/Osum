#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/kernel/memmap.py -- DIE SPEICHERKARTE VON `kdata` MECHANISCH PRUEFEN.

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
    python3 tools/kernel/memmap.py [kernelverzeichnis]

Ausgabe: eine Zeile je Bereich (nur mit -v), am Ende die Zahl der Bereiche
und der Kollisionen.  Rueckgabe 0, wenn sich nichts ueberschneidet und
alles in KDATA_SIZE passt.
"""
import glob
import os
import re
import sys


BEREICHE = [
    ("IDT",        "kstate.fi", "IDT_OFF",        "0x1000"),
    ("BITMAP",     "kstate.fi", "BITMAP_OFF",     "BITMAP_BYTES"),
    ("PT",         "kstate.fi", "PT_OFF",         "0x2000"),
    ("EXT4",       "kstate.fi", "EXT4_OFF",       "EXT4_MAX"),
    ("NTFS",       "kstate.fi", "NTFS_OFF",       "NTFS_MAX"),
    ("EXFAT",      "kstate.fi", "EXFAT_OFF",      "EXFAT_MAX"),
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
    ("HIDREP_FLD", "hidrep.fi", "FLD_OFF",       "MAX_DEV * 0x1000"),
    ("HIDREP_SUM", "hidrep.fi", "SUM_OFF",       "MAX_DEV * SUM_BYTES"),
    ("HIDREP_RAW", "hidrep.fi", "RAW_OFF",       "MAX_DEV * RAW_MAX"),
    ("HIDIN",      "hidin.fi",  "IN_OFF",        "0x1000"),
    ("I2CHID",     "i2chid.fi", "I2C_OFF",       "0x1000"),
    ("R3D",        "r3dsoft.fi", "R3D_OFF",      "R3D_MAX"),
    ("I2CBUF",     "i2chid.fi", "BUF_OFF",       "0x1000"),
    ("AHCI",       "ahci.fi",   "AHCI_OFF",       "0x1000"),
    ("AHCI_ID",    "ahci.fi",   "AHCI_ID_OFF",    "0x1000"),
    ("AHCI_BUF_A", "ahci.fi",   "AHCI_BUFA_OFF",  "0x1000"),
    ("AHCI_BUF_B", "ahci.fi",   "AHCI_BUFB_OFF",  "0x1000"),
    ("AHCI_SC",    "ahci.fi",   "AHCI_SC_OFF",    "0x1000"),
    ("CPU",        "kstate.fi", "CPU_OFF",        "CPU_BYTES * MAX_CPUS"),
    ("LOCK",       "kstate.fi", "LOCK_OFF",       "LOCK_BYTES * LOCK_COUNT"),
    ("CPUX",       "kstate.fi", "CPUX_OFF",       "CPUX_BYTES * MAX_CPUS"),
    ("TCPU",       "kstate.fi", "TCPU_OFF",       "TCPU_BYTES * MAX_TASKS"),
    ("CX",         "kstate.fi", "CX_OFF",         "CX_BYTES * MAX_TASKS"),
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
    ("SIGRT",      "kstate.fi", "SIGRT_OFF",      "SIGRT_TASK * MAX_TASKS"),
    ("EXE",        "kstate.fi", "EXE_OFF",        "EXE_SLOT * MAX_TASKS"),
    ("SHMN",       "kstate.fi", "SHMN_OFF",       "SHMN_MAX"),
    ("TTY",        "kstate.fi", "TTY_OFF",        "TTY_MAX"),
    ("TTY2",       "kstate.fi", "TTY2_OFF",       "TTY2_MAX"),
    ("RAND",       "kstate.fi", "RANDOM_OFF",       "RANDOM_MAX"),
    ("FB",         "kstate.fi", "FB_OFF",         "FB_MAX"),
    ("K11",        "kstate.fi", "K11_OFF",        "K11_MAX"),
    ("MOUSE",      "kstate.fi", "MOUSE_OFF",      "MOUSE_MAX"),
    ("WM",         "kstate.fi", "WM_OFF",         "WM_MAX"),
    ("TTF",        "kstate.fi", "TTF_OFF",        "TTF_MAX"),
    ("K16",        "kstate.fi", "K16_OFF",        "K16_MAX"),
    ("K17",        "kstate.fi", "K17_OFF",        "K17_MAX"),
    ("HV",         "hv.fi",     "HV_OFF",         "HV_MAX"),
    ("VDEV",       "hv.fi",     "VDEV_OFF",       "VDEV_MAX"),
    ("K13",        "kstate.fi", "K13_OFF",        "K13_MAX"),
    ("MU",         "kstate.fi", "MU_OFF",         "MU_MAX"),
    ("K14",        "kstate.fi", "K14_OFF",        "K14_MAX"),
    ("K14FAT",     "kstate.fi", "FAT_OFF",        "FAT_MAX"),
    ("K14PROC",    "kstate.fi", "PROCFS_OFF",     "PROCFS_MAX"),
    ("WIG",        "kstate.fi", "WIG_OFF",        "WIG_MAX"),
    ("WIGST",      "kstate.fi", "WIGST_OFF",      "WIGST_MAX"),
    ("SCANB",      "kstate.fi", "SCANB_OFF",      "SCANB_MAX"),
    ("NAMEK",      "kstate.fi", "NAMEK_OFF",      "NAMEK_MAX"),
    ("BLOCKK",     "kstate.fi", "BLOCKK_OFF",     "BLOCKK_MAX"),
    ("EARGK",      "kstate.fi", "EARGK_OFF",      "EARGK_MAX"),
    # ROUND A11Y-2 (S-007): the accessibility tree. Six pages,
    # 0x13E000..0x144000, allotted in advance by the wave of 18.09.2026
    # (see kstate.fi at KDATA_SIZE) -- this round took exactly that.
    ("AX",         "kstate.fi", "AX_OFF",         "AX_MAX"),
    ("FLOCK",      "kstate.fi", "FLOCK_OFF",      "FLOCK_MAX"),
    ("WECHSEL",    "kstate.fi", "WECHSEL_OFF",    "WECHSEL_MAX"),
    ("VGPU",       "kstate.fi", "VGPU_OFF",       "VGPU_MAX"),
    ("VMSVGA",     "kstate.fi", "VMSVGA_OFF",     "VMSVGA_MAX"),
    ("USOCK",      "unixsock.fi", "USOCK_OFF",   "USOCK_MAX * USOCK_BYTES"),
    ("UNAME",      "unixsock.fi", "UNAME_OFF",   "UNAME_MAX * UNAME_BYTES"),
    ("UCNT",       "unixsock.fi", "UCNT_OFF",    "0x40"),
    ("USHM",       "unixsock.fi", "USHM_OFF",    "USHM_MAX * USHM_BYTES"),
    ("USHMPG",     "unixsock.fi", "USHMPG_OFF",  "USHM_PAGED * SHM_PAGES_MAX * 8"),
    # COMPOSITOR S3: who maps which shared object (the reference of a mapping is given back by munmap and by the end of the task)
    ("UMAP",       "unixsock.fi", "UMAP_OFF",    "UMAP_MAX * UMAP_BYTES"),
    ("WLSCRATCH",  "sys.fi",      "WL_SCRATCH",  "0x1000"),
    ("WLPATH",     "sys.fi",      "WL_PATH",     "0x1000"),
    ("OFS3",       "kstate.fi", "OFS3_OFF",       "OFS3_MAX"),
    ("MODE",       "kstate.fi", "MODE_OFF",       "MODE_MAX"),
    ("K18",        "kstate.fi", "K18_OFF",        "K18_MAX"),
    # RUNDE POWERMON: die Akkuanalyse je Programm (0x5C000..0x5E000).
    ("PMON",       "kstate.fi", "PMON_OFF",       "PMON_MAX"),
    ("NETVIEW",    "kstate.fi", "NETVIEW_OFF",    "NETVIEW_MAX"),
    ("NETDEV",     "kstate.fi", "NETDEV_OFF",     "NETDEV_MAX"),
    ("ROOTSEL",    "rootsel.fi", "ROOT_OFF",      "ROOT_MAX"),
    ("BLKDEV",     "blkdev.fi", "BLKDEV_OFF",     "BLKDEV_MAX"),
    ("SHOT",       "kstate.fi", "SHOT_OFF",       "SHOT_MAX"),
    ("TIPP",       "kstate.fi", "TIPP_OFF",       "TIPP_MAX"),
    ("EHCI",       "ehci.fi",   "EHCI_OFF",       "EHCI_MAX"),
    ("MODUL",      "kstate.fi", "MODULE_OFF",      "MODULE_MAX"),
    ("BUS",        "kstate.fi", "BUS_OFF",        "BUS_MAX"),

    ("JR",         "kstate.fi", "JR_OFF",         "JR_MAX"),
    ("K18BATT",    "kstate.fi", "BATT_OFF",       "BATT_MAX"),
    ("AML",        "kstate.fi", "AML_OFF",        "AML_MAX"),
    ("ACPIEV",     "kstate.fi", "ACPIEV_OFF",     "ACPIEV_MAX"),
    ("DISP",       "kstate.fi", "DISP_OFF",       "DISP_MAX"),
    ("DLUT",       "kstate.fi", "DLUT_OFF",       "DLUT_MAX"),
    ("DESK",       "kstate.fi", "DSK_OFF",        "DSK_MAX"),
    # DELL ROUND 04.10.2026: the window event rings of the 32 windows, in the
    # hole 0x10C000..0x110000.
    ("DESKEV",     "kstate.fi", "EVR_OFF",        "EVR_MAX"),
    ("TILE",       "kstate.fi", "TILE_OFF",       "TILE_MAX"),
    ("WMPLUG",     "kstate.fi", "WMP_OFF",        "WMP_MAX"),
    ("SUSP",       "kstate.fi", "SUSP_OFF",       "SUSP_MAX"),
    ("SCHLAF",     "kstate.fi", "SCHLAF_OFF",     "SCHLAF_MAX"),
    ("WACH",       "kstate.fi", "WACH_OFF",       "WACH_MAX"),
    ("CONTAINER",  "kstate.fi", "CTR_OFF",        "CTR_MAX"),
    ("KRYPTO",     "kstate.fi", "CRYPT_OFF",      "CRYPT_MAX"),
    ("CODEC",      "kstate.fi", "CODEC_OFF",      "CODEC_MAX"),
    ("AESNI",      "kstate.fi", "AESNI_OFF",      "AESNI_MAX"),
    ("ARGON",      "kstate.fi", "ARGON_OFF",      "ARGON_MAX"),
    ("NETMON",     "kstate.fi", "NETMON_OFF",     "NETMON_MAX"),
    ("EBPF",       "kstate.fi", "EBPF_OFF",       "EBPF_MAX"),
    ("EBPFMAP",    "kstate.fi", "EBPFMAP_OFF",    "EBPFMAP_MAX"),
    ("EBPFVER",    "kstate.fi", "EBPFVER_OFF",    "EBPFVER_MAX"),
    ("EBPFHOOK",   "kstate.fi", "EBPFHOOK_OFF",   "EBPFHOOK_MAX"),
    ("SHARE",      "kstate.fi", "SHARE_OFF",      "SHARE_MAX"),
    # ---- Runde HANDLE ----
    ("HND",        "kstate.fi", "HND_OFF",        "HND_MAX"),
    ("HOBJ",       "kstate.fi", "HOBJ_OFF",       "HOBJ_MAX"),
    ("HREQ",       "kstate.fi", "HREQ_OFF",       "HREQ_MAX"),
    ("HNON",       "kstate.fi", "HNON_OFF",       "HNON_MAX"),
    ("HCNT",       "kstate.fi", "HCNT_OFF",       "HCNT_MAX"),
    ("AIO",        "kstate.fi", "AIO_OFF",        "AIO_MAX"),
    ("ACQ",        "kstate.fi", "ACQ_OFF",        "ACQ_MAX"),
    ("ASC",        "kstate.fi", "ASC_OFF",        "ASC_MAX"),
    ("APATH",      "kstate.fi", "APATH_OFF",      "APATH_MAX"),
    ("LOG",        "kstate.fi", "LOG_OFF",        "LOG_MAX"),
    ("HWID",       "kstate.fi", "HWID_OFF",       "HWID_MAX"),
    ("JRNL",       "kstate.fi", "JRNL_OFF",       "JRNL_MAX"),
    ("AUD",        "kstate.fi", "AUD_OFF",        "AUD_MAX"),
    ("HDA",        "kstate.fi", "HDA_OFF",        "HDA_MAX"),
    ("HDARING",    "kstate.fi", "HDAR_OFF",       "HDAR_MAX"),
    ("HDABDL",     "kstate.fi", "HDAB_OFF",       "HDAB_MAX"),
    ("MIX",        "kstate.fi", "MIX_OFF",        "MIX_MAX"),
    ("AUDB",       "kstate.fi", "AUDB_OFF",       "AUDB_MAX"),
    ("BLKCACHE",   "kstate.fi", "BLKC_OFF",       "BLKC_MAX"),
    ("BLKDATA",    "kstate.fi", "BLKD_OFF",       "BLKD_MAX"),
]

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
    ("usb.fi",  "USCAL_OFF",  0x180),
    ("usb.fi",  "UDEV_OFF",   0x400),
    ("usb.fi",  "FUND_OFF",   0x280),
    ("usb.fi",  "DESC_OFF",   0x200),
    ("usb.fi",  "REPORT_OFF", 0x100),
    ("usb.fi",  "CBW_OFF",    0x40),
    ("usb.fi",  "CSW_OFF",    0x40),
    ("usb.fi",  "BLK_OFF",    0x200),
    ("usb.fi",  "HUB_OFF",    0x100),
    ("usb.fi",  "ISO_BUF_OFF", 0x600),
]

EXT4_STUECKE = [
    ("ext4.fi", "SB_OFF",   0x400),
    ("ext4.fi", "NODE_OFF", 0x380),
    ("ext4.fi", "BLKBUF",   0x1000),
    ("ext4.fi", "NODEBUF",  0x1000),
    ("ext4.fi", "INOBUF",   0x200),
    ("ext4.fi", "SECBUF",   0x200),
    ("ext4.fi", "NAMBUF",   0x100),
]

NTFS_STUECKE = [
    ("ntfs.fi", "SB_OFF",   0x400),
    ("ntfs.fi", "NODE_OFF", 0x380),
    ("ntfs.fi", "MFTBUF",   0x1000),
    ("ntfs.fi", "IDXBUF",   0x1000),
    ("ntfs.fi", "DATBUF",   0x200),
    ("ntfs.fi", "NAMBUF",   0x100),
    ("ntfs.fi", "CNVBUF",   0x100),
]

EXFAT_STUECKE = [
    ("exfat.fi", "SB_OFF",    0x400),
    ("exfat.fi", "NODE_OFF",  0x900),
    ("exfat.fi", "FATBUF",    0x200),
    ("exfat.fi", "DIRBUF",    0x200),
    ("exfat.fi", "DATBUF",    0x200),
    ("exfat.fi", "BMPBUF",    0x200),
    ("exfat.fi", "SETBUF",    0x300),
    ("exfat.fi", "CMPBUF",    0x80),
    ("exfat.fi", "NAMBUF",    0x80),
    ("exfat.fi", "CACHE_OFF", 0x80),
    ("exfat.fi", "CACHE_RR",  0x8),
]

EHCI_STUECKE = [
    ("ehci.fi", "PF_OFF",   0x1000),
    ("ehci.fi", "SCAL_OFF", 0x200),
    ("ehci.fi", "QH_OFF",   0x180),
    ("ehci.fi", "QTD_OFF",  0x400),
    ("ehci.fi", "DEV_OFF",  0x200),
    ("ehci.fi", "BUF_OFF",  0xC00),
]

KEINE_KDATA = {
    ("fb.fi", "FB_OFF"),        # Spiegel von kstate.FB_OFF, s. u.
    ("fb.fi", "FONT_OFF"),      # liegt IN FB_OFF
    ("fb.fi", "VMS_OFF"),       # Spiegel von kstate.VMSVGA_OFF (vmsvga.fi)
    ("inet.fi", "SOCK_OFF"),
    ("inet.fi", "ARP_OFF"),
    ("inet.fi", "ICMP_OFF"),
    ("virtio.fi", "RXD_OFF"),
    ("virtio.fi", "RXA_OFF"),
    ("virtio.fi", "RXU_OFF"),
    ("virtio.fi", "TXD_OFF"),
    ("virtio.fi", "TXA_OFF"),
    ("virtio.fi", "TXU_OFF"),
    ("virtio.fi", "RXB_OFF"),
    ("virtio.fi", "TXB_OFF"),
    ("pci.fi", "K2_OFF"),
    ("ttf.fi", "A_HEAP"),
    ("wmlayout.fi", "W_OFF"),
    ("wig.fi", "CLIP_OFF"),     # Versatz IN WIG_OFF (Runde K15)
    ("wig.fi", "STAGE_OFF"),    # dito
    ("vmode.fi", "LUT_OFF"),    # Versatz IN DLUT_OFF (Runde DISPLAY)
    ("vmode.fi", "EDID_OFF"),   # dito
    ("vmode.fi", "LIST_OFF"),   # Versatz IN DISP_OFF (Runde DISPLAY)
    ("kstate.fi", "FSG_OFF"),   # Versatz IN WIG_OFF (K15, zweiter Nachtrag)
    ("kstate.fi", "JRNL_OFF"),  # dito -- das Aenderungsjournal
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
    ("nidx.fi", "H_BASE"),
    ("hv.fi", "CNT_OFF"),       # Versaetze INNERHALB von HV_OFF (Runde K12)
    ("hv.fi", "VAL_OFF"),
    ("hv.fi", "VM_OFF"),
    ("hv.fi", "GPR_OFF"),
    ("virtio.fi", "C_QNOTIFY_OFF"),
    ("mnt.fi", "MNT_OFF"),      # in K14_OFF
    ("part.fi", "PART_OFF"),    # in K14_OFF
    ("part.fi", "SECT_OFF"),    # in K14_OFF
    ("ofs.fi", "SCRATCH_OFF"),  # in K14_OFF
    ("fat.fi", "SB_OFF"),       # in FAT_OFF
    ("fat.fi", "NODE_OFF"),     # in FAT_OFF
    ("fat.fi", "CACHE_OFF"),    # in FAT_OFF (r208 chain cache)
}
for _d, _k, _n in K17_STUECKE:
    KEINE_KDATA.add((_d, _k))
for _d, _k, _n in EHCI_STUECKE:
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
    ersetzt = re.sub(r"0[xX][0-9A-Fa-f]+",
                     lambda m: str(int(m.group(0), 16)), t)
    ersetzt = re.sub(r"[A-Za-z_][A-Za-z_0-9]*",
                     lambda m: str(wert(werte, m.group(0), tiefe + 1)), ersetzt)
    return int(eval(ersetzt, {"__builtins__": {}}, {}))  # noqa: S307


def alle_fi(kdir):
    """Jede .fi im Kernbaum, ohne user/ und app/ -- gleich, wie tief.

    RUNDE O-STRUKTUR: vorher standen hier feste glob-Muster fuer
    `kernel/*.fi` und `kernel/arch/x86_64/*.fi`. Nach dem Umzug in
    Schichten haetten sie die Haelfte des Kerns nicht mehr gesehen --
    und eine Karte, die die Haelfte nicht sieht, meldet `0
    Kollisionen`, weil sie nichts zu vergleichen hat. Das ist
    schlimmer als ein Fehler."""
    aus = []
    for stamm, verz, namen in os.walk(kdir):
        verz[:] = [v for v in verz if v not in ("user", "app")]
        for n in namen:
            if n.endswith(".fi"):
                aus.append(os.path.join(stamm, n))
    return sorted(aus)


def finde_fi(kdir, name):
    """Den Ort EINER Kerndatei suchen; None, wenn es sie nicht gibt."""
    for p in alle_fi(kdir):
        if os.path.basename(p) == name:
            return p
    return None


def main():
    kdir = sys.argv[1] if len(sys.argv) > 1 else "kernel"
    laut = "-v" in sys.argv

    dateien = {}
    for d in ("kstate.fi", "pci.fi", "nvme.fi", "fb.fi", "inet.fi",
              # RUNDE AHCI -- der SATA-Treiber nimmt fuenf Seiten.
              "ahci.fi",
              "virtio.fi", "hv.fi",
              "xhci.fi", "usb.fi",
              "vfs.fi", "mnt.fi", "fat.fi", "procfs.fi", "devfs.fi",
              "ext4.fi", "ntfs.fi", "exfat.fi",
              "part.fi", "ofs.fi",
              "fs.fi",
              "rootsel.fi", "ehci.fi", "blkdev.fi",
              "hidrep.fi", "hidin.fi", "i2chid.fi",
              # RUNDE GRAFIK-1 -- der Software-Rasterer.
              "r3dsoft.fi",
              "unixsock.fi", "sys.fi"):
        p = None
        for stamm, verz, namen in os.walk(kdir):
            verz[:] = [v for v in verz if v not in ("user", "app")]
            if d in namen:
                p = os.path.join(stamm, d)
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

    benannt = {(d, k) for _, _, _, d, k in stuecke}
    benannt |= {(d, k) for d, k, _ in EXT4_STUECKE}
    benannt |= {(d, k) for d, k, _ in NTFS_STUECKE}
    benannt |= {(d, k) for d, k, _ in EXFAT_STUECKE}
    benannt |= {(datei, anf) for _, datei, anf, _ in BEREICHE}
    for datei, w in dateien.items():
        for k in w:
            if not k.endswith("_OFF"):
                continue
            if (datei, k) in benannt or (datei, k) in KEINE_KDATA:
                continue
            fehler.append("%s:%s steht in keiner Karte -- Bereich oder "
                          "ausdruecklich kein kdata?" % (datei, k))

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

    if "ehci.fi" in dateien:
        a0 = wert(dateien["ehci.fi"], "EHCI_OFF")
        e0 = a0 + wert(dateien["ehci.fi"], "EHCI_MAX")
        pf = wert(dateien["ehci.fi"], "PF_OFF")
        if pf % 0x1000 != 0:
            fehler.append("ehci.PF_OFF 0x%X liegt nicht auf 4096" % pf)
        eh = []
        for datei, k, n in EHCI_STUECKE:
            if datei not in dateien or k not in dateien[datei]:
                fehler.append("%s:%s fehlt -- die EHCI-Karte ist veraltet"
                              % (datei, k))
                continue
            a = wert(dateien[datei], k)
            if a < a0 or a + n > e0:
                fehler.append(
                    "%s:%s 0x%X..0x%X liegt AUSSERHALB von EHCI 0x%X..0x%X"
                    % (datei, k, a, a + n, a0, e0))
            eh.append((a, a + n, datei, k))
        eh.sort()
        for i in range(len(eh)):
            a1, e1, d1, k1 = eh[i]
            for j in range(i + 1, len(eh)):
                a2, e2, d2, k2 = eh[j]
                if a2 >= e1:
                    break
                fehler.append(
                    "KOLLISION IN EHCI: %s:%s 0x%X..0x%X ueberschneidet "
                    "%s:%s 0x%X..0x%X" % (d1, k1, a1, e1, d2, k2, a2, e2))

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

    for name, liste in (("EXT4", EXT4_STUECKE), ("NTFS", NTFS_STUECKE),
                        ("EXFAT", EXFAT_STUECKE)):
        datei0 = liste[0][0]
        if datei0 not in dateien:
            continue
        a0 = wert(dateien["kstate.fi"], name + "_OFF")
        e0 = a0 + wert(dateien["kstate.fi"], name + "_MAX")
        teile = []
        for datei, k, n in liste:
            if datei not in dateien or k not in dateien[datei]:
                fehler.append("%s:%s fehlt -- die %s-Karte ist veraltet"
                              % (datei, k, name))
                continue
            a = a0 + wert(dateien[datei], k)
            if a < a0 or a + n > e0:
                fehler.append(
                    "%s:%s 0x%X..0x%X liegt AUSSERHALB von %s 0x%X..0x%X"
                    % (datei, k, a, a + n, name, a0, e0))
            teile.append((a, a + n, datei, k))
        teile.sort()
        for i in range(len(teile)):
            a1, e1, d1, k1 = teile[i]
            for j in range(i + 1, len(teile)):
                a2, e2, d2, k2 = teile[j]
                if a2 >= e1:
                    break
                fehler.append(
                    "KOLLISION IN %s: %s:%s 0x%X..0x%X ueberschneidet "
                    "%s:%s 0x%X..0x%X"
                    % (name, d1, k1, a1, e1, d2, k2, a2, e2))
        if laut:
            print("  ---- die Untergliederung von %s ----" % name)
            vorx = a0
            for a, e, dd, kk in teile:
                if a > vorx:
                    print("       ---- frei 0x%05X..0x%05X" % (vorx, a))
                print("  0x%05X..0x%05X  %s:%s" % (a, e, dd, kk))
                vorx = max(vorx, e)
            if vorx < e0:
                print("       ---- frei 0x%05X..0x%05X" % (vorx, e0))

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

    mode_words = wert(dateien["kstate.fi"], "MODE_WORDS")
    modi = {}
    for datei in ("kstate.fi", "kmain.fi"):
        pfad = finde_fi(kdir, datei)
        if pfad is None:
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
    for pfad in alle_fi(kdir):
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
