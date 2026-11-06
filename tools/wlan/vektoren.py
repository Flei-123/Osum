#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import hashlib
import hmac as pyhmac
import os
import subprocess
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(HIER))
ORAKEL = os.path.join(REPO_ROOT, ".probe", "worakel")
MITSCHNITT = os.path.join(HIER, "mitschnitt.txt")

QUICK = ("--quick" in sys.argv or "--schnell" in sys.argv)

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


def equal(name, ist, soll):
    if ist == soll:
        ok("%s: %s" % (name, ist if len(str(ist)) < 60 else str(ist)[:57] + "..."))
    else:
        bad("%s: '%s', erwartet '%s'" % (name, ist, soll))


# ------------------------------------------------------------ das Orakel

def orakel(rows):
    input_text = ("\n".join(rows) + "\n").encode()
    p = subprocess.run([ORAKEL], input=input_text, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE)
    if p.returncode != 0:
        bad("the oracle exited with code %d" % p.returncode)
        return ["ABSTURZ"] * len(rows)
    aus = p.stdout.decode(errors="replace").split("\n")
    while aus and aus[-1] == "":
        aus.pop()
    if len(aus) != len(rows):
        bad("the oracle gave %d lines for %d questions" % (len(aus), len(rows)))
        while len(aus) < len(rows):
            aus.append("FEHLT")
    return aus


def eins(row):
    return orakel([row])[0]


def h(b):
    return b.hex() if b else "-"


# ============================================================ 1. SHA-1

def part_sha1():
    print("== 1. SHA-1, HMAC-SHA1, PRF und PBKDF2 ==")
    equal("SHA-1(\"abc\")", eins("sha1 " + h(b"abc")),
           "a9993e364706816aba3e25717850c26c9cd0d89d")
    lang = b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
    equal("SHA-1(56 octets, FIPS 180-4)", eins("sha1 " + h(lang)),
           "84983e441c3bd26ebaae4aa1f95129e5e54670f1")
    equal("SHA-1(leer)", eins("sha1 -"),
           "da39a3ee5e6b4b0d3255bfef95601890afd80709")

    laengen = list(range(0, 200)) if not QUICK else [0, 1, 55, 56, 63, 64, 65, 119, 120, 128]
    queries = []
    sollen = []
    for n in laengen:
        m = bytes((i * 37 + n) & 255 for i in range(n))
        queries.append("sha1 " + h(m))
        sollen.append(hashlib.sha1(m).hexdigest())
    antworten = orakel(queries)
    defective = [i for i in range(len(queries)) if antworten[i] != sollen[i]]
    if defective:
        bad("SHA-1 vs hashlib: %d of %d wrong, first length %d"
            % (len(defective), len(queries), laengen[defective[0]]))
    else:
        ok("SHA-1 vs Python hashlib: %d lengths from %d to %d, all equal"
           % (len(laengen), laengen[0], laengen[-1]))

    queries = []
    sollen = []
    for kl in [0, 1, 20, 63, 64, 65, 100, 200]:
        for ml in [0, 1, 64, 200]:
            k = bytes((i * 11 + kl) & 255 for i in range(kl))
            m = bytes((i * 7 + ml) & 255 for i in range(ml))
            queries.append("hmacsha1 %s %s" % (h(k), h(m)))
            sollen.append(pyhmac.new(k, m, hashlib.sha1).hexdigest())
    antworten = orakel(queries)
    if antworten == sollen:
        ok("HMAC-SHA1 vs Python hmac: %d cases, including keys > 64 octets"
           % len(queries))
    else:
        i = [j for j in range(len(queries)) if antworten[j] != sollen[j]][0]
        bad("HMAC-SHA1: case %d wrong (%s instead of %s)" % (i, antworten[i], sollen[i]))

    # ---- PRF-SHA1, IEEE 802.11i 8.5.1.1 ----
    #
    # HERKUNFT: hostapd 2.10, src/crypto/crypto_module_tests.c, die
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
        response = eins("prf %s %s %s %d" % (h(key), h(b"prefix"), h(data),
                                            len(soll) // 2))
        equal("PRF-SHA1, IEEE-802.11i-Vektor %d (aus hostapd 2.10)" % i,
               response, soll)

    # ---- PBKDF2-HMAC-SHA1, RFC 6070 ----
    for pw, salt, c, soll in [
        (b"password", b"salt", 1, "0c60c80f961f0e71f3a9b524af6012062fe037a6"),
        (b"password", b"salt", 2, "ea6c014dc72d6f8ccd1ed92ace1d41f0d8de8957"),
        (b"password", b"salt", 4096, "4b007901b765489abead49d926f721d065a429c1"),
        (b"passwordPASSWORDpassword",
         b"saltSALTsaltSALTsaltSALTsaltSALTsalt", 4096,
         "3d2eec4fe41c849b80c8d83662c0e44a8b291a964cf2f07038"),
    ]:
        response = eins("pbkdf2 %s %s %d %d" % (h(pw), h(salt), c, len(soll) // 2))
        equal("PBKDF2-SHA1, RFC 6070, c=%d" % c, response, soll)

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
        response = eins("pmk %s %s" % (h(pw), h(ssid)))
        equal("PMK from password and SSID (%s)" % ssid.decode(), response, soll)

    equal("a password of 7 characters is REJECTED",
           eins("pmk %s %s" % (h(b"1234567"), h(b"Netz"))), "FAIL")
    equal("a password of 64 characters is REJECTED",
           eins("pmk %s %s" % (h(b"x" * 64), h(b"Netz"))), "FAIL")
    equal("an SSID of 33 octets is REJECTED",
           eins("pmk %s %s" % (h(b"passwort"), h(b"y" * 33))), "FAIL")


# ============================================================ 2. AES

def part_aes():
    print()
    print("== 2. AES, CMAC, Key Wrap und CCM ==")
    pt = bytes(range(0x00, 0x100, 0x11))
    for kl, soll in [
        (16, "69c4e0d86a7b0430d8cdb78070b4c55a"),
        (24, "dda97ca4864cdfe06eaf70a0ec0d7191"),
        (32, "8ea2b7ca516745bfeafc49904b496089"),
    ]:
        key = bytes(range(kl))
        equal("AES-%d, FIPS 197 Anhang C" % (kl * 8),
               eins("aesenc %s %s" % (h(key), h(pt))), soll)
        equal("AES-%d rueckwaerts, FIPS 197 Anhang C" % (kl * 8),
               eins("aesdec %s %s" % (h(key), bytes.fromhex(soll).hex())),
               pt.hex())
    equal("a key of 20 octets is REJECTED",
           eins("aesenc %s %s" % (h(b"x" * 20), h(pt))), "FAIL")

    try:
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
        have_crypto = True
    except ImportError:
        have_crypto = False
    if have_crypto:
        queries = []
        sollen = []
        total = 20 if QUICK else 200
        for i in range(total):
            kl = [16, 24, 32][i % 3]
            key = hashlib.sha256(b"k%d" % i).digest()[:kl]
            blk = hashlib.sha256(b"b%d" % i).digest()[:16]
            c = Cipher(algorithms.AES(key), modes.ECB())
            queries.append("aesenc %s %s" % (h(key), h(blk)))
            sollen.append(c.encryptor().update(blk).hex())
        if orakel(queries) == sollen:
            ok("AES vs OpenSSL: %d blocks over all three key lengths"
               % total)
        else:
            bad("AES vs OpenSSL: at least one block wrong")

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
        equal("AES-CMAC, RFC 4493, example with %d octets" % n,
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
        equal("Key Wrap, RFC 3394, KEK %d bit / %d octets of content"
               % (kek_l * 8, pl),
               eins("wrap %s %s" % (h(kek), h(plain))), soll)
        equal("and unwrapped again",
               eins("unwrap %s %s" % (h(kek), soll)), plain.hex())
    kek = bytes(range(16))
    gut = "1fa68b0a8112b447aef34bd8fb5a7b829d3e862371d2cfe5"
    b = bytearray.fromhex(gut)
    b[0] ^= 1
    equal("Key Wrap: one flipped bit in the package -> REJECTED",
           eins("unwrap %s %s" % (h(kek), bytes(b).hex())), "FAIL")
    kek2 = bytearray(kek)
    kek2[15] ^= 1
    equal("Key Wrap: a wrong key -> REJECTED",
           eins("unwrap %s %s" % (h(bytes(kek2)), gut)), "FAIL")
    equal("Key Wrap: 8 octets of content are too few -> REJECTED",
           eins("wrap %s %s" % (h(kek), h(b"12345678"))), "FAIL")

    # ---- CCM gegen OpenSSL ----
    if have_crypto:
        from cryptography.hazmat.primitives.ciphers.aead import AESCCM
        queries = []
        sollen = []
        faelle = []
        total = 12 if QUICK else 120
        for i in range(total):
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
            queries.append("ccmenc %s %s %s %s %d"
                          % (h(key), h(nonce), h(aad), h(msg), tl))
            sollen.append(soll)
            faelle.append((key, nonce, aad, msg, tl, soll))
        antworten = orakel(queries)
        if antworten == sollen:
            ok("AES-CCM vs OpenSSL: %d cases, nonce 7..13, check value 4..16, "
               "message 0..199" % total)
        else:
            i = [j for j in range(len(queries)) if antworten[j] != sollen[j]][0]
            bad("AES-CCM: case %d wrong" % i)
        queries = []
        sollen = []
        for key, nonce, aad, msg, tl, ct in faelle:
            queries.append("ccmdec %s %s %s %s %d"
                          % (h(key), h(nonce), h(aad), ct, tl))
            sollen.append(msg.hex() if msg else "-")
        if orakel(queries) == sollen:
            ok("AES-CCM back: the same %d cases, plaintext equal" % total)
        else:
            bad("AES-CCM back: at least one case wrong")
        queries = []
        for key, nonce, aad, msg, tl, ct in faelle:
            b = bytearray.fromhex(ct)
            b[-1] ^= 1
            queries.append("ccmdec %s %s %s %s %d"
                          % (h(key), h(nonce), h(aad), bytes(b).hex(), tl))
        antworten = orakel(queries)
        if all(a == "FAIL" for a in antworten):
            ok("AES-CCM: one flipped bit in the check value -> all %d REJECTED"
               % total)
        else:
            bad("AES-CCM: %d von %d Faelschungen wurden ANGENOMMEN"
                % (sum(1 for a in antworten if a != "FAIL"), total))
        queries = []
        n = 0
        for key, nonce, aad, msg, tl, ct in faelle:
            if not aad:
                continue
            b = bytearray(aad)
            b[0] ^= 1
            queries.append("ccmdec %s %s %s %s %d"
                          % (h(key), h(nonce), h(bytes(b)), ct, tl))
            n += 1
        if n:
            antworten = orakel(queries)
            if all(a == "FAIL" for a in antworten):
                ok("AES-CCM: one flipped bit in the ADDITIONAL data "
                   "-> all %d REJECTED" % n)
            else:
                bad("AES-CCM: changed additional data was accepted")


# ============================================================ 3. CCMP

# HERKUNFT dieser beiden Vektoren: IEEE Std 802.11-2012, Anhaenge M.6.4
CCMP_VEKTOREN = [
    ("IEEE Std 802.11-2012 M.6.4, data frame",
     "c97c1f67ce371185514a8a19f2bdd52f",
     "b5039776e70c",
     "0848c32c0fd2e128a57c5030f1844408abaea5b8fcba8033"
     "f8ba1a55d02f85ae967bb62fb6cda8eb7e78a050",
     "0848c32c0fd2e128a57c5030f1844408abaea5b8fcba8033"
     "0ce70020769703b5"
     "f3d0a2fe9a3dbf2342a643e43246e80c3c04d019"
     "7845ce0b16f97623"),
    ("IEEE Std 802.11-2012 M.9.2, protected deauth frame",
     "66ed21042f9f26d7115706e40414cf2e",
     "000000000001",
     "c00000000200000001000200000000000200000000006000"
     "0200",
     "c04000000200000001000200000000000200000000006000"
     "0100002000000000"
     "1d07"
     "cafd0409bb8bafef"),
]


def part_ccmp():
    print()
    print("== 3. CCMP: nonce, additional data, whole MPDU ==")
    for name, tk, pn, klar, geschuetzt in CCMP_VEKTOREN:
        equal("%s -- schuetzen" % name,
               eins("ccmpenc %s %s %s" % (tk, pn, klar)), geschuetzt)
        kb = bytearray.fromhex(klar)
        kb[1] &= ~0x40
        equal("%s -- entschuetzen" % name,
               eins("ccmpdec %s %s" % (tk, geschuetzt)), bytes(kb).hex())
        # steckt.
        roh = bytearray.fromhex(geschuetzt)
        queries = []
        places = list(range(len(roh)))
        for i in places:
            b = bytearray(roh)
            b[i] ^= 0x01
            queries.append("ccmpdec %s %s" % (tk, bytes(b).hex()))
        antworten = orakel(queries)
        durch = set(i for i, a in enumerate(antworten) if a != "FAIL")
        # verspricht, als sie haelt:
        #
        #           hineingeht: Frame Control, A1, A2, A3,
        #           Sequence Control, gegebenenfalls A4 und QoS --
        #           veraendern.
        #           wird ueberhaupt geprueft.
        #
        header = 24
        erwartet_frei = {2, 3, 23, header + 2, header + 3}
        if durch == erwartet_frei:
            ok("%s -- of %d octets all are noticed except exactly the "
               "five the standard does not protect (duration, sequence number, "
               "the two header fields)" % (name, len(queries)))
        else:
            zuviel = sorted(durch - erwartet_frei)
            zuwenig = sorted(erwartet_frei - durch)
            bad("%s -- unbemerkt geblieben, obwohl gesichert: %s; "
                "aufgefallen, obwohl ungesichert: %s"
                % (name, zuviel, zuwenig))
        frei = [(1, 0x08, "Wiederholung"), (1, 0x10, "Stromsparen"),
                (1, 0x20, "more data")]
        queries = []
        for okt, bit, _ in frei:
            b = bytearray(roh)
            b[okt] ^= bit
            queries.append("ccmpdec %s %s" % (tk, bytes(b).hex()))
        antworten = orakel(queries)
        durch = [frei[i][2] for i, a in enumerate(antworten) if a != "FAIL"]
        if len(durch) == len(frei):
            ok("%s -- and the three bits EXEMPTED by the standard "
               "(%s) pass as expected"
               % (name, ", ".join(durch)))
        else:
            bad("%s -- the exempted bits behave differently than "
                "die Norm sagt: %s" % (name, antworten))
        b = bytearray.fromhex(tk)
        b[0] ^= 1
        equal("%s -- wrong key -> REJECTED" % name,
               eins("ccmpdec %s %s" % (bytes(b).hex(), geschuetzt)), "FAIL")
        equal("%s -- shortened by one octet -> REJECTED" % name,
               eins("ccmpdec %s %s" % (tk, geschuetzt[:-2])), "FAIL")

    # Klartextrahmen als Schluesseltext ausgeben.
    name, tk, pn, klar, geschuetzt = CCMP_VEKTOREN[0]
    b = bytearray.fromhex(geschuetzt)
    b[1] = b[1] & 0xBF
    equal("a frame WITHOUT the protected flag is not decrypted",
           eins("ccmpdec %s %s" % (tk, bytes(b).hex())), "FAIL")
    b = bytearray.fromhex(geschuetzt)
    b[24 + 3] = b[24 + 3] & 0xDF
    equal("a CCMP header without the ExtIV bit is REJECTED",
           eins("ccmpdec %s %s" % (tk, bytes(b).hex())), "FAIL")


# ============================================== 4. die echte Aufzeichnung

def read_capture():
    payload = {}
    entries = {}
    with open(MITSCHNITT, encoding="utf-8") as f:
        for row in f:
            row = row.strip()
            if not row or row.startswith("#"):
                continue
            k, _, v = row.partition(" ")
            if k in ("beacon", "daten", "beacon_db"):
                entries.setdefault(k, []).append(v)
            else:
                payload[k] = v
    payload.update(entries)
    return payload


def prf_sha1(key, label, data, n):
    r = b""
    i = 0
    while len(r) < n:
        r += pyhmac.new(key, label + b"\x00" + data + bytes([i]),
                        hashlib.sha1).digest()
        i += 1
    return r[:n]


def part_capture():
    print()
    print("== 4. against a REAL capture (wpa-Induction.pcap) ==")
    m = read_capture()

    # ---- die Beacons ----
    for i, b in enumerate(m["beacon"]):
        response = eins("beacon " + b)
        felder = dict(x.split("=", 1) for x in response.split(" "))
        if i == 0:
            equal("Beacon 1: SSID", bytes.fromhex(felder["ssid"]).decode(),
                   "Coherer")
            equal("Beacon 1: channel", felder["channel"], "1")
            equal("Beacon 1: band (derived from the channel number)",
                   felder["band"], "1")
            equal("Beacon 1: Sicherheitsart WPA2", felder["sich"], "3")
            equal("Beacon 1: Paarchiffre CCMP-128", felder["paar"], "4")
            equal("Beacon 1: group cipher TKIP (as it is on the network)",
                   felder["gruppe"], "2")
            equal("Beacon 1: Anmeldeverfahren PSK", felder["akm"], "2")
            equal("Beacon 1: no management frame protection", felder["pmf"], "0")
            equal("Beacon 1: Intervall 100 Zeiteinheiten", felder["intv"], "100")
            equal("Beacon 1: BSSID", felder["bssid"], "000c4182b255")
            equal("Beacon 1: SSID not hidden", felder["verbrg"], "0")
        else:
            if felder["ssid"] == b"Coherer".hex() and felder["channel"] == "1":
                ok("Beacon %d of the same network: SSID and channel equal" % (i + 1))
            else:
                bad("Beacon %d weicht ab: %s" % (i + 1, response))
    equal("Beacon 1: the chain of information elements",
           eins("ies " + m["beacon"][0]),
           "0:7 1:8 3:1 5:4 42:1 47:1 48:24 50:4 221:6 221:28")
    if "probeantwort" in m:
        response = eins("beacon " + m["probeantwort"])
        felder = dict(x.split("=", 1) for x in response.split(" "))
        equal("a probe response is read like a beacon",
               bytes.fromhex(felder["ssid"]).decode(), "Coherer")
    if "beacon_db" in m:
        ok("Signal strength of the first beacon: %s dB (from the radiotap header, "
           "NOT from the frame -- see lib/wlan/beacon.fi)"
           % m["beacon_db"][0])

    # ---- der Handschlag ----
    for i in range(1, 5):
        response = eins("eapol " + m["eapol%d" % i])
        felder = dict(x.split("=", 1) for x in response.split(" "))
        equal("EAPOL frame %d is recognized as message %d" % (i, i),
               felder["nr"], str(i))
    response = eins("eapol " + m["eapol3"])
    felder = dict(x.split("=", 1) for x in response.split(" "))
    equal("message 3: key data is encrypted",
           felder["kdec"], "1")
    equal("message 3: 'install' is set", felder["insta"], "1")
    equal("message 4: no key data",
           dict(x.split("=", 1)
                for x in eins("eapol " + m["eapol4"]).split(" "))["dlen"], "0")

    pw = bytes.fromhex(m["pwhex"])
    ssid = bytes.fromhex(m["ssidhex"])
    pmk_soll = hashlib.pbkdf2_hmac("sha1", pw, ssid, 4096, 32).hex()
    pmk = eins("pmk %s %s" % (m["pwhex"], m["ssidhex"]))
    equal("PMK from 'Induction' and 'Coherer'", pmk, pmk_soll)

    aa = m["aa"]
    spa = m["spa"]
    e1 = bytes.fromhex(m["eapol1"])
    e2 = bytes.fromhex(m["eapol2"])
    anonce = e1[17:49].hex()
    snonce = e2[17:49].hex()
    ptk = eins("ptk %s %s %s %s %s 2 48" % (pmk, aa, spa, anonce, snonce))
    # geschrieben hat (hashlib/hmac).
    d = (min(bytes.fromhex(aa), bytes.fromhex(spa))
         + max(bytes.fromhex(aa), bytes.fromhex(spa))
         + min(bytes.fromhex(anonce), bytes.fromhex(snonce))
         + max(bytes.fromhex(anonce), bytes.fromhex(snonce)))
    ptk_soll = prf_sha1(bytes.fromhex(pmk_soll), b"Pairwise key expansion",
                        d, 48).hex()
    equal("PTK from the real handshake (48 octets)", ptk, ptk_soll)
    kck = ptk[:32]
    kek = ptk[32:64]
    tk = ptk[64:96]

    for i in (2, 3, 4):
        roh = bytes.fromhex(m["eapol%d" % i])
        echt = roh[81:97].hex()
        gerechnet = eins("mic %s %s 2" % (kck, m["eapol%d" % i]))
        equal("check value of message %d, against the REAL frame" % i,
               gerechnet, echt)
    b = bytearray.fromhex(kck)
    b[0] ^= 1
    incorrect = eins("mic %s %s 2" % (bytes(b).hex(), m["eapol2"]))
    if incorrect != bytes.fromhex(m["eapol2"])[81:97].hex():
        ok("a KCK with one flipped bit gives a DIFFERENT check value")
    else:
        bad("a wrong KCK gave the same check value -- that cannot be")

    kd = bytes.fromhex(m["eapol3"])[99:].hex()
    response = eins("gtk %s %s" % (kek, kd))
    if response == "FAIL":
        bad("the group key from message 3 could not be unwrapped")
    else:
        gtk, number = response.split(" ")
        try:
            from cryptography.hazmat.primitives import keywrap
            klar = keywrap.aes_key_unwrap(bytes.fromhex(kek),
                                          bytes.fromhex(kd))
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
            equal("group key from message 3 (vs OpenSSL)",
                   gtk, gefunden)
        except ImportError:
            ok("group key unwrapped: %s (key number %s)"
               % (gtk, number))
        equal("key number of the group key", number, "2")
    b = bytearray.fromhex(kek)
    b[0] ^= 1
    equal("with a wrong KEK message 3 can NOT be unwrapped",
           eins("gtk %s %s" % (bytes(b).hex(), kd)), "FAIL")

    queries = ["ccmpdec %s %s" % (tk, f) for f in m["daten"]]
    antworten = orakel(queries)
    gut = 0
    for i, a in enumerate(antworten):
        if a == "FAIL":
            bad("real data frame %d could not be decrypted" % (i + 1))
            continue
        roh = bytes.fromhex(a)
        header = len(bytes.fromhex(m["daten"][i])) - len(roh) - 8
        body_bytes = roh[24:]
        if body_bytes[:6] == b"\xaa\xaa\x03\x00\x00\x00":
            gut += 1
        else:
            bad("real data frame %d: no LLC/SNAP in the plaintext (%s)"
                % (i + 1, body_bytes[:8].hex()))
    if gut == len(m["daten"]):
        ok("THE WHOLE CHAIN: password -> PMK -> PTK -> TK -> %d REAL "
           "frames decrypted, each contains LLC/SNAP" % gut)
    b = bytearray.fromhex(tk)
    b[0] ^= 1
    antworten = orakel(["ccmpdec %s %s" % (bytes(b).hex(), f)
                        for f in m["daten"]])
    if all(a == "FAIL" for a in antworten):
        ok("with a TK that has one bit flipped, NONE of the %d "
           "frames" % len(m["daten"]))
    else:
        bad("a wrong TK decrypted a frame")



def part_channel():
    print()
    print("== 5. channels, frequencies and the ETSI table ==")
    for f, k, band in [(2412, 1, 1), (2437, 6, 1), (2472, 13, 1),
                       (2484, 14, 1), (5180, 36, 2), (5320, 64, 2),
                       (5500, 100, 2), (5745, 149, 2), (5955, 1, 3),
                       (6175, 45, 3)]:
        equal("%d MHz is channel %d in band %d" % (f, k, band),
               eins("channel %d" % f), "%d %d" % (k, band))
        equal("and back: channel %d in band %d is %d MHz" % (k, band, f),
               eins("freq %d %d" % (k, band)), str(f))
    for f in [2413, 2500, 5181, 1000, 9999]:
        equal("%d MHz is not a channel" % f, eins("channel %d" % f), "FAIL")
    equal("channel 2 in the 6 GHz band is the outlier 5935 MHz",
           eins("freq 2 3"), "5935")
    equal("channel 2 in the 2.4 GHz band is 2417 MHz", eins("freq 2 1"), "2417")

    faelle = [
        (1, 1, "erlaubt=1 dbm=20 dfs=0 innen=0 passiv=0 tx=1 active=1",
         "channel 1, 2.4 GHz: 20 dBm, no radar, indoor and outdoor"),
        (1, 13, "erlaubt=1 dbm=20 dfs=0 innen=0 passiv=0 tx=1 active=1",
         "channel 13 is allowed in Europe (not in the USA)"),
        (1, 14, "erlaubt=0 dbm=0 dfs=0 innen=0 passiv=0 tx=0 active=0",
         "channel 14 is NOT allocated in Europe"),
        (2, 36, "erlaubt=1 dbm=23 dfs=0 innen=1 passiv=0 tx=1 active=1",
         "channel 36: 23 dBm, indoor only, no radar"),
        (2, 52, "erlaubt=1 dbm=23 dfs=1 innen=1 passiv=1 tx=0 active=0",
         "channel 52: radar required -> without DFS NO transmission"),
        (2, 100, "erlaubt=1 dbm=30 dfs=1 innen=0 passiv=1 tx=0 active=0",
         "channel 100: 30 dBm, radar required -> without DFS NO transmission"),
        (2, 144, "erlaubt=0 dbm=0 dfs=0 innen=0 passiv=0 tx=0 active=0",
         "channel 144 extends past the band edge 5725 -> not allocated"),
        (2, 149, "erlaubt=0 dbm=0 dfs=0 innen=0 passiv=0 tx=0 active=0",
         "channel 149 is not part of the WLAN range in Europe"),
        (2, 165, "erlaubt=0 dbm=0 dfs=0 innen=0 passiv=0 tx=0 active=0",
         "channel 165 likewise"),
        (3, 1, "erlaubt=1 dbm=23 dfs=0 innen=1 passiv=0 tx=1 active=1",
         "channel 1 in the 6 GHz band: 23 dBm, indoor only"),
        (3, 93, "erlaubt=1 dbm=23 dfs=0 innen=1 passiv=0 tx=1 active=1",
         "channel 93 is the last in the European 6 GHz range"),
        (3, 97, "erlaubt=0 dbm=0 dfs=0 innen=0 passiv=0 tx=0 active=0",
         "channel 97 is above 6425 MHz -> not allocated"),
    ]
    for band, k, soll, name in faelle:
        equal(name, eins("etsi %d %d" % (band, k)), soll)
    queries = []
    for band in (1, 2, 3):
        for k in range(0, 250):
            queries.append("etsi %d %d" % (band, k))
    antworten = orakel(queries)
    verstoss = []
    for row in antworten:
        f = dict(x.split("=", 1) for x in row.split(" "))
        if f["tx"] == "1" and (f["erlaubt"] == "0" or f["dfs"] == "1"):
            verstoss.append(row)
        if f["active"] == "1" and (f["erlaubt"] == "0" or f["passiv"] == "1"):
            verstoss.append(row)
    if not verstoss:
        ok("over ALL %d channels in three bands: never transmit without allocation, "
           "never transmit on a radar channel, never scan actively where only "
           "listening is allowed" % len(queries))
    else:
        bad("%d channels violate the rule, first: %s"
            % (len(verstoss), verstoss[0]))


# ==================================================== 6. der Zustandsautomat

ALPHABET = "sbaAcC1234dtx"
RICHTIG = "sbac1234"


def zerlege_automat(row):
    return dict(x.split("=", 1) for x in row.split(" "))


def part_state_machine():
    print()
    print("== 6. the state machine: there is no half connection ==")
    f = zerlege_automat(eins("automat " + RICHTIG))
    equal("the correct sequence '%s' leads to CONNECTED" % RICHTIG,
           f["z"], "8")
    equal("and may send data", f["data"], "1")
    equal("and installed the key EXACTLY ONCE", f["inst"], "1")

    faelle = []
    for i in range(len(RICHTIG)):
        faelle.append(("Omitting '%s' at position %d" % (RICHTIG[i], i),
                       RICHTIG[:i] + RICHTIG[i + 1:]))
        faelle.append(("Repeating '%s' at position %d" % (RICHTIG[i], i),
                       RICHTIG[:i + 1] + RICHTIG[i] + RICHTIG[i + 1:]))
    for i in range(len(RICHTIG) - 1):
        v = list(RICHTIG)
        v[i], v[i + 1] = v[i + 1], v[i]
        faelle.append(("Swapping '%s' and '%s'"
                       % (RICHTIG[i], RICHTIG[i + 1]), "".join(v)))
    for i in range(len(RICHTIG) + 1):
        for c in ALPHABET:
            faelle.append(("Inserting '%s' at position %d" % (c, i),
                           RICHTIG[:i] + c + RICHTIG[i:]))
    queries = ["automat " + sequence for _, sequence in faelle]
    antworten = orakel(queries)
    defective = []
    for (name, sequence), row in zip(faelle, antworten):
        f = zerlege_automat(row)
        erlaubt = is_valid_sequence(sequence)
        if (f["data"] == "1") != erlaubt:
            defective.append((name, sequence, row))
        if int(f["inst"]) > 1:
            defective.append(("MEHRFACHE Installation", sequence, row))
    if not defective:
        ok("all %d mutilations of the correct sequence (omit, "
           "Wiederholen, Vertauschen, Einschieben) enden genau dann in "
           "CONNECTED when they are valid again" % len(faelle))
    else:
        for name, sequence, row in defective[:5]:
            bad("%s ('%s') -> %s" % (name, sequence, row))

    for sequence, why, name in [
        ("sbAc1234", "2", "abgelehnte Authentifizierung -> Grund 2"),
        ("sbacC1234", "1", "'C' after the handshake start -> reason 1"),
        ("sbatc1234", "3", "Zeitueberschreitung -> Grund 3"),
        ("sbacd1234", "4", "deauth in the middle of the handshake -> reason 4"),
        ("sbac1233", "5", "message 3 twice (KRACK) -> reason 5"),
        ("sbac123x", "6", "message 3 with wrong check value -> reason 6"),
    ]:
        f = zerlege_automat(eins("automat " + sequence))
        equal(name, "%s/%s" % (f["z"], f["reason"]), "9/%s" % why)
        if f["data"] != "0":
            bad("'%s' ends in error and may still send data" % sequence)

    tiefe = 3 if QUICK else 4
    folgen = [""]
    every_item = []
    for _ in range(tiefe):
        folgen = [f + c for f in folgen for c in ALPHABET]
        every_item.extend(folgen)
    antworten = orakel(["automat " + f for f in every_item])
    defective = []
    for sequence, row in zip(every_item, antworten):
        f = zerlege_automat(row)
        if f["data"] != "0" or f["inst"] != "0" or f["verbund"] != "0":
            defective.append((sequence, row))
    if not defective:
        ok("EXHAUSTIVE: all %d event sequences up to length %d over an "
           "alphabet of %d -- not a single one connects, none installs "
           "a key" % (len(every_item), tiefe, len(ALPHABET)))
    else:
        bad("%d sequences up to length %d get too far, first: '%s' -> %s"
            % (len(defective), tiefe, defective[0][0], defective[0][1]))

    queries = []
    for sequence in ["sbAc1234", "s1", "d", "sbacd", "sbac1233"]:
        for anhang in ["", "s", "sbac1234", "1234", "tttt"]:
            queries.append("automat " + sequence + anhang)
    antworten = orakel(queries)
    if all(zerlege_automat(a)["z"] == "9" and zerlege_automat(a)["data"] == "0"
           for a in antworten):
        ok("the error state is a dead end: %d sequences that were aborted once "
           "do not come out again with any suffix"
           % len(queries))
    else:
        bad("an aborted sequence came out again")


def is_valid_sequence(sequence):
    i = 0
    n = len(sequence)
    if i >= n or sequence[i] != "s":
        return False
    while i < n and sequence[i] == "s":
        i += 1
    if i >= n or sequence[i] != "b":
        return False
    while i < n and sequence[i] == "b":
        i += 1
    return sequence[i:] == "ac1234"


# ==================================================== 7. die Grenzfaelle

def part_limits():
    print()
    print("== 7. what must NOT pass ==")
    m = read_capture()
    b = m["beacon"][0]
    roh = bytearray.fromhex(b)

    # unverschluesselte Verbindung.
    defective = 0
    queries = []
    laengen = list(range(0, len(roh)))
    for i in laengen:
        queries.append("beacon " + bytes(roh[:i]).hex())
    antworten = orakel(queries)
    for i, a in zip(laengen, antworten):
        if a != "FAIL":
            # kuerzerer Beacon.
            f = dict(x.split("=", 1) for x in a.split(" "))
            if f["sich"] == "0" and "48" in eins("ies " + b):
                defective += 1
    if defective == 0:
        ok("all %d prefixes of the real beacon: none is reported as an OPEN "
           "network although the network is WPA2" % len(laengen))
    else:
        bad("%d truncated beacons were reported as an open network"
            % defective)

    ies_start = 24 + 12
    queries = []
    for lie in (0xFF, 0x80, len(roh)):
        v = bytearray(roh)
        v[ies_start + 1] = lie & 255
        queries.append("beacon " + bytes(v).hex())
        queries.append("ies " + bytes(v).hex())
    antworten = orakel(queries)
    if all(a == "FAIL" or "BROKEN" in a for a in antworten):
        ok("a length field pointing past the end of the frame "
           "is detected and not read")
    else:
        bad("a lying length field got through: %s" % antworten)

    ies = eins("ies " + b)
    at = ies_start
    rsn_at = None
    while at + 2 <= len(roh):
        if roh[at] == 48:
            rsn_at = at
            break
        at += 2 + roh[at + 1]
    if rsn_at is None:
        bad("the real beacon has no RSN element -- test not possible")
    else:
        queries = []
        for value in (0xFFFF, 0x0100, 0x0010):
            v = bytearray(roh)
            v[rsn_at + 2 + 6] = value & 255
            v[rsn_at + 2 + 7] = (value >> 8) & 255
            queries.append("beacon " + bytes(v).hex())
        antworten = orakel(queries)
        if all(a == "FAIL" for a in antworten):
            ok("an RSN element announcing more ciphers than it has "
               "(0xFFFF, 0x0001, 0x1000), is REJECTED")
        else:
            bad("a lying RSN element got through: %s" % antworten)

    for name, roh2 in [
        ("ein Steuerrahmen (ACK)", "d4000000000c4182b255"),
        ("ein data frame", "0842000000000000000000000000000000000000000000"),
        ("two octets", "8000"),
        ("one octet", "80"),
        ("a frame with protocol version 1", "8100" + b[4:]),
    ]:
        equal("%s is not a beacon" % name, eins("beacon " + roh2), "FAIL")

    # EAPOL: die beiden Laengenfelder muessen zueinander passen.
    e = bytearray.fromhex(m["eapol3"])
    v = bytearray(e)
    v[97] = 0xFF
    v[98] = 0xFF
    equal("EAPOL: a key data length of 65535 -> REJECTED",
           eins("eapol " + bytes(v).hex()), "FAIL")
    v = bytearray(e)
    v[2] = 0xFF
    v[3] = 0xFF
    equal("EAPOL: a body length of 65535 -> REJECTED",
           eins("eapol " + bytes(v).hex()), "FAIL")
    v = bytearray(e)
    v[1] = 0
    equal("EAPOL: a packet type other than 3 -> REJECTED",
           eins("eapol " + bytes(v).hex()), "FAIL")
    v = bytearray(e)
    v[4] = 7
    equal("EAPOL: an unknown descriptor type -> REJECTED",
           eins("eapol " + bytes(v).hex()), "FAIL")
    for n in range(0, len(e)):
        pass
    queries = ["eapol " + bytes(e[:n]).hex() for n in range(1, 99)]
    antworten = orakel(queries)
    if all(a == "FAIL" for a in antworten):
        ok("EAPOL: all 98 prefixes below the fixed part -> REJECTED")
    else:
        bad("a too short EAPOL frame got through")

    kck = "00" * 16
    equal("MIC with an unknown key descriptor -> REJECTED",
           eins("mic %s %s 99" % (kck, m["eapol2"])), "FAIL")
    equal("MIC with a KCK of 15 octets -> REJECTED",
           eins("mic %s %s 2" % ("00" * 15, m["eapol2"])), "FAIL")


# ==================================================== 8. WPA3-Ableitung

def part_wpa3():
    print()
    print("== 8. the SHA-256 derivation (WPA3 AKM and PSK-SHA256) ==")
    # gebaut -- Begruendung in docs/WLAN-BEFUND.md Abschnitt 6 --, aber
    #
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
        equal("PTK mit KDF-SHA256, AKM %d (%s)" % (akm, name), ist, soll)
    mit_sha1 = eins("ptk %s %s %s %s %s 2 48"
                    % (pmk.hex(), aa.hex(), spa.hex(), an.hex(), sn.hex()))
    mit_sha256 = eins("ptk %s %s %s %s %s 8 48"
                      % (pmk.hex(), aa.hex(), spa.hex(), an.hex(), sn.hex()))
    if mit_sha1 != mit_sha256:
        ok("AKM 2 (SHA-1) and AKM 8 (SHA-256) give DIFFERENT keys")
    else:
        bad("AKM 2 and AKM 8 gave the same key -- so one "
            "of the two paths computes wrongly")
    m = read_capture()
    a = eins("mic %s %s 2" % ("00" * 16, m["eapol2"]))
    b = eins("mic %s %s 8" % ("00" * 16, m["eapol2"]))
    if a != b and a != "FAIL" and b != "FAIL":
        ok("the check value of AKM 2 (HMAC-SHA1) and AKM 8 (AES-CMAC) is "
           "verschieden")
    else:
        bad("the two check value methods give the same result or fail")
    # sortieren.
    v1 = eins("ptk %s %s %s %s %s 2 48"
              % (pmk.hex(), aa.hex(), spa.hex(), an.hex(), sn.hex()))
    v2 = eins("ptk %s %s %s %s %s 2 48"
              % (pmk.hex(), spa.hex(), aa.hex(), sn.hex(), an.hex()))
    if v1 == v2:
        ok("both sides compute the same PTK although each has its own "
           "Adresse zuerst kennt (min/max)")
    else:
        bad("the sorting of addresses and nonces is missing -- the "
            "both sides get different keys")


# ==================================================================

def main():
    if not os.path.exists(ORAKEL):
        print("  FAIL  %s does not exist -- erst tools/wlan/run.sh" % ORAKEL)
        return 1
    part_sha1()
    part_aes()
    part_ccmp()
    part_capture()
    part_channel()
    part_state_machine()
    part_limits()
    part_wpa3()
    print()
    print("WLAN: %d Zusagen, %d Fehler" % (pass_n, fail_n))
    return 1 if fail_n else 0


if __name__ == "__main__":
    sys.exit(main())
