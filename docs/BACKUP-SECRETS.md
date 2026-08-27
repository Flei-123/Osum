<!-- SPDX-License-Identifier: GPL-2.0-only -->
# BACKUP-SECRETS.md -- what a backup is allowed to carry

Round TRESOR, third addendum. Written 27.08.2026, measured on QEMU
7.2.22, `tools/tresor/run.sh` section 13.

Every number in this document comes from a run. Where something is a
design argument rather than a measurement, it says so.

---

## 1. The objection

The owner, on the backup this round had just built:

> If I make a backup and install it somewhere else, no passwords and no
> account may travel with it -- if somebody gets the backup, your whole
> account is gone.

He is right, and the design as it stood was wrong. `docs/THEFT.md`
section 4(b) rule 1 said a backup carries "`PLAN`, **the secret store**,
`config/`, `state/`", in the clear, on a stick.

A backup stick is an **object**. Objects are lost, left in hotel rooms and
posted through letterboxes. Whatever is on one must be assumable-
compromised.

## 2. Why "then do not back up secrets" is the wrong fix

It is the obvious fix and it trades one failure for a worse one.

A disk dies far more often than a stick is stolen. A person whose password
vault was deliberately left out of the backup, and whose disk then fails,
has lost every account they own -- which is **exactly the outcome the
objection is about**, arrived at by a different road. The rare loud
failure has been swapped for a common quiet one.

So secrets must be able to travel. They must simply be **useless to
whoever finds them**.

## 3. Three classes

Every path in the backup set falls into exactly one class. The
classification lives in `kernel/user/bsec.fi`, **in the program**, not in
a file on the stick -- a policy an attacker can edit is not a policy.

| class | what | in the backup? |
|---|---|---|
| **(a) ordinary data** | documents, pictures, `PLAN`, `config/`, `state/` | yes, plain; encrypted if a store password was given |
| **(b) secrets** | password vault, saved logins, VPN private keys, payment data | **only on request**, and then always sealed under the master password |
| **(c) never** | device key, machine identity, session tokens, TPM-bound keys | **never**, under any option |

The table as the program has it, longest match wins:

```
NEVER   /device            device key, machine identity, TPM handles
        /state/session     session tokens -- "this machine is logged in"
        /etc/machine-id    the identity a reinstall must not inherit
SECRET  /secrets           the password vault and everything like it
        /etc/shadow        password hashes: slow to crack, not safe
        /config/vpn/keys   the private halves of VPN profiles
PLAIN   everything else
```

`/device` matches the **directory itself**, not only things inside it, so
a class (c) folder does not appear in the snapshot even as an empty
folder. The walk does not descend into it: not one octet can reach the
store, which is stronger than filtering the files inside one at a time.

### Why class (c) exists at all

Three reasons, and each alone is enough:

1. **A TPM-bound key cannot travel.** It never leaves the chip. Software
   that promises to back one up is lying about physics.
2. **A session token is a claim that *this machine* is logged in.**
   Copying it to another machine is precisely the theft being defended
   against.
3. **The device key is what makes crypto erase work.**
   `docs/CRYPTO-ERASE.md` rests on destroying one wrapped key so that
   every octet on the disk becomes noise. A copy of that key in a backup
   **defeats the erase**: you destroy the key on the machine and the stick
   still has it. This is not a leak, it is a *contradiction* with a
   feature built earlier in the same round.

These are re-created on the target machine. That is not a workaround; it
is what identity means.

## 4. Two secrets, not one

* the **store password** (`-p`) encrypts class (a);
* the **master password** (`-m`) encrypts class (b).

They are independent on purpose. Handing somebody the store password so
they can fetch a document must **not** hand them the vault. With one
password over both, "restore my photos" and "restore my bank logins"
would be the same act.

**Class (b) is left out by default.** There is no setting that changes
this and no "remember my choice". Carrying secrets requires `-m` with the
password in hand, every time. On the way back it is the same: a restore
without `-m` of a snapshot that has secrets **stops and says so** -- it
does not return a tree that looks whole and has no credentials in it.

## 5. The construction

```
MK   = PBKDF2-HMAC-SHA256(password, salt, 2048, 32)
CONV = HMAC-SHA256(MK, "osum backup v1 convergence")
ENC  = HMAC-SHA256(MK, "osum backup v1 blockkey")
MAC  = HMAC-SHA256(MK, "osum backup v1 blockmac")
CHK  = HMAC-SHA256(MK, "osum backup v1 check")
```

and per 4096-octet block of plaintext `P`:

```
name = HMAC-SHA256(CONV, P)              the block's name in INDEX
k    = HMAC-SHA256(ENC, name)            a ChaCha20 key, 32 octets
C    = ChaCha20(k, nonce = 0, ctr = 0) XOR P
tag  = HMAC-SHA256(MAC, name || C), first 16 octets
PACK holds C || tag
```

**Encrypt-then-MAC**, which is the composition with a proof behind it. The
tag covers the *name* as well as the ciphertext, so a block cannot be
swapped for another block of the same store. The tag is checked **before**
anything is decrypted and before one octet reaches the target tree: a
restore writes files onto a running system, and handing it octets that
nothing vouched for is how a backup becomes an attack.

`CHK` goes into `<store>/HEADER` next to the salt. It is what lets a wrong
password be **refused in the first second with a sentence**, instead of
the run going on to decrypt rubbish.

### Why ChaCha20 and not the AES that is already here

`vendor/firn/lib/std/crypto/aes.fi` exists, and its own header says what
it is: *"A4 NO GCM, NO AUTHENTICATION"*, offering CBC and CFB8.
Confidentiality without authentication is how padding oracles are born,
and a backup is the worst place to learn that lesson. Round TUNNEL is
building ChaCha20-Poly1305 and when it lands it is the better answer -- one
pass, a 128-bit tag. It is not here today, so the cipher is ChaCha20
(RFC 8439, written for this round in `kernel/user/chacha.fi`) and the
authentication is explicit HMAC-SHA256 over the ciphertext, on top of a
SHA-256 this round already checked digit by digit against `hashlib`.
The snapshot header carries a version word, so the swap will not
invalidate what exists.

### Why the nonce is zero

It looks wrong and it is the point. A stream cipher dies if one key and
one nonce ever encrypt two *different* plaintexts. Here the key is a
function of the plaintext alone, so two blocks sharing a key are literally
the same octets -- the pad is only ever reused on the message it already
encrypted. A random nonce would add no security and would destroy the
property in the next section.

## 6. The hard part: encryption kills deduplication

This store exists because identical blocks are stored once. Round TRESOR
measured it: the same file in three folders costs **8192** octets, not
24576. Encrypt naively -- a fresh random nonce per block -- and identical
plaintexts produce different ciphertexts, the store never recognises a
repeat, and every one of those numbers collapses. Nobody announces this;
the backup simply becomes three times bigger.

### The usual answer, and why it is rejected

**Convergent encryption**: derive both the name and the key from the hash
of the plaintext. Identical plaintext gives identical ciphertext, so
deduplication survives, and it needs no password at all. It is what most
deduplicating encrypted stores do.

It is **rejected here**, for a real attack and not a purity argument:

> **Confirmation of a file.** With pure convergent encryption anybody
> holding the stick *and* a candidate file can compute the name that file
> would have and look it up in `INDEX`. No password needed. The encrypted
> backup then answers the question *"does this person have THIS
> document"* -- for any document the asker can guess or obtain. For a
> specific leaked pamphlet or a particular medical form, that is the whole
> secret.

### What is built instead

**Keyed convergent encryption**: `name = HMAC-SHA256(CONV, P)`, where
`CONV` comes from the password. Then

* identical blocks **within one store** still land on the same name, so
  deduplication is untouched -- measured below, and the numbers are
  identical to the unencrypted case;
* the confirmation attack fails, because computing the name of a candidate
  file needs `CONV`, which needs the password.

**The price, stated rather than hidden:** deduplication no longer works
*between* stores with different passwords. Two people cannot share one
deduplicated store. For a personal backup on a personal stick that costs
nothing. For a shared backup server it would, and that is the case where
this decision would have to be revisited -- not silently, but by writing
down which of the two attacks that operator is more afraid of.

## 7. What is measured

`tools/tresor/run.sh` section 13. The round runs **220 assertions, 0
failures**; 71 of them are this section. Three parts.

### 7a. The cipher is the cipher (13a)

`kernel/user/bsect.fi` prints from ring 3; the host recomputes with
`cryptography` (OpenSSL underneath) and `hashlib`, neither of which this
tree wrote.

| vector | what |
|---|---|
| `cc1` | the ChaCha20 keystream block of **RFC 8439 section 2.3.2** |
| `cc2` | the encryption of **RFC 8439 section 2.4.2** -- and it equals the ciphertext *printed in the RFC itself*, so the agreement is with the specification and not merely with a second program that could share a misreading |
| `cc3` | 4096 octets, so the block counter really advances 64 times |
| `hm1` | HMAC-SHA256 over 4096 octets. `key.fi`'s HMAC cannot do this -- it copies the message into a 128-octet array -- which is why `bsec.fi` has a streaming one |
| `pb1` | PBKDF2-HMAC-SHA256, 2048 iterations, against `hashlib` |
| `sl1` | the sealed block: name, ciphertext, tag, all three recomputed on the host |

and four properties, each a single yes:

* `sl2` -- unsealing returns exactly the plaintext;
* `sl3` -- **one flipped octet and the unseal refuses**;
* `sl4` -- the same plaintext gets the **same name** (deduplication);
* `sl5` -- a different password gets a **different name** for the same
  plaintext (the confirmation attack fails).

`cls` prints the class of nine paths as nine letters: `dddssdnnn`. The
security decision is not described in the test, it is *printed by the
program under test*.

### 7b. Three classes in a real backup (13b)

A backup set with all three classes, every file carrying a distinctive
marker so the host can search the finished store for it -- and so that
**not** finding one means something. Three runs of `backup save` over the
same set:

| run | options | secret files | secret left out | class (c) left out |
|---|---|---:|---:|---:|
| A | *(none)* | **0** | 3 | 3 |
| B | `-mmasterpw` | 3 | 0 | 3 |
| C | `-pstorepw -mmasterpw` | 3 | 0 | 3 |

Then the host reads each finished store **out of the disk image** and
counts the markers in it, exactly as a person who found the stick would:

| marker | class | in A | in B | in C |
|---|---|---:|---:|---:|
| `MARK-PLAN-ORDINARY-DATA` | (a) | **1** | **1** | **0** |
| `MARK-VAULT-SECRET-BANK-PW` | (b) | 0 | **0** | 0 |
| `MARK-VPNKEY-SECRET` | (b) | 0 | **0** | 0 |
| `MARK-SHADOW-SECRET` | (b) | 0 | **0** | 0 |
| `MARK-DEVICEKEY-NEVER` | (c) | **0** | **0** | **0** |
| `MARK-MACHINEID-NEVER` | (c) | **0** | **0** | **0** |
| `MARK-SESSION-NEVER` | (c) | **0** | **0** | **0** |

Read the rows in order and the whole design is in them:

* the **1** in row 1 column A is the counter-test. A search that can never
  find anything proves nothing; ordinary data really is lying there in the
  clear, and the same search finds it.
* the vault is **not in A at all** -- default is default.
* the vault **is** in B (`secret files: 3`) and **still cannot be read**.
  That is the answer to the objection.
* row 1 column **B is still 1**: `-m` protected the vault and left the
  documents alone. The two layers are genuinely independent.
* column C is zero everywhere. That is what `-p` buys.
* class (c) is **zero in every column**, including B and C where the
  master password was on the command line. There is no option that carries
  it.

**The raw content**, cut out of the store the way a finder would: the
snapshot names the blocks of `/secrets/vault.kdbx`, `INDEX` says where
they sit in `PACK`, and those octets are dumped.

the first 48 of them, in store B:

```
5b4b743378616a7065261f3c23ced95c45063f5913ee6024b2baebc548ac243b7a267710d143d5cedafe032390cc2abd
```

and the same vault in store C, under a different master salt:

```
6a957e1d337642738230d85ed791200b94bbbfb642e72516d2183f3e821b531515a91e218d57b9530dd939b4d2f67f08
```

4112 octets: 4096 of ciphertext and the 16-octet tag. The marker occurs
**0** times in it. The same vault in store C, under a different master
salt, is a **different** ciphertext -- asserted, not asserted-by-eye.

**The refusals**, each with a sentence rather than silence:

| attempt | what the program says |
|---|---|
| restore B without `-m` | `this snapshot carries secrets -- the master password is` **and no success line** |
| restore C with a wrong `-p` | `wrong store password` |
| restore C with a wrong `-m` | `wrong master password` |
| `verify` C with no password | `this store is encrypted -- give the store password` |
| `verify` C with both | `corrupt: 0`, `unchecked: 0` |

`unchecked` is new and it exists because of one temptation: a `verify`
that cannot open a block must not count it as checked, or `corrupt: 0`
becomes a lie.

**And the way back**: the host reads the restored trees out of the disk
image and compares octet for octet -- 6 pairs, 6 equal, including the
vault out of B and out of C. The three class (c) paths are **absent** from
the restored tree, which is asserted too: they were never in the snapshot,
so they cannot come back.

### 7c. What encryption costs, and what it does not (13c)

The same file in three folders, 8192 octets, once without and once with a
store password.

| | chunks seen | new chunks | read | **written** | ms |
|---|---:|---:|---:|---:|---:|
| plain | 6 | **2** | 24576 | **8192** | 260 / 300 |
| encrypted | 6 | **2** | 24576 | **8224** | 280 / 320 |
| plain, run again | 6 | **0** | 24576 | 0 | |
| encrypted, run again | 6 | **0** | 24576 | 0 | |

**The deduplication rate is unchanged.** Six blocks seen, two stored, in
both cases -- and a second run of the encrypted store writes **zero**
octets, which is the incremental property surviving as well. That is the
whole point of section 6, as two numbers.

The cost on the disk is **+32 octets on 8192, or 0.39 %**: the 16-octet
tag per stored block and nothing else. No padding, no per-block nonce, no
length growth. Time is given for two runs of the same suite on the same host: 260 to
280 ms in one, 300 to 320 ms in the other. The **difference** is 20 ms
both times, at a timer resolution of 10 ms -- two ticks. That is worth
reporting and not worth a claim, which is why no assertion depends on it:
a test that falls over under load measures the host, not the program.

### 7d. One bug this section caught

`-p pass -m pass` made a `backup save` line **nine arguments**, and this
kernel gives a program at most `proc.MAX_ARGS` = 8. The shell printed
`sh: too many arguments` and **dropped the command**. The backup never
ran, the store stayed empty, and the tests read empty fields. Fixed by
attaching the password to the letter (`-pfoo`), and there is now an
assertion that no line in the run trips the limit -- because the failure
mode was a command that quietly did not happen.

A second one, found while wiring: `bsec.seal` appends 16 octets in place,
and `bstore.fi` handed it a buffer of exactly 4096. Every full block
overran it by the length of the tag, into the static that happened to
follow. The buffer is `CHUNK + TAGLEN` now.


## 8. No account, no network -- unchanged

The fourth addendum to round PLAN2 stands: a machine can be set up
completely **from a stick, with no account and no network**. Nothing here
changes that. The vault may go on the stick; it is simply always sealed.
The master password is a thing the owner knows, not a thing a server
knows. A forced account would be Windows 11 and is ruled out.

The consequence is stated plainly: **a forgotten master password means the
vault is gone.** That is what "not derivable from anything in the backup"
means. It is the correct trade and it is the one thing about this design
a user must be told out loud, because the alternative -- a recovery path
that works without the password -- is a back door with a friendly name.
The shape `key.fi` already has (several wrappings of one data key) is how
a printed recovery code would be added later without weakening this.

## 9. Honest limits

* **B1 -- PBKDF2, not Argon2id.** Current guidance is Argon2id and it is
  not here. Argon2id is *memory-hard*: it needs tens of mebioctets of
  scratch so that a graphics card, which has many weak cores and little
  memory per core, loses its advantage. **This userland has no
  allocator** -- every buffer in it is a fixed static array. Argon2id is
  not a matter of writing the mixing function; it needs memory this ring
  cannot ask for. PBKDF2-HMAC-SHA256 is what SHA-256 in this tree can
  carry honestly, and it is **not** memory-hard: a cracker with a GPU is
  far better off against it than against Argon2id.
* **B2 -- 2048 iterations**, the number `key.fi` and `pw.fi` use, for the
  reason given there: under software emulation the 600000 of today's
  guidance is minutes per unlock. The shape is right and the number is too
  small. It is in the header of every store and can be raised without
  invalidating what exists.
* **B3 -- the password comes in on the command line.** `ps` can see it and
  a shell history keeps it. `key.fi` has the same hole. `pw.fi` already
  has `read_pass`, which reads from the terminal with echo off; wiring it
  through, and through the file manager's dialog, is the missing piece.
* **B4 -- the snapshot text is not encrypted.** Block *content* is. The
  list of paths, sizes and modes in `S-<name>` is readable on a found
  stick, so an encrypted backup still says **what** you have, only not
  what is in it. This is measured rather than hedged: the test greps
  `/secrets/vault.kdbx` out of a fully encrypted store and **finds it**.
  The fix has a definite shape -- write `S-` as a stream of sealed
  4096-octet records through the same `seal`/`unseal` -- and it touches
  every reader in `bstore.fi`, which is why it is named here instead of
  half-done.
* **B5 -- the keys live in the process**, in ordinary static arrays. No
  keyring, no pinned pages. Same limit as `key.fi` K2.
* **B6 -- the classification is by path.** A secret that a program writes
  somewhere unlisted is backed up in the clear. The table in section 3 is
  the complete list. A future `config/backup.policy` may only ever make it
  **stricter**, never looser, and it is not built this round.
* **B7 -- an unencrypted store cannot be encrypted later.** The attempt is
  refused. Half its blocks would be plaintext while the header claimed
  otherwise, which is worse than either honest state. Make a new store.
