#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/modul/mkomod.py -- aus einer Objektdatei ein ladbares Modul.

Ein `.omod` ist ein Kopf von 64 Oktetten, eine ELF64-Objektdatei (ET_REL)
und eine Ed25519-Signatur ueber alles davor:

      0   8   Kennung "OSUMMOD\\n"
      8   4   Formatfassung dieses Kopfes (1), kleinendig
     12   4   die Schnittstellenfassung des Kerns (ksym.ABI)
     16   8   Laenge der Nutzlast
     24   8   Merker, 0
     32  32   Name, nullbeendet
     64   n   die Objektdatei
   64+n  64   Ed25519 (RFC 8032) ueber die Oktette 0 .. 64+n

WARUM DIE SIGNATUR AM ENDE UND NICHT IM KOPF: dann ist die signierte
Nachricht ein zusammenhaengendes Stueck vom Anfang der Datei an, und der
Kern muss sie nicht erst zusammenstueckeln. `kernel/modul.fi` prueft
genau `datei[0 .. 64+n]` gegen `datei[64+n .. 128+n]`.

DIE GEGENPROBEN sind hier eingebaut und nicht nachtraeglich mit `dd`
gemacht -- eine kaputte Datei, die ein Skript nachtraeglich verbiegt,
misst am naechsten Tag etwas anderes.

    --abi N        eine andere Schnittstellenfassung in den Kopf
    --kein-sig     die Signatur durch 64 Nullen ersetzen
    --sig-dreh     ein Oktett der gueltigen Signatur kippen
    --nutz-dreh N  ein Oktett der NUTZLAST kippen (die Signatur bleibt
                   gueltig ueber die alte Nutzlast, also faellt sie)
    --kennung      die Kennung verderben
    --text-dreh N  N Oktette IM PROGRAMMTEXT durch 0xCC (int3) ersetzen
                   UND danach SIGNIEREN -- das ist das absichtlich
                   kaputte, aber echt signierte Modul aus Teil 3 der
                   Aufgabe: es kommt durch alle Riegel und stuerzt dann
                   in Ring 0 ab.

Verwendung:
    mkomod.py bauen <ein.o> <aus.omod> --name NAME --abi N --seed DATEI
    mkomod.py zeigen <datei.omod>
"""
import hashlib
import struct
import subprocess
import sys
import os

KENNUNG = b"OSUMMOD\n"
FORMAT = 1
HDR = 64
SIGLEN = 64


def ed25519_sign(seed: bytes, msg: bytes) -> bytes:
    """Signieren. ZWEI Umsetzungen, und sie muessen sich einig sein.

    Derselbe Gedanke wie in `orientstore/docs/KATALOG-FORMAT.md`
    Abschnitt 4: sind sich zwei Umsetzungen uneins, ist eine davon
    kaputt, und das ist schlimmer als eine ungueltige Signatur.
    """
    aus = []
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import (
            Ed25519PrivateKey)
        sk = Ed25519PrivateKey.from_private_bytes(seed)
        aus.append(("cryptography", sk.sign(msg)))
    except ImportError:
        pass
    try:
        import nacl.signing
        sk = nacl.signing.SigningKey(seed)
        aus.append(("pynacl", bytes(sk.sign(msg).signature)))
    except ImportError:
        pass
    if not aus:
        sys.exit("mkomod: weder `cryptography` noch `pynacl` vorhanden")
    if len(aus) > 1 and aus[0][1] != aus[1][1]:
        sys.exit("mkomod: %s und %s sind sich uneins -- eine der beiden "
                 "ist kaputt" % (aus[0][0], aus[1][0]))
    return aus[0][1]


def pubkey(seed: bytes) -> bytes:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import (
        Ed25519PrivateKey)
    from cryptography.hazmat.primitives import serialization
    sk = Ed25519PrivateKey.from_private_bytes(seed)
    return sk.public_key().public_bytes(serialization.Encoding.Raw,
                                        serialization.PublicFormat.Raw)


def strip_debug(pfad: str) -> bytes:
    """Die Fehlersuchabschnitte weg.

    Sie sind nicht SHF_ALLOC und wuerden vom Lader ohnehin uebergangen --
    aber ihre Relokationen stehen mit in der Datei, und sie machen aus 63
    KiB 3,6 MiB. Was der Kern nicht braucht, gehoert nicht in eine Datei,
    die er von der Platte liest.
    """
    tmp = pfad + ".stripped"
    r = subprocess.run(["objcopy", "--strip-debug", pfad, tmp],
                       capture_output=True)
    if r.returncode != 0:
        sys.exit("mkomod: objcopy: " + r.stderr.decode()[:200])
    d = open(tmp, "rb").read()
    os.unlink(tmp)
    return d


def text_bereich(elf: bytes):
    """Wo `.text` in der Objektdatei liegt (Versatz, Laenge).

    Wird nur fuer `--text-dreh` gebraucht: die Gegenprobe soll den
    PROGRAMMTEXT verderben und nicht irgendein Oktett, denn nur so
    stuerzt das Modul wirklich ab, statt eine falsche Zahl zu liefern.
    """
    shoff = struct.unpack_from("<Q", elf, 0x28)[0]
    shent = struct.unpack_from("<H", elf, 0x3A)[0]
    shnum = struct.unpack_from("<H", elf, 0x3C)[0]
    shstrndx = struct.unpack_from("<H", elf, 0x3E)[0]
    sh = shoff + shstrndx * shent
    stroff = struct.unpack_from("<Q", elf, sh + 24)[0]
    for i in range(shnum):
        sh = shoff + i * shent
        nameoff = struct.unpack_from("<I", elf, sh)[0]
        ende = elf.index(b"\0", stroff + nameoff)
        name = elf[stroff + nameoff:ende].decode()
        if name == ".text":
            return (struct.unpack_from("<Q", elf, sh + 24)[0],
                    struct.unpack_from("<Q", elf, sh + 32)[0])
    sys.exit("mkomod: kein .text in der Objektdatei")


def bauen(argv):
    ein = argv[0]
    aus = argv[1]
    name = "unbenannt"
    abi = 1
    seedpfad = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "pruef.seed")
    kein_sig = False
    sig_dreh = False
    nutz_dreh = -1
    kennung_kaputt = False
    text_dreh = 0
    i = 2
    while i < len(argv):
        a = argv[i]
        if a == "--name":
            name = argv[i + 1]; i += 2
        elif a == "--abi":
            abi = int(argv[i + 1]); i += 2
        elif a == "--seed":
            seedpfad = argv[i + 1]; i += 2
        elif a == "--kein-sig":
            kein_sig = True; i += 1
        elif a == "--sig-dreh":
            sig_dreh = True; i += 1
        elif a == "--nutz-dreh":
            nutz_dreh = int(argv[i + 1]); i += 2
        elif a == "--kennung":
            kennung_kaputt = True; i += 1
        elif a == "--text-dreh":
            text_dreh = int(argv[i + 1]); i += 2
        else:
            sys.exit("mkomod: unbekannte Option " + a)

    seed = open(seedpfad, "rb").read()
    if len(seed) != 32:
        sys.exit("mkomod: der Same ist %d Oktette lang, nicht 32" % len(seed))

    nutz = bytearray(strip_debug(ein))

    if text_dreh > 0:
        off, laenge = text_bereich(bytes(nutz))
        # In die MITTE des Programmtextes, damit `modul_init` (das ganz
        # vorne liegt) noch anspringbar ist und der Absturz WAEHREND des
        # Laufs kommt und nicht schon beim Sprung.
        anfang = off + laenge // 2
        for k in range(text_dreh):
            nutz[anfang + k] = 0xCC

    nb = bytes(nutz)
    kopf = bytearray(HDR)
    kopf[0:8] = KENNUNG
    struct.pack_into("<I", kopf, 8, FORMAT)
    struct.pack_into("<I", kopf, 12, abi)
    struct.pack_into("<Q", kopf, 16, len(nb))
    struct.pack_into("<Q", kopf, 24, 0)
    nb_name = name.encode()[:31]
    kopf[32:32 + len(nb_name)] = nb_name

    msg = bytes(kopf) + nb
    sig = bytearray(ed25519_sign(seed, msg))

    if nutz_dreh >= 0:
        # NACH dem Signieren: die Signatur bleibt gueltig ueber die alte
        # Nutzlast und faellt damit ueber die neue.
        nb = bytearray(nb)
        nb[nutz_dreh] ^= 0xFF
        nb = bytes(nb)
    if kein_sig:
        sig = bytearray(SIGLEN)
    if sig_dreh:
        sig[0] ^= 0x01
    if kennung_kaputt:
        kopf[0] = 0x58

    daten = bytes(kopf) + nb + bytes(sig)
    open(aus, "wb").write(daten)
    print("%s (%d Oktette: Kopf %d, Nutzlast %d, Signatur %d), abi=%d, "
          "name=%s, sha256=%s"
          % (aus, len(daten), HDR, len(nb), SIGLEN, abi, name,
             hashlib.sha256(daten).hexdigest()[:16]))
    return 0


def zeigen(argv):
    d = open(argv[0], "rb").read()
    if len(d) < HDR + SIGLEN:
        sys.exit("zu kurz")
    print("kennung   %r" % d[0:8])
    print("format    %d" % struct.unpack_from("<I", d, 8)[0])
    print("abi       %d" % struct.unpack_from("<I", d, 12)[0])
    n = struct.unpack_from("<Q", d, 16)[0]
    print("nutzlast  %d" % n)
    print("name      %s" % d[32:64].split(b"\0")[0].decode())
    print("laenge    %d (erwartet %d)" % (len(d), HDR + n + SIGLEN))
    seedpfad = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "pruef.seed")
    if os.path.exists(seedpfad):
        seed = open(seedpfad, "rb").read()
        from cryptography.hazmat.primitives.asymmetric.ed25519 import (
            Ed25519PublicKey)
        pk = Ed25519PublicKey.from_public_bytes(pubkey(seed))
        try:
            pk.verify(d[HDR + n:HDR + n + SIGLEN], d[0:HDR + n])
            print("signatur  gueltig")
        except Exception:
            print("signatur  UNGUELTIG")
    return 0


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    if argv[1] == "bauen":
        return bauen(argv[2:])
    if argv[1] == "zeigen":
        return zeigen(argv[2:])
    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
