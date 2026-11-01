
from wasm2firn import (Leser, blocktyp, Error)


class Ebene:

    def __init__(self, art, begin, ende, sp_ein, res):
        self.art = art
        self.begin = begin
        self.ende = ende
        self.sp_ein = sp_ein
        self.res = res
        self.hat_else = False
        self.else_chunk = None
        self.sp_else = 0


class FlachErzeuger:

    def __init__(self, erz):
        self.erz = erz
        self.m = erz.m

    def body(self, code, par, res):
        erz = self.erz
        m = self.m
        self.res = res

        self.stuecke = {}
        self.n_chunk = 0
        self.now = self.neues_chunk()

        self.gebraucht = set()

        ende_funk = self.reservieren()
        self.stack = [Ebene('func', 0, ende_funk, 0, res)]

        l = Leser(code)
        sp = 0
        unerreichbar = False

        while l.at < len(code):
            op = l.u8()

            if op == 0x0B:
                b = self.stack.pop()
                if b.art == 'func':
                    if not unerreichbar:
                        self.spring(b.ende)
                    break
                if not unerreichbar:
                    self.spring(b.ende)
                if b.art == 'if' and not b.hat_else:
                    self.set_chunk(b.else_chunk)
                    self.spring(b.ende)
                self.set_chunk(b.ende)
                sp = b.sp_ein + len(b.res)
                unerreichbar = False
                continue

            if op == 0x05:
                b = self.stack[-1]
                b.hat_else = True
                if not unerreichbar:
                    self.spring(b.ende)
                self.set_chunk(b.else_chunk)
                sp = b.sp_else
                unerreichbar = False
                continue

            if op in (0x02, 0x03, 0x04):
                bt = l.sleb()
                bpar, bres = blocktyp(m, bt)
                sp -= len(bpar)
                ende = self.reservieren()
                if op == 0x04:
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
                    e.else_chunk = sonst
                    e.sp_else = sp + len(bpar)
                    self.set_chunk(dann)
                elif op == 0x03:
                    begin = self.reservieren()
                    self.spring(begin)
                    e = Ebene('loop', begin, ende, sp, bres)
                    self.set_chunk(begin)
                else:
                    begin = self.reservieren()
                    self.spring(begin)
                    e = Ebene('block', begin, ende, sp, bres)
                    self.set_chunk(begin)
                sp += len(bpar)
                self.stack.append(e)
                unerreichbar = False
                continue

            if unerreichbar:
                erz.ueberspringen(l, op)
                continue

            if op == 0x0F:
                self.rueckgabe(sp)
                unerreichbar = True
                continue

            if op in (0x0C, 0x0D):
                lab = l.uleb()
                bed = None
                if op == 0x0D:
                    sp -= 1
                    bed = erz.sv(sp)
                target = self.stack[len(self.stack) - 1 - lab]
                if bed is None:
                    self.br(target, sp)
                    unerreichbar = True
                else:
                    self.br_bedingt(target, sp, bed)
                continue

            if op == 0x0E:
                n = l.uleb()
                ziele = [l.uleb() for _ in range(n)]
                sonst = l.uleb()
                sp -= 1
                wahl = erz.sv(sp)
                self.br_table(wahl, ziele, sonst, sp)
                unerreichbar = True
                continue

            sp, unerreichbar = self.gewoehnlich(l, op, sp)

        self.set_chunk(ende_funk)
        self.rueckgabe(sp)
        return self.ausgeben()

    def reservieren(self):
        self.n_chunk += 1
        return self.n_chunk

    def neues_chunk(self):
        self.stuecke[0] = []
        return 0

    def set_chunk(self, nr):
        if nr not in self.stuecke:
            self.stuecke[nr] = []
        self.now = nr

    def z(self, s):
        self.stuecke[self.now].append(s)

    def spring(self, nr):
        self.gebraucht.add(nr)
        self.z('fall = %d' % nr)
        self.z('continue')

    def zielnummer(self, target):
        if target.art == 'loop':
            return target.begin
        return target.ende

    def value_pan(self, target, sp):
        if target.art == 'func':
            return
        if not target.res:
            return
        if target.art == 'loop':
            return
        n = len(target.res)
        for i in range(n):
            von = sp - n + i
            nach = target.sp_ein + i
            if von != nach:
                self.z('%s = %s' % (self.erz.sv(nach), self.erz.sv(von)))

    def br(self, target, sp):
        if target.art == 'func':
            self.rueckgabe(sp)
            return
        self.value_pan(target, sp)
        self.spring(self.zielnummer(target))

    def br_bedingt(self, target, sp, bed):
        next_ = self.reservieren()
        self.gebraucht.add(next_)
        if target.art == 'func':
            self.z('if %s != 0 {' % bed)
            self.rueckgabe_eingerueckt(sp, '    ')
            self.z('}')
            return
        nr = self.zielnummer(target)
        self.gebraucht.add(nr)
        schiebe = []
        if target.res and target.art != 'loop':
            n = len(target.res)
            for i in range(n):
                von = sp - n + i
                nach = target.sp_ein + i
                if von != nach:
                    schiebe.append('%s = %s'
                                   % (self.erz.sv(nach), self.erz.sv(von)))
        self.z('if %s != 0 {' % bed)
        for s in schiebe:
            self.z('    ' + s)
        self.z('    fall = %d' % nr)
        self.z('} else {')
        self.z('    fall = %d' % next_)
        self.z('}')
        self.z('continue')
        self.set_chunk(next_)

    def br_table(self, wahl, ziele, sonst, sp):
        for i, lab in enumerate(ziele):
            target = self.stack[len(self.stack) - 1 - lab]
            self.z('if %s == %d {' % (wahl, i))
            if target.art == 'func':
                self.rueckgabe_eingerueckt(sp, '    ')
            else:
                if target.res and target.art != 'loop':
                    n = len(target.res)
                    for k in range(n):
                        von = sp - n + k
                        nach = target.sp_ein + k
                        if von != nach:
                            self.z('    %s = %s'
                                   % (self.erz.sv(nach), self.erz.sv(von)))
                nr = self.zielnummer(target)
                self.gebraucht.add(nr)
                self.z('    fall = %d' % nr)
                self.z('    continue')
            self.z('}')
        target = self.stack[len(self.stack) - 1 - sonst]
        self.br(target, sp)

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

    def gewoehnlich(self, l, op, sp):
        erz = self.erz
        gesammelt = []
        alt_e = erz.e
        erz.e = lambda tiefe, s: gesammelt.append((tiefe, s))
        try:
            sp2, unerr = erz.cmd(l, op, sp, self.stack_fallback(), 1)
        finally:
            erz.e = alt_e
        reason = None
        for tiefe, s in gesammelt:
            if reason is None:
                reason = tiefe
            self.z('    ' * max(0, tiefe - reason) + s)
        return sp2, unerr

    def stack_fallback(self):
        return self.stack

    def ausgeben(self):
        o = []
        o.append(' var fall: u64 = 0')
        o.append(' while true {')
        o.append('  match fall {')
        for nr in sorted(self.stuecke):
            lines = self.stuecke[nr]
            if nr != 0 and not lines and nr not in self.gebraucht:
                continue
            o.append('   %d => {' % nr)
            for z in lines:
                o.append('    ' + z)
            if not lines or not (lines[-1].startswith('continue')
                                  or lines[-1].startswith('return')
                                  or lines[-1].lstrip().startswith('return')):
                o.append('    break')
            o.append('   }')
        o.append('   _ => {')
        o.append('    break')
        o.append('   }')
        o.append('  }')
        o.append(' }')
        return o
