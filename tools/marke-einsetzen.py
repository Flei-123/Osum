#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
#
# tools/marke-einsetzen.py -- den Namen aus marke.conf in den Kernbaum.
#
#   python3 tools/marke-einsetzen.py <baum> <marke.conf> <fassungshash>
#
# Das ist Firns Ersatz fuer `option_env!` aus der Vorlage
# (/root/projects/freeviewer/src/brand.rs): Rust liest die Umgebung
# beim Uebersetzen selbst, Firn kann das nicht -- also tut es der Bau.
# Die Reihenfolge ist die des Repos (tools/config, OSUM_GUI):
#
#     OSUM_MARKE_<FELD> in der Umgebung   schlaegt   marke.conf
#
# `<baum>` ist die /tmp-Kopie, aus der `firnc` uebersetzt -- NICHT der
# Arbeitsbaum. Der bleibt sauber; das ist dieselbe Regel wie bei der
# Fassungsnummer, und sie ist der Grund, warum `git status` nach einem
# Bau nichts meldet.
#
# ERSETZT ZWEI DINGE:
#
#   kernel/brand.fi     die sechs Platzhalterfelder
#   kernel/version.fi   "<KURZ> <hash>" -- die Zeile, die der Kern beim
#                       Start als erstes sagt und die in
#                       docs/BLECH-BEREIT.md der Frischebeleg ist
#
# UND ES BRICHT AB, WENN ETWAS NICHT PASST. Ein Bau, der bei einem zu
# langen Namen stillschweigend abschneidet, liefert ein Abbild aus, auf
# dem "OrientO" steht. Lieber kein Abbild als ein falsches.
import os
import re
import sys

# muessen zu `const MAX` / `const MAX_URL` in kernel/brand.fi passen
MAX = 32
MAX_URL = 96
# Feldname -> erwartete Elementzahl im Firn-Literal
FELDER = {
    "PRODUKT": MAX,
    "KERN": MAX,
    "HERSTELLER": MAX,
    "KURZ": MAX,
    "WEB": MAX_URL,
    "FEED": MAX_URL,
}


def lies_marke(pfad):
    """marke.conf lesen, dann die Umgebung daruebergelegt."""
    werte = {}
    with open(pfad, encoding="utf-8") as f:
        for zeile in f:
            z = zeile.strip()
            if not z or z.startswith("#") or "=" not in z:
                continue
            k, v = z.split("=", 1)
            k = k.strip()
            v = v.strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
                v = v[1:-1]
            werte[k] = v

    # DIE UMGEBUNG SCHLAEGT DIE DATEI -- das ist der ganze Trick der
    # Vorlage. Wer umbenennen will, ruft den Bau mit OSUM_MARKE_* auf
    # und fasst keine Zeile Quelltext an.
    for k in FELDER:
        env = os.environ.get("OSUM_MARKE_" + k)
        if env is not None and env != "":
            werte[k] = env

    fehlt = [k for k in FELDER if k not in werte]
    if fehlt:
        sys.exit("marke: diese Felder fehlen: %s" % ", ".join(sorted(fehlt)))
    for k, n in FELDER.items():
        v = werte[k]
        if not v:
            sys.exit("marke: %s ist leer" % k)
        if len(v) > n - 1:
            sys.exit("marke: %s ist %d Zeichen lang, hoechstens %d sind "
                     "erlaubt (kernel/brand.fi)" % (k, len(v), n - 1))
        # Ein Anzeigetext mit einem Anfuehrungszeichen oder einem
        # Rueckstrich darin wuerde das Firn-Literal zerreissen. Das ist
        # kein Fall, den man rettet -- das ist einer, den man meldet.
        if '"' in v or "\\" in v or "\n" in v:
            sys.exit("marke: %s enthaelt ein Zeichen, das in einem "
                     "Firn-Literal nicht stehen darf" % k)
    if werte["KURZ"] != werte["KURZ"].lower() or " " in werte["KURZ"]:
        sys.exit("marke: KURZ muss kleingeschrieben und ohne Leerzeichen "
                 "sein (es steht in Dateinamen)")
    return werte


def literal(text, laenge):
    """Firn-Literal mit GENAU `laenge` Elementen: Text, dann Nullen."""
    rest = laenge - len(text)
    if rest < 1:
        sys.exit("intern: '%s' passt nicht in %d Elemente" % (text, laenge))
    return '"' + text + "\\0" * rest + '"'


def setz_marke(pfad, werte):
    with open(pfad, encoding="utf-8") as f:
        s = f.read()
    for k, erwartet in FELDER.items():
        name = "s_" + k.lower()
        muster = re.compile(
            r'(static mut %s: \[u8; (\d+)\] = )"[^"]*"' % re.escape(name))
        m = muster.search(s)
        if not m:
            sys.exit("kernel/brand.fi: Feld %s nicht gefunden" % name)
        n = int(m.group(2))
        if n != erwartet:
            sys.exit("kernel/brand.fi: %s hat %d Elemente, erwartet %d -- "
                     "marke-einsetzen.py und marke.fi sind auseinander"
                     % (name, n, erwartet))
        s = muster.sub(lambda mm: mm.group(1) + literal(werte[k], n), s, 1)
    # GEGENPROBE: steht in einem der Felder noch ein Fragezeichen, hat
    # eine Ersetzung nicht gegriffen. Ein Abbild mit "????????" auf dem
    # Startschirm ist kein Abbild, das man ausliefert.
    for k in FELDER:
        rest = re.search(r'static mut s_%s: \[u8; \d+\] = "([^"]*)"'
                         % k.lower(), s)
        if rest and "?" in rest.group(1):
            sys.exit("kernel/brand.fi: %s ist noch ein Platzhalter" % k)
    with open(pfad, "w", encoding="utf-8") as f:
        f.write(s)


def setz_fassung(pfad, kurz, hash_):
    """`osum ????????` -> `<KURZ> <hash>`, auf die Feldlaenge gepolstert."""
    with open(pfad, encoding="utf-8") as f:
        s = f.read()
    muster = re.compile(r'(static mut s_fassung: \[u8; (\d+)\] = )"[^"]*"')
    m = muster.search(s)
    if not m:
        sys.exit("kernel/version.fi: s_fassung nicht gefunden")
    n = int(m.group(2))
    text = "%s %s" % (kurz, hash_)
    if len(text) > n - 1:
        sys.exit("kernel/version.fi: '%s' passt nicht in %d Elemente -- "
                 "KURZ ist zu lang" % (text, n))
    s = muster.sub(lambda mm: mm.group(1) + literal(text, n), s, 1)
    with open(pfad, "w", encoding="utf-8") as f:
        f.write(s)
    return text


def finde(baum, name):
    """RUNDE O-STRUKTUR: `brand.fi` und `version.fi` lagen bis hierher
    fest unter `<baum>/kernel/`. Seit die Kerndateien in Schichten
    liegen, wird gesucht statt buchstabiert -- genau wie in
    `tools/build-kernel.sh` und `tools/kfind.sh`.

    `kernel/user/` und `kernel/app/` bleiben aussen vor: das sind
    eigene Programme, und `brand.fi` gibt es dort noch einmal."""
    wurzel = os.path.join(baum, "kernel")
    for stamm, verz, namen in os.walk(wurzel):
        verz[:] = [d for d in verz if d not in ("user", "app")]
        if name in namen:
            return os.path.join(stamm, name)
    sys.exit("marke-einsetzen.py: %s liegt nirgends unter %s" % (name, wurzel))


def main():
    if len(sys.argv) != 4:
        sys.exit("Aufruf: marke-einsetzen.py <baum> <marke.conf> <hash>")
    baum, conf, hash_ = sys.argv[1], sys.argv[2], sys.argv[3]
    werte = lies_marke(conf)
    setz_marke(finde(baum, "brand.fi"), werte)
    zeile = setz_fassung(finde(baum, "version.fi"), werte["KURZ"], hash_)
    print("marke: PRODUKT=%s KERN=%s HERSTELLER=%s KURZ=%s"
          % (werte["PRODUKT"], werte["KERN"], werte["HERSTELLER"],
             werte["KURZ"]))
    print("marke: WEB=%s" % werte["WEB"])
    print("marke: FEED=%s" % werte["FEED"])
    print("marke: Fassungszeile '%s'" % zeile)


main()
