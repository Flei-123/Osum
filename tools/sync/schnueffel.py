#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/sync/schnueffel.py -- DER SERVER, DER MITLESEN WILL.

Dieses Programm ist der Angreifer der Runde. Es bekommt genau das, was
ein Anbieter hat -- den ganzen Blockspeicher, jedes Oktett davon -- und
versucht damit zwei Dinge:

  (b) DEN KLARTEXT FINDEN. Eine bekannte Zeichenkette
      ("GEHEIMNIS-4711") wird im gesamten Speicher gesucht: in den
      Oktetten, in den Namen, in der Wurzel und in den Dateinamen. Sie
      darf NIRGENDS vorkommen.

  (c) EINE DATEI WIEDERERKENNEN. Der bekannte Angriff gegen konvergente
      Verschluesselung: der Angreifer hat eine Datei im Verdacht,
      rechnet den Namen aus, den sie im Speicher haette, und sieht nach.
      Er wird ZWEIMAL gefuehrt:

        NAIV   der Name ist der blanke SHA-256 des Blocks. Der Angreifer
               braucht nichts als die vermutete Datei.
        ECHT   der Name ist HMAC(K_NAME, Block). Der Angreifer hat
               K_NAME nicht.

      Und mit der GEGENPROBE, ohne die "nicht gefunden" nichts wert
      waere: mit K_NAME (den nur der Besitzer hat) werden dieselben
      Dateien SEHR WOHL gefunden. Der Speicher enthaelt sie also -- der
      Angriff scheitert am Schluessel und nicht daran, dass nichts da
      ist.

Verwendung:

    schnueffel.py <speicherverz> <klartextbaum> <passphrase> <N> <r>
                  [--habe <datei>...] [--habe-nicht <datei>...]

`<speicherverz>` enthaelt PACK, INDEX und ROOT, so wie sie aus dem
Plattenabbild von Osum herausgeholt wurden. `<klartextbaum>` ist der
Baum, wie ihn der WIRT gebaut hat -- der Angreifer im Fall (c) darf
Dateien kennen, das ist ja die Annahme des Angriffs.
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


def gleich(name, ist, soll):
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


def bloecke(pfad):
    """Die 4096-Oktett-Bloecke einer Datei, aufgefuellt wie sync es tut."""
    d = open(pfad, "rb").read()
    aus = []
    i = 0
    while i < len(d):
        b = d[i:i + BLOCK]
        aus.append(b + bytes(BLOCK - len(b)))
        i += BLOCK
    return aus


def index_namen(speicher):
    namen = set()
    p = os.path.join(speicher, "INDEX")
    if not os.path.exists(p):
        return namen
    for z in open(p, "rb").read().split(b"\n"):
        if len(z) >= 64:
            namen.add(z[:64].decode("ascii", "replace").lower())
    return namen


def main():
    if len(sys.argv) < 6:
        print(__doc__)
        return 2
    speicher, baum, passphrase, N, r = sys.argv[1:6]
    N, r = int(N), int(r)
    habe, habe_nicht, modus = [], [], None
    for a in sys.argv[6:]:
        if a == "--habe":
            modus = habe
        elif a == "--habe-nicht":
            modus = habe_nicht
        elif modus is not None:
            modus.append(a)

    # ---------------------------------------------- (b) der Klartext
    marke = b"GEHEIMNIS-4711"
    alle = b""
    dateien = []
    for f in sorted(os.listdir(speicher)):
        p = os.path.join(speicher, f)
        if os.path.isfile(p):
            dateien.append(f)
            alle += open(p, "rb").read()
    print("  der Speicher: %s, %d Oktette zusammen"
          % (", ".join(dateien), len(alle)))
    gleich("(b) der Klartext steht NICHT im Speicher", marke in alle, False)
    gleich("(b) und auch nicht als Dateiname",
           any(marke.decode() in f for f in dateien), False)
    # Die Gegenprobe zur Gegenprobe: die Marke steht wirklich im Baum.
    imbaum = False
    for wurzel, _, fs in os.walk(baum):
        for f in fs:
            if marke in open(os.path.join(wurzel, f), "rb").read():
                imbaum = True
    gleich("(b) GEGENPROBE: im Klartextbaum steht sie sehr wohl", imbaum, True)
    # Und: kein Name im INDEX ist der blanke Hash irgendeines Blocks des
    # Baums -- das ist (c) in seiner scharfen Form.
    namen = index_namen(speicher)
    gleich("(b) der Index hat Namen", len(namen) > 0, True)

    # ------------------------------- (c) der Wiedererkennungsangriff
    # Den Schluessel K_NAME holt sich der BESITZER (fuer die Gegenprobe),
    # nicht der Angreifer.
    # DER WEG ZUM SCHLUESSELBUND IST DER WEG DES BESITZERS, und nicht die
    # Abkuerzung. Der Hauptschluessel eines echten Kontos ist ZUFAELLIG
    # (kbund.kb_neu) und liegt eingepackt in der Huelle; die Passphrase
    # oeffnet nur die Huelle. Wer statt dessen den Hauptschluessel aus der
    # Passphrase ableitet, bekommt einen Bund, der zu nichts passt -- und
    # dann meldet die Gegenprobe "0 von 3 gefunden" und sieht aus wie ein
    # Erfolg der Verschluesselung. Genau das ist hier einmal passiert.
    # Also, drei Schritte, jeder einzeln nachpruefbar:
    #   1. Einpackschluessel = scrypt(Passphrase, Salz) -- mit PYTHONS
    #      hashlib.scrypt, nicht mit unserem Code. Passt der Bund am Ende,
    #      ist das nebenbei der Beweis, dass unser scrypt richtig rechnet.
    #   2. Hauptschluessel = Huelle oeffnen (XChaCha20-Poly1305).
    #   3. Bund = HKDF(Hauptschluessel, Salz).
    kopf = os.path.join(speicher, "KOPF")
    felder = {}
    if os.path.exists(kopf):
        for z in open(kopf, "rb").read().split(b"\n"):
            t = z.split()
            if len(t) == 2:
                felder[t[0].decode("ascii", "replace")] = t[1].decode(
                    "ascii", "replace")
    salz = bytes.fromhex(felder["salz"]) if "salz" in felder else None
    if salz is None:
        print("  kein Salz gefunden -- (c) kann nicht gemessen werden")
        return 1
    pkey = hashlib.scrypt(passphrase.encode(), salt=salz, n=N, r=r, p=1,
                          dklen=32, maxmem=(128 * N * r * 2) + (1 << 22))
    mk = ask(["hopen %s %s %s" % (binascii.hexlify(pkey).decode(),
                                  felder["pnonce"], felder["phuelle"])])[0]
    if mk == "FAIL" or len(mk) != 64:
        print("  die Huelle laesst sich nicht oeffnen -- (c) misst nichts")
        return 1
    bund = ask(["bundmk %s %s" % (mk, felder["salz"])])[0]
    if bund == "FAIL" or len(bund) != 320:
        print("  der Bund laesst sich nicht ableiten -- (c) misst nichts")
        return 1
    KN = bytes.fromhex(bund[64:128])
    # Und die Probe auf die Probe: der Pruefwert im KOPF ist der fuenfte
    # Unterschluessel. Stimmt er, ist der ganze Weg richtig gegangen.
    gleich("(c) der Schluesselbund des Besitzers stimmt mit dem KOPF ueberein",
           bund[256:320], felder.get("pruef", ""))

    def naiv_treffer(dateien):
        t = 0
        for f in dateien:
            for b in bloecke(f):
                if hashlib.sha256(b).hexdigest() in namen:
                    t += 1
                    break
        return t

    def hmac_treffer(dateien):
        t = 0
        for f in dateien:
            for b in bloecke(f):
                if pyhmac.new(KN, b, hashlib.sha256).hexdigest() in namen:
                    t += 1
                    break
        return t

    # Der Angreifer rechnet die NAIVEN Namen aus -- so, wie jeder
    # inhaltsadressierte Speicher ohne Schluessel sie bilden wuerde.
    print("  (c) der Angreifer hat %d Dateien im Verdacht, %d davon hat "
          "der Nutzer wirklich" % (len(habe) + len(habe_nicht), len(habe)))
    gleich("(c) NAIV (blanker SHA-256): erkannte Dateien", naiv_treffer(habe), 0)
    gleich("(c) NAIV: falsch erkannte", naiv_treffer(habe_nicht), 0)
    gleich("(c) GEGENPROBE mit K_NAME: der Speicher HAT die Dateien",
           hmac_treffer(habe), len(habe))
    gleich("(c) GEGENPROBE mit K_NAME: und die anderen nicht",
           hmac_treffer(habe_nicht), 0)

    # Und die Simulation des naiven Speichers, damit die Zahl oben nicht
    # nur "0 von 3" heisst, sondern auch "waere 3 von 3 gewesen".
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
    gleich("(c) IN EINEM NAIVEN SPEICHER waere der Angriff aufgegangen",
           t, len(habe))
    gleich("(c) und haette die fremden Dateien NICHT gemeldet", tn, 0)

    # ------------------------------------ was der Server SEHR WOHL sieht
    n_bloecke = len(namen)
    groessen = set()
    idx = os.path.join(speicher, "INDEX")
    if os.path.exists(idx):
        for z in open(idx, "rb").read().split(b"\n"):
            t2 = z.split(b"\t")
            if len(t2) == 3:
                groessen.add(int(t2[2]))
    print("  WAS DER SERVER TROTZDEM SIEHT: %d Bloecke, Groessen %s"
          % (n_bloecke, sorted(groessen)))
    gleich("alle Bloecke sind gleich gross", len(groessen), 1)
    if fails:
        print("  %d von %d Zusagen gefallen" % (len(fails), count))
        return 1
    print("schnueffel: %d Zusagen, 0 Fehler" % count)
    return 0


if __name__ == "__main__":
    sys.exit(main())
