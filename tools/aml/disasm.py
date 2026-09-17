#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/aml/disasm.py -- AML LESEN, UNABHAENGIG VOM KERNEL.

WARUM ES DIESES PROGRAMM GIBT.

Runde AML baut einen AML-Interpreter in `kernel/acpi/aml.fi`.  Eine Zusage
wie "der Namensraum enthaelt die erwarteten Geraete" oder "wir decken
so und so viele Opcodes ab" ist nichts wert, wenn dieselbe Software sie
prueft, die sie aufstellt -- dann misst der Test seine eigene Meinung.

Also steht die Kodierung von AML hier ein ZWEITES MAL, in einer anderen
Sprache, von Hand nach der ACPI-Spezifikation (Kapitel 20, "ACPI Machine
Language Specification").  `tools/aml/run.sh` laesst beide ueber
DIESELBEN Oktette laufen -- die DSDT, die QEMU der Maschine hinlegt --
und vergleicht.  Wo sie auseinandergehen, hat einer von beiden unrecht,
und dann ist die Runde nicht fertig.

Das ist derselbe Griff wie `tools/k18/expect.py` (die zweite Fassung der
MSR-Kodierung) und `tools/kernel/memmap.py` (die zweite Fassung der
kdata-Karte).

VERWENDUNG

    python3 tools/aml/disasm.py ns    TABELLE...     Namensraum auflisten
    python3 tools/aml/disasm.py hist  TABELLE...     Opcode-Histogramm
    python3 tools/aml/disasm.py asm   TABELLE...     Baum ausgeben
    python3 tools/aml/disasm.py prt   TABELLE...     was zu _PRT gehoert
    python3 tools/aml/disasm.py deckung LISTE TABELLE...
                                                     Abdeckung gegen eine
                                                     Liste unterstuetzter
                                                     Opcodes (eine Zahl je
                                                     Zeile, hex oder dez;
                                                     erweiterte Opcodes
                                                     als 5bXX)

TABELLE ist eine rohe ACPI-Tabelle MIT ihrem 36 Oktett langen Kopf
(so, wie `amldump` sie ausgibt).
"""
import sys


# ===================================================================
# DIE OPCODE-TAFEL
# ===================================================================
#
# Jeder Eintrag: (Name, Argumentliste).  Die Buchstaben der Argumentliste:
#
#   T  TermArg          -- ein Ausdruck
#   S  SuperName        -- ein benennbares Ziel (wird wie TermArg gelesen)
#   R  Target           -- SuperName ODER NullName (ein einzelnes 0x00)
#   N  NameString
#   B  ein Oktett
#   W  zwei Oktette
#   D  vier Oktette
#   Q  acht Oktette
#   Z  Zeichenkette, mit Null beendet
#
# Opcodes mit PkgLength und eigenem Rumpf (Scope, If, Method, Buffer ...)
# stehen NICHT hier, sondern werden im Parser einzeln behandelt -- ihre
# Form ist jeweils anders genug, dass eine Tabelle sie nur verstecken
# wuerde.

OPS = {
    0x00: ("Zero", ""),
    0x01: ("One", ""),
    0x06: ("Alias", "NN"),
    0x0A: ("Byte", "B"),
    0x0B: ("Word", "W"),
    0x0C: ("DWord", "D"),
    0x0D: ("String", "Z"),
    0x0E: ("QWord", "Q"),
    0x70: ("Store", "TS"),
    0x71: ("RefOf", "S"),
    0x72: ("Add", "TTR"),
    0x73: ("Concat", "TTR"),
    0x74: ("Subtract", "TTR"),
    0x75: ("Increment", "S"),
    0x76: ("Decrement", "S"),
    0x77: ("Multiply", "TTR"),
    0x78: ("Divide", "TTRR"),
    0x79: ("ShiftLeft", "TTR"),
    0x7A: ("ShiftRight", "TTR"),
    0x7B: ("And", "TTR"),
    0x7C: ("Nand", "TTR"),
    0x7D: ("Or", "TTR"),
    0x7E: ("Nor", "TTR"),
    0x7F: ("Xor", "TTR"),
    0x80: ("Not", "TR"),
    0x81: ("FindSetLeftBit", "TR"),
    0x82: ("FindSetRightBit", "TR"),
    0x83: ("DerefOf", "T"),
    0x84: ("ConcatRes", "TTR"),
    0x85: ("Mod", "TTR"),
    0x86: ("Notify", "ST"),
    0x87: ("SizeOf", "S"),
    0x88: ("Index", "TTR"),
    0x89: ("Match", "TBTBTT"),
    0x8A: ("CreateDWordField", "TTN"),
    0x8B: ("CreateWordField", "TTN"),
    0x8C: ("CreateByteField", "TTN"),
    0x8D: ("CreateBitField", "TTN"),
    0x8E: ("ObjectType", "S"),
    0x8F: ("CreateQWordField", "TTN"),
    0x90: ("LAnd", "TT"),
    0x91: ("LOr", "TT"),
    0x93: ("LEqual", "TT"),
    0x94: ("LGreater", "TT"),
    0x95: ("LLess", "TT"),
    0x96: ("ToBuffer", "TR"),
    0x97: ("ToDecimalString", "TR"),
    0x98: ("ToHexString", "TR"),
    0x99: ("ToInteger", "TR"),
    0x9C: ("ToString", "TTR"),
    0x9D: ("CopyObject", "TS"),
    0x9E: ("Mid", "TTTR"),
    0x9F: ("Continue", ""),
    0xA3: ("Noop", ""),
    0xA4: ("Return", "T"),
    0xA5: ("Break", ""),
    0xCC: ("BreakPoint", ""),
    0xFF: ("Ones", ""),
}

# Die erweiterten Opcodes, alle mit 0x5B davor.
EXT = {
    0x01: ("Mutex", "NB"),
    0x02: ("Event", "N"),
    0x12: ("CondRefOf", "SR"),
    0x1F: ("LoadTable", "TTTTTT"),
    0x20: ("Load", "NS"),
    0x21: ("Stall", "T"),
    0x22: ("Sleep", "T"),
    0x23: ("Acquire", "SW"),
    0x24: ("Signal", "S"),
    0x25: ("Wait", "ST"),
    0x26: ("Reset", "S"),
    0x27: ("Release", "S"),
    0x28: ("FromBCD", "TR"),
    0x29: ("ToBCD", "TR"),
    0x2A: ("Unload", "S"),
    0x30: ("Revision", ""),
    0x31: ("Debug", ""),
    0x32: ("Fatal", "BDT"),
    0x33: ("Timer", ""),
    0x80: ("OperationRegion", "NBTT"),
}

# Was `LNot` daraus macht: die drei zusammengesetzten Vergleiche stehen
# in AML als zwei Opcodes hintereinander.
LNOT_PAIR = {0x93: "LNotEqual", 0x94: "LLessEqual", 0x95: "LGreaterEqual"}

REGION_SPACE = {
    0: "SystemMemory", 1: "SystemIO", 2: "PCI_Config", 3: "EmbeddedControl",
    4: "SMBus", 5: "SystemCMOS", 6: "PciBarTarget", 7: "IPMI",
    8: "GeneralPurposeIO", 9: "GenericSerialBus", 10: "PCC",
}


# ===================================================================
# NAMEN
# ===================================================================

def seg_text(b):
    return b.decode("latin1").rstrip("_") or "_"


def join(scope, name):
    """Einen (moeglicherweise relativen) Namen an einen Bereich haengen."""
    if name.startswith("\\"):
        return name
    up = 0
    while name.startswith("^"):
        up += 1
        name = name[1:]
    base = scope
    for _ in range(up):
        if base != "\\":
            base = base.rsplit(".", 1)[0] if "." in base else "\\"
    if not name:
        return base
    if base == "\\":
        return "\\" + name
    return base + "." + name


class Aml:
    """Der Parser.  Eine Instanz je Durchgang ueber eine Tabelle."""

    def __init__(self, data, methods=None, count=None):
        self.d = data
        self.n = len(data)
        self.methods = methods if methods is not None else {}
        self.names = []          # (voller Name, Art, Zusatz)
        self.count = count if count is not None else {}
        self.errors = []

    # ------------------------------------------------------- Grundformen

    def u8(self, i):
        if i >= self.n:
            raise IndexError("AML zu Ende")
        return self.d[i]

    def pkglen(self, i):
        """PkgLength -- die Laenge zaehlt SICH SELBST mit."""
        lead = self.u8(i)
        extra = lead >> 6
        if extra == 0:
            return lead & 0x3F, i + 1
        v = lead & 0x0F
        for k in range(extra):
            v |= self.u8(i + 1 + k) << (4 + 8 * k)
        return v, i + 1 + extra

    def namestring(self, i):
        pre = ""
        if self.u8(i) == 0x5C:      # RootChar
            pre = "\\"
            i += 1
        else:
            while self.u8(i) == 0x5E:   # ParentPrefixChar
                pre += "^"
                i += 1
        c = self.u8(i)
        if c == 0x00:               # NullName
            return pre, i + 1
        if c == 0x2E:               # DualNamePath
            a = seg_text(self.d[i + 1:i + 5])
            b = seg_text(self.d[i + 5:i + 9])
            return pre + a + "." + b, i + 9
        if c == 0x2F:               # MultiNamePath
            cnt = self.u8(i + 1)
            segs = [seg_text(self.d[i + 2 + 4 * k:i + 6 + 4 * k])
                    for k in range(cnt)]
            return pre + ".".join(segs), i + 2 + 4 * cnt
        return pre + seg_text(self.d[i:i + 4]), i + 4

    def note(self, op):
        self.count[op] = self.count.get(op, 0) + 1

    # ------------------------------------------------------ Nachschlagen

    def lookup_method(self, scope, name):
        """Wie viele Argumente nimmt der Name, wenn er eine Methode ist?

        ACPI sucht einen einzelnen NameSeg vom aktuellen Bereich aufwaerts
        bis zur Wurzel (Spezifikation 5.3, "Name Search Rules")."""
        if name.startswith("\\") or name.startswith("^") or "." in name:
            full = join(scope, name)
            return self.methods.get(full)
        base = scope
        while True:
            full = join(base, name)
            if full in self.methods:
                return self.methods[full]
            if base == "\\":
                return None
            base = base.rsplit(".", 1)[0] if "." in base else "\\"

    # ------------------------------------------------------- TermArg

    def termarg(self, i, scope, out):
        """EIN Ausdruck.  Gibt die Position dahinter zurueck."""
        c = self.u8(i)
        if 0x60 <= c <= 0x67:
            self.note(c)
            out.append("Local%d" % (c - 0x60))
            return i + 1
        if 0x68 <= c <= 0x6E:
            self.note(c)
            out.append("Arg%d" % (c - 0x68))
            return i + 1
        if c == 0x11:                    # Buffer
            self.note(c)
            ln, j = self.pkglen(i + 1)
            end = i + 1 + ln
            sub = []
            j = self.termarg(j, scope, sub)
            out.append("Buffer(%s){%d Oktett}" % (sub[0], end - j))
            return end
        if c in (0x12, 0x13):            # Package / VarPackage
            self.note(c)
            ln, j = self.pkglen(i + 1)
            end = i + 1 + ln
            if c == 0x12:
                num = self.u8(j)
                j += 1
                head = "Package(%d)" % num
            else:
                sub = []
                j = self.termarg(j, scope, sub)
                head = "VarPackage(%s)" % sub[0]
            elems = []
            while j < end:
                sub = []
                j = self.term(j, scope, sub, allow_name_data=True)
                elems.append(sub[0] if sub else "?")
            out.append(head + "{" + ", ".join(elems) + "}")
            return end
        return self.term(i, scope, out)

    # -------------------------------------------------------- ein Term

    def term(self, i, scope, out, allow_name_data=False):
        c = self.u8(i)

        # --- Namensraum-Bauwerke mit eigenem Rumpf
        if c == 0x10:                    # Scope
            self.note(c)
            ln, j = self.pkglen(i + 1)
            end = i + 1 + ln
            nm, j = self.namestring(j)
            full = join(scope, nm)
            self.names.append((full, "Scope", ""))
            self.termlist(j, end, full, out)
            out.append("Scope(%s)" % full)
            return end
        if c == 0x14:                    # Method
            self.note(c)
            ln, j = self.pkglen(i + 1)
            end = i + 1 + ln
            nm, j = self.namestring(j)
            flags = self.u8(j)
            j += 1
            full = join(scope, nm)
            self.names.append((full, "Method", "%d" % (flags & 7)))
            self.methods[full] = flags & 7
            body = []
            try:
                self.termlist(j, end, full, body)
            except Exception as e:       # ein kaputter Rumpf haelt uns nicht auf
                self.errors.append("%s: %s" % (full, e))
            out.append("Method(%s, %d)" % (full, flags & 7))
            return end
        if c == 0x08:                    # Name
            self.note(c)
            nm, j = self.namestring(i + 1)
            full = join(scope, nm)
            sub = []
            j = self.termarg(j, scope, sub)
            self.names.append((full, "Name", sub[0] if sub else ""))
            out.append("Name(%s, %s)" % (full, sub[0] if sub else "?"))
            return j
        if c == 0xA0:                    # If
            self.note(c)
            ln, j = self.pkglen(i + 1)
            end = i + 1 + ln
            sub = []
            j = self.termarg(j, scope, sub)
            body = []
            self.termlist(j, end, scope, body)
            out.append("If(%s)" % (sub[0] if sub else "?"))
            return end
        if c == 0xA1:                    # Else
            self.note(c)
            ln, j = self.pkglen(i + 1)
            end = i + 1 + ln
            body = []
            self.termlist(j, end, scope, body)
            out.append("Else")
            return end
        if c == 0xA2:                    # While
            self.note(c)
            ln, j = self.pkglen(i + 1)
            end = i + 1 + ln
            sub = []
            j = self.termarg(j, scope, sub)
            body = []
            self.termlist(j, end, scope, body)
            out.append("While(%s)" % (sub[0] if sub else "?"))
            return end
        if c == 0x92:                    # LNot, evtl. als Paar
            nxt = self.u8(i + 1)
            if nxt in LNOT_PAIR:
                self.note(0x9200 | nxt)
                a, b = [], []
                j = self.termarg(i + 2, scope, a)
                j = self.termarg(j, scope, b)
                out.append("%s(%s, %s)" % (LNOT_PAIR[nxt], a[0], b[0]))
                return j
            self.note(c)
            a = []
            j = self.termarg(i + 1, scope, a)
            out.append("LNot(%s)" % a[0])
            return j

        # --- erweiterte Opcodes
        if c == 0x5B:
            e = self.u8(i + 1)
            self.note(0x5B00 | e)
            if e in (0x82, 0x85, 0x84, 0x83):   # Device, ThermalZone, PowerRes, Processor
                ln, j = self.pkglen(i + 2)
                end = i + 2 + ln
                nm, j = self.namestring(j)
                full = join(scope, nm)
                kind = {0x82: "Device", 0x85: "ThermalZone",
                        0x84: "PowerResource", 0x83: "Processor"}[e]
                if e == 0x83:
                    j += 6                       # ProcID, PblkAddr, PblkLen
                if e == 0x84:
                    j += 3                       # SystemLevel, ResourceOrder
                self.names.append((full, kind, ""))
                body = []
                self.termlist(j, end, full, body)
                out.append("%s(%s)" % (kind, full))
                return end
            if e == 0x81:                        # Field
                ln, j = self.pkglen(i + 2)
                end = i + 2 + ln
                nm, j = self.namestring(j)
                flags = self.u8(j)
                j += 1
                self.fieldlist(j, end, scope, join(scope, nm), flags)
                out.append("Field(%s)" % join(scope, nm))
                return end
            if e == 0x86:                        # IndexField
                ln, j = self.pkglen(i + 2)
                end = i + 2 + ln
                nm1, j = self.namestring(j)
                nm2, j = self.namestring(j)
                flags = self.u8(j)
                j += 1
                self.fieldlist(j, end, scope, join(scope, nm1), flags)
                out.append("IndexField(%s, %s)" % (nm1, nm2))
                return end
            if e == 0x87:                        # BankField
                ln, j = self.pkglen(i + 2)
                end = i + 2 + ln
                nm1, j = self.namestring(j)
                nm2, j = self.namestring(j)
                sub = []
                j = self.termarg(j, scope, sub)
                flags = self.u8(j)
                j += 1
                self.fieldlist(j, end, scope, join(scope, nm1), flags)
                out.append("BankField(%s, %s)" % (nm1, nm2))
                return end
            if e == 0x13:                        # CreateField
                a, b, cc = [], [], []
                j = self.termarg(i + 2, scope, a)
                j = self.termarg(j, scope, b)
                j = self.termarg(j, scope, cc)
                nm, j = self.namestring(j)
                self.names.append((join(scope, nm), "BufferField", ""))
                out.append("CreateField(%s)" % nm)
                return j
            if e in EXT:
                name, spec = EXT[e]
                j = i + 2
                args = []
                if e == 0x80:                    # OperationRegion
                    nm, j = self.namestring(j)
                    space = self.u8(j)
                    j += 1
                    a, b = [], []
                    j = self.termarg(j, scope, a)
                    j = self.termarg(j, scope, b)
                    self.names.append((join(scope, nm), "OperationRegion",
                                       REGION_SPACE.get(space, str(space))))
                    out.append("OperationRegion(%s, %s, %s, %s)"
                               % (join(scope, nm),
                                  REGION_SPACE.get(space, str(space)),
                                  a[0], b[0]))
                    return j
                if e in (0x01, 0x02):            # Mutex, Event
                    nm, j = self.namestring(j)
                    if e == 0x01:
                        j += 1
                    self.names.append((join(scope, nm),
                                       "Mutex" if e == 0x01 else "Event", ""))
                    out.append("%s(%s)" % (name, nm))
                    return j
                j, args = self.args(j, scope, spec)
                out.append("%s(%s)" % (name, ", ".join(args)))
                return j
            raise ValueError("unbekannter erweiterter Opcode 0x5b%02x an %d"
                             % (e, i))

        # --- die einfachen Opcodes aus der Tafel
        if c in OPS:
            self.note(c)
            name, spec = OPS[c]
            j, args = self.args(i + 1, scope, spec)
            if spec in ("B", "W", "D", "Q", "Z", ""):
                out.append(args[0] if args else name)
            else:
                out.append("%s(%s)" % (name, ", ".join(args)))
            return j

        # --- sonst: ein Name.  Entweder ein Methodenaufruf oder ein Verweis.
        if c in (0x5C, 0x5E, 0x2E, 0x2F) or (0x41 <= c <= 0x5A) or c == 0x5F:
            nm, j = self.namestring(i)
            nargs = self.lookup_method(scope, nm)
            if nargs:
                args = []
                for _ in range(nargs):
                    sub = []
                    j = self.termarg(j, scope, sub)
                    args.append(sub[0] if sub else "?")
                out.append("%s(%s)" % (nm, ", ".join(args)))
            else:
                out.append(nm)
            return j

        raise ValueError("unbekannter Opcode 0x%02x an %d" % (c, i))

    def args(self, i, scope, spec):
        out = []
        for ch in spec:
            if ch == "B":
                out.append("0x%02x" % self.u8(i))
                i += 1
            elif ch == "W":
                out.append("0x%04x" % int.from_bytes(self.d[i:i + 2], "little"))
                i += 2
            elif ch == "D":
                out.append("0x%08x" % int.from_bytes(self.d[i:i + 4], "little"))
                i += 4
            elif ch == "Q":
                out.append("0x%016x" % int.from_bytes(self.d[i:i + 8], "little"))
                i += 8
            elif ch == "Z":
                k = i
                while self.d[k] != 0:
                    k += 1
                out.append('"%s"' % self.d[i:k].decode("latin1"))
                i = k + 1
            elif ch == "N":
                nm, i = self.namestring(i)
                out.append(nm)
            elif ch == "R":
                if self.u8(i) == 0x00:
                    out.append("-")
                    i += 1
                else:
                    sub = []
                    i = self.termarg(i, scope, sub)
                    out.append(sub[0] if sub else "?")
            else:                                # T, S
                sub = []
                i = self.termarg(i, scope, sub)
                out.append(sub[0] if sub else "?")
        return i, out

    def fieldlist(self, i, end, scope, region, flags):
        """Die Elemente eines Field.  Jedes traegt seine Bitbreite."""
        off = 0
        while i < end:
            c = self.u8(i)
            if c == 0x00:                        # ReservedField
                ln, i = self.pkglen(i + 1)
                off += ln
                continue
            if c == 0x01:                        # AccessField
                i += 3
                continue
            if c == 0x02:                        # ConnectField
                i += 1
                sub = []
                i = self.termarg(i, scope, sub)
                continue
            if c == 0x03:                        # ExtendedAccessField
                i += 4
                continue
            nm = seg_text(self.d[i:i + 4])
            i += 4
            ln, i = self.pkglen(i)
            full = join(region.rsplit(".", 1)[0] if "." in region else "\\", nm)
            self.names.append((join(scope, nm), "FieldUnit",
                               "%s+%d:%d" % (region, off, ln)))
            off += ln

    def termlist(self, i, end, scope, out):
        while i < end:
            sub = []
            i = self.term(i, scope, sub)
            out.extend(sub)


# ===================================================================
# Ein Durchgang ueber eine Tabelle
# ===================================================================

def strip_header(raw):
    if len(raw) < 36:
        raise ValueError("Tabelle kuerzer als ihr Kopf")
    sig = raw[0:4].decode("latin1")
    length = int.from_bytes(raw[4:8], "little")
    return sig, raw[36:length] if length <= len(raw) else raw[36:]


def collect_methods(body, methods, scope="\\"):
    """Erster Durchgang: nur die Methodennamen und ihre Argumentzahlen.

    Ein Methodenaufruf steht in AML als nackter Name -- ohne die
    Argumentzahl weiss man nicht, wo er aufhoert.  Also werden die
    Deklarationen zuerst eingesammelt, und dabei werden Methodenrumpfe
    UEBERSPRUNGEN (ihre PkgLength sagt, wie weit)."""
    p = Aml(body, methods)

    def walk(i, end, scope):
        while i < end:
            c = p.u8(i)
            if c == 0x14:                       # Method
                ln, j = p.pkglen(i + 1)
                nm, j = p.namestring(j)
                flags = p.u8(j)
                methods[join(scope, nm)] = flags & 7
                i = i + 1 + ln
                continue
            if c == 0x10:                       # Scope
                ln, j = p.pkglen(i + 1)
                nm, j = p.namestring(j)
                walk(j, i + 1 + ln, join(scope, nm))
                i = i + 1 + ln
                continue
            if c == 0x5B and p.u8(i + 1) in (0x82, 0x83, 0x84, 0x85):
                e = p.u8(i + 1)
                ln, j = p.pkglen(i + 2)
                nm, j = p.namestring(j)
                if e == 0x83:
                    j += 6
                if e == 0x84:
                    j += 3
                walk(j, i + 2 + ln, join(scope, nm))
                i = i + 2 + ln
                continue
            # alles andere: ueberspringen ist nicht moeglich, ohne es zu
            # lesen -- also einen vollen Term lesen und wegwerfen.
            sub = []
            i = p.term(i, scope, sub)
    walk(0, len(body), scope)
    return methods


def parse_tables(paths):
    """Alle Tabellen zusammen: erst die Methoden, dann der Baum."""
    bodies = []
    for path in paths:
        raw = open(path, "rb").read()
        sig, body = strip_header(raw)
        if sig not in ("DSDT", "SSDT"):
            continue
        bodies.append((sig, body))
    methods = {}
    for sig, body in bodies:
        try:
            collect_methods(body, methods)
        except Exception as e:
            print("WARNUNG: erster Durchgang ueber %s: %s" % (sig, e),
                  file=sys.stderr)
    names = []
    count = {}
    errors = []
    for sig, body in bodies:
        p = Aml(body, methods, count)
        out = []
        try:
            p.termlist(0, len(body), "\\", out)
        except Exception as e:
            errors.append("%s: %s" % (sig, e))
        names.extend(p.names)
        errors.extend(p.errors)
    return names, count, errors, methods


def op_text(op):
    if op >= 0x9200:
        return "%s (0x92 0x%02x)" % (LNOT_PAIR[op & 0xFF], op & 0xFF)
    if op >= 0x5B00:
        e = op & 0xFF
        nm = EXT.get(e, ("Ext%02x" % e, ""))[0]
        if e == 0x82:
            nm = "Device"
        if e == 0x85:
            nm = "ThermalZone"
        if e == 0x81:
            nm = "Field"
        if e == 0x86:
            nm = "IndexField"
        if e == 0x87:
            nm = "BankField"
        if e == 0x83:
            nm = "Processor"
        if e == 0x84:
            nm = "PowerResource"
        if e == 0x13:
            nm = "CreateField"
        return "%s (0x5b 0x%02x)" % (nm, e)
    if 0x60 <= op <= 0x67:
        return "Local%d (0x%02x)" % (op - 0x60, op)
    if 0x68 <= op <= 0x6E:
        return "Arg%d (0x%02x)" % (op - 0x68, op)
    extra = {0x10: "Scope", 0x14: "Method", 0x11: "Buffer", 0x12: "Package",
             0x13: "VarPackage", 0xA0: "If", 0xA1: "Else", 0xA2: "While",
             0x92: "LNot"}
    nm = extra.get(op) or OPS.get(op, ("Op%02x" % op, ""))[0]
    return "%s (0x%02x)" % (nm, op)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    mode = argv[1]
    if mode == "deckung":
        liste = argv[2]
        paths = argv[3:]
    else:
        paths = argv[2:]
    names, count, errors, methods = parse_tables(paths)

    if mode == "ns":
        for full, kind, extra in names:
            print("%-40s %-16s %s" % (full, kind, extra))
        print("namen=%d" % len(names))
    elif mode == "hist":
        for op in sorted(count):
            print("%-34s %6d" % (op_text(op), count[op]))
        print("verschiedene=%d gesamt=%d" % (len(count), sum(count.values())))
    elif mode == "asm":
        # Der Baum ist schon beim Parsen ausgegeben worden; hier nur die
        # oberste Ebene, damit die Ausgabe lesbar bleibt.
        for full, kind, extra in names:
            print("%-40s %-16s %s" % (full, kind, extra))
    elif mode == "prt":
        for full, kind, extra in names:
            if full.endswith("_PRT") or full.endswith("PRTA") \
                    or full.endswith("PRTP") or "LNK" in full \
                    or full.endswith("PICF") or full.endswith("_PIC"):
                print("%-40s %-16s %s" % (full, kind, extra))
    elif mode == "deckung":
        koennen = set()
        for line in open(liste):
            line = line.split("#")[0].strip()
            if not line:
                continue
            koennen.add(int(line, 16) if not line.startswith("0x")
                        else int(line, 16))
        da = set(count)
        fehlt = sorted(da - koennen)
        print("in der Tabelle vorkommend: %d verschiedene Opcodes" % len(da))
        print("davon unterstuetzt:        %d" % len(da & koennen))
        print("Abdeckung:                 %d%%"
              % (100 * len(da & koennen) // max(1, len(da))))
        for op in fehlt:
            print("  FEHLT %-34s %6d mal" % (op_text(op), count[op]))
    if errors:
        print("FEHLER beim Lesen:", file=sys.stderr)
        for e in errors:
            print("  " + e, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
