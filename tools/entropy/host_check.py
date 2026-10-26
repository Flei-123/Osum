import os
import random
import struct
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import refmodel as R

oracle = sys.argv[1]
ok = 0
bad = 0


def check(name, cond, detail=''):
    global ok, bad
    if cond:
        ok += 1
        print('  OK    %s' % name)
    else:
        bad += 1
        print('  FAIL  %s %s' % (name, detail))


def run(script):
    r = subprocess.run([oracle], input=script, capture_output=True, timeout=120)
    return r.stdout


def cmd_c(key, nonce, ctr):
    return b'C' + key + nonce + struct.pack('<I', ctr)


rfc_key = bytes(range(32))
rfc_nonce = bytes.fromhex('000000090000004a00000000')
rfc_expect = bytes.fromhex(
    '10f1e7e4d13b5915500fdd1fa32071c4c7d1f4c733c068030422aa9ac3d46c4e'
    'd2826446079faa0914c2d705d98b02a2b5129cd1de164eb9cbd083e8a2503c4e')
check('chacha20 block equals RFC 8439 2.3.2', run(cmd_c(rfc_key, rfc_nonce, 1)) == rfc_expect)
check('python reference chacha equals RFC 8439 2.3.2', R.chacha_block(rfc_key, rfc_nonce, 1) == rfc_expect)

rnd = random.Random(20261026)
script = b''
expect = b''
for _ in range(200):
    key = rnd.randbytes(32)
    nonce = rnd.randbytes(12)
    ctr = rnd.randrange(0, 1 << 32)
    script += cmd_c(key, nonce, ctr)
    expect += R.chacha_block(key, nonce, ctr)
check('chacha20 block equals reference for 200 random inputs', run(script) == expect)

pool = R.Pool()
script = b''
expect = b''
for i in range(300):
    kind = rnd.randrange(0, 3)
    if kind < 2:
        data = rnd.randbytes(rnd.choice([0, 1, 7, 31, 32, 33, 63, 64, 65, 200, 1000]))
        script += b'M' + struct.pack('<H', len(data)) + data
        pool.mix(data)
    else:
        script += b'X'
        expect += pool.extract()
check('pool hash chain equals hashlib.blake2s model (300 steps)', run(script) == expect)

d = R.Drbg()
script = b''
expect = b''
for i in range(120):
    if rnd.randrange(0, 4) == 0:
        seed = rnd.randbytes(32)
        script += b'R' + seed
        d.reseed(seed)
    n = rnd.choice([0, 1, 16, 31, 32, 33, 63, 64, 65, 100, 4096, 5000])
    script += b'G' + struct.pack('<H', n)
    expect += d.generate(n)
check('fast-key-erasure generator equals reference byte for byte', run(script) == expect)

d = R.Drbg()
script = b'R' + bytes(32) + b'G' + struct.pack('<H', 64) + b'G' + struct.pack('<H', 64)
out = run(script)
check('two requests give different output', out[:64] != out[64:128])
d.reseed(bytes(32))
first = d.generate(64)
check('key is erased: second request does not reuse the first key stream', out[:64] == first and out[64:] == d.generate(64))

h = R.Health()
script = b''
expect = b''
samples = [rnd.randrange(0, 256) for _ in range(5000)]
samples += [7] * 100
samples += [rnd.randrange(0, 256) for _ in range(1000)]
samples += [rnd.choice([1, 2]) if rnd.random() < 0.9 else 3 for _ in range(1500)]
for s in samples:
    script += b'H' + bytes([s])
    expect += bytes([1 if h.feed(s) else 0])
got = run(script)
check('health tests equal reference sample by sample (%d samples)' % len(samples), got == expect)
check('health tests flag a constant run', expect.count(0) > 0 and got.count(0) == expect.count(0))
clean = R.Health()
fails = sum(0 if clean.feed(rnd.randrange(0, 256)) else 1 for _ in range(200000))
check('health tests rarely trip on uniform samples', fails <= 4, 'failures=%d' % fails)

rnd2 = random.Random(5)
key = rnd2.randbytes(32)
seed = rnd2.randbytes(64)
enc = run(b'E' + struct.pack('<Q', 77) + seed + key)
check('seed file encode equals reference (magic, counter, seed, HMAC-BLAKE2s)', enc == R.seedfile_encode(77, seed, key))
dec = run(b'D' + enc + key)
check('seed file decode accepts a valid file and returns seed and counter', dec[0] == 1 and dec[1:65] == seed and struct.unpack('<Q', dec[65:73])[0] == 77)
tampered = bytearray(enc)
tampered[20] ^= 1
check('seed file with one flipped bit is refused', run(b'D' + bytes(tampered) + key)[0] == 0)
check('seed file under a wrong key is refused', run(b'D' + enc + bytes(32))[0] == 0)
bad_magic = bytearray(enc)
bad_magic[0] ^= 1
check('seed file with wrong magic is refused', run(b'D' + bytes(bad_magic) + key)[0] == 0)

print('ENTROPY-HOST: %d passed, %d failed' % (ok, bad))
sys.exit(1 if bad else 0)
