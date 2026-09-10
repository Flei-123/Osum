# SPDX-License-Identifier: GPL-2.0-only
#
# tools/wasm2firn/flach.py -- RUNDE SCHLEUSE-3
#
# EIN flacher Verteiler je Funktion, statt geschachtelter Bloecke.
#
# ====================================================================
# WARUM
# ====================================================================
#
# firncs `escape`-Durchgang ist EXPONENTIELL in der Schachtelungstiefe
# (gemessen in FIRN-ESCAPE-TIEFE.md: Faktor ~2 je Ebene). SQLite
# erreichte mit der geschachtelten Erzeugung 25 Ebenen; der Bau lief
# ueber 1,5 Stunden und war nicht fertig.
#
# Die Loesung ist die, die jeder WASM-nach-Quelltext-Uebersetzer ohne
# `goto` nimmt (Emscriptens Relooper, wasm2c ohne goto): der ganze
# Funktionsrumpf wird EIN Zustandsautomat.
#
#     var fall: u64 = 0
#     while true {
#         match fall {
#             0 => { ...Stueck 0...  fall = 3  continue }
#             1 => { ...Stueck 1...  break }
#             ...
#             _ => { break }
#         }
#     }
#
# Tiefe: `while` (1) + `match` (2) + Arm (3). FERTIG. Egal wie tief das
# WASM schachtelt.
#
# ====================================================================
# DIE UEBERSETZUNG
# ====================================================================
#
# WASM-Kontrollfluss ist bereits strukturiert -- das macht es einfach.
# Jede Blockebene bekommt ZWEI Marken:
#
#   * `beginn` -- die Nummer des Stuecks, das ihren Rumpf anfaengt
#   * `ende`   -- die Nummer des Stuecks, das HINTER ihrem `end` steht
#
# Damit ist `br k` in beiden Faellen dasselbe: eine Zuweisung.
#
#   * `br k` auf einen `block` -> `fall = <ende von k>`
#   * `br k` auf eine `loop`   -> `fall = <beginn von k>`
#
# Genau der Unterschied, an dem der geschachtelte Erzeuger in RUNDE
# SCHLEUSE-2 gestorben ist (Fehler 5) -- hier ist er eine Zeile und
# nicht zu verwechseln.
#
# `if`/`else` braucht keinen Sonderfall: die Bedingung waehlt zwischen
# zwei Stueck-Nummern.
#
# ====================================================================
# DER STAPEL
# ====================================================================
#
# Der WASM-Operandenstapel liegt wie bisher in Variablen `s0..sN`, und
# die statische Stapelhoehe ist an jeder Stelle bekannt. Weil die
# Stuecke nur ueber ihre Nummer verbunden sind, muessen die
# Stapelvariablen ueber einen Stueckwechsel HINWEG gelten -- sie sind
# ohnehin Funktionsvariablen, also stimmt das von selbst.
#
# Ein Sprung, der einen Wert mitnimmt (`br` aus einem Block mit
# Ergebnistyp), muss den Wert an die Stelle legen, an der ihn das
# Zielstueck erwartet. Das ist die einzige Stelle, an der wirklich
# umkopiert wird.

from wasm2firn import (Leser, blocktyp, Fehler)


class Ebene:
    """Eine WASM-Blockebene im flachen Verteiler."""

    def __init__(self, art, beginn, ende, sp_ein, res):
        self.art = art          # 'block' | 'loop' | 'if' | 'func'
        self.beginn = beginn    # Stueck-Nummer des Rumpfanfangs
        self.ende = ende        # Stueck-Nummer HINTER dem `end`
        self.sp_ein = sp_ein    # Stapelhoehe beim Betreten
        self.res = res          # Ergebnistypen
        self.hat_else = False
        self.else_stueck = None
        self.sp_else = 0


class FlachErzeuger:
    """Uebersetzt EINE WASM-Funktion in einen flachen Verteiler.

    Nutzt den bestehenden `Erzeuger` fuer alles, was NICHT
    Kontrollfluss ist (Rechnen, Speicher, Rufe) -- dort aendert sich
    nichts, und der Code ist erprobt.
    """

    def __init__(self, erz):
        self.erz = erz          # der bestehende Erzeuger
        self.m = erz.m

    # ---------------------------------------------------------------
    def rumpf(self, code, par, res):
        erz = self.erz
        m = self.m
        self.res = res

        # Die Stuecke: Nummer -> Liste von Zeilen.
        self.stuecke = {}
        self.n_stueck = 0
        self.jetzt = self.neues_stueck()

        # Stuecke, die tatsaechlich angesprungen werden. Alles andere
        # faellt am Ende weg -- sonst stuenden Hunderte leerer Arme da.
        self.gebraucht = set()

        # Die aeusserste Ebene ist die Funktion: ein `br` darauf ist
        # ein `return`.
        ende_funk = self.reservieren()
        self.stapel = [Ebene('func', 0, ende_funk, 0, res)]

        l = Leser(code)
        sp = 0
        unerreichbar = False

        while l.at < len(code):
            op = l.u8()

            # ------------------------------------------------- end
            if op == 0x0B:
                b = self.stapel.pop()
                if b.art == 'func':
                    # Faellt der Rumpf unten heraus, geht es beim
                    # Ausgang weiter -- NICHT einfach `break`, sonst
                    # verliert die Funktion ihren Rueckgabewert.
                    if not unerreichbar:
                        self.spring(b.ende)
                    break
                # REIHENFOLGE ZAEHLT: erst den gerade laufenden Zweig
                # abschliessen, DANN den fehlenden else-Zweig
                # nachtragen. Andersherum landet der Abschluss des
                # then-Zweigs im else-Stueck -- und der then-Zweig
                # faellt aus dem Verteiler heraus (Fehler in `if2`,
                # Fall $d).
                if not unerreichbar:
                    self.spring(b.ende)
                # Ein `if` OHNE else: der fehlende Zweig springt
                # unmittelbar hinter das `end`.
                if b.art == 'if' and not b.hat_else:
                    self.setz_stueck(b.else_stueck)
                    self.spring(b.ende)
                self.setz_stueck(b.ende)
                sp = b.sp_ein + len(b.res)
                unerreichbar = False
                continue

            # ------------------------------------------------ else
            if op == 0x05:
                b = self.stapel[-1]
                b.hat_else = True
                if not unerreichbar:
                    self.spring(b.ende)
                self.setz_stueck(b.else_stueck)
                sp = b.sp_else
                unerreichbar = False
                continue

            # ---------------------------------------------- Bloecke
            if op in (0x02, 0x03, 0x04):
                bt = l.sleb()
                bpar, bres = blocktyp(m, bt)
                sp -= len(bpar)
                ende = self.reservieren()
                if op == 0x04:                      # if
                    sp -= 1
                    bed = erz.sv(sp)
                    dann = self.reservieren()
                    sonst = self.reservieren()
                    self.z('if %s != 0 {' % bed)
                    self.z('    fall = %d' % dann)
                    self.z('} else {')
                    self.z('    fall = %d' % sonst)
                    self.z('}')
                    self.z('continue')
                    self.gebraucht.add(dann)
                    self.gebraucht.add(sonst)
                    e = Ebene('if', dann, ende, sp, bres)
                    e.else_stueck = sonst
                    e.sp_else = sp + len(bpar)
                    self.setz_stueck(dann)
                elif op == 0x03:                    # loop
                    beginn = self.reservieren()
                    self.spring(beginn)
                    e = Ebene('loop', beginn, ende, sp, bres)
                    self.setz_stueck(beginn)
                else:                               # block
                    beginn = self.reservieren()
                    self.spring(beginn)
                    e = Ebene('block', beginn, ende, sp, bres)
                    self.setz_stueck(beginn)
                sp += len(bpar)
                self.stapel.append(e)
                unerreichbar = False
                continue

            if unerreichbar:
                erz.ueberspringen(l, op)
                continue

            # ------------------------------------- Kontrollfluss-Ops
            if op == 0x0F:                                    # return
                self.rueckgabe(sp)
                unerreichbar = True
                continue

            if op in (0x0C, 0x0D):                            # br/br_if
                lab = l.uleb()
                bed = None
                if op == 0x0D:
                    sp -= 1
                    bed = erz.sv(sp)
                ziel = self.stapel[len(self.stapel) - 1 - lab]
                if bed is None:
                    self.br(ziel, sp)
                    unerreichbar = True
                else:
                    self.br_bedingt(ziel, sp, bed)
                continue

            if op == 0x0E:                                    # br_table
                n = l.uleb()
                ziele = [l.uleb() for _ in range(n)]
                sonst = l.uleb()
                sp -= 1
                wahl = erz.sv(sp)
                self.br_tabelle(wahl, ziele, sonst, sp)
                unerreichbar = True
                continue

            # ------------- alles Uebrige: der erprobte Befehlsuebersetzer
            sp, unerreichbar = self.gewoehnlich(l, op, sp)

        # Der Ausgang der Funktion.
        self.setz_stueck(ende_funk)
        self.rueckgabe(sp)
        return self.ausgeben()

    # ================================================== Stueckverwaltung
    def reservieren(self):
        self.n_stueck += 1
        return self.n_stueck

    def neues_stueck(self):
        self.stuecke[0] = []
        return 0

    def setz_stueck(self, nr):
        if nr not in self.stuecke:
            self.stuecke[nr] = []
        self.jetzt = nr

    def z(self, s):
        """Eine Zeile in das laufende Stueck."""
        self.stuecke[self.jetzt].append(s)

    def spring(self, nr):
        self.gebraucht.add(nr)
        self.z('fall = %d' % nr)
        self.z('continue')

    # ================================================== Kontrollfluss
    def zielnummer(self, ziel):
        """Wohin ein `br` auf diese Ebene fuehrt.

        DIE Kernunterscheidung von WASM: auf einen `block` ans ENDE,
        auf eine `loop` an den ANFANG."""
        if ziel.art == 'loop':
            return ziel.beginn
        return ziel.ende

    def wert_schieben(self, ziel, sp):
        """Nimmt ein Sprung einen Wert mit, muss er dort liegen, wo ihn
        das Zielstueck erwartet."""
        if ziel.art == 'func':
            return
        if not ziel.res:
            return
        if ziel.art == 'loop':
            return                       # `loop` erwartet Parameter, keine Ergebnisse
        n = len(ziel.res)
        for i in range(n):
            von = sp - n + i
            nach = ziel.sp_ein + i
            if von != nach:
                self.z('%s = %s' % (self.erz.sv(nach), self.erz.sv(von)))

    def br(self, ziel, sp):
        if ziel.art == 'func':
            self.rueckgabe(sp)
            return
        self.wert_schieben(ziel, sp)
        self.spring(self.zielnummer(ziel))

    def br_bedingt(self, ziel, sp, bed):
        weiter = self.reservieren()
        self.gebraucht.add(weiter)
        if ziel.art == 'func':
            self.z('if %s != 0 {' % bed)
            self.rueckgabe_eingerueckt(sp, '    ')
            self.z('}')
            return
        nr = self.zielnummer(ziel)
        self.gebraucht.add(nr)
        # Muss ein Wert mitwandern, geht das nur im Zweig.
        schiebe = []
        if ziel.res and ziel.art != 'loop':
            n = len(ziel.res)
            for i in range(n):
                von = sp - n + i
                nach = ziel.sp_ein + i
                if von != nach:
                    schiebe.append('%s = %s'
                                   % (self.erz.sv(nach), self.erz.sv(von)))
        self.z('if %s != 0 {' % bed)
        for s in schiebe:
            self.z('    ' + s)
        self.z('    fall = %d' % nr)
        self.z('} else {')
        self.z('    fall = %d' % weiter)
        self.z('}')
        self.z('continue')
        self.setz_stueck(weiter)

    def br_tabelle(self, wahl, ziele, sonst, sp):
        """`br_table` wird zur Fallnummer-Berechnung -- KEINE
        Schachtelung, nur unabhaengige `if`.

        Das ist die Stelle, an der der flache Verteiler am meisten
        gewinnt: `yy_reduce` in SQLite hat 276 Ziele."""
        # Erst alle Werte einsammeln, dann EINE Kette flacher `if`.
        for i, lab in enumerate(ziele):
            ziel = self.stapel[len(self.stapel) - 1 - lab]
            self.z('if %s == %d {' % (wahl, i))
            if ziel.art == 'func':
                self.rueckgabe_eingerueckt(sp, '    ')
            else:
                if ziel.res and ziel.art != 'loop':
                    n = len(ziel.res)
                    for k in range(n):
                        von = sp - n + k
                        nach = ziel.sp_ein + k
                        if von != nach:
                            self.z('    %s = %s'
                                   % (self.erz.sv(nach), self.erz.sv(von)))
                nr = self.zielnummer(ziel)
                self.gebraucht.add(nr)
                self.z('    fall = %d' % nr)
                self.z('    continue')
            self.z('}')
        ziel = self.stapel[len(self.stapel) - 1 - sonst]
        self.br(ziel, sp)

    def rueckgabe(self, sp):
        if self.res:
            if sp >= 1:
                self.z('return %s' % self.erz.sv(sp - 1))
            else:
                self.z('return 0')
        else:
            self.z('return')

    def rueckgabe_eingerueckt(self, sp, vor):
        if self.res:
            if sp >= 1:
                self.z('%sreturn %s' % (vor, self.erz.sv(sp - 1)))
            else:
                self.z('%sreturn 0' % vor)
        else:
            self.z('%sreturn' % vor)

    # ============================== gewoehnliche Befehle weiterreichen
    def gewoehnlich(self, l, op, sp):
        """Alles, was kein Kontrollfluss ist, uebersetzt der bestehende
        `Erzeuger`. Er schreibt ueber `e(tiefe, s)` -- also faengt der
        Flacherzeuger diese Zeilen kurz ab und legt sie ins Stueck."""
        erz = self.erz
        gesammelt = []
        alt_e = erz.e
        erz.e = lambda tiefe, s: gesammelt.append((tiefe, s))
        try:
            sp2, unerr = erz.befehl(l, op, sp, self.stapel_ersatz(), 1)
        finally:
            erz.e = alt_e
        grund = None
        for tiefe, s in gesammelt:
            if grund is None:
                grund = tiefe
            self.z('    ' * max(0, tiefe - grund) + s)
        return sp2, unerr

    def stapel_ersatz(self):
        """`befehl` fasst den Stapel nur bei `br`/`br_table` an -- und
        die behandelt der Flacherzeuger selbst. Fuer alles Uebrige
        reicht die Liste unveraendert."""
        return self.stapel

    # ====================================================== Ausgeben
    def ausgeben(self):
        """Der fertige Verteiler.

        Ein Stueck, das niemand anspringt, wird an sein Vorgaengerstueck
        angehaengt statt als eigener `match`-Arm ausgegeben. Sonst
        haette `f97` statt 31 000 Zeilen ueber 60 000."""
        o = []
        o.append(' var fall: u64 = 0')
        o.append(' while true {')
        o.append('  match fall {')
        for nr in sorted(self.stuecke):
            zeilen = self.stuecke[nr]
            if nr != 0 and not zeilen and nr not in self.gebraucht:
                continue
            o.append('   %d => {' % nr)
            for z in zeilen:
                o.append('    ' + z)
            # Ein Stueck, das nicht selbst springt, faellt ans Ende der
            # Funktion. Das kann nur beim Ausgang vorkommen.
            if not zeilen or not (zeilen[-1].startswith('continue')
                                  or zeilen[-1].startswith('return')
                                  or zeilen[-1].lstrip().startswith('return')):
                o.append('    break')
            o.append('   }')
        o.append('   _ => {')
        o.append('    break')
        o.append('   }')
        o.append('  }')
        o.append(' }')
        return o
