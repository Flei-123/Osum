#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/wlan/gegenstelle.py -- ein ZWEITES Programm auf der anderen
Seite des Handschlags.

======================================================================
WARUM ES DIESE DATEI GIBT: SCHWACHSTELLE S2 AUS docs/WLAN-BEFUND.md
======================================================================

Die Runde WLAN hat ihren eigenen Befund so geschlossen:

    S2 -- Der 4-Wege-Handschlag ist gegen sich selbst und gegen die
    Normvektoren der Primitiven gemessen, NICHT gegen einen echten
    Zugangspunkt. PRF und PBKDF2 stimmen oktettgleich mit hostapds
    Vektoren; dass die richtigen Oktette in der richtigen Reihenfolge
    in die PRF gehen, folgt aus dem Text der Norm und nicht aus einer
    Messung gegen ein zweites Programm.

Das ist die ehrlichste Zeile des ganzen Befundes und zugleich die
teuerste. Ein Supplicant, der nur gegen sich selbst geprueft wird, ist
gegen einen SYSTEMATISCHEN Denkfehler blind: wer beim Ableiten des PTK
zweimal dieselbe falsche Reihenfolge annimmt -- einmal beim Bauen,
einmal beim Pruefen --, bekommt zwei Mal dasselbe falsche Ergebnis und
sieht gruen. Genau dieser Fehlerklasse ist mit Selbstvergleich nicht
beizukommen.

Diese Datei ist die Antwort darauf. Sie ist ein VOLLSTAENDIGER
WPA2-PSK-AUTHENTICATOR -- also die Gegenseite, der Zugangspunkt --,
geschrieben in Python, unabhaengig von Osums Quelltext, mit einer
anderen Kryptobibliothek darunter (`cryptography` bzw. `hashlib`, also
OpenSSL) und von einem anderen Text abgeleitet: IEEE Std 802.11-2016
Abschnitt 12.7. Sie teilt mit `lib/wlan/wpa.fi` KEINE EINZIGE ZEILE.

Wenn Osums Supplicant und dieses Programm sich auf denselben PTK
einigen, sich gegenseitig die Pruefwerte bestaetigen und am Ende
Nutzdaten austauschen, die die jeweils andere Seite entschluesseln
kann, dann ist das eine Aussage, die kein Selbstvergleich liefern
kann.

======================================================================
WARUM NICHT hostapd
======================================================================

Der Auftrag dieser Runde sagte: gegen hostapd messen. Das waere die
erste Wahl, und es wurde ernsthaft versucht. Der Befund, gemessen auf
DIESEM Rechner am 06.09.2026, steht hier, damit niemand ihn ein
zweites Mal erarbeiten muss:

  * `hostapd` 2.10 und `wpa_supplicant` sind aus Debian installierbar
    und wurden installiert. Sie laufen.
  * Debian baut beide OHNE `CONFIG_TESTING_OPTIONS`. Damit fehlen
    genau die Befehle, mit denen man einen Handschlag ohne Funk
    einspeisen koennte:

        $ hostapd_cli EAPOL_RX ...        -> Unknown command 'EAPOL_RX'
        $ hostapd_cli MGMT_RX_PROCESS ... -> Unknown command
        $ hostapd_cli DATA_TEST_CONFIG 1  -> Unknown command

  * `hostapd -d driver=none` laeuft bis `AP-ENABLED`, leitet PSK, GMK
    und GTK ab -- aber ohne die obigen Befehle kommt kein Rahmen
    hinein und keiner heraus.
  * `hostapd driver=wired` auf einem veth-Paar laeuft ebenfalls bis
    `AP-ENABLED` und EMPFAENGT ueber AF_PACKET echte EAPOL-Rahmen
    (nachgewiesen im Mitschnitt). Er verarbeitet sie aber nicht:

        IEEE 802.1X: Ignore STA - 802.1X not enabled or forced for WPS

    Der `wired`-Treiber ist in hostapd fest auf 802.1X/EAP verdrahtet;
    die WPA-PSK-Zustandsmaschine haengt nicht daran. `NEW_STA` meldet
    eine Station an, startet aber keinen 4-Wege-Handschlag.
  * `wpa_supplicant -D wired` spiegelbildlich:
        WPA: drop TX EAPOL in non-IEEE 802.1X mode
  * `mac80211_hwsim` gibt es nicht: der Kern dieses Rechners
    (7.0.14-5-pve, ein Proxmox-Kern in einem LXC-Behaelter) hat
    ueberhaupt kein `drivers/net/wireless/`. `/dev/net/tun` fehlt
    ebenfalls -- dieselbe Wand, an die Runde K8 schon gelaufen ist
    (siehe den Kopf von `tools/net/bridge.c`).

Ein hostapd ohne Testschalter und ohne Funkgeraet ist also kein
Handschlagpartner. Die Wahl stand damit zwischen "hostapd selbst
uebersetzen" und "die Gegenseite selbst schreiben". Diese Datei ist die
zweite Wahl, und sie ist aus einem Grund die bessere: sie ist ein paar
hundert Zeilen, sie ist lesbar, sie steht im Baum, und sie kann
ABSICHTLICH FALSCH SPIELEN. Der letzte Punkt ist der wichtigste --
siehe `--boese` weiter unten. Ein echter Zugangspunkt haelt sich an die
Norm; ein Angreifer nicht, und die interessanten Fehler eines
Supplicanten liegen dort.

Was diese Datei damit NICHT behauptet: dass Osum sich mit einem echten
Zugangspunkt verbindet. Das braucht eine Karte. Sie behauptet, dass
Osums Rechnung mit der eines zweiten, unabhaengigen Programms
uebereinstimmt -- und das ist genau so viel, wie ohne Karte zu holen
ist.

======================================================================
DER MASSSTAB HINTER DEM MASSSTAB
======================================================================

Ein selbst geschriebener Massstab ist erst dann einer, wenn er selbst
geeicht ist. Diese Datei eicht sich an der ECHTEN AUFZEICHNUNG, die
schon in `tools/wlan/mitschnitt.txt` liegt: aus dem Netz `Coherer` mit
dem Passwort `Induction` rechnet sie PMK, PTK und die Pruefwerte der
Nachrichten 2, 3 und 4 nach und vergleicht sie mit dem, was 2007
wirklich auf dem Draht stand. Erst wenn das stimmt, darf sie Osum
pruefen. Das ist `--selbsttest`, und `run.sh` faehrt ihn ZUERST.
"""

import binascii
import hashlib
import hmac
import os
import struct
import sys

# ---------------------------------------------------------------------
# Krypto. Bewusst aus einer ANDEREN Quelle als lib/crypto/: hashlib und
# `cryptography` sind OpenSSL. Nichts hier ruft Osum-Quelltext auf.
# ---------------------------------------------------------------------

try:
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    from cryptography.hazmat.primitives.ciphers.aead import AESCCM
    HAVE_CRYPTO = True
except Exception:                                     # pragma: no cover
    HAVE_CRYPTO = False


def h(b):
    return binascii.hexlify(b).decode()


def u(s):
    return binascii.unhexlify(s.strip())


def prf_sha1(key, label, data, nbits):
    """IEEE 802.11i 8.5.1.1 -- PRF-n ueber HMAC-SHA1."""
    n = (nbits + 7) // 8
    out = b''
    i = 0
    while len(out) < n:
        out += hmac.new(key, label.encode() + b'\x00' + data + bytes([i]),
                        hashlib.sha1).digest()
        i += 1
    return out[:n]


def kdf_sha256(key, label, data, nbits):
    """IEEE 802.11-2016 12.7.1.2 -- KDF-Hash-Length, hier SHA-256."""
    n = (nbits + 7) // 8
    out = b''
    i = 1
    while len(out) < n:
        out += hmac.new(key, struct.pack('<H', i) + label.encode() + data +
                        struct.pack('<H', nbits), hashlib.sha256).digest()
        i += 1
    return out[:n]


def pmk_aus_psk(passwort, ssid):
    """PBKDF2-HMAC-SHA1, 4096 Runden, 32 Oktette (802.11i H.4)."""
    return hashlib.pbkdf2_hmac('sha1', passwort, ssid, 4096, 32)


def ptk_ableiten(pmk, aa, spa, anonce, snonce, sha256=False, n=48):
    """PTK = PRF(PMK, "Pairwise key expansion", min||max||min||max).

    IEEE 802.11-2016 12.7.1.3. Die kleinere Adresse und die kleinere
    Zufallszahl kommen ZUERST -- genau die Stelle, an der ein
    Selbstvergleich blind ist, weil beide Seiten denselben Fehler
    machen wuerden.
    """
    da = min(aa, spa) + max(aa, spa)
    dn = min(anonce, snonce) + max(anonce, snonce)
    if sha256:
        return kdf_sha256(pmk, "Pairwise key expansion", da + dn, n * 8)
    return prf_sha1(pmk, "Pairwise key expansion", da + dn, n * 8)


def aes_cmac(key, msg):
    """RFC 4493, gebraucht fuer den MIC der SHA-256-AKM."""
    if not HAVE_CRYPTO:
        raise RuntimeError("cryptography fehlt")

    def enc(b):
        c = Cipher(algorithms.AES(key), modes.ECB()).encryptor()
        return c.update(b) + c.finalize()

    def shift(b):
        v = int.from_bytes(b, 'big') << 1
        v &= (1 << 128) - 1
        return v.to_bytes(16, 'big')

    L = enc(b'\x00' * 16)
    K1 = shift(L)
    if L[0] & 0x80:
        K1 = bytes(a ^ b for a, b in zip(K1, b'\x00' * 15 + b'\x87'))
    K2 = shift(K1)
    if K1[0] & 0x80:
        K2 = bytes(a ^ b for a, b in zip(K2, b'\x00' * 15 + b'\x87'))
    if len(msg) and len(msg) % 16 == 0:
        last = bytes(a ^ b for a, b in zip(msg[-16:], K1))
        blocks = msg[:-16]
    else:
        pad = msg[len(msg) - len(msg) % 16:] + b'\x80'
        pad += b'\x00' * (16 - len(pad))
        last = bytes(a ^ b for a, b in zip(pad, K2))
        blocks = msg[:len(msg) - len(msg) % 16]
    x = b'\x00' * 16
    for i in range(0, len(blocks), 16):
        x = enc(bytes(a ^ b for a, b in zip(x, blocks[i:i + 16])))
    return enc(bytes(a ^ b for a, b in zip(x, last)))


def aes_wrap(kek, plain):
    """RFC 3394 Key Wrap."""
    if not HAVE_CRYPTO:
        raise RuntimeError("cryptography fehlt")

    def enc(b):
        c = Cipher(algorithms.AES(kek), modes.ECB()).encryptor()
        return c.update(b) + c.finalize()

    n = len(plain) // 8
    R = [plain[i * 8:(i + 1) * 8] for i in range(n)]
    A = b'\xa6' * 8
    for j in range(6):
        for i in range(n):
            B = enc(A + R[i])
            A = bytes(a ^ b for a, b in
                      zip(B[:8], (n * j + i + 1).to_bytes(8, 'big')))
            R[i] = B[8:]
    return A + b''.join(R)


def aes_unwrap(kek, ct):
    if not HAVE_CRYPTO:
        raise RuntimeError("cryptography fehlt")

    def dec(b):
        c = Cipher(algorithms.AES(kek), modes.ECB()).decryptor()
        return c.update(b) + c.finalize()

    n = len(ct) // 8 - 1
    A = ct[:8]
    R = [ct[8 + i * 8:16 + i * 8] for i in range(n)]
    for j in range(5, -1, -1):
        for i in range(n - 1, -1, -1):
            B = dec(bytes(a ^ b for a, b in
                          zip(A, (n * j + i + 1).to_bytes(8, 'big'))) + R[i])
            A = B[:8]
            R[i] = B[8:]
    if A != b'\xa6' * 8:
        return None
    return b''.join(R)


# ---------------------------------------------------------------------
# EAPOL-Key-Rahmen. IEEE 802.11-2016 12.7.2.
# ---------------------------------------------------------------------

MIC_VERSATZ = 4 + 1 + 2 + 2 + 8 + 32 + 16 + 8 + 8   # = 81


def eapol_bauen(key_info, key_len, replay, nonce, keyrsc, keydata,
                mic=None, iv=b'\x00' * 16, ver=2):
    """Setzt einen EAPOL-Key-Rahmen zusammen. `mic=None` heisst: das
    Feld bleibt null -- so wird es fuer die MIC-Rechnung gebraucht."""
    body = struct.pack('!BHH', 3, key_info, key_len)
    body += struct.pack('!Q', replay)
    body += nonce
    body += iv
    body += struct.pack('!Q', keyrsc)
    body += b'\x00' * 8
    body += (mic if mic is not None else b'\x00' * 16)
    body += struct.pack('!H', len(keydata))
    body += keydata
    return struct.pack('!BB H', ver, 3, len(body)) + body


def eapol_mic_setzen(frame, kck, sha256=False):
    """Rechnet den MIC ueber den GANZEN Rahmen mit MIC-Feld null und
    setzt ihn ein. Genau die Reihenfolge aus 12.7.2."""
    null = frame[:MIC_VERSATZ] + b'\x00' * 16 + frame[MIC_VERSATZ + 16:]
    if sha256:
        m = aes_cmac(kck, null)[:16]
    else:
        m = hmac.new(kck, null, hashlib.sha1).digest()[:16]
    return frame[:MIC_VERSATZ] + m + frame[MIC_VERSATZ + 16:], m


def eapol_mic_pruefen(frame, kck, sha256=False):
    ist = frame[MIC_VERSATZ:MIC_VERSATZ + 16]
    _, soll = eapol_mic_setzen(frame, kck, sha256)
    return hmac.compare_digest(ist, soll), ist, soll


def eapol_zerlegen(frame):
    """Zerlegt einen EAPOL-Key-Rahmen in ein Woerterbuch. Bewusst
    streng: was nicht passt, wirft."""
    if len(frame) < 4:
        raise ValueError("zu kurz fuer den EAPOL-Kopf")
    ver, typ, blen = struct.unpack('!BBH', frame[:4])
    if typ != 3:
        raise ValueError("kein EAPOL-Key (Typ %d)" % typ)
    b = frame[4:4 + blen]
    if len(b) < 95:
        raise ValueError("EAPOL-Key-Rumpf zu kurz: %d" % len(b))
    d = {}
    d['ver'] = ver
    d['desc'] = b[0]
    d['key_info'] = struct.unpack('!H', b[1:3])[0]
    d['key_len'] = struct.unpack('!H', b[3:5])[0]
    d['replay'] = struct.unpack('!Q', b[5:13])[0]
    d['nonce'] = b[13:45]
    d['iv'] = b[45:61]
    d['rsc'] = b[61:69]
    d['mic'] = b[77:93]
    dlen = struct.unpack('!H', b[93:95])[0]
    d['keydata'] = b[95:95 + dlen]
    d['pairwise'] = bool(d['key_info'] & 0x0008)
    d['install'] = bool(d['key_info'] & 0x0040)
    d['ack'] = bool(d['key_info'] & 0x0080)
    d['mic_gesetzt'] = bool(d['key_info'] & 0x0100)
    d['secure'] = bool(d['key_info'] & 0x0200)
    d['encrypted'] = bool(d['key_info'] & 0x1000)
    d['akm_sha256'] = (d['key_info'] & 0x0007) == 3
    return d


def gtk_kde(gtk, idx=1):
    """Das GTK-KDE aus 802.11-2016 12.7.2, Tabelle 12-8."""
    inner = bytes([idx & 3, 0]) + gtk
    return bytes([0xDD, len(inner) + 4, 0x00, 0x0F, 0xAC, 0x01]) + inner


# ---------------------------------------------------------------------
# CCMP. IEEE 802.11-2016 12.5.3.
# ---------------------------------------------------------------------

def kopf_laenge(hdr):
    """Dieselbe Rechnung wie `kopf_laenge` in lib/wlan/rahmen.fi.

    Sie steht hier nachgebaut und nicht geraten, weil der erste Anlauf
    dieser Datei genau daran gescheitert ist: beim Vektor M.6.4 ist
    FC = 0x4808, also Untertyp 0 (ein GEWOEHNLICHER Datenrahmen) mit
    gesetztem ORDNUNGSBIT -- und nicht, wie zuerst angenommen, ein
    QoS-Rahmen. Der Kopf ist deshalb 24 Oktette lang und `f8ba` ist
    schon Nutzlast.
    """
    fc = struct.unpack('<H', hdr[0:2])[0]
    typ = (fc >> 2) & 3
    untertyp = (fc >> 4) & 15
    adr4 = (fc & 0x0300) == 0x0300
    qos = (typ == 2) and (untertyp & 8) != 0
    l = 24
    if typ == 2:
        if adr4:
            l += 6
        if qos:
            l += 2
    # Das Ordnungsbit heisst nur bei Verwaltungs- und QoS-Datenrahmen
    # "HT-Control" (vier Oktette); bei Daten ohne QoS heisst es
    # "streng geordnet" und fuegt nichts hinzu.
    if fc & 0x8000:
        if typ == 0 or (typ == 2 and qos):
            l += 4
    return l


def ccmp_nonce(a2, pn, prio=0):
    """Nonce = Kennzeichen || A2 || PN, die PN HOECHSTWERTIG ZUERST.

    Die Reihenfolge ist ueberall in dieser Datei dieselbe wie in
    `lib/wlan/ccmp.fi` und wie die Norm sie in ihren Vektoren druckt
    ("PN: b5 03 97 76 e7 0c"): pn[0] ist PN5. Sie wird NICHT gedreht --
    gedreht wird nur im CCMP-KOPF, und das passiert in `ccmp_kopf`.
    Der erste Anlauf dieser Datei drehte sie hier zusaetzlich um und
    bekam damit gegen den Vektor M.6.4 einen anderen Geheimtext.
    """
    return bytes([prio & 0x0F]) + a2 + pn


def ccmp_aad(hdr):
    """AAD nach IEEE 802.11-2016 12.5.3.3.3.

    Die maskierten Felder sind genau die, die ein Vermittler unterwegs
    aendern darf. Zwei Stellen, an denen der erste Anlauf dieser Datei
    danebenlag und `lib/wlan/ccmp.fi` recht hatte:

      * Es sind DREI Adressen (18 Oktette, A1||A2||A3), nicht zwei.
      * Die Untertyp-Maske ~0x0070 gilt nur fuer Datenrahmen; bei
        einem QoS-Rahmen faellt zusaetzlich das Ordnungsbit weg.

    Beides ist mit dem Vektor IEEE Std 802.11-2012 M.6.4 nachgemessen.
    """
    fc = struct.unpack('<H', hdr[0:2])[0]
    typ = (fc >> 2) & 3
    untertyp = (fc >> 4) & 15
    qos = (typ == 2) and (untertyp & 8) != 0
    adr4 = (fc & 0x0300) == 0x0300
    if typ == 2:
        fc &= ~0x0070      # die Untertyp-Bits, nur bei Daten
        if qos:
            fc &= ~0x8000  # das Ordnungsbit, nur bei QoS
    fc &= ~0x0800          # Wiederholung
    fc &= ~0x1000          # Stromsparen
    fc &= ~0x2000          # mehr Daten
    fc |= 0x4000           # geschuetzt
    aad = struct.pack('<H', fc) + hdr[4:22]     # A1 || A2 || A3
    sc = struct.unpack('<H', hdr[22:24])[0] & 0x000F
    aad += struct.pack('<H', sc)
    at = 24
    if adr4:
        aad += hdr[24:30]
        at = 30
    if qos:
        aad += bytes([hdr[at] & 0x0F, 0])
    return aad


def ccmp_kopf(pn, keyid=0):
    """Der 8-Oktett-CCMP-Kopf. Die Reihenfolge ist der Fehler, den die
    Runde WLAN beim ersten Lauf gemacht hat -- pn[0] ist PN5."""
    return bytes([pn[5], pn[4], 0x00, 0x20 | ((keyid & 3) << 6),
                  pn[3], pn[2], pn[1], pn[0]])


def _prio_aus(hdr):
    """Die Verkehrsklasse steht im QoS-Feld des Kopfes -- sie wird
    nicht geraten."""
    fc = struct.unpack('<H', hdr[0:2])[0]
    typ = (fc >> 2) & 3
    untertyp = (fc >> 4) & 15
    if typ == 2 and (untertyp & 8):
        at = 30 if (fc & 0x0300) == 0x0300 else 24
        if len(hdr) > at:
            return hdr[at] & 0x0F
    return 0


def ccmp_schuetzen(tk, hdr, plain, pn, prio=None):
    if not HAVE_CRYPTO:
        raise RuntimeError("cryptography fehlt")
    if prio is None:
        prio = _prio_aus(hdr)
    a2 = hdr[10:16]
    c = AESCCM(tk, tag_length=8)
    ct = c.encrypt(ccmp_nonce(a2, pn, prio), plain, ccmp_aad(hdr))
    return hdr + ccmp_kopf(pn) + ct


def ccmp_oeffnen(tk, mpdu, hlen=None, prio=None):
    if not HAVE_CRYPTO:
        raise RuntimeError("cryptography fehlt")
    if hlen is None:
        hlen = kopf_laenge(mpdu)
    hdr = mpdu[:hlen]
    if prio is None:
        prio = _prio_aus(hdr)
    kopf = mpdu[hlen:hlen + 8]
    # zurueck in "hoechstwertig zuerst": PN5..PN0
    pn = bytes([kopf[7], kopf[6], kopf[5], kopf[4], kopf[1], kopf[0]])
    a2 = hdr[10:16]
    c = AESCCM(tk, tag_length=8)
    return c.decrypt(ccmp_nonce(a2, pn, prio), mpdu[hlen + 8:], ccmp_aad(hdr))


# ---------------------------------------------------------------------
# Der Authenticator als Zustandsmaschine.
# ---------------------------------------------------------------------

class Authenticator:
    """Die AP-Seite eines WPA2-PSK-Handschlags.

    `boese` laesst ihn absichtlich von der Norm abweichen -- das ist
    der Teil, den ein echter Zugangspunkt NICHT kann und der die
    interessanten Fehler eines Supplicanten findet.
    """

    def __init__(self, ssid, passwort, aa, spa, sha256=False,
                 gtk=None, anonce=None, boese=None):
        self.ssid = ssid
        self.aa = aa
        self.spa = spa
        self.sha256 = sha256
        self.boese = boese or set()
        self.pmk = pmk_aus_psk(passwort, ssid)
        self.anonce = anonce or os.urandom(32)
        self.gtk = gtk or os.urandom(16)
        self.replay = 1
        self.snonce = None
        self.ptk = None
        self.rsn_ie = u('30140100000fac040100000fac04'
                        '0100000fac' + ('06' if sha256 else '02') + '0000')

    # -- die Teile des PTK, nach 12.7.1.3 --
    @property
    def kck(self):
        return self.ptk[0:16]

    @property
    def kek(self):
        return self.ptk[16:32]

    @property
    def tk(self):
        return self.ptk[32:48]

    def nachricht1(self):
        """A -> S: ANonce, kein MIC."""
        ki = 0x008A if not self.sha256 else 0x008B
        return eapol_bauen(ki, 16, self.replay, self.anonce, 0, b'')

    def nachricht2_pruefen(self, frame):
        d = eapol_zerlegen(frame)
        if not d['mic_gesetzt']:
            raise ValueError("Nachricht 2 ohne MIC")
        if d['replay'] != self.replay:
            raise ValueError("Nachricht 2 mit falschem Replay-Zaehler: "
                             "%d statt %d" % (d['replay'], self.replay))
        self.snonce = d['nonce']
        self.ptk = ptk_ableiten(self.pmk, self.aa, self.spa,
                                self.anonce, self.snonce, self.sha256)
        ok, ist, soll = eapol_mic_pruefen(frame, self.kck, self.sha256)
        if not ok:
            raise ValueError("MIC von Nachricht 2 falsch: %s statt %s"
                             % (h(ist), h(soll)))
        return d

    def nachricht3(self):
        """A -> S: GTK verpackt, MIC, Install-Bit."""
        self.replay += 1
        kd = self.rsn_ie + gtk_kde(self.gtk, 1)
        while len(kd) % 8:
            kd += b'\xdd'
        if 'gtk_falsch_gepackt' in self.boese:
            verpackt = kd
        else:
            verpackt = aes_wrap(self.kek, kd)
        ki = 0x13CA if not self.sha256 else 0x13CB
        f = eapol_bauen(ki, 16, self.replay, self.anonce, 0, verpackt)
        if 'mic3_falsch' in self.boese:
            return f[:MIC_VERSATZ] + b'\x00' * 16 + f[MIC_VERSATZ + 16:]
        f, _ = eapol_mic_setzen(f, self.kck, self.sha256)
        return f

    def nachricht4_pruefen(self, frame):
        d = eapol_zerlegen(frame)
        if d['replay'] != self.replay:
            raise ValueError("Nachricht 4 mit falschem Replay-Zaehler")
        ok, ist, soll = eapol_mic_pruefen(frame, self.kck, self.sha256)
        if not ok:
            raise ValueError("MIC von Nachricht 4 falsch: %s statt %s"
                             % (h(ist), h(soll)))
        return d


# ---------------------------------------------------------------------
# Selbsttest: der Massstab eicht sich an der ECHTEN Aufzeichnung.
# ---------------------------------------------------------------------

def lade_mitschnitt(pfad):
    d = {}
    mehr = {}
    for zeile in open(pfad, encoding='utf-8'):
        zeile = zeile.strip()
        if not zeile or zeile.startswith('#'):
            continue
        teil = zeile.split(None, 1)
        if len(teil) != 2:
            continue
        k, v = teil
        if k in d:
            mehr.setdefault(k, [d[k]]).append(v)
        else:
            d[k] = v
        mehr.setdefault(k, []).append(v) if k in mehr else None
    return d


def selbsttest(pfad):
    """Rechnet die echte Aufzeichnung nach. Erst wenn das stimmt, ist
    dieses Programm ein Massstab."""
    m = lade_mitschnitt(pfad)
    fehler = 0
    gut = 0

    def pruef(name, ist, soll):
        nonlocal fehler, gut
        if ist == soll:
            gut += 1
            print("  OK    %s" % name)
        else:
            fehler += 1
            print("  FAIL  %s: %s statt %s" % (name, ist, soll))

    pw = u(m['pwhex'])
    ssid = u(m['ssidhex'])
    aa = u(m['aa'])
    spa = u(m['spa'])
    e1 = u(m['eapol1'])
    e2 = u(m['eapol2'])
    e3 = u(m['eapol3'])
    e4 = u(m['eapol4'])

    pmk = pmk_aus_psk(pw, ssid)
    pruef("PMK aus 'Induction'/'Coherer' (PBKDF2, 4096 Runden)",
          h(pmk),
          "a288fcf0caaacda9a9f58633ff35e8992a01d9c10ba5e02efdf8cb5d730ce7bc")

    d1 = eapol_zerlegen(e1)
    d2 = eapol_zerlegen(e2)
    anonce = d1['nonce']
    snonce = d2['nonce']
    ptk = ptk_ableiten(pmk, aa, spa, anonce, snonce)
    kck = ptk[0:16]

    # Der eigentliche Punkt: die Pruefwerte, die 2007 auf dem Draht
    # standen, muessen sich nachrechnen lassen.
    for name, fr in (("2", e2), ("3", e3), ("4", e4)):
        ok, ist, soll = eapol_mic_pruefen(fr, kck)
        pruef("Pruefwert von Nachricht %s stimmt mit dem echten Draht" % name,
              h(ist), h(soll))

    # Der Gruppenschluessel aus Nachricht 3.
    d3 = eapol_zerlegen(e3)
    kek = ptk[16:32]
    kd = aes_unwrap(kek, d3['keydata'])
    if kd is None:
        fehler += 1
        print("  FAIL  Schluesseldaten von Nachricht 3 lassen sich nicht auspacken")
    else:
        gut += 1
        print("  OK    Schluesseldaten von Nachricht 3 ausgepackt (%d Oktette)"
              % len(kd))

    return gut, fehler


def main():
    if '--selbsttest' in sys.argv:
        i = sys.argv.index('--selbsttest')
        pfad = sys.argv[i + 1] if len(sys.argv) > i + 1 else \
            os.path.join(os.path.dirname(__file__), 'mitschnitt.txt')
        print("== die Gegenstelle eicht sich an der echten Aufzeichnung ==")
        gut, fehler = selbsttest(pfad)
        print("GEGENSTELLE-SELBSTTEST: %d Zusagen, %d Fehler" % (gut, fehler))
        return 1 if fehler else 0
    print(__doc__)
    return 0


if __name__ == '__main__':
    sys.exit(main())
