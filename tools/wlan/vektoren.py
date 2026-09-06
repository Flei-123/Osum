#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/wlan/vektoren.py -- die Rechnung der Runde WLAN gegen ihre Normen.

WARUM DAS DIE ERSTE DATEI IST, DIE DIESE RUNDE GEBAUT HAT (nach dem
Befund). Es gibt in dieser Runde nichts, was sich in QEMU messen liesse
-- QEMU hat kein 802.11-Geraet, gemessen und in `docs/WLAN-BEFUND.md`
Abschnitt 5 belegt. Alles, was hier gebaut wurde, ist deshalb so
gebaut, dass es sich AUF DEM WIRT messen laesst, gegen dieselben
Firn-Quelltexte, die der Kern spaeter bindet (`.probe/worakel`,
gebaut aus `tools/wlan/orakel.fi`).

VIER ARTEN VON VERGLEICH, absteigend nach Beweiskraft:

 1. GEGEN EINE ECHTE AUFZEICHNUNG. `tools/wlan/mitschnitt.txt` enthaelt
    Rahmen aus `wpa-Induction.pcap` -- einem echten WPA2-PSK-Netz mit
    bekanntem Passwort. Daran haengt die staerkste Zusage dieser Runde:
    aus dem Passwort `Induction` und dem Namen `Coherer` wird ein PMK,
    daraus mit den beiden Zufallszahlen des ECHTEN Handschlags ein PTK,
    und mit dessen KCK stimmen die Pruefwerte, die der ECHTE
    Zugangspunkt und der ECHTE Rechner damals gerechnet haben, Oktett
    fuer Oktett -- und mit dessen TK lassen sich die ECHTEN
    Datenrahmen entschluesseln. Wenn das stimmt, stimmt die ganze
    Kette, und zwar gegen die Wirklichkeit und nicht gegen eine
    Meinung.

 2. GEGEN DIE VEROEFFENTLICHTEN VEKTOREN DER NORMEN. FIPS 197 (AES),
    RFC 4493 (CMAC), RFC 3394 (Key Wrap), RFC 6070 (PBKDF2), die
    PRF-Vektoren aus IEEE 802.11i und die CCMP-Vektoren aus IEEE Std
    802.11-2012 M.6.4 und M.9.2. Bei jedem steht, woher er kommt.

 3. GEGEN EINE ZWEITE, UNABHAENGIGE UMSETZUNG. Pythons `hashlib`,
    `hmac` und `cryptography` (OpenSSL darunter) ueber erzeugte
    Eingaben. Das faengt die Laengen- und Randfaelle, die keine Norm
    druckt.

 4. GEGEN EIGENSCHAFTEN. Der Zustandsautomat wird nicht mit einer
    Liste erwarteter Ausgaben verglichen, sondern erschoepfend
    durchsucht: JEDE Ereignisfolge bis Laenge 4, und dazu jede
    Verstuemmelung der richtigen Folge. Die Zusage ist eine
    Eigenschaft -- "es gibt keine halbe Verbindung" -- und keine
    Tabelle.

UND DIE NEGATIVE HAELFTE, ohne die nichts davon etwas wert ist: zu
jedem Pruefwert ein gekipptes Bit mit der Antwort NEIN, zu jedem
Laengenfeld eine Luege mit der Antwort FAIL.

    ./tools/wlan/vektoren.py            alles
    ./tools/wlan/vektoren.py --schnell  ohne die langen Schleifen
"""
import hashlib
import hmac as pyhmac
import os
import subprocess
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.path.dirname(os.path.dirname(HIER))
ORAKEL = os.path.join(WURZEL, ".probe", "worakel")
MITSCHNITT = os.path.join(HIER, "mitschnitt.txt")

SCHNELL = "--schnell" in sys.argv

pass_n = 0
fail_n = 0


def ok(text):
    global pass_n
    pass_n += 1
    print("  OK    %s" % text)


def bad(text):
    global fail_n
    fail_n += 1
    print("  FAIL  %s" % text)


def gleich(name, ist, soll):
    if ist == soll:
        ok("%s: %s" % (name, ist if len(str(ist)) < 60 else str(ist)[:57] + "..."))
    else:
        bad("%s: '%s', erwartet '%s'" % (name, ist, soll))


# ------------------------------------------------------------ das Orakel

def orakel(zeilen):
    """Eine Liste von Befehlszeilen hinein, eine Liste von Antworten heraus."""
    eingabe = ("\n".join(zeilen) + "\n").encode()
    p = subprocess.run([ORAKEL], input=eingabe, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE)
    if p.returncode != 0:
        bad("das Orakel ist mit Code %d ausgestiegen" % p.returncode)
        return ["ABSTURZ"] * len(zeilen)
    aus = p.stdout.decode(errors="replace").split("\n")
    while aus and aus[-1] == "":
        aus.pop()
    if len(aus) != len(zeilen):
        bad("das Orakel gab %d Zeilen auf %d Fragen" % (len(aus), len(zeilen)))
        while len(aus) < len(zeilen):
            aus.append("FEHLT")
    return aus


def eins(zeile):
    return orakel([zeile])[0]


def h(b):
    return b.hex() if b else "-"


# ============================================================ 1. SHA-1

def teil_sha1():
    print("== 1. SHA-1, HMAC-SHA1, PRF und PBKDF2 ==")
    # FIPS 180-4, die zwei Beispiele aus dem Dokument selbst.
    gleich("SHA-1(\"abc\")", eins("sha1 " + h(b"abc")),
           "a9993e364706816aba3e25717850c26c9cd0d89d")
    lang = b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
    gleich("SHA-1(56 Oktette, FIPS 180-4)", eins("sha1 " + h(lang)),
           "84983e441c3bd26ebaae4aa1f95129e5e54670f1")
    gleich("SHA-1(leer)", eins("sha1 -"),
           "da39a3ee5e6b4b0d3255bfef95601890afd80709")

    # Gegen hashlib ueber alle Laengen um die Blockgrenzen herum. Genau
    # dort sitzt die Auffuellung, und genau dort sitzen die Fehler.
    laengen = list(range(0, 200)) if not SCHNELL else [0, 1, 55, 56, 63, 64, 65, 119, 120, 128]
    fragen = []
    sollen = []
    for n in laengen:
        m = bytes((i * 37 + n) & 255 for i in range(n))
        fragen.append("sha1 " + h(m))
        sollen.append(hashlib.sha1(m).hexdigest())
    antworten = orakel(fragen)
    schlecht = [i for i in range(len(fragen)) if antworten[i] != sollen[i]]
    if schlecht:
        bad("SHA-1 gegen hashlib: %d von %d falsch, erste Laenge %d"
            % (len(schlecht), len(fragen), laengen[schlecht[0]]))
    else:
        ok("SHA-1 gegen Pythons hashlib: %d Laengen von %d bis %d, alle gleich"
           % (len(laengen), laengen[0], laengen[-1]))

    # HMAC, auch mit einem Schluessel LAENGER als der Block -- das ist
    # die eine Stelle, an der HMAC anders rechnet.
    fragen = []
    sollen = []
    for kl in [0, 1, 20, 63, 64, 65, 100, 200]:
        for ml in [0, 1, 64, 200]:
            k = bytes((i * 11 + kl) & 255 for i in range(kl))
            m = bytes((i * 7 + ml) & 255 for i in range(ml))
            fragen.append("hmacsha1 %s %s" % (h(k), h(m)))
            sollen.append(pyhmac.new(k, m, hashlib.sha1).hexdigest())
    antworten = orakel(fragen)
    if antworten == sollen:
        ok("HMAC-SHA1 gegen Pythons hmac: %d Faelle, auch Schluessel > 64 Oktette"
           % len(fragen))
    else:
        i = [j for j in range(len(fragen)) if antworten[j] != sollen[j]][0]
        bad("HMAC-SHA1: Fall %d falsch (%s statt %s)" % (i, antworten[i], sollen[i]))

    # ---- PRF-SHA1, IEEE 802.11i 8.5.1.1 ----
    #
    # HERKUNFT: hostapd 2.10, src/crypto/crypto_module_tests.c, die
    # Werte key0/data0/prf0, key1/data1/prf1, key2/data2/prf2 (dort
    # "PRF-SHA1 test cases"). Sie stammen aus dem 802.11i-Entwurf.
    prf_faelle = [
        (bytes([0x0b] * 20), b"Hi There",
         "bcd4c650b30b9684951829e0d75f9d54b862175ed9f00606e17d8da3"
         "5402ffee75df78c3d31e0f889f012120c0862beb67753e7439ae242e"
         "db837369835 6cf5a".replace(" ", "")),
        (b"Jefe", b"what do ya want for nothing?",
         "51f4de5b33f249adf81aeb713a3c20f4fe631446fabdfa58244759ae"
         "58ef9009a99abf4eac2ca5fa87e692c440eb40023e7babb206d61de7"
         "b92f41529092b8fc"),
        (bytes([0xaa] * 20), bytes([0xdd] * 50),
         "e1ac546ec4cb636f9976487be5c86be17a0252ca5d8d8df12cfb0473"
         "525249ce9dd8d177ead710bc9b590547239107aef7b4abd43d87f0a6"
         "8f1cbd9e2b6f7607"),
    ]
    for i, (key, data, soll) in enumerate(prf_faelle):
        soll = soll.replace(" ", "")
        antwort = eins("prf %s %s %s %d" % (h(key), h(b"prefix"), h(data),
                                            len(soll) // 2))
        gleich("PRF-SHA1, IEEE-802.11i-Vektor %d (aus hostapd 2.10)" % i,
               antwort, soll)

    # ---- PBKDF2-HMAC-SHA1, RFC 6070 ----
    for pw, salt, c, soll in [
        (b"password", b"salt", 1, "0c60c80f961f0e71f3a9b524af6012062fe037a6"),
        (b"password", b"salt", 2, "ea6c014dc72d6f8ccd1ed92ace1d41f0d8de8957"),
        (b"password", b"salt", 4096, "4b007901b765489abead49d926f721d065a429c1"),
        (b"passwordPASSWORDpassword",
         b"saltSALTsaltSALTsaltSALTsaltSALTsalt", 4096,
         "3d2eec4fe41c849b80c8d83662c0e44a8b291a964cf2f07038"),
    ]:
        antwort = eins("pbkdf2 %s %s %d %d" % (h(pw), h(salt), c, len(soll) // 2))
        gleich("PBKDF2-SHA1, RFC 6070, c=%d" % c, antwort, soll)

    # ---- PMK aus Passwort und SSID, IEEE 802.11i Anhang H.4 ----
    #
    # HERKUNFT: hostapd 2.10, passphrase_tests[].
    for pw, ssid, soll in [
        (b"password", b"IEEE",
         "f42c6fc52df0ebef9ebb4b90b38a5f902e83fe1b135a70e23aed762e9710a12e"),
        (b"ThisIsAPassword", b"ThisIsASSID",
         "0dc0d6eb90555ed6419756b9a15ec3e3209b63df707dd508d14581f8982721af"),
        (b"a" * 32, b"Z" * 32,
         "becb93866bb8c3832cb777c2f559807c8c59afcb6eae7348850013 00a981cc62"
         .replace(" ", "")),
    ]:
        antwort = eins("pmk %s %s" % (h(pw), h(ssid)))
        gleich("PMK aus Passwort und SSID (%s)" % ssid.decode(), antwort, soll)

    # Die negative Haelfte: ein Passwort, das die Norm nicht zulaesst.
    gleich("ein Passwort mit 7 Zeichen wird ABGELEHNT",
           eins("pmk %s %s" % (h(b"1234567"), h(b"Netz"))), "FAIL")
    gleich("ein Passwort mit 64 Zeichen wird ABGELEHNT",
           eins("pmk %s %s" % (h(b"x" * 64), h(b"Netz"))), "FAIL")
    gleich("eine SSID mit 33 Oktetten wird ABGELEHNT",
           eins("pmk %s %s" % (h(b"passwort"), h(b"y" * 33))), "FAIL")


# ============================================================ 2. AES

def teil_aes():
    print()
    print("== 2. AES, CMAC, Key Wrap und CCM ==")
    # FIPS 197, Anhang C. Ein Klartext, drei Schluessellaengen.
    pt = bytes(range(0x00, 0x100, 0x11))
    for kl, soll in [
        (16, "69c4e0d86a7b0430d8cdb78070b4c55a"),
        (24, "dda97ca4864cdfe06eaf70a0ec0d7191"),
        (32, "8ea2b7ca516745bfeafc49904b496089"),
    ]:
        key = bytes(range(kl))
        gleich("AES-%d, FIPS 197 Anhang C" % (kl * 8),
               eins("aesenc %s %s" % (h(key), h(pt))), soll)
        gleich("AES-%d rueckwaerts, FIPS 197 Anhang C" % (kl * 8),
               eins("aesdec %s %s" % (h(key), bytes.fromhex(soll).hex())),
               pt.hex())
    gleich("ein Schluessel mit 20 Oktetten wird ABGELEHNT",
           eins("aesenc %s %s" % (h(b"x" * 20), h(pt))), "FAIL")

    # Gegen OpenSSL ueber erzeugte Bloecke.
    try:
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
        have_crypto = True
    except ImportError:
        have_crypto = False
    if have_crypto:
        fragen = []
        sollen = []
        anzahl = 20 if SCHNELL else 200
        for i in range(anzahl):
            kl = [16, 24, 32][i % 3]
            key = hashlib.sha256(b"k%d" % i).digest()[:kl]
            blk = hashlib.sha256(b"b%d" % i).digest()[:16]
            c = Cipher(algorithms.AES(key), modes.ECB())
            fragen.append("aesenc %s %s" % (h(key), h(blk)))
            sollen.append(c.encryptor().update(blk).hex())
        if orakel(fragen) == sollen:
            ok("AES gegen OpenSSL: %d Bloecke ueber alle drei Schluessellaengen"
               % anzahl)
        else:
            bad("AES gegen OpenSSL: mindestens ein Block falsch")

    # ---- AES-CMAC, RFC 4493 Abschnitt 4 ----
    k = bytes.fromhex("2b7e151628aed2a6abf7158809cf4f3c")
    m = bytes.fromhex("6bc1bee22e409f96e93d7e117393172a"
                      "ae2d8a571e03ac9c9eb76fac45af8e51"
                      "30c81c46a35ce411e5fbc1191a0a52ef"
                      "f69f2445df4f9b17ad2b417be66c3710")
    for n, soll in [
        (0, "bb1d6929e95937287fa37d129b756746"),
        (16, "070a16b46b4d4144f79bdd9dd04a287c"),
        (40, "dfa66747de9ae63030ca32611497c827"),
        (64, "51f0bebf7e3b9d92fc4974177936 3cfe".replace(" ", "")),
    ]:
        gleich("AES-CMAC, RFC 4493, Beispiel mit %d Oktetten" % n,
               eins("cmac %s %s" % (h(k), h(m[:n]))), soll)

    # ---- AES Key Wrap, RFC 3394 Abschnitt 4 ----
    for kek_l, pl, soll in [
        (16, 16, "1fa68b0a8112b447aef34bd8fb5a7b829d3e862371d2cfe5"),
        (24, 16, "96778b25ae6ca435f92b5b97c050aed2468ab8a17ad84e5d"),
        (32, 16, "64e8c3f9ce0f5ba263e977790581 8a2a93c8191e7d6e8ae7".replace(" ", "")),
        (24, 24, "031d33264e15d33268f24ec260743edce1c6c7ddee725a936ba814915c6762d2"),
        (32, 24, "a8f9bc1612c68b3ff6e6f4fbe30e71e4769c8b80a32cb8958cd5d17d6b254da1"),
        (32, 32, "28c9f404c4b810f4cbccb35cfb87f8263f5786e2d80ed326"
                 "cbc7f0e71a99f43bfb988b9b7a02dd21"),
    ]:
        kek = bytes(range(kek_l))
        plain = bytes.fromhex("00112233445566778899aabbccddeeff"
                              "000102030405060708090a0b0c0d0e0f")[:pl]
        gleich("Key Wrap, RFC 3394, KEK %d Bit / %d Oktette Inhalt"
               % (kek_l * 8, pl),
               eins("wrap %s %s" % (h(kek), h(plain))), soll)
        gleich("und wieder ausgepackt",
               eins("unwrap %s %s" % (h(kek), soll)), plain.hex())
    # Negativ: ein gekipptes Bit muss das Auspacken zum Scheitern
    # bringen. Ohne diese Zusage waere der Anfangswert A6A6... nutzlos.
    kek = bytes(range(16))
    gut = "1fa68b0a8112b447aef34bd8fb5a7b829d3e862371d2cfe5"
    b = bytearray.fromhex(gut)
    b[0] ^= 1
    gleich("Key Wrap: ein gekipptes Bit im Paket -> ABGELEHNT",
           eins("unwrap %s %s" % (h(kek), bytes(b).hex())), "FAIL")
    kek2 = bytearray(kek)
    kek2[15] ^= 1
    gleich("Key Wrap: ein falscher Schluessel -> ABGELEHNT",
           eins("unwrap %s %s" % (h(bytes(kek2)), gut)), "FAIL")
    gleich("Key Wrap: 8 Oktette Inhalt sind zu wenig -> ABGELEHNT",
           eins("wrap %s %s" % (h(kek), h(b"12345678"))), "FAIL")

    # ---- CCM gegen OpenSSL ----
    if have_crypto:
        from cryptography.hazmat.primitives.ciphers.aead import AESCCM
        fragen = []
        sollen = []
        faelle = []
        anzahl = 12 if SCHNELL else 120
        for i in range(anzahl):
            key = hashlib.sha256(b"ck%d" % i).digest()[:16]
            nlen = 7 + (i % 7)
            nonce = hashlib.sha256(b"cn%d" % i).digest()[:nlen]
            alen = i % 40
            aad = hashlib.sha256(b"ca%d" % i).digest()[:32] * 2
            aad = aad[:alen]
            mlen = (i * 13) % 200
            msg = bytes((j * 5 + i) & 255 for j in range(mlen))
            tl = [4, 6, 8, 10, 12, 14, 16][i % 7]
            c = AESCCM(key, tag_length=tl)
            soll = c.encrypt(nonce, msg, aad if alen else None).hex()
            fragen.append("ccmenc %s %s %s %s %d"
                          % (h(key), h(nonce), h(aad), h(msg), tl))
            sollen.append(soll)
            faelle.append((key, nonce, aad, msg, tl, soll))
        antworten = orakel(fragen)
        if antworten == sollen:
            ok("AES-CCM gegen OpenSSL: %d Faelle, Nonce 7..13, Pruefwert 4..16, "
               "Nachricht 0..199" % anzahl)
        else:
            i = [j for j in range(len(fragen)) if antworten[j] != sollen[j]][0]
            bad("AES-CCM: Fall %d falsch" % i)
        # zurueck, und einmal mit gekipptem Bit
        fragen = []
        sollen = []
        for key, nonce, aad, msg, tl, ct in faelle:
            fragen.append("ccmdec %s %s %s %s %d"
                          % (h(key), h(nonce), h(aad), ct, tl))
            sollen.append(msg.hex() if msg else "-")
        if orakel(fragen) == sollen:
            ok("AES-CCM zurueck: dieselben %d Faelle, Klartext gleich" % anzahl)
        else:
            bad("AES-CCM zurueck: mindestens ein Fall falsch")
        fragen = []
        for key, nonce, aad, msg, tl, ct in faelle:
            b = bytearray.fromhex(ct)
            b[-1] ^= 1
            fragen.append("ccmdec %s %s %s %s %d"
                          % (h(key), h(nonce), h(aad), bytes(b).hex(), tl))
        antworten = orakel(fragen)
        if all(a == "FAIL" for a in antworten):
            ok("AES-CCM: ein gekipptes Bit im Pruefwert -> alle %d ABGELEHNT"
               % anzahl)
        else:
            bad("AES-CCM: %d von %d Faelschungen wurden ANGENOMMEN"
                % (sum(1 for a in antworten if a != "FAIL"), anzahl))
        # und eines in den zusaetzlichen Daten
        fragen = []
        n = 0
        for key, nonce, aad, msg, tl, ct in faelle:
            if not aad:
                continue
            b = bytearray(aad)
            b[0] ^= 1
            fragen.append("ccmdec %s %s %s %s %d"
                          % (h(key), h(nonce), h(bytes(b)), ct, tl))
            n += 1
        if n:
            antworten = orakel(fragen)
            if all(a == "FAIL" for a in antworten):
                ok("AES-CCM: ein gekipptes Bit in den ZUSAETZLICHEN Daten "
                   "-> alle %d ABGELEHNT" % n)
            else:
                bad("AES-CCM: veraenderte zusaetzliche Daten wurden angenommen")


# ============================================================ 3. CCMP

# HERKUNFT dieser beiden Vektoren: IEEE Std 802.11-2012, Anhaenge M.6.4
# und M.9.2. Eingang und Ausgang sind mit `wlantest/test_vectors` aus
# `hostap.git` nachgerechnet worden -- also mit einem Programm, das
# dieses Repository nicht geschrieben hat.
CCMP_VEKTOREN = [
    ("IEEE Std 802.11-2012 M.6.4, Datenrahmen",
     "c97c1f67ce371185514a8a19f2bdd52f",
     "b5039776e70c",
     "0848c32c0fd2e128a57c5030f1844408abaea5b8fcba8033"
     "f8ba1a55d02f85ae967bb62fb6cda8eb7e78a050",
     "0848c32c0fd2e128a57c5030f1844408abaea5b8fcba8033"
     "0ce70020769703b5"
     "f3d0a2fe9a3dbf2342a643e43246e80c3c04d019"
     "7845ce0b16f97623"),
    ("IEEE Std 802.11-2012 M.9.2, geschuetzter Deauth-Rahmen",
     "66ed21042f9f26d7115706e40414cf2e",
     "000000000001",
     "c00000000200000001000200000000000200000000006000"
     "0200",
     "c04000000200000001000200000000000200000000006000"
     "0100002000000000"
     "1d07"
     "cafd0409bb8bafef"),
]


def teil_ccmp():
    print()
    print("== 3. CCMP: Nonce, zusaetzliche Daten, ganze MPDU ==")
    for name, tk, pn, klar, geschuetzt in CCMP_VEKTOREN:
        gleich("%s -- schuetzen" % name,
               eins("ccmpenc %s %s %s" % (tk, pn, klar)), geschuetzt)
        # `unprotect` gibt einen KLARTEXTrahmen zurueck und loescht
        # dabei das Schutzkennzeichen. Der Vektor druckt den Kopf so,
        # wie er in die Verschluesselung ging -- bei M.6.4 mit
        # gesetztem Kennzeichen, bei M.9.2 ohne. Verglichen wird
        # deshalb gegen den Klartext MIT GELOESCHTEM Kennzeichen.
        kb = bytearray.fromhex(klar)
        kb[1] &= ~0x40
        gleich("%s -- entschuetzen" % name,
               eins("ccmpdec %s %s" % (tk, geschuetzt)), bytes(kb).hex())
        # Jedes einzelne Oktett kippen und nachsehen, dass es auffaellt.
        # Das ist die Zusage, die CCMP von "verschleiert" zu
        # "gesichert" macht -- und sie gilt fuer den KOPF genauso wie
        # fuer den Inhalt, weil der Kopf in den zusaetzlichen Daten
        # steckt.
        roh = bytearray.fromhex(geschuetzt)
        fragen = []
        stellen = list(range(len(roh)))
        for i in stellen:
            b = bytearray(roh)
            b[i] ^= 0x01
            fragen.append("ccmpdec %s %s" % (tk, bytes(b).hex()))
        antworten = orakel(fragen)
        durch = set(i for i, a in enumerate(antworten) if a != "FAIL")
        # DIE STELLEN, DIE CCMP NICHT SICHERT, und zwar nach dem Text
        # der Norm und nicht aus Versehen. Sie stehen hier namentlich,
        # weil die Aussage "CCMP sichert den Rahmen" sonst mehr
        # verspricht, als sie haelt:
        #
        #   2, 3    Duration/ID. Steht NICHT in den zusaetzlichen
        #           Daten (IEEE 802.11-2016 12.5.3.3.3 zaehlt auf, was
        #           hineingeht: Frame Control, A1, A2, A3,
        #           Sequence Control, gegebenenfalls A4 und QoS --
        #           Duration ist nicht dabei). Ein Vermittler darf sie
        #           veraendern.
        #   23      das obere Oktett von Sequence Control, also die
        #           Folgenummer. Nur die Bruchstuecknummer (die
        #           unteren vier Bit von Oktett 22) wird gesichert.
        #   26      das vorbehaltene Oktett des CCMP-Kopfes.
        #   27      die unteren Bits des Schluesselnummer-Oktetts.
        #           Gesichert ist davon gar nichts; nur Bit 5 (ExtIV)
        #           wird ueberhaupt geprueft.
        #
        # Wer eine dieser Stellen aendert, aendert den Rahmen, ohne
        # dass es auffaellt. Das ist eine EIGENSCHAFT VON CCMP und
        # keine Schwaeche dieser Umsetzung -- und deshalb steht sie
        # hier als Zusage und nicht als Fussnote.
        kopf = 24
        erwartet_frei = {2, 3, 23, kopf + 2, kopf + 3}
        if durch == erwartet_frei:
            ok("%s -- von %d Oktetten fallen alle auf ausser genau den "
               "fuenf, die die Norm nicht sichert (Duration, Folgenummer, "
               "die zwei Kopffelder)" % (name, len(fragen)))
        else:
            zuviel = sorted(durch - erwartet_frei)
            zuwenig = sorted(erwartet_frei - durch)
            bad("%s -- unbemerkt geblieben, obwohl gesichert: %s; "
                "aufgefallen, obwohl ungesichert: %s"
                % (name, zuviel, zuwenig))
        # UND DIE ANDERE HAELFTE DERSELBEN AUSSAGE, die genauso
        # dastehen muss: es gibt Bits, die die Norm AUSDRUECKLICH aus
        # der Sicherung herausnimmt, weil ein Vermittler sie unterwegs
        # setzen darf. Wer die kippt, faellt NICHT auf -- und das ist
        # kein Fehler, sondern der Text der Norm (IEEE 802.11-2016
        # 12.5.3.3.3). Damit niemand spaeter glaubt, CCMP sichere den
        # ganzen Kopf, stehen sie hier namentlich.
        frei = [(1, 0x08, "Wiederholung"), (1, 0x10, "Stromsparen"),
                (1, 0x20, "weitere Daten")]
        fragen = []
        for okt, bit, _ in frei:
            b = bytearray(roh)
            b[okt] ^= bit
            fragen.append("ccmpdec %s %s" % (tk, bytes(b).hex()))
        antworten = orakel(fragen)
        durch = [frei[i][2] for i, a in enumerate(antworten) if a != "FAIL"]
        if len(durch) == len(frei):
            ok("%s -- und die drei von der Norm AUSGENOMMENEN Bits "
               "(%s) gehen erwartungsgemaess durch"
               % (name, ", ".join(durch)))
        else:
            bad("%s -- die ausgenommenen Bits verhalten sich anders als "
                "die Norm sagt: %s" % (name, antworten))
        # Ein falscher Schluessel.
        b = bytearray.fromhex(tk)
        b[0] ^= 1
        gleich("%s -- falscher Schluessel -> ABGELEHNT" % name,
               eins("ccmpdec %s %s" % (bytes(b).hex(), geschuetzt)), "FAIL")
        # Ein abgeschnittener Rahmen.
        gleich("%s -- um ein Oktett gekuerzt -> ABGELEHNT" % name,
               eins("ccmpdec %s %s" % (tk, geschuetzt[:-2])), "FAIL")

    # Der Rahmen ohne das Kennzeichen "geschuetzt" darf nicht
    # entschuesselt werden -- sonst koennte ein Angreifer einen
    # Klartextrahmen als Schluesseltext ausgeben.
    name, tk, pn, klar, geschuetzt = CCMP_VEKTOREN[0]
    b = bytearray.fromhex(geschuetzt)
    b[1] = b[1] & 0xBF
    gleich("ein Rahmen OHNE Schutzkennzeichen wird nicht entschluesselt",
           eins("ccmpdec %s %s" % (tk, bytes(b).hex())), "FAIL")
    # Das ExtIV-Bit fehlt -> kein CCMP-Kopf.
    b = bytearray.fromhex(geschuetzt)
    b[24 + 3] = b[24 + 3] & 0xDF
    gleich("ein CCMP-Kopf ohne ExtIV-Bit wird ABGELEHNT",
           eins("ccmpdec %s %s" % (tk, bytes(b).hex())), "FAIL")


# ============================================== 4. die echte Aufzeichnung

def lies_mitschnitt():
    daten = {}
    liste = {}
    with open(MITSCHNITT, encoding="utf-8") as f:
        for zeile in f:
            zeile = zeile.strip()
            if not zeile or zeile.startswith("#"):
                continue
            k, _, v = zeile.partition(" ")
            if k in ("beacon", "daten", "beacon_db"):
                liste.setdefault(k, []).append(v)
            else:
                daten[k] = v
    daten.update(liste)
    return daten


def prf_sha1(key, label, data, n):
    r = b""
    i = 0
    while len(r) < n:
        r += pyhmac.new(key, label + b"\x00" + data + bytes([i]),
                        hashlib.sha1).digest()
        i += 1
    return r[:n]


def teil_mitschnitt():
    print()
    print("== 4. gegen eine ECHTE Aufzeichnung (wpa-Induction.pcap) ==")
    m = lies_mitschnitt()

    # ---- die Beacons ----
    for i, b in enumerate(m["beacon"]):
        antwort = eins("beacon " + b)
        felder = dict(x.split("=", 1) for x in antwort.split(" "))
        if i == 0:
            gleich("Beacon 1: SSID", bytes.fromhex(felder["ssid"]).decode(),
                   "Coherer")
            gleich("Beacon 1: Kanal", felder["kanal"], "1")
            gleich("Beacon 1: Band (aus der Kanalnummer geschlossen)",
                   felder["band"], "1")
            # sich=3 ist WPA2 (RSN mit PSK, kein SAE)
            gleich("Beacon 1: Sicherheitsart WPA2", felder["sich"], "3")
            # paar=4 ist CCMP-128, gruppe=2 ist TKIP -- so steht es im
            # RSN-Element dieses Netzes wirklich drin.
            gleich("Beacon 1: Paarchiffre CCMP-128", felder["paar"], "4")
            gleich("Beacon 1: Gruppenchiffre TKIP (so steht es im Netz)",
                   felder["gruppe"], "2")
            gleich("Beacon 1: Anmeldeverfahren PSK", felder["akm"], "2")
            gleich("Beacon 1: kein Verwaltungsrahmenschutz", felder["pmf"], "0")
            gleich("Beacon 1: Intervall 100 Zeiteinheiten", felder["intv"], "100")
            gleich("Beacon 1: BSSID", felder["bssid"], "000c4182b255")
            gleich("Beacon 1: SSID nicht verborgen", felder["verbrg"], "0")
        else:
            if felder["ssid"] == b"Coherer".hex() and felder["kanal"] == "1":
                ok("Beacon %d desselben Netzes: SSID und Kanal gleich" % (i + 1))
            else:
                bad("Beacon %d weicht ab: %s" % (i + 1, antwort))
    # Die Kette der Informationselemente, roh.
    gleich("Beacon 1: die Kette der Informationselemente",
           eins("ies " + m["beacon"][0]),
           "0:7 1:8 3:1 5:4 42:1 47:1 48:24 50:4 221:6 221:28")
    if "probeantwort" in m:
        antwort = eins("beacon " + m["probeantwort"])
        felder = dict(x.split("=", 1) for x in antwort.split(" "))
        gleich("eine Probe Response wird wie ein Beacon gelesen",
               bytes.fromhex(felder["ssid"]).decode(), "Coherer")
    # Die Signalstaerke steht NICHT im Rahmen -- sie kommt aus dem
    # Radiotap-Kopf der Aufzeichnung, so wie sie ein Treiber aus dem
    # Empfangsdeskriptor liefern wuerde. Das steht hier, damit die
    # Behauptung "Signalstaerke stimmt" nicht falsch gelesen wird.
    if "beacon_db" in m:
        ok("Signalstaerke des ersten Beacons: %s dB (aus dem Radiotap-Kopf, "
           "NICHT aus dem Rahmen -- siehe lib/wlan/beacon.fi)"
           % m["beacon_db"][0])

    # ---- der Handschlag ----
    for i in range(1, 5):
        antwort = eins("eapol " + m["eapol%d" % i])
        felder = dict(x.split("=", 1) for x in antwort.split(" "))
        gleich("EAPOL-Rahmen %d wird als Nachricht %d erkannt" % (i, i),
               felder["nr"], str(i))
    antwort = eins("eapol " + m["eapol3"])
    felder = dict(x.split("=", 1) for x in antwort.split(" "))
    gleich("Nachricht 3: Schluesseldaten sind verschluesselt",
           felder["kdec"], "1")
    gleich("Nachricht 3: 'installieren' ist gesetzt", felder["insta"], "1")
    gleich("Nachricht 4: keine Schluesseldaten",
           dict(x.split("=", 1)
                for x in eins("eapol " + m["eapol4"]).split(" "))["dlen"], "0")

    # Der PMK -- aus dem Passwort und dem Netznamen der Aufzeichnung.
    pw = bytes.fromhex(m["pwhex"])
    ssid = bytes.fromhex(m["ssidhex"])
    pmk_soll = hashlib.pbkdf2_hmac("sha1", pw, ssid, 4096, 32).hex()
    pmk = eins("pmk %s %s" % (m["pwhex"], m["ssidhex"]))
    gleich("PMK aus 'Induction' und 'Coherer'", pmk, pmk_soll)

    aa = m["aa"]
    spa = m["spa"]
    e1 = bytes.fromhex(m["eapol1"])
    e2 = bytes.fromhex(m["eapol2"])
    anonce = e1[17:49].hex()
    snonce = e2[17:49].hex()
    ptk = eins("ptk %s %s %s %s %s 2 48" % (pmk, aa, spa, anonce, snonce))
    # Gegenrechnung mit einer Umsetzung, die dieses Repository nicht
    # geschrieben hat (hashlib/hmac).
    d = (min(bytes.fromhex(aa), bytes.fromhex(spa))
         + max(bytes.fromhex(aa), bytes.fromhex(spa))
         + min(bytes.fromhex(anonce), bytes.fromhex(snonce))
         + max(bytes.fromhex(anonce), bytes.fromhex(snonce)))
    ptk_soll = prf_sha1(bytes.fromhex(pmk_soll), b"Pairwise key expansion",
                        d, 48).hex()
    gleich("PTK aus dem echten Handschlag (48 Oktette)", ptk, ptk_soll)
    kck = ptk[:32]
    kek = ptk[32:64]
    tk = ptk[64:96]

    # DIE ZUSAGE DIESER RUNDE: die Pruefwerte, die damals wirklich auf
    # dem Draht standen, kommen aus diesem Quelltext heraus.
    for i in (2, 3, 4):
        roh = bytes.fromhex(m["eapol%d" % i])
        echt = roh[81:97].hex()
        gerechnet = eins("mic %s %s 2" % (kck, m["eapol%d" % i]))
        gleich("Pruefwert von Nachricht %d, gegen den ECHTEN Rahmen" % i,
               gerechnet, echt)
    # Negativ: ein KCK mit einem gekippten Bit darf NICHT passen.
    b = bytearray.fromhex(kck)
    b[0] ^= 1
    falsch = eins("mic %s %s 2" % (bytes(b).hex(), m["eapol2"]))
    if falsch != bytes.fromhex(m["eapol2"])[81:97].hex():
        ok("ein KCK mit einem gekippten Bit ergibt einen ANDEREN Pruefwert")
    else:
        bad("ein falscher KCK ergab denselben Pruefwert -- das kann nicht sein")

    # Der Gruppenschluessel aus Nachricht 3.
    kd = bytes.fromhex(m["eapol3"])[99:].hex()
    antwort = eins("gtk %s %s" % (kek, kd))
    if antwort == "FAIL":
        bad("der Gruppenschluessel aus Nachricht 3 liess sich nicht auspacken")
    else:
        gtk, nummer = antwort.split(" ")
        try:
            from cryptography.hazmat.primitives import keywrap
            klar = keywrap.aes_key_unwrap(bytes.fromhex(kek),
                                          bytes.fromhex(kd))
            # KDE 00-0F-AC Typ 1 von Hand suchen
            at = 0
            gefunden = None
            while at + 2 <= len(klar):
                l = klar[at + 1]
                if (klar[at] == 0xDD and l >= 6
                        and klar[at + 2:at + 6] == bytes.fromhex("000fac01")):
                    gefunden = klar[at + 8:at + 2 + l].hex()
                    break
                if klar[at] == 0 and l == 0:
                    break
                at += 2 + l
            gleich("Gruppenschluessel aus Nachricht 3 (gegen OpenSSL)",
                   gtk, gefunden)
        except ImportError:
            ok("Gruppenschluessel ausgepackt: %s (Schluesselnummer %s)"
               % (gtk, nummer))
        gleich("Schluesselnummer des Gruppenschluessels", nummer, "2")
    # Negativ: mit dem falschen KEK darf gar nichts herauskommen.
    b = bytearray.fromhex(kek)
    b[0] ^= 1
    gleich("mit falschem KEK laesst sich Nachricht 3 NICHT auspacken",
           eins("gtk %s %s" % (bytes(b).hex(), kd)), "FAIL")

    # ---- und jetzt die echten verschluesselten Rahmen ----
    fragen = ["ccmpdec %s %s" % (tk, f) for f in m["daten"]]
    antworten = orakel(fragen)
    gut = 0
    for i, a in enumerate(antworten):
        if a == "FAIL":
            bad("echter Datenrahmen %d liess sich nicht entschluesseln" % (i + 1))
            continue
        roh = bytes.fromhex(a)
        kopf = len(bytes.fromhex(m["daten"][i])) - len(roh) - 8
        rumpf = roh[24:]
        if rumpf[:6] == b"\xaa\xaa\x03\x00\x00\x00":
            gut += 1
        else:
            bad("echter Datenrahmen %d: kein LLC/SNAP im Klartext (%s)"
                % (i + 1, rumpf[:8].hex()))
    if gut == len(m["daten"]):
        ok("DIE GANZE KETTE: Passwort -> PMK -> PTK -> TK -> %d ECHTE "
           "Rahmen entschluesselt, in jedem steht LLC/SNAP" % gut)
    # Negativ: mit dem Gruppenschluessel oder einem gekippten TK geht es nicht.
    b = bytearray.fromhex(tk)
    b[0] ^= 1
    antworten = orakel(["ccmpdec %s %s" % (bytes(b).hex(), f)
                        for f in m["daten"]])
    if all(a == "FAIL" for a in antworten):
        ok("mit einem TK, in dem ein Bit gekippt ist, geht KEINER der %d "
           "Rahmen auf" % len(m["daten"]))
    else:
        bad("ein falscher TK hat einen Rahmen entschluesselt")


# ==================================================== 5. Kanal und Regeln

def teil_kanal():
    print()
    print("== 5. Kanaele, Frequenzen und die ETSI-Tabelle ==")
    for f, k, band in [(2412, 1, 1), (2437, 6, 1), (2472, 13, 1),
                       (2484, 14, 1), (5180, 36, 2), (5320, 64, 2),
                       (5500, 100, 2), (5745, 149, 2), (5955, 1, 3),
                       (6175, 45, 3)]:
        gleich("%d MHz ist Kanal %d in Band %d" % (f, k, band),
               eins("kanal %d" % f), "%d %d" % (k, band))
        gleich("und zurueck: Kanal %d in Band %d ist %d MHz" % (k, band, f),
               eins("freq %d %d" % (k, band)), str(f))
    for f in [2413, 2500, 5181, 1000, 9999]:
        gleich("%d MHz ist kein Kanal" % f, eins("kanal %d" % f), "FAIL")
    gleich("Kanal 2 im 6-GHz-Band ist der Ausreisser 5935 MHz",
           eins("freq 2 3"), "5935")
    gleich("Kanal 2 im 2,4-GHz-Band ist 2417 MHz", eins("freq 2 1"), "2417")

    # Die Regeln. Jede Zeile ist eine Aussage ueber europaeisches Recht,
    # und jede steht so in `lib/wlan/kanal.fi` mit ihrer Norm daneben.
    faelle = [
        (1, 1, "erlaubt=1 dbm=20 dfs=0 innen=0 passiv=0 senden=1 aktiv=1",
         "Kanal 1, 2,4 GHz: 20 dBm, kein Radar, innen und aussen"),
        (1, 13, "erlaubt=1 dbm=20 dfs=0 innen=0 passiv=0 senden=1 aktiv=1",
         "Kanal 13 ist in Europa erlaubt (in den USA nicht)"),
        (1, 14, "erlaubt=0 dbm=0 dfs=0 innen=0 passiv=0 senden=0 aktiv=0",
         "Kanal 14 ist in Europa NICHT zugeteilt"),
        (2, 36, "erlaubt=1 dbm=23 dfs=0 innen=1 passiv=0 senden=1 aktiv=1",
         "Kanal 36: 23 dBm, nur innen, kein Radar"),
        (2, 52, "erlaubt=1 dbm=23 dfs=1 innen=1 passiv=1 senden=0 aktiv=0",
         "Kanal 52: Radarpflicht -> ohne DFS wird NICHT gesendet"),
        (2, 100, "erlaubt=1 dbm=30 dfs=1 innen=0 passiv=1 senden=0 aktiv=0",
         "Kanal 100: 30 dBm, Radarpflicht -> ohne DFS wird NICHT gesendet"),
        (2, 144, "erlaubt=0 dbm=0 dfs=0 innen=0 passiv=0 senden=0 aktiv=0",
         "Kanal 144 ragt ueber die Bandkante 5725 -> nicht zugeteilt"),
        (2, 149, "erlaubt=0 dbm=0 dfs=0 innen=0 passiv=0 senden=0 aktiv=0",
         "Kanal 149 gehoert in Europa nicht zum WLAN-Bereich"),
        (2, 165, "erlaubt=0 dbm=0 dfs=0 innen=0 passiv=0 senden=0 aktiv=0",
         "Kanal 165 ebenso"),
        (3, 1, "erlaubt=1 dbm=23 dfs=0 innen=1 passiv=0 senden=1 aktiv=1",
         "Kanal 1 im 6-GHz-Band: 23 dBm, nur innen"),
        (3, 93, "erlaubt=1 dbm=23 dfs=0 innen=1 passiv=0 senden=1 aktiv=1",
         "Kanal 93 ist der letzte im europaeischen 6-GHz-Bereich"),
        (3, 97, "erlaubt=0 dbm=0 dfs=0 innen=0 passiv=0 senden=0 aktiv=0",
         "Kanal 97 liegt oberhalb von 6425 MHz -> nicht zugeteilt"),
    ]
    for band, k, soll, name in faelle:
        gleich(name, eins("etsi %d %d" % (band, k)), soll)
    # Die Eigenschaft, die ueber die einzelnen Zeilen hinausgeht.
    fragen = []
    for band in (1, 2, 3):
        for k in range(0, 250):
            fragen.append("etsi %d %d" % (band, k))
    antworten = orakel(fragen)
    verstoss = []
    for zeile in antworten:
        f = dict(x.split("=", 1) for x in zeile.split(" "))
        if f["senden"] == "1" and (f["erlaubt"] == "0" or f["dfs"] == "1"):
            verstoss.append(zeile)
        if f["aktiv"] == "1" and (f["erlaubt"] == "0" or f["passiv"] == "1"):
            verstoss.append(zeile)
    if not verstoss:
        ok("ueber ALLE %d Kanaele in drei Baendern: nie senden ohne Zuteilung, "
           "nie senden auf einem Radarkanal, nie aktiv suchen wo nur "
           "zugehoert werden darf" % len(fragen))
    else:
        bad("%d Kanaele verletzen die Regel, erster: %s"
            % (len(verstoss), verstoss[0]))


# ==================================================== 6. der Zustandsautomat

ALPHABET = "sbaAcC1234dtx"
RICHTIG = "sbac1234"


def zerlege_automat(zeile):
    return dict(x.split("=", 1) for x in zeile.split(" "))


def teil_automat():
    print()
    print("== 6. der Zustandsautomat: es gibt keine halbe Verbindung ==")
    f = zerlege_automat(eins("automat " + RICHTIG))
    gleich("die richtige Folge '%s' fuehrt zu VERBUNDEN" % RICHTIG,
           f["z"], "8")
    gleich("und darf Daten senden", f["daten"], "1")
    gleich("und hat den Schluessel GENAU EINMAL installiert", f["inst"], "1")

    # Jede einzelne Verstuemmelung der richtigen Folge.
    faelle = []
    for i in range(len(RICHTIG)):
        faelle.append(("Auslassen von '%s' an Stelle %d" % (RICHTIG[i], i),
                       RICHTIG[:i] + RICHTIG[i + 1:]))
        faelle.append(("Wiederholen von '%s' an Stelle %d" % (RICHTIG[i], i),
                       RICHTIG[:i + 1] + RICHTIG[i] + RICHTIG[i + 1:]))
    for i in range(len(RICHTIG) - 1):
        v = list(RICHTIG)
        v[i], v[i + 1] = v[i + 1], v[i]
        faelle.append(("Vertauschen von '%s' und '%s'"
                       % (RICHTIG[i], RICHTIG[i + 1]), "".join(v)))
    for i in range(len(RICHTIG) + 1):
        for c in ALPHABET:
            faelle.append(("Einschieben von '%s' an Stelle %d" % (c, i),
                           RICHTIG[:i] + c + RICHTIG[i:]))
    fragen = ["automat " + folge for _, folge in faelle]
    antworten = orakel(fragen)
    schlecht = []
    for (name, folge), zeile in zip(faelle, antworten):
        f = zerlege_automat(zeile)
        # Eine verstuemmelte Folge darf NUR dann verbinden, wenn sie
        # zufaellig wieder genau die richtige ist (Einschieben von 's'
        # ganz vorne, von 'b' an Stelle 1, ...).
        erlaubt = ist_gueltige_folge(folge)
        if (f["daten"] == "1") != erlaubt:
            schlecht.append((name, folge, zeile))
        if int(f["inst"]) > 1:
            schlecht.append(("MEHRFACHE Installation", folge, zeile))
    if not schlecht:
        ok("alle %d Verstuemmelungen der richtigen Folge (Auslassen, "
           "Wiederholen, Vertauschen, Einschieben) enden genau dann in "
           "VERBUNDEN, wenn sie wieder gueltig sind" % len(faelle))
    else:
        for name, folge, zeile in schlecht[:5]:
            bad("%s ('%s') -> %s" % (name, folge, zeile))

    # Die einzelnen Gruende, damit sie nicht alle nur "Reihenfolge" sind.
    for folge, grund, name in [
        ("sbAc1234", "2", "abgelehnte Authentifizierung -> Grund 2"),
        ("sbacC1234", "1", "'C' nach dem Handschlagbeginn -> Grund 1"),
        ("sbatc1234", "3", "Zeitueberschreitung -> Grund 3"),
        ("sbacd1234", "4", "Deauth mitten im Handschlag -> Grund 4"),
        ("sbac1233", "5", "Nachricht 3 zweimal (KRACK) -> Grund 5"),
        ("sbac123x", "6", "Nachricht 3 mit falschem Pruefwert -> Grund 6"),
    ]:
        f = zerlege_automat(eins("automat " + folge))
        gleich(name, "%s/%s" % (f["z"], f["grund"]), "9/%s" % grund)
        if f["daten"] != "0":
            bad("'%s' endet im Fehler und darf trotzdem Daten senden" % folge)

    # Und die erschoepfende Suche. Bis Laenge 4 kann NICHTS verbinden --
    # der richtige Ablauf braucht acht Ereignisse. Wenn hier auch nur
    # eine Folge 'daten=1' meldet, gibt es eine Abkuerzung.
    tiefe = 3 if SCHNELL else 4
    folgen = [""]
    alle = []
    for _ in range(tiefe):
        folgen = [f + c for f in folgen for c in ALPHABET]
        alle.extend(folgen)
    antworten = orakel(["automat " + f for f in alle])
    schlecht = []
    for folge, zeile in zip(alle, antworten):
        f = zerlege_automat(zeile)
        if f["daten"] != "0" or f["inst"] != "0" or f["verbund"] != "0":
            schlecht.append((folge, zeile))
    if not schlecht:
        ok("ERSCHOEPFEND: alle %d Ereignisfolgen bis Laenge %d ueber ein "
           "Alphabet von %d -- keine einzige verbindet, keine installiert "
           "einen Schluessel" % (len(alle), tiefe, len(ALPHABET)))
    else:
        bad("%d Folgen bis Laenge %d kommen zu weit, erste: '%s' -> %s"
            % (len(schlecht), tiefe, schlecht[0][0], schlecht[0][1]))

    # Die zweite Eigenschaft: der Fehlerzustand ist eine Sackgasse.
    fragen = []
    for folge in ["sbAc1234", "s1", "d", "sbacd", "sbac1233"]:
        for anhang in ["", "s", "sbac1234", "1234", "tttt"]:
            fragen.append("automat " + folge + anhang)
    antworten = orakel(fragen)
    if all(zerlege_automat(a)["z"] == "9" and zerlege_automat(a)["daten"] == "0"
           for a in antworten):
        ok("der Fehlerzustand ist eine Sackgasse: %d Folgen, die einmal "
           "abgebrochen sind, kommen mit keinem Anhang wieder heraus"
           % len(fragen))
    else:
        bad("eine abgebrochene Folge kam wieder heraus")


def ist_gueltige_folge(folge):
    """Die Regel, die eine Verbindung erlaubt -- unabhaengig vom Firn-Code
    aufgeschrieben, damit der Vergleich etwas heisst:
    ein oder mehr 's', dann ein oder mehr 'b', dann genau 'ac1234'."""
    i = 0
    n = len(folge)
    if i >= n or folge[i] != "s":
        return False
    while i < n and folge[i] == "s":
        i += 1
    if i >= n or folge[i] != "b":
        return False
    while i < n and folge[i] == "b":
        i += 1
    return folge[i:] == "ac1234"


# ==================================================== 7. die Grenzfaelle

def teil_grenzen():
    print()
    print("== 7. was NICHT durchgehen darf ==")
    m = lies_mitschnitt()
    b = m["beacon"][0]
    roh = bytearray.fromhex(b)

    # Ein Beacon, dem das letzte Element abgeschnitten ist. Er darf
    # NICHT als Netz durchgehen -- das abgeschnittene koennte das
    # RSN-Element sein, und ein Netz ohne RSN-Element gilt als offen.
    # Genau hier entstuende aus einem Uebertragungsfehler eine
    # unverschluesselte Verbindung.
    schlecht = 0
    fragen = []
    laengen = list(range(0, len(roh)))
    for i in laengen:
        fragen.append("beacon " + bytes(roh[:i]).hex())
    antworten = orakel(fragen)
    for i, a in zip(laengen, antworten):
        if a != "FAIL":
            # Ein abgeschnittener Beacon darf nur dann durchgehen, wenn
            # er zufaellig genau an einer Elementgrenze endet UND alle
            # Elemente vollstaendig sind. Dann ist er ein gueltiger,
            # kuerzerer Beacon.
            f = dict(x.split("=", 1) for x in a.split(" "))
            if f["sich"] == "0" and "48" in eins("ies " + b):
                schlecht += 1
    if schlecht == 0:
        ok("alle %d Abschnitte des echten Beacons: keiner wird als OFFENES "
           "Netz gemeldet, obwohl das Netz WPA2 ist" % len(laengen))
    else:
        bad("%d abgeschnittene Beacons wurden als offenes Netz gemeldet"
            % schlecht)

    # Ein Element, dessen Laengenfeld ueber das Ende zeigt.
    ies_start = 24 + 12
    fragen = []
    for luege in (0xFF, 0x80, len(roh)):
        v = bytearray(roh)
        v[ies_start + 1] = luege & 255
        fragen.append("beacon " + bytes(v).hex())
        fragen.append("ies " + bytes(v).hex())
    antworten = orakel(fragen)
    if all(a == "FAIL" or "KAPUTT" in a for a in antworten):
        ok("ein Laengenfeld, das ueber das Ende des Rahmens zeigt, "
           "wird erkannt und nicht gelesen")
    else:
        bad("ein luegendes Laengenfeld ging durch: %s" % antworten)

    # Ein RSN-Element, das mehr Chiffren ansagt, als es hat. Das ist der
    # klassische Weg, einen Zerleger ueber das Ende zu schicken.
    ies = eins("ies " + b)
    # das RSN-Element hat Kennung 48; wir suchen es von Hand
    at = ies_start
    rsn_at = None
    while at + 2 <= len(roh):
        if roh[at] == 48:
            rsn_at = at
            break
        at += 2 + roh[at + 1]
    if rsn_at is None:
        bad("im echten Beacon steht kein RSN-Element -- Test nicht moeglich")
    else:
        fragen = []
        # Versatz im RSN-Element: 2 Version + 4 Gruppe = 6, dann die
        # Zahl der Paarchiffren.
        for wert in (0xFFFF, 0x0100, 0x0010):
            v = bytearray(roh)
            v[rsn_at + 2 + 6] = wert & 255
            v[rsn_at + 2 + 7] = (wert >> 8) & 255
            fragen.append("beacon " + bytes(v).hex())
        antworten = orakel(fragen)
        if all(a == "FAIL" for a in antworten):
            ok("ein RSN-Element, das mehr Chiffren ansagt als es hat "
               "(0xFFFF, 0x0001, 0x1000), wird ABGELEHNT")
        else:
            bad("ein luegendes RSN-Element ging durch: %s" % antworten)

    # Rahmen, die keine Beacons sind.
    for name, roh2 in [
        ("ein Steuerrahmen (ACK)", "d4000000000c4182b255"),
        ("ein Datenrahmen", "0842000000000000000000000000000000000000000000"),
        ("zwei Oktette", "8000"),
        ("ein Oktett", "80"),
        ("ein Rahmen mit Protokollversion 1", "8100" + b[4:]),
    ]:
        gleich("%s ist kein Beacon" % name, eins("beacon " + roh2), "FAIL")

    # EAPOL: die beiden Laengenfelder muessen zueinander passen.
    e = bytearray.fromhex(m["eapol3"])
    v = bytearray(e)
    v[97] = 0xFF
    v[98] = 0xFF
    gleich("EAPOL: eine Schluesseldatenlaenge von 65535 -> ABGELEHNT",
           eins("eapol " + bytes(v).hex()), "FAIL")
    v = bytearray(e)
    v[2] = 0xFF
    v[3] = 0xFF
    gleich("EAPOL: eine Rumpflaenge von 65535 -> ABGELEHNT",
           eins("eapol " + bytes(v).hex()), "FAIL")
    v = bytearray(e)
    v[1] = 0
    gleich("EAPOL: ein anderer Pakettyp als 3 -> ABGELEHNT",
           eins("eapol " + bytes(v).hex()), "FAIL")
    v = bytearray(e)
    v[4] = 7
    gleich("EAPOL: ein unbekannter Deskriptortyp -> ABGELEHNT",
           eins("eapol " + bytes(v).hex()), "FAIL")
    for n in range(0, len(e)):
        pass
    fragen = ["eapol " + bytes(e[:n]).hex() for n in range(1, 99)]
    antworten = orakel(fragen)
    if all(a == "FAIL" for a in antworten):
        ok("EAPOL: alle 98 Abschnitte unterhalb des festen Teils -> ABGELEHNT")
    else:
        bad("ein zu kurzer EAPOL-Rahmen ging durch")

    # Ein Anmeldeverfahren, fuer das es keine Pruefwertrechnung gibt.
    kck = "00" * 16
    gleich("MIC mit einem unbekannten Anmeldeverfahren -> ABGELEHNT",
           eins("mic %s %s 99" % (kck, m["eapol2"])), "FAIL")
    gleich("MIC mit einem KCK von 15 Oktetten -> ABGELEHNT",
           eins("mic %s %s 2" % ("00" * 15, m["eapol2"])), "FAIL")


# ==================================================== 8. WPA3-Ableitung

def teil_wpa3():
    print()
    print("== 8. die SHA-256-Ableitung (WPA3-AKM und PSK-SHA256) ==")
    # Der Handschlag kann AKM 8 (SAE). Die ANMELDUNG selbst ist nicht
    # gebaut -- Begruendung in docs/WLAN-BEFUND.md Abschnitt 6 --, aber
    # sobald ein PMK da ist, ist der Rest von WPA3 dieser Weg hier.
    #
    # Gegengerechnet wird mit einer Nachbildung der Norm
    # (IEEE 802.11-2016 12.7.1.6.2) auf Pythons hmac.
    def kdf(key, label, data, nbits):
        r = b""
        i = 1
        n = (nbits + 7) // 8
        while len(r) < n:
            r += pyhmac.new(key, i.to_bytes(2, "little") + label + data
                            + nbits.to_bytes(2, "little"),
                            hashlib.sha256).digest()
            i += 1
        return r[:n]

    pmk = hashlib.sha256(b"wpa3").digest()
    aa = bytes.fromhex("020000000001")
    spa = bytes.fromhex("020000000002")
    an = bytes(range(32))
    sn = bytes(range(32, 64))
    d = min(aa, spa) + max(aa, spa) + min(an, sn) + max(an, sn)
    for akm, name in [(8, "SAE"), (9, "FT-SAE"), (6, "PSK-SHA256"),
                      (5, "802.1X-SHA256")]:
        soll = kdf(pmk, b"Pairwise key expansion", d, 48 * 8).hex()
        ist = eins("ptk %s %s %s %s %s %d 48"
                   % (pmk.hex(), aa.hex(), spa.hex(), an.hex(), sn.hex(), akm))
        gleich("PTK mit KDF-SHA256, AKM %d (%s)" % (akm, name), ist, soll)
    # und dass AKM 2 (PSK) NICHT dasselbe rechnet
    mit_sha1 = eins("ptk %s %s %s %s %s 2 48"
                    % (pmk.hex(), aa.hex(), spa.hex(), an.hex(), sn.hex()))
    mit_sha256 = eins("ptk %s %s %s %s %s 8 48"
                      % (pmk.hex(), aa.hex(), spa.hex(), an.hex(), sn.hex()))
    if mit_sha1 != mit_sha256:
        ok("AKM 2 (SHA-1) und AKM 8 (SHA-256) ergeben VERSCHIEDENE Schluessel")
    else:
        bad("AKM 2 und AKM 8 ergaben denselben Schluessel -- dann rechnet "
            "eine der beiden Bahnen falsch")
    # Der Pruefwert bei WPA3 ist AES-CMAC und nicht HMAC-SHA1.
    m = lies_mitschnitt()
    a = eins("mic %s %s 2" % ("00" * 16, m["eapol2"]))
    b = eins("mic %s %s 8" % ("00" * 16, m["eapol2"]))
    if a != b and a != "FAIL" and b != "FAIL":
        ok("der Pruefwert von AKM 2 (HMAC-SHA1) und AKM 8 (AES-CMAC) ist "
           "verschieden")
    else:
        bad("die beiden Pruefwertverfahren liefern dasselbe oder scheitern")
    # Die Vertauschung der Adressen darf NICHTS aendern -- beide Seiten
    # sortieren.
    v1 = eins("ptk %s %s %s %s %s 2 48"
              % (pmk.hex(), aa.hex(), spa.hex(), an.hex(), sn.hex()))
    v2 = eins("ptk %s %s %s %s %s 2 48"
              % (pmk.hex(), spa.hex(), aa.hex(), sn.hex(), an.hex()))
    if v1 == v2:
        ok("beide Seiten rechnen denselben PTK, obwohl jede ihre eigene "
           "Adresse zuerst kennt (min/max)")
    else:
        bad("die Sortierung von Adressen und Zufallszahlen fehlt -- die "
            "beiden Seiten bekommen verschiedene Schluessel")


# ==================================================================

def main():
    if not os.path.exists(ORAKEL):
        print("  FAIL  %s gibt es nicht -- erst tools/wlan/run.sh" % ORAKEL)
        return 1
    teil_sha1()
    teil_aes()
    teil_ccmp()
    teil_mitschnitt()
    teil_kanal()
    teil_automat()
    teil_grenzen()
    teil_wpa3()
    print()
    print("WLAN: %d Zusagen, %d Fehler" % (pass_n, fail_n))
    return 1 if fail_n else 0


if __name__ == "__main__":
    sys.exit(main())
