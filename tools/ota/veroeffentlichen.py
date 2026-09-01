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
    paket          <name> <fassung> <sha256> <oktette> <datei>

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
OPK = os.environ.get("OPK", "/root/orientos-install/pkg/opk.py")
BUND_PY = os.path.join(HIER, "schluesselbund.py")


def sha256d(pfad):
    h = hashlib.sha256()
    with open(pfad, "rb") as f:
        for b in iter(lambda: f.read(1 << 16), b""):
            h.update(b)
    return h.hexdigest()


def signieren(bund, datei, aus, wer="haupt"):
    # Erst wegnehmen: das Ziel kann eine HARTE VERKNUEPFUNG in den Vorrat
    # sein (aus einem aelteren Stand dieses Werkzeugs), und ein Schreiben
    # darauf traefe jede andere Verknuepfung mit.
    if os.path.lexists(aus):
        os.remove(aus)
    r = subprocess.run([sys.executable, BUND_PY, bund, "signieren", datei,
                        "-o", aus, "--wer", wer],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stdout + r.stderr)
        raise SystemExit("veroeffentlichen: signieren schlug fehl")
    return r.stdout.strip()


def bund_lesen(bund):
    with open(bund) as f:
        return json.load(f)


def meta_aus_opk(pfad):
    with open(pfad, "rb") as f:
        kopf = f.read(64)
        if kopf[:8] != b"OPKG0001":
            raise SystemExit("veroeffentlichen: %s ist keine OPKG-Datei"
                             % pfad)
        ml = int.from_bytes(kopf[8:16], "little")
        meta = f.read(ml).decode("utf-8", "replace")
    name = fassung = None
    for z in meta.split("\n"):
        if z.startswith("name="):
            name = z[5:].strip()
        elif z.startswith("fassung="):
            fassung = z[8:].strip()
    if not name:
        raise SystemExit("veroeffentlichen: %s hat keinen Namen" % pfad)
    return name, fassung or "0"


# ------------------------------------------------------------- Register

def register_pfad(aus):
    return os.path.join(aus, "register.json")


def register_lesen(aus):
    p = register_pfad(aus)
    if not os.path.isfile(p):
        return {"letzte": 0, "vergeben": [], "zurueckgenommen": []}
    with open(p) as f:
        return json.load(f)


def register_schreiben(aus, r):
    p = register_pfad(aus)
    tmp = p + ".neu"
    with open(tmp, "w") as f:
        json.dump(r, f, indent=1)
    os.replace(tmp, p)


def journal(aus, text):
    with open(os.path.join(aus, "journal.txt"), "a") as f:
        f.write("%s\t%s\n"
                % (time.strftime("%Y-%m-%dT%H:%M:%S"), text))


def gesperrt_lesen(aus):
    p = os.path.join(aus, "gesperrt.txt")
    if not os.path.isfile(p):
        return []
    out = []
    for z in open(p):
        z = z.split("#")[0].strip()
        if z.isdigit():
            out.append(int(z))
    return sorted(set(out))


def gesperrt_schreiben(aus, liste):
    with open(os.path.join(aus, "gesperrt.txt"), "w") as f:
        f.write("# zurueckgezogene Fassungen. Ein Geraet spielt sie NICHT\n")
        f.write("# mehr ein, auch wenn es lange offline war.\n")
        for n in sorted(set(liste)):
            f.write("%d\n" % n)


# --------------------------------------------------------- das Verzeichnis

def verzeichnis_text(fassung, gen, kette, gesperrt, pakete):
    z = ["OTA2", "fassung\t%d" % fassung, "schluesselgen\t%d" % gen]
    for k in kette:
        z.append("kette\t%d\t%s\t%s" % (k["gen"], k["pub"], k["sig"]))
    for g in gesperrt:
        z.append("gesperrt\t%d" % g)
    for name, pf, h, n, datei in pakete:
        z.append("paket\t%s\t%s\t%s\t%d\t%s" % (name, pf, h, n, datei))
    return ("\n".join(z) + "\n").encode("ascii")


def verknuepfen(quelle, ziel):
    if os.path.exists(ziel):
        os.remove(ziel)
    try:
        os.link(quelle, ziel)
    except OSError:
        shutil.copy2(quelle, ziel)


def aktuell_setzen(aus, register, gesperrt):
    """`aktuell/` zeigt auf die hoechste NICHT gesperrte Fassung."""
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


def bauen(aus, stand, bund, notiz, sperren, feste_fassung=None,
          signierer="haupt", kette_kaputt=False):
    os.makedirs(os.path.join(aus, "pakete"), exist_ok=True)
    os.makedirs(os.path.join(aus, "v"), exist_ok=True)

    # 1. DIE NUMMER, UND ZWAR ZUERST. Sie ist verbraucht, sobald sie
    #    vergeben ist -- auch wenn der Rest dieses Laufs scheitert.
    reg = register_lesen(aus)
    if feste_fassung is not None:
        fassung = feste_fassung
        if fassung <= reg["letzte"]:
            raise SystemExit("veroeffentlichen: --fassung %d geht zurueck "
                             "(gefuehrt ist %d) -- das ist genau der Fall, "
                             "den das Register verhindert"
                             % (fassung, reg["letzte"]))
    else:
        fassung = reg["letzte"] + 1
    reg["letzte"] = fassung
    reg.setdefault("vergeben", []).append(fassung)
    register_schreiben(aus, reg)
    journal(aus, "nummer\t%d\tvergeben%s"
            % (fassung, ("\t" + notiz) if notiz else ""))

    zv = os.path.join(aus, "v", str(fassung))
    if os.path.isdir(zv):
        shutil.rmtree(zv)
    os.makedirs(zv)

    # 2. DIE PAKETE IN DEN VORRAT, inhaltsadressiert, und je eine
    #    Signatur daneben.
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
        # DIE SIGNATUR GEHOERT DER AUSLIEFERUNG UND NICHT DEM VORRAT.
        #
        # GEMESSEN, UND ES WAR EIN ECHTER FEHLER: der erste Entwurf legte
        # `<sha256>.opk.sig` neben die Datei in den Vorrat und benutzte
        # sie wieder. Nach einem SCHLUESSELWECHSEL war die Auslieferung
        # damit in sich widerspruechlich -- `INDEX.sig` und
        # `VERZEICHNIS.sig` trugen den neuen Schluessel, die Paketsignatur
        # den alten -- und ein Geraet, das den Wechsel gerade angenommen
        # hatte, sagte richtigerweise `opk: SIGNATUR FALSCH -- das Paket
        # wird ABGELEHNT`. Das Paket ist inhaltsadressiert und
        # unveraenderlich; die Signatur darueber haengt an einer
        # SCHLUESSELGENERATION. Beides in denselben Topf zu legen war der
        # Fehler.
        #
        # Also: die Oktette liegen einmal im Vorrat, die Signatur wird je
        # Auslieferung neu gerechnet. Das kostet 64 Oktett je Paket und
        # Fassung und macht jede Auslieferung unter EINEM Schluessel in
        # sich stimmig.
        signieren(bund, vorrat, os.path.join(zv, d + ".sig"), signierer)
        name, pf = meta_aus_opk(p)
        pakete.append((name, pf, h, os.path.getsize(p), d))

    # 3. INDEX (von `opk.py`, unsigniert) und die Signatur aus dem Bund.
    r = subprocess.run([sys.executable, OPK, "quelle", zv],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stdout + r.stderr)
        raise SystemExit("veroeffentlichen: opk quelle schlug fehl")
    signieren(bund, os.path.join(zv, "INDEX"),
              os.path.join(zv, "INDEX.sig"), signierer)

    # 4. DAS VERZEICHNIS.
    b = bund_lesen(bund)
    sperrliste = sorted(set(gesperrt_lesen(aus)) | set(sperren))
    gesperrt_schreiben(aus, sperrliste)
    kette = [dict(k) for k in b["kette"]]
    if kette_kaputt and kette:
        # EIN BIT IM LETZTEN KETTENSATZ. Alles andere bleibt richtig:
        # die Auslieferung ist sauber signiert, nur der WECHSEL laesst
        # sich nicht mehr nachrechnen. Das ist der Fall "unterbrochene
        # Kette", und ein Geraet muss ihn von "kein Wechsel"
        # unterscheiden.
        sig = bytearray(bytes.fromhex(kette[-1]["sig"]))
        sig[0] ^= 1
        kette[-1]["sig"] = bytes(sig).hex()
    roh = verzeichnis_text(fassung, b["haupt"]["gen"], kette,
                           sperrliste, pakete)
    with open(os.path.join(zv, "VERZEICHNIS"), "wb") as f:
        f.write(roh)
    signieren(bund, os.path.join(zv, "VERZEICHNIS"),
              os.path.join(zv, "VERZEICHNIS.sig"), signierer)

    # 5. Der oeffentliche Schluessel liegt zum Nachsehen daneben. Er ist
    #    KEIN Vertrauensanker -- der steht im Abbild des Geraets.
    with open(os.path.join(zv, "schluessel.pub"), "wb") as f:
        f.write(bytes.fromhex(b["haupt"]["pub"]))

    n = aktuell_setzen(aus, reg, sperrliste)
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
    reg = register_lesen(aus)
    sperr = gesperrt_lesen(aus)
    sperr.append(fassung)
    gesperrt_schreiben(aus, sperr)
    reg.setdefault("zurueckgenommen", []).append(fassung)
    # `letzte` wird NICHT angefasst. Die Nummer ist verbraucht.
    register_schreiben(aus, reg)
    n = aktuell_setzen(aus, reg, gesperrt_lesen(aus))
    journal(aus, "zuruecknahme\t%d\tletzte bleibt %d\taktuell %d"
            % (fassung, reg["letzte"], n))
    print("   fassung %d zurueckgenommen; gefuehrt bleibt %d, aktuell ist %d"
          % (fassung, reg["letzte"], n))
    print("   ACHTUNG: die Sperrliste wirkt erst, wenn eine NEUE "
          "Auslieferung sie traegt -- sie steht im signierten VERZEICHNIS.")
    return 0


def zeigen(aus):
    reg = register_lesen(aus)
    print("gefuehrte Fassung  %d" % reg["letzte"])
    print("vergeben           %s" % reg.get("vergeben", []))
    print("zurueckgenommen    %s" % reg.get("zurueckgenommen", []))
    print("gesperrt           %s" % gesperrt_lesen(aus))
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
    zurueck = None
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
            zurueck = int(sys.argv[i])
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
    if zurueck is not None:
        return zuruecknehmen(aus, zurueck)
    if not stand or not bund:
        print(__doc__)
        return 2
    bauen(aus, stand, bund, notiz, sperren, feste, signierer, kaputt)
    return 0


if __name__ == "__main__":
    sys.exit(main())
