#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/demux/mktab.py -- die Zahlentafeln fuer den MP3-Dekodierer.

Warum ein Erzeuger und keine Handarbeit: der Dekodierer in
`kernel/user/mp3.fi` rechnet in FESTKOMMA, weil es in Ring 3 dieses
Systems kein Fliesskomma gibt (`kernel/user/netstat.fi` sagt dasselbe
ueber Prozentangaben). Jede Konstante -- Fenster, Kosinusse,
Syntheseflanke, x^(4/3) -- ist damit eine ganze Zahl mit 20 Bruchbits,
und keine davon soll jemand abtippen.

Zwei Sorten Zahlen kommen hier zusammen, und ihre HERKUNFT ist
verschieden:

  1. GERECHNET. Fenster, Kosinustafeln, x^(4/3), 2^(k/4), die
     Aliasfaktoren, die Intensitaetsverhaeltnisse. Sie stehen als
     FORMEL in ISO/IEC 11172-3 und werden hier ausgerechnet, nicht
     abgeschrieben.
  2. TABELLIERT. Die Huffman-Tafeln (ISO Tabelle B.7), die
     Syntheseflanke D[512] (Tabelle B.3) und die Bandgrenzen
     (Tabelle B.8). Das sind Zahlenkolonnen ohne Formel. Sie werden aus
     einer GEMEINFREIEN Quelle gelesen -- pdmp3 von Krister Lagerstroem
     (Public Domain, https://github.com/technosaurus/PDMP3) -- und in
     das EIGENE Format dieses Repos umgeschrieben. Die Herkunft steht in
     THIRD_PARTY.md.

     Die Huffman-Baeume werden dabei nicht kopiert, sondern
     ABGELAUFEN: aus dem Baum kommt die Liste (Code, Laenge, x, y)
     zurueck, und aus der Liste wird ein neuer Baum in unserem Format
     gebaut. Als Gegenprobe wird fuer jede Tafel die Kraft-Ungleichung
     nachgerechnet -- ein vollstaendiger Praefixcode summiert sich auf
     genau 1. Alle 17 Tafeln tun das.

     GEFUNDENER FEHLER IN DER QUELLE: pdmp3 zeigt fuer Tafel 33 auf
     Versatz 2261, mitten in den Baum von Tafel 24. Der richtige Versatz
     ist 2773 -- dort liegen 16 Codes zu je vier Bit, wie es Tabelle B.7
     fuer die count1-Tafel B verlangt. Auf 2261 liefert der Ablauf EINEN
     Code der Laenge null. Wir nehmen 2773 und sagen hier, warum.

    python3 tools/demux/mktab.py <pdmp3.c> <ausgabe.fi>
"""
import math
import re
import sys

FB = 20        # Bruchbits im Abtastweg
FB43 = 14      # Bruchbits in der Tafel x^(4/3)
FB2Q = 26      # Bruchbits in 2^(k/4)

PDMP3_SHA256 = "3fa7df3b90d47696e656cb0d277296f19048832432c4b2a0584b64c71bfc1ff7"


def q(x, bits=FB):
    """Eine reelle Zahl als ganze Zahl mit `bits` Bruchbits, gerundet."""
    return int(math.floor(x * (1 << bits) + 0.5))


def read_pdmp3(path):
    src = open(path).read()
    out = {}

    m = re.search(r"static const unsigned short g_huffman_table\[\]\s*=\s*\{(.*?)\n\};",
                  src, re.S)
    body = re.sub(r"//[^\n]*", "", m.group(1))
    out["huff"] = [int(x, 16) for x in re.findall(r"0x([0-9a-fA-F]+)", body)]

    m = re.search(r"hufftables g_huffman_main\s*\[34\]\s*=\s*\{(.*?)\n\};", src, re.S)
    rows = []
    for line in m.group(1).split("\n"):
        line = line.strip()
        if not line.startswith("{"):
            continue
        inner = line[1:line.index("}")]
        parts = [p.strip() for p in inner.split(",")]
        if parts[0] == "NULL":
            off = None
        else:
            mm = re.match(r"g_huffman_table\s*\+?\s*(\d*)", parts[0])
            off = int(mm.group(1)) if mm.group(1) else 0
        rows.append([off, int(parts[1]), int(parts[2])])
    # Der Fehler in der Quelle, siehe Kopf.
    rows[33][0] = 2773
    out["tabs"] = rows

    m = re.search(r"g_synth_dtbl\[512\]\s*=\s*\{(.*?)\n\s*\};", src, re.S)
    d = [float(x) for x in re.findall(r"-?\d+\.\d+", m.group(1))]
    assert len(d) == 512, len(d)
    out["dtbl"] = d

    m = re.search(r"g_sf_band_indices\[3[^\]]*\]\s*=\s*\{(.*?)\n\s*\};", src, re.S)
    nums = re.findall(r"\{([^{}]*)\}", m.group(1))
    lo, sh = [], []
    for i in range(0, len(nums), 2):
        lo.append([int(x) for x in nums[i].split(",")])
        sh.append([int(x) for x in nums[i + 1].split(",")])
    assert len(lo) == 3 and len(lo[0]) == 23 and len(sh[0]) == 14
    out["sfbl"] = lo
    out["sfbs"] = sh
    return out


def walk(vals, off):
    """Den Baum von pdmp3 ablaufen -> [(Code, Laenge, x, y)]."""
    out = []

    def rec(point, code, ln):
        if ln > 24:
            raise RuntimeError("Baum zu tief")
        v = vals[off + point]
        if (v & 0xFF00) == 0:
            out.append((code, ln, (v >> 4) & 0xF, v & 0xF))
            return
        p = point
        while (vals[off + p] >> 8) >= 250:
            p += vals[off + p] >> 8
        rec(p + (vals[off + p] >> 8), code << 1, ln + 1)
        p = point
        while (vals[off + p] & 0xFF) >= 250:
            p += vals[off + p] & 0xFF
        rec(p + (vals[off + p] & 0xFF), (code << 1) | 1, ln + 1)

    rec(0, 0, 0)
    return out


def build_tree(entries):
    """Aus (Code, Laenge, x, y) einen Baum in UNSEREM Format.

    Ein Knoten sind zwei Zellen: [links, rechts]. Eine Zelle >= 0x8000
    ist ein Blatt und traegt (x<<4)|y in den unteren Bits, sonst ist sie
    die Nummer des Kindknotens.
    """
    nodes = [[0, 0]]

    def put(code, ln, sym):
        n = 0
        for k in range(ln - 1, -1, -1):
            b = (code >> k) & 1
            if k == 0:
                assert nodes[n][b] == 0, "Praefix kollidiert"
                nodes[n][b] = 0x8000 | sym
            else:
                if nodes[n][b] == 0:
                    nodes.append([0, 0])
                    nodes[n][b] = len(nodes) - 1
                n = nodes[n][b]
                assert n < 0x8000

    for (code, ln, x, y) in entries:
        if ln == 0:
            raise RuntimeError("Code der Laenge null")
        put(code, ln, (x << 4) | y)
    return nodes


def emit_array(f, name, ty, values, per_line=16):
    f.write("static mut %s: [%s; %d] = [" % (name, ty, len(values)))
    for i, v in enumerate(values):
        if i % per_line == 0:
            f.write("\n    ")
        f.write("%d" % v)
        if i != len(values) - 1:
            f.write(",")
    f.write("\n]\n\n")


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 1
    src = read_pdmp3(sys.argv[1])
    vals = src["huff"]

    # ---- Huffman: ablaufen, pruefen, neu bauen ----
    roots = [0xFFFF] * 34
    linb = [0] * 34
    tree = []
    seen = {}
    report = []
    for i, (off, tl, lb) in enumerate(src["tabs"]):
        linb[i] = lb
        if off is None:
            continue
        if off in seen:
            roots[i] = seen[off]
            continue
        e = walk(vals, off)
        kraft = sum(2.0 ** -ln for (_, ln, _, _) in e)
        if abs(kraft - 1.0) > 1e-12:
            raise RuntimeError("Tafel %d ist kein vollstaendiger Code (%f)" % (i, kraft))
        nodes = build_tree(e)
        base = len(tree) // 2
        for (l, r) in nodes:
            tree.append(l if l >= 0x8000 else (l + base))
            tree.append(r if r >= 0x8000 else (r + base))
        roots[i] = base
        seen[off] = base
        report.append((i, len(e), max(ln for (_, ln, _, _) in e), len(nodes)))

    f = open(sys.argv[2], "w")
    f.write("""// SPDX-License-Identifier: GPL-2.0-only
// kernel/user/mp3tab.fi -- ERZEUGT von tools/demux/mktab.py. NICHT von Hand
// aendern; wer etwas aendern will, aendert den Erzeuger.
//
// Alle Zahlen im Abtastweg haben %d Bruchbits. x^(4/3) hat %d, 2^(k/4)
// hat %d -- beide werden mit einem eigenen Schub verrechnet, damit das
// Produkt in eine 64-Bit-Zahl passt (der Uebersetzer PRUEFT den Ueberlauf,
// er wickelt ihn nicht; SPEC 13).
//
// Herkunft der TABELLIERTEN Zahlen (Huffman, Syntheseflanke, Bandgrenzen):
// pdmp3, Public Domain, sha256 %s
// Alles andere ist aus den Formeln von ISO/IEC 11172-3 gerechnet.

profile kernel

export {
    FB, htree, hroot, hlin, sfbl, sfbs, pretab, slen1, slen2,
    l3_bitrate, srate, pow43, pow2q, csf, caf, imdct_win, cos36, cos12,
    nwin, dtbl, isr_l, isr_r, INV_SQRT2
}

const FB: u64 = %d
const INV_SQRT2: i64 = %d

""" % (FB, FB43, FB2Q, PDMP3_SHA256, FB, q(1.0 / math.sqrt(2.0))))

    f.write("// Die %d Huffman-Baeume, hintereinander. Zwei Zellen je Knoten:\n"
            "// links, rechts. Zelle >= 0x8000 ist ein Blatt mit (x<<4)|y.\n"
            % len(seen))
    for (i, n, mx, nd) in report:
        f.write("//   Tafel %2d: %4d Codes, laengster %2d Bit, %4d Knoten\n"
                % (i, n, mx, nd))
    emit_array(f, "htree", "u16", tree, 12)
    emit_array(f, "hroot", "u16", roots, 12)
    f.write("// linbits je Tafel (ISO Tabelle B.7).\n")
    emit_array(f, "hlin", "u8", linb, 17)

    f.write("// Bandgrenzen, je Abtastrate (0=44100, 1=48000, 2=32000).\n")
    emit_array(f, "sfbl", "u16", [x for r in src["sfbl"] for x in r], 23)
    emit_array(f, "sfbs", "u16", [x for r in src["sfbs"] for x in r], 14)

    f.write("// Die Anhebung (ISO Tabelle B.6) und die Laengen der Skalenfaktoren.\n")
    emit_array(f, "pretab", "u8",
               [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 3, 3, 3, 2, 0], 22)
    sl = [(0, 0), (0, 1), (0, 2), (0, 3), (3, 0), (1, 1), (1, 2), (1, 3),
          (2, 1), (2, 2), (2, 3), (3, 1), (3, 2), (3, 3), (4, 2), (4, 3)]
    emit_array(f, "slen1", "u8", [a for (a, b) in sl], 16)
    emit_array(f, "slen2", "u8", [b for (a, b) in sl], 16)

    f.write("// Datenraten (Layer III, MPEG-1) und Abtastraten.\n")
    emit_array(f, "l3_bitrate", "u32",
               [0, 32000, 40000, 48000, 56000, 64000, 80000, 96000,
                112000, 128000, 160000, 192000, 224000, 256000, 320000, 0], 8)
    emit_array(f, "srate", "u32", [44100, 48000, 32000, 0], 4)

    f.write("// x^(4/3), %d Bruchbits. Der groesste Wert ist 8206 (linbits 13).\n" % FB43)
    emit_array(f, "pow43", "u32",
               [0] + [int(math.floor(pow(i, 4.0 / 3.0) * (1 << FB43) + 0.5))
                      for i in range(1, 8207)], 12)
    f.write("// 2^(k/4), %d Bruchbits -- der Viertelschritt des globalen Gewinns.\n" % FB2Q)
    emit_array(f, "pow2q", "u32", [q(pow(2.0, k / 4.0), FB2Q) for k in range(4)], 4)

    f.write("// Aliasminderung (ISO 2.4.3.4.10.1): cs und ca aus ci.\n")
    ci = [-0.6, -0.535, -0.33, -0.185, -0.095, -0.041, -0.0142, -0.0037]
    cs = [1.0 / math.sqrt(1.0 + c * c) for c in ci]
    ca = [c / math.sqrt(1.0 + c * c) for c in ci]
    emit_array(f, "csf", "i32", [q(x) for x in cs], 8)
    emit_array(f, "caf", "i32", [q(x) for x in ca], 8)

    f.write("// Die vier Fenster der IMDCT (Blockart 0,1,2,3), je 36 Werte.\n")
    win = [[0.0] * 36 for _ in range(4)]
    for i in range(36):
        win[0][i] = math.sin(math.pi / 36 * (i + 0.5))
    for i in range(18):
        win[1][i] = math.sin(math.pi / 36 * (i + 0.5))
    for i in range(18, 24):
        win[1][i] = 1.0
    for i in range(24, 30):
        win[1][i] = math.sin(math.pi / 12 * (i + 0.5 - 18.0))
    for i in range(12):
        win[2][i] = math.sin(math.pi / 12 * (i + 0.5))
    for i in range(6, 12):
        win[3][i] = math.sin(math.pi / 12 * (i + 0.5 - 6.0))
    for i in range(12, 18):
        win[3][i] = 1.0
    for i in range(18, 36):
        win[3][i] = math.sin(math.pi / 36 * (i + 0.5))
    emit_array(f, "imdct_win", "i32", [q(x) for r in win for x in r], 12)

    f.write("// cos(pi/(2N) * (2p+1+N/2) * (2m+1)), N=36 (p*18+m) und N=12 (p*6+m).\n")
    c36 = []
    for p in range(36):
        for m in range(18):
            c36.append(q(math.cos(math.pi / 72 * (2 * p + 1 + 18) * (2 * m + 1))))
    emit_array(f, "cos36", "i32", c36, 12)
    c12 = []
    for p in range(12):
        for m in range(6):
            c12.append(q(math.cos(math.pi / 24 * (2 * p + 1 + 6) * (2 * m + 1))))
    emit_array(f, "cos12", "i32", c12, 12)

    f.write("// Die Matrix der Teilbandsynthese: cos((16+i)(2j+1) pi/64), i*32+j.\n")
    nw = []
    for i in range(64):
        for j in range(32):
            nw.append(q(math.cos((16 + i) * (2 * j + 1) * math.pi / 64.0)))
    emit_array(f, "nwin", "i32", nw, 12)

    f.write("// Die Syntheseflanke D[512] (ISO Tabelle B.3).\n")
    emit_array(f, "dtbl", "i32", [q(x) for x in src["dtbl"]], 12)

    f.write("// Intensitaetsstereo: die zwei Faktoren je is_pos 0..6.\n")
    isl, isr = [], []
    for p in range(8):
        if p == 6:
            l, r = 1.0, 0.0
        elif p < 6:
            t = math.tan(p * math.pi / 12.0)
            l, r = t / (1.0 + t), 1.0 / (1.0 + t)
        else:
            l, r = 0.0, 0.0
        isl.append(q(l))
        isr.append(q(r))
    emit_array(f, "isr_l", "i32", isl, 8)
    emit_array(f, "isr_r", "i32", isr, 8)
    f.close()

    print("%s: %d Baumzellen, %d Tafeln geprueft (Kraft = 1)"
          % (sys.argv[2], len(tree), len(report)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
