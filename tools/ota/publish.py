#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    publish.py <auslieferung> --stand <verz> --bund <bund.json>
    [--notiz <text>] [--lock-down <revision>]...
    publish.py <auslieferung> --zuruecknehmen <revision> [--bund ...]
    publish.py <auslieferung> --display
    pakete/<sha256>.opk.sig
    revision        <dezimal>
    schluesselgen  <dezimal>
    chain          <gen>  <64hex neuer pub>  <128hex sig>     (0..n)
    locked       <revision>                                  (0..n)
    packet          <name> <revision> <sha256> <oktette> <file> <plattform>
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
import listdoc   # noqa: E402
import plattform as PLT   # noqa: E402
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import opkpfad
OPK = opkpfad.path_2()
BUND_PY = os.path.join(HIER, "keyring.py")


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
    name = revision = None
    for z in meta.split("\n"):
        if z.startswith("name="):
            name = z[5:].strip()
        elif z.startswith("fassung="):
            revision = z[8:].strip()
    if not name:
        raise SystemExit("veroeffentlichen: %s hat keinen Namen" % path_2)
    return name, revision or "0"



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


def locked_read(aus):
    p = os.path.join(aus, "gesperrt.txt")
    if not os.path.isfile(p):
        return []
    out = []
    for z in open(p):
        z = z.split("#")[0].strip()
        if z.isdigit():
            out.append(int(z))
    return sorted(set(out))


def locked_write(aus, list_2):
    with open(os.path.join(aus, "gesperrt.txt"), "w") as f:
        f.write("# withdrawn versions. A device does NOT install them\n")
        f.write("# any more, even if it was offline for a long time.\n")
        for n in sorted(set(list_2)):
            f.write("%d\n" % n)



def verknuepfen(source, target):
    if os.path.exists(target):
        os.remove(target)
    try:
        os.link(source, target)
    except OSError:
        shutil.copy2(source, target)


def current_set(aus, register, locked):
    kandidaten = [n for n in register["vergeben"] if n not in locked
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


def build(aus, stand, bund, notiz, lock_down, feste_version=None,
          signierer="haupt", chain_broken=False):
    os.makedirs(os.path.join(aus, "pakete"), exist_ok=True)
    os.makedirs(os.path.join(aus, "v"), exist_ok=True)

    reg = register_read(aus)
    if feste_version is not None:
        revision = feste_version
        if revision <= reg["letzte"]:
            raise SystemExit("publish: --revision %d goes backwards "
                             "(led is %d) -- exactly the case "
                             "the register prevents"
                             % (revision, reg["letzte"]))
    else:
        revision = reg["letzte"] + 1
    reg["letzte"] = revision
    reg.setdefault("vergeben", []).append(revision)
    register_write(aus, reg)
    journal(aus, "nummer\t%d\tvergeben%s"
            % (revision, ("\t" + notiz) if notiz else ""))

    zv = os.path.join(aus, "v", str(revision))
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
    sperrliste = sorted(set(locked_read(aus)) | set(lock_down))
    locked_write(aus, sperrliste)
    chain = [dict(k) for k in b["kette"]]
    if chain_broken and chain:
        sig = bytearray(bytes.fromhex(chain[-1]["sig"]))
        sig[0] ^= 1
        chain[-1]["sig"] = bytes(sig).hex()
    listdoc.write_signed(zv, lambda doc, sig: signieren(bund, doc, sig, signierer),
                         revision, b["haupt"]["gen"], chain=chain,
                         blocked=sperrliste, packages=pakete)

    with open(os.path.join(zv, "schluessel.pub"), "wb") as f:
        f.write(bytes.fromhex(b["haupt"]["pub"]))

    n = current_set(aus, reg, sperrliste)
    journal(aus, "auslieferung\t%d\t%d Paket(e)\tgen %d\tkette %d\t"
            "gesperrt %s\taktuell %d"
            % (revision, len(pakete), b["haupt"]["gen"], len(b["kette"]),
               sperrliste or "-", n))
    print("   fassung %d  %d Paket(e)  schluesselgen %d  kette %d  "
          "gesperrt %s  -> aktuell %d"
          % (revision, len(pakete), b["haupt"]["gen"], len(b["kette"]),
             sperrliste or "-", n))
    return revision


def zuruecknehmen(aus, revision):
    reg = register_read(aus)
    lock = locked_read(aus)
    lock.append(revision)
    locked_write(aus, lock)
    reg.setdefault("zurueckgenommen", []).append(revision)
    register_write(aus, reg)
    n = current_set(aus, reg, locked_read(aus))
    journal(aus, "zuruecknahme\t%d\tletzte bleibt %d\taktuell %d"
            % (revision, reg["letzte"], n))
    print("   version %d withdrawn; led remains %d, current is %d"
          % (revision, reg["letzte"], n))
    print("   NOTE: the revocation list only takes effect when a NEW "
          "delivery carries it -- it lives in the signed directory.")
    return 0


def display(aus):
    reg = register_read(aus)
    print("led version        %d" % reg["letzte"])
    print("issued            %s" % reg.get("vergeben", []))
    print("withdrawn          %s" % reg.get("zurueckgenommen", []))
    print("locked            %s" % locked_read(aus))
    vd = os.path.join(aus, "v")
    if os.path.isdir(vd):
        print("kept              %s"
              % sorted(int(x) for x in os.listdir(vd) if x.isdigit()))
    p = os.path.join(aus, "pakete")
    if os.path.isdir(p):
        n = len([x for x in os.listdir(p) if x.endswith(".opk")])
        gr = sum(os.path.getsize(os.path.join(p, x))
                 for x in os.listdir(p))
        print("stock             %d packages, %d octets" % (n, gr))
    return 0


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    aus = sys.argv[1]
    stand = bund = notiz = None
    lock_down = []
    back = None
    nurzeigen = False
    feste = None
    signierer = "haupt"
    broken = False
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
        elif a == "--lock-down":
            i += 1
            lock_down.append(int(sys.argv[i]))
        elif a == "--revision":
            i += 1
            feste = int(sys.argv[i])
        elif a == "--zuruecknehmen":
            i += 1
            back = int(sys.argv[i])
        elif a == "--signierer":
            i += 1
            signierer = sys.argv[i]
        elif a == "--kette-kaputt":
            broken = True
        elif a == "--display":
            nurzeigen = True
        else:
            print(__doc__)
            return 2
        i += 1
    os.makedirs(aus, exist_ok=True)
    if nurzeigen:
        return display(aus)
    if back is not None:
        return zuruecknehmen(aus, back)
    if not stand or not bund:
        print(__doc__)
        return 2
    build(aus, stand, bund, notiz, lock_down, feste, signierer, broken)
    return 0


if __name__ == "__main__":
    sys.exit(main())
