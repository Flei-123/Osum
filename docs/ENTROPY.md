# Entropy and CSPRNG (R-005)

## Status: stage 1 of 2 (library layer done, kernel wiring open)

### What already existed (kernel/sched/rand.fi, unchanged so far)
- 8-word collector fed by timer IRQ, keyboard, serial (`rand.stir`); ChaCha20 in kstate; RDSEED/RDRAND xor-mixed; reseed every 4096 octets; `fixedrand` counter-probe.
- Gaps (real, verified in the source): `bytes()` seeds silently on first call without any entropy proof; no credit counter; no health tests; collector mix is not cryptographic; `getrandom` ignores flags; writing to /dev/random mixes nothing; no seed file; no per-request key erasure; no lock around the shared key.

### What exists now (additive, host-verified)
- `lib/entropy/health.fi`: SP 800-90B repetition count (cutoff 21) and adaptive proportion (window 512, cutoff 410), assumed H = 1 bit/sample.
- `lib/entropy/pool.fi`: BLAKE2s hash-chain pool with forward-secret extract.
- `lib/entropy/drbg.fi`: ChaCha20 generator with fast key erasure per request (block 0 gives next key and request key).
- `lib/entropy/seedfile.fi`: 112 octet seed file format (magic, counter, 64 octet seed, HMAC-BLAKE2s).
- `tools/entropy/run.sh`: host oracle, 15 checks: RFC 8439 vector, bytewise equality with Python reference for chacha, pool (hashlib.blake2s), generator, health, seed file; tamper and wrong-key cases.

### Open (not started in the kernel)
- Wire rand.fi to these modules; bytes() returns 0 before init; credit accounting per source; jitter harvester; CPU-source policy (`randnotrustcpu`).
- getrandom flags, /dev/random write, /proc/random, seed file service, statistics and reboot gates, kernel measurements.

### Honest limits
- Credit values are policy, not proof. CPU RNG output is never used alone. The seed file key will only be a checksum-level secret (no per-machine secret exists).
