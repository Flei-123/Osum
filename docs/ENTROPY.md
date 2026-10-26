# Entropy and CSPRNG (R-005)

## Status: both stages done (library layer and kernel wiring)

### What existed before (kernel/sched/rand.fi, replaced in stage 2)
- 8-word collector fed by timer IRQ, keyboard, serial (`rand.stir`); ChaCha20 in kstate; RDSEED/RDRAND xor-mixed; reseed every 4096 octets; `fixedrand` counter-probe.
- Real gaps (verified in the source): `bytes()` seeded silently on the first call without any entropy proof; no credit counter; no health tests; the collector mix was not cryptographic; `getrandom` ignored its flags; writing to /dev/random mixed nothing; no seed file; no per-request key erasure; no lock around the shared key.

### Stage 1: library layer (`lib/entropy/`, host oracle `tools/entropy/run.sh`)
- `health.fi`: SP 800-90B repetition count (cutoff 21) and adaptive proportion (window 512, cutoff 410), assumed H = 1 bit/sample.
- `pool.fi`: BLAKE2s hash-chain pool with forward-secret extract.
- `drbg.fi`: ChaCha20 generator with fast key erasure per request (block 0 gives the next key and the request key).
- `seedfile.fi`: 112 octet seed file format (magic, counter, 64 octet seed, HMAC-BLAKE2s).

### Stage 2: the kernel (`kernel/sched/`)
- `rand.fi` uses the library: pool, generator and two health tests are statics; the interrupt path (`stir`) only writes a small ring and a credit counter, the ring is folded into the pool at reseed time, under a spin lock that no interrupt handler takes.
- **Initialised = 256 bits credited.** Credit is counted in 1/16 bit. Sources: RDSEED 4 words = 256 bits; RDRAND 4 words = 128 bits (only when there is no RDSEED); jitter harvester = 1 bit per 32 healthy samples; seed file = 128 bits; interrupt timings = 1 unit per 8 healthy events, capped at 64 bits. CPU words are mixed at every reseed and never used alone.
- **Before initialisation `rand.bytes` returns 0 and writes nothing.** Kernel callers check it: wireguard skips the handshake/junk, krypto fails, /proc UUID stays zero. `getrandom` blocks (yield + more jitter) or, with `GRND_NONBLOCK`/`GRND_INSECURE`, returns `-EAGAIN`; unknown flags give `-EINVAL`. `/dev/random` and `/dev/urandom` block until initialised (Linux >= 5.6 semantics), a write to them mixes without credit.
- Jitter harvester (`jitter_batch`): a data-dependent memory walk timed with rdtsc, 1024 samples per batch, every delta mixed into the pool, credit only for a batch in which every sample passed the health tests. Runs at boot until the generator is initialised and again from `poll` while a caller waits.
- Test words (kernel command line): `randnotrustcpu` (CPU generator mixed, no credit), `randnojitter` (no jitter source), `randjitterstuck` (the harvester sees a constant: the health test must refuse it), `fixedrand` (the old counter-probe).
- `randseed.fi`: kernel-side seed file `/system/RANDSEED` (112 octets, mode 0600, fixed length, written through `fs/fixedfile.fi`). At boot after the root is mounted: read, verify the HMAC (key = BLAKE2s of a constant: integrity only, there is no per-machine secret), mix, credit 128 bits, then replace it at once with fresh output of the generator (never used twice); save again before reboot/poweroff. A damaged file is refused. A **RAM root (live stick) is reported as `ram-root-not-persistent-no-use`**: the file is mixed if present but never credited and never written. A seed is only written when the generator is initialised or a seed file was loaded, so a machine with no entropy cannot write a weak seed that the next boot would credit.
- `/proc/random` (`randview.fi`): state, credited bits and bits per source, the CPU flags, jitter mode/samples/failures, interrupt samples/failures, pool octets, generator generation and reseeds, octets issued, seed file state and counter. The boot log (word `unix`) prints the same in one `rand:` line.
- `rndtest` (user program): `hex N [nonblock]`, `peek [badflag]`, `write`, `dump <file>` for the gates.

### Measured (QEMU/KVM, AMD EPYC host, `tools/entropy/kernel.sh`: 53 passed, 0 failed)
- 1 MiB from the running kernel passes chi-square, monobit, runs, serial correlation, entropy (> 7.999 bit/octet) and the repeated-block check on Haswell (RDRAND), Broadwell (RDSEED) and qemu64 (no CPU generator: the jitter alone). The same battery rejects five synthetic bad streams and the `fixedrand` stream.
- Time from the clock start to "initialised": Broadwell 0.16 ms (RDSEED credits 256 bits at once), Haswell about 10 ms (60 ms in one earlier run; RDRAND 128 bits + 4096 jitter samples), qemu64 about 26 ms (8192 jitter samples).
- `getrandom` throughput for 4 MiB in 4096 octet requests: 11-13 MB/s now, 7 MB/s before (old collector + in-kstate ChaCha20). 36 further 1 MiB runs on three CPU models all ended cleanly; one earlier run of the gate saw QEMU stop mid-output with exit code 0 and was not reproduced.
- Counter-proofs: no source -> `-EAGAIN`, `not-initialised`, no output bytes; stuck jitter -> health failures counted (478..3830 per boot), no credit; `randnotrustcpu` -> 0 CPU bits; /dev/random write -> no credit; unknown flags -> `-EINVAL`.
- Seed file: absent -> written; loaded with 128 bits; replaced at every boot (three different files in three boots); damaged -> refused; RAM root -> `ram-root-not-persistent-no-use`, nothing written.
- No regression: `tools/unix/run.sh` 106 passed / 1 failed (the same failure as on the old main: signal 64), `tools/krypto/run.sh` 60/1 (same as old main: `check-ui.sh`), `tools/tunnel/run.sh` 16/0 on the second run (the first run lost one ping under load).

### Honest limits
- Credit values are policy, not proof. The jitter harvester's 1 bit per 32 samples is a conservative assumption, not a measured min-entropy; under emulation the TSC may be coarser than on real hardware (the health tests are the guard).
- The seed file key only protects integrity against accidents; whoever can read the disk can read the seed (mode 0600 only keeps other users away). Its 128 bit credit assumes the disk stays private.
- A virtual machine that is cloned or restored from a snapshot repeats the generator state until the next reseed (every 4096 octets) mixes in new interrupt timings and CPU words.
- No Linux-style `RNDADDENTROPY` ioctl: credit only comes from the sources above and the seed file.
