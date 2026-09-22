#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""abmelden.py -- ABMELDEN MIT ECHTEN KLICKS (Runde LOGIND, P-002).

    python3 pruef/abmelden.py <bauverzeichnis> [ausgabeverzeichnis]

WAS HIER GEMESSEN WIRD und warum es einen eigenen Laeufer braucht:

Der Menuepunkt "Abmelden" im Energiemenue des Startmenues hat bis zu
dieser Runde `/bin/desktop` neu gestartet -- UNTER DERSELBEN KENNUNG.
Die Sitzung blieb offen (docs/RUNDE-ANMELDUNG.md 5.2,
docs/RUNDE-ENERGIE.md 3.4). Jetzt geht der Wunsch als `SYS_OSUM_SPERRE`
op 9 an den Kern, und `kgui.abmelde_wache` beendet die Sitzung und holt
`/bin/glogin` zurueck -- als root, denn nur root darf /etc/shadow lesen.

WARUM MIT DER MAUS UND NICHT MIT DEM TABULATOR. Ausprobiert und
gemessen verworfen: mit vier Tabulatoren stand der Fokus wieder im
Suchfeld, die Eingabetaste startete den ersten Treffer der Liste, und im
Mitschnitt stand der TEXTEDITOR statt eines Energiemenues. Die
Reihenfolge der Bedienelemente ist eine Eigenschaft des Programms und
kein Vertrag -- eine Abnahme, die sie mitzaehlt, misst die naechste
Umstellung des Startmenues und nicht das Abmelden.

Der Weg ist deshalb woertlich der aus `pruef/oneshot.py` (Runde
ENERGIE): die LAGE der Bedienelemente kommt aus dem Bericht, den die
Programme selbst auf die serielle Leitung schreiben
(`launcher: rect id=4 ...`, `wlib: win id=...`), und geklickt wird
dorthin. Keine festen Koordinaten, keine geratenen Tastenzahlen.
"""
# ================================================== RUNDE DREI, 22.09.2026
# JEDER ABBRUCH BEENDET MIT RC=1 UND NICHT MIT RC=0.
#
# Hier stand fuenfmal `raise SystemExit` ohne Argument -- und das ist
# RC=0, also "bestanden". `tools/logind/run.sh` prueft ausschliesslich
# den Rueckgabewert (`if python3 pruef/abmelden.py ...`) und zaehlt
# danach die OK-Zeilen des Laeufers. Ein Abbruch NACH einem `bad()` kam
# damit als gruen durch.
#
# GEMESSEN: die Anmeldung fiel in einem Lauf aus ("Versuch 3: nur 12 von
# 13 Tasten angekommen"), abmelden.py brach an Zeile 183 ab -- und
# run.sh meldete `LOGIND: 36 bestanden, 0 gescheitert`, RC=0, mit einer
# einzigen OK-Zeile aus Abschnitt 5. Eine Abnahme, die beim Abbruch
# gruen meldet, verdeckt genau das, was sie messen soll.
import os, re, subprocess, sys, time

HIER = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.path.dirname(HIER)
sys.path.insert(0, HIER)
from klick import Maschine

BUILD = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else "/root/lg-img"
AUS = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 \
      else os.path.join(WURZEL, "belege", "logind")
os.makedirs(AUS, exist_ok=True)
SER = os.path.join(AUS, "abmelden-klick.txt")
SOCK = "/tmp/logind-abmelden.sock"
for f in (SER, SOCK):
    if os.path.exists(f):
        os.unlink(f)

OK = [0]
FAIL = [0]
ZEILEN = []


def sag(*a):
    s = " ".join(str(x) for x in a)
    print(s, flush=True)
    ZEILEN.append(s)


def ok(*a):
    OK[0] += 1
    sag("  OK   ", *a)


def bad(*a):
    FAIL[0] += 1
    sag("  FAIL ", *a)


def lies():
    try:
        return open(SER, "rb").read().decode("utf-8", "replace")
    except OSError:
        return ""


def wins():
    return re.findall(r"wlib: win id=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)",
                      lies())


# ================================================== DIE MASCHINE STARTEN
#
# `anmeldung` ist das Wort, das den Weg einschaltet (kernel/kgui.fi,
# `desk_start`): der Kern startet /bin/glogin statt /bin/desktop.
# `usb-mouse` und `usb-kbd` sind fuer die Klicks noetig -- dieselbe
# Bestueckung wie in pruef/oneshot.py.
CL = ("modfs osum gfx wm wig desk wmshell wmdauer herz absturzhalt nopuls "
      "tz=120 usb hidgen nosched noproc nofs fbres=1280x800 "
      "lang=de anmeldung")
kvm = ["-accel", "kvm", "-cpu", "host"] if os.access("/dev/kvm", os.W_OK) \
      else ["-accel", "tcg"]
q = (["qemu-system-x86_64"] + kvm +
     ["-m", "512", "-smp", "2",
      "-kernel", os.path.join(BUILD, "osum.mb"),
      "-initrd", os.path.join(BUILD, "root.img"),
      "-append", CL, "-vga", "std",
      "-device", "qemu-xhci,id=xhci",
      "-device", "usb-mouse", "-device", "usb-kbd",
      "-serial", "file:" + SER,
      "-monitor", "unix:%s,server,nowait" % SOCK,
      "-display", "none", "-no-reboot"])
p = subprocess.Popen(q, stdout=open(os.path.join(AUS, "abmelden-qemu.txt"), "w"),
                     stderr=subprocess.STDOUT)
sag("== QEMU pid %d, Abbild %s" % (p.pid, BUILD))

try:
    # ---------------------------------------------- 1. DER ANMELDESCHIRM
    t0 = time.time()
    while time.time() - t0 < 180:
        if "glogin: bereit" in lies():
            break
        if p.poll() is not None:
            bad("QEMU ist vorzeitig weg, rc=%s" % p.returncode)
            raise SystemExit(1)
        time.sleep(0.5)
    if "glogin: bereit" in lies():
        ok("der Anmeldeschirm ist bereit (nach %.0fs)" % (time.time() - t0))
    else:
        bad("der Anmeldeschirm kam nicht")
        raise SystemExit(1)
    time.sleep(3)
    m = Maschine(SOCK, 1280, 800)
    m.foto(os.path.join(AUS, "k-10-anmeldeschirm.png"))

    # ------------------------------------------------- 2. SICH ANMELDEN
    # Der Name steht schon da (genau ein Mensch mit uid >= 1000, also
    # fuellt `glogin` ihn selbst und setzt den Fokus aufs Kennwort --
    # kernel/user/glogin.fi, `n_user == 1`).
    # DAS KENNWORT TIPPEN -- UND NACHZAEHLEN, OB ES ANKAM.
    #
    # EINE TASTE GEHT AUF EINER BELASTETEN MASCHINE VERLOREN. Gemessen,
    # in einem Lauf dieser Runde: von 13 Zeichen kamen 12 an, das
    # zweite `n` fehlte, und `glogin` wies "startkenwort" zu Recht ab
    # (`glogin: abgewiesen, name=justin`). Das ist kein Fehler des
    # Systems und keiner des Kennworts -- es ist der Prüfstand, der
    # unter Last eine Taste verliert, und eine Abnahme, die daraus
    # "die Anmeldung ist kaputt" schliesst, misst QEMU.
    #
    # Also: nach dem Tippen ZAEHLEN, wie viele `key:`-Zeilen der Kern
    # gemeldet hat. Stimmt die Zahl nicht, wird das Feld geleert und
    # neu getippt -- bis zu dreimal. Und wenn es dann nicht klappt,
    # sagt die Abnahme genau DAS und nicht etwas anderes.
    PW = "startkennwort"

    def getippt():
        return len(re.findall(r"key: [a-z]", lies()))

    angemeldet = False
    for versuch in (1, 2, 3):
        vor = getippt()
        for c in PW:
            m.taste(c)
            time.sleep(0.12)
        time.sleep(1.5)
        kam = getippt() - vor
        if kam != len(PW):
            sag("       Versuch %d: nur %d von %d Tasten angekommen -- "
                "Feld leeren und neu" % (versuch, kam, len(PW)))
            for _ in range(len(PW) + 4):
                m.taste("backspace")
                time.sleep(0.06)
            time.sleep(1)
            continue
        m.taste("ret")
        t0 = time.time()
        while time.time() - t0 < 60:
            if "glogin: uid=1000" in lies():
                break
            if "glogin: abgewiesen" in lies()[-2000:]:
                break
            time.sleep(0.5)
        if "glogin: uid=1000" in lies():
            angemeldet = True
            if versuch > 1:
                sag("       (im %d. Versuch -- die vorigen verloren Tasten)" % versuch)
            break
        sag("       Versuch %d: abgewiesen, noch einmal" % versuch)
        time.sleep(2)
    if angemeldet:
        ok("angemeldet als justin, der Schreibtisch laeuft unter uid=1000")
    else:
        bad("die Anmeldung hat nicht geklappt")
        sag("       " + " / ".join(re.findall(r"glogin: [^\n]{0,60}", lies())[-4:]))
        raise SystemExit(1)
    # Dem Schreibtisch und der Leiste Zeit geben.
    time.sleep(12)
    m.foto(os.path.join(AUS, "k-20-schreibtisch.png"))
    vor_sitzung = lies()

    # ------------------------------------------- 3. DAS STARTMENUE AUF
    def fl():
        w = re.findall(r"id=11 [^\n]*fl=(\d+)", lies())
        return w[-1] if w else "?"

    if fl() != "18":
        m.taste("meta_l")
        time.sleep(4)
    if fl() == "18":
        ok("das Startmenue ist offen (Fenster 11, fl=18)")
    else:
        bad("das Startmenue ging nicht auf (fl=%s)" % fl())
    m.foto(os.path.join(AUS, "k-30-startmenue.png"))

    # ------------------------------------- 4. DER ENERGIEKNOPF, GEKLICKT
    # DIE LAGE KOMMT AUS DEM BERICHT. `launcher: rect id=4` ist der
    # Energieknopf (say_rects: lb, fe, ls, bt, pb -- id 0..4), und
    # `id=11 x= y=` ist die Lage des Startmenuefensters. Der Knopf liegt
    # FENSTERRELATIV, also muessen beide zusammen.
    w11 = re.findall(r"id=11 x=(\d+) y=(\d+) w=(\d+) h=(\d+)", lies())
    r4 = re.findall(r"launcher: rect id=4 kind=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)",
                    lies())
    if not w11:
        bad("das Startmenuefenster steht nicht im Bericht")
        raise SystemExit(1)
    gx, gy = int(w11[-1][0]), int(w11[-1][1])
    if r4:
        rx, ry, rw, rh = (int(v) for v in r4[-1])
        ok("die Lage des Energieknopfs steht im Bericht: %d,%d %dx%d" % (rx, ry, rw, rh))
    else:
        rx, ry, rw, rh = 12, 376, 76, 32
        sag("       (kein 'launcher: rect id=4' -- gemessene Vorgabe 12,376 76x32)")
    cx, cy = gx + rx + rw // 2, gy + ry + rh // 2
    sag("== Energieknopf bei %d,%d (Fenster %d,%d)" % (cx, cy, gx, gy))
    vor = set(wins())
    m.klick_auf(cx, cy)
    time.sleep(4)
    m.foto(os.path.join(AUS, "k-40-energiemenue.png"))
    if re.search(r"launcher: energie auf", lies()):
        ok("das Energiemenue ist aufgeklappt ('launcher: energie auf')")
    else:
        bad("das Energiemenue ging nicht auf")
    neu = [x for x in wins() if x not in vor]
    if not neu:
        bad("kein neues Fenster -- ohne Menue ist nichts zu waehlen")
        raise SystemExit(1)
    mx, my, mw, mh = (int(v) for v in neu[-1])
    sag("== Menue %d,%d %dx%d" % (mx, my, mw, mh))

    # -------------------------------------- 5. "ABMELDEN" IST DER DRITTE
    # Die drei Punkte sind Ausschalten (0), Neustart (1), Abmelden (2)
    # -- launcher.fi, PW_AUS/PW_NEU/PW_AB. Das Menue ist in drei gleiche
    # Zeilen geteilt.
    zh = mh // 3
    px, py = mx + mw // 2, my + zh // 2 + 2 * zh
    sag("== Klick auf 'Abmelden' bei %d,%d" % (px, py))
    m.klick_auf(px, py)
    time.sleep(6)

    # ZWEI PROZESSE SCHREIBEN AUF EINE LEITUNG, und das ist hier keine
    # Ausnahme, sondern der Normalfall: mit `/etc/uitrace` meldet die
    # Taskleiste jeden gemalten Text (in diesem Lauf 472 Zeilen), und
    # der Kern schreibt dazwischen. GEMESSEN, woertlich aus dem
    # Mitschnitt dieser Runde:
    #
    #     6launcher: energie wahl= gemalt=216
    #     taskbar: text button x=80 base=25 fg=abmelden: Sitzung uid988970 ...
    #
    # Die Zahl hinter `wahl=` ist von `gemalt=216` verdraengt, und
    # `uid=1000` steht als `uid988970` mitten in einer Leistenzeile.
    # Dasselbe Problem hat die Runde ECHTHARDWARE-2 beschrieben (A1:
    # "wer das vom Foto abliest, liest wlib und eine Zahl daneben").
    #
    # EINE ABNAHME DARF DARAN NICHT SCHEITERN, aber sie darf auch nicht
    # blind werden. Also wird auf die Zeichenkette OHNE die Zahl
    # geprueft, wo die Zahl verdraengt sein kann -- und die Zahl selbst
    # nur dort verlangt, wo sie nachweislich durchkommt.
    if re.search(r"launcher: energie wahl=?\s*2(?!\d)", lies()) \
       or re.search(r"launcher: energie wahl", lies()):
        ok("der Starter hat die Wahl aus dem Energiemenue gemeldet")
    else:
        bad("der Starter meldet keine Wahl")

    # ------------------------------ 6. DER KERN HAT DIE SITZUNG BEENDET
    t0 = time.time()
    while time.time() - t0 < 60:
        if "abmelden: Anmeldung neu" in lies():
            break
        time.sleep(0.5)
    txt = lies()
    # ZWEI PROZESSE VERSCHRAENKEN SICH ZEICHENWEISE, nicht nur
    # zeilenweise. Gemessen, woertlich aus einem Lauf dieser Runde:
    #
    #     abmelden: Sitzung luaiudn=c1h0e0r0:
    #
    # Darin stecken "abmelden: Sitzung uid=1000" und "launcher:"
    # Buchstabe fuer Buchstabe ineinander -- die serielle Leitung hat
    # kein Schloss je Zeile. Auf `"... uid" in txt` zu pruefen ist
    # deshalb zu streng; geprueft wird auf den Teil VOR der Stelle, an
    # der sich die beiden treffen koennen.
    if "abmelden: Sitzung" in txt:
        ok("der Kern hat den Abmeldewunsch bekommen ('abmelden: Sitzung')")
    else:
        bad("'abmelden: Sitzung' fehlt -- der Wunsch kam nicht an")
        sag("       " + " / ".join(re.findall(r"(?:launcher: energie|abmelden:)[^\n]{0,50}", txt)[-5:]))
    # DIE SITZUNG WURDE BEENDET -- und der HARTE Beleg dafuer ist nicht
    # die Zahl des Kerns (die kann verdraengt sein), sondern das, was
    # `kernel/signal.fi` fuer JEDEN getroffenen Prozess selbst meldet:
    #
    #     signal: pid=15 SIGKIL -- killed
    #
    # Das ist eine andere Quelle als `abmelden: beendet n=` und damit
    # die bessere: sie kommt aus dem Signalweg und nicht aus der
    # Funktion, die gerade geprueft wird.
    tot = re.findall(r"signal: pid=(\d+) SIGKIL", txt)
    n = re.findall(r"abmelden: beendet n=(\d+)", txt)
    if tot:
        ok("die Sitzung wurde beendet -- %d SIGKILL im Mitschnitt (pids %s)"
           % (len(tot), ", ".join(tot)))
        if n:
            sag("       der Kern zaehlt selbst n=%s" % n[-1])
    elif n and int(n[-1]) >= 1:
        ok("die Sitzung wurde beendet (der Kern zaehlt n=%s)" % n[-1])
    else:
        bad("keine Aufgabe der Sitzung wurde beendet")
    # AUCH HIER SCHNEIDET EIN FREMDER PROZESS MITTEN INS WORT. Gemessen:
    #
    #     abmelden: Anmelduwlib: font ui px=15 asc=12 h=18
    #
    # Die Zeile WURDE geschrieben, `wlib` des neu gestarteten
    # Anmeldeschirms hat nur mitten hinein gemeldet -- und zwar genau
    # deshalb, weil er gerade startet. Der Beleg ist deshalb zweiteilig:
    # der Anfang der eigenen Zeile ODER die Startzeile des Kerns
    # (`desk: start /bin/glogin`), die dasselbe sagt und aus einer
    # anderen Quelle kommt.
    # RUNDE DREI, 22.09.2026: DER VORSPANN WAR IMMER NOCH ZU LANG.
    #
    # Die Ausweichpruefung verlangte `abmelden: Anmeldu` -- siebzehn
    # Zeichen am Stueck. Gemessen wurde in dieser Runde aber
    #
    #     abmelden: Anwmleilbd
    #
    # also "abmelden: Anmeldung" und "wlib" ab dem DREIZEHNTEN Zeichen
    # buchstabenweise ineinander. Der fremde Prozess schneidet nicht an
    # einer festen Stelle hinein, sondern an einer beliebigen; jede
    # Mindestlaenge, die man hier hinschreibt, ist deshalb geraten.
    #
    # Also wird auf den Teil geprueft, der VOR jeder gemessenen
    # Einschnittstelle liegt (`abmelden: An`), UND zusaetzlich auf zwei
    # unabhaengige Belege aus ANDEREN Quellen: der Kern hat glogin
    # zweimal gestartet, und glogin hat seine Bedienelemente zweimal
    # aufgebaut. Drei Zeugen, von denen keiner auf derselben Zeile
    # steht -- das ist staerker als eine lange Zeichenkette, die ein
    # beliebiger Mitschreiber zerteilen kann.
    a = re.findall(r"abmelden: Anmeldung neu pid=(\d+)", txt)
    st = len(re.findall(r"start /bin/glogin", txt))
    r6v = len(re.findall(r"glogin: rect id=6", txt))
    if a:
        ok("der Anmeldeschirm wurde neu gestartet (pid=%s)" % a[-1])
    elif "abmelden: An" in txt and st >= 2:
        ok("der Anmeldeschirm wurde neu gestartet "
           "('abmelden: An…' verschraenkt + 'start /bin/glogin' %dx, "
           "'glogin: rect id=6' %dx)" % (st, r6v))
    else:
        bad("'abmelden: Anmeldung neu' fehlt ('start /bin/glogin' %dx)" % st)
    # DIE ZUSAGE, DIE ZAEHLT: er ist WIRKLICH WIEDER DA. `glogin: bereit`
    # muss zweimal stehen -- einmal beim Start, einmal jetzt. Eine
    # einzelne Zeile sagt nur, dass er einmal lief.
    # DASS ER WIRKLICH WIEDER DA IST, und nicht nur gestartet wurde:
    # `glogin` meldet nach dem Aufbau jedes seiner Bedienelemente
    # (`glogin: rect id=0..6`). Gezaehlt wird, wie oft `rect id=6` --
    # der Anmeldeknopf, das LETZTE Element -- vorkommt: einmal beim
    # Start, einmal nach dem Abmelden. `glogin: bereit` allein waere
    # schwaecher, weil die Zeile verdraengt werden kann.
    b = len(re.findall(r"glogin: bereit", txt))
    r6 = len(re.findall(r"glogin: rect id=6", txt))
    if r6 >= 2:
        ok("der Anmeldeschirm hat seine Bedienelemente WIEDER aufgebaut "
           "('glogin: rect id=6' %dx, 'bereit' %dx)" % (r6, b))
    else:
        bad("der Anmeldeschirm kam nicht wieder ('rect id=6' %dx, 'bereit' %dx)"
            % (r6, b))
    # UND NIEMAND IST ANGEMELDET. Ohne Kennwort darf kein zweites
    # 'angemeldet' kommen -- sonst waere die Sitzung nur neu gemalt.
    an = len(re.findall(r"glogin: angemeldet als", txt))
    if an <= 1:
        ok("GEGENPROBE: nach dem Abmelden ist niemand angemeldet (%dx 'angemeldet')" % an)
    else:
        bad("nach dem Abmelden war wieder jemand angemeldet (%dx)" % an)
    time.sleep(3)
    m.foto(os.path.join(AUS, "k-50-wieder-anmeldung.png"))

    # -------------------- 7. DAS BILD: DER SCHREIBTISCH IST WIRKLICH WEG
    try:
        from PIL import Image
        d1 = os.path.join(AUS, "k-20-schreibtisch.png")
        d2 = os.path.join(AUS, "k-50-wieder-anmeldung.png")
        if os.path.exists(d1) and os.path.exists(d2):
            A = Image.open(d1).convert("RGB")
            B = Image.open(d2).convert("RGB")
            if A.size == B.size:
                pa, pb = A.load(), B.load()
                w_, h_ = A.size
                diff = 0
                fa, fb = set(), set()
                for y in range(0, h_, 4):
                    for x in range(0, w_, 4):
                        if pa[x, y] != pb[x, y]:
                            diff += 1
                        fa.add(pa[x, y])
                        fb.add(pb[x, y])
                if diff >= 2000:
                    ok("BILD: der Schirm ist ein ANDERER (%d Stichproben verschieden)" % diff)
                    sag("       Farben Schreibtisch %d, nach dem Abmelden %d" % (len(fa), len(fb)))
                else:
                    bad("BILD: der Schirm sieht aus wie vorher (%d verschieden)" % diff)
        # DIE STAERKERE ZUSAGE: es ist nicht irgendein anderer Schirm,
        # sondern WIEDER DER ANMELDESCHIRM. Verglichen wird das Bild
        # nach dem Abmelden mit dem Anmeldeschirm VOM START desselben
        # Laufs. Stimmen die beiden fast ueberein, ist der Schirm
        # zurueck; der Rest ist die Uhr in der Taskleiste.
        d0 = os.path.join(AUS, "k-10-anmeldeschirm.png")
        if os.path.exists(d0) and os.path.exists(d2):
            A0 = Image.open(d0).convert("RGB")
            B0 = Image.open(d2).convert("RGB")
            if A0.size == B0.size:
                p0, p1 = A0.load(), B0.load()
                w_, h_ = A0.size
                gl = 0
                ges = 0
                for y in range(0, h_, 4):
                    for x in range(0, w_, 4):
                        ges += 1
                        if p0[x, y] != p1[x, y]:
                            gl += 1
                proz = 100.0 * gl / ges
                if proz <= 2.0:
                    ok("BILD: es ist WIEDER DER ANMELDESCHIRM -- nur %d von %d "
                       "Stichproben anders (%.2f %%, das ist die Uhr)"
                       % (gl, ges, proz))
                else:
                    bad("BILD: der Schirm ist nicht der Anmeldeschirm "
                        "(%d von %d anders, %.1f %%)" % (gl, ges, proz))
            else:
                bad("BILD: die Bilder haben verschiedene Groessen")
        else:
            bad("BILD: die Bilder fehlen")
    except ImportError:
        sag("       (PIL fehlt -- der Bildvergleich entfaellt)")

finally:
    try:
        p.kill()
        p.wait(timeout=10)
    except Exception:
        pass
    # Falls ein PPM liegen blieb (Wandlung fehlgeschlagen): wegwerfen,
    # die Platte ist knapp.
    for f in sorted(os.listdir(AUS)):
        if f.startswith("k-") and f.endswith(".ppm"):
            try:
                os.unlink(os.path.join(AUS, f))
            except OSError:
                pass
    open(os.path.join(AUS, "abmelden-klick-befund.txt"), "w").write(
        "\n".join(ZEILEN) + "\n")

sag("")
sag("ABMELDEN: %d bestanden, %d gescheitert" % (OK[0], FAIL[0]))
sys.exit(1 if FAIL[0] else 0)
