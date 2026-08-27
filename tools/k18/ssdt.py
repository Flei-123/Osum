#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/k18/ssdt.py -- EINE ACPI-TABELLE MIT EINEM AKKU DARIN, SELBST GEBAUT.

WARUM ES DIESES PROGRAMM GIBT.

Runde K18 sagt zu, dass Osum den Ladestand eines Akkus, den Zustand des
Netzteils und die Temperatur einer Thermalzone aus den ACPI-Tabellen
liest.  Eine solche Zusage ist nur dann etwas wert, wenn die Zahl, die
hinten herauskommt, von AUSSEN vorgegeben wurde -- sonst misst der Test
eine Zahl, die das Programm sich selbst gesetzt hat.  Genau davor warnt
der Auftrag dieser Runde ausdruecklich.

Die Messmaschine ist QEMU 7.2.  Ein `-device battery` gibt es dort noch
nicht (das kam erst mit QEMU 8.2), also gibt es nichts zu lesen, was
nicht von hier kaeme.  Was es gibt, ist `-acpitable`: QEMU nimmt eine
fertige Tabelle entgegen, rechnet ihr eine Pruefsumme aus und haengt sie
in die RSDT beziehungsweise XSDT ein -- dort, wo jeder Kernel seine
Tabellen sucht.

Also baut dieses Programm eine SSDT mit
    Device (BAT0)  { _HID, _UID, _STA, _BIF, _BST }
    Device (ADP0)  { _HID, _PSR }
    ThermalZone (TZ0) { _TMP }
und der Testlauf gibt die Werte auf der Befehlszeile vor.  Andere Werte
hier -> andere Ausgabe von `/bin/power`.  Keine Tabelle -> "kein Akku".
Das ist der Unterschied zwischen einer Messung und einer Behauptung.

WAS HIER MIT ABSICHT ANDERS IST ALS AUF EINEM ECHTEN LAPTOP.

Auf einem Laptop ist `_BST` eine METHODE: sie liest ueber den Embedded
Controller sechs Register und rechnet daraus ein Paket.  Hier steht ein
KONSTANTES Paket (`Name(_BST, Package(4){...})`).  Beides ist gueltiges
ACPI, aber nur das zweite kann `kernel/batt.fi` lesen -- und genau das
steht auch dort im Kopf der Datei und in `docs/ROUNDK18.md`, statt dass
so getan wuerde, als sei damit jeder Laptop erledigt.

`iasl` ist auf der Messmaschine nicht vorhanden, deshalb werden die
AML-Oktette hier von Hand erzeugt.  Das ist wenig Code, weil nur ein
winziger Teil von AML gebraucht wird: Device, ThermalZone, Name,
Package und die vier Zahlenpraefixe.

VERWENDUNG
    python3 tools/k18/ssdt.py AUSGABE [--rest N] [--voll N] [--design N]
                                      [--rate N] [--volt N] [--zustand N]
                                      [--netz 0|1] [--temp ZEHNTELKELVIN]
                                      [--modell TEXT] [--seriennr TEXT]
                                      [--art TEXT] [--hersteller TEXT]
                                      [--kein-akku] [--kein-netzteil]
                                      [--keine-zone] [--methode]

Die Datei enthaelt NUR den Rumpf der Tabelle (ohne den 36 Oktette langen
Kopf) -- so will es `-acpitable data=...`, und QEMU setzt Kopf und
Pruefsumme selbst.

`--methode` baut `_BST` absichtlich als METHODE statt als konstantes
Paket.  Das ist die GEGENPROBE zur Ehrlichkeit dieser Runde: Osum darf
dann KEINEN Akku melden, statt eine Zahl zu raten.
"""
import argparse
import sys


# --------------------------------------------------------------- AML

def pkglen(n_payload):
    """PkgLength fuer einen Rumpf von n_payload Oktetten.

    Die Laenge zaehlt SICH SELBST mit, also muss sie gesucht werden: mit
    einem Oktett Laengenfeld passen 0x3F Oktette insgesamt, mit zweien
    0xFFF und so fort.  Ein Durchgang von unten reicht, das sind hoechstens
    vier Versuche.
    """
    for width in (1, 2, 3, 4):
        total = n_payload + width
        if width == 1:
            if total <= 0x3F:
                return bytes([total])
            continue
        # oberste zwei Bits = Zahl der Folgeoktette, untere vier = Bits 3:0
        if total < (1 << (4 + 8 * (width - 1))):
            out = [((width - 1) << 6) | (total & 0x0F)]
            v = total >> 4
            for _ in range(width - 1):
                out.append(v & 0xFF)
                v >>= 8
            return bytes(out)
    raise ValueError("Paket zu gross")


def aml_int(v):
    """Die kuerzeste Form, in der eine Zahl in AML steht."""
    if v == 0:
        return b"\x00"                      # ZeroOp
    if v == 1:
        return b"\x01"                      # OneOp
    if v == 0xFFFFFFFF:
        return b"\xff"                      # OnesOp
    if v <= 0xFF:
        return b"\x0a" + bytes([v])         # BytePrefix
    if v <= 0xFFFF:
        return b"\x0b" + v.to_bytes(2, "little")
    if v <= 0xFFFFFFFF:
        return b"\x0c" + v.to_bytes(4, "little")
    return b"\x0e" + v.to_bytes(8, "little")


def aml_str(s):
    return b"\x0d" + s.encode("ascii") + b"\x00"


def nameseg(s):
    """Vier Oktette.  Kuerzere Namen werden mit '_' aufgefuellt, so will
    es die Spezifikation."""
    s = (s + "____")[:4].upper()
    return s.encode("ascii")


def name_op(seg, data):
    return b"\x08" + nameseg(seg) + data


def package(elems):
    body = bytes([len(elems)]) + b"".join(elems)
    return b"\x12" + pkglen(len(body)) + body


def device(seg, body):
    inner = nameseg(seg) + body
    return b"\x5b\x82" + pkglen(len(inner)) + inner


def thermal_zone(seg, body):
    inner = nameseg(seg) + body
    return b"\x5b\x85" + pkglen(len(inner)) + inner


def method_returning(seg, data):
    """Method(SEG, 0) { Return(data) } -- fuer die Gegenprobe."""
    inner = nameseg(seg) + bytes([0]) + b"\xa4" + data
    return b"\x14" + pkglen(len(inner)) + inner


def eisa_id(s):
    """PNP0C0A -> 0x0A0CD041, wie es in jeder DSDT steht."""
    letters, digits = s[:3], s[3:]
    v = 0
    for ch in letters:
        v = (v << 5) | (ord(ch) - ord("A") + 1)
    return (v >> 8 & 0xFF) | ((v & 0xFF) << 8) | (int(digits, 16) << 16)


# ------------------------------------------------------------ die Tabelle

def build(a):
    out = b""

    if not a.kein_akku:
        # _BIF -- was der Akku IST.  Dreizehn Elemente, die ersten neun
        # Zahlen, die letzten vier Zeichenketten.
        bif = package([
            aml_int(a.einheit),      # 0 = mW/mWh
            aml_int(a.design),       # Auslegungskapazitaet
            aml_int(a.voll),         # letzte volle Ladung
            aml_int(1),              # Technik: wiederaufladbar
            aml_int(a.dvolt),        # Auslegungsspannung
            aml_int(a.warnung),
            aml_int(a.untergrenze),
            aml_int(1),              # Koernung 1
            aml_int(1),              # Koernung 2
            aml_str(a.modell),
            aml_str(a.seriennr),
            aml_str(a.art),
            aml_str(a.hersteller),
        ])
        # _BST -- wie es ihm GERADE geht.
        bst = package([
            aml_int(a.zustand),      # Bit 0 entlaedt, Bit 1 laedt
            aml_int(a.rate),         # mW
            aml_int(a.rest),         # mWh
            aml_int(a.volt),         # mV
        ])
        body = name_op("_HID", aml_int(eisa_id("PNP0C0A")))
        body += name_op("_UID", aml_int(0))
        body += name_op("_STA", aml_int(a.sta))
        body += name_op("_BIF", bif)
        if a.methode:
            # DIE GEGENPROBE: `_BST` als Methode.  Osum kann das nicht
            # lesen und MUSS deshalb "kein Akku" melden.
            body += method_returning("_BST", bst)
        else:
            body += name_op("_BST", bst)
        out += device("BAT0", body)

    if not a.kein_netzteil:
        body = name_op("_HID", aml_str("ACPI0003"))
        body += name_op("_PSR", aml_int(a.netz))
        out += device("ADP0", body)

    if not a.keine_zone:
        body = name_op("_TMP", aml_int(a.temp))
        body += name_op("_CRT", aml_int(3732))   # 100 Grad
        out += thermal_zone("TZ00", body)

    return out


def main():
    p = argparse.ArgumentParser(add_help=True)
    p.add_argument("out")
    p.add_argument("--rest", type=int, default=3300)
    p.add_argument("--voll", type=int, default=4400)
    p.add_argument("--design", type=int, default=4400)
    p.add_argument("--rate", type=int, default=500)
    p.add_argument("--volt", type=int, default=10800)
    p.add_argument("--dvolt", type=int, default=10800)
    p.add_argument("--zustand", type=int, default=1)     # 1 = entlaedt
    p.add_argument("--warnung", type=int, default=440)
    p.add_argument("--untergrenze", type=int, default=220)
    p.add_argument("--einheit", type=int, default=0)
    p.add_argument("--sta", type=int, default=0x1F)
    p.add_argument("--netz", type=int, default=0)
    p.add_argument("--temp", type=int, default=3032)     # 30,0 Grad
    p.add_argument("--modell", default="OSUM-BAT")
    p.add_argument("--seriennr", default="0001")
    p.add_argument("--art", default="LION")
    p.add_argument("--hersteller", default="FLEITEC")
    p.add_argument("--kein-akku", action="store_true")
    p.add_argument("--kein-netzteil", action="store_true")
    p.add_argument("--keine-zone", action="store_true")
    p.add_argument("--methode", action="store_true")
    a = p.parse_args()

    data = build(a)
    with open(a.out, "wb") as f:
        f.write(data)

    # Was der Kernel daraus ausrechnen MUSS -- damit der Testlauf nicht
    # dieselbe Rechnung noch einmal aufschreiben muss.
    if a.kein_akku:
        prozent = minuten = -1
    else:
        prozent = (a.rest * 100 + a.voll // 2) // a.voll if a.voll else 0
        prozent = min(prozent, 100)
        if a.rate:
            menge = a.voll - a.rest if (a.zustand & 2) else a.rest
            minuten = (menge * 60) // a.rate
        else:
            minuten = 0
    grad = (a.temp - 2732) // 10
    print("oktette=%d prozent=%d minuten=%d grad=%d netz=%d"
          % (len(data), prozent, minuten, grad, a.netz))
    return 0


if __name__ == "__main__":
    sys.exit(main())
