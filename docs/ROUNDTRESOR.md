# Round TRESOR -- device identity, backup, key management

27.08.2026. Branch `tresor`. Runner: `tools/tresor/run.sh`.

The question this round was given: what can an operating system actually
do about a stolen machine? The answer turned out to be mostly a list of
things that are impossible, and a short list of things that are worth
building. Both lists are in `docs/THEFT.md`; this file is the log of what
was built and what the measurements said.

---

## 1. What was built

| file | what it is |
|---|---|
| `kernel/hwid.fi` | device identity: SMBIOS type 1 and 2, NVMe serial, MAC |
| `kernel/nvme.fi` | *additive*: `identify_ctrl`, a second identify (CNS 1) |
| `kernel/procfs.fi` | *additive*: `/proc/hwid` |
| `kernel/user/sha.fi` | SHA-256 as a stream, any length |
| `kernel/user/hwid.fi` | the raw values and a fingerprint over the stable ones |
| `kernel/user/bak.fi` | `/bin/bak`: content-addressed backup |
| `kernel/user/key.fi` | key management: wrap, unwrap, destroy |
| `kernel/user/shat.fi` | the SHA-256 measurement, in ring 3 |
| `tools/tresor/` | the runner, a second SMBIOS decoder, a memory dumper, a corrupter |
| `docs/THEFT.md` | the threat model |
| `docs/CRYPTO-ERASE.md` | why the key and not the data, and what is missing |

kdata grew by two pages at `0x5A000` (`HWID_OFF`), entered in
`tools/kernel/karte.py`. The second page is not padding: it is the DMA
target of the NVMe controller identify, and a PRP entry over 4096 octets
with a non-zero offset would need a second entry.

**103 assertions, 0 failures.**

---

## 2. The three things that were wrong before they were measured

### 2.1 The NVMe serial number is not where the task said it was

The round was specified as: take the serial number out of the existing
`A_IDENTIFY` buffer, octets 4..23.

That buffer holds **IDENTIFY NAMESPACE** (CNS 0) -- `nvme.identify` asks
for the size and block format of one namespace. Octets 4..23 there are
part of the namespace capacity. The serial number and model belong to the
**controller**, not to a namespace, and need a second command with
`nsid = 0` and `CDW10 = 1` (**IDENTIFY CONTROLLER**, CNS 1).

Reading the old buffer would have produced no error at all -- just wrong
characters, consistently, for ever. So `nvme.identify_ctrl` was added
additively, with the destination buffer supplied by the caller (this
driver has no free page: `0x14000..0x1B000` is fully allocated).

Measured with `-device nvme,serial=NVME-SER-4242`: `nvme_ser` =
`NVME-SER-4242`, `nvme_mod` = `QEMU NVMe Ctrl`.

### 2.2 The SMBIOS string-set rule

SMBIOS 6.1.3: after the formatted body come the strings, each NUL
terminated, and the set ends with **one more** NUL. A structure with no
strings at all is the special case of exactly two NULs.

The plausible reading -- "the set ends at two NULs in a row" -- fails in a
way that does not look like failure: it reads the first structure
correctly, then meets the terminator followed by the *type* octet of the
next structure (a 1, not a 0), keeps going, and reads a length of 0.

Measured with the wrong rule: **1 structure of 9**. With the right rule:
9 of 9, agreeing with the independent Python decoder.

### 2.3 The ordering of `kernel_main`

`hwid.stage` was first placed after `netsvc.stage`, so that the MAC
address exists. With an NVMe drive plainly present and the driver plainly
finding it (`nvme: blocks=16384`), `hwid: nvme_ser` came out **empty** --
because `hw.disk`, which sets up the controller, runs one stage *below*.

The values were not wrong, they were early. Fixed by splitting collection
from reporting: `hwid.stage` collects what exists at that moment,
`hwid.late` runs after `hw.disk` and reports, and `hwid.refresh` fills in
late sources when `/proc/hwid` is read (at most eight attempts, so a
machine without a drive does not pay for a failing admin command on every
`cat`).

---

## 3. The measurements

### 3.1 The parser is right, checked against a second implementation

The host dumps physical memory over the QEMU monitor
(`tools/tresor/dump.py`) and decodes SMBIOS with a **second, independent
implementation** written from the specification
(`tools/tresor/smbios.py`, Python). Entry point, table address, length,
structure count and every string agree with the kernel.

The dump has its own lesson: the first version pulled memory immediately
after start and found nothing in the F-segment but SeaBIOS's string
table. The firmware had not run yet. A dump without a wait measures the
state *before* the thing one wants to measure.

### 3.2 The checksum is load-bearing

SeaBIOS carries the literal characters `_SM3_` at `0x000F1031` -- the
string its own code uses to build the real entry point. Two independent
things reject it: the checksum fails, and `0x...031` is not 16-octet
aligned. The kernel reports `tried=1`: exactly one entry point accepted,
not two.

### 3.3 What SMBIOS is worth

Same kernel image, two QEMU command lines:

| field | plain QEMU | with `-smbios` |
|---|---|---|
| `system_serial` | *(empty)* | `SN-JUSTIN-0001` |
| `uuid` | sixteen zero octets | `11111111-2222-...` |
| `uuid_valid` | `0` | `1` |
| baseboard | **absent** | present |

Both directions matter: the parser works, and the values are whatever the
firmware says. The kernel refuses to treat sixteen zero octets as a UUID,
because a fingerprint that hashed them would be identical on every
default virtual machine and would look just as convincing as a real one.

### 3.4 The fingerprint survives a reinstall

* Same machine, **freshly built disk image**: same fingerprint.
* Different machine: different fingerprint.
* Reproduced on the host from the canonical text with Python's
  `hashlib` -- the fingerprint is not something only Osum can compute.
* Default VM: `sources:` reports how few fields contributed.

### 3.5 The backup

5 files, 3 directories, 25,491 octets, one file a byte-for-byte copy of
another:

| run | chunks | new | read | written |
|---|---:|---:|---:|---:|
| first | 9 | 5 | 25,491 | 11,155 |
| second, unchanged | 9 | **0** | 25,491 | **0** |

The second run reads everything and writes nothing. No timestamps, no
change journal -- the hash answers the question "do I already have these
octets".

Time, from the same run: **260 ms** for the first save, **190 ms** for the
second. Both read all 25,491 octets; the difference is the writing. The
figure is soft -- the kernel's timer runs at 100 Hz, so the resolution is
10 ms, and this host was running other rounds at the same time. What the
pair shows is the shape (the second save is cheaper), not a throughput
number worth quoting elsewhere.

Restore is byte-identical, and that is checked **out of the disk image**
rather than off the serial line: **6 entries compared, 6 identical, 0
different**.

`bak verify` re-hashes every chunk. The host flips **one octet** in the
pack file inside the image, from outside the kernel; `cmp` confirms
exactly one octet differs. The same run then finds **1 corrupt chunk in
the damaged store and 0 in an intact one**.

### 3.6 The honest limit, measured rather than admitted in passing

Same file, same eight octets, two positions:

| what | new chunks | written of read |
|---|---:|---|
| appended at the **end** | 1 of 3 | 2,056 of 10,248 (20.1 %) |
| inserted at the **front** | **3 of 3** | 10,248 of 10,248 (100 %) |

Fixed-size chunking cannot do better. Content-defined chunking (a rolling
hash choosing the boundary) is the fix and is not in this round.

### 3.7 Key management

PBKDF2-HMAC-SHA256 agrees with Python's `hashlib.pbkdf2_hmac` on three
cases at 64 octets of output -- two blocks, so the block-index handling is
exercised. `init` then `open` returns the same key; a wrong passphrase is
refused **and** produces no key (checked separately); after `erase` the
key is gone; `erase` takes 10-20 ms, which is at the resolution floor of
a 100 Hz timer.

Counter-check: the key itself never appears in the output. Only
SHA-256 of it does.

---

## 4. Decisions taken

**The tool is called `bak`, not `sich`.** Every other program in this
`/bin` has an English or traditional Unix name -- `cat`, `cp`, `find`,
`sed`, `tar`, `gzip`, `du`, `xargs` -- and the documentation language was
settled as English on 27.08.2026. `sich` would have been the only German
name in the directory, and a userland with half its vocabulary in each
language makes every future name an argument.

**A pack file, not one file per chunk.** A directory entry in OFS is 32
octets: an inode number and 24 for the name. A file name is therefore at
most 23 characters and a SHA-256 in hex is 64. Truncating the hash to fit
would trade a real property for an invented one, silently.

**Chunks are written before the index is extended.** A run that dies in
the middle leaves octets in the pack that nothing points at -- wasted
space. The other order would leave index entries pointing at octets that
were never written, and `restore` would hand back rubbish while reporting
success. Wasted space is a nuisance; silent corruption is a lie.

**A second SHA-256 in ring 3.** `pw.fi` already has one and it is
measured against `hashlib` (round K13), but it also has
`if len > 256 { return false }`. Chunk hashing needs 4096. `sha.fi` is
the same algorithm written as a stream, and it is measured the same way,
including the same 1000 octets fed in one piece and in seven uneven
pieces (which must agree, or the buffering is wrong).

**The EFI path is built but unreachable, and says so.** `hwid.from_efi`
walks the EFI configuration table for both SMBIOS GUIDs. Osum boots
multiboot 1, which hands over no EFI system table pointer -- that is
multiboot 2. So the path is measured against a system table the test
**builds by hand** (`hwidefi`), with three counter-checks: a null
pointer, a wrong signature, and a table whose only entry is a foreign
GUID. Code that is never executed is a guess; this one is at least
exercised. It is *not* claimed to work on real UEFI firmware.

---

## 5. What this round did not do

* **No disk encryption.** The reason is specific: Firn's `main` has an
  AEAD since round B5 (`gcm.fi`, `chacha.fi`), and Osum's pinned compiler
  commit `c66c6bcd5` predates it. The next step is moving
  `vendor/firn/COMMIT`, once Certus B5/B6 settle -- not writing a cipher.
* **No lock, no remote wipe trigger, no location.** `docs/THEFT.md`
  section 2 and 3 argue why Activation Lock and Find My are not
  reproducible without our own silicon, our own firmware and an installed
  base of millions.
* **No network backend for `bak`.** The seam is a path and nothing else,
  which is what makes adding one later small. It needs a transport that
  can be trusted with the octets.
* **No content-defined chunking.**
* **Still only QEMU.** Section 5 of `THEFT.md` marks its statements about
  real hardware as *expectations*, not measurements, because this tree has
  never booted on a physical machine.

## 6. What the next round would need

Effort in rounds of this project:

1. **Move the compiler pin and build disk encryption on the key
   management** -- 1 round for the pin plus its fallout, 1-2 rounds for
   the block layer. The open design decision is length preservation: XTS
   (confidentiality only, what LUKS and BitLocker ship) versus an AEAD
   with a separate tag area (real integrity, slower, more space).
2. **Content-defined chunking in `bak`** -- well under a round. One
   rolling hash, and the table in 3.6 changes from 100 % to a few per
   cent.
3. **Multiboot 2 in `boot.s`**, which makes the EFI path in `hwid.fi`
   reachable and is a prerequisite for a serious UEFI story -- 1 round.
4. **A boot on real hardware**, to replace expectation with measurement.
