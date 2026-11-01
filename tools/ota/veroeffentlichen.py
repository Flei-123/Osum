#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/ota/veroeffentlichen.py -- AUS EINEM STAND EINE AUSLIEFERUNG.

    veroeffentlichen.py <auslieferung> --stand <verz> --bund <bund.json>
                        [--notiz <text>] [--sperren <fassung>]...
                        [--fassung <n>]        nur zum Nachstellen alter Laeufe
    veroeffentlichen.py <auslieferung> --zuruecknehmen <fassung> [--bund ...]
    veroeffentlichen.py <auslieferung> --zeigen

WAS `docs/OTA.md` HIER VERMISST HAT, woertlich: "ein Bau, der aus einem
Stand Pakete, INDEX und VERZEICHNIS erzeugt und AUTOMATISCH die
Fassungsnummer hochzaehlt; ein Ort, an dem die Fassungsnummer gefuehrt
wird (sie darf nie zurueckgehen, auch nicht durch ein zurueckgenommenes
Auslieferungspaket); und eine Auslieferung, die alte Fassungen weiter
vorhaelt, damit ein Geraet, das drei Fassungen hinterherhinkt, nicht ins
Leere greift."

Alle drei stehen hier.

================================================================ DER BAU

Ein Verzeichnis, das ausgeliefert wird, sieht danach so aus:

    register.json          die gefuehrte Fassungsnummer
    journal.txt            eine Zeile je Vorgang, zum Nachlesen
    gesperrt.txt           zurueckgezogene Fassungen, eine je Zeile
    pakete/<sha256>.opk    DER VORRAT, inhaltsadressiert
    pakete/<sha256>.opk.sig
    v/<n>/                 die Auslieferung der Fassung n, vollstaendig
    aktuell/               dasselbe wie die hoechste NICHT gesperrte v/<n>

`v/<n>/` und `aktuell/` enthalten HARTE VERKNUEPFUNGEN in den Vorrat.
Deshalb kostet eine alte Fassung, die weiter vorgehalten wird, nur
einen Verzeichniseintrag -- ein Paket, das sich zwischen zwei
Fassungen nicht geaendert hat, liegt genau EINMAL auf der Platte. Das
ist der Grund, warum "alte Fassungen weiter vorhalten" hier keine
Platzfrage ist.

============================================== DIE GEFUEHRTE FASSUNGSNUMMER

`register.json` ist der einzige Ort, an dem die Zahl steht.

    {"letzte": 7, "vergeben": [1,2,3,4,5,6,7], "zurueckgenommen": [5]}

DIE REGEL, und sie ist der ganze Punkt: **die naechste Fassung ist
IMMER `letzte + 1`, und `letzte` wird geschrieben, BEVOR gebaut wird.**
Damit verbraucht auch ein Bau, der mittendrin scheitert, seine Nummer,
und eine zurueckgenommene Auslieferung gibt ihre NICHT zurueck.

Warum das wichtig ist: auf dem Geraet steht `/system/FASSUNG`, und die
Zahl darf nur steigen (Rueckschrittsschutz). Wuerde eine Nummer nach
einer Ruecknahme neu vergeben, gaebe es ZWEI verschiedene, beide
richtig signierte Auslieferungen mit derselben Zahl -- und ein Geraet,
das die erste schon hat, wuerde die zweite als Rueckschritt ablehnen.
Es waere dann fuer immer auf einer Fassung stehengeblieben, die es
nicht behalten sollte, und niemand saehe, warum.

============================================ DAS VERZEICHNIS, FASSUNG OTA2

    OTA2
    fassung        <dezimal>
    schluesselgen  <dezimal>
    kette          <gen>  <64hex neuer pub>  <128hex sig>     (0..n)
    gesperrt       <fassung>                                  (0..n)
    paket          <name> <fassung> <sha256> <oktette> <datei> <plattform>

RUNDE STORE-MOBIL: die sechste Spalte, `<plattform>`, sagt in EINEM
Wort, wofuer das Paket ist -- `osum-x86_64`, `osum-aarch64` oder
`osum-any` --, und `tools/ota/plattform.py` sagt, woher das Wort kommt
(Metadaten, sonst der ELF-Kopf in der Nutzlast). `/bin/ota` zeigt und
holt nur die Zeilen, die auf seine Maschine passen. Die Kennung bleibt
OTA2: die Spalte ist keine Sicherheitsaussage, ein altes Geraet liest
darueber hinweg.

Die ersten beiden Zeilen stehen fest, damit ein Geraet die Fassung
lesen kann, bevor es irgendetwas anderes ansieht.

WARUM DIE KENNUNG VON OTA1 AUF OTA2 GEHT, obwohl nur Zeilen dazukommen
und ein alter Zerteiler sie ueberspringen wuerde: WEIL ER SIE
UEBERSPRINGEN WUERDE. `gesperrt` ist eine Sicherheitsaussage. Ein
Geraet, das sie nicht versteht, muss ABLEHNEN und nicht einspielen --
sonst waere die Sperrliste ein Vorschlag. Aus demselben Grund lehnt ein
Geraet dieser Runde eine OTA1-Auslieferung ab: sonst reichte es, dem
Geraet ein altes, richtig signiertes OTA1-Verzeichnis vorzulegen, um
die Sperrliste loszuwerden.

DER KETTENSATZ ist in `tools/ota/schluesselbund.py` beschrieben. Er
steht in JEDEM Verzeichnis und traegt die GANZE Kette -- deshalb kann
ein Geraet, das zwei Wechsel verpasst hat, sie in einem Zug nachholen.

================================================== DER SCHLUESSEL

Dieses Programm hat den geheimen Schluessel NIE. Es ruft
`schluesselbund.py signieren` auf; wer das Signieren auf eine getrennte
Maschine legen will, ersetzt genau diesen Aufruf. Was signiert wird,
sind drei Dinge je Auslieferung: jedes Paket, der INDEX und das
VERZEICHNIS.
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
import plattform as PLT   # noqa: E402
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import opkpfad
OPK = opkpfad.path_2()
BUND_PY = os.path.join(HIER, "schluesselbund.py")


def sha256d(path_2):
    h = hashlib.sha256()
    with open(path_2, "rb") as f:
        for b in iter(lambda: f.read(1 << 16), b""):
            h.update(b)
    return h.hexdigest()


def signieren(bund, file_2, aus, wer="haupt"):
    if os.path.lexists(aus):
        os.remove(aus)
    r = subprocess.run([sys.executable, BUND_PY, bund, "signieren", file_2,
                        "-o", aus, "--wer", wer],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stdout + r.stderr)
        raise SystemExit("veroeffentlichen: signieren schlug fehl")
    return r.stdout.strip()


def bund_read(bund):
    with open(bund) as f:
        return json.load(f)


def meta_aus_opk(path_2):
    with open(path_2, "rb") as f:
        header = f.read(64)
        if header[:8] != b"OPKG0001":
            raise SystemExit("veroeffentlichen: %s ist not an OPKG file"
                             % path_2)
        ml = int.from_bytes(header[8:16], "little")
        meta = f.read(ml).decode("utf-8", "replace")
    name = fassung = None
    for z in meta.split("\n"):
        if z.startswith("name="):
            name = z[5:].strip()
        elif z.startswith("fassung="):
            fassung = z[8:].strip()
    if not name:
        raise SystemExit("veroeffentlichen: %s hat keinen Namen" % path_2)
    return name, fassung or "0"



def register_path(aus):
    return os.path.join(aus, "register.json")


def register_read(aus):
    p = register_path(aus)
    if not os.path.isfile(p):
        return {"letzte": 0, "vergeben": [], "zurueckgenommen": []}
    with open(p) as f:
        return json.load(f)


def register_write(aus, r):
    p = register_path(aus)
    tmp = p + ".neu"
    with open(tmp, "w") as f:
        json.dump(r, f, indent=1)
    os.replace(tmp, p)


def journal(aus, text):
    with open(os.path.join(aus, "journal.txt"), "a") as f:
        f.write("%s\t%s\n"
                % (time.strftime("%Y-%m-%dT%H:%M:%S"), text))


def gesperrt_read(aus):
    p = os.path.join(aus, "gesperrt.txt")
    if not os.path.isfile(p):
        return []
    out = []
    for z in open(p):
        z = z.split("#")[0].strip()
        if z.isdigit():
            out.append(int(z))
    return sorted(set(out))


def gesperrt_write(aus, list_2):
    with open(os.path.join(aus, "gesperrt.txt"), "w") as f:
        f.write("# withdrawn versions. A device does NOT install them\n")
        f.write("# any more, even if it was offline for a long time.\n")
        for n in sorted(set(list_2)):
            f.write("%d\n" % n)



def dir_text(fassung, gen, kette, gesperrt, pakete):
    z = ["OTA2", "fassung\t%d" % fassung, "schluesselgen\t%d" % gen]
    for k in kette:
        z.append("kette\t%d\t%s\t%s" % (k["gen"], k["pub"], k["sig"]))
    for g in gesperrt:
        z.append("gesperrt\t%d" % g)
    for name, pf, h, n, file_2, plattform in pakete:
        z.append("paket\t%s\t%s\t%s\t%d\t%s\t%s"
                 % (name, pf, h, n, file_2, plattform))
    return ("\n".join(z) + "\n").encode("ascii")


def verknuepfen(source, ziel):
    if os.path.exists(ziel):
        os.remove(ziel)
    try:
        os.link(source, ziel)
    except OSError:
        shutil.copy2(source, ziel)


def current_set(aus, register, gesperrt):
    kandidaten = [n for n in register["vergeben"] if n not in gesperrt
                  and os.path.isdir(os.path.join(aus, "v", str(n)))]
    if not kandidaten:
        return 0
    n = max(kandidaten)
    ak = os.path.join(aus, "aktuell")
    if os.path.isdir(ak):
        shutil.rmtree(ak)
    os.makedirs(ak)
    for d in sorted(os.listdir(os.path.join(aus, "v", str(n)))):
        verknuepfen(os.path.join(aus, "v", str(n), d), os.path.join(ak, d))
    return n


def bauen(aus, stand, bund, notiz, sperren, feste_version=None,
          signierer="haupt", chain_broken=False):
    os.makedirs(os.path.join(aus, "pakete"), exist_ok=True)
    os.makedirs(os.path.join(aus, "v"), exist_ok=True)

    reg = register_read(aus)
    if feste_version is not None:
        fassung = feste_version
        if fassung <= reg["letzte"]:
            raise SystemExit("veroeffentlichen: --fassung %d geht zurueck "
                             "(gefuehrt ist %d) -- das ist genau der Fall, "
                             "den das Register verhindert"
                             % (fassung, reg["letzte"]))
    else:
        fassung = reg["letzte"] + 1
    reg["letzte"] = fassung
    reg.setdefault("vergeben", []).append(fassung)
    register_write(aus, reg)
    journal(aus, "nummer\t%d\tvergeben%s"
            % (fassung, ("\t" + notiz) if notiz else ""))

    zv = os.path.join(aus, "v", str(fassung))
    if os.path.isdir(zv):
        shutil.rmtree(zv)
    os.makedirs(zv)

    quellen = sorted(f for f in os.listdir(stand) if f.endswith(".opk"))
    if not quellen:
        raise SystemExit("veroeffentlichen: %s hat keine .opk-Datei" % stand)
    pakete = []
    for d in quellen:
        p = os.path.join(stand, d)
        h = sha256d(p)
        vorrat = os.path.join(aus, "pakete", h + ".opk")
        if not os.path.isfile(vorrat):
            shutil.copy2(p, vorrat)
        verknuepfen(vorrat, os.path.join(zv, d))
        signieren(bund, vorrat, os.path.join(zv, d + ".sig"), signierer)
        name, pf = meta_aus_opk(p)
        plattform = PLT.plattform_von_opk(p)
        pakete.append((name, pf, h, os.path.getsize(p), d, plattform))
        print("   paket    %-14s %-8s %s" % (name, pf, plattform))

    r = subprocess.run([sys.executable, OPK, "quelle", zv],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stdout + r.stderr)
        raise SystemExit("veroeffentlichen: opk quelle schlug fehl")
    signieren(bund, os.path.join(zv, "INDEX"),
              os.path.join(zv, "INDEX.sig"), signierer)

    b = bund_read(bund)
    sperrliste = sorted(set(gesperrt_read(aus)) | set(sperren))
    gesperrt_write(aus, sperrliste)
    kette = [dict(k) for k in b["kette"]]
    if chain_broken and kette:
        sig = bytearray(bytes.fromhex(kette[-1]["sig"]))
        sig[0] ^= 1
        kette[-1]["sig"] = bytes(sig).hex()
    roh = dir_text(fassung, b["haupt"]["gen"], kette,
                           sperrliste, pakete)
    with open(os.path.join(zv, "VERZEICHNIS"), "wb") as f:
        f.write(roh)
    signieren(bund, os.path.join(zv, "VERZEICHNIS"),
              os.path.join(zv, "VERZEICHNIS.sig"), signierer)

    with open(os.path.join(zv, "schluessel.pub"), "wb") as f:
        f.write(bytes.fromhex(b["haupt"]["pub"]))

    n = current_set(aus, reg, sperrliste)
    journal(aus, "auslieferung\t%d\t%d Paket(e)\tgen %d\tkette %d\t"
            "gesperrt %s\taktuell %d"
            % (fassung, len(pakete), b["haupt"]["gen"], len(b["kette"]),
               sperrliste or "-", n))
    print("   fassung %d  %d Paket(e)  schluesselgen %d  kette %d  "
          "gesperrt %s  -> aktuell %d"
          % (fassung, len(pakete), b["haupt"]["gen"], len(b["kette"]),
             sperrliste or "-", n))
    return fassung


def zuruecknehmen(aus, fassung):
    reg = register_read(aus)
    lock = gesperrt_read(aus)
    lock.append(fassung)
    gesperrt_write(aus, lock)
    reg.setdefault("zurueckgenommen", []).append(fassung)
    register_write(aus, reg)
    n = current_set(aus, reg, gesperrt_read(aus))
    journal(aus, "zuruecknahme\t%d\tletzte bleibt %d\taktuell %d"
            % (fassung, reg["letzte"], n))
    print("   version %d withdrawn; led remains %d, current is %d"
          % (fassung, reg["letzte"], n))
    print("   NOTE: the revocation list only takes effect when a NEW "
          "Auslieferung sie traegt -- sie steht im signierten VERZEICHNIS.")
    return 0


def zeigen(aus):
    reg = register_read(aus)
    print("gefuehrte Fassung  %d" % reg["letzte"])
    print("vergeben           %s" % reg.get("vergeben", []))
    print("zurueckgenommen    %s" % reg.get("zurueckgenommen", []))
    print("gesperrt           %s" % gesperrt_read(aus))
    vd = os.path.join(aus, "v")
    if os.path.isdir(vd):
        print("vorgehalten        %s"
              % sorted(int(x) for x in os.listdir(vd) if x.isdigit()))
    p = os.path.join(aus, "pakete")
    if os.path.isdir(p):
        n = len([x for x in os.listdir(p) if x.endswith(".opk")])
        gr = sum(os.path.getsize(os.path.join(p, x))
                 for x in os.listdir(p))
        print("Vorrat             %d Pakete, %d Oktette" % (n, gr))
    return 0


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    aus = sys.argv[1]
    stand = bund = notiz = None
    sperren = []
    back = None
    nurzeigen = False
    feste = None
    signierer = "haupt"
    kaputt = False
    i = 2
    while i < len(sys.argv):
        a = sys.argv[i]
        if a == "--stand":
            i += 1
            stand = sys.argv[i]
        elif a == "--bund":
            i += 1
            bund = sys.argv[i]
        elif a == "--notiz":
            i += 1
            notiz = sys.argv[i]
        elif a == "--sperren":
            i += 1
            sperren.append(int(sys.argv[i]))
        elif a == "--fassung":
            i += 1
            feste = int(sys.argv[i])
        elif a == "--zuruecknehmen":
            i += 1
            back = int(sys.argv[i])
        elif a == "--signierer":
            i += 1
            signierer = sys.argv[i]
        elif a == "--kette-kaputt":
            kaputt = True
        elif a == "--zeigen":
            nurzeigen = True
        else:
            print(__doc__)
            return 2
        i += 1
    os.makedirs(aus, exist_ok=True)
    if nurzeigen:
        return zeigen(aus)
    if back is not None:
        return zuruecknehmen(aus, back)
    if not stand or not bund:
        print(__doc__)
        return 2
    bauen(aus, stand, bund, notiz, sperren, feste, signierer, kaputt)
    return 0


if __name__ == "__main__":
    sys.exit(main())
