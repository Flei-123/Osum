#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/wasm2firn/wasm2firn.py -- RUNDE SCHLEUSE-2
#
# WASM VORAB nach Firn uebersetzen, statt es zur Laufzeit zu deuten.
#
# Das ist das wasm2c-Prinzip. Der Deuter aus SCHLEUSE liest bei JEDEM
# Befehl ein Oktett, verteilt ueber eine if/else-Kette und bewegt einen
# Stapel im Speicher -- 67 ns je Schritt, 158x langsamer als nativ.
# Hier passiert das alles EINMAL, auf dem Bauserver: aus jeder
# WASM-Funktion wird eine Firn-Funktion, aus dem Stapel werden lokale
# Variablen, aus dem Kontrollfluss werden Firn-Schleifen. Was uebrig
# bleibt, uebersetzt firnc zu Maschinencode.
#
# WARUM DAS HIER IN PYTHON STEHT UND NICHT IN FIRN. Das Werkzeug laeuft
# auf dem BAUSERVER, nie auf Osum -- dort ist alles erlaubt. Das
# ERGEBNIS muss mit firnc bauen, und nur das zaehlt.
#
# ---------------------------------------------------------------- Der
# Stapel wird zu Variablen. WASM ist eine Stapelmaschine, aber die
# Stapelhoehe ist an jeder Stelle STATISCH bekannt -- das ist die
# Eigenschaft, auf der wasm2c steht. `i32.add` nimmt zwei Werte und legt
# einen zurueck; wo der Stapel vorher 5 tief war, ist er danach 4 tief.
# Also heisst der oberste Wert einfach `s4`, und aus
#
#     local.get 0 ; local.get 1 ; i32.add
#
# wird
#
#     s0 = l0 ; s1 = l1 ; s0 = (s0 +% s1) & 4294967295
#
# Kein Stapelzeiger, kein Speicherzugriff, keine Grenzpruefung je Befehl.
#
# ---------------------------------------------------------------- Der
# Kontrollfluss. WASM hat block/loop/if mit `br N` ("verlasse den N-ten
# Block von innen"). Firn hat while/if/break/continue. Die Uebersetzung,
# die immer traegt und ohne Relooper auskommt:
#
#   block  -> `while true { ... break }`   (br = break aus dieser Schleife)
#   loop   -> `while true { ... break }`   (br = continue, also zurueck)
#   if     -> `if ... {}` -- und WEIL ein `br` aus einem `if` heraus
#             mehrere Ebenen springen kann, traegt jede Funktion eine
#             Sprungvariable `br_ziel`. Wer `br 2` macht, setzt sie auf
#             die Tiefe des Ziels und verlaesst die innerste Schleife;
#             jede umgebende Schleife prueft am Ende, ob sie selbst
#             gemeint ist, und bricht sonst weiter aus.
#
# Das kostet einen Vergleich je verlassener Ebene, nicht je Befehl.
#
# ---------------------------------------------------------------- Das
# umlaufende Rechnen. WASM rechnet umlaufend, Firn prueft. firnc hat
# dafuer `+% -% *%` (SPEC ~1238), die ohne jede Pruefung genau eine
# Anweisung erzeugen -- am Assembler nachgesehen, siehe STATUS-SCHLEUSE2
# Abschnitt 0. i32 wird in u64 gerechnet und mit & 4294967295 auf 32 Bit
# geschnitten; i64 laeuft direkt in u64.

import struct
import sys

# ------------------------------------------------------------ Lesen

class Leser:
    def __init__(self, b, at=0):
        self.b = b
        self.at = at

    def u8(self):
        v = self.b[self.at]
        self.at += 1
        return v

    def uleb(self):
        r = 0
        s = 0
        while True:
            x = self.u8()
            r |= (x & 0x7F) << s
            if not (x & 0x80):
                return r
            s += 7

    def sleb(self):
        r = 0
        s = 0
        while True:
            x = self.u8()
            r |= (x & 0x7F) << s
            s += 7
            if not (x & 0x80):
                if x & 0x40:
                    r -= 1 << s
                return r

    def f32(self):
        v = struct.unpack_from('<f', self.b, self.at)[0]
        self.at += 4
        return v

    def f64(self):
        v = struct.unpack_from('<d', self.b, self.at)[0]
        self.at += 8
        return v

    def bytes(self, n):
        v = self.b[self.at:self.at + n]
        self.at += n
        return v

    def name(self):
        return self.bytes(self.uleb()).decode('utf-8', 'replace')


I32, I64, F32, F64, EMPTY = 0x7F, 0x7E, 0x7D, 0x7C, 0x40

# Ab so vielen Bloecken am Stueck wird aus dem Turm ein Verteiler.
# firnc laesst 200 Ebenen zu; 64 ist reichlich Abstand und trifft nur
# echte Sprungtabellen, keine gewoehnliche Schachtelung.
TURM_GRENZE = 64


def typname(t):
    return {I32: 'i32', I64: 'i64', F32: 'f32', F64: 'f64'}.get(t, '?')


# Wie ein Wert in Firn gehalten wird. ALLES liegt in u64 -- auch die
# Gleitkommazahlen, die als Bitmuster durchgereicht und nur zum Rechnen
# ausgepackt werden. Ein einziger Variablentyp macht den Stapel
# uniform: `s3` ist immer u64, egal was gerade darin liegt.
FIRNTYP = 'u64'


class Modul:
    def __init__(self, b):
        self.b = b
        self.typen = []          # [(params, results)]
        self.importe = []        # [(modul, name, art, index)]
        self.funktypen = []      # typindex je funktion (importe zuerst)
        self.tabelle_min = 0
        self.elemente = []       # [(offset, [funcidx])]
        self.mem_min = 0
        self.mem_max = 0
        self.globals = []        # [(typ, veraenderlich, initwert, ist_import)]
        self.exporte = {}        # name -> (art, index)
        self.start = None
        self.code = []           # [(lokale, bytecode)] nur eigene funktionen
        self.data = []           # [(offset, bytes)]
        self.n_import_funcs = 0
        self.namen = {}          # funcidx -> name aus der name-Sektion
        self.lesen()

    def lesen(self):
        b = self.b
        if b[0:4] != b'\x00asm':
            raise SystemExit('kein WASM-Modul')
        at = 8
        while at < len(b):
            l = Leser(b, at)
            sid = l.u8()
            groesse = l.uleb()
            ende = l.at + groesse
            self.sektion(sid, Leser(b, l.at), ende)
            at = ende

    def sektion(self, sid, l, ende):
        if sid == 1:
            for _ in range(l.uleb()):
                l.u8()                      # 0x60
                p = [l.u8() for _ in range(l.uleb())]
                r = [l.u8() for _ in range(l.uleb())]
                self.typen.append((p, r))
        elif sid == 2:
            for _ in range(l.uleb()):
                m = l.name()
                n = l.name()
                art = l.u8()
                if art == 0:
                    ti = l.uleb()
                    self.importe.append((m, n, 'func', ti))
                    self.funktypen.append(ti)
                    self.n_import_funcs += 1
                elif art == 1:
                    l.u8()
                    self.grenzen(l)
                    self.importe.append((m, n, 'table', 0))
                elif art == 2:
                    mn, mx = self.grenzen(l)
                    self.mem_min = max(self.mem_min, mn)
                    self.mem_max = mx
                    self.importe.append((m, n, 'memory', 0))
                elif art == 3:
                    t = l.u8()
                    ver = l.u8()
                    self.globals.append((t, ver, 0, True))
                    self.importe.append((m, n, 'global', 0))
        elif sid == 3:
            for _ in range(l.uleb()):
                self.funktypen.append(l.uleb())
        elif sid == 4:
            for _ in range(l.uleb()):
                l.u8()
                mn, _ = self.grenzen(l)
                self.tabelle_min = max(self.tabelle_min, mn)
        elif sid == 5:
            for _ in range(l.uleb()):
                mn, mx = self.grenzen(l)
                self.mem_min = max(self.mem_min, mn)
                self.mem_max = mx
        elif sid == 6:
            for _ in range(l.uleb()):
                t = l.u8()
                ver = l.u8()
                w = self.konstausdruck(l)
                self.globals.append((t, ver, w, False))
        elif sid == 7:
            for _ in range(l.uleb()):
                n = l.name()
                art = l.u8()
                self.exporte[n] = (art, l.uleb())
        elif sid == 8:
            self.start = l.uleb()
        elif sid == 9:
            for _ in range(l.uleb()):
                flag = l.uleb()
                if flag == 0:
                    off = self.konstausdruck(l)
                    n = l.uleb()
                    self.elemente.append((off, [l.uleb() for _ in range(n)]))
                else:
                    # passive/deklarative Segmente: fuer unsere Module
                    # nicht noetig, aber sauber ueberspringen
                    if flag in (1, 3):
                        l.u8()
                        n = l.uleb()
                        for _ in range(n):
                            l.uleb()
                    elif flag == 2:
                        l.uleb()
                        off = self.konstausdruck(l)
                        l.u8()
                        n = l.uleb()
                        self.elemente.append((off, [l.uleb() for _ in range(n)]))
        elif sid == 10:
            for _ in range(l.uleb()):
                groesse = l.uleb()
                bis = l.at + groesse
                lok = []
                for _ in range(l.uleb()):
                    anz = l.uleb()
                    t = l.u8()
                    lok.append((anz, t))
                self.code.append((lok, self.b[l.at:bis]))
                l.at = bis
        elif sid == 11:
            for _ in range(l.uleb()):
                flag = l.uleb()
                if flag == 0:
                    off = self.konstausdruck(l)
                    n = l.uleb()
                    self.data.append((off, l.bytes(n)))
                elif flag == 1:
                    n = l.uleb()
                    l.bytes(n)
                elif flag == 2:
                    l.uleb()
                    off = self.konstausdruck(l)
                    n = l.uleb()
                    self.data.append((off, l.bytes(n)))
        elif sid == 0:
            # name-Sektion: nur fuer lesbare Namen im Erzeugnis
            try:
                nm = l.name()
                if nm == 'name':
                    while l.at < ende:
                        u = l.u8()
                        gr = l.uleb()
                        bis = l.at + gr
                        if u == 1:
                            for _ in range(l.uleb()):
                                idx = l.uleb()
                                self.namen[idx] = l.name()
                        l.at = bis
            except Exception:
                pass

    def grenzen(self, l):
        f = l.u8()
        mn = l.uleb()
        mx = l.uleb() if f & 1 else 0
        return mn, mx

    def konstausdruck(self, l):
        # Ein Initialisierer ist ein winziger Ausdruck, der mit `end`
        # aufhoert. Fuer unsere Module reichen die Konstanten und
        # global.get (auf importierte Globale).
        w = 0
        while True:
            op = l.u8()
            if op == 0x0B:
                return w
            elif op == 0x41:
                w = l.sleb() & 0xFFFFFFFF
            elif op == 0x42:
                w = l.sleb() & 0xFFFFFFFFFFFFFFFF
            elif op == 0x43:
                w = struct.unpack('<I', struct.pack('<f', l.f32()))[0]
            elif op == 0x44:
                w = struct.unpack('<Q', struct.pack('<d', l.f64()))[0]
            elif op == 0x23:
                gi = l.uleb()
                if gi < len(self.globals):
                    w = self.globals[gi][2]
            else:
                raise SystemExit('unbekannter Initialisierer 0x%02x' % op)

    def typ_von(self, fi):
        return self.typen[self.funktypen[fi]]


# ---------------------------------------------------- Blocktypen

def blocktyp(m, bt):
    """(params, results) eines Blocks. Ein negativer Wert ist eine
    Kurzform (leer oder ein einzelner Werttyp), ein positiver ein
    Index in die Typtabelle."""
    if bt == -64:                      # 0x40, leer
        return [], []
    if bt in (-1, -2, -3, -4):         # i32 i64 f32 f64 als sleb
        return [], [{-1: I32, -2: I64, -3: F32, -4: F64}[bt]]
    return m.typen[bt]


class Block:
    def __init__(self, art, tiefe, stack_ein, res, marke):
        self.art = art          # 'block' | 'loop' | 'if'
        self.tiefe = tiefe
        self.stack_ein = stack_ein
        self.res = res
        self.marke = marke
        self.hat_else = False
        # Wird dieser Block als `while true` erzeugt? Nur dann darf
        # ein `break` darin stehen, und nur dann gibt es ein `continue`.
        self.schleife = (art == 'loop')
        # Nur fuer Ebenen eines Turms (siehe turm_erzeugen/TIEFE.md)
        self.turm_marke = None
        self.turm_fall = 0


# ====================================================================
#                          Der Erzeuger
# ====================================================================

# ------------------------------- braucht dieser `block` eine Schleife?
#
# Ein `block` wird nur dann zu `while true { ... break }`, wenn
# WIRKLICH jemand aus ihm herausspringt. Sonst reicht ein nackter
# Firn-Block `{ ... }`, und genau das entscheidet bei SQLite ueber
# Bauen oder Nicht-Bauen: mit `while` je Block erreichte die
# Verschachtelung 278 Ebenen, firnc laesst 200 zu.
#
# Gesucht wird ein `br`/`br_if`/`br_table`, das GENAU auf diesen Block
# zeigt -- also mit einer Sprungweite, die der Zahl der seither
# geoeffneten Ebenen entspricht.
def _block_braucht_schleife(b, at):
    tiefe = 0
    l = Leser(b, at)
    n = len(b)
    while l.at < n:
        op = l.u8()
        if op in (0x02, 0x03, 0x04):
            l.sleb()
            tiefe += 1
        elif op == 0x0B:
            if tiefe == 0:
                return False              # Ende dieses Blocks erreicht
            tiefe -= 1
        elif op == 0x05:
            pass
        elif op in (0x0C, 0x0D):
            if l.uleb() == tiefe:
                return True
        elif op == 0x0E:
            k = l.uleb()
            treffer = False
            for _ in range(k):
                if l.uleb() == tiefe:
                    treffer = True
            if l.uleb() == tiefe:
                treffer = True
            if treffer:
                return True
        else:
            _ueberlesen(l, op)
    return False


def _ueberlesen(l, op):
    if op in (0x10, 0x20, 0x21, 0x22, 0x23, 0x24):
        l.uleb()
    elif op == 0x11:
        l.uleb()
        l.uleb()
    elif op in (0x41, 0x42):
        l.sleb()
    elif op == 0x43:
        l.f32()
    elif op == 0x44:
        l.f64()
    elif 0x28 <= op <= 0x3E:
        l.uleb()
        l.uleb()
    elif op in (0x3F, 0x40):
        l.u8()
    elif op == 0x1C:
        for _ in range(l.uleb()):
            l.u8()
    elif op == 0xFC:
        u = l.uleb()
        if u == 10:
            l.u8()
            l.u8()
        elif u == 11:
            l.u8()


# ============================================================
#   Der Turm aus Bloecken -> ein Verteiler  (siehe TIEFE.md)
# ============================================================
#
# Ein `block`-Turm, der nur dazu da ist, dass ein `br_table` in einen
# von n Faellen springt, sprengt firncs Grenze von 200 Ebenen. SQLite
# hat genau eine solche Stelle: `yy_reduce` mit 276 Bloecken.
#
# Erkannt wird der Turm daran, dass am Stueck (ohne einen anderen
# Befehl dazwischen) mehr als GRENZE Bloecke geoeffnet werden.
def turm_messen(code, at):
    """Wie viele `block` werden ab `at` unmittelbar hintereinander
    geoeffnet? Gibt (anzahl, position_danach) zurueck."""
    l = Leser(code, at)
    n = 0
    while l.at < len(code):
        merk = l.at
        op = l.u8()
        if op != 0x02:
            l.at = merk
            break
        bt = l.sleb()
        if bt != -64:            # nur leere Blocktypen sind so einfach
            l.at = merk
            break
        n += 1
    return n, l.at


# Verlaesst IRGENDEIN Sprung diese Blockebene -- sie selbst oder eine
# weiter aussen? Dann muss der Block eine `while true` sein, denn nur
# aus einer Schleife traegt `break`. Ein nackter `{ }` wuerde das
# `break` an die naechste umgebende Schleife weiterreichen und den Rest
# des Blocks ueberspringen (siehe Kommentar an der Aufrufstelle).
def _block_hat_sprung(b, at):
    tiefe = 0
    l = Leser(b, at)
    n = len(b)
    while l.at < n:
        op = l.u8()
        if op in (0x02, 0x03, 0x04):
            l.sleb()
            tiefe += 1
        elif op == 0x0B:
            if tiefe == 0:
                return False
            tiefe -= 1
        elif op == 0x05:
            pass
        elif op in (0x0C, 0x0D):
            if l.uleb() >= tiefe:
                return True
        elif op == 0x0E:
            k = l.uleb()
            treffer = False
            for _ in range(k):
                if l.uleb() >= tiefe:
                    treffer = True
            if l.uleb() >= tiefe:
                treffer = True
            if treffer:
                return True
        else:
            _ueberlesen(l, op)
    return False


class Fehler(Exception):
    pass


class Erzeuger:
    def __init__(self, m, opt):
        self.m = m
        self.opt = opt
        self.out = []
        self.unbekannt = {}

    def w(self, s=''):
        self.out.append(s)

    # ---------------------------------------------------------- Namen
    def fname(self, fi):
        return 'f%d' % fi

    # ------------------------------------------------- eine Funktion
    def funktion(self, fi):
        m = self.m
        ci = fi - m.n_import_funcs
        lokdef, code = m.code[ci]
        par, res = m.typ_von(fi)

        # Lokale: erst die Parameter, dann die deklarierten
        lokal_typen = list(par)
        for anz, t in lokdef:
            lokal_typen += [t] * anz
        self.lokal_typen = lokal_typen
        self.nlok = len(lokal_typen)
        self.res = res
        self.fi = fi

        kopf = 'fn %s(%s)%s {' % (
            self.fname(fi),
            ', '.join('p%d: u64' % i for i in range(len(par))),
            ' -> u64' if res else '')
        self.w(kopf)

        # WASM darf auf PARAMETER schreiben (`local.set 0`), Firn nicht:
        # ein Parameter ist dort unveraenderlich. Also bekommt jeder
        # Parameter eine veraenderliche Kopie. Das kostet nichts --
        # firnc haelt beide im selben Register.
        for i in range(len(par)):
            self.w('    var l%d: u64 = p%d' % (i, i))
        # deklarierte Lokale sind in WASM garantiert null
        for i in range(len(par), self.nlok):
            self.w('    var l%d: u64 = 0' % i)

        self.koerper = []
        self.maxstack = 0
        self.br_benutzt = False
        self.im_turm = False
        self.turm_faelle = 0
        try:
            self.rumpf(code, par, res)
        except Fehler:
            raise
        # Stapelvariablen anlegen
        for i in range(self.maxstack):
            self.w('    var s%d: u64 = 0' % i)
        if self.br_benutzt:
            self.w('    var br_ziel: i64 = -1')
        self.out += self.koerper
        if res:
            self.w('    return 0')
        self.w('}')
        self.w('')

    def e(self, tiefe, s):
        # EIN Leerzeichen je Ebene, nicht vier. Bei SQLite wird bis zu
        # 278 Ebenen tief geschachtelt; mit vier Leerzeichen waeren das
        # 1112 Spalten Einrueckung je Zeile und ein Vielfaches an
        # Dateigroesse. Lesbar ist der erzeugte Text ohnehin nicht --
        # er ist Zwischenerzeugnis, kein Quelltext zum Anschauen.
        self.koerper.append(' ' + ' ' * tiefe + s)

    def sv(self, i):
        if i + 1 > self.maxstack:
            self.maxstack = i + 1
        return 's%d' % i

    # ------------------------------------------------------ der Rumpf
    #
    # Ein Durchgang ueber den Bytecode. `sp` ist die STATISCHE
    # Stapelhoehe -- die Zahl, die den ganzen Ansatz traegt: an jeder
    # Stelle im Code steht fest, wie viele Werte auf dem Stapel liegen,
    # also bekommt jeder davon eine eigene Variable.
    def rumpf(self, code, par, res):
        m = self.m
        l = Leser(code)
        sp = 0
        # Der aeusserste "Block" ist die Funktion selbst: ein `br` auf
        # die aeusserste Tiefe ist ein `return`.
        stapel = [Block('func', 0, 0, res, 0)]
        self.marke = 0
        tiefe = 1
        unerreichbar = False

        while l.at < len(code):
            op = l.u8()

            # ---------------------------------------------- Ende
            if op == 0x0B:                       # end
                b = stapel.pop()
                if b.art == 'func':
                    break
                if b.art == 'turm':
                    # Das `end` einer Turmebene schliesst keinen
                    # Firn-Block -- es beendet einen FALL. Der Code
                    # dahinter gehoert in den naechsten Zweig.
                    self.turm_ende(b, tiefe, stapel)
                    sp = b.stack_ein + len(b.res)
                    unerreichbar = False
                    continue
                tiefe -= 1
                if b.art in ('block', 'loop'):
                    # Eine `while true` darf nicht von selbst noch
                    # einmal laufen: ein `loop` faellt nach dem letzten
                    # Befehl heraus (nur ein `br` geht zurueck), ein
                    # `block` ist am Ende ohnehin zu Ende. Also
                    # schliesst jede ECHTE Schleife mit `break`.
                    if b.schleife:
                        self.e(tiefe, 'break')
                    self.e(tiefe - 1, '}')
                    if b.schleife:
                        self.nach_block(b, tiefe - 1, stapel)
                else:                            # if
                    self.e(tiefe - 1, '}')
                sp = b.stack_ein + len(b.res)
                unerreichbar = False
                continue

            if op == 0x05:                       # else
                b = stapel[-1]
                b.hat_else = True
                self.e(tiefe - 1, '} else {')
                sp = b.stack_ein
                unerreichbar = False
                continue

            # ------------------------------ der Turm (siehe TIEFE.md)
            #
            # Werden hier mehr als GRENZE Bloecke am Stueck geoeffnet,
            # ist das eine Sprungtabelle in Blockform. Sie wird nicht
            # geschachtelt, sondern als Verteiler erzeugt: eine Ebene
            # statt 276.
            if op == 0x02 and not self.im_turm:
                merk = l.at
                anzahl, danach = turm_messen(code, l.at - 1)
                if anzahl > TURM_GRENZE:
                    sp = self.turm_erzeugen(l, code, anzahl, danach, sp,
                                            stapel, tiefe)
                    tiefe += 1
                    continue
                l.at = merk

            # --------------------------------------------- Bloecke
            if op in (0x02, 0x03, 0x04):
                bt = l.sleb()
                bpar, bres = blocktyp(m, bt)
                sp -= len(bpar)
                self.marke += 1
                b = Block({0x02: 'block', 0x03: 'loop', 0x04: 'if'}[op],
                          tiefe, sp, bres, self.marke)
                b.schleife = (op == 0x03)
                if op == 0x04:
                    sp -= 1
                    self.e(tiefe - 1, 'if %s != 0 {' % self.sv(sp))
                elif op == 0x03:
                    # NUR `loop` braucht wirklich eine Schleife: allein
                    # dorthin kann ein `br` ZURUECKspringen.
                    self.e(tiefe - 1, 'while true {')
                else:
                    # `block` ist KEINE Schleife -- ein `br` daraus
                    # geht immer VORWAERTS ans Ende. Frueher stand hier
                    # ebenfalls `while true`, und genau das hat SQLite
                    # gesprengt: die Verschachtelung erreichte 278
                    # Ebenen, firnc laesst 200 zu. Ein `block` wird
                    # deshalb zu einem EINMAL durchlaufenen `while`,
                    # der nur dann entsteht, wenn wirklich jemand
                    # herausspringt -- sonst gar nichts.
                    # FALLSTRICK, teuer bezahlt: ein nackter Firn-Block
                    # `{ }` schluckt kein `break`. Springt IRGENDWER von
                    # innen ueber diese Ebene hinweg nach aussen, laeuft
                    # sein `break` in die naechste UMGEBENDE Schleife und
                    # ueberspringt den Rest dieses Blocks. Genau daran
                    # ist dateitest.wasm gestorben: `path_open` wurde nie
                    # gerufen, weil ein `br 1` den umgebenden Block mit
                    # verlassen hat.
                    #
                    # Deshalb wird ein `block` NUR dann nackt erzeugt,
                    # wenn aus ihm heraus GAR NICHT gesprungen wird --
                    # weder auf ihn selbst noch an ihm vorbei.
                    b.schleife = self.block_hat_sprung(l.b, l.at)
                    if b.schleife:
                        self.e(tiefe - 1, 'while true {')
                    else:
                        self.e(tiefe - 1, '{')
                sp += len(bpar)
                b.stack_ein = sp - len(bpar)
                stapel.append(b)
                tiefe += 1
                continue

            if unerreichbar:
                # Nach `br`/`return`/`unreachable` bis zum naechsten
                # end/else nur noch ueberspringen -- der Code ist tot,
                # aber die Operanden muessen gelesen werden.
                self.ueberspringen(l, op)
                continue

            sp, unerreichbar = self.befehl(l, op, sp, stapel, tiefe)

        # Rueckgabe der Funktion.
        #
        # `sp` kann hier 0 sein: dann endete der Rumpf mit `br`,
        # `return` oder `unreachable`, und das `end` der Funktion ist
        # gar nicht erreichbar. Firn will trotzdem einen Rueckgabewert
        # sehen -- der Erzeuger haengt ihn hinter der letzten
        # Anweisung an, er wird nie ausgefuehrt.
        if res:
            if sp >= 1:
                self.e(0, 'return %s' % self.sv(sp - 1))
            else:
                self.e(0, 'return 0')

    def nach_block(self, b, tiefe, stapel=None):
        """Direkt hinter einer verlassenen Schleife: trug der Sprung
        eine AEUSSERE Tiefe, dann galt er nicht dieser Ebene -- also
        weiter hinausbrechen. Das kostet einen Vergleich je verlassener
        Ebene, nicht je Befehl.

        `tiefe` ist die Einrueckung DIREKT NACH dem schliessenden `}`.
        Auf Tiefe 0 (unmittelbar im Funktionsrumpf) gibt es keine
        Schleife mehr, aus der man ausbrechen koennte -- dort wird der
        Sprung zum `return`."""
        if not self.br_benutzt:
            return
        # Steht ueberhaupt noch eine Schleife um diese Stelle herum?
        # Nur dann darf hier `break` stehen. Sonst ist der Sprung nur
        # noch als `return` aus der Funktion zu erfuellen -- das ist
        # der Fall, wenn ein `block` (der KEINE Schleife erzeugt) die
        # aeusserste Ebene ist.
        umschliesst = False
        if stapel is not None:
            for x in stapel:
                if x.art == 'loop' or (x.art == 'block' and x.schleife) \
                        or x.art == 'turm':
                    umschliesst = True
                    break
        # WELCHE TIEFE HIER STEHEN MUSS -- der Fehler, der f175 zerlegt
        # hat. Wir stehen DIREKT HINTER dem `}` des gerade verlassenen
        # Blocks `b`, also wieder auf der Ebene, die ihn UMGIBT. Ein
        # Sprung ist genau dann erfuellt, wenn er DIESE umgebende Ebene
        # meinte -- nicht die des verlassenen Blocks.
        #
        # `b.tiefe` ist die Ebene, auf der `b` selbst lag; die Ebene
        # dahinter ist `b.tiefe - 1`. Stand vorher `b.tiefe` da, wurde
        # ein `br 1` (Ziel: die umgebende Ebene) nie als erfuellt
        # erkannt und brach weiter nach aussen aus -- der Rest der
        # Funktion wurde uebersprungen.
        ziel_tiefe = b.tiefe
        self.e(tiefe, 'if br_ziel >= 0 {')
        if not umschliesst:
            self.e(tiefe + 1, 'if br_ziel == %d { br_ziel = -1 } else {'
                   % ziel_tiefe)
            if self.res:
                self.e(tiefe + 2, 'return %s' % self.sv(0))
            else:
                self.e(tiefe + 2, 'return')
            self.e(tiefe + 1, '}')
        else:
            self.e(tiefe + 1,
                   'if br_ziel == %d { br_ziel = -1 } else { break }'
                   % ziel_tiefe)
        self.e(tiefe, '}')

    # ------------------------------------------------- ein Befehl
    def befehl(self, l, op, sp, stapel, tiefe):
        m = self.m
        E = lambda s: self.e(tiefe - 1, s)
        M32 = '4294967295'

        # ---------------------------------------------- Kontrollfluss
        if op == 0x00:                                    # unreachable
            E('wasm_unreachable()')
            return sp, True
        if op == 0x01:                                    # nop
            return sp, False
        if op == 0x0F:                                    # return
            if self.res:
                E('return %s' % self.sv(sp - 1))
            else:
                E('return')
            return sp, True
        if op in (0x0C, 0x0D):                            # br, br_if
            lab = l.uleb()
            bed = None
            if op == 0x0D:
                sp -= 1
                bed = self.sv(sp)
            ziel = stapel[len(stapel) - 1 - lab]
            self.sprung(ziel, stapel, tiefe, bed, sp)
            return sp, (op == 0x0C)
        if op == 0x0E:                                    # br_table
            n = l.uleb()
            ziele = [l.uleb() for _ in range(n)]
            sonst = l.uleb()
            sp -= 1
            wahl = self.sv(sp)
            # KEINE else-if-Kette: sie schachtelt in firncs Parser, und
            # `br_table` hat bei SQLite bis zu 185 Ziele -- zusammen mit
            # dem umgebenden Code reisst das die Grenze von 200 Ebenen.
            # Unabhaengige `if`-Bloecke sind flach. Jeder Zweig endet
            # ohnehin mit `continue`/`break`/`return`, also kann keiner
            # in den naechsten durchfallen.
            for i, lab in enumerate(ziele):
                E('if %s == %d {' % (wahl, i))
                z = stapel[len(stapel) - 1 - lab]
                self.sprung(z, stapel, tiefe + 1, None, sp)
                E('}')
            z = stapel[len(stapel) - 1 - sonst]
            self.sprung(z, stapel, tiefe, None, sp)
            return sp, True

        # ------------------------------------------------------ Rufe
        if op == 0x10:                                    # call
            fi = l.uleb()
            par, res = m.typ_von(fi)
            sp -= len(par)
            args = ', '.join(self.sv(sp + i) for i in range(len(par)))
            ziel = self.rufname(fi)
            if res:
                E('%s = %s(%s)' % (self.sv(sp), ziel, args))
                sp += 1
            else:
                E('%s(%s)' % (ziel, args))
            return sp, False
        if op == 0x11:                                    # call_indirect
            ti = l.uleb()
            l.uleb()
            par, res = m.typen[ti]
            sp -= 1
            idx = self.sv(sp)
            sp -= len(par)
            args = ', '.join(self.sv(sp + i) for i in range(len(par)))
            ruf = 'tab_ruf_%d(%s%s%s)' % (ti, idx, ', ' if args else '', args)
            if res:
                E('%s = %s' % (self.sv(sp), ruf))
                sp += 1
            else:
                E(ruf)
            return sp, False

        # ------------------------------------------------ Parameter
        if op == 0x1A:                                    # drop
            return sp - 1, False
        if op == 0x1B or op == 0x1C:                      # select
            if op == 0x1C:
                for _ in range(l.uleb()):
                    l.u8()
            sp -= 3
            E('if %s == 0 { %s = %s }' % (self.sv(sp + 2), self.sv(sp),
                                          self.sv(sp + 1)))
            return sp + 1, False

        # -------------------------------------------- Lokale/Globale
        if op == 0x20:                                    # local.get
            i = l.uleb()
            E('%s = l%d' % (self.sv(sp), i))
            return sp + 1, False
        if op == 0x21:                                    # local.set
            i = l.uleb()
            E('l%d = %s' % (i, self.sv(sp - 1)))
            return sp - 1, False
        if op == 0x22:                                    # local.tee
            i = l.uleb()
            E('l%d = %s' % (i, self.sv(sp - 1)))
            return sp, False
        if op == 0x23:                                    # global.get
            i = l.uleb()
            E('%s = g%d' % (self.sv(sp), i))
            return sp + 1, False
        if op == 0x24:                                    # global.set
            i = l.uleb()
            E('g%d = %s' % (i, self.sv(sp - 1)))
            return sp - 1, False

        # ------------------------------------------------ Konstanten
        if op == 0x41:                                    # i32.const
            E('%s = %d' % (self.sv(sp), l.sleb() & 0xFFFFFFFF))
            return sp + 1, False
        if op == 0x42:                                    # i64.const
            E('%s = %d' % (self.sv(sp), l.sleb() & 0xFFFFFFFFFFFFFFFF))
            return sp + 1, False
        if op == 0x43:                                    # f32.const
            E('%s = %d' % (self.sv(sp),
                           struct.unpack('<I', struct.pack('<f', l.f32()))[0]))
            return sp + 1, False
        if op == 0x44:                                    # f64.const
            E('%s = %d' % (self.sv(sp),
                           struct.unpack('<Q', struct.pack('<d', l.f64()))[0]))
            return sp + 1, False

        # -------------------------------------------------- Speicher
        if 0x28 <= op <= 0x3E:
            return self.speicher(l, op, sp, tiefe)
        if op == 0x3F:                                    # memory.size
            l.u8()
            E('%s = mem_seiten' % self.sv(sp))
            return sp + 1, False
        if op == 0x40:                                    # memory.grow
            l.u8()
            E('%s = mem_wachsen(%s)' % (self.sv(sp - 1), self.sv(sp - 1)))
            return sp, False

        # ------------------------------------------------ Rechnen
        r = self.zahl(op, sp, tiefe)
        if r is not None:
            return r

        # ------------------------------------------- 0xFC-Gruppe
        if op == 0xFC:
            u = l.uleb()
            if u == 10:                                   # memory.copy
                l.u8()
                l.u8()
                sp -= 3
                E('mem_copy(%s, %s, %s)' % (self.sv(sp), self.sv(sp + 1),
                                            self.sv(sp + 2)))
                return sp, False
            if u == 11:                                   # memory.fill
                l.u8()
                sp -= 3
                E('mem_fill(%s, %s, %s)' % (self.sv(sp), self.sv(sp + 1),
                                            self.sv(sp + 2)))
                return sp, False
            if u in (0, 1, 2, 3):                         # sat-Umwandlungen
                E('%s = %s' % (self.sv(sp - 1), self.sattrunc(u, sp - 1)))
                return sp, False
            raise Fehler('0xFC %d' % u)

        raise Fehler('opcode 0x%02x' % op)

    # ------------------------------------------------------- Sprung
    def sprung(self, ziel, stapel, tiefe, bed, sp):
        """Ein `br` auf eine Blockebene. Liegt das Ziel genau eine
        Ebene hoeher, reicht break/continue; sonst traegt `br_ziel` die
        Tiefe, und jede verlassene Schleife reicht weiter."""
        E = lambda s: self.e(tiefe - 1, s)
        innen = stapel[-1]
        if bed is not None:
            E('if %s != 0 {' % bed)
            tiefe += 1
            E = lambda s: self.e(tiefe - 1, s)
        if ziel.art == 'turm':
            # Sprung in einen Fall des Verteilers: Nummer setzen und
            # die Verteilerschleife neu durchlaufen.
            E('fall%d = %d' % (ziel.turm_marke, ziel.turm_fall))
            E('continue')
        elif ziel.art == 'func':
            if self.res:
                E('return %s' % self.sv(sp - 1))
            else:
                E('return')
        elif ziel is innen and ziel.art == 'loop':
            E('continue')
        elif ziel is innen and ziel.schleife:
            E('break')
        else:
            self.br_benutzt = True
            if ziel.art == 'loop':
                # Ein Sprung an den Anfang einer AEUSSEREN Schleife:
                # dorthin ausbrechen und dort wieder eintreten.
                E('br_ziel = %d' % ziel.tiefe)
            else:
                E('br_ziel = %d' % ziel.tiefe)
            E('break')
        if bed is not None:
            tiefe -= 1
            self.e(tiefe - 1, '}')

    # ----------------------------------------------------- Speicher
    def speicher(self, l, op, sp, tiefe):
        E = lambda s: self.e(tiefe - 1, s)
        l.uleb()                       # align
        off = l.uleb()
        LAD = {
            0x28: ('mem_ld32', 0), 0x29: ('mem_ld64', 0),
            0x2A: ('mem_ld32', 0), 0x2B: ('mem_ld64', 0),
            0x2C: ('mem_ld8s', 32), 0x2D: ('mem_ld8', 0),
            0x2E: ('mem_ld16s', 32), 0x2F: ('mem_ld16', 0),
            0x30: ('mem_ld8s', 64), 0x31: ('mem_ld8', 0),
            0x32: ('mem_ld16s', 64), 0x33: ('mem_ld16', 0),
            0x34: ('mem_ld32s', 64), 0x35: ('mem_ld32', 0),
        }
        SPE = {
            0x36: 'mem_st32', 0x37: 'mem_st64',
            0x38: 'mem_st32', 0x39: 'mem_st64',
            0x3A: 'mem_st8', 0x3B: 'mem_st16',
            0x3C: 'mem_st8', 0x3D: 'mem_st16', 0x3E: 'mem_st32',
        }
        if op in LAD:
            fn, breite = LAD[op]
            adr = self.sv(sp - 1)
            # DIE BREITE ZAEHLT. `i32.load8_s` von 0xFF ist 0xFFFFFFFF
            # (32 Bit), NICHT 0xFFFFFFFFFFFFFFFF -- der Wert liegt in
            # den unteren 32 Bit eines i32. `i64.load8_s` dagegen
            # erweitert auf volle 64 Bit. Wer das gleich behandelt,
            # bekommt bei jedem Vergleich mit einer i32-Konstante ein
            # falsches Ergebnis; die Pruefung mem.wat faengt genau das.
            if breite == 32:
                E('%s = %s(%s +%% %d) & 4294967295'
                  % (self.sv(sp - 1), fn, adr, off))
            else:
                E('%s = %s(%s +%% %d)' % (self.sv(sp - 1), fn, adr, off))
            return sp, False
        fn = SPE[op]
        sp -= 2
        E('%s(%s +%% %d, %s)' % (fn, self.sv(sp), off, self.sv(sp + 1)))
        return sp, False

    def sattrunc(self, u, i):
        s = self.sv(i)
        return {0: 'trunc_sat_i32_f32_s(%s)' % s,
                1: 'trunc_sat_i32_f32_u(%s)' % s,
                2: 'trunc_sat_i32_f64_s(%s)' % s,
                3: 'trunc_sat_i32_f64_u(%s)' % s}[u]

    # ------------------------------------------------------ Rechnen
    #
    # HIER ZAHLT SICH DER FUND AUS. Jedes `+% -% *%` wird von firnc zu
    # EINER Anweisung ohne Ueberlaufpruefung -- der Deuter brauchte
    # dafuer einen Funktionsaufruf (`wadd`) mit Verzweigung.
    #
    # i32 liegt in den unteren 32 Bit einer u64 und wird nach jeder
    # Rechnung mit `& 4294967295` beschnitten. Vorzeichenbehaftete
    # Operationen gehen ueber i64-Umdeutung (`i32s`).
    def zahl(self, op, sp, tiefe):
        E = lambda s: self.e(tiefe - 1, s)
        M = '4294967295'

        def ein(ausdruck):
            E('%s = %s' % (self.sv(sp - 1), ausdruck))
            return sp, False

        def zwei(ausdruck):
            E('%s = %s' % (self.sv(sp - 2), ausdruck))
            return sp - 1, False

        a = self.sv(sp - 2) if sp >= 2 else 's0'
        b = self.sv(sp - 1) if sp >= 1 else 's0'
        x = self.sv(sp - 1) if sp >= 1 else 's0'

        # -------------------------------------------- i32 Vergleiche
        if op == 0x45: return ein('b2i(%s == 0)' % x)
        if op == 0x46: return zwei('b2i(%s == %s)' % (a, b))
        if op == 0x47: return zwei('b2i(%s != %s)' % (a, b))
        if op == 0x48: return zwei('b2i(i32s(%s) < i32s(%s))' % (a, b))
        if op == 0x49: return zwei('b2i(%s < %s)' % (a, b))
        if op == 0x4A: return zwei('b2i(i32s(%s) > i32s(%s))' % (a, b))
        if op == 0x4B: return zwei('b2i(%s > %s)' % (a, b))
        if op == 0x4C: return zwei('b2i(i32s(%s) <= i32s(%s))' % (a, b))
        if op == 0x4D: return zwei('b2i(%s <= %s)' % (a, b))
        if op == 0x4E: return zwei('b2i(i32s(%s) >= i32s(%s))' % (a, b))
        if op == 0x4F: return zwei('b2i(%s >= %s)' % (a, b))
        # -------------------------------------------- i64 Vergleiche
        if op == 0x50: return ein('b2i(%s == 0)' % x)
        if op == 0x51: return zwei('b2i(%s == %s)' % (a, b))
        if op == 0x52: return zwei('b2i(%s != %s)' % (a, b))
        if op == 0x53: return zwei('b2i(i64s(%s) < i64s(%s))' % (a, b))
        if op == 0x54: return zwei('b2i(%s < %s)' % (a, b))
        if op == 0x55: return zwei('b2i(i64s(%s) > i64s(%s))' % (a, b))
        if op == 0x56: return zwei('b2i(%s > %s)' % (a, b))
        if op == 0x57: return zwei('b2i(i64s(%s) <= i64s(%s))' % (a, b))
        if op == 0x58: return zwei('b2i(%s <= %s)' % (a, b))
        if op == 0x59: return zwei('b2i(i64s(%s) >= i64s(%s))' % (a, b))
        if op == 0x5A: return zwei('b2i(%s >= %s)' % (a, b))
        # ------------------------------------------- f32/f64 Vergleiche
        if op == 0x5B: return zwei('b2i(f32v(%s) == f32v(%s))' % (a, b))
        if op == 0x5C: return zwei('b2i(f32v(%s) != f32v(%s))' % (a, b))
        if op == 0x5D: return zwei('b2i(f32v(%s) < f32v(%s))' % (a, b))
        if op == 0x5E: return zwei('b2i(f32v(%s) > f32v(%s))' % (a, b))
        if op == 0x5F: return zwei('b2i(f32v(%s) <= f32v(%s))' % (a, b))
        if op == 0x60: return zwei('b2i(f32v(%s) >= f32v(%s))' % (a, b))
        if op == 0x61: return zwei('b2i(f64v(%s) == f64v(%s))' % (a, b))
        if op == 0x62: return zwei('b2i(f64v(%s) != f64v(%s))' % (a, b))
        if op == 0x63: return zwei('b2i(f64v(%s) < f64v(%s))' % (a, b))
        if op == 0x64: return zwei('b2i(f64v(%s) > f64v(%s))' % (a, b))
        if op == 0x65: return zwei('b2i(f64v(%s) <= f64v(%s))' % (a, b))
        if op == 0x66: return zwei('b2i(f64v(%s) >= f64v(%s))' % (a, b))

        # -------------------------------------------------- i32 Rechnen
        if op == 0x67: return ein('i32_clz(%s)' % x)
        if op == 0x68: return ein('i32_ctz(%s)' % x)
        if op == 0x69: return ein('popcnt(%s & %s)' % (x, M))
        if op == 0x6A: return zwei('(%s +%% %s) & %s' % (a, b, M))
        if op == 0x6B: return zwei('(%s -%% %s) & %s' % (a, b, M))
        if op == 0x6C: return zwei('(%s *%% %s) & %s' % (a, b, M))
        if op == 0x6D: return zwei('i32_div_s(%s, %s)' % (a, b))
        if op == 0x6E: return zwei('i32_div_u(%s, %s)' % (a, b))
        if op == 0x6F: return zwei('i32_rem_s(%s, %s)' % (a, b))
        if op == 0x70: return zwei('i32_rem_u(%s, %s)' % (a, b))
        if op == 0x71: return zwei('%s & %s' % (a, b))
        if op == 0x72: return zwei('%s | %s' % (a, b))
        if op == 0x73: return zwei('%s ^ %s' % (a, b))
        if op == 0x74: return zwei('(%s << ((%s & 31) as u32)) & %s' % (a, b, M))
        if op == 0x75: return zwei('i32_shr_s(%s, %s)' % (a, b))
        if op == 0x76: return zwei('(%s & %s) >> ((%s & 31) as u32)' % (a, M, b))
        if op == 0x77: return zwei('i32_rotl(%s, %s)' % (a, b))
        if op == 0x78: return zwei('i32_rotr(%s, %s)' % (a, b))
        # -------------------------------------------------- i64 Rechnen
        if op == 0x79: return ein('i64_clz(%s)' % x)
        if op == 0x7A: return ein('i64_ctz(%s)' % x)
        if op == 0x7B: return ein('popcnt(%s)' % x)
        if op == 0x7C: return zwei('%s +%% %s' % (a, b))
        if op == 0x7D: return zwei('%s -%% %s' % (a, b))
        if op == 0x7E: return zwei('%s *%% %s' % (a, b))
        if op == 0x7F: return zwei('i64_div_s(%s, %s)' % (a, b))
        if op == 0x80: return zwei('i64_div_u(%s, %s)' % (a, b))
        if op == 0x81: return zwei('i64_rem_s(%s, %s)' % (a, b))
        if op == 0x82: return zwei('i64_rem_u(%s, %s)' % (a, b))
        if op == 0x83: return zwei('%s & %s' % (a, b))
        if op == 0x84: return zwei('%s | %s' % (a, b))
        if op == 0x85: return zwei('%s ^ %s' % (a, b))
        if op == 0x86: return zwei('%s << ((%s & 63) as u32)' % (a, b))
        if op == 0x87: return zwei('i64_shr_s(%s, %s)' % (a, b))
        if op == 0x88: return zwei('%s >> ((%s & 63) as u32)' % (a, b))
        if op == 0x89: return zwei('i64_rotl(%s, %s)' % (a, b))
        if op == 0x8A: return zwei('i64_rotr(%s, %s)' % (a, b))
        # ------------------------------------------------ f32 Rechnen
        if op == 0x8B: return ein('f32b(f32_abs(f32v(%s)))' % x)
        if op == 0x8C: return ein('f32b(0.0 - f32v(%s))' % x)
        if op == 0x8D: return ein('f32b(f32_ceil(f32v(%s)))' % x)
        if op == 0x8E: return ein('f32b(f32_floor(f32v(%s)))' % x)
        if op == 0x8F: return ein('f32b(f32_trunc(f32v(%s)))' % x)
        if op == 0x90: return ein('f32b(f32_nearest(f32v(%s)))' % x)
        if op == 0x91: return ein('f32b(f32_sqrt(f32v(%s)))' % x)
        if op == 0x92: return zwei('f32b(f32v(%s) + f32v(%s))' % (a, b))
        if op == 0x93: return zwei('f32b(f32v(%s) - f32v(%s))' % (a, b))
        if op == 0x94: return zwei('f32b(f32v(%s) * f32v(%s))' % (a, b))
        if op == 0x95: return zwei('f32b(f32v(%s) / f32v(%s))' % (a, b))
        if op == 0x96: return zwei('f32b(f32_min(f32v(%s), f32v(%s)))' % (a, b))
        if op == 0x97: return zwei('f32b(f32_max(f32v(%s), f32v(%s)))' % (a, b))
        if op == 0x98: return zwei('f32_copysign(%s, %s)' % (a, b))
        # ------------------------------------------------ f64 Rechnen
        if op == 0x99: return ein('f64b(f64_abs(f64v(%s)))' % x)
        if op == 0x9A: return ein('f64b(0.0 - f64v(%s))' % x)
        if op == 0x9B: return ein('f64b(f64_ceil(f64v(%s)))' % x)
        if op == 0x9C: return ein('f64b(f64_floor(f64v(%s)))' % x)
        if op == 0x9D: return ein('f64b(f64_trunc(f64v(%s)))' % x)
        if op == 0x9E: return ein('f64b(f64_nearest(f64v(%s)))' % x)
        if op == 0x9F: return ein('f64b(f64_sqrt(f64v(%s)))' % x)
        if op == 0xA0: return zwei('f64b(f64v(%s) + f64v(%s))' % (a, b))
        if op == 0xA1: return zwei('f64b(f64v(%s) - f64v(%s))' % (a, b))
        if op == 0xA2: return zwei('f64b(f64v(%s) * f64v(%s))' % (a, b))
        if op == 0xA3: return zwei('f64b(f64v(%s) / f64v(%s))' % (a, b))
        if op == 0xA4: return zwei('f64b(f64_min(f64v(%s), f64v(%s)))' % (a, b))
        if op == 0xA5: return zwei('f64b(f64_max(f64v(%s), f64v(%s)))' % (a, b))
        if op == 0xA6: return zwei('f64_copysign(%s, %s)' % (a, b))
        # ---------------------------------------------- Umwandlungen
        if op == 0xA7: return ein('%s & 4294967295' % x)                  # i32.wrap_i64
        if op == 0xA8: return ein('i32_trunc_f32_s(%s)' % x)
        if op == 0xA9: return ein('i32_trunc_f32_u(%s)' % x)
        if op == 0xAA: return ein('i32_trunc_f64_s(%s)' % x)
        if op == 0xAB: return ein('i32_trunc_f64_u(%s)' % x)
        if op == 0xAC: return ein('i32s(%s) as u64' % x)                  # i64.extend_i32_s
        if op == 0xAD: return ein('%s & 4294967295' % x)                  # i64.extend_i32_u
        if op == 0xAE: return ein('i64_trunc_f32_s(%s)' % x)
        if op == 0xAF: return ein('i64_trunc_f32_u(%s)' % x)
        if op == 0xB0: return ein('i64_trunc_f64_s(%s)' % x)
        if op == 0xB1: return ein('i64_trunc_f64_u(%s)' % x)
        if op == 0xB2: return ein('f32b(i32s(%s) as f32)' % x)            # f32.convert_i32_s
        if op == 0xB3: return ein('f32b((%s & 4294967295) as f32)' % x)
        if op == 0xB4: return ein('f32b(i64s(%s) as f32)' % x)
        if op == 0xB5: return ein('f32b(u64_zu_f32(%s))' % x)
        if op == 0xB6: return ein('f32b(f64v(%s) as f32)' % x)            # f32.demote_f64
        if op == 0xB7: return ein('f64b(i32s(%s) as f64)' % x)
        if op == 0xB8: return ein('f64b((%s & 4294967295) as f64)' % x)
        if op == 0xB9: return ein('f64b(i64s(%s) as f64)' % x)
        if op == 0xBA: return ein('f64b(u64_zu_f64(%s))' % x)
        if op == 0xBB: return ein('f64b(f32v(%s) as f64)' % x)            # f64.promote_f32
        if op == 0xBC: return ein('%s & 4294967295' % x)                  # i32.reinterpret_f32
        if op == 0xBD: return ein('%s' % x)                               # i64.reinterpret_f64
        if op == 0xBE: return ein('%s & 4294967295' % x)                  # f32.reinterpret_i32
        if op == 0xBF: return ein('%s' % x)                               # f64.reinterpret_i64
        # ------------------------------------ Vorzeichen-Erweiterungen
        if op == 0xC0: return ein('sext8_32(%s)' % x)
        if op == 0xC1: return ein('sext16_32(%s)' % x)
        if op == 0xC2: return ein('sext8_64(%s)' % x)
        if op == 0xC3: return ein('sext16_64(%s)' % x)
        if op == 0xC4: return ein('sext32_64(%s)' % x)
        return None

    # ---------------------------------------- der Turm als Verteiler
    #
    # Aus
    #     block block block ... (n mal)  RUMPF  end end end ...
    # wird
    #     var fall = 0
    #     while true {
    #         if fall == 0 { RUMPF }            // br k setzt fall = n-k
    #         else if fall == 1 { ...hinter dem innersten end... }
    #         ...
    #         break
    #     }
    #
    # Der Kontrollfluss ist derselbe, die Tiefe ist 1 statt n.
    def turm_erzeugen(self, l, code, anzahl, danach, sp, stapel, tiefe):
        self.br_benutzt = True
        self.im_turm = True
        self.turm_faelle = anzahl
        marke = self.marke + 1
        self.marke += 1
        E = lambda t, x: self.e(t, x)
        E(tiefe - 1, '// %d Bloecke am Stueck -> Verteiler (TIEFE.md)' % anzahl)
        E(tiefe - 1, 'var fall%d: u64 = 0' % marke)
        E(tiefe - 1, 'while true {')
        # KEINE else-if-Kette: die schachtelt in firncs Parser und
        # sprengt bei 276 Faellen dieselbe Grenze von 200 noch einmal
        # (gemessen). Stattdessen unabhaengige `if`-Bloecke, jeder mit
        # `break` am Ende -- das ist flach und traegt auch 300 Faelle.
        E(tiefe, 'if fall%d == 0 {' % marke)
        # Die n Blockebenen werden als Block-Objekte gefuehrt, damit
        # `br k` weiterhin die richtige Ebene findet -- sie erzeugen nur
        # keine Einrueckung mehr.
        for k in range(anzahl):
            b = Block('turm', tiefe + k, sp, [], marke)
            b.schleife = False
            b.turm_marke = marke
            b.turm_fall = anzahl - k        # br k -> fall = anzahl-k
            stapel.append(b)
        l.at = danach
        return sp

    def turm_ende(self, b, tiefe, stapel):
        """Das `end` einer Turmebene: der bisherige Fall ist zu Ende,
        der naechste faengt an. Jeder Fall ist ein EIGENES `if` mit
        `break` -- keine else-if-Kette (die schachtelt im Parser)."""
        self.e(tiefe + 1, 'break')
        self.e(tiefe, '}')
        self.e(tiefe, 'if fall%d == %d {' % (b.turm_marke, b.turm_fall))
        # War das die letzte Ebene, schliesst der Verteiler.
        noch = [x for x in stapel if x.art == 'turm'
                and x.turm_marke == b.turm_marke]
        if not noch:
            self.e(tiefe + 1, 'break')
            self.e(tiefe, '}')
            self.e(tiefe, 'break')
            self.e(tiefe - 1, '}')
            self.im_turm = False

    def block_braucht_schleife(self, b, at):
        return _block_braucht_schleife(b, at)

    def block_hat_sprung(self, b, at):
        return _block_hat_sprung(b, at)

    # ------------------------------------- toten Code ueberspringen
    #
    # Nach `br`/`return`/`unreachable` ist der Rest des Blocks nicht
    # erreichbar. Er muss trotzdem GELESEN werden, damit die Operanden
    # richtig ueberlaufen werden -- ausgeben muss man ihn nicht.
    def ueberspringen(self, l, op):
        if op in (0x02, 0x03, 0x04):
            l.sleb()
        elif op in (0x0C, 0x0D, 0x10, 0x20, 0x21, 0x22, 0x23, 0x24):
            l.uleb()
        elif op == 0x0E:
            for _ in range(l.uleb()):
                l.uleb()
            l.uleb()
        elif op == 0x11:
            l.uleb()
            l.uleb()
        elif op == 0x41 or op == 0x42:
            l.sleb()
        elif op == 0x43:
            l.f32()
        elif op == 0x44:
            l.f64()
        elif 0x28 <= op <= 0x3E:
            l.uleb()
            l.uleb()
        elif op in (0x3F, 0x40):
            l.u8()
        elif op == 0x1C:
            for _ in range(l.uleb()):
                l.u8()
        elif op == 0xFC:
            u = l.uleb()
            if u == 10:
                l.u8()
                l.u8()
            elif u == 11:
                l.u8()

    # ------------------------------------------------- Name eines Rufs
    def rufname(self, fi):
        m = self.m
        if fi < m.n_import_funcs:
            mod, nam, art, _ = m.importe[fi]
            return 'imp_%s' % sicher(nam)
        return self.fname(fi)


def sicher(n):
    return ''.join(c if (c.isalnum() or c == '_') else '_' for c in n)


# ====================================================================
#                     Das ganze Erzeugnis
# ====================================================================

def erzeugen(m, wasi_txt, laufzeit_txt, name):
    e = Erzeuger(m, {})
    o = []
    o.append('// SPDX-License-Identifier: GPL-2.0-only')
    o.append('// ERZEUGT von tools/wasm2firn/wasm2firn.py aus %s' % name)
    o.append('// NICHT VON HAND AENDERN -- RUNDE SCHLEUSE-2.')
    o.append('//')
    o.append('// Aus %d WASM-Funktionen sind %d Firn-Funktionen geworden.'
             % (len(m.funktypen), len(m.code)))
    o.append('// Der WASM-Stapel liegt nicht mehr im Speicher, sondern in')
    o.append('// lokalen Variablen -- das ist der ganze Trick.')
    o.append('')
    o.append(laufzeit_txt)
    o.append('')
    o.append('// ============================ WASI, aus dem Deuter gezogen')
    o.append('static mut wasi_argc: usize = 0')
    o.append('static mut wasi_argv_von: usize = 0')
    o.append('static mut wasi_start: u64 = 0')
    o.append('static mut wasi_spur: bool = false')
    o.append('')
    o.append('// `unreachable` ist in WASM eine FALLE, kein stiller Ausgang.')
    o.append('fn zahl_aus2(x: u64) {')
    o.append('    var b: rt.Buf = rt.buf_new()')
    o.append('    rt.buf_push_dec_u64(&b, x)')
    o.append('    rt.write_everything(1, b.ptr, b.len)')
    o.append('    rt.buf_free(&b)')
    o.append('}')
    o.append('')
    o.append('fn wasm_unreachable() {')
    o.append('    io.print("wasm: unreachable erreicht\\n")')
    o.append('    rt.finish(132)')
    o.append('}')
    o.append('')
    o.append('fn mem_ok(at: u64, n: usize) -> bool {')
    o.append('    if at > mem_bytes() || at +% (n as u64) > mem_bytes() {')
    o.append('        return false')
    o.append('    }')
    o.append('    return true')
    o.append('}')
    o.append('')
    o.append(wasi_txt)

    # ------------------------------------------------------ Globale
    o.append('// ================================== Globale des Moduls')
    for i, (t, ver, w, imp) in enumerate(m.globals):
        o.append('static mut g%d: u64 = %d' % (i, w))
    o.append('')

    # ------------------------------------------------------ Importe
    o.append('// ================================= Die Importe (WASI)')
    gesehen = set()
    for fi, (mod, nam, art, ti) in enumerate(m.importe):
        if art != 'func':
            continue
        nm = 'imp_%s' % sicher(nam)
        if nm in gesehen:
            continue
        gesehen.add(nm)
        par, res = m.typen[ti]
        args = ', '.join('a%d: u64' % i for i in range(len(par)))
        o.append('fn %s(%s)%s {' % (nm, args, ' -> u64' if res else ''))
        ruf = wasi_ruf(nam, len(par))
        if ruf is None:
            o.append('    // in WASI preview1 nicht (oder noch nicht) da')
            if res:
                o.append('    return %d' % 52)
            o.append('}')
        else:
            if nam == 'proc_exit':
                o.append('    rt.finish(a0 as i64)')
                o.append('}')
            elif res:
                # SPUR: mit gesetztem wasi_spur nennt jeder abschlaegige
                # Ruf sich selbst -- derselbe Dienst, den `wasm -s` im
                # Deuter leistet. Ohne das sucht man bei einem Modul mit
                # zwanzig Importen im Dunkeln.
                o.append('    let r: u64 = %s' % ruf)
                o.append('    if wasi_spur && r != 0 {')
                o.append('        io.print("wasi: %s -> errno=")' % nam)
                o.append('        zahl_aus2(r)')
                o.append('        io.print("\\n")')
                o.append('    }')
                o.append('    return r')
                o.append('}')
            else:
                o.append('    %s' % ruf)
                o.append('}')
        o.append('')

    # ------------------------------------------- Funktionen
    o.append('// =========================== Die uebersetzten Funktionen')
    for fi in range(m.n_import_funcs, len(m.funktypen)):
        e.out = []
        e.funktion(fi)
        o += e.out

    # ------------------------------------------- Tabelle
    o += tabelle_erzeugen(m)

    # ------------------------------------------- Start
    o += start_erzeugen(m, name)
    return '\n'.join(o)


# Welcher WASI-Ruf gehoert zu welchem Namen. Die Reihenfolge der
# Argumente ist die der Spezifikation.
def wasi_ruf(nam, npar):
    T = {
        'fd_write':              'w_fd_write(a0, a1, a2 as usize, a3)',
        'fd_read':               'w_fd_read(a0, a1, a2 as usize, a3)',
        'fd_seek':               'w_fd_seek(a0, a1, a2, a3)',
        'fd_close':              'w_fd_close(a0)',
        'fd_fdstat_get':         'w_fd_fdstat_get(a0, a1)',
        'fd_prestat_get':        'w_fd_prestat_get(a0, a1)',
        'fd_prestat_dir_name':   'w_fd_prestat_dir_name(a0, a1, a2 as usize)',
        'fd_filestat_get':       'w_fd_filestat_get(a0, a1)',
        'fd_tell':               'w_fd_seek(a0, 0, 1, a1)',
        'path_open':             'w_path_open(a2, a3 as usize, a4, a5, a8)',
        'path_filestat_get':     'w_path_filestat_get(a2, a3 as usize, a4)',
        'path_unlink_file':      'w_path_unlink(a1, a2 as usize)',
        'path_create_directory': 'w_path_mkdir(a1, a2 as usize)',
        'path_remove_directory': 'w_path_rmdir(a1, a2 as usize)',
        'args_sizes_get':        'w_args_sizes_get(a0, a1)',
        'args_get':              'w_args_get(a0, a1)',
        'environ_sizes_get':     'w_environ_sizes_get(a0, a1)',
        'environ_get':           '0',
        'clock_time_get':        'w_clock_time_get(a0, a2)',
        'clock_res_get':         'wasi_clock_res(a1)',
        'random_get':            'w_random_get(a0, a1 as usize)',
        'proc_exit':             'rt.finish(a0 as i64)',
        'sched_yield':           '0',
        'fd_sync':               '0',
        'fd_datasync':           '0',
        'fd_fdstat_set_flags':   '0',
        'fd_filestat_set_size':  '0',
        'poll_oneoff':           '0',
    }
    return T.get(nam)


# ------------------------------------------------------- call_indirect
#
# WASM ruft indirekt ueber eine TABELLE: `call_indirect` nimmt einen
# Index und einen erwarteten Typ. Firn hat keine Funktionszeiger in
# Stufe 0, also wird je Typ eine Verteilerfunktion erzeugt -- eine
# Kette von Vergleichen ueber die Eintraege, die diesen Typ haben.
# Das ist der Preis dafuer, dass es ohne Funktionszeiger geht; er faellt
# nur bei indirekten Rufen an, nicht bei gewoehnlichen.
def tabelle_erzeugen(m):
    o = ['// ============================ Die Tabelle (call_indirect)']
    # index -> funcidx
    tab = {}
    for off, funcs in m.elemente:
        for k, f in enumerate(funcs):
            tab[off + k] = f
    gebraucht = set()
    for ci, (lok, code) in enumerate(m.code):
        pass
    # Welche Typen werden indirekt gerufen? Der Erzeuger sammelt das
    # beim Uebersetzen; einfacher ist: fuer jeden Typ, der in der
    # Tabelle vorkommt, eine Verteilerfunktion bauen.
    typen = {}
    for idx, f in tab.items():
        ti = m.funktypen[f]
        typen.setdefault(ti, []).append((idx, f))
    for ti, eintraege in sorted(typen.items()):
        par, res = m.typen[ti]
        args = ', '.join('a%d: u64' % i for i in range(len(par)))
        o.append('fn tab_ruf_%d(idx: u64%s%s)%s {' % (
            ti, ', ' if args else '', args, ' -> u64' if res else ''))
        ruf_args = ', '.join('a%d' % i for i in range(len(par)))
        for idx, f in sorted(eintraege):
            if f < m.n_import_funcs:
                mod, nam, art, mti = m.importe[f]
                ziel = 'imp_%s' % sicher(nam)
            else:
                ziel = 'f%d' % f
            if res:
                o.append('    if idx == %d { return %s(%s) }' % (idx, ziel, ruf_args))
            else:
                o.append('    if idx == %d {' % idx)
                o.append('        %s(%s)' % (ziel, ruf_args))
                o.append('        return')
                o.append('    }')
        o.append('    tab_falle(idx)')
        if res:
            o.append('    return 0')
        o.append('}')
        o.append('')
    o.append('fn tab_falle(idx: u64) {')
    o.append('    io.print("wasm: call_indirect auf einen leeren Platz\\n")')
    o.append('    rt.finish(133)')
    o.append('}')
    o.append('')
    return o


# ------------------------------------------------------------ Start
def start_erzeugen(m, name):
    o = ['// ==================================== Der Programmstart']
    o.append('fn wasi_clock_res(ret: u64) -> u64 {')
    o.append('    mem_st64(ret, 1000)')
    o.append('    return 0')
    o.append('}')
    o.append('')
    # Datensegmente als eine einzige Zeichenkette: Firn kann lange
    # Byte-Literale, und der Startcode kopiert sie in den Speicher.
    # DIE DATENSEGMENTE.
    #
    # Sie sind BELIEBIGE OKTETTE -- der Datenbereich eines Rust- oder
    # C-Programms enthaelt Zeiger, Sprungtabellen und Zahlen, kein
    # Text. Ein Firn-Zeichenkettenliteral verlangt aber gueltiges
    # UTF-8 ("\xNN above 0x7F does not yield valid UTF-8"), also
    # scheidet der bequeme Weg aus.
    #
    # Stattdessen: ein `const`-Feld aus u8. Das ist genau das, was ein
    # Datensegment ist, und firnc legt es unveraendert in den
    # Datenbereich des Programms.
    for k, (off, b) in enumerate(m.data):
        if not b:
            continue
        o.append('static mut DATA%d: [u8; %d] = [' % (k, len(b)))
        for z in range(0, len(b), 32):
            stueck = ', '.join(str(c) for c in b[z:z + 32])
            o.append('    %s,' % stueck)
        o.append(']')
        o.append('')
    o.append('fn data_legen() {')
    for k, (off, b) in enumerate(m.data):
        if not b:
            continue
        o.append('    data_kopieren(%d, (&DATA%d[0]) as u64, %d)' % (off, k, len(b)))
    o.append('}')
    o.append('')
    o.append('fn data_kopieren(ziel: u64, p: u64, n: u64) {')
    o.append('    var i: u64 = 0')
    o.append('    while i < n {')
    o.append('        rt.st8(mem_p, (ziel + i) as usize, rt.ld8(p, i as usize))')
    o.append('        i = i + 1')
    o.append('    }')
    o.append('}')
    o.append('')
    o.append('fn main(start: u64) -> i32 {')
    o.append('    wasi_start = start')
    o.append('    wasi_argc = rt.arg_count(start)')
    # DIE ARGUMENTE. Anders als beim Deuter ist das erzeugte Programm
    # SELBST das Modul -- argv[0] ist also schon der Modulpfad, und die
    # Argumente fangen bei 0 an. (Im Deuter musste `argv_von` erst auf
    # den Modulpfad gesetzt werden, weil davor noch `wasm` und `-s`
    # standen; siehe Fallstrick 7 in STATUS-SCHLEUSE.)
    o.append('    wasi_argv_von = 0')
    o.append('    // WASMSPUR=1 in der Umgebung gibt es hier nicht --')
    o.append('    // die Spur haengt an einem eigenen Schalter, der dem')
    o.append('    // Gast NICHT als Argument untergeschoben wird.')
    o.append('    if wasi_argc > 1 {')
    o.append('        let a1: u64 = rt.arg_ptr(start, wasi_argc - 1)')
    o.append('        if rt.c_length(a1) == 6 && rt.ld8(a1, 0) == 45 as u8')
    o.append('            && rt.ld8(a1, 1) == 45 as u8 {')
    o.append('            wasi_spur = true')
    o.append('            wasi_argc = wasi_argc - 1')
    o.append('        }')
    o.append('    }')
    o.append('    // Der lineare Speicher: gleich auf die Hoechstgroesse,')
    o.append('    // damit memory.grow nur eine Grenze vorrueckt.')
    o.append('    mem_max = %d' % (m.mem_max if m.mem_max else max(m.mem_min * 4, m.mem_min + 256)))
    o.append('    mem_seiten = %d' % m.mem_min)
    o.append('    mem_p = rt.heap_alloc((mem_max * 65536) as usize)')
    o.append('    if mem_p == 0 {')
    o.append('        io.print("wasm: kein Speicher fuer den linearen Speicher\\n")')
    o.append('        return 1')
    o.append('    }')
    o.append('    rt.mem_set(mem_p, 0, (mem_max * 65536) as usize)')
    o.append('    data_legen()')
    if m.start is not None:
        o.append('    f%d()' % m.start)
    ziel = m.exporte.get('_start')
    if ziel and ziel[0] == 0:
        par, res = m.typ_von(ziel[1])
        ruf = 'f%d()' % ziel[1]
        if res:
            o.append('    let rc: u64 = %s' % ruf)
            o.append('    return rc as i32')
        else:
            o.append('    %s' % ruf)
            o.append('    return 0')
    else:
        o.append('    io.print("wasm: das Modul hat kein _start\\n")')
        o.append('    return 1')
    o.append('}')
    return o


def firn_bytes(b):
    r = []
    for c in b:
        if c == 0x22:
            r.append('\\"')
        elif c == 0x5C:
            r.append('\\\\')
        elif 0x20 <= c < 0x7F:
            r.append(chr(c))
        else:
            r.append('\\x%02x' % c)
    return ''.join(r)


# ------------------------------------------------------------- Haupt
def main():
    import argparse
    ap = argparse.ArgumentParser(
        description='uebersetzt ein .wasm nach Firn-Quelltext (RUNDE SCHLEUSE-2)')
    ap.add_argument('wasm')
    ap.add_argument('-o', '--out', required=True)
    ap.add_argument('--wasm-fi', default='kernel/app/wasm.fi',
                    help='woraus die WASI-Schicht gezogen wird')
    ap.add_argument('--laufzeit', default='tools/wasm2firn/laufzeit.fi.in')
    a = ap.parse_args()

    import wasi_ziehen
    m = Modul(open(a.wasm, 'rb').read())
    wasi = wasi_ziehen.ziehen(a.wasm_fi)
    lz = open(a.laufzeit).read()
    # der Kopf der Laufzeit traegt die imports -- die kommen ganz nach oben
    txt = erzeugen(m, wasi, lz, a.wasm)
    open(a.out, 'w').write(txt)
    n = txt.count('\n')
    sys.stderr.write('%s -> %s: %d WASM-Funktionen, %d Zeilen Firn\n'
                     % (a.wasm, a.out, len(m.code), n))


if __name__ == '__main__':
    main()
