# THEFT.md -- what happens when somebody takes the machine

Round TRESOR. Written 27.08.2026, measured on QEMU 7.2.22.

This document is the threat model for device theft on ordinary PC
hardware, and it exists mainly to say **no** in a useful way. The
question it answers is not "how do we build Find My" -- it is "what of
that is physically possible for us, what is not, and what is worth
building instead".

Every number below comes from a run of `tools/tresor/run.sh`. Where
something is a design argument rather than a measurement, it says so.

---

## 1. The adversary

Assume the machine is gone: a laptop off a table, a desktop out of a
flat. The person holding it now:

* **has physical access, without a time limit.** They can open the case.
* **can remove the drive** and read it in another machine, or throw it
  away and fit a new one.
* **can install another operating system.** Nothing in our software is
  running any more at that point. This is the single most important line
  in this document: *software we ship cannot defend a machine that is not
  running it.*
* **can reset the firmware.** A CMOS jumper or a coin cell clears a BIOS
  password on most consumer boards. On many of them the vendor's own
  flashing tool will also rewrite SMBIOS strings.
* **can stay offline for ever.** Nothing that depends on the device
  phoning home can be relied on, because not phoning home costs the thief
  nothing.

There is no software answer to any of these five. Pretending otherwise is
how "anti-theft features" end up as marketing.

---

## 2. Why Apple's Activation Lock cannot be rebuilt here

Activation Lock is not clever software. It is a **hardware root of trust
plus a vendor monopoly**, and it needs all three of the following at
once:

1. **Silicon that keeps a secret the owner cannot read.** On Apple
   machines this is the Secure Enclave: a separate processor with its own
   fused key, which the main processor cannot extract. The lock state is
   bound to that key.
2. **Firmware that refuses to boot anything unsigned.** The boot chain is
   signed from the immutable ROM upwards, so a thief cannot replace the
   part of the system that enforces the lock. There is no "install
   another OS" path that skips it.
3. **A server the device must reach, run by the vendor, that everyone
   accepts.** Activation is a conversation with Apple. That is what makes
   the lock survive a wipe: the *device*, not the disk, is registered as
   stolen in a database that the *firmware* consults.

We have none of the three, and none of them is a programming problem:

* A generic PC has a TPM, which is real and useful, but a TPM binds keys
  to a **platform state**, not to an ownership claim that a firmware
  refuses to boot without. A TPM cannot stop a thief installing Linux; it
  can only stop that Linux from unsealing *our* keys, which is a
  different and much smaller promise (and a valuable one -- see
  `CRYPTO-ERASE.md`).
* We do not write the firmware of anybody's mainboard, so we cannot make
  the boot chain enforce anything.
* We are not a vendor that every mainboard in the world consults.

**Conclusion: Activation Lock is out of reach, permanently, on hardware
we do not build.** Any "lock" implemented purely in our operating system
is removed by installing a different operating system, which takes about
ten minutes and a USB stick.

---

## 3. Why "Find My" cannot be rebuilt here either

Find My does not find an offline device by magic. The offline case works
like this: the lost device emits a Bluetooth beacon carrying a rotating
public key; **any** nearby Apple device -- a stranger's phone in the
street -- hears it, encrypts its own location to that public key, and
uploads the result. The owner later fetches and decrypts it. Apple never
learns the location, which is the elegant part.

The part that cannot be copied is the precondition: **hundreds of
millions of foreign devices that already run the listening half.** The
protocol is publishable, the cryptography is ordinary, and the network is
the entire product. A beacon that nobody is listening for is a beacon
that does nothing.

For an operating system with, at time of writing, no users other than its
author, an offline location network is not a hard project. It is an
impossible one, and it stays impossible until the installed base exists.

**What remains possible is the online case**, and only that: a machine
that is switched on, connected, and still running our software can report
where it is. A thief avoids this by not connecting it, or by installing
Windows. So it is worth building -- some thieves are careless -- but it
must never be described as a recovery guarantee.

---

## 4. What is actually achievable

Three things, in descending order of how much they are worth.

### (a) Make the data unreadable -- the only one that always works

Full-disk encryption is the one measure that does not depend on the
thief's behaviour, on a network, or on our software still running. If the
drive is encrypted and the key is not on it, then the drive is noise. The
thief keeps the hardware; they do not get the data.

This is worth more than every locating and locking feature put together,
because losing the *data* is usually worse than losing the *machine*.

Status in this tree: **not built.** The key management for it exists as
of this round (`kernel/user/key.fi`); the cipher underneath does not.
`docs/CRYPTO-ERASE.md` sets out exactly what is missing and why the key,
not the cipher, is the interesting part.

### (b) Make the data recoverable -- so the loss is only money

If a backup exists, a stolen machine costs its purchase price and an
afternoon. If it does not, it costs everything on it. This is the part of
theft defence that is entirely in our hands, needs no hardware support,
no network and no vendor.

Status: **built and measured this round** (`kernel/user/bak.fi`, section
6 below).

### (c) Recognise the device if it ever reports in

A machine that is switched on with our system on it can say what it is.
For that it needs a name that survives a reinstall -- an identity read out
of the hardware and not out of a file. That is what `kernel/hwid.fi`
does.

Status: **built and measured** (sections 5 and 7 below). Its worth is
limited and the limits are measured, not estimated.

---

## 5. What SMBIOS is actually worth -- measured

`kernel/hwid.fi` reads the SMBIOS tables that the firmware leaves in
memory, the serial number of the NVMe drive, and the MAC address.

### The parser is right

The kernel's reading was checked against a **second, independent
implementation** (`tools/tresor/smbios.py`, Python, written from the
specification and not from the Firn source). The host dumps the same
physical memory over the QEMU monitor and decodes it separately. Entry
point, table address, table length, structure count and every string
agree:

| field | value |
|---|---|
| entry point | `0xf59f0`, 16-octet aligned |
| version | SMBIOS 2.8 |
| table | `0xf5a10`, 388 octets, 9 structures |

### Two parsing traps, both real

* **The string-set rule (SMBIOS 6.1.3).** After the formatted body comes
  one NUL per string and then **one more**. The plausible reading -- "the
  set ends at two NULs in a row" -- reads the first structure correctly
  and then mistakes the *type* octet of the next one (a 1, not a 0) for a
  continuation. Measured: that rule finds **1 structure of 9**.
* **The checksum is not decoration.** SeaBIOS carries the literal
  characters `_SM3_` in its own string table at `0x000F1031` -- the string
  its code uses to *build* the real entry point. A scanner that trusts
  four characters reads a string table as a table of hardware. Two things
  reject it here: the checksum fails, and `0x...031` is not 16-octet
  aligned. Measured: the kernel accepts exactly **1** entry point
  (`hwid: tried=1`), not two.

### And now the uncomfortable part

Two runs of the **same kernel image**, differing only in the QEMU command
line:

| field | plain QEMU | with `-smbios type=1,...` |
|---|---|---|
| `system_manufacturer` | `QEMU` | `Flei` |
| `system_product` | `Standard PC (i440FX + PIIX, 1996)` | `FLEI-ONE` |
| `system_serial` | *(empty)* | `SN-JUSTIN-0001` |
| `uuid` | sixteen zero octets | `11111111-2222-3333-4444-555555555555` |
| `uuid_valid` | `0` | `1` |
| baseboard structure | **absent entirely** | present, serial `BOARD-9999` |

Read that table twice. It says two things at once:

1. The parser works -- whatever the firmware puts there is what comes out.
2. **Whatever the firmware puts there is what comes out.** SMBIOS is a
   claim made by firmware. In a virtual machine it is a command-line
   argument. On real hardware many vendor tools will rewrite it. It is
   *not* a property of the silicon.

Also worth stating plainly: **a default virtual machine gives nothing
usable.** Empty serial, zero UUID, no baseboard structure. The kernel
reports `uuid_valid: 0` rather than treating sixteen zero octets as an
identity, because a fingerprint that hashed them would be identical on
every default VM on earth -- and would look every bit as convincing as a
real one.

### What to expect on real hardware

Not measured -- this tree has only ever been run in QEMU, and saying
otherwise would be inventing data. From the specification and from what
the fields are for, the *expectation* is:

* Type 1 UUID: usually present and genuinely unique on branded machines;
  often absent or all-zero on self-built boards.
* Type 1 serial: often present on branded machines, frequently empty or a
  placeholder (`To Be Filled By O.E.M.`) on retail boards.
* Type 2 baseboard serial: commonly present and often the most stable
  field of the three.
* NVMe serial: burned in by the drive vendor, **not** rewritable by
  ordinary tools, and the most trustworthy of the lot -- but it names the
  *drive*, so it dies with a drive swap.

Confirming this needs a boot on real hardware, which is an open item for
this whole tree, not just for this round.

### The MAC address is deliberately not in the fingerprint

It identifies the *card*, not the machine, and on most operating systems
it can be changed from software in one line. `/proc/hwid` prints it; the
fingerprint ignores it.

---

## 6. The backup -- measured

`bak` stores content-addressed: a chunk of octets is named by its
SHA-256, so identical chunks are stored once. Deduplication and
"incremental" are then the same mechanism, not two.

Source tree: 5 files, 3 directories, 25,491 octets, containing one file
that is a byte-for-byte copy of another.

| run | chunks seen | new chunks | octets read | octets written |
|---|---:|---:|---:|---:|
| first `bak save` | 9 | 5 | 25,491 | 11,155 |
| second `bak save`, nothing changed | 9 | **0** | 25,491 | **0** |

The second run reads the whole tree again and writes **nothing**. It does
not consult a timestamp or a change journal; it asks "do I already have
these octets", and the hash answers.

Time for the two runs: 260 ms and 190 ms. Both read all 25,491 octets;
only the writing differs. Treat that pair as a shape and not as a
throughput figure -- the timer resolution is 10 ms and the host was busy
with other work.

**Save, delete, restore is byte-identical.** Not checked against a serial
log -- the host reads the restored tree back **out of the disk image**
(`mkfs.py cat`) and compares it with the originals: **6 entries compared,
6 identical, 0 different** (5 whole-tree files plus one single-file
`bak get`). Restore reported 3 directories, 5 files, 25,491 octets.

`bak verify` re-reads every chunk out of the pack and hashes it again.
Counter-check: the host flips **one octet** inside the pack file *in the
disk image*, from outside the kernel (`tools/tresor/kaputt.py`; `cmp`
confirms exactly 1 octet differs). The same run then checks the damaged
store and an intact one: **1 corrupt chunk found in the damaged store, 0
in the intact one.**

### The honest limit: fixed-size chunking

The chunk boundary is at every 4096 octets, which means it moves whenever
anything is *inserted*. Same file, same eight octets, two positions:

| what | new chunks | octets written | of octets read |
|---|---:|---:|---:|
| 8 octets appended at the **end** | 1 of 3 | 2,056 | 10,248 (20.1 %) |
| 8 octets inserted at the **front** | **3 of 3** | **10,248** | 10,248 (100 %) |

Eight octets in a different position, and deduplication goes from saving
80 % to saving nothing. This is the known weakness of fixed-size
chunking and the fix is known too -- **content-defined chunking**, where a
rolling hash puts the boundary where the *data* says rather than where
the counter says. It is not in this round.

Other limits, stated rather than discovered later: no compression, no
encryption of the store, at most 1024 distinct chunks in memory per run
(4 MiB of unique data), directory nesting at most 8 deep, no owner and no
timestamps preserved.

---

## 7. What this round actually delivers against theft

Honest scoring against section 4:

* **(a) data unreadable** -- *not delivered.* Key management only. The
  disk is plain. A stolen drive is readable in another machine today.
* **(b) data recoverable** -- *delivered and measured*, to a second disk
  or a mounted FAT32 stick. No network target (needs TLS, which is not
  finished in this tree).
* **(c) device recognisable when online** -- *delivered and measured*, as
  a fingerprint that survives a reinstall. Proved: the same machine with
  a **freshly built disk image** produces the **same** fingerprint; a
  different machine produces a different one. On a default virtual
  machine the fingerprint rests on 2 sources and `hwid` says so
  (`sources:`), because a fingerprint over nothing is not an identity.

What does **not** exist, and should not be implied anywhere:

* No lock of any kind. Nothing prevents booting another system.
* No reporting-in, no server, no registry of stolen machines.
* No location, online or offline.
* No tamper detection, no TPM use, no secure boot.

---

## 8. What the next round would need

In the order that buys the most safety per round:

1. **An AEAD in `lib/std/crypto`**, then full-disk encryption on top of
   the key management this round built. That is item (a), the only
   measure that always works. Certus B6 is building the AEAD; see
   `CRYPTO-ERASE.md` for what exactly is missing.
2. **Content-defined chunking** in `bak`, so that an insertion does not
   destroy deduplication. One rolling hash, and the table in section 6
   changes from 100 % to a few per cent.
3. **A boot on real hardware**, to replace section 5's *expectations*
   about SMBIOS fields with measurements. Everything in this tree has only
   ever run in QEMU.
4. **Multiboot 2 in `boot.s`.** The EFI configuration-table path in
   `hwid.fi` is written and measured against a hand-built system table,
   and it is unreachable from a real UEFI boot because multiboot 1 hands
   over no system table pointer. Until then, a UEFI machine without a
   legacy F-segment yields no SMBIOS at all.
5. **A network backend for `bak`**, once there is a transport that can be
   trusted with the octets.
