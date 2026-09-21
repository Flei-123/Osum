# SPDX-License-Identifier: GPL-2.0-only
# pruef/db-sprache.py -- PUNKT 1: IST DIE OBERFLAECHE DEUTSCH?
#
# Justin sieht im Startmenue "Write and change text", "View files and
# folders", "Find and start programs and files" -- also die ENGLISCHEN
# Saetze aus den INFO-Dateien der Buendel, obwohl locale/de/messages
# die Schluessel `editor.info`, `explorer.info` und `launcher.info`
# seit langem uebersetzt.
#
# DIESES DREHBUCH RAET NICHT, WO DIE KETTE REISST -- es liest die
# Kette an jedem Glied ab:
#
#   1. Welche Sprache hat der Katalog geladen?  -> `msg:`/`taskbar: lang=`
#   2. Wie viele Schluessel stehen darin?       -> keys=
#   3. Welchen NAMEN meldet der Starter je Buendel? -> `launcher: treffer`
#   4. Und was steht am Ende WIRKLICH auf dem Schirm? -> Bild
#
# Punkt 3 ist der entscheidende: appdir.name_of/info_of bauen den
# Schluessel aus dem Buendelnamen (`editor.osp` -> `editor.info`) und
# fallen auf das INFO-Feld zurueck, wenn msg.get den Schluessel SELBST
# zurueckgibt. Steht auf der Leitung der englische Satz, dann hat der
# Katalog diesen Schluessel nicht -- und dann ist die Frage, ob er die
# Datei nicht fand, die Sprache nicht kannte oder der Platz nicht
# reichte. Alle drei melden sich verschieden.
import re
import time

lauf.sag("== PUNKT 1: die Sprache der Oberflaeche ==")


def fenster():
    text = lauf.lies()
    bloecke = re.split(r"(?=wm: fen i=0 )", text)
    letzter = bloecke[-1] if len(bloecke) > 1 else text
    alle = re.findall(
        r"wm: fen i=\d+ id=(\d+) x=(-?\d+) y=(-?\d+) w=(\d+) h=(\d+) lay=(\d+)",
        letzter)
    d = {}
    for f in alle:
        d[int(f[0])] = tuple(int(v) for v in f[1:])
    return d


# ------------------------------------------------ 1. Was sagt der Katalog
roh = lauf.lies()

lauf.sag("-- 1. der Katalog, wie ihn die Programme melden --")
for zeile in re.findall(r"^[a-z]+: [^\n]*lang=[^\n]*$", roh, re.M):
    lauf.sag("   " + zeile.strip())
if not re.search(r"lang=", roh):
    lauf.sag("   KEINE EINZIGE lang=-Zeile auf der Leitung")

# ------------------------------------------------ 2. Die Namen der Buendel
lauf.sag("-- 2. was der Starter je Buendel meldet --")
treffer = re.findall(r"^launcher: [^\n]*name=\[[^\]]*\][^\n]*$", roh, re.M)
for t in treffer[:20]:
    lauf.sag("   " + t.strip())
if not treffer:
    lauf.sag("   (keine treffer-Zeilen -- der Starter meldet sie nur beim Suchen)")

name_zeilen = re.findall(r"^launcher: name \[([^\]]*)\]", roh, re.M)
for n in name_zeilen:
    lauf.sag("   eigener Name: [%s]" % n)

# ------------------------------------------------ 3. Das Startmenue oeffnen
lauf.sag("-- 3. das Startmenue --")
vor = fenster()
lauf.m.taste("meta_l")
time.sleep(3)
lauf.bild("startmenue")

men = [(i, v) for i, v in fenster().items() if v[4] == 4]
if not men:
    lauf.sag("   KEIN STARTMENUE -- Super hat nichts geoeffnet")
else:
    mid, (mx, my, mw, mh, _) = men[-1]
    lauf.sag("   Startmenue id=%d bei %d,%d  %dx%d" % (mid, mx, my, mw, mh))

# ------------------------------------------------ 4. Suchen -> Trefferliste
# Der Starter meldet `treffer ... name=[...]` erst, wenn gesucht wird.
# Ein einzelner Buchstabe, der auf alle drei Programme passt: "e".
lauf.sag("-- 4. eine Suche, damit die Namen auf die Leitung kommen --")
if men:
    lauf.m.klick_auf(mx + 207, my + 60)
    time.sleep(1)
    lauf.m.tippe("e")
    time.sleep(3)
    lauf.bild("suche-e")

    roh2 = lauf.lies()
    treffer2 = re.findall(r"^launcher: [^\n]*name=\[[^\]]*\][^\n]*$", roh2, re.M)
    for t in treffer2[:20]:
        lauf.sag("   " + t.strip())
    if not treffer2:
        lauf.sag("   NICHTS -- der Starter meldet keine Treffer")

lauf.sag("== Ende Punkt 1 ==")
