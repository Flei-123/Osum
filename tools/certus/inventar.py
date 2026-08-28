#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/certus/inventar.py -- DIE BESTANDSAUFNAHME, aus dem Quelltext
gezaehlt und nicht aus der Doku abgeschrieben.

Was hier gezaehlt wird, steht in Tabellen, die der Motor WIRKLICH liest:

  * HTML-Elementnamen      lib/browser/tag.fi   (die festen Atome)
  * HTML-Elemente mit Stil lib/dom/ua.css       (Vorgabe-Stilblatt)
  * CSS-Eigenschaften      lib/css/cascade.fi   (P_* bis P_COUNT)
  * CSS-Selektorformen     lib/css/sel.fi
  * CSS-Einheiten/Farben   lib/css/cv.fi
  * JavaScript-Eingebaute  lib/js/builtin*.fi   (B_* Nummern)
  * DOM-Schnittstelle      lib/browser/domjs.fi (D_* Nummern)
  * Layout-Anzeigearten    lib/layout/box.fi + cascade.fi (DI_*)
  * Bildformate            lib/paint/*.fi
  * Netz/TLS               lib/net, lib/tls

    python3 tools/certus/inventar.py <firn-lib-verzeichnis>
"""
import json
import os
import re
import sys


def rd(p):
    try:
        return open(p, encoding="utf-8", errors="replace").read()
    except OSError:
        return ""


def const_names(text, prefix):
    return sorted(set(re.findall(r"const (%s[A-Z0-9_]+)\s*:" % prefix, text)))


def main():
    lib = sys.argv[1]
    out = {}

    tag = rd(os.path.join(lib, "browser/tag.fi"))
    m = re.search(r"const M_LAST_FIXED: u32 = (\d+)", tag)
    fixed = int(m.group(1)) if m else 0
    names = const_names(tag, "M_")
    names = [n for n in names if n != "M_LAST_FIXED"]
    # Die letzten acht sind Attributnamen, nicht Elemente -- sie stehen im
    # Quelltext hinter M_DESC/M_IMAGE. Wir trennen sie namentlich.
    attrs = {"M_TYPE", "M_ID", "M_CLASS", "M_HREF", "M_SRC", "M_NAME",
             "M_ACTION", "M_PROMPT"}
    out["html_atome_fest"] = fixed
    out["html_elementnamen"] = len([n for n in names if n not in attrs])
    out["html_attributnamen_fest"] = len(attrs)

    ua = rd(os.path.join(lib, "dom/ua.css"))
    sel = set()
    for block in re.findall(r"([^{}]+)\{", ua):
        for s in block.split(","):
            s = s.strip()
            if s and not s.startswith("/*") and re.match(r"^[a-z0-9]+$", s):
                sel.add(s)
    out["ua_stilblatt_elemente"] = len(sel)
    out["ua_stilblatt_regeln"] = len(re.findall(r"\{", ua))

    casc = rd(os.path.join(lib, "css/cascade.fi"))
    m = re.search(r"const P_COUNT: u32 = (\d+)", casc)
    out["css_eigenschaften"] = int(m.group(1)) if m else 0
    out["css_eigenschaften_namen"] = [
        n[2:].lower().replace("_", "-")
        for n in const_names(casc, "P_")
        if n not in ("P_COUNT", "P_NONE")]
    out["css_anzeigearten"] = len(const_names(casc, "DI_"))
    out["css_anzeigearten_namen"] = [n[3:].lower()
                                     for n in const_names(casc, "DI_")]

    s = rd(os.path.join(lib, "css/sel.fi"))
    out["css_selektorformen"] = len(const_names(s, "SC_"))
    out["css_selektorformen_namen"] = [n[3:].lower()
                                       for n in const_names(s, "SC_")]
    out["css_pseudoklassen"] = len(const_names(s, "PC_"))

    cv = rd(os.path.join(lib, "css/cv.fi"))
    out["css_werttypen"] = len(const_names(cv, "V_"))
    out["css_einheiten"] = len(const_names(cv, "U_"))

    b1 = rd(os.path.join(lib, "js/builtin.fi"))
    b2 = rd(os.path.join(lib, "js/builtin2.fi"))
    nat = set(re.findall(r"const (B_[A-Z0-9_]+): u64", b1 + b2))
    out["js_eingebaute_funktionen"] = len(nat)
    groups = {}
    for n in nat:
        g = n.split("_")[1]
        groups[g] = groups.get(g, 0) + 1
    out["js_gruppen"] = dict(sorted(groups.items(), key=lambda kv: -kv[1]))

    lex = rd(os.path.join(lib, "js/lex.fi"))
    out["js_schluesselwoerter"] = len(const_names(lex, "K_"))

    dj = rd(os.path.join(lib, "browser/domjs.fi"))
    dnat = set(re.findall(r"const (D_[A-Z0-9_]+): u64", dj))
    out["dom_js_schnittstellen"] = len(dnat)

    api = rd(os.path.join(lib, "dom/api.fi"))
    out["dom_api_funktionen"] = len(
        set(re.findall(r"^fn ([a-z_0-9]+)\(", api, re.M)))

    fl = rd(os.path.join(lib, "layout/flow.fi"))
    out["layout_zeilen"] = fl.count("\n")
    out["layout_funktionen"] = len(
        set(re.findall(r"^fn ([a-z_0-9]+)\(", fl, re.M)))

    out["bildformate"] = sorted(
        f[:-3] for f in os.listdir(os.path.join(lib, "paint"))
        if f in ("png.fi", "jpeg.fi"))

    out["zeilen"] = {}
    for d in ("browser", "css", "dom", "font", "html", "js", "layout",
              "net", "paint", "tls"):
        p = os.path.join(lib, d)
        if not os.path.isdir(p):
            continue
        n = 0
        for f in os.listdir(p):
            if f.endswith(".fi"):
                n += rd(os.path.join(p, f)).count("\n")
        out["zeilen"][d] = n
    out["zeilen"]["summe"] = sum(out["zeilen"].values())

    print(json.dumps(out, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
