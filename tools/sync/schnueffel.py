#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    schnueffel.py <speicherverz> <klartextbaum> <passphrase> <N> <r>
"""
import binascii
import hashlib
import hmac as pyhmac
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ORACLE = os.path.join(ROOT, ".probe", "syncoracle")
BLOCK = 4096

fails = []
count = 0


def eq(name, ist, soll):
    global count
    count += 1
    if ist != soll:
        fails.append("%s: %r, erwartet %r" % (name, ist, soll))
        print("  FAIL  %s: %r, erwartet %r" % (name, ist, soll))
    else:
        print("  OK    %s: %r" % (name, ist))


def ask(lines):
    p = subprocess.run([ORACLE], input="\n".join(lines) + "\n",
                       capture_output=True, text=True)
    out = [l for l in p.stdout.split("\n")]
    while out and out[-1] == "":
        out.pop()
    return out


def bloecke(path_2):
    d = open(path_2, "rb").read()
    aus = []
    i = 0
    while i < len(d):
        b = d[i:i + BLOCK]
        aus.append(b + bytes(BLOCK - len(b)))
        i += BLOCK
    return aus


def index_names(mem):
    names = set()
    p = os.path.join(mem, "INDEX")
    if not os.path.exists(p):
        return names
    for z in open(p, "rb").read().split(b"\n"):
        if len(z) >= 64:
            names.add(z[:64].decode("ascii", "replace").lower())
    return names


def main():
    if len(sys.argv) < 6:
        print(__doc__)
        return 2
    mem, tree, passphrase, N, r = sys.argv[1:6]
    N, r = int(N), int(r)
    habe, habe_nicht, modus = [], [], None
    for a in sys.argv[6:]:
        if a == "--habe":
            modus = habe
        elif a == "--habe-nicht":
            modus = habe_nicht
        elif modus is not None:
            modus.append(a)

    brand = b"GEHEIMNIS-4711"
    all_2 = b""
    dateien = []
    for f in sorted(os.listdir(mem)):
        p = os.path.join(mem, f)
        if os.path.isfile(p):
            dateien.append(f)
            all_2 += open(p, "rb").read()
    print("  the memory: %s, %d octets together"
          % (", ".join(dateien), len(all_2)))
    eq("(b) der Klartext steht NICHT im Speicher", brand in all_2, False)
    eq("(b) und auch nicht als Dateiname",
           any(brand.decode() in f for f in dateien), False)
    imbaum = False
    for root, _, fs in os.walk(tree):
        for f in fs:
            if brand in open(os.path.join(root, f), "rb").read():
                imbaum = True
    eq("(b) GEGENPROBE: im Klartextbaum steht sie sehr wohl", imbaum, True)
    names = index_names(mem)
    eq("(b) der Index hat Namen", len(names) > 0, True)

    header = os.path.join(mem, "KOPF")
    felder = {}
    if os.path.exists(header):
        for z in open(header, "rb").read().split(b"\n"):
            t = z.split()
            if len(t) == 2:
                felder[t[0].decode("ascii", "replace")] = t[1].decode(
                    "ascii", "replace")
    salz = bytes.fromhex(felder["salz"]) if "salz" in felder else None
    if salz is None:
        print("  no salt found -- (c) cannot be measured")
        return 1
    pkey = hashlib.scrypt(passphrase.encode(), salt=salz, n=N, r=r, p=1,
                          dklen=32, maxmem=(128 * N * r * 2) + (1 << 22))
    mk = ask(["hopen %s %s %s" % (binascii.hexlify(pkey).decode(),
                                  felder["pnonce"], felder["phuelle"])])[0]
    if mk == "FAIL" or len(mk) != 64:
        print("  the envelope cannot be opened -- (c) measures nothing")
        return 1
    bund = ask(["bundmk %s %s" % (mk, felder["salz"])])[0]
    if bund == "FAIL" or len(bund) != 320:
        print("  the bundle cannot be derived -- (c) measures nothing")
        return 1
    KN = bytes.fromhex(bund[64:128])
    eq("(c) der Schluesselbund des Besitzers stimmt mit dem KOPF ueberein",
           bund[256:320], felder.get("check", felder.get("pruef", "")))

    def naiv_treffer(dateien):
        t = 0
        for f in dateien:
            for b in bloecke(f):
                if hashlib.sha256(b).hexdigest() in names:
                    t += 1
                    break
        return t

    def hmac_treffer(dateien):
        t = 0
        for f in dateien:
            for b in bloecke(f):
                if pyhmac.new(KN, b, hashlib.sha256).hexdigest() in names:
                    t += 1
                    break
        return t

    print("  (c) the attacker suspects %d files, %d of which "
          "der Nutzer wirklich" % (len(habe) + len(habe_nicht), len(habe)))
    eq("(c) NAIV (blanker SHA-256): erkannte Dateien", naiv_treffer(habe), 0)
    eq("(c) NAIV: falsch erkannte", naiv_treffer(habe_nicht), 0)
    eq("(c) GEGENPROBE mit K_NAME: der Speicher HAT die Dateien",
           hmac_treffer(habe), len(habe))
    eq("(c) GEGENPROBE mit K_NAME: und die anderen nicht",
           hmac_treffer(habe_nicht), 0)

    naiv_index = set()
    for f in habe:
        for b in bloecke(f):
            naiv_index.add(hashlib.sha256(b).hexdigest())
    t = sum(1 for f in habe
            if any(hashlib.sha256(b).hexdigest() in naiv_index
                   for b in bloecke(f)))
    tn = sum(1 for f in habe_nicht
             if any(hashlib.sha256(b).hexdigest() in naiv_index
                    for b in bloecke(f)))
    eq("(c) IN EINEM NAIVEN SPEICHER waere der Angriff aufgegangen",
           t, len(habe))
    eq("(c) und haette die fremden Dateien NICHT gemeldet", tn, 0)

    n_bloecke = len(names)
    groessen = set()
    idx = os.path.join(mem, "INDEX")
    if os.path.exists(idx):
        for z in open(idx, "rb").read().split(b"\n"):
            t2 = z.split(b"\t")
            if len(t2) == 3:
                groessen.add(int(t2[2]))
    print("  WAS DER SERVER TROTZDEM SIEHT: %d Bloecke, Groessen %s"
          % (n_bloecke, sorted(groessen)))
    eq("alle Bloecke sind gleich gross", len(groessen), 1)
    if fails:
        print("  %d von %d Zusagen gefallen" % (len(fails), count))
        return 1
    print("schnueffel: %d Zusagen, 0 Fehler" % count)
    return 0


if __name__ == "__main__":
    sys.exit(main())
