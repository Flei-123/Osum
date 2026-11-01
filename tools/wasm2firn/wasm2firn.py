#!/usr/bin/env python3

import struct
import sys


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

FLACH = True

TURM_LIMIT = 8

TIEFE_DECKEL = 20


def typname(t):
    return {I32: 'i32', I64: 'i64', F32: 'f32', F64: 'f64'}.get(t, '?')


FIRNTYP = 'u64'


class Module:
    def __init__(self, b):
        self.b = b
        self.typen = []
        self.importe = []
        self.funktypen = []
        self.table_min = 0
        self.elemente = []
        self.mem_min = 0
        self.mem_max = 0
        self.globals = []
        self.exporte = {}
        self.start = None
        self.code = []
        self.data = []
        self.n_import_funcs = 0
        self.names = {}
        self.read_2()

    def read_2(self):
        b = self.b
        if b[0:4] != b'\x00asm':
            raise SystemExit('kein WASM-Modul')
        at = 8
        while at < len(b):
            l = Leser(b, at)
            sid = l.u8()
            size = l.uleb()
            ende = l.at + size
            self.sektion(sid, Leser(b, l.at), ende)
            at = ende

    def sektion(self, sid, l, ende):
        if sid == 1:
            for _ in range(l.uleb()):
                l.u8()
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
                self.table_min = max(self.table_min, mn)
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
                size = l.uleb()
                bis = l.at + size
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
                                self.names[idx] = l.name()
                        l.at = bis
            except Exception:
                pass

    def grenzen(self, l):
        f = l.u8()
        mn = l.uleb()
        mx = l.uleb() if f & 1 else 0
        return mn, mx

    def konstausdruck(self, l):
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



def blocktyp(m, bt):
    if bt == -64:
        return [], []
    if bt in (-1, -2, -3, -4):
        return [], [{-1: I32, -2: I64, -3: F32, -4: F64}[bt]]
    return m.typen[bt]


class Block:
    def __init__(self, art, tiefe, stack_ein, res, marke):
        self.art = art
        self.tiefe = tiefe
        self.stack_ein = stack_ein
        self.res = res
        self.marke = marke
        self.hat_else = False
        self.loop = (art == 'loop')
        self.turm_brand = None
        self.turm_fall = 0
        self.turm_loop = False



def _block_braucht_loop(b, at):
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


TURM_KENNUNG = 1000000


def _in_dispatch_body(stack, marke):
    for x in reversed(stack):
        if x.art == 'turm':
            return x.turm_brand == marke
        if x.art == 'loop' or (x.art == 'block' and x.loop):
            return False
    return False


def _dispatch_without_loop(stack):
    for x in reversed(stack):
        if x.art == 'turm':
            return x.turm_brand
        if x.art == 'loop' or (x.art == 'block' and x.loop):
            return None
    return None


def turm_messen(code, at):
    l = Leser(code, at)
    arten = []
    while l.at < len(code):
        remember = l.at
        op = l.u8()
        if op not in (0x02, 0x03):
            l.at = remember
            break
        bt = l.sleb()
        if bt != -64:
            l.at = remember
            break
        arten.append(op == 0x03)
    return len(arten), l.at, arten


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


class Error(Exception):
    pass


class Erzeuger:
    def __init__(self, m, opt):
        self.indirekte_typen = set()
        self.m = m
        self.opt = opt
        self.out = []
        self.unbekannt = {}

    def w(self, s=''):
        self.out.append(s)

    def fname(self, fi):
        return 'f%d' % fi

    def func(self, fi):
        m = self.m
        ci = fi - m.n_import_funcs
        lokdef, code = m.code[ci]
        par, res = m.typ_von(fi)

        local_typen = list(par)
        for anz, t in lokdef:
            local_typen += [t] * anz
        self.local_typen = local_typen
        self.nlok = len(local_typen)
        self.res = res
        self.fi = fi

        header = 'fn %s(%s)%s {' % (
            self.fname(fi),
            ', '.join('p%d: u64' % i for i in range(len(par))),
            ' -> u64' if res else '')
        self.w(header)

        for i in range(len(par)):
            self.w('    var l%d: u64 = p%d' % (i, i))
        for i in range(len(par), self.nlok):
            self.w('    var l%d: u64 = 0' % i)

        self.koerper = []
        self.maxstack = 0
        self.br_benutzt = False
        self.im_turm = False
        self.turm_faelle = 0
        try:
            if FLACH:
                import flach
                fe = flach.FlachErzeuger(self)
                self.koerper = fe.body(code, par, res)
            else:
                self.body(code, par, res)
        except Error:
            raise
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
        self.koerper.append(' ' + ' ' * tiefe + s)

    def sv(self, i):
        if i + 1 > self.maxstack:
            self.maxstack = i + 1
        return 's%d' % i

    def body(self, code, par, res):
        m = self.m
        l = Leser(code)
        sp = 0
        stack = [Block('func', 0, 0, res, 0)]
        self.marke = 0
        tiefe = 1
        unerreichbar = False

        while l.at < len(code):
            op = l.u8()

            if op == 0x0B:
                b = stack.pop()
                if b.art == 'func':
                    break
                if b.art == 'turm':
                    self.turm_ende(b, tiefe, stack)
                    sp = b.stack_ein + len(b.res)
                    unerreichbar = False
                    continue
                tiefe -= 1
                if b.art in ('block', 'loop'):
                    if b.loop:
                        self.e(tiefe, 'break')
                    self.e(tiefe - 1, '}')
                    if b.loop:
                        self.nach_block(b, tiefe - 1, stack)
                else:
                    self.e(tiefe - 1, '}')
                sp = b.stack_ein + len(b.res)
                unerreichbar = False
                continue

            if op == 0x05:
                b = stack[-1]
                b.hat_else = True
                self.e(tiefe - 1, '} else {')
                sp = b.stack_ein
                unerreichbar = False
                continue

            if op in (0x02, 0x03):
                remember = l.at
                count_2, danach, arten = turm_messen(code, l.at - 1)
                if count_2 > TURM_LIMIT or (count_2 >= 3 and tiefe >= TIEFE_DECKEL):
                    sp = self.turm_erzeugen(l, code, count_2, danach, sp,
                                            stack, tiefe, arten)
                    tiefe += 1
                    continue
                l.at = remember

            if op in (0x02, 0x03, 0x04):
                bt = l.sleb()
                bpar, bres = blocktyp(m, bt)
                sp -= len(bpar)
                self.marke += 1
                b = Block({0x02: 'block', 0x03: 'loop', 0x04: 'if'}[op],
                          tiefe, sp, bres, self.marke)
                b.loop = (op == 0x03)
                if op == 0x04:
                    sp -= 1
                    self.e(tiefe - 1, 'if %s != 0 {' % self.sv(sp))
                elif op == 0x03:
                    self.e(tiefe - 1, 'while true {')
                else:
                    b.loop = self.block_hat_sprung(l.b, l.at)
                    if b.loop:
                        self.e(tiefe - 1, 'while true {')
                    else:
                        self.e(tiefe - 1, '{')
                sp += len(bpar)
                b.stack_ein = sp - len(bpar)
                stack.append(b)
                tiefe += 1
                continue

            if unerreichbar:
                self.ueberspringen(l, op)
                continue

            sp, unerreichbar = self.cmd(l, op, sp, stack, tiefe)

        if res:
            if sp >= 1:
                self.e(0, 'return %s' % self.sv(sp - 1))
            else:
                self.e(0, 'return 0')

    def nach_block(self, b, tiefe, stack=None):
        if not self.br_benutzt:
            return
        umschliesst = False
        if stack is not None:
            for x in stack:
                if x.art == 'loop' or (x.art == 'block' and x.loop) \
                        or x.art == 'turm':
                    umschliesst = True
                    break
        target_tiefe = b.tiefe
        if b.art == 'loop':
            target_tiefe = -2
        self.e(tiefe, 'if br_ziel >= 0 {')
        if not umschliesst:
            self.e(tiefe + 1, 'if br_ziel == %d { br_ziel = -1 } else {'
                   % target_tiefe)
            if self.res:
                self.e(tiefe + 2, 'return %s' % self.sv(0))
            else:
                self.e(tiefe + 2, 'return')
            self.e(tiefe + 1, '}')
        else:
            umg = stack[-1] if stack else None
            if umg is not None and umg.art == 'loop':
                self.e(tiefe + 1, 'if br_ziel == %d {' % target_tiefe)
                self.e(tiefe + 2, 'br_ziel = -1')
                self.e(tiefe + 1, '} else if br_ziel == %d {' % umg.tiefe)
                self.e(tiefe + 2, 'br_ziel = -1')
                self.e(tiefe + 2, 'continue')
                self.e(tiefe + 1, '} else {')
                self.e(tiefe + 2, 'break')
                self.e(tiefe + 1, '}')
                self.e(tiefe, '}')
                return
            m = _dispatch_without_loop(stack) if stack is not None else None
            if m is not None:
                self.e(tiefe + 1, 'if br_ziel == %d {' % target_tiefe)
                self.e(tiefe + 2, 'br_ziel = -1')
                self.e(tiefe + 1, '} else if br_ziel == %d {'
                       % (TURM_KENNUNG + m))
                self.e(tiefe + 2, 'br_ziel = -1')
                self.e(tiefe + 2, 'continue')
                self.e(tiefe + 1, '} else {')
                self.e(tiefe + 2, 'break')
                self.e(tiefe + 1, '}')
            else:
                self.e(tiefe + 1,
                       'if br_ziel == %d { br_ziel = -1 } else { break }'
                       % target_tiefe)
        self.e(tiefe, '}')

    def cmd(self, l, op, sp, stack, tiefe):
        m = self.m
        E = lambda s: self.e(tiefe - 1, s)
        M32 = '4294967295'

        if op == 0x00:
            E('wasm_unreachable()')
            return sp, True
        if op == 0x01:
            return sp, False
        if op == 0x0F:
            if self.res:
                E('return %s' % self.sv(sp - 1))
            else:
                E('return')
            return sp, True
        if op in (0x0C, 0x0D):
            lab = l.uleb()
            bed = None
            if op == 0x0D:
                sp -= 1
                bed = self.sv(sp)
            target = stack[len(stack) - 1 - lab]
            self.sprung(target, stack, tiefe, bed, sp)
            return sp, (op == 0x0C)
        if op == 0x0E:
            n = l.uleb()
            ziele = [l.uleb() for _ in range(n)]
            sonst = l.uleb()
            sp -= 1
            wahl = self.sv(sp)
            for i, lab in enumerate(ziele):
                E('if %s == %d {' % (wahl, i))
                z = stack[len(stack) - 1 - lab]
                self.sprung(z, stack, tiefe + 1, None, sp)
                E('}')
            z = stack[len(stack) - 1 - sonst]
            self.sprung(z, stack, tiefe, None, sp)
            return sp, True

        if op == 0x10:
            fi = l.uleb()
            par, res = m.typ_von(fi)
            sp -= len(par)
            args = ', '.join(self.sv(sp + i) for i in range(len(par)))
            target = self.rufname(fi)
            if res:
                E('%s = %s(%s)' % (self.sv(sp), target, args))
                sp += 1
            else:
                E('%s(%s)' % (target, args))
            return sp, False
        if op == 0x11:
            ti = l.uleb()
            l.uleb()
            par, res = m.typen[ti]
            sp -= 1
            idx = self.sv(sp)
            sp -= len(par)
            args = ', '.join(self.sv(sp + i) for i in range(len(par)))
            self.indirekte_typen.add(ti)
            ruf = 'tab_ruf_%d(%s%s%s)' % (ti, idx, ', ' if args else '', args)
            if res:
                E('%s = %s' % (self.sv(sp), ruf))
                sp += 1
            else:
                E(ruf)
            return sp, False

        if op == 0x1A:
            return sp - 1, False
        if op == 0x1B or op == 0x1C:
            if op == 0x1C:
                for _ in range(l.uleb()):
                    l.u8()
            sp -= 3
            E('if %s == 0 { %s = %s }' % (self.sv(sp + 2), self.sv(sp),
                                          self.sv(sp + 1)))
            return sp + 1, False

        if op == 0x20:
            i = l.uleb()
            E('%s = l%d' % (self.sv(sp), i))
            return sp + 1, False
        if op == 0x21:
            i = l.uleb()
            E('l%d = %s' % (i, self.sv(sp - 1)))
            return sp - 1, False
        if op == 0x22:
            i = l.uleb()
            E('l%d = %s' % (i, self.sv(sp - 1)))
            return sp, False
        if op == 0x23:
            i = l.uleb()
            E('%s = g%d' % (self.sv(sp), i))
            return sp + 1, False
        if op == 0x24:
            i = l.uleb()
            E('g%d = %s' % (i, self.sv(sp - 1)))
            return sp - 1, False

        if op == 0x41:
            E('%s = %d' % (self.sv(sp), l.sleb() & 0xFFFFFFFF))
            return sp + 1, False
        if op == 0x42:
            E('%s = %d' % (self.sv(sp), l.sleb() & 0xFFFFFFFFFFFFFFFF))
            return sp + 1, False
        if op == 0x43:
            E('%s = %d' % (self.sv(sp),
                           struct.unpack('<I', struct.pack('<f', l.f32()))[0]))
            return sp + 1, False
        if op == 0x44:
            E('%s = %d' % (self.sv(sp),
                           struct.unpack('<Q', struct.pack('<d', l.f64()))[0]))
            return sp + 1, False

        if 0x28 <= op <= 0x3E:
            return self.speicher(l, op, sp, tiefe)
        if op == 0x3F:
            l.u8()
            E('%s = mem_seiten' % self.sv(sp))
            return sp + 1, False
        if op == 0x40:
            l.u8()
            E('%s = mem_wachsen(%s)' % (self.sv(sp - 1), self.sv(sp - 1)))
            return sp, False

        r = self.num(op, sp, tiefe)
        if r is not None:
            return r

        if op == 0xFC:
            u = l.uleb()
            if u == 10:
                l.u8()
                l.u8()
                sp -= 3
                E('mem_copy(%s, %s, %s)' % (self.sv(sp), self.sv(sp + 1),
                                            self.sv(sp + 2)))
                return sp, False
            if u == 11:
                l.u8()
                sp -= 3
                E('mem_fill(%s, %s, %s)' % (self.sv(sp), self.sv(sp + 1),
                                            self.sv(sp + 2)))
                return sp, False
            if u in (0, 1, 2, 3):
                E('%s = %s' % (self.sv(sp - 1), self.sattrunc(u, sp - 1)))
                return sp, False
            raise Error('0xFC %d' % u)

        raise Error('opcode 0x%02x' % op)

    def sprung(self, target, stack, tiefe, bed, sp):
        E = lambda s: self.e(tiefe - 1, s)
        innen = stack[-1]
        if bed is not None:
            E('if %s != 0 {' % bed)
            tiefe += 1
            E = lambda s: self.e(tiefe - 1, s)
        if target.art == 'turm':
            E('fall%d = %d' % (target.turm_brand,
                               0 if target.turm_loop else target.turm_fall))
            if _in_dispatch_body(stack, target.turm_brand):
                E('continue')
            else:
                self.br_benutzt = True
                E('br_ziel = %d' % (TURM_KENNUNG + target.turm_brand))
                E('break')
        elif target.art == 'func':
            if self.res:
                E('return %s' % self.sv(sp - 1))
            else:
                E('return')
        elif target is innen and target.art == 'loop':
            E('continue')
        elif target is innen and target.loop:
            E('break')
        else:
            self.br_benutzt = True
            if target.art == 'loop':
                E('br_ziel = %d' % target.tiefe)
            else:
                E('br_ziel = %d' % target.tiefe)
            E('break')
        if bed is not None:
            tiefe -= 1
            self.e(tiefe - 1, '}')

    def speicher(self, l, op, sp, tiefe):
        E = lambda s: self.e(tiefe - 1, s)
        l.uleb()
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

    def num(self, op, sp, tiefe):
        E = lambda s: self.e(tiefe - 1, s)
        M = '4294967295'

        def ein(ausdruck):
            E('%s = %s' % (self.sv(sp - 1), ausdruck))
            return sp, False

        def two(ausdruck):
            E('%s = %s' % (self.sv(sp - 2), ausdruck))
            return sp - 1, False

        a = self.sv(sp - 2) if sp >= 2 else 's0'
        b = self.sv(sp - 1) if sp >= 1 else 's0'
        x = self.sv(sp - 1) if sp >= 1 else 's0'

        if op == 0x45: return ein('b2i(%s == 0)' % x)
        if op == 0x46: return two('b2i(%s == %s)' % (a, b))
        if op == 0x47: return two('b2i(%s != %s)' % (a, b))
        if op == 0x48: return two('b2i(i32s(%s) < i32s(%s))' % (a, b))
        if op == 0x49: return two('b2i(%s < %s)' % (a, b))
        if op == 0x4A: return two('b2i(i32s(%s) > i32s(%s))' % (a, b))
        if op == 0x4B: return two('b2i(%s > %s)' % (a, b))
        if op == 0x4C: return two('b2i(i32s(%s) <= i32s(%s))' % (a, b))
        if op == 0x4D: return two('b2i(%s <= %s)' % (a, b))
        if op == 0x4E: return two('b2i(i32s(%s) >= i32s(%s))' % (a, b))
        if op == 0x4F: return two('b2i(%s >= %s)' % (a, b))
        if op == 0x50: return ein('b2i(%s == 0)' % x)
        if op == 0x51: return two('b2i(%s == %s)' % (a, b))
        if op == 0x52: return two('b2i(%s != %s)' % (a, b))
        if op == 0x53: return two('b2i(i64s(%s) < i64s(%s))' % (a, b))
        if op == 0x54: return two('b2i(%s < %s)' % (a, b))
        if op == 0x55: return two('b2i(i64s(%s) > i64s(%s))' % (a, b))
        if op == 0x56: return two('b2i(%s > %s)' % (a, b))
        if op == 0x57: return two('b2i(i64s(%s) <= i64s(%s))' % (a, b))
        if op == 0x58: return two('b2i(%s <= %s)' % (a, b))
        if op == 0x59: return two('b2i(i64s(%s) >= i64s(%s))' % (a, b))
        if op == 0x5A: return two('b2i(%s >= %s)' % (a, b))
        if op == 0x5B: return two('b2i(f32v(%s) == f32v(%s))' % (a, b))
        if op == 0x5C: return two('b2i(f32v(%s) != f32v(%s))' % (a, b))
        if op == 0x5D: return two('b2i(f32v(%s) < f32v(%s))' % (a, b))
        if op == 0x5E: return two('b2i(f32v(%s) > f32v(%s))' % (a, b))
        if op == 0x5F: return two('b2i(f32v(%s) <= f32v(%s))' % (a, b))
        if op == 0x60: return two('b2i(f32v(%s) >= f32v(%s))' % (a, b))
        if op == 0x61: return two('b2i(f64v(%s) == f64v(%s))' % (a, b))
        if op == 0x62: return two('b2i(f64v(%s) != f64v(%s))' % (a, b))
        if op == 0x63: return two('b2i(f64v(%s) < f64v(%s))' % (a, b))
        if op == 0x64: return two('b2i(f64v(%s) > f64v(%s))' % (a, b))
        if op == 0x65: return two('b2i(f64v(%s) <= f64v(%s))' % (a, b))
        if op == 0x66: return two('b2i(f64v(%s) >= f64v(%s))' % (a, b))

        if op == 0x67: return ein('i32_clz(%s)' % x)
        if op == 0x68: return ein('i32_ctz(%s)' % x)
        if op == 0x69: return ein('popcnt(%s & %s)' % (x, M))
        if op == 0x6A: return two('(%s +%% %s) & %s' % (a, b, M))
        if op == 0x6B: return two('(%s -%% %s) & %s' % (a, b, M))
        if op == 0x6C: return two('(%s *%% %s) & %s' % (a, b, M))
        if op == 0x6D: return two('i32_div_s(%s, %s)' % (a, b))
        if op == 0x6E: return two('i32_div_u(%s, %s)' % (a, b))
        if op == 0x6F: return two('i32_rem_s(%s, %s)' % (a, b))
        if op == 0x70: return two('i32_rem_u(%s, %s)' % (a, b))
        if op == 0x71: return two('%s & %s' % (a, b))
        if op == 0x72: return two('%s | %s' % (a, b))
        if op == 0x73: return two('%s ^ %s' % (a, b))
        if op == 0x74: return two('(%s << ((%s & 31) as u32)) & %s' % (a, b, M))
        if op == 0x75: return two('i32_shr_s(%s, %s)' % (a, b))
        if op == 0x76: return two('(%s & %s) >> ((%s & 31) as u32)' % (a, M, b))
        if op == 0x77: return two('i32_rotl(%s, %s)' % (a, b))
        if op == 0x78: return two('i32_rotr(%s, %s)' % (a, b))
        if op == 0x79: return ein('i64_clz(%s)' % x)
        if op == 0x7A: return ein('i64_ctz(%s)' % x)
        if op == 0x7B: return ein('popcnt(%s)' % x)
        if op == 0x7C: return two('%s +%% %s' % (a, b))
        if op == 0x7D: return two('%s -%% %s' % (a, b))
        if op == 0x7E: return two('%s *%% %s' % (a, b))
        if op == 0x7F: return two('i64_div_s(%s, %s)' % (a, b))
        if op == 0x80: return two('i64_div_u(%s, %s)' % (a, b))
        if op == 0x81: return two('i64_rem_s(%s, %s)' % (a, b))
        if op == 0x82: return two('i64_rem_u(%s, %s)' % (a, b))
        if op == 0x83: return two('%s & %s' % (a, b))
        if op == 0x84: return two('%s | %s' % (a, b))
        if op == 0x85: return two('%s ^ %s' % (a, b))
        if op == 0x86: return two('%s << ((%s & 63) as u32)' % (a, b))
        if op == 0x87: return two('i64_shr_s(%s, %s)' % (a, b))
        if op == 0x88: return two('%s >> ((%s & 63) as u32)' % (a, b))
        if op == 0x89: return two('i64_rotl(%s, %s)' % (a, b))
        if op == 0x8A: return two('i64_rotr(%s, %s)' % (a, b))
        if op == 0x8B: return ein('f32b(f32_abs(f32v(%s)))' % x)
        if op == 0x8C: return ein('f32b(0.0 - f32v(%s))' % x)
        if op == 0x8D: return ein('f32b(f32_ceil(f32v(%s)))' % x)
        if op == 0x8E: return ein('f32b(f32_floor(f32v(%s)))' % x)
        if op == 0x8F: return ein('f32b(f32_trunc(f32v(%s)))' % x)
        if op == 0x90: return ein('f32b(f32_nearest(f32v(%s)))' % x)
        if op == 0x91: return ein('f32b(f32_sqrt(f32v(%s)))' % x)
        if op == 0x92: return two('f32b(f32v(%s) + f32v(%s))' % (a, b))
        if op == 0x93: return two('f32b(f32v(%s) - f32v(%s))' % (a, b))
        if op == 0x94: return two('f32b(f32v(%s) * f32v(%s))' % (a, b))
        if op == 0x95: return two('f32b(f32v(%s) / f32v(%s))' % (a, b))
        if op == 0x96: return two('f32b(f32_min(f32v(%s), f32v(%s)))' % (a, b))
        if op == 0x97: return two('f32b(f32_max(f32v(%s), f32v(%s)))' % (a, b))
        if op == 0x98: return two('f32_copysign(%s, %s)' % (a, b))
        if op == 0x99: return ein('f64b(f64_abs(f64v(%s)))' % x)
        if op == 0x9A: return ein('f64b(0.0 - f64v(%s))' % x)
        if op == 0x9B: return ein('f64b(f64_ceil(f64v(%s)))' % x)
        if op == 0x9C: return ein('f64b(f64_floor(f64v(%s)))' % x)
        if op == 0x9D: return ein('f64b(f64_trunc(f64v(%s)))' % x)
        if op == 0x9E: return ein('f64b(f64_nearest(f64v(%s)))' % x)
        if op == 0x9F: return ein('f64b(f64_sqrt(f64v(%s)))' % x)
        if op == 0xA0: return two('f64b(f64v(%s) + f64v(%s))' % (a, b))
        if op == 0xA1: return two('f64b(f64v(%s) - f64v(%s))' % (a, b))
        if op == 0xA2: return two('f64b(f64v(%s) * f64v(%s))' % (a, b))
        if op == 0xA3: return two('f64b(f64v(%s) / f64v(%s))' % (a, b))
        if op == 0xA4: return two('f64b(f64_min(f64v(%s), f64v(%s)))' % (a, b))
        if op == 0xA5: return two('f64b(f64_max(f64v(%s), f64v(%s)))' % (a, b))
        if op == 0xA6: return two('f64_copysign(%s, %s)' % (a, b))
        if op == 0xA7: return ein('%s & 4294967295' % x)
        if op == 0xA8: return ein('i32_trunc_f32_s(%s)' % x)
        if op == 0xA9: return ein('i32_trunc_f32_u(%s)' % x)
        if op == 0xAA: return ein('i32_trunc_f64_s(%s)' % x)
        if op == 0xAB: return ein('i32_trunc_f64_u(%s)' % x)
        if op == 0xAC: return ein('i32s(%s) as u64' % x)
        if op == 0xAD: return ein('%s & 4294967295' % x)
        if op == 0xAE: return ein('i64_trunc_f32_s(%s)' % x)
        if op == 0xAF: return ein('i64_trunc_f32_u(%s)' % x)
        if op == 0xB0: return ein('i64_trunc_f64_s(%s)' % x)
        if op == 0xB1: return ein('i64_trunc_f64_u(%s)' % x)
        if op == 0xB2: return ein('f32b(i32s(%s) as f32)' % x)
        if op == 0xB3: return ein('f32b((%s & 4294967295) as f32)' % x)
        if op == 0xB4: return ein('f32b(i64s(%s) as f32)' % x)
        if op == 0xB5: return ein('f32b(u64_zu_f32(%s))' % x)
        if op == 0xB6: return ein('f32b(f64v(%s) as f32)' % x)
        if op == 0xB7: return ein('f64b(i32s(%s) as f64)' % x)
        if op == 0xB8: return ein('f64b((%s & 4294967295) as f64)' % x)
        if op == 0xB9: return ein('f64b(i64s(%s) as f64)' % x)
        if op == 0xBA: return ein('f64b(u64_zu_f64(%s))' % x)
        if op == 0xBB: return ein('f64b(f32v(%s) as f64)' % x)
        if op == 0xBC: return ein('%s & 4294967295' % x)
        if op == 0xBD: return ein('%s' % x)
        if op == 0xBE: return ein('%s & 4294967295' % x)
        if op == 0xBF: return ein('%s' % x)
        if op == 0xC0: return ein('sext8_32(%s)' % x)
        if op == 0xC1: return ein('sext16_32(%s)' % x)
        if op == 0xC2: return ein('sext8_64(%s)' % x)
        if op == 0xC3: return ein('sext16_64(%s)' % x)
        if op == 0xC4: return ein('sext32_64(%s)' % x)
        return None

    def turm_erzeugen(self, l, code, count_2, danach, sp, stack, tiefe, arten=None):
        self.br_benutzt = True
        self.im_turm = True
        self.turm_faelle = count_2
        marke = self.marke + 1
        self.marke += 1
        E = lambda t, x: self.e(t, x)
        E(tiefe - 1, '// %d Bloecke am Stueck -> Verteiler (TIEFE.md)' % count_2)
        E(tiefe - 1, 'var fall%d: u64 = 0' % marke)
        E(tiefe - 1, 'while true {')
        E(tiefe, 'if fall%d == 0 {' % marke)
        for k in range(count_2):
            b = Block('turm', tiefe + k, sp, [], marke)
            b.loop = False
            b.turm_brand = marke
            b.turm_fall = count_2 - k
            b.turm_loop = bool(arten[k]) if arten else False
            stack.append(b)
        l.at = danach
        return sp

    def turm_ende(self, b, tiefe, stack):
        self.e(tiefe + 1, 'fall%d = %d' % (b.turm_brand, b.turm_fall))
        self.e(tiefe + 1, 'continue')
        self.e(tiefe, '}')
        self.e(tiefe, 'if fall%d == %d {' % (b.turm_brand, b.turm_fall))
        noch = [x for x in stack if x.art == 'turm'
                and x.turm_brand == b.turm_brand]
        if not noch:
            self.e(tiefe + 1, 'break')
            self.e(tiefe, '}')
            self.e(tiefe, 'break')
            self.e(tiefe - 1, '}')
            self.im_turm = False

    def block_braucht_loop(self, b, at):
        return _block_braucht_loop(b, at)

    def block_hat_sprung(self, b, at):
        return _block_hat_sprung(b, at)

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

    def rufname(self, fi):
        m = self.m
        if fi < m.n_import_funcs:
            mod, nam, art, _ = m.importe[fi]
            return 'imp_%s' % secure(nam)
        return self.fname(fi)


def secure(n):
    return ''.join(c if (c.isalnum() or c == '_') else '_' for c in n)



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

    o.append('// ================================== Globale des Moduls')
    for i, (t, ver, w, imp) in enumerate(m.globals):
        o.append('static mut g%d: u64 = %d' % (i, w))
    o.append('')

    o.append('// ================================= Die Importe (WASI)')
    seen = set()
    for fi, (mod, nam, art, ti) in enumerate(m.importe):
        if art != 'func':
            continue
        nm = 'imp_%s' % secure(nam)
        if nm in seen:
            continue
        seen.add(nm)
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

    o.append('// =========================== Die uebersetzten Funktionen')
    for fi in range(m.n_import_funcs, len(m.funktypen)):
        e.out = []
        e.func(fi)
        o += e.out

    o += table_erzeugen(m, e.indirekte_typen)

    o += start_erzeugen(m, name)
    return '\n'.join(o)


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


def table_erzeugen(m, indirekte_typen=()):
    o = ['// ============================ Die Tabelle (call_indirect)']
    tab = {}
    for off, funcs in m.elemente:
        for k, f in enumerate(funcs):
            tab[off + k] = f
    gebraucht = set()
    for ci, (lok, code) in enumerate(m.code):
        pass
    typen = {}
    for idx, f in tab.items():
        ti = m.funktypen[f]
        typen.setdefault(ti, []).append((idx, f))
    for ti in indirekte_typen:
        typen.setdefault(ti, [])
    for ti, eintraege in sorted(typen.items()):
        par, res = m.typen[ti]
        args = ', '.join('a%d: u64' % i for i in range(len(par)))
        o.append('fn tab_ruf_%d(idx: u64%s%s)%s {' % (
            ti, ', ' if args else '', args, ' -> u64' if res else ''))
        ruf_args = ', '.join('a%d' % i for i in range(len(par)))
        for idx, f in sorted(eintraege):
            if f < m.n_import_funcs:
                mod, nam, art, mti = m.importe[f]
                target = 'imp_%s' % secure(nam)
            else:
                target = 'f%d' % f
            if res:
                o.append('    if idx == %d { return %s(%s) }' % (idx, target, ruf_args))
            else:
                o.append('    if idx == %d {' % idx)
                o.append('        %s(%s)' % (target, ruf_args))
                o.append('        return')
                o.append('    }')
        o.append('    tab_falle(idx)')
        if res:
            o.append('    return 0')
        o.append('}')
        o.append('')
    o.append('fn tab_falle(idx: u64) {')
    o.append('    io.print("wasm: call_indirect on an empty slot\\n")')
    o.append('    rt.finish(133)')
    o.append('}')
    o.append('')
    return o


def start_erzeugen(m, name):
    o = ['// ==================================== Der Programmstart']
    o.append('fn wasi_clock_res(ret: u64) -> u64 {')
    o.append('    mem_st64(ret, 1000)')
    o.append('    return 0')
    o.append('}')
    o.append('')
    for k, (off, b) in enumerate(m.data):
        if not b:
            continue
        o.append('static mut DATA%d: [u8; %d] = [' % (k, len(b)))
        for z in range(0, len(b), 32):
            chunk = ', '.join(str(c) for c in b[z:z + 32])
            o.append('    %s,' % chunk)
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
    o.append('        io.print("wasm: no memory for the linear memory\\n")')
    o.append('        return 1')
    o.append('    }')
    o.append('    rt.mem_set(mem_p, 0, (mem_max * 65536) as usize)')
    o.append('    data_legen()')
    if m.start is not None:
        o.append('    f%d()' % m.start)
    target = m.exporte.get('_start')
    if target and target[0] == 0:
        par, res = m.typ_von(target[1])
        ruf = 'f%d()' % target[1]
        if res:
            o.append('    let rc: u64 = %s' % ruf)
            o.append('    return rc as i32')
        else:
            o.append('    %s' % ruf)
            o.append('    return 0')
    else:
        o.append('    io.print("wasm: the module has no _start\\n")')
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
    m = Module(open(a.wasm, 'rb').read())
    wasi = wasi_ziehen.ziehen(a.wasm_fi)
    lz = open(a.laufzeit).read()
    txt = erzeugen(m, wasi, lz, a.wasm)
    open(a.out, 'w').write(txt)
    n = txt.count('\n')
    sys.stderr.write('%s -> %s: %d WASM-Funktionen, %d Zeilen Firn\n'
                     % (a.wasm, a.out, len(m.code), n))


if __name__ == '__main__':
    main()
