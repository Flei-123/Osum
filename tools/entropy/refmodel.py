import hashlib
import hmac
import struct

M32 = 0xFFFFFFFF
RCT_CUTOFF = 21
APT_WINDOW = 512
APT_CUTOFF = 410


def rotl(x, n):
    return ((x << n) | (x >> (32 - n))) & M32


def chacha_block(key, nonce, counter):
    s = list(struct.unpack('<4I', b'expand 32-byte k')) + list(struct.unpack('<8I', key)) + [counter & M32] + list(struct.unpack('<3I', nonce))
    w = s[:]

    def qr(a, b, c, d):
        w[a] = (w[a] + w[b]) & M32; w[d] = rotl(w[d] ^ w[a], 16)
        w[c] = (w[c] + w[d]) & M32; w[b] = rotl(w[b] ^ w[c], 12)
        w[a] = (w[a] + w[b]) & M32; w[d] = rotl(w[d] ^ w[a], 8)
        w[c] = (w[c] + w[d]) & M32; w[b] = rotl(w[b] ^ w[c], 7)
    for _ in range(10):
        qr(0, 4, 8, 12); qr(1, 5, 9, 13); qr(2, 6, 10, 14); qr(3, 7, 11, 15)
        qr(0, 5, 10, 15); qr(1, 6, 11, 12); qr(2, 7, 8, 13); qr(3, 4, 9, 14)
    return struct.pack('<16I', *[(w[i] + s[i]) & M32 for i in range(16)])


def b2s(data):
    return hashlib.blake2s(data).digest()


class Pool:
    def __init__(self):
        self.chain = bytes(32)

    def step(self, tag, data):
        return b2s(self.chain + bytes([tag]) + struct.pack('<Q', len(data)) + data)

    def mix(self, data):
        self.chain = self.step(0x4D, data)

    def extract(self):
        out = self.step(0x58, b'')
        self.chain = self.step(0x41, b'')
        return out


class Drbg:
    def __init__(self):
        self.key = bytes(32)
        self.generation = 0

    def reseed(self, seed):
        self.key = b2s(self.key + seed)
        self.generation += 1

    def generate(self, n):
        nonce = struct.pack('<Q', self.generation) + bytes(4)
        first = chacha_block(self.key, nonce, 0)
        self.key = first[:32]
        rk = first[32:]
        out = b''
        counter = 1
        while len(out) < n:
            out += chacha_block(rk, nonce, counter)
            counter += 1
        return out[:n]


class Health:
    def __init__(self):
        self.rv = 0
        self.rr = 0
        self.av = 0
        self.seen = 0
        self.hits = 0
        self.failures = 0

    def feed(self, s):
        ok = True
        if self.rr > 0 and s == self.rv:
            self.rr += 1
            if self.rr >= RCT_CUTOFF:
                ok = False
                self.rr = 1
        else:
            self.rv = s
            self.rr = 1
        if self.seen == 0:
            self.av = s
            self.hits = 1
            self.seen = 1
        else:
            self.seen += 1
            if s == self.av:
                self.hits += 1
                if self.hits >= APT_CUTOFF:
                    ok = False
                    self.hits = 0
            if self.seen >= APT_WINDOW:
                self.seen = 0
        if not ok:
            self.failures += 1
        return ok


def seedfile_encode(counter, seed, key):
    body = bytes([79, 83, 82, 78, 68, 83, 68, 49]) + struct.pack('<Q', counter) + seed
    return body + hmac.new(key, body, hashlib.blake2s).digest()
