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
| `kernel/user/bstore.fi` | *addendum 2*: the block store, snapshots, restore -- the whole engine |
| `kernel/user/backup.fi` | `/bin/backup`: a command line over `bstore` |
| `kernel/user/explorer.fi` | *addendum 2*: "Backup hierhin sichern", and snapshots as folders |
| `kernel/user/key.fi` | key management: wrap, unwrap, destroy |
| `kernel/user/shat.fi` | the SHA-256 measurement, in ring 3 |
| `tools/tresor/` | the runner, a second SMBIOS decoder, a memory dumper, a corrupter |
| `docs/THEFT.md` | the threat model |
| `docs/CRYPTO-ERASE.md` | why the key and not the data, and what is missing |
| `docs/ORPHANS.md` | *addendum*: the three backup rules and the `opk` interface |
| `tools/tresor/orphans.py` | *addendum*: the reference producer of the orphan list |

kdata grew by two pages at `0x5A000` (`HWID_OFF`), entered in
`tools/kernel/memmap.py`. The second page is not padding: it is the DMA
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

`backup verify` re-hashes every chunk. The host flips **one octet** in the
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

**The tool is called `backup`.** Not `sich`, and not `bak` either. The
owner rejected `sich` on 27.08.2026 and rejected my abbreviation `bak`
with it, settling the rule that now stands above every name in this
system: EVERY command, subcommand, option, field and format name in
Osum/OrientOS is ENGLISH -- no German stems, no German abbreviations, no
umlauts. The sole exception is the proper noun `opk` and its `.opk`
suffix.

`bak` failed that rule twice: it is a truncation, and a reader has to be
told what it stands for. The rename reached the file name
(`kernel/user/backup.fi`), the build target, the snapshot magic
(`backup1`, not `bak1`) and the test scratch names.

**A caught mistake worth recording.** The first rename replaced the text
`bak` with `backup` inside the error strings and did **not** adjust the
declared array lengths -- and Firn requires `[u8; N]` to match its string
literal exactly. Thirteen declarations were three octets short, so the
round did not compile at all after its own rename commit. `PROGS` still
listed `bak` as well, against a `kernel/user/bak.fi` that no longer
existed. Both are fixed, and the lesson is that a rename in this language
is not a text substitution.

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
* **No network backend for `backup`.** The seam is a path and nothing else,
  which is what makes adding one later small. It needs a transport that
  can be trusted with the octets.
* **No content-defined chunking.**
* **Still only QEMU.** Section 5 of `THEFT.md` marks its statements about
  real hardware as *expectations*, not measurements, because this tree has
  never booted on a physical machine.

## 5a. Regression check against an untouched baseline

This round changed four files that other rounds depend on: `kmain.fi`
(two calls), `kstate.fi` (constants), `nvme.fi` (one function) and
`procfs.fi` (one more file in `/proc`). The last one is the risky one --
`/proc` gained an entry, and a test that counted them would break.

So the affected sections were run **twice**: once on this branch and once
on a worktree of untouched `main` (`3389fbd`), same compiler, same host.

| section | untouched `main` | branch `tresor` |
|---|---|---|
| `tools/k14/run.sh` (VFS, /proc, /dev, FAT32) | 143 passed, **9 failed** | 144 passed, **8 failed** |
| `tools/k13/run.sh` (users, permissions, init) | 87 passed, **12 failed** | 87 passed, **12 failed** |
| `tools/userland/run.sh` | -- | 91 passed, 0 failed |
| `tools/posix/run.sh` | -- | 134 passed, 0 failed |
| `tools/tresor/run.sh` (this round) | -- | **104 passed, 0 failed** |

**The failures in k13 and k14 are not from this round.** They are present
on untouched `main` in the same numbers: all eight k14 failures are the
one `novfs` counter-check block, which produces no `k14:` lines at all on
either tree, and k13 fails identically on both. The single difference
(9 against 8) is one FAT32 `fsck` counter-check that failed on the
baseline run and not on this one -- it moves between runs, so it is flaky
rather than a verdict on either tree.

That those sections are red on `main` is worth someone's attention. It is
not this round's to fix, and this round did not make it worse.

A caveat on the numbers: the host was running several other rounds
concurrently (load average around 9, fourteen QEMU processes). Runners
that boot QEMU under a timeout are sensitive to that, which is the likely
reason a counter-check moved between runs.

## 5b. Addendum, 27.08.2026: orphaned packages

The owner asked what happens to programs that are in no source -- built
by hand, never published -- when a new machine is set up from a backup.

The answer was that the backup loses them, and the design said so without
noticing. A backup here is `PLAN` + `config/` + `state/`, and programs are
left out because their hash in the PLAN names them exactly and a source
can hand the octets back. That argument holds only while a source
actually can. For a self-built package the hash names something nobody
can deliver: it is **orphaned**, and `opk rebuild` on the new machine
stops at a hash it cannot resolve.

**Three rules now, and no fourth** (`docs/ORPHANS.md`):

1. ALWAYS -- `PLAN`, `config/`, `state/`. (Geheimnisse standen hier
   einmal mit drin; das ist seit dem dritten Nachtrag unten falsch.)
2. NEVER -- store entries a source can deliver, `apps/`, `etc/`, `cache/`.
3. ONLY IF ORPHANED -- a store entry no registered source can deliver.

Rule 3 is the precondition of rule 2 written down, not an exception to it.

**The interface, defined here because PLAN2's subcommand was not yet
there.** A plain text file, one store entry name per line, lower-case hex,
16 to 64 digits. `backup save <set> <store> <name> [orphans [tree]]` walks
`<tree>/store/<name>` for each and puts it in the snapshot at
`/store/<name>`. The name is treated as an **opaque path component**: the
rule that shortens a SHA-256 to 20 hex digits belongs to `opk`, and if
this side recomputed it, a change over there would break backups here
silently. `tools/tresor/orphans.py` is a working producer that imports the
real `opk.py`; run against a tree with one published and one self-built
package, it names exactly the self-built one.

**Measured** (`tools/tresor/run.sh` § 11, 20 assertions):

| run | orphan entries | octets written |
|---|---:|---:|
| no orphan list | 0 | 43,092 |
| one orphan | 1 | 72,220 |

**+29,128 octets, +67.6 %** -- and the growth equals the reported `orphan
bytes` exactly, which is asserted. The backup set is sized to match the
one PLAN2 measured on a real tree (44,076 octets); with the 812-octet toy
set I first used, the same package read as "+3587 %", a true number that
means nothing.

The restore is proved on a **second machine that has only the backup
store** -- no tree, no set, no package -- so the octets cannot come from
anywhere but `PACK`. There the entry restores, `verify` says `corrupt: 0`,
the restored program is **executed and prints its line**, and the host
compares it out of the disk image: 29,104 octets, byte for byte identical.

**Two bugs this addendum caught:**

* `restore` recorded the mode and never applied it. H6 said "the mode is
  kept" and half of it was false; nothing restored before had needed to
  *run*. Fixed with `chmod` (syscall 90).
* The earlier rename commit substituted `bak` -> `backup` inside string
  literals without adjusting the `[u8; N]` lengths, which Firn requires to
  match exactly. Thirteen declarations were three octets short and the
  round **did not compile at all**; `PROGS` also still named a file that
  no longer existed. A rename in this language is not a text substitution.

**What this side deliberately does not do:** it does not verify that a
listed entry really is unreachable. It has no source list and no network.
It checks the *shape* of every line -- which is what stops `../..` from
reaching a path -- and that the entry exists, and stores what it is told.
A wrong list costs space or loses a program, and both faults belong to the
producer, which is the side that has the information.

## 5c. Addendum, 27.08.2026: the button in the file manager

The owner described what he wanted in one sentence -- *plug in a stick,
go into it, say "save a backup here", done* -- and asked whether that
produces "a backup file, a ZIP or something".

**It does not, and the answer carries the design.** What lands on the
stick is a **directory**: a block store plus one text file per snapshot.
`docs/BACKUP-UI.md` is the full argument; the short version is that a
lump cannot share, cannot be partially rewritten, and cannot be browsed.
Time Machine is a directory of shared files; Windows' Backup is a lump,
and that is why the second one takes as long as the first.

**One implementation, two front ends.** The store moved out of
`backup.fi` into **`kernel/user/bstore.fi`**, and `/bin/backup` became a
119-line command line over it. The file manager calls the same functions.
The alternative -- letting the file manager run `/bin/backup` and scrape
its output -- was less code on the day and a second definition of the
format for ever after. The seam is a **function pointer**: `bstore` calls
a progress hook after every file, which is how the dialog can show
"Dateien / Oktette / neu" while the run is going.

**Three views in the file manager**, and the whole of the browsing story:
an ordinary directory; a store, showing its **snapshots** with the date
they were taken and their size; and the inside of a snapshot, walkable
like a folder, with "Zurueckholen" on one file or on the lot. The "Zeit"
column, empty since round K15 because OFS inodes carry no timestamp,
finally has something true to show: the snapshot header carries a **real
date from the CMOS clock**, the same source `/bin/date` reads.

**Measured** (`tools/tresor/run.sh` § 12):

| | |
|---|---:|
| first backup of the tree | 44,384 octets written |
| **second backup, nothing changed** | **0 octets** |
| one octet changed in a 16,384-octet file | 4,096 octets, **11× less** |
| same file in three folders | read 24,576, **written 8,192** |

Restore of one file and of the whole tree compared **out of the disk
image**: 4 of 4 identical.

**Three faults found and fixed on the way:**

1. `restore` recorded the mode and never applied it (found in the first
   addendum, and it is what makes a restored program runnable).
2. **A snapshot could be left half written.** Fixed properly rather than
   narrowly: blocks go to `PACK` first, the snapshot is written under a
   temporary `T-` name, `INDEX` follows, and `S-` appears last. Every
   snapshot ends with an **`end` line**, and `restore`, `verify` and the
   listing all refuse one without it. So a run that dies leaves wasted
   space and never a backup that lies. This kernel has no `rename`, so
   the last step is a copy of a small text file; if that fails the
   half-written `S-` is removed again.
3. **Backing up into your own source would have eaten itself.** `/data`
   is the source, and the first thing a user points at is a folder inside
   `/data`; the store would have grown while being walked. Refused now,
   with the prefix check written so that `/datakram` is not caught by it.

**What is NOT proven, and it is the honest hole in this addendum:** the
menu item is built and compiles, but `tools/tresor/gui.sh` does not yet
land the mouse on the tree row that navigates up, so the **wiring between
the menu item and the engine is not measured end to end**. The engine
under it is measured, and it is the same module. The runner is left in
the tree red and labelled rather than deleted or wired into `test.sh`.
An earlier version of it *passed* that step falsely, because
`grep 'explorer: cd /'` also matches `cd /data` -- the assertion is now
exact, which is why it is honestly red instead of dishonestly green.

Two useful things survive the attempt: the file manager now reports
`explorer: menurect` and `explorer: dlgrect`, so a test can click a menu
item or a dialog button without guessing. The missing one is where the
rows of the tree list sit.

## 5d. Dritter Nachtrag, 27.08.2026: was eine Sicherung mitnehmen darf

Der Eigentuemer, zur gerade gebauten Sicherung:

> Wenn ich ein Backup mache und woanders installiere, duerfen keine
> Passwoerter oder das Konto mituebertragen werden -- wenn jemand das
> Backup bekommt, ist dein ganzes Konto futsch.

Er hat recht, und `docs/THEFT.md` Regel 1 sagte woertlich, dass "the
secret store" IMMER mitkommt. Im Klartext. Auf einem Stick.

**Die falsche Loesung waere "dann eben keine Geheimnisse sichern".** Eine
Platte stirbt oefter als ein Stick gestohlen wird, und wer seinen
Passworttresor absichtlich draussen liess und dann einen Plattenschaden
hat, hat jedes Konto verloren -- genau das Ergebnis, um das es in dem
Einwand geht, nur ueber einen anderen Weg. Ein seltener lauter Ausfall
waere gegen einen haeufigen leisen getauscht.

**Gebaut wurde stattdessen: drei Klassen und ZWEI getrennte Geheimnisse**
(`docs/BACKUP-SECRETS.md`, `kernel/user/bsec.fi`).

| Klasse | was | im Backup? |
|---|---|---|
| (a) gewoehnlich | Dokumente, `PLAN`, `config/`, `state/` | ja; verschluesselt, wenn ein Speicherpasswort gegeben wurde |
| (b) geheim | Passworttresor, gespeicherte Anmeldungen, private VPN-Schluessel | **nur auf Verlangen**, und dann immer unter dem Hauptpasswort versiegelt |
| (c) nie | Geraeteschluessel, Maschinenkennung, Sitzungsmerkmale, TPM-Schluessel | **nie**, unter keiner Option |

Klasse (c) hat drei Gruende, jeder allein genuegt: ein TPM-Schluessel
*kann* nicht mit, er verlaesst den Chip nie; ein Sitzungsmerkmal ist die
Behauptung, dass GENAU DIESE Maschine angemeldet ist; und der
Geraeteschluessel ist das, woran `docs/CRYPTO-ERASE.md` haengt -- eine
Kopie davon im Backup macht das Loeschen wirkungslos. Das ist kein Leck,
das ist ein **Widerspruch** zu einer Zusage aus derselben Runde.

**Der Aufbau.** ChaCha20 (RFC 8439, neu in `kernel/user/chacha.fi`) plus
HMAC-SHA256 ueber den Geheimtext, encrypt-then-MAC. Nicht das vorhandene
AES: dessen eigener Kopf sagt "A4 NO GCM, NO AUTHENTICATION", und ein
Backup ist der schlechteste Ort, um zu lernen, was ein Padding-Orakel ist.
Schluessel aus PBKDF2-HMAC-SHA256; **Argon2id nicht**, und der Grund ist
konkret und keine Ausrede: Argon2id ist speicherhart und braucht zig
Mebioktett Kratzspeicher, und dieser Ring 3 hat **keinen
Speicherverwalter** -- jeder Puffer darin ist ein festes statisches Feld.

**Der eigentliche Entwurfsstreit war die Deduplizierung.** Naiv
verschluesselt -- neuer Zufallszaehler je Block -- ergeben gleiche
Klartexte verschiedene Geheimtexte, der Speicher erkennt keine
Wiederholung mehr, und jede gemessene Zahl dieser Runde bricht zusammen.
Die uebliche Antwort ist **konvergente Verschluesselung** (Name und
Schluessel aus dem Klartext-Hash). Sie ist hier **verworfen**, wegen eines
echten Angriffs: wer den Stick hat und eine Datei RAET, kann deren Namen
ausrechnen und im INDEX nachsehen -- das Backup beantwortet dann die Frage
"hat dieser Mensch GENAU DIESES Dokument", ohne Passwort.

Gebaut ist **geschluesselt-konvergent**: `name = HMAC(CONV, Klartext)`,
und `CONV` kommt aus dem Passwort. Gleiche Bloecke im selben Speicher
bekommen weiter denselben Namen -- die Deduplizierung ist unangetastet --
und ohne Passwort laesst sich der Name einer geratenen Datei nicht
ausrechnen. **Der Preis, benannt statt verschwiegen:** zwischen Speichern
mit verschiedenen Passwoertern dedupliziert nichts mehr. Fuer einen
persoenlichen Stick kostet das nichts; fuer einen geteilten Sicherungsserver
schon, und dort waere die Entscheidung neu zu treffen.

**Gemessen** (`tools/tresor/run.sh` § 13):

| Lauf | Optionen | geheime Dateien | ausgelassen (b) | ausgelassen (c) |
|---|---|---:|---:|---:|
| A | *(keine)* | **0** | 3 | 3 |
| B | `-mmasterpw` | 3 | 0 | 3 |
| C | `-pstorepw -mmasterpw` | 3 | 0 | 3 |

Der WIRT liest danach jeden fertigen Speicher AUS DEM ABBILD und sucht die
Marken darin, so wie ein Finder des Sticks es taete:

| Marke | Klasse | in A | in B | in C |
|---|---|---:|---:|---:|
| `MARK-PLAN-ORDINARY-DATA` | (a) | **1** | **1** | **0** |
| `MARK-VAULT-SECRET-BANK-PW` | (b) | 0 | **0** | 0 |
| `MARK-DEVICEKEY-NEVER` | (c) | **0** | **0** | **0** |
| `MARK-MACHINEID-NEVER` | (c) | **0** | **0** | **0** |
| `MARK-SESSION-NEVER` | (c) | **0** | **0** | **0** |

Die **1** in der ersten Zeile ist die Gegenprobe: eine Suche, die nie
etwas findet, beweist nichts. Die **1 in Spalte B** ist der Beweis, dass
die zwei Schichten wirklich getrennt sind -- `-m` hat den Tresor
geschuetzt und die Dokumente in Ruhe gelassen. Und Klasse (c) ist in
**jeder** Spalte null, auch dort, wo das Hauptpasswort auf der
Befehlszeile stand.

Der **Rohinhalt** des Tresorblocks wird aus PACK herausgeschnitten und
gezeigt -- 4112 Oktette, die Marke kommt **0 mal** darin vor:

```
5b4b743378616a7065261f3c23ced95c45063f5913ee6024b2baebc548ac243b...
```

und derselbe Tresor im zweiten Speicher, anderes Hauptsalz, ergibt
**andere** Oktette:

```
6a957e1d337642738230d85ed791200b94bbbfb642e72516d2183f3e821b5315...
```

Was die Verschluesselung kostet -- und was nicht:

| | Bloecke | neu | gelesen | **geschrieben** | ms |
|---|---:|---:|---:|---:|---:|
| ohne | 6 | **2** | 24576 | **8192** | 260 / 300 |
| mit | 6 | **2** | 24576 | **8224** | 280 / 320 |
| ohne, zweiter Lauf | 6 | **0** | 24576 | 0 | |
| mit, zweiter Lauf | 6 | **0** | 24576 | 0 | |

(Zwei Laeufe derselben Abnahme auf demselben Wirt; der UNTERSCHIED ist
beide Male 20 ms bei 10 ms Aufloesung. Darum haengt keine Zusage daran.)

**Die Deduplizierungsrate ist unveraendert**, und der zweite Lauf des
verschluesselten Speichers schreibt weiter **null** Oktette. Der Aufschlag
auf dem Datentraeger ist **0,39 %** -- 16 Oktette Marke je Block, sonst
nichts.

**Die ehrliche Luecke, gemessen statt umschrieben:** der SCHNAPPSCHUSS ist
nicht verschluesselt. Der Pfad `/secrets/vault.kdbx` steht auch im voll
verschluesselten Speicher C im Klartext, und der Test sucht ihn und
FINDET ihn. Ein gefundener Stick verraet also weiterhin, WAS man hat, nur
nicht, was darin steht. Die Behebung hat eine feste Form -- `S-` als
Strom versiegelter 4096-Oktett-Saetze durch dieselbe `seal`/`unseal` --
und beruehrt jeden Leser in `bstore.fi`; darum steht sie hier als Grenze
(`bsec.fi` B4) statt halb gebaut im Baum.

**Zwei Fehler, die dieser Abschnitt gefunden hat:**

* `-p pass -m pass` sind **neun** Argumente, und dieser Kern gibt einem
  Programm hoechstens `proc.MAX_ARGS` = 8. Die Schale sagte "too many
  arguments" und **liess den Befehl aus** -- die Sicherung lief nie, der
  Speicher blieb leer, und der Test las leere Felder. Das Passwort haengt
  jetzt am Buchstaben (`-pfoo`), und es gibt eine Zusage darauf, dass
  keine Zeile das Limit sprengt.
* `bsec.seal` haengt 16 Oktette an, und `bstore.fi` gab ihm einen Puffer
  von genau 4096. Jeder volle Block schrieb ueber das Ende hinaus, in das
  statische Feld dahinter. Der Puffer ist jetzt `CHUNK + TAGLEN`.

**Kein Widerspruch zum Stick-Grundsatz.** Ein Geraet laesst sich weiterhin
vollstaendig ohne Konto und ohne Netz aus einem Stick aufsetzen. Der
Tresor darf mit, er ist nur immer versiegelt. Der Preis wird laut gesagt:
**ein vergessenes Hauptpasswort heisst, der Tresor ist weg** -- das ist,
was "nicht aus dem Backup ableitbar" bedeutet, und die Alternative waere
eine Hintertuer mit freundlichem Namen.


## 6. What the next round would need

Effort in rounds of this project:

1. **Move the compiler pin and build disk encryption on the key
   management** -- 1 round for the pin plus its fallout, 1-2 rounds for
   the block layer. The open design decision is length preservation: XTS
   (confidentiality only, what LUKS and BitLocker ship) versus an AEAD
   with a separate tag area (real integrity, slower, more space).
2. **Content-defined chunking in `backup`** -- well under a round. One
   rolling hash, and the table in 3.6 changes from 100 % to a few per
   cent.
3. **Multiboot 2 in `boot.s`**, which makes the EFI path in `hwid.fi`
   reachable and is a prerequisite for a serious UEFI story -- 1 round.
4. **A boot on real hardware**, to replace expectation with measurement.
5. **`opk orphans` in PLAN2**, after which `tools/tresor/orphans.py`
   becomes the cross-check rather than the source, and the runner should
   assert the two outputs are equal.
6. **Finish `tools/tresor/gui.sh`** -- it needs the file manager to report
   where the rows of its tree list are, the way it now reports its menu
   and its dialog. Small, and it closes the one hole in addendum 2.
7. **A backup onto a FAT32 stick**, which `kernel/fat.fi` can already
   write; and OFS3, after which an OFS target stops being a toy.
