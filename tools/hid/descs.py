#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/hid/descs.py -- DIE ECHTEN BERICHTSBESCHREIBUNGEN UND EIN
ZWEITER ZERLEGER, DER SIE UNABHAENGIG LIEST.

Warum ein ZWEITER Zerleger.  Ein Test, in dem dieselbe Person zuerst den
Zerleger schreibt und dann hinschreibt, was herauskommen soll, misst nur,
ob sie sich zweimal gleich geirrt hat.  Deshalb steht hier eine zweite
Umsetzung -- in einer anderen Sprache, aus der Spezifikation heraus --
und `tools/hid/run.sh` haelt beide Ergebnisse ZEILE FUER ZEILE
gegeneinander.  Wo sie sich unterscheiden, ist einer von beiden falsch,
und das ist mehr, als eine von Hand geschriebene Erwartungsliste je
sagen koennte.

DIE BESCHREIBUNGEN sind nicht erfunden.  Sie stehen hier als Postenliste
mit Kommentar, damit jede Zeile nachlesbar ist:

  1. BOOT-TASTATUR -- HID 1.11, Anhang B.1, woertlich.  63 Oktette.
  2. BOOT-MAUS     -- HID 1.11, Anhang B.2, woertlich.  50 Oktette.
  3. RADMAUS       -- die Bauform, die seit 1999 in jeder Maus mit Rad
                      und fuenf Knoepfen steckt: Berichtsnummer, fuenf
                      Knoepfe, 16 Bit je Achse, Rad.
  4. PRAEZISIONS-TOUCHPAD -- die von Microsoft fuer ein Windows
                      Precision Touchpad vorgeschriebene Bauform: fuenf
                      Finger-Sammlungen mit Zuversicht, Spitzenschalter,
                      Kontaktnummer, X und Y, dazu Kontaktzahl, Knopf,
                      Abtastzeit und die Eigenschaft Kontaktzahl-Maximum.
  5. VERBRAUCHERSTEUERUNG -- die Multimediatasten eines Laptops als
                      Feldgruppe ueber die Gebrauchsseite 0x0C.
  6. NKRO-TASTATUR -- eine Tastatur ohne Anschlagsgrenze: acht
                      Zusatztasten plus 120 Bit, ein Bit je Taste.
                      DAS IST DER FALL, DEN DAS BOOT-PROTOKOLL NICHT KANN.

Aufruf:
    python3 tools/hid/descs.py firn   > kernel/hidtest.fi
    python3 tools/hid/descs.py kopf              # Erwartung, Zeile je Geraet
    python3 tools/hid/descs.py felder            # Erwartung, Zeile je Feld
    python3 tools/hid/descs.py fehler            # die kaputten, mit Nummer
"""
import sys

# ----------------------------------------------------------------------
# 1. Boot-Tastatur, HID 1.11 Anhang B.1
KBD_BOOT = bytes([
    0x05, 0x01,        # Usage Page (Generic Desktop)
    0x09, 0x06,        # Usage (Keyboard)
    0xA1, 0x01,        # Collection (Application)
    0x05, 0x07,        #   Usage Page (Keyboard/Keypad)
    0x19, 0xE0,        #   Usage Minimum (224)
    0x29, 0xE7,        #   Usage Maximum (231)
    0x15, 0x00,        #   Logical Minimum (0)
    0x25, 0x01,        #   Logical Maximum (1)
    0x75, 0x01,        #   Report Size (1)
    0x95, 0x08,        #   Report Count (8)
    0x81, 0x02,        #   Input (Data,Var,Abs)   -- die acht Zusatztasten
    0x95, 0x01,        #   Report Count (1)
    0x75, 0x08,        #   Report Size (8)
    0x81, 0x01,        #   Input (Cnst)           -- das vorbehaltene Oktett
    0x95, 0x05,        #   Report Count (5)
    0x75, 0x01,        #   Report Size (1)
    0x05, 0x08,        #   Usage Page (LEDs)
    0x19, 0x01,        #   Usage Minimum (1)
    0x29, 0x05,        #   Usage Maximum (5)
    0x91, 0x02,        #   Output (Data,Var,Abs)  -- die Leuchten
    0x95, 0x01,        #   Report Count (1)
    0x75, 0x03,        #   Report Size (3)
    0x91, 0x01,        #   Output (Cnst)          -- Fuellbits
    0x95, 0x06,        #   Report Count (6)
    0x75, 0x08,        #   Report Size (8)
    0x15, 0x00,        #   Logical Minimum (0)
    0x25, 0x65,        #   Logical Maximum (101)
    0x05, 0x07,        #   Usage Page (Keyboard/Keypad)
    0x19, 0x00,        #   Usage Minimum (0)
    0x29, 0x65,        #   Usage Maximum (101)
    0x81, 0x00,        #   Input (Data,Array)     -- sechs Tastenplaetze
    0xC0,              # End Collection
])

# 2. Boot-Maus, HID 1.11 Anhang B.2
MOUSE_BOOT = bytes([
    0x05, 0x01,        # Usage Page (Generic Desktop)
    0x09, 0x02,        # Usage (Mouse)
    0xA1, 0x01,        # Collection (Application)
    0x09, 0x01,        #   Usage (Pointer)
    0xA1, 0x00,        #   Collection (Physical)
    0x05, 0x09,        #     Usage Page (Button)
    0x19, 0x01,        #     Usage Minimum (1)
    0x29, 0x03,        #     Usage Maximum (3)
    0x15, 0x00,        #     Logical Minimum (0)
    0x25, 0x01,        #     Logical Maximum (1)
    0x95, 0x03,        #     Report Count (3)
    0x75, 0x01,        #     Report Size (1)
    0x81, 0x02,        #     Input (Data,Var,Abs)
    0x95, 0x01,        #     Report Count (1)
    0x75, 0x05,        #     Report Size (5)
    0x81, 0x01,        #     Input (Cnst)
    0x05, 0x01,        #     Usage Page (Generic Desktop)
    0x09, 0x30,        #     Usage (X)
    0x09, 0x31,        #     Usage (Y)
    0x15, 0x81,        #     Logical Minimum (-127)
    0x25, 0x7F,        #     Logical Maximum (127)
    0x75, 0x08,        #     Report Size (8)
    0x95, 0x02,        #     Report Count (2)
    0x81, 0x06,        #     Input (Data,Var,Rel)
    0xC0,              #   End Collection
    0xC0,              # End Collection
])

# 3. Radmaus: Berichtsnummer, fuenf Knoepfe, 16 Bit je Achse, Rad
MOUSE_WHEEL = bytes([
    0x05, 0x01,        # Usage Page (Generic Desktop)
    0x09, 0x02,        # Usage (Mouse)
    0xA1, 0x01,        # Collection (Application)
    0x85, 0x01,        #   Report ID (1)
    0x09, 0x01,        #   Usage (Pointer)
    0xA1, 0x00,        #   Collection (Physical)
    0x05, 0x09,        #     Usage Page (Button)
    0x19, 0x01,        #     Usage Minimum (1)
    0x29, 0x05,        #     Usage Maximum (5)
    0x15, 0x00,        #     Logical Minimum (0)
    0x25, 0x01,        #     Logical Maximum (1)
    0x95, 0x05,        #     Report Count (5)
    0x75, 0x01,        #     Report Size (1)
    0x81, 0x02,        #     Input (Data,Var,Abs)
    0x95, 0x01,        #     Report Count (1)
    0x75, 0x03,        #     Report Size (3)
    0x81, 0x01,        #     Input (Cnst)
    0x05, 0x01,        #     Usage Page (Generic Desktop)
    0x09, 0x30,        #     Usage (X)
    0x09, 0x31,        #     Usage (Y)
    0x16, 0x01, 0x80,  #     Logical Minimum (-32767)
    0x26, 0xFF, 0x7F,  #     Logical Maximum (32767)
    0x75, 0x10,        #     Report Size (16)
    0x95, 0x02,        #     Report Count (2)
    0x81, 0x06,        #     Input (Data,Var,Rel)
    0x09, 0x38,        #     Usage (Wheel)
    0x15, 0x81,        #     Logical Minimum (-127)
    0x25, 0x7F,        #     Logical Maximum (127)
    0x75, 0x08,        #     Report Size (8)
    0x95, 0x01,        #     Report Count (1)
    0x81, 0x06,        #     Input (Data,Var,Rel)
    0xC0,              #   End Collection
    0xC0,              # End Collection
])


def _finger():
    """Eine Finger-Sammlung eines Praezisions-Touchpads, 73 Oktette."""
    return [
        0x05, 0x0D,        #   Usage Page (Digitizer)
        0x09, 0x22,        #   Usage (Finger)
        0xA1, 0x02,        #   Collection (Logical)
        0x15, 0x00,        #     Logical Minimum (0)
        0x25, 0x01,        #     Logical Maximum (1)
        0x09, 0x47,        #     Usage (Confidence)
        0x09, 0x42,        #     Usage (Tip Switch)
        0x95, 0x02,        #     Report Count (2)
        0x75, 0x01,        #     Report Size (1)
        0x81, 0x02,        #     Input (Data,Var,Abs)
        0x95, 0x01,        #     Report Count (1)
        0x75, 0x02,        #     Report Size (2)
        0x81, 0x03,        #     Input (Cnst,Var,Abs)
        0x95, 0x01,        #     Report Count (1)
        0x75, 0x04,        #     Report Size (4)
        0x25, 0x05,        #     Logical Maximum (5)
        0x09, 0x51,        #     Usage (Contact Identifier)
        0x81, 0x02,        #     Input (Data,Var,Abs)
        0x05, 0x01,        #     Usage Page (Generic Desktop)
        0x15, 0x00,        #     Logical Minimum (0)
        0x26, 0x20, 0x0E,  #     Logical Maximum (3616)
        0x75, 0x10,        #     Report Size (16)
        0x55, 0x0E,        #     Unit Exponent (-2)
        0x65, 0x11,        #     Unit (cm)
        0x09, 0x30,        #     Usage (X)
        0x35, 0x00,        #     Physical Minimum (0)
        0x46, 0x60, 0x02,  #     Physical Maximum (608)
        0x95, 0x01,        #     Report Count (1)
        0x81, 0x02,        #     Input (Data,Var,Abs)
        0x46, 0x8E, 0x01,  #     Physical Maximum (398)
        0x26, 0x88, 0x08,  #     Logical Maximum (2184)
        0x09, 0x31,        #     Usage (Y)
        0x81, 0x02,        #     Input (Data,Var,Abs)
        0x05, 0x0D,        #     Usage Page (Digitizer)
        0xC0,              #   End Collection
    ]


# 4. Praezisions-Touchpad, fuenf Finger
PTP = bytes(
    [
        0x05, 0x0D,        # Usage Page (Digitizer)
        0x09, 0x05,        # Usage (Touch Pad)
        0xA1, 0x01,        # Collection (Application)
        0x85, 0x01,        #   Report ID (1)
    ]
    + _finger() * 5
    + [
        0x05, 0x0D,        #   Usage Page (Digitizer)
        0x09, 0x54,        #   Usage (Contact Count)
        0x95, 0x01,        #   Report Count (1)
        0x75, 0x07,        #   Report Size (7)
        0x15, 0x00,        #   Logical Minimum (0)
        0x25, 0x05,        #   Logical Maximum (5)
        0x81, 0x02,        #   Input (Data,Var,Abs)
        0x05, 0x09,        #   Usage Page (Button)
        0x09, 0x01,        #   Usage (Button 1)
        0x25, 0x01,        #   Logical Maximum (1)
        0x75, 0x01,        #   Report Size (1)
        0x95, 0x01,        #   Report Count (1)
        0x81, 0x02,        #   Input (Data,Var,Abs)
        0x05, 0x0D,        #   Usage Page (Digitizer)
        0x09, 0x56,        #   Usage (Scan Time)
        0x55, 0x00,        #   Unit Exponent (0)
        0x66, 0x01, 0x10,  #   Unit (Sekunden)
        0x47, 0xFF, 0xFF, 0x00, 0x00,   # Physical Maximum (65535)
        0x27, 0xFF, 0xFF, 0x00, 0x00,   # Logical Maximum (65535)
        0x75, 0x10,        #   Report Size (16)
        0x95, 0x01,        #   Report Count (1)
        0x81, 0x02,        #   Input (Data,Var,Abs)
        0x09, 0x55,        #   Usage (Contact Count Maximum)
        0x25, 0x05,        #   Logical Maximum (5)
        0x75, 0x08,        #   Report Size (8)
        0xB1, 0x02,        #   Feature (Data,Var,Abs)
        0xC0,              # End Collection
    ]
)

# 5. Verbrauchersteuerung (Multimediatasten)
CONSUMER = bytes([
    0x05, 0x0C,        # Usage Page (Consumer)
    0x09, 0x01,        # Usage (Consumer Control)
    0xA1, 0x01,        # Collection (Application)
    0x85, 0x03,        #   Report ID (3)
    0x15, 0x00,        #   Logical Minimum (0)
    0x26, 0xFF, 0x03,  #   Logical Maximum (1023)
    0x19, 0x00,        #   Usage Minimum (0)
    0x2A, 0xFF, 0x03,  #   Usage Maximum (1023)
    0x75, 0x10,        #   Report Size (16)
    0x95, 0x02,        #   Report Count (2)
    0x81, 0x00,        #   Input (Data,Array,Abs)
    0xC0,              # End Collection
])

# 6. Tastatur ohne Anschlagsgrenze (NKRO)
KBD_NKRO = bytes([
    0x05, 0x01,        # Usage Page (Generic Desktop)
    0x09, 0x06,        # Usage (Keyboard)
    0xA1, 0x01,        # Collection (Application)
    0x85, 0x02,        #   Report ID (2)
    0x05, 0x07,        #   Usage Page (Keyboard/Keypad)
    0x19, 0xE0,        #   Usage Minimum (224)
    0x29, 0xE7,        #   Usage Maximum (231)
    0x15, 0x00,        #   Logical Minimum (0)
    0x25, 0x01,        #   Logical Maximum (1)
    0x75, 0x01,        #   Report Size (1)
    0x95, 0x08,        #   Report Count (8)
    0x81, 0x02,        #   Input (Data,Var,Abs)
    0x19, 0x00,        #   Usage Minimum (0)
    0x29, 0x77,        #   Usage Maximum (119)
    0x95, 0x78,        #   Report Count (120)
    0x81, 0x02,        #   Input (Data,Var,Abs)
    0xC0,              # End Collection
])

GUT = [
    ("kbdboot", KBD_BOOT),
    ("mouse", MOUSE_BOOT),
    ("wheel", MOUSE_WHEEL),
    ("ptp", PTP),
    ("consumer", CONSUMER),
    ("nkro", KBD_NKRO),
]

# ----------------------------------------------------------------------
# DIE KAPUTTEN.  Jede ist auf GENAU EINE Art kaputt, und zu jeder gehoert
# die Fehlernummer aus kernel/hidrep.fi, die dabei herauskommen MUSS.

E_OK, E_TRUNC, E_NEST, E_FIELDS, E_RIDS = 0, 1, 2, 3, 4
E_PUSH, E_SIZE, E_USAGE, E_LONG, E_EMPTY, E_BIG = 5, 6, 7, 8, 9, 10

KAPUTT = [
    # mitten in einem Posten abgeschnitten
    ("abgeschn", KBD_BOOT[:41], E_TRUNC),
    # der letzte Posten verspricht zwei Datenoktette und hat keins
    ("kopfleer", KBD_BOOT[:62] + bytes([0x26]), E_TRUNC),
    # Sammlung nie geschlossen (das schliessende C0 fehlt)
    ("offen", KBD_BOOT[:-1], E_NEST),
    # Sammlungsende ohne Sammlung
    ("endeohne", bytes([0xC0]), E_NEST),
    # neun Sammlungen tief -- MAX_DEPTH ist acht
    ("zutief", bytes([0x05, 0x01, 0x09, 0x06] + [0xA1, 0x01] * 9), E_NEST),
    # Holen ohne Ablegen
    ("popleer", bytes([0x05, 0x01, 0x09, 0x06, 0xA1, 0x01, 0xB4, 0xC0]),
     E_PUSH),
    # Berichtsgroesse 255 -- ueber 32 Bit rechnet dieser Kernel nicht
    ("gr255", bytes([0x05, 0x01, 0x09, 0x06, 0xA1, 0x01,
                     0x75, 0xFF, 0x95, 0x01, 0x81, 0x02, 0xC0]), E_SIZE),
    # Berichtsnummer 0 gibt es nicht
    ("ridnull", bytes([0x05, 0x01, 0x09, 0x06, 0xA1, 0x01,
                       0x85, 0x00, 0xC0]), E_SIZE),
    # ein Bericht von 8 * 1024 Bit passt in keinen Puffer
    ("zugross", bytes([0x05, 0x01, 0x09, 0x06, 0xA1, 0x01,
                       0x75, 0x08, 0x96, 0x00, 0x04,
                       0x81, 0x02, 0xC0]), E_BIG),
    # ein LANGER Posten -- es gibt bis heute keinen vergebenen
    ("langpost", bytes([0x05, 0x01, 0xFE, 0x02, 0x00, 0x00, 0x00, 0xC0]),
     E_LONG),
    # leer
    ("leer", b"", E_EMPTY),
    # mehr Felder als die Tabelle fasst
    ("vielfeld",
     bytes([0x05, 0x01, 0x09, 0x06, 0xA1, 0x01, 0x75, 0x01, 0x95, 0x01]
           + [0x09, 0x30, 0x81, 0x02] * 65 + [0xC0]), E_FIELDS),
    # mehr Berichtsnummern als die Tabelle fasst (MAX_RIDS ist 16)
    ("vielrid",
     bytes([0x05, 0x01, 0x09, 0x06, 0xA1, 0x01, 0x75, 0x08, 0x95, 0x01]
           + sum([[0x85, i + 1, 0x09, 0x30, 0x81, 0x02] for i in range(17)], [])
           + [0xC0]), E_RIDS),
    # mehr lokale Gebraeuche als Platz (MAX_USAGES ist 32)
    ("vielgeb",
     bytes([0x05, 0x01, 0x09, 0x06, 0xA1, 0x01] + [0x09, 0x30] * 33
           + [0x75, 0x01, 0x95, 0x01, 0x81, 0x02, 0xC0]), E_USAGE),
]



# ----------------------------------------------------------------------
# DIE BERICHTE.  Zu den Beschreibungen gehoeren Berichte -- sonst ist der
# Zerleger eine Uebung ohne Gegenstand.  Jeder Bericht hier ist VON HAND
# gebaut, mit der Bitlage aus der Beschreibung daneben, damit sich
# nachrechnen laesst, was herauskommen MUSS.


def bitset(buf, bit, wert, n=1):
    """Ein Feld von n Bit ab `bit` setzen -- HID packt von der
    niedrigsten Stelle aus."""
    for k in range(n):
        if (wert >> k) & 1:
            buf[bit // 8 + (bit % 8 + k) // 8] |= 1 << ((bit % 8 + k) % 8)
    return buf


def nkro(mods, tasten):
    """Ein Bericht der NKRO-Tastatur (Beschreibung 5, Nummer 2).
    Oktett 0 ist die Nummer, dann 8 Bit Zusatztasten (0xE0..0xE7),
    dann 120 Bit -- EIN Bit je Taste, Gebrauch 0 bis 119."""
    b = bytearray(17)
    b[0] = 2
    for m in mods:
        bitset(b, 8 + (m - 0xE0), 1)
    for u in tasten:
        bitset(b, 8 + 8 + u, 1)
    return bytes(b)


def bootkbd(mods, tasten):
    """Ein Bericht der Boot-Tastatur (Beschreibung 0, ohne Nummer):
    ein Zusatztastenoktett, ein leeres, sechs Plaetze."""
    b = bytearray(8)
    for m in mods:
        b[0] |= 1 << (m - 0xE0)
    for i, u in enumerate(tasten[:6]):
        b[2 + i] = u
    return bytes(b)


def ptp(finger, knopf=0, zeit=0):
    """Ein Bericht des Praezisions-Touchpads (Beschreibung 3, Nummer 1).

    Bitlage je Finger k, ab Bit k*40 (nachgerechnet aus der
    Beschreibung, und `tools/hid/descs.py felder` druckt sie aus):
        +0      Zuversicht        1 Bit
        +1      Spitzenschalter   1 Bit
        +2..3   Fuellbits         2 Bit
        +4..7   Kontaktnummer     4 Bit
        +8..23  X                16 Bit
        +24..39 Y                16 Bit
    Danach: Bit 200..206 Kontaktzahl (7), Bit 207 Knopf,
    Bit 208..223 Abtastzeit (16).  224 Bit = 28 Oktett, plus Nummer 29.
    """
    b = bytearray(29)
    b[0] = 1
    for k, (cid, x, y) in enumerate(finger[:5]):
        o = 8 + k * 40          # +8, weil Oktett 0 die Nummer ist
        bitset(b, o + 0, 1)     # Zuversicht
        bitset(b, o + 1, 1)     # Spitzenschalter
        bitset(b, o + 4, cid, 4)
        bitset(b, o + 8, x, 16)
        bitset(b, o + 24, y, 16)
    bitset(b, 8 + 200, len(finger[:5]), 7)
    bitset(b, 8 + 207, knopf, 1)
    bitset(b, 8 + 208, zeit, 16)
    return bytes(b)


def bootmaus(knoepfe, dx, dy):
    """Boot-Maus (Beschreibung 1, ohne Nummer): Knoepfe, dx, dy."""
    return bytes([knoepfe & 7, dx & 0xFF, dy & 0xFF])


# (Beschreibung, Bericht, Bemerkung).  Die Reihenfolge IST der Test:
# ein Touchpad wird aus zwei aufeinanderfolgenden Berichten gelesen.
BERICHTE = [
    # --- (c) MEHR ALS SECHS TASTEN GLEICHZEITIG.
    #     Acht Buchstaben (a..h = Gebrauch 4..11) in EINEM Bericht.
    #     Im Boot-Protokoll gibt es dafuer nur sechs Plaetze.
    (5, nkro([], [4, 5, 6, 7, 8, 9, 10, 11]), "acht Tasten"),
    #     zwei mehr, und Umschalt dazu: elf gleichzeitig
    (5, nkro([0xE1], [4, 5, 6, 7, 8, 9, 10, 11, 12, 13]), "elf mit Umschalt"),
    #     alles los
    (5, nkro([], []), "alles losgelassen"),
    #     die Super-Taste allein -- der Latch von kbd.fi
    (5, nkro([0xE3], []), "Super gedrueckt"),
    #     SUPER PLUS BUCHSTABE. Das ist der Regressionstest (d): in
    #     kbd.fi wird das GELATCHT und NICHT ins Fenster geliefert --
    #     "A hotkey has no window, that is what makes it global".
    #     Erwartet: eine Zeile `hk: super+a` und KEIN `key: a`.
    (5, nkro([0xE3], [4]), "Super+a"),
    (5, nkro([0xE3], []), "Super+a los"),
    (5, nkro([], []), "Super losgelassen"),
    # --- die Boot-Tastatur, ueber DENSELBEN Weg
    (0, bootkbd([], [4]), "boot: a"),
    (0, bootkbd([0xE1], [4]), "boot: Umschalt+a"),
    (0, bootkbd([], []), "boot: los"),
    #     UEBERLAUF: sechs Plaetze mit 0x01 heisst "zu viele Tasten"
    (0, bootkbd([], [1, 1, 1, 1, 1, 1]), "boot: Ueberlauf"),
    # --- die Boot-Maus
    (1, bootmaus(1, 10, 250), "maus: links, +10, -6"),
    (1, bootmaus(0, 0, 0), "maus: losgelassen"),
    # --- (f) DAS PRAEZISIONS-TOUCHPAD
    #     erster Bericht: nur merken, NICHT bewegen
    (3, ptp([(1, 1000, 800)]), "pad: aufsetzen"),
    #     +300 Einheiten in x.  Teiler 3616/1024 = 3 -> 100 Bildpunkte
    (3, ptp([(1, 1300, 800)]), "pad: +300x -> +100px"),
    #     +150 in y.  Teiler 2184/768 = 2 -> 75 Bildpunkte
    (3, ptp([(1, 1300, 950)]), "pad: +150y -> +75px"),
    #     Knopf gedrueckt
    (3, ptp([(1, 1300, 950)], knopf=1), "pad: klick"),
    (3, ptp([(1, 1300, 950)], knopf=0), "pad: klick los"),
    #     zweiter Finger dazu: der Bericht setzt nur neu auf
    (3, ptp([(1, 1300, 950), (2, 1800, 950)]), "pad: zwei Finger"),
    #     beide 120 Einheiten nach unten: EINE Radrastung
    (3, ptp([(1, 1300, 1070), (2, 1800, 1070)]), "pad: rollen"),
    #     abheben
    (3, ptp([]), "pad: abheben"),
]




# ----------------------------------------------------------------------
# EINE ACPI-TABELLE MIT ZWEI I2C-GERAETEN, gebaut nach der Spezifikation.
#
# Der Ersatzweg in kernel/i2chid.fi sucht in DSDT und SSDT nach dem
# Oktettmuster einer I2C-Verbindung.  Ob er das richtig tut, laesst sich
# ohne ein Brett mit LPSS-I2C nur so pruefen: eine Tabelle bauen, in der
# GENAU BEKANNT ist, was drinsteht, und nachsehen, ob er genau das
# findet -- und nicht mehr.
#
# I2C Serial Bus Connection Resource Descriptor (ACPI 6.x, 6.4.3.8.2.1):
#     +0   0x8E        grosser Typ, Serial Bus Connection
#     +1   Laenge, 2 Oktett (alles NACH diesen drei)
#     +3   Revision (0x01)
#     +4   Index der Ressourcenquelle
#     +5   Bustyp (0x01 = I2C)
#     +6   allgemeine Merker
#     +7   typabhaengige Merker, 2 Oktett
#     +9   typabhaengige Revision
#     +10  Laenge der Typdaten, 2 Oktett (6 bei I2C)
#     +12  Verbindungsgeschwindigkeit, 4 Oktett
#     +16  SKLAVENADRESSE, 2 Oktett
#     +18  Name der Ressourcenquelle, mit abschliessender Null


def i2c_res(adr, hz=400000, quelle=b"\\_SB.PCI0.I2C1\0"):
    kopf = bytes([0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01])
    tdl = (6).to_bytes(2, "little")
    rest = kopf + tdl + hz.to_bytes(4, "little") \
        + adr.to_bytes(2, "little") + quelle
    return bytes([0x8E]) + len(rest).to_bytes(2, "little") + rest


def acpi_tabelle(adressen, sig=b"DSDT"):
    """Eine Tabelle mit Kopf (36 Oktett) und AML-artigem Fuellwerk, in
    dem die Ressourcenvorlagen stehen.  Das Fuellwerk enthaelt absichtlich
    ein einzelnes 0x8E, das KEINE I2C-Verbindung ist -- ein Sucher, der
    nur auf das Oktett schaut, faellt daran auf."""
    koerper = bytearray()
    koerper += bytes([0x5B, 0x82, 0x30, 0x44, 0x45, 0x56, 0x30])  # Device(DEV0)
    koerper += bytes([0x08, 0x5F, 0x48, 0x49, 0x44])              # Name(_HID
    koerper += (0x500CD041).to_bytes(4, "little")                 # EisaId PNP0C50
    koerper += bytes([0x8E, 0x00, 0x00, 0xFF])   # ein 0x8E, das KEINES ist
    koerper += i2c_res(adressen[0])
    koerper += bytes([0x11, 0x22, 0x33, 0x44, 0x8E, 0x02])  # noch ein Koeder
    koerper += i2c_res(adressen[1], quelle=b"\\_SB.PCI0.I2C0\0")
    koerper += i2c_res(adressen[0])   # DIESELBE noch einmal -- darf nicht
    #                                    doppelt in die Liste
    kopf = bytearray(36)
    kopf[0:4] = sig
    kopf[4:8] = (36 + len(koerper)).to_bytes(4, "little")
    kopf[8] = 2
    kopf[10:16] = b"OSUMHD"
    t = bytes(kopf) + bytes(koerper)
    # Pruefsumme, damit die Tabelle auch als echte durchginge
    t = bytearray(t)
    t[9] = (-sum(t)) & 0xFF
    return bytes(t)


I2C_ADRESSEN = [0x2C, 0x15]
ACPI_BLOB = acpi_tabelle(I2C_ADRESSEN)


# ----------------------------------------------------------------------
# DER ZWEITE ZERLEGER.  Aus der Spezifikation, nicht aus hidrep.fi.

FL_CONST, FL_VAR = 1, 2
KIND_IN, KIND_OUT, KIND_FEAT = 1, 2, 3
MAX_FIELDS, MAX_RIDS, MAX_USAGES, MAX_DEPTH, MAX_PUSH = 64, 16, 32, 8, 8
M64 = 0xFFFFFFFFFFFFFFFF


class Fehler(Exception):
    def __init__(self, code, pos):
        self.code = code
        self.pos = pos


def sx(v, n):
    if n == 0:
        return 0
    if v & (1 << (n * 8 - 1)):
        return (v - (1 << (n * 8))) & M64
    return v


def art_von(page, usage):
    if page == 0x01 and usage == 0x06:
        return 1
    if page == 0x01 and usage == 0x02:
        return 2
    if page == 0x0D and usage in (0x04, 0x05):
        return 4
    if page == 0x0C and usage == 0x01:
        return 8
    return 0


def ausgeben(rid, kd, flags, base, rsize, rcount, page, ul, umin, umax,
             bereich, lmin, lmax):
    """EIN Hauptposten -> Liste von Feldern.  Drei Faelle, siehe hidrep.fi."""
    if rcount == 0 or rsize == 0:
        return []

    def F(off, cnt, pg, u, um):
        return {"rid": rid, "kind": kd, "flags": flags, "bitoff": off,
                "bitsz": rsize, "count": cnt, "page": pg, "usage": u,
                "umax": um, "lmin": lmin, "lmax": lmax}

    if flags & FL_CONST:
        return [F(base, rcount, page, 0, 0)]
    if not (flags & FL_VAR):
        if not bereich and ul:
            return [F(base, rcount, page, ul[0] & 0xFFFF, ul[0] & 0xFFFF)]
        return [F(base, rcount, page, umin & 0xFFFF, umax & 0xFFFF)]
    if bereich:
        return [F(base, rcount, page, umin & 0xFFFF, umax & 0xFFFF)]
    if not ul:
        return [F(base, rcount, page, 0, 0)]
    out, i = [], 0
    while i < rcount:
        if i >= len(ul):
            last = ul[-1]
            out.append(F(base + i * rsize, rcount - i,
                         (last >> 16) & 0xFFFF, last & 0xFFFF, 0))
            return out
        j = i
        while j + 1 < rcount and j + 1 < len(ul) and ul[j + 1] == ul[j] + 1:
            j += 1
        cnt = j - i + 1
        u0 = ul[i]
        out.append(F(base + i * rsize, cnt, (u0 >> 16) & 0xFFFF,
                     u0 & 0xFFFF, (u0 + cnt - 1) & 0xFFFF))
        i = j + 1
    return out


def zerlege(d):
    """(kopf, felder).  Bricht bei einer kaputten Beschreibung mit einer
    Fehlernummer ab -- und laesst stehen, was bis dahin erkannt wurde,
    genau wie kernel/hidrep.fi."""
    kopf = {"ok": 0, "err": 0, "errat": 0, "felder": 0, "rids": 0, "hasid": 0,
            "top": 0, "art": 0, "bits": 0, "posten": 0, "tiefe": 0,
            "len": len(d), "ridtab": []}
    felder = []
    if len(d) == 0 or len(d) > 1024:
        kopf["err"] = E_EMPTY
        return kopf, felder

    gl = [0] * 10   # 0 Seite 1 lmin 2 lmax 3 pmin 4 pmax
    #                 5 uexp 6 unit 7 rsize 8 rid 9 rcount
    stapel = []
    ul, umin, umax, bereich = [], 0, 0, False
    rids = []
    p, tiefe, maxd, n = 0, 0, 0, 0
    top, karte = 0, 0

    def rid_slot(r):
        for i, e in enumerate(rids):
            if e[0] == r:
                return i
        if len(rids) >= MAX_RIDS:
            return MAX_RIDS
        rids.append([r, 0, 0, 0])
        return len(rids) - 1

    def raus():
        kopf["felder"] = len(felder)
        kopf["rids"] = len(rids)
        kopf["top"] = top
        kopf["bits"] = rids[0][1] if rids else 0
        kopf["ridtab"] = rids

    try:
        while p < len(d):
            start = p
            b0 = d[p]
            p += 1
            if b0 == 0xFE:
                raise Fehler(E_LONG, start)
            bsize = b0 & 3
            if bsize == 3:
                bsize = 4
            btype = (b0 >> 2) & 3
            btag = (b0 >> 4) & 0xF
            if p + bsize > len(d):
                raise Fehler(E_TRUNC, start)
            data = 0
            for k in range(bsize):
                data |= d[p + k] << (k * 8)
            p += bsize
            n += 1

            if btype == 1:
                if btag == 0:
                    gl[0] = data & 0xFFFF
                elif btag == 1:
                    gl[1] = sx(data, bsize)
                elif btag == 2:
                    gl[2] = sx(data, bsize) if (gl[1] >> 63) else data
                elif btag == 3:
                    gl[3] = sx(data, bsize)
                elif btag == 4:
                    gl[4] = sx(data, bsize)
                elif btag in (5, 6, 7):
                    gl[btag] = data
                elif btag == 8:
                    if data == 0 or data > 255:
                        raise Fehler(E_SIZE, start)
                    gl[8] = data
                    kopf["hasid"] = 1
                elif btag == 9:
                    gl[9] = data
                elif btag == 10:
                    if len(stapel) >= MAX_PUSH:
                        raise Fehler(E_PUSH, start)
                    stapel.append(list(gl))
                elif btag == 11:
                    if not stapel:
                        raise Fehler(E_PUSH, start)
                    gl = stapel.pop()

            elif btype == 2:
                if btag == 0:
                    if len(ul) >= MAX_USAGES:
                        raise Fehler(E_USAGE, start)
                    ul.append(data if bsize == 4
                              else (gl[0] << 16) | (data & 0xFFFF))
                elif btag == 1:
                    umin = (data if bsize == 4
                            else (gl[0] << 16) | (data & 0xFFFF))
                    bereich = True
                elif btag == 2:
                    umax = (data if bsize == 4
                            else (gl[0] << 16) | (data & 0xFFFF))
                    bereich = True

            elif btype == 0:
                if btag == 0xA:
                    tiefe += 1
                    if tiefe > MAX_DEPTH:
                        raise Fehler(E_NEST, start)
                    maxd = max(maxd, tiefe)
                    if tiefe == 1:
                        tu = ul[0] if ul else (umin if bereich else 0)
                        if top == 0:
                            top = tu
                        karte |= art_von((tu >> 16) & 0xFFFF, tu & 0xFFFF)
                elif btag == 0xC:
                    if tiefe == 0:
                        raise Fehler(E_NEST, start)
                    tiefe -= 1
                elif btag in (0x8, 0x9, 0xB):
                    kd = {0x8: KIND_IN, 0x9: KIND_OUT, 0xB: KIND_FEAT}[btag]
                    rsize, rcount = gl[7], gl[9]
                    if rsize > 32:
                        raise Fehler(E_SIZE, start)
                    if rcount > 1024:
                        raise Fehler(E_SIZE, start)
                    if rsize * rcount > 4096:
                        raise Fehler(E_BIG, start)
                    slot = rid_slot(gl[8])
                    if slot >= MAX_RIDS:
                        raise Fehler(E_RIDS, start)
                    idx = kd
                    base = rids[slot][idx]
                    if base + rsize * rcount > 4096:
                        raise Fehler(E_BIG, start)
                    for e in ausgeben(gl[8], kd, data & 0xFFFF, base, rsize,
                                      rcount, gl[0], ul, umin, umax, bereich,
                                      gl[1], gl[2]):
                        if len(felder) >= MAX_FIELDS:
                            raise Fehler(E_FIELDS, start)
                        felder.append(e)
                    rids[slot][idx] = base + rsize * rcount
                ul, umin, umax, bereich = [], 0, 0, False
        if tiefe != 0:
            raise Fehler(E_NEST, len(d))
    except Fehler as f:
        kopf["err"] = f.code
        kopf["errat"] = f.pos
        raus()
        return kopf, felder

    kopf["ok"] = 1
    raus()
    kopf["art"] = karte
    kopf["posten"] = n
    kopf["tiefe"] = maxd
    return kopf, felder


# ----------------------------------------------------------------------
# Die Ausgaben.

ALLE = GUT + [(k[0], k[1]) for k in KAPUTT]


def firn():
    z = []
    a = z.append
    a("// SPDX-License-Identifier: GPL-2.0-only")
    a("// kernel/hidtest.fi -- ERZEUGT VON tools/hid/descs.py, NICHT VON HAND.")
    a("//")
    a("// Sechs ECHTE Berichtsbeschreibungen und vierzehn kaputte, gepackt zu")
    a("// je acht Oktett in ein Wort. Firn kann in einer Zeichenkette keine")
    a("// Oktette ueber 0x7F ausdruecken (dort faengt UTF-8 an), also stehen")
    a("// sie als Zahlen. Woher jede stammt und wie sie aussieht, steht in")
    a("// tools/hid/descs.py -- hier stuende es nur doppelt und waere beim")
    a("// naechsten Mal ungleich.")
    a("//")
    a("// Das Ganze kostet %d Oktett Nutzdaten im Abbild und wird NUR im"
      % sum(len(d) for _, d in ALLE))
    a("// Modus `hidrep` angesehen.")
    a("")
    a("profile kernel")
    a("")
    a("import kstate")
    a("")
    a("export { count, len_of, name_of, load, GUTE,")
    a("    bcount, bdesc, blen, bload, alen, aload }")
    a("")
    a("const N: u64 = %d" % len(ALLE))
    a("// Die ersten GUTE Beschreibungen muessen durchgehen, die uebrigen")
    a("// muessen mit einer bestimmten Fehlernummer scheitern.")
    a("const GUTE: u64 = %d" % len(GUT))
    a("")
    a("fn count() -> u64 {")
    a("    return N")
    a("}")
    a("")
    a("fn len_of(i: u64) -> u64 {")
    a("    var t: [u64; %d] = [%s]"
      % (len(ALLE), ", ".join(str(len(d)) for _, d in ALLE)))
    a("    if i >= N {")
    a("        return 0")
    a("    }")
    a("    return t[i as usize]")
    a("}")
    a("")
    a("// Der Name, acht Zeichen in EINEM Wort -- so bleibt die Meldung")
    a("// lesbar, ohne dass eine Zeichenkettentabelle noetig waere.")
    a("fn name_of(i: u64) -> u64 {")
    namen = ["0x%016X" % int.from_bytes((nm + "        ")[:8].encode("ascii"),
                                        "little") for nm, _ in ALLE]
    a("    var t: [u64; %d] = [%s]" % (len(ALLE), ", ".join(namen)))
    a("    if i >= N {")
    a("        return 0")
    a("    }")
    a("    return t[i as usize]")
    a("}")
    a("")
    offs, cur = [], 0
    for _, d in ALLE:
        offs.append(cur)
        cur += (len(d) + 7) // 8
    a("fn off_of(i: u64) -> u64 {")
    a("    var t: [u64; %d] = [%s]"
      % (len(ALLE), ", ".join(str(o) for o in offs)))
    a("    if i >= N {")
    a("        return 0")
    a("    }")
    a("    return t[i as usize]")
    a("}")
    a("")
    a("// Beschreibung `i` nach `dst` legen. Rueckgabe: die Laenge.")
    a("fn load(i: u64, dst: u64) -> u64 {")
    a("    let n: u64 = len_of(i)")
    a("    var k: u64 = 0")
    a("    while k < n {")
    a("        kstate.set8(dst + k, oktett(i, k) as u8)")
    a("        k = k + 1")
    a("    }")
    a("    return n")
    a("}")
    a("")
    a("fn oktett(i: u64, k: u64) -> u64 {")
    a("    let w: u64 = wort(off_of(i) + k / 8)")
    a("    return (w >> ((k % 8) * 8)) & 0xFF")
    a("}")
    a("")
    worte = []
    for _, d in ALLE:
        pad = d + b"\0" * ((8 - len(d) % 8) % 8)
        for k in range(0, len(pad), 8):
            worte.append(int.from_bytes(pad[k:k + 8], "little"))
    a("const NW: u64 = %d" % len(worte))
    a("")
    a("fn wort(i: u64) -> u64 {")
    a("    var t: [u64; %d] = [" % len(worte))
    for k in range(0, len(worte), 4):
        stueck = ", ".join("0x%016X" % w for w in worte[k:k + 4])
        a("        %s%s" % (stueck, "," if k + 4 < len(worte) else ""))
    a("    ]")
    a("    if i >= NW {")
    a("        return 0")
    a("    }")
    a("    return t[i as usize]")
    a("}")
    # ---------------------------------------------------------- Berichte
    a("")
    a("// ------------------------------------------------------ DIE BERICHTE")
    a("//")
    a("// Zu den Beschreibungen gehoeren Berichte, sonst ist der Zerleger eine")
    a("// Uebung ohne Gegenstand. Jeder ist von Hand gebaut, mit der Bitlage")
    a("// aus der Beschreibung daneben; was dabei herauskommen MUSS, steht in")
    a("// tools/hid/descs.py und wird von tools/hid/run.sh nachgerechnet.")
    a("const NB: u64 = %d" % len(BERICHTE))
    a("")
    a("fn bcount() -> u64 {")
    a("    return NB")
    a("}")
    a("")
    a("// Zu welcher Beschreibung dieser Bericht gehoert.")
    a("fn bdesc(i: u64) -> u64 {")
    a("    var t: [u64; %d] = [%s]"
      % (len(BERICHTE), ", ".join(str(d) for d, _, _ in BERICHTE)))
    a("    if i >= NB {")
    a("        return 0")
    a("    }")
    a("    return t[i as usize]")
    a("}")
    a("")
    a("fn blen(i: u64) -> u64 {")
    a("    var t: [u64; %d] = [%s]"
      % (len(BERICHTE), ", ".join(str(len(b)) for _, b, _ in BERICHTE)))
    a("    if i >= NB {")
    a("        return 0")
    a("    }")
    a("    return t[i as usize]")
    a("}")
    a("")
    boffs, cur = [], 0
    for _, b, _ in BERICHTE:
        boffs.append(cur)
        cur += (len(b) + 7) // 8
    a("fn boff_of(i: u64) -> u64 {")
    a("    var t: [u64; %d] = [%s]"
      % (len(BERICHTE), ", ".join(str(o) for o in boffs)))
    a("    if i >= NB {")
    a("        return 0")
    a("    }")
    a("    return t[i as usize]")
    a("}")
    a("")
    a("fn bload(i: u64, dst: u64) -> u64 {")
    a("    let n: u64 = blen(i)")
    a("    var k: u64 = 0")
    a("    while k < n {")
    a("        kstate.set8(dst + k, boktett(i, k) as u8)")
    a("        k = k + 1")
    a("    }")
    a("    return n")
    a("}")
    a("")
    a("fn boktett(i: u64, k: u64) -> u64 {")
    a("    let w: u64 = bwort(boff_of(i) + k / 8)")
    a("    return (w >> ((k % 8) * 8)) & 0xFF")
    a("}")
    a("")
    bworte = []
    for _, b, _ in BERICHTE:
        pad = b + b"\0" * ((8 - len(b) % 8) % 8)
        for k in range(0, len(pad), 8):
            bworte.append(int.from_bytes(pad[k:k + 8], "little"))
    a("const NBW: u64 = %d" % len(bworte))
    a("")
    a("fn bwort(i: u64) -> u64 {")
    a("    var t: [u64; %d] = [" % len(bworte))
    for k in range(0, len(bworte), 4):
        st = ", ".join("0x%016X" % w for w in bworte[k:k + 4])
        a("        %s%s" % (st, "," if k + 4 < len(bworte) else ""))
    a("    ]")
    a("    if i >= NBW {")
    a("        return 0")
    a("    }")
    a("    return t[i as usize]")
    a("}")
    a("")
    a("// ------------------------------------ EINE GEBAUTE ACPI-TABELLE")
    a("//")
    a("// Mit GENAU zwei I2C-Verbindungen (Adressen %s) und drei"
      % ", ".join("0x%02X" % x for x in I2C_ADRESSEN))
    a("// Koedern, die wie eine aussehen und keine sind. Der Ersatzweg in")
    a("// i2chid.fi muss genau die zwei finden -- die dritte Vorlage ist")
    a("// eine WIEDERHOLUNG der ersten und darf nicht doppelt zaehlen.")
    a("const AN: u64 = %d" % len(ACPI_BLOB))
    a("")
    a("fn alen() -> u64 {")
    a("    return AN")
    a("}")
    a("")
    a("fn aload(dst: u64) -> u64 {")
    a("    var k: u64 = 0")
    a("    while k < AN {")
    a("        kstate.set8(dst + k, aoktett(k) as u8)")
    a("        k = k + 1")
    a("    }")
    a("    return AN")
    a("}")
    a("")
    a("fn aoktett(k: u64) -> u64 {")
    a("    return (awort(k / 8) >> ((k % 8) * 8)) & 0xFF")
    a("}")
    a("")
    ablob = ACPI_BLOB + b"\0" * ((8 - len(ACPI_BLOB) % 8) % 8)
    aworte = [int.from_bytes(ablob[k:k + 8], "little")
              for k in range(0, len(ablob), 8)]
    a("const NAW: u64 = %d" % len(aworte))
    a("")
    a("fn awort(i: u64) -> u64 {")
    a("    var t: [u64; %d] = [" % len(aworte))
    for k in range(0, len(aworte), 4):
        st = ", ".join("0x%016X" % w for w in aworte[k:k + 4])
        a("        %s%s" % (st, "," if k + 4 < len(aworte) else ""))
    a("    ]")
    a("    if i >= NAW {")
    a("        return 0")
    a("    }")
    a("    return t[i as usize]")
    a("}")
    print("\n".join(z))


def kopf_zeilen():
    out = []
    for i, (nm, d) in enumerate(ALLE):
        k, _ = zerlege(d)
        out.append("hidrep: dev=%d ok=%d err=%d errat=%d felder=%d rids=%d "
                   "hasid=%d top=0x%x art=%d bits=%d posten=%d tiefe=%d"
                   % (i, k["ok"], k["err"], k["errat"], k["felder"], k["rids"],
                      k["hasid"], k["top"], k["art"], k["bits"], k["posten"],
                      k["tiefe"]))
    return out


def feld_zeilen():
    out = []
    for i, (nm, d) in enumerate(ALLE):
        k, f = zerlege(d)
        if not k["ok"]:
            continue
        for j, e in enumerate(f):
            out.append("hidf: %d %d rid=%d art=%d mrk=0x%x bit=%d gr=%d anz=%d "
                       "seite=0x%x geb=0x%x gmax=0x%x lmin=0x%x lmax=0x%x"
                       % (i, j, e["rid"], e["kind"], e["flags"], e["bitoff"],
                          e["bitsz"], e["count"], e["page"], e["usage"],
                          e["umax"], e["lmin"] & M64, e["lmax"] & M64))
    return out


def nr_von(marke):
    """Die Nummer des Berichts mit dieser Bemerkung.  tools/hid/run.sh
    holt sie SO und schreibt sie nicht hin -- als in dieser Runde zwei
    Berichte fuer die Super-Taste dazukamen, verschoben sich alle
    folgenden Nummern, und drei Zusagen fielen, obwohl am Kernel nichts
    falsch war."""
    for i, (_, _, k) in enumerate(BERICHTE):
        if k == marke:
            return i
    raise SystemExit("kein Bericht mit der Bemerkung %r" % marke)


def main():
    was = sys.argv[1] if len(sys.argv) > 1 else "kopf"
    if was == "nr":
        print(nr_von(sys.argv[2]))
        return 0
    if was == "firn":
        firn()
    elif was == "kopf":
        print("\n".join(kopf_zeilen()))
    elif was == "felder":
        print("\n".join(feld_zeilen()))
    elif was == "fehler":
        schlecht = 0
        for nm, d, e in KAPUTT:
            k, _ = zerlege(d)
            gut = (e == k["err"] and k["ok"] == 0)
            schlecht += 0 if gut else 1
            print("%-10s erwartet=%2d bekommen=%2d %s"
                  % (nm, e, k["err"], "ok" if gut else "FALSCH"))
        return 1 if schlecht else 0
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
