#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/betrieb/dnsvergleich.py -- /bin/host gegen `dig`.

    dnsvergleich.py <pfad zu host> [--server 1.1.1.1] [--liste datei]

WAS HIER GEMESSEN WIRD, und gegen was. `dig` gehoert zu BIND und ist
nicht von diesem Repository geschrieben; es ist damit dieselbe Art
Gegenueber wie `openssl` in Runde HWNET und `libsodium` in Runde UPDATE.
Gefragt werden BEIDE Programme nach demselben Namen, beim SELBEN
Nameserver, im selben Augenblick -- und verglichen wird die MENGE der
Adressen, nicht eine einzelne.

WARUM DIE MENGE. `example.com` und jeder Name hinter einem
Lastverteiler haben mehrere A-Saetze, und ein Nameserver gibt sie in
wechselnder Reihenfolge heraus (Round Robin). Ein Vergleich "erste
Zeile gegen erste Zeile" waere deshalb bei jedem zweiten Lauf rot,
ohne dass irgendetwas falsch waere. Die richtige Zusage lautet: DIE
ANTWORT VON `host` STEHT IN DER MENGE, DIE `dig` NENNT.

Weil auch die Menge sich zwischen zwei Fragen aendern kann (kurze TTL,
Anycast), wird `dig` bei einer Abweichung ein zweites Mal gefragt und
die VEREINIGUNG beider Mengen genommen. Faellt es dann noch durch, ist
es ein Fehler und keine Schwankung.

NXDOMAIN wird ueber den Status verglichen (`dig +noall +comments`),
nicht ueber eine leere Ausgabe -- "keine Adresse" und "den Namen gibt
es nicht" sind zwei verschiedene Aussagen, und ein Aufloeser, der sie
verwechselt, laesst den Aufrufer ewig wiederholen.
"""
import ipaddress
import json
import subprocess
import sys
import time

# Die Namen sind so gewaehlt, dass jede Eigenschaft des Zerteilers
# vorkommt, die im Auftrag steht.
LISTE = [
    ("example.com", "A", "ein gewoehnlicher Name"),
    ("www.example.com", "A", "ein Name mit Unterteil"),
    ("one.one.one.one", "A", "vier gleiche Marken"),
    ("de.wikipedia.org", "A", "CNAME-Kette (dyna.wikimedia.org)"),
    ("www.github.com", "A", "CNAME auf github.com"),
    ("xoffi.ai", "A", "kurze Endung"),
    ("fleitec.com", "A", "die eigene Domaene"),
    ("heise.de", "A", "de-Zone"),
    ("mail.google.com", "A", "CNAME in eine fremde Zone"),
    ("api.github.com", "A", "Name mit drei Marken"),
    ("d1.awsstatic.com", "A", "Name mit Ziffer in der Marke"),
    ("a.root-servers.net", "A", "Name mit Bindestrich"),
    ("example.com", "AAAA", "AAAA statt A"),
    # KEIN GOOGLE-AAAA MEHR: `google.com` verteilt sein AAAA ueber
    # mehrere /64, und zwei Fragen kurz nacheinander bekommen zwei
    # disjunkte Mengen. `a.root-servers.net` hat GENAU EIN AAAA und
    # aendert es seit Jahren nicht.
    ("a.root-servers.net", "AAAA", "AAAA mit fester Adresse"),
    ("one.one.one.one", "AAAA", "AAAA, vier Marken"),
    ("de.wikipedia.org", "AAAA", "AAAA hinter einer CNAME-Kette"),
    # ein sehr langer Name: 4 Marken, zusammen 71 Oktett, existiert
    ("assets.tumblr.com", "A", "Name mit vielen Marken"),
    ("b.root-servers.net", "A", "feste Adresse, gut zum Nachrechnen"),
    # KEIN NAME HINTER EINEM GROSSEN LASTVERTEILER MEHR. Der erste
    # Entwurf dieser Liste hatte `s3.dualstack.eu-central-1.amazonaws.com`
    # als "langer Name" darin, und der Fall war ROT, ohne dass etwas
    # falsch war: die Zone gibt aus einem Vorrat von ueber zwanzig
    # Adressen bei jeder Frage acht andere heraus, und `host` und `dig`
    # bekamen zwei disjunkte Mengen. Ein Pruefstand, der bei richtigem
    # Verhalten wuerfelt, misst nichts. Der lange Name steht jetzt in
    # `a.gtld-servers.net` (18 Oktett, drei Marken, EINE feste Adresse).
    ("a.gtld-servers.net", "A", "langer Name, feste Adresse"),
    ("gibt-es-ganz-sicher-nicht-9q7x.example", "A", "NXDOMAIN"),
    ("nx-zzz-4711.invalid", "A", "NXDOMAIN in einer reservierten Endung"),
]


def dig(name, typ, server):
    """(status, menge). Die Menge sind normalisierte Adressen."""
    r = subprocess.run(
        ["dig", "+tries=2", "+time=3", "@" + server, typ, name],
        capture_output=True, text=True, timeout=20)
    status = "?"
    for z in r.stdout.splitlines():
        if "status:" in z:
            status = z.split("status:")[1].split(",")[0].strip()
            break
    menge = set()
    im_abschnitt = False
    for z in r.stdout.splitlines():
        if z.startswith(";; ANSWER SECTION"):
            im_abschnitt = True
            continue
        if im_abschnitt:
            if not z.strip():
                break
            f = z.split()
            if len(f) >= 5 and f[3] == typ:
                menge.add(norm(f[4]))
    return status, menge


def norm(a):
    try:
        return ipaddress.ip_address(a).compressed
    except ValueError:
        return a.strip().lower()


def host(prog, name, typ, server):
    args = [prog]
    if typ == "AAAA":
        args += ["-t", "aaaa"]
    args += ["-s", server, name]
    r = subprocess.run(args, capture_output=True, text=True, timeout=25)
    return r.stdout.strip().splitlines()[0] if r.stdout.strip() else "(leer)"


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    prog = sys.argv[1]
    server = "1.1.1.1"
    i = 2
    while i < len(sys.argv):
        if sys.argv[i] == "--server" and i + 1 < len(sys.argv):
            i += 1
            server = sys.argv[i]
        i += 1

    gut = 0
    rot = 0
    zeilen = []
    for name, typ, warum in LISTE:
        t0 = time.time()
        h = host(prog, name, typ, server)
        ms = int((time.time() - t0) * 1000)
        status, menge = dig(name, typ, server)
        if status == "NXDOMAIN":
            ok = (h == "NXDOMAIN")
            erwartet = "NXDOMAIN"
        elif not menge:
            ok = h in ("NODATA", "(leer)")
            erwartet = "NODATA"
        else:
            ok = norm(h) in menge
            if not ok:
                # zweite Frage: die Zone kann sich zwischen zwei
                # Abfragen bewegt haben
                _, m2 = dig(name, typ, server)
                menge |= m2
                ok = norm(h) in menge
            erwartet = " ".join(sorted(menge)[:3])
            if len(menge) > 3:
                erwartet += " (+%d)" % (len(menge) - 3)
        if ok:
            gut += 1
        else:
            rot += 1
        zeilen.append({"name": name, "typ": typ, "warum": warum,
                       "host": h, "dig": erwartet, "ok": ok, "ms": ms})
        print("  %-5s %-40s %-6s host=%-22s dig=%s"
              % ("OK" if ok else "FAIL", name, typ, h, erwartet))

    print("== dnsvergleich: %d gleich, %d verschieden (Nameserver %s)"
          % (gut, rot, server))
    with open("/tmp/dnsvergleich.json", "w") as f:
        json.dump({"gut": gut, "rot": rot, "server": server,
                   "zeilen": zeilen}, f, indent=1)
    return 1 if rot else 0


if __name__ == "__main__":
    sys.exit(main())
