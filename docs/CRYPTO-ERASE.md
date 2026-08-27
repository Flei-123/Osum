# CRYPTO-ERASE.md -- destroying the key, not the data

Round TRESOR. Written 27.08.2026.

`THEFT.md` concludes that of everything one can do about a stolen
machine, exactly one measure does not depend on the thief's behaviour,
on a network, or on our software still running: **the data on the drive
is unreadable without a key that is not on the drive.**

This document says why that is the right thing to build, why "remote
wipe" has to mean *destroy the key* rather than *overwrite the data*,
what exists in this tree today, and what is missing. It is a design
document with a working key-management prototype behind it -- not a
description of finished disk encryption, which does not exist here.

---

## 1. Why overwriting data is the wrong mechanism

The obvious idea: the machine is stolen, it comes online, we send it a
command, it overwrites every block.

It fails on arithmetic and on hardware.

**Arithmetic.** Overwriting is bounded by the write speed of the drive
and the size of the drive. A 1 TB drive at 500 MB/s is a bit over half an
hour, at best, with nothing going wrong. A stolen machine that reaches
the network at all typically does so for a few minutes -- long enough to
receive a command, nowhere near long enough to execute that one. And the
thief can pull the power at any moment, leaving a drive that is *partly*
wiped, which means the interesting parts may well survive.

**Hardware.** On flash, "overwrite this block" is not a thing you can ask
for. The flash translation layer writes the new data to a *different*
physical page and marks the old one for later erase. Overwriting a file
overwrites a logical address; the old physical page keeps its contents
until the controller gets round to it, and a determined reader who talks
to the flash chips directly can often still find it. Wear levelling and
over-provisioning make this worse, not better: the drive deliberately
keeps more physical pages than it admits to having.

So a wipe-by-overwriting is slow, interruptible, and on the most common
storage medium not even reliable.

---

## 2. Why destroying the key is the right one

If every block of the drive was encrypted with a key **K**, and **K**
exists nowhere except in one small place, then destroying that one small
place makes the entire drive noise. Not "hard to read" -- noise, for the
same reason that any 256-bit key is out of reach.

The size of the work drops from "the whole drive" to "32 octets". That
changes the character of the operation:

* It is **fast**. Measured in this tree at the resolution the timer
  allows: `key erase` completed in **10-20 ms** (the kernel's timer runs
  at 100 Hz, so one to two ticks -- the true figure is below the
  measurement floor, and quoting microseconds would be inventing
  precision).
* It is **atomic enough to be trustworthy.** There is no half-wiped
  state that leaks the interesting half.
* It **works offline**, if the trigger is local -- for example a limit on
  failed unlock attempts. It does not require the thief's cooperation in
  connecting the machine.
* It costs the drive **nothing**: no write amplification, no wear.

This is what the industry calls *crypto erase*, and it is why the ATA and
NVMe specifications have a sanitize-crypto-scramble command at all: the
drive throws away its internal media key and every sector becomes
gibberish instantly.

---

## 3. The two-key shape, and why the passphrase must not be the key

The prototype in `kernel/user/key.fi` uses two keys and never one:

```
DATA KEY   32 octets from getrandom(). This is what would encrypt the
           disk. Never derived from anything a human knows.
WRAP KEY   PBKDF2-HMAC-SHA256(passphrase, salt, iterations).
           It encrypts THE DATA KEY, and nothing else.
```

Three consequences fall out of that, none of which needs extra
machinery:

1. **Changing the passphrase re-wraps 32 octets.** It does not re-encrypt
   the disk. A design in which the passphrase encrypts the data directly
   cannot change a passphrase without rewriting every block -- which is
   the same half hour as section 1, and for a routine operation.
2. **Several passphrases can wrap the same data key.** Yours and a
   recovery one, each its own wrapping of the same 32 octets. (The shape
   allows it; the prototype writes one blob and does not manage a set of
   slots.)
3. **Crypto erase is possible at all.** Destroy the wrapped data key and
   the data key is gone, because it existed nowhere else. If the key were
   derived from the passphrase, there would be nothing to destroy -- the
   secret would live in somebody's head and be re-derivable for ever.

Point 3 is the whole argument. *Crypto erase is a property of the key
hierarchy, not of the cipher.* That is why this round built the key
management and not a cipher.

---

## 4. What the prototype does

`kernel/user/key.fi`, three commands and one for measuring:

```
key init  <blob> <passphrase>   new random data key, wrapped, written
key open  <blob> <passphrase>   unwrap it, print its FINGERPRINT
key erase <blob>                destroy the wrapping
key kdf   <pass> <salt> <iters> derive and print -- exists only to be measured
```

The wrapping, stated exactly so that nobody has to read it out of the
code:

```
wrap    = PBKDF2-HMAC-SHA256(pass, salt, iters, 64 octets)
pad     = wrap[0..31]        mac = wrap[32..63]
wrapped = datakey XOR pad
tag     = HMAC-SHA256(mac, salt || iters || wrapped)
```

That is a **one-time pad over 32 octets, encrypt-then-MAC**. It is sound
for exactly this use, under one condition which is stated because
somebody will eventually be tempted to reuse this code elsewhere: **the
salt is fresh for every blob and the pad is never used twice.** Re-wrap
with the same salt and passphrase and two data keys XOR to a known value
-- the classic two-time pad. `init` always draws a new salt from
`getrandom`; there is no code path that reuses one.

The tag covers the salt **and the iteration count**, not only the wrapped
octets. Without that, an attacker could lower the iteration count in the
file and make the next unwrap cheap to brute-force.

The tag is checked **before** unwrapping, so an edited blob is refused
rather than yielding a key that is wrong in a way nobody notices until
the data is gone.

### Measured

From `tools/tresor/run.sh`, section 10:

* **PBKDF2-HMAC-SHA256 agrees with Python's `hashlib.pbkdf2_hmac`** on
  three cases (1, 2048 and 4096 iterations), each producing 64 octets --
  that is **two** output blocks, so the block-index handling is exercised
  and not just the first-block case.
* `init` then `open` with the right passphrase returns **the same key**
  (compared by SHA-256 of the key, so the key itself never reaches the
  serial line).
* `open` with a wrong passphrase is **refused**, and **no key is
  produced** -- checked separately, because "refused" and "refused but
  printed something anyway" are different bugs.
* After `erase`, `open` finds nothing.
* Counter-check: the key never appears in the output.

---

## 5. What is missing -- checked, not assumed

The task for this round said: check first whether `lib/std/crypto` has an
AEAD by now, and write down what is missing. Checked on 27.08.2026:

| where | AEAD available? |
|---|---|
| Osum's **pinned** compiler, `vendor/firn/COMMIT` = `c66c6bcd5` (25.08.2026) | **no** -- `lib/std/crypto/` holds only `accel.fi`, `aes.fi`, `hmac.fi`, `random.fi`, `sha1.fi`, `sha256.fi` |
| Firn **main** today, `ce28104bf` (27.08.2026) | **yes** -- `gcm.fi` (AES-GCM: `gcm_seal`, `gcm_open`), `chacha.fi` (ChaCha20-Poly1305: `aead_seal`, `aead_open`), plus `hkdf.fi`, `sha512.fi`, `x25519.fi`, `big.fi` |

So the honest statement is neither "there is no AEAD" nor "we can use
one":

**An authenticated cipher exists in Firn as of round B5, and Osum cannot
reach it yet, because Osum deliberately builds against a pinned compiler
commit that predates it.**

`aes.fi` in the pinned commit is AES-128 with CBC and CFB8, and its own
header says why that is not enough: *"A4 NO GCM, NO AUTHENTICATION"*.
Confidentiality without authentication is how padding oracles are born.
Building disk encryption on it would produce something that looks
finished and is not.

The work to close this is therefore **not** "write a cipher". It is:

1. Move `vendor/firn/COMMIT` forward to a Firn commit that carries
   `gcm.fi` / `chacha.fi`. That is a deliberate act and the repository's
   own rule gates it: the pin moves only once `./test.sh` is green on the
   new compiler. Certus B5/B6 are still moving the same tree, so this
   should wait for their round to settle rather than race it.
2. Add `vendor/net/BLOBS`-style hash entries for the new crypto files, so
   that the pin moving does not silently change the cipher.
3. Then build the layer between the data key and the block device.

---

## 6. What the disk-encryption layer would have to look like

Sketch, not code. Recorded now so that the next round starts from a
design rather than a blank page.

**Where it sits.** Between `kernel/blk.fi` (which moves 512-octet blocks)
and the file systems above it, as another block device, so that OFS,
FAT32 and everything else stay unaware -- the same seam that already lets
a boot module be a root disk.

**The unit is the sector, not the file.** A file system writes block 12345
and expects to read block 12345 back, at the same size. So the ciphertext
must be the same length as the plaintext, which rules out storing a tag
next to the data in the same sector.

**That is the hard part, and it must not be glossed over.** Length
preservation is exactly what AES-GCM cannot give: it appends 16 octets of
tag. Two honest ways out, and the choice is a real decision for the next
round:

* **A length-preserving tweakable mode (XTS, or AES-XEX with the sector
  number as the tweak).** This is what LUKS, BitLocker and FileVault use.
  It gives confidentiality and **not** authentication: an attacker who
  can write to the drive can flip ciphertext bits and the result decrypts
  to different plaintext without anything noticing. Everybody ships this
  anyway, because the alternative costs a separate metadata area.
* **An AEAD plus a separate tag area** -- a reserved region of the drive
  holding 16 octets of tag and a nonce per sector. This gives real
  integrity, and costs a second write per sector plus the space. Slower,
  honest, and rarely done.

XTS is not in Firn's library either, and it is a *mode*, not a new cipher
-- it needs the AES block function that already exists.

**The nonce discipline** is the other thing to get right before writing
code: with a counter-based mode, re-encrypting a sector with the same key
and the same nonce is catastrophic. The sector number as tweak (XTS) side-
steps it; a counter mode needs a nonce that changes on every write, which
means storing it, which brings back the metadata area.

**Where the key lives at run time** is the third open item. Today
`key.fi` holds it in ordinary process memory. A real implementation keeps
it in the kernel, pins the pages, and keeps it out of anything that dumps
memory. This kernel has no swap, which removes one class of leak by
accident rather than by design.

---

## 7. What crypto erase would then mean here, honestly

With the layer above in place, "remote wipe" becomes: overwrite and
unlink the key blob, and drop the key from memory. Milliseconds, as
measured.

Three limitations that must be stated wherever this is described,
because each of them can turn the promise into a lie:

1. **The blob is a file.** `key erase` overwrites its octets and unlinks
   it. On flash, that does not guarantee the old octets are physically
   gone -- section 1's argument about the flash translation layer applies
   to the key blob exactly as it applies to everything else. The
   difference is that 32 octets in one place is a far smaller target to
   protect properly than a whole drive. The honest version needs the key
   held somewhere built to be destroyed: a **TPM** sealed object, or the
   drive's own key slot via **NVMe Sanitize / ATA Secure Erase**, both of
   which purge in the controller where the flash translation layer cannot
   preserve anything behind our back. Neither is used in this tree.
2. **A wipe still needs a trigger.** A remote trigger needs the machine
   online and running our software -- the same limitation as everything
   in `THEFT.md` section 3, and a thief avoids it for free. The trigger
   that does *not* need a network is a local one: N failed unlock
   attempts, or a dead-man timer that requires a periodic unlock. Those
   are worth more than the remote command, and neither exists yet.
3. **Anything copied off the machine before the wipe is gone for good.**
   Crypto erase protects the drive, not the past.

---

## 8. Summary

* Overwriting data as a wipe mechanism is slow, interruptible and
  unreliable on flash. Destroying the key is fast, atomic, and complete.
* Crypto erase is a property of the **key hierarchy**, not of the cipher.
  That is why this round built the key hierarchy: random data key, wrapped
  by a passphrase-derived key, authenticated, and destroyable.
* Measured: PBKDF2-HMAC-SHA256 agrees with Python on three cases at 64
  octets of output; the wrap/unwrap round trip returns the same key; a
  wrong passphrase is refused and yields nothing; `erase` completes in
  10-20 ms and the key is then gone.
* **No disk encryption was built, and none should be claimed.** The
  reason is specific and now documented: the AEAD exists in Firn main
  (`gcm.fi`, `chacha.fi`, round B5) but not in the compiler commit Osum
  is pinned to. The next step is moving the pin once Certus settles, not
  writing a cipher.
* The open design decision for the next round is length preservation:
  XTS (confidentiality only, what everyone ships) versus an AEAD with a
  separate tag area (real integrity, slower, more space).
