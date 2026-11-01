#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

import binascii
import hashlib
import hmac
import os
import struct
import sys

# ---------------------------------------------------------------------
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
    n = (nbits + 7) // 8
    out = b''
    i = 0
    while len(out) < n:
        out += hmac.new(key, label.encode() + b'\x00' + data + bytes([i]),
                        hashlib.sha1).digest()
        i += 1
    return out[:n]


def kdf_sha256(key, label, data, nbits):
    n = (nbits + 7) // 8
    out = b''
    i = 1
    while len(out) < n:
        out += hmac.new(key, struct.pack('<H', i) + label.encode() + data +
                        struct.pack('<H', nbits), hashlib.sha256).digest()
        i += 1
    return out[:n]


def pmk_aus_psk(passwort, ssid):
    return hashlib.pbkdf2_hmac('sha1', passwort, ssid, 4096, 32)


def ptk_ableiten(pmk, aa, spa, anonce, snonce, sha256=False, n=48):
    da = min(aa, spa) + max(aa, spa)
    dn = min(anonce, snonce) + max(anonce, snonce)
    if sha256:
        return kdf_sha256(pmk, "Pairwise key expansion", da + dn, n * 8)
    return prf_sha1(pmk, "Pairwise key expansion", da + dn, n * 8)


def aes_cmac(key, msg):
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

MIC_OFFSET = 4 + 1 + 2 + 2 + 8 + 32 + 16 + 8 + 8   # = 81


def build_eapol(key_info, key_len, replay, nonce, keyrsc, keydata,
                mic=None, iv=b'\x00' * 16, ver=2, deskriptor=2):
    body = struct.pack('!BHH', deskriptor, key_info, key_len)
    body += struct.pack('!Q', replay)
    body += nonce
    body += iv
    body += struct.pack('!Q', keyrsc)
    body += b'\x00' * 8
    body += (mic if mic is not None else b'\x00' * 16)
    body += struct.pack('!H', len(keydata))
    body += keydata
    return struct.pack('!BB H', ver, 3, len(body)) + body


def set_eapol_mic(frame, kck, sha256=False):
    null = frame[:MIC_OFFSET] + b'\x00' * 16 + frame[MIC_OFFSET + 16:]
    if sha256:
        m = aes_cmac(kck, null)[:16]
    else:
        m = hmac.new(kck, null, hashlib.sha1).digest()[:16]
    return frame[:MIC_OFFSET] + m + frame[MIC_OFFSET + 16:], m


def check_eapol_mic(frame, kck, sha256=False):
    ist = frame[MIC_OFFSET:MIC_OFFSET + 16]
    _, soll = set_eapol_mic(frame, kck, sha256)
    return hmac.compare_digest(ist, soll), ist, soll


def eapol_zerlegen(frame):
    if len(frame) < 4:
        raise ValueError("too short for the EAPOL header")
    ver, typ, blen = struct.unpack('!BBH', frame[:4])
    if typ != 3:
        raise ValueError("not an EAPOL key (type %d)" % typ)
    b = frame[4:4 + blen]
    if len(b) < 95:
        raise ValueError("EAPOL key body too short: %d" % len(b))
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
    inner = bytes([idx & 3, 0]) + gtk
    return bytes([0xDD, len(inner) + 4, 0x00, 0x0F, 0xAC, 0x01]) + inner


# ---------------------------------------------------------------------
# CCMP. IEEE 802.11-2016 12.5.3.
# ---------------------------------------------------------------------

def header_len(hdr):
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
    # "streng geordnet" und fuegt nichts hinzu.
    if fc & 0x8000:
        if typ == 0 or (typ == 2 and qos):
            l += 4
    return l


def ccmp_nonce(a2, pn, prio=0):
    return bytes([prio & 0x0F]) + a2 + pn


def ccmp_aad(hdr):
    fc = struct.unpack('<H', hdr[0:2])[0]
    typ = (fc >> 2) & 3
    untertyp = (fc >> 4) & 15
    qos = (typ == 2) and (untertyp & 8) != 0
    adr4 = (fc & 0x0300) == 0x0300
    if typ == 2:
        fc &= ~0x0070
        if qos:
            fc &= ~0x8000
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


def ccmp_header(pn, keyid=0):
    return bytes([pn[5], pn[4], 0x00, 0x20 | ((keyid & 3) << 6),
                  pn[3], pn[2], pn[1], pn[0]])


def _prio_aus(hdr):
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
    return hdr + ccmp_header(pn) + ct


def ccmp_open(tk, mpdu, hlen=None, prio=None):
    if not HAVE_CRYPTO:
        raise RuntimeError("cryptography fehlt")
    if hlen is None:
        hlen = header_len(mpdu)
    hdr = mpdu[:hlen]
    if prio is None:
        prio = _prio_aus(hdr)
    header = mpdu[hlen:hlen + 8]
    # zurueck in "hoechstwertig zuerst": PN5..PN0
    pn = bytes([header[7], header[6], header[5], header[4], header[1], header[0]])
    a2 = hdr[10:16]
    c = AESCCM(tk, tag_length=8)
    return c.decrypt(ccmp_nonce(a2, pn, prio), mpdu[hlen + 8:], ccmp_aad(hdr))


# ---------------------------------------------------------------------
# ---------------------------------------------------------------------

class Authenticator:

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
        ki = 0x008A if not self.sha256 else 0x008B
        return build_eapol(ki, 16, self.replay, self.anonce, 0, b'')

    def check_message2(self, frame):
        d = eapol_zerlegen(frame)
        if not d['mic_gesetzt']:
            raise ValueError("message 2 without MIC")
        if d['replay'] != self.replay:
            raise ValueError("message 2 with wrong replay counter: "
                             "%d statt %d" % (d['replay'], self.replay))
        self.snonce = d['nonce']
        self.ptk = ptk_ableiten(self.pmk, self.aa, self.spa,
                                self.anonce, self.snonce, self.sha256)
        ok, ist, soll = check_eapol_mic(frame, self.kck, self.sha256)
        if not ok:
            raise ValueError("MIC of message 2 wrong: %s instead of %s"
                             % (h(ist), h(soll)))
        return d

    def nachricht3(self):
        self.replay += 1
        kd = self.rsn_ie + gtk_kde(self.gtk, 1)
        while len(kd) % 8:
            kd += b'\xdd'
        if 'gtk_falsch_gepackt' in self.boese:
            verpackt = kd
        else:
            verpackt = aes_wrap(self.kek, kd)
        ki = 0x13CA if not self.sha256 else 0x13CB
        f = build_eapol(ki, 16, self.replay, self.anonce, 0, verpackt)
        if 'mic3_falsch' in self.boese:
            return f[:MIC_OFFSET] + b'\x00' * 16 + f[MIC_OFFSET + 16:]
        f, _ = set_eapol_mic(f, self.kck, self.sha256)
        return f

    def check_message4(self, frame):
        d = eapol_zerlegen(frame)
        if d['replay'] != self.replay:
            raise ValueError("message 4 with wrong replay counter")
        ok, ist, soll = check_eapol_mic(frame, self.kck, self.sha256)
        if not ok:
            raise ValueError("MIC of message 4 wrong: %s instead of %s"
                             % (h(ist), h(soll)))
        return d


# ---------------------------------------------------------------------
# ---------------------------------------------------------------------

def load_capture(file_path):
    d = {}
    mehr = {}
    for row in open(file_path, encoding='utf-8'):
        row = row.strip()
        if not row or row.startswith('#'):
            continue
        part = row.split(None, 1)
        if len(part) != 2:
            continue
        k, v = part
        if k in d:
            mehr.setdefault(k, [d[k]]).append(v)
        else:
            d[k] = v
        mehr.setdefault(k, []).append(v) if k in mehr else None
    return d


def selbsttest(file_path):
    m = load_capture(file_path)
    error_list = 0
    gut = 0

    def verify(name, ist, soll):
        nonlocal error_list, gut
        if ist == soll:
            gut += 1
            print("  OK    %s" % name)
        else:
            error_list += 1
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
    verify("PMK aus 'Induction'/'Coherer' (PBKDF2, 4096 Runden)",
          h(pmk),
          "a288fcf0caaacda9a9f58633ff35e8992a01d9c10ba5e02efdf8cb5d730ce7bc")

    d1 = eapol_zerlegen(e1)
    d2 = eapol_zerlegen(e2)
    anonce = d1['nonce']
    snonce = d2['nonce']
    ptk = ptk_ableiten(pmk, aa, spa, anonce, snonce)
    kck = ptk[0:16]

    # standen, muessen sich nachrechnen lassen.
    for name, fr in (("2", e2), ("3", e3), ("4", e4)):
        ok, ist, soll = check_eapol_mic(fr, kck)
        verify("check value of message %s matches the real wire" % name,
              h(ist), h(soll))

    d3 = eapol_zerlegen(e3)
    kek = ptk[16:32]
    kd = aes_unwrap(kek, d3['keydata'])
    if kd is None:
        error_list += 1
        print("  FAIL  key data of message 3 cannot be unwrapped")
    else:
        gut += 1
        print("  OK    key data of message 3 unwrapped (%d octets)"
              % len(kd))

    return gut, error_list


# =====================================================================
# =====================================================================
#
#
# keine teilt.


def ip2i(s):
    """'192.168.0.1' -> 3232235521"""
    a, b, c, d = (int(x) for x in s.split('.'))
    return (a << 24) | (b << 16) | (c << 8) | d


def sum16(daten, start=0):
    s = start
    i = 0
    while i + 1 < len(daten):
        s += (daten[i] << 8) | daten[i + 1]
        i += 2
    if i < len(daten):
        s += daten[i] << 8
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF


def pseudo(qip, zip_, proto, length):
    return ((qip >> 16) + (qip & 0xFFFF) + (zip_ >> 16) +
            (zip_ & 0xFFFF) + proto + length)


def build_ipv4(qip, zip_, proto, nutz, kennung=1):
    header = bytearray(20)
    header[0] = 0x45
    struct.pack_into('>H', header, 2, 20 + len(nutz))
    struct.pack_into('>H', header, 4, kennung)
    struct.pack_into('>H', header, 6, 0x4000)
    header[8] = 64
    header[9] = proto
    struct.pack_into('>I', header, 12, qip)
    struct.pack_into('>I', header, 16, zip_)
    struct.pack_into('>H', header, 10, sum16(bytes(header)))
    return bytes(header) + nutz


def build_udp(qip, zip_, qport, zport, nutz):
    header = bytearray(8)
    struct.pack_into('>H', header, 0, qport)
    struct.pack_into('>H', header, 2, zport)
    struct.pack_into('>H', header, 4, 8 + len(nutz))
    ganz = bytes(header) + nutz
    s = sum16(ganz, pseudo(qip, zip_, 17, len(ganz)))
    if s == 0:
        s = 0xFFFF
    struct.pack_into('>H', header, 6, s)
    return bytes(header) + nutz


def build_tcp(qip, zip_, qport, zport, seq, ack, flags, nutz=b''):
    header = bytearray(20)
    struct.pack_into('>H', header, 0, qport)
    struct.pack_into('>H', header, 2, zport)
    struct.pack_into('>I', header, 4, seq)
    struct.pack_into('>I', header, 8, ack)
    header[12] = 0x50
    header[13] = flags
    struct.pack_into('>H', header, 14, 8192)
    ganz = bytes(header) + nutz
    struct.pack_into('>H', header, 16,
                     sum16(ganz, pseudo(qip, zip_, 6, len(ganz))))
    return bytes(header) + nutz


def build_dhcp_ack(xid, mac, angeboten, server, maske, tor, dns,
                   miete=86400, art=5):
    b = bytearray(240)
    b[0] = 2           # op: Antwort
    b[1] = 1           # htype: Ethernet
    b[2] = 6           # hlen
    struct.pack_into('>I', b, 4, xid)
    struct.pack_into('>I', b, 16, angeboten)   # yiaddr
    struct.pack_into('>I', b, 20, server)      # siaddr
    b[28:34] = mac
    b[236:240] = bytes([99, 130, 83, 99])      # die Zauberzahl
    o = bytearray()
    o += bytes([53, 1, art])
    o += bytes([54, 4]) + struct.pack('>I', server)
    o += bytes([51, 4]) + struct.pack('>I', miete)
    o += bytes([1, 4]) + struct.pack('>I', maske)
    o += bytes([3, 4]) + struct.pack('>I', tor)
    o += bytes([6, 4]) + struct.pack('>I', dns)
    o += bytes([255])
    return bytes(b) + bytes(o)


def snap(ethertype=0x0800):
    return bytes([0xAA, 0xAA, 0x03, 0x00, 0x00, 0x00]) + \
        struct.pack('>H', ethertype)


def datenkopf(bssid, target, source, fromds=True, seq=0,
              geschuetzt=False):
    # GESENDET WIRD.
    #
    #
    # nicht gibt.
    fc = 0x0208 if fromds else 0x0108
    if geschuetzt:
        fc |= 0x4000
    return struct.pack('<H', fc) + b'\x00\x00' + target + bssid + \
        source + struct.pack('<H', seq << 4)


class Zugangspunkt:

    def __init__(self, tk, bssid, klient, ip_server='192.168.0.1',
                 ip_klient='192.168.0.50', maske='255.255.255.0'):
        self.tk = tk
        self.bssid = bssid
        self.klient = klient
        self.server = ip2i(ip_server)
        self.klient_ip = ip2i(ip_klient)
        self.maske = ip2i(maske)
        self.pn = 1

    def _pn(self):
        p = self.pn
        self.pn += 1
        return bytes([0, 0, 0, 0, (p >> 8) & 255, p & 255])

    def _frame(self, nutzlast_ip, seq=0):
        hdr = datenkopf(self.bssid, self.klient, self.bssid, True, seq,
                        geschuetzt=True)
        klar = snap(0x0800) + nutzlast_ip
        return ccmp_schuetzen(self.tk, hdr, klar, self._pn())

    def dhcp_reply(self, xid, art=5, seq=1):
        d = build_dhcp_ack(xid, self.klient, self.klient_ip,
                           self.server, self.maske, self.server,
                           self.server, art=art)
        u = build_udp(self.server, self.klient_ip, 67, 68, d)
        return self._frame(build_ipv4(self.server, self.klient_ip,
                                       17, u, 2), seq)

    def http_reply(self, rumpf=b'OsumOK', seq=2, status=b'200 OK'):
        header = b'HTTP/1.0 ' + status + b'\r\n' + \
            b'Content-Type: text/plain\r\n' + \
            b'Content-Length: ' + str(len(rumpf)).encode() + b'\r\n' + \
            b'\r\n'
        t = build_tcp(self.server, self.klient_ip, 80, 40000,
                      1000, 1, 0x18, header + rumpf)
        return self._frame(build_ipv4(self.server, self.klient_ip,
                                       6, t, 3), seq)

    def echo(self, nutz=b'ABCDEFG', seq=0):
        u = build_udp(self.server, self.klient_ip, 67, 68, nutz)
        return self._frame(build_ipv4(self.server, self.klient_ip,
                                       17, u, 4), seq)

    def open_frame(self, mpdu):
        return ccmp_open(self.tk, mpdu)


def main():
    if '--selbsttest' in sys.argv:
        i = sys.argv.index('--selbsttest')
        file_path = sys.argv[i + 1] if len(sys.argv) > i + 1 else \
            os.path.join(os.path.dirname(__file__), 'mitschnitt.txt')
        print("== the peer calibrates itself on the real capture ==")
        gut, error_list = selbsttest(file_path)
        print("GEGENSTELLE-SELBSTTEST: %d Zusagen, %d Fehler" % (gut, error_list))
        return 1 if error_list else 0
    print(__doc__)
    return 0


if __name__ == '__main__':
    sys.exit(main())
