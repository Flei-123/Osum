#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/pdf/corpus.py -- the test PDFs of the viewer (lib/pdfread).

    python3 tools/pdf/corpus.py <outdir>

Every file is made by an independent writer (reportlab, pypdf or the raw
writer below), so the reader is not tested against its own idea of a PDF.
"""
import base64, io, os, struct, sys, zlib

def main(out):
    os.makedirs(out, exist_ok=True)
    from reportlab.lib.pagesizes import A4, letter
    from reportlab.pdfgen import canvas
    from reportlab.lib import colors
    from reportlab import rl_config

    # 1. text, graphics, dash, colours, two pages (uncompressed)
    rl_config.pageCompression = 0
    c = canvas.Canvas(f"{out}/basic.pdf", pagesize=A4)
    c.setFont("Helvetica", 24); c.drawString(72, 750, "Hello PDF viewer: Umlaute äöü ß €")
    c.setFont("Times-Roman", 12); c.drawString(72, 700, "The quick brown fox jumps over the lazy dog. 0123456789")
    c.setFont("Courier", 10); c.drawString(72, 680, "monospace text line")
    c.setFillColorRGB(1, 0, 0); c.rect(72, 500, 200, 100, fill=1, stroke=0)
    c.setStrokeColorRGB(0, 0, 1); c.setLineWidth(3); c.line(72, 450, 400, 480)
    c.setFillColorRGB(0, .6, 0); c.circle(350, 550, 40, fill=1)
    c.setDash(4, 2); c.rect(72, 300, 200, 80)
    c.setDash(); c.setFillColorCMYK(0, 1, 1, 0); c.rect(300, 300, 100, 60, fill=1, stroke=0)
    c.setFillGray(.5); c.rect(420, 300, 60, 60, fill=1, stroke=0)
    c.showPage(); c.setFont("Helvetica-Bold", 18); c.drawString(72, 750, "Page two"); c.save()

    # 2. compressed, rotated text, clipping, even-odd, curves, transparency
    rl_config.pageCompression = 1
    c = canvas.Canvas(f"{out}/graphics.pdf", pagesize=letter)
    c.saveState(); c.translate(300, 400); c.rotate(30); c.setFont("Helvetica", 20); c.drawString(0, 0, "Rotated 30 degrees"); c.restoreState()
    p = c.beginPath(); p.moveTo(100, 100); p.curveTo(150, 300, 250, 300, 300, 100); p.close()
    c.setFillColorRGB(.2, .2, .8); c.drawPath(p, fill=1, stroke=1)
    c.saveState(); cp = c.beginPath(); cp.circle(400, 600, 50); c.clipPath(cp, stroke=0, fill=0)
    c.setFillColorRGB(1, .5, 0); c.rect(340, 540, 120, 120, fill=1, stroke=0); c.restoreState()
    c.setFillAlpha(.4); c.setFillColorRGB(1, 0, 0); c.rect(100, 500, 100, 100, fill=1, stroke=0)
    c.setFillColorRGB(0, 0, 1); c.rect(150, 550, 100, 100, fill=1, stroke=0)
    c.setFillAlpha(1); c.setLineWidth(.2); c.grid([50, 100, 150, 200], [50, 100, 150, 200])
    c.showPage(); c.save()

    # 3. platypus: a long text with a table, many pages
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak
    from reportlab.lib.styles import getSampleStyleSheet
    st = getSampleStyleSheet()
    doc = SimpleDocTemplate(f"{out}/long.pdf", pagesize=A4)
    story = []
    for i in range(1, 41):
        story.append(Paragraph(f"Chapter {i}", st["Heading1"]))
        story.append(Paragraph(("Lorem ipsum dolor sit amet, consectetur adipiscing elit. " * 12), st["BodyText"]))
        t = Table([[f"r{r}c{k}" for k in range(5)] for r in range(6)])
        t.setStyle(TableStyle([("GRID", (0, 0), (-1, -1), .5, colors.black), ("BACKGROUND", (0, 0), (-1, 0), colors.lightgrey)]))
        story.append(Spacer(1, 6)); story.append(t); story.append(PageBreak())
    doc.build(story)

    # 4. an embedded TrueType font with Greek and Cyrillic
    try:
        from reportlab.pdfbase import pdfmetrics
        from reportlab.pdfbase.ttfonts import TTFont
        pdfmetrics.registerFont(TTFont("DejaVu", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"))
        c = canvas.Canvas(f"{out}/unicode.pdf", pagesize=A4)
        c.setFont("DejaVu", 18)
        c.drawString(72, 750, "Greek: Αβγδ Ω  Cyrillic: Привет мир")
        c.drawString(72, 720, "Latin: Ångström café ½ • →")
        c.save()
    except Exception as e:
        print("no unicode.pdf:", e)

    # 5. images: PNG (RGB + alpha) and JPEG
    from PIL import Image
    im = Image.new("RGB", (64, 48))
    for y in range(48):
        for x in range(64):
            im.putpixel((x, y), (x * 4, y * 5, 128))
    im.save(f"{out}/_i.png"); im.save(f"{out}/_i.jpg", quality=90)
    c = canvas.Canvas(f"{out}/images.pdf", pagesize=A4)
    c.drawImage(f"{out}/_i.png", 72, 600, 200, 150)
    c.drawImage(f"{out}/_i.jpg", 300, 600, 200, 150)
    c.saveState(); c.translate(150, 400); c.rotate(20); c.drawImage(f"{out}/_i.png", 0, 0, 160, 120); c.restoreState()
    c.save()

    # 6. rotated pages (pypdf)
    from pypdf import PdfReader, PdfWriter
    for rot in (90, 180, 270):
        w = PdfWriter(); r = PdfReader(f"{out}/basic.pdf"); pg = r.pages[0]; pg.rotate(rot); w.add_page(pg)
        with open(f"{out}/rot{rot}.pdf", "wb") as f:
            w.write(f)

    # 7. encrypted
    c = canvas.Canvas(f"{out}/encrypted.pdf", pagesize=A4, encrypt="secret")
    c.drawString(72, 700, "secret"); c.save()

    # 8. the raw writer: xref stream + object stream, and the old filters
    def raw_pdf(path, objs, content_filter=None, xref_stream=False, objstm=False):
        """objs: dict num -> bytes (a dict/array text) or ('stream', dict_text, data)."""
        out_b = bytearray(b"%PDF-1.5\n%\xe2\xe3\xcf\xd3\n")
        offs = {}
        in_stm = []
        for n in sorted(objs):
            o = objs[n]
            if objstm and not isinstance(o, tuple):
                in_stm.append(n)
                continue
            offs[n] = len(out_b)
            if isinstance(o, tuple):
                _, d, data = o
                out_b += b"%d 0 obj\n<< %s /Length %d >>\nstream\n" % (n, d.encode(), len(data)) + data + b"\nendstream\nendobj\n"
            else:
                out_b += b"%d 0 obj\n" % n + o + b"\nendobj\n"
        stm_num = max(objs) + 1
        if objstm:
            hdr = b""; body = b""
            for n in in_stm:
                hdr += b"%d %d " % (n, len(body)); body += objs[n] + b"\n"
            raw = hdr + body
            comp = zlib.compress(raw)
            offs[stm_num] = len(out_b)
            out_b += b"%d 0 obj\n<< /Type /ObjStm /N %d /First %d /Filter /FlateDecode /Length %d >>\nstream\n" % (stm_num, len(in_stm), len(hdr), len(comp)) + comp + b"\nendstream\nendobj\n"
        size = stm_num + 1 + (1 if xref_stream else 0)
        if xref_stream:
            xr = stm_num + 1
            offs[xr] = len(out_b)
            rows = b""
            for n in range(size):
                if n in in_stm:
                    rows += struct.pack(">BHB", 2, stm_num, in_stm.index(n))
                elif n in offs:
                    rows += struct.pack(">BHB", 1, offs[n], 0)
                else:
                    rows += struct.pack(">BHB", 0, 0, 255)
            # PNG "up" predictor, to exercise it
            rowsz = 4; pred = b""; prev = bytes(rowsz)
            for i in range(0, len(rows), rowsz):
                r = rows[i:i + rowsz]
                pred += b"\x02" + bytes((r[k] - prev[k]) & 255 for k in range(rowsz)); prev = r
            comp = zlib.compress(pred)
            out_b += (b"%d 0 obj\n<< /Type /XRef /Size %d /W [1 2 1] /Root 1 0 R /Filter /FlateDecode "
                      b"/DecodeParms << /Predictor 12 /Columns 4 >> /Length %d >>\nstream\n" % (xr, size, len(comp))) + comp + b"\nendstream\nendobj\n"
            out_b += b"startxref\n%d\n%%%%EOF\n" % offs[xr]
        else:
            xo = len(out_b)
            out_b += b"xref\n0 %d\n0000000000 65535 f \n" % size
            for n in range(1, size):
                out_b += b"%010d 00000 n \n" % offs.get(n, 0)
            out_b += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (size, xo)
        open(path, "wb").write(bytes(out_b))

    cs = b"BT /F1 20 Tf 72 700 Td (Filters: xref stream, object stream) Tj ET 0 0 1 rg 72 600 100 50 re f"
    base = {
        1: b"<< /Type /Catalog /Pages 2 0 R >>",
        2: b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        3: b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        5: b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    }
    objs = dict(base); objs[4] = ("stream", "/Filter /FlateDecode", zlib.compress(cs))
    raw_pdf(f"{out}/xrefstm.pdf", objs, xref_stream=True, objstm=True)
    raw_pdf(f"{out}/plain-flate.pdf", objs)
    # ASCII85 + Flate, ASCIIHex, RunLength, LZW
    a85 = base64.a85encode(zlib.compress(cs), adobe=True)
    objs = dict(base); objs[4] = ("stream", "/Filter [/ASCII85Decode /FlateDecode]", a85)
    raw_pdf(f"{out}/a85.pdf", objs)
    objs = dict(base); objs[4] = ("stream", "/Filter /ASCIIHexDecode", cs.hex().encode() + b">")
    raw_pdf(f"{out}/ahx.pdf", objs)
    rl = bytearray(); i = 0
    while i < len(cs):
        n = min(128, len(cs) - i); rl += bytes([n - 1]) + cs[i:i + n]; i += n
    rl += b"\x80"
    objs = dict(base); objs[4] = ("stream", "/Filter /RunLengthDecode", bytes(rl))
    raw_pdf(f"{out}/rl.pdf", objs)

    def lzw_encode(data):
        # PDF LZW, early change 1
        table = {bytes([i]): i for i in range(256)}; nxt = 258; bits = 9
        out_bits = []; w = b""
        def emit(code):
            out_bits.append((code, bits))
        emit(256)
        for ch in data:
            wc = w + bytes([ch])
            if wc in table:
                w = wc
            else:
                emit(table[w])
                table[wc] = nxt; nxt += 1
                if nxt + 1 > 2048: bits = 12
                elif nxt + 1 > 1024: bits = 11
                elif nxt + 1 > 512: bits = 10
                if nxt >= 4094:
                    emit(256); table = {bytes([i]): i for i in range(256)}; nxt = 258; bits = 9
                w = bytes([ch])
        if w: emit(table[w])
        emit(257)
        acc = 0; n = 0; res = bytearray()
        for code, b in out_bits:
            acc = (acc << b) | code; n += b
            while n >= 8:
                res.append((acc >> (n - 8)) & 255); n -= 8
            acc &= (1 << n) - 1
        if n: res.append((acc << (8 - n)) & 255)
        return bytes(res)
    objs = dict(base); objs[4] = ("stream", "/Filter /LZWDecode", lzw_encode(cs * 6))
    raw_pdf(f"{out}/lzw.pdf", objs)

    # 9. damaged: truncated (no xref, no trailer) and with a wrong startxref
    data = open(f"{out}/plain-flate.pdf", "rb").read()
    open(f"{out}/damaged-notrailer.pdf", "wb").write(data[:data.index(b"xref\n0")])
    open(f"{out}/damaged-startxref.pdf", "wb").write(data.replace(b"startxref\n", b"startxref\n99999", 1))
    open(f"{out}/damaged-garbage.pdf", "wb").write(b"%PDF-1.4\nthis is not a pdf at all\n" * 5)
    open(f"{out}/damaged-empty.pdf", "wb").write(b"")
    # 10. a PDF with a form XObject and an Info dictionary
    form = b"0 1 0 rg 0 0 50 50 re f 0 0 0 RG 0 0 50 50 re S"
    objs = dict(base)
    objs[3] = b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Contents 4 0 R /Resources << /XObject << /Fm1 6 0 R >> >> >>"
    objs[4] = ("stream", "", b"q 2 0 0 2 20 20 cm /Fm1 Do Q q 1 0 0 1 150 150 cm /Fm1 Do Q")
    objs[6] = ("stream", "/Type /XObject /Subtype /Form /BBox [0 0 50 50]", form)
    raw_pdf(f"{out}/form.pdf", objs)
    for f in ("_i.png", "_i.jpg"):
        os.remove(f"{out}/{f}")

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "/tmp/pdfc")
