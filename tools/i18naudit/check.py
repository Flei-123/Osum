#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import subprocess
import sys
import tempfile

from PIL import Image, ImageOps

GERMAN_WORDS = [
    "Kennwort", "Anmelden", "Anmeldung", "Benutzer", "Herunterfahren", "Neu starten", "Netzwerk", "Aktualisieren",
    "Abbrechen", "Löschen", "Öffnen", "Größe", "Zurück", "Speichern", "Schließen", "Beenden", "Datei", "Bearbeiten",
    "Suchen", "Ansicht", "Hilfe", "Papierkorb", "Rechner", "Seite", "Fehler", "Keine", "Kein ", "Nicht ", "Wirklich",
    "Installieren", "Entfernen", "Programme", "Gesperrt", "Entsperren", "Energie", "Alle ",
]
UMLAUT = re.compile("[äöüßÄÖÜ]")


def literals(line):
    found = []
    i = 0
    while i < len(line):
        c = line[i]
        if c == "/" and line[i + 1:i + 2] == "/":
            break
        if c == '"':
            j = i + 1
            buf = []
            while j < len(line):
                if line[j] == "\\" and j + 1 < len(line):
                    buf.append(line[j:j + 2])
                    j += 2
                    continue
                if line[j] == '"':
                    break
                buf.append(line[j])
                j += 1
            found.append("".join(buf))
            i = j + 1
            continue
        i += 1
    return found


def is_exempt(text):
    t = text.replace("\\0", "").strip()
    if not t or t.startswith("/"):
        return True
    if re.match(r"^[a-z0-9_-]+: ", t):
        return True
    if re.match(r"^[a-z0-9_]+(\.[a-z0-9_-]+)+$", t):
        return True
    if re.match(r"^[ ]?[a-z0-9_]+=", t):
        return True
    return False


def scan_text(text):
    hits = []
    for number, line in enumerate(text.split("\n"), 1):
        for lit in literals(line):
            if is_exempt(lit):
                continue
            plain = lit.replace("\\0", "")
            if UMLAUT.search(plain) or any(w in plain for w in GERMAN_WORDS):
                hits.append((number, plain[:70]))
    return hits


def command_scan(registry):
    total = 0
    for path in open(registry, encoding="utf-8").read().split():
        hits = scan_text(open(path, encoding="utf-8", errors="replace").read())
        for number, lit in hits:
            print("  FAIL  %s:%d: %s" % (path, number, lit))
        total += len(hits)
    print("german-literals: %d" % total)
    return 1 if total else 0


def command_probe():
    sample = 'static mut T_X: [u8; 9] = "Kennwort\\0"\nstatic mut T_Y: [u8; 12] = "signin.pw\\0"\n'
    hits = scan_text(sample)
    print("probe-hits: %d" % len(hits))
    return 0 if len(hits) == 1 else 1


def ocr(ppm):
    image = Image.open(ppm).convert("L")
    image = image.resize((image.width * 2, image.height * 2), Image.LANCZOS)
    words = []
    for variant in (image, ImageOps.invert(image)):
        with tempfile.NamedTemporaryFile(suffix=".png") as tmp:
            variant.save(tmp.name)
            out = subprocess.run(["tesseract", tmp.name, "-", "--psm", "11"], capture_output=True, text=True).stdout
        words.append(out)
    return "\n".join(words)


def command_ocr(ppm, expect, absent):
    text = ocr(ppm)
    low = text.lower()
    bad = 0
    found = [w for w in expect.split(",") if w and w.lower() in low]
    if expect and not found:
        print("  FAIL  none of [%s] on screen; ocr=%r" % (expect, " ".join(text.split())[:160]))
        bad += 1
    elif expect:
        print("  OK    on screen: %s" % ",".join(found))
    seen = [w for w in absent.split(",") if w and w.lower() in low]
    if seen:
        print("  FAIL  should not be on screen: %s" % ",".join(seen))
        bad += 1
    elif absent:
        print("  OK    none of [%s] on screen" % absent)
    return 1 if bad else 0


def command_luma(ppm, limit, direction):
    image = Image.open(ppm).convert("L")
    pixels = list(image.getdata())
    mean = sum(pixels) / len(pixels)
    ok = mean < float(limit) if direction == "dark" else mean > float(limit)
    print("  %s  mean luma %.1f (%s, limit %s)" % ("OK  " if ok else "FAIL", mean, direction, limit))
    return 0 if ok else 1


KEY = re.compile(r"^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$")


def catalog(lang):
    keys = {}
    for line in open("locale/%s/messages" % lang, encoding="utf-8"):
        if line.startswith("#") or " = " not in line:
            continue
        key, value = line.rstrip("\n").split(" = ", 1)
        keys[key.strip()] = value
    return keys


def used_keys(text, prefixes):
    found = set()
    for line in text.split("\n"):
        for lit in literals(line):
            plain = lit.replace("\\0", "")
            if KEY.match(plain) and plain.split(".")[0] in prefixes:
                found.add(plain)
    return found


def command_keys(registry):
    en = catalog("en")
    de = catalog("de")
    prefixes = {k.split(".")[0] for k in en}
    bad = 0
    for path in open(registry, encoding="utf-8").read().split():
        for key in sorted(used_keys(open(path, encoding="utf-8", errors="replace").read(), prefixes)):
            if key not in en:
                print("  FAIL  %s: key %s missing in en" % (path, key))
                bad += 1
            if key not in de:
                print("  FAIL  %s: key %s missing in de" % (path, key))
                bad += 1
    print("missing-keys: %d" % bad)
    return 1 if bad else 0


def command_parity():
    en = set(catalog("en"))
    de = set(catalog("de"))
    only_en = sorted(en - de)
    only_de = sorted(de - en)
    for k in only_en:
        print("  FAIL  key %s only in en" % k)
    for k in only_de:
        print("  FAIL  key %s only in de" % k)
    print("parity: %d only-en, %d only-de" % (len(only_en), len(only_de)))
    return 1 if only_en or only_de else 0


def command_keyprobe():
    en = catalog("en")
    prefixes = {k.split(".")[0] for k in en}
    found = used_keys('static mut A: [u8; 14] = "calc.no_such_k\\0"\n', prefixes)
    print("keyprobe: %d" % len([k for k in found if k not in en]))
    return 0 if len([k for k in found if k not in en]) == 1 else 1


def main():
    cmd = sys.argv[1]
    if cmd == "scan":
        return command_scan(sys.argv[2])
    if cmd == "keys":
        return command_keys(sys.argv[2])
    if cmd == "parity":
        return command_parity()
    if cmd == "keyprobe":
        return command_keyprobe()
    if cmd == "probe":
        return command_probe()
    if cmd == "ocr":
        return command_ocr(sys.argv[2], sys.argv[3], sys.argv[4])
    if cmd == "luma":
        return command_luma(sys.argv[2], sys.argv[3], sys.argv[4])
    return 2


sys.exit(main())
