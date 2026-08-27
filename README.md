# Osum

An operating system kernel for x86-64, written in **Firn**. It boots via
Multiboot, manages memory and address spaces, schedules processes, reads
its own hardware over PCI, speaks NVMe over DMA, runs on multiple
processors, offers a POSIX layer with the system call numbers of Linux
x86-64, starts a userland of standalone ELF files off the disk — a shell
and twenty-three tools — and **shows all of it in windows**: with a
mouse, a window server and TrueType fonts with antialiasing.

multiple processors, **speaks TCP/IP through a virtio-net card**, offers
a POSIX layer with the system call numbers of Linux x86-64 and starts a
userland of standalone ELF files off the disk — a shell and twenty-five
tools. Since round K11 you can **work** on it: there is a full-screen
editor, twenty more tools (`find`, `sed`, `diff`, `patch`, `tar`, `gzip`,
…) and a shell with `if`, `for`, `while`, `case` and functions.

    osum$ edit /notizen.txt          # ^O saves, ^X leaves, ^W searches
    osum$ find / -name *.txt -type f
    /d/three.txt
    /notizen.txt
    osum$ tar -cf /w/alles.tar /d ; gzip /w/alles.tar
    osum$ for f in a b c ; do echo $f > /w/$f ; done
    osum$ if [ -s /w/a ] ; then echo da ; fi
    da

    osum$ cat /d/nums.txt | grep 1 | wc -l
    4
    osum$ sort /d/three.txt | head -n 1 > /first.txt
    osum$ cd /d ; ls ; wc -l < nums.txt
    ./ ../ three.txt dup.txt nums.txt empty.txt
    12
    osum$ ping -c 3 10.9.0.1
    PING 10.9.0.1 56 octets of data.
    64 octets from 10.9.0.1: icmp_seq=1 time=20 ms
    64 octets from 10.9.0.1: icmp_seq=2 time=10 ms
    64 octets from 10.9.0.1: icmp_seq=3 time=10 ms
    --- ping statistics
    3 transmitted, 3 received, 0% packet loss
    osum$ wget http://10.9.0.1:8000/x
    wget: connected to 10.9.0.1:8000
    a page from the linux kernel side, 46 octets.
    wget: status 200

The size, counted:

| part | lines |
|---|---:|
| `kernel/*.fi` — the kernel | 30,383 |
| `kernel/user/*.fi` — shell, tools, ulib | 5,114 |
| `kernel/*.s`, `kernel/user/crt.s` — assembly | 1,336 |
| `lib/libc/*.fi` — the libc from round K4 | 1,598 |
| `tools/` — the test runners | 9,650 |

Round **TILING** turned the floating windows into a **window tree**, the
way i3, sway and bspwm keep one: leaves are windows, inner nodes are
splits with a *ratio* (not with pixels), a container can be `split`,
`tabbed` or `stacked`, and rotating, mirroring and balancing a subtree
come with it. The Windows-style quick snap (half left, a quarter) is a
*special case* of that tree and not a second mechanism.

    tile: selftest 24/24  failed=0x0
    tile: fuzz ops=10000  violations=0  peak=85  checks=10000
    tile: bench relay2=5419 ns  relay8=28644 ns  relay32=94061 ns
    tile: dirty split=240000  close=240000  screen=480000

The middle line is the one that matters: ten thousand random operations
(open, close, move, change mode, resize, rotate, mirror, snap), and after
**every single one** the kernel recomputes the invariant on two
independent paths — no gap, no overlap, the sum of the children is
exactly the parent. Zero violations. It found two bugs that nobody would
have found by hand; both are named in `docs/TILING.md`, together with
what does not work and why. The key map is a text file in
`/users/<name>/config/tiling.conf`, not source code — without the file
there is no key map at all, and the acceptance run boots a second image
to prove it. `kernel/tile.fi`, `kernel/user/tiling.fi`, `tools/tiling/`.

Most recently added: round K10 has TWO parts that ran in parallel.
The user interface -- `kernel/wm.fi` (the window server), `kernel/ttf.fi`
(TrueType reader and rasteriser) and `kernel/ps2m.fi` (the pointing
device), plus on the host `tools/ttf/schnitt.py`, `tools/ttf/raster.py`
(the SECOND version of the rasteriser, the one the first is measured
against) and `tools/wm/` (`docs/ROUNDK10W.md`). And the protection bits
-- `kernel/guard.fi` (SMEP and SMAP in CR4 together with the `stac`
window) and `kernel/bootmod.fi` (a boot module as the root disk, with a
CRC32 in front of it); both ported from OrientOS' Rust kernel and the
last two open items of the kernel switch there (`docs/ROUNDK10.md`).
Round K11 added the editor and the twenty tools (`docs/ROUNDK11.md`).

On top of that, from the capability round: `kernel/cap.fi` (the handle
table) and the test runners `tools/caps/` and `tools/boot/`. From the
network round K8: `kernel/virtio.fi`, `kernel/inet.fi`,
`kernel/netsvc.fi`, `lib/libc/net.fi` and `tools/net/`.

The **TCP/IP stack** (2,646 lines) is not part of this count — it is not
written here. It comes in as a dependency from the Firn commit that
`vendor/firn/COMMIT` pins for the compiler anyway;
`vendor/net/HERKUNFT.md` says how, and section 1 of `./test.sh` checks
the three blob hashes.

Osum is **not a toy bootloader and not a finished system.** What it can
do is below; what it cannot do is below as well, and that is the longer
list.

---

## What it can do

**Boot and kernel, BIOS and UEFI.** Multiboot through `boot.s`. Since the
capability round the header demands a **linear framebuffer** (flag bit
2): without that bit a Multiboot loader insists on a text mode that does
not exist under UEFI and aborts — with it, the same image boots through
SeaBIOS **and** through OVMF. The ISO for that is built by OrientOS.
Further: its own GDT/IDT, every exception reported with error code and
register set (`#DE`, `#PF`, `#GP`, `#DF`), PIC and PIT with a rising tick
counter, serial console, keyboard through IRQ1.

**Memory.** Memory map from the Multiboot header, frame allocator, heap,
page tables. Every process gets its **own address space**; a process that
touches kernel memory dies, and the kernel lives on.

**Processes.** Scheduler with preemption through the timer, context
switch in `switch.s`, ring 3 through `syscall`/`sysret`, `fork`,
`execve`, `wait4`, pipes, `dup2`.

**File system.** OFS — a file system of its own with inodes, direct and
indirect blocks, directories, `getdents64`. It sits on a RAM disk, on an
ATA disk or on NVMe. `tools/osum/mkfs.py` builds images of it outside the
kernel.

**Several file systems side by side (round K14).** A file system registers
itself with a **table of nine operations** (`kernel/vfsops.fi`) — real
function pointers, counted in the compiled object file. `kernel/vfs.fi`
resolves paths across mount boundaries (longest matching mount path, at a
NAME BOUNDARY: `/mnttest` is not `/mnt`), mounts with a target (`mount`,
Linux' number 165) and unmounts again (`umount2`, 166) — with a check for
open descriptors, so `-EBUSY` instead of data loss. OFS is the **first
user** of this layer (`kernel/ofs.fi`), not a special case beside it: with
the word `vfsall` the root goes through the same table too, and the same
work produces byte for byte the same output. On top of it:

* **`/proc`** (`kernel/procfs.fi`) — a file system whose files come into
  being when they are READ: `meminfo`, `cpuinfo`, `uptime`, `mounts`,
  `stat`, `version`, and per process `status`, `stat`, `cmdline`, `maps`,
  `fd/`. `cmdline` reads the address space of the other process through
  `proc.translate`; `maps` walks its PAGE TABLE — a process that takes a
  page for itself with `mmap` has a different file afterwards.
* **`/dev`** (`kernel/devfs.fi`) — `null`, `zero`, `random`, `urandom`,
  `tty`, `console`, `fb` and the block devices `hda`, `hdb`, `ram0`,
  `nvme0`. `lseek(SEEK_END)` on `/dev/hdb` says how large the disk is;
  `ls -l` tells a character device from a block device.
* **FAT32, reading and writing** (`kernel/fat.fi`) — with long names
  (VFAT), subdirectories and chains across any number of clusters.
  Measured against the REAL tools: the image comes from `mkfs.vfat`, the
  files from `mcopy`, and `fsck.fat` passes judgement on what Osum has
  written (return value 0, no complaint).
* **MBR and GPT** (`kernel/part.fi`) — both tables, and for GPT BOTH
  CRC32 checksums are computed. One flipped bit in the header and the
  disk is no longer read.

**ELF loader.** `/bin/sh` is a file. The kernel reads it off the disk,
puts its segments into a fresh address space with the rights they ask
for, and starts it. All tools are standalone ELF64 files without a libc
binding to the kernel.

**Hardware.** PCI enumeration through the configuration space, local APIC
and I/O APIC, NVMe over DMA with a queue of its own.

**Screen.** A linear framebuffer, taken from the loader (Multiboot, flag
bit 12) or set up by the card itself (Bochs VBE over PCI — QEMU's
`-kernel` has no video part). On top of it a text console of 100 x 37
characters with its own 8x16 font, scrolling, colours and a cursor, plus
pixel, line, rectangle, image area and a back buffer with region-wise
transfer. **The serial console keeps running in parallel** —
`serial.put` mirrors every byte, so both show the same thing, from the
boot messages to the shell. And **/dev/fb**: a program in ring 3 opens
it, writes into it, reads back, and maps it into its own address space
with `mmap` as a 2 MiB tile — with the usual permission checks. All of
this hangs on the word `gfx` on the command line; without it nothing
about the kernel changes. Measured against screenshots
(`docs/ROUNDK7.md`).

**User interface (round K10).** A **pointing device** on the second port
of the keyboard controller (IRQ 12, `kernel/ps2m.fi`): three- and
four-byte packets, wheel, clamping at the screen edges, a drawn pointer.
A **window server** (`kernel/wm.fi`): create, move, resize and close
windows; stacking order; input focus; events to the right window; and
**damage tracking**, so that only what is new gets painted — measured
6801 us for the whole screen against 198 us for a pointer movement, a
factor of 34. Applications talk to it through **handles** from
`kernel/cap.fi` (nine calls from 2100 on), not through a second path.

And **real fonts** (`kernel/ttf.fi`): a TrueType reader (`head`, `hhea`,
`maxp`, `hmtx`, `cmap` format 4, `loca`, `glyf`, `kern`) and a rasteriser
with **antialiasing**, entirely in Firn and entirely in fixed point — no
FreeType, no floating point number. The fonts sit on the disk as
subsetted TrueType files (`assets/`, `tools/ttf/schnitt.py`). On top of
that a **terminal window** in which `/bin/sh` runs off the disk, and a
second window that a program in **ring 3** creates, paints and answers
clicks and keystrokes in.

Measured against screenshots into which **real mouse movements, clicks
and key presses** were fed through the QEMU monitor — and the text in
them not against a surface but **per character** against a second,
independent rasterisation of the same outline
(`tools/ttf/raster.py`). `docs/ROUNDK10.md`.

**NVMe throughput, measured.** In QEMU/TCG at 2.19 GHz, 128 KiB in one
go (`tools/pci/run.sh` reproduces it):

| path | KiB/s | words through the CPU |
|---|---:|---:|
| ATA PIO, 1 block per command | 4,541 | 65,536 |
| NVMe DMA, 1 block per command | 6,485 | **0** |
| NVMe DMA, 16 blocks per command | 97,663 | **0** |

Those are the figures from `docs/OSUM-K2.md`. The value of the fast path
depends on the host: the same test delivered 109,208 KiB/s on this server
under load, and 140,799 KiB/s were measured on an idle machine. Only the
last column is structural: the DMA path pushes **no** data word through
the CPU, and no host changes that.

**Multiple processors.** The application processors are read from the
ACPI MADT and started with INIT/SIPI; each gets a stack, a descriptor
table and a local APIC. Run queue, frame allocator and file system are
under one lock. Measured: the same work on one core against four cores,
**speedup 3.54**, with the counter-checks `nosmp`, `nolock` and
`thread=single`.

**POSIX layer.** Twenty-six system calls with the **numbers of Linux
x86-64** — `read`, `write`, `open`, `close`, `stat`, `fstat`, `lseek`,
`mmap`, `brk`, `pipe`, `dup2`, `fork`, `execve`, `wait4`, `getdents64`
and the rest — and on top of them a libc in Firn (`lib/libc/`). The
failure cases are measured along with them: fourteen ways to be wrong,
fourteen negative return values, a living kernel afterwards.

**Handles instead of ambient authority.** Next to the POSIX layer stands
a second ABI, ported from OrientOS (`libs/osum-abi-native/`, Rust →
`kernel/cap.fi`, Firn): a **handle table per process** in which a handle
consists of a slot, a generation and a per-process random value, with ten
rights bits and eight object kinds. Three statements, and every one of
them is measured from ring 3 (`tools/caps/run.sh`, eighteen checks):

* **A fresh table is empty.** Nothing is inherited — not even from a
  predecessor in the same slot of the task table.
* **A closed handle never hits anything again**, not even after the slot
  has been reused (generation).
* **Rights can only get smaller.** A copy with fewer rights cannot fetch
  back what it lost.

The difference from POSIX in one line: a valid handle without the
required right is `RightsDenied`, a forged one is `BadHandle` — POSIX has
only `-EBADF` for both. The call numbers start at 2000; what does **not**
exist yet (channels, ports, namespaces, spawn with a handle list, memory
objects) answers `NotSupported` and is an open item in OrientOS'
`KERNELWECHSEL.md`.

**Network.** A **virtio-net driver** in Firn (`kernel/virtio.fi`), modern
by virtio 1.0: the four regions from the device's capability list,
feature negotiation with `FEATURES_OK`, two virtqueues of 64 descriptors,
MSI-X or the interrupt pin. On top of it the **TCP/IP stack from round
K3** — as a dependency, not as a copy — and above that **sockets for ring
3** with the numbers of Linux x86-64 (`socket` 41, `connect` 42, `accept`
43, `sendto` 44, `recvfrom` 45, `shutdown` 48, `bind` 49, `listen` 50,
`getsockname` 51, `getpeername` 52). A socket is an entry in the open
file table from round K4, so `read`, `write`, `close`, `dup2` and `fork`
work on it without any of them knowing what a socket is.

**Measured against the real Linux kernel** (`tools/net/run.sh`, 75
checks, `veth` + `AF_PACKET` in a network namespace of its own, QEMU
without KVM):

| what | result |
|---|---|
| `ping -c 10` from the Linux kernel | **10 of 10**, 3.3 ms on average |
| `nc` pushes 1 MiB in | **1,048,576 bytes**, 732 frames, **6,027 KiB/s**, 0 retransmissions |
| `nc` through the echo | **262,144 bytes there and back, md5 identical** |
| `curl http://10.9.0.2:8080/` | status line, header and body accepted by curl itself |
| Osum connects **actively** | 262,144 out, 262,144 back, **0 wrong bytes** |
| `tc netem loss 20 %` inbound | everything in order, 132 segments reassembled |
| `tc netem loss 10 %` outbound | 0 wrong, **4 losses recovered: 1 through the timer, 3 through three duplicate acks** |

Counter-check: the same kernel image without the word `nic` loses every
packet, `nicnobm` (no bus master) likewise, and with `nicnoirq` all
262,144 bytes arrive while the interrupt counter stays at 0. The figures
and the open items are in `docs/ROUNDK8.md`.

**The kernel protects itself from the userland (round K10).** SMEP and
SMAP stand in CR4 as soon as CPUID reports them — on EVERY core, because
CR4 is per processor. Ring 0 no longer executes user code with them, and
it touches user data only in the `stac` window, which stands in exactly
four places (`sys.peek`, `sys.poke`, `sys.copy_in`, `sys.copy_out`) plus
at the signal frame. What is measured is not the claim but the register:
`guard: cr4=0x300020  smep=1  smap=1`. Counter-checks: `smapraw` and
`smepraw` have to produce a #PF with the bits set (error code 0x1 and
0x11) and to run through without them.

**A boot module can be the root disk (round K10).** What a loader places
next to the kernel (Multiboot, flag bit 3) is checked with CRC32 and then
mounted as a block device — `fs.fi` notices nothing of it, they are the
same 512 bytes per block. That way an ISO carries not just a kernel but a
userland. A wrong `modcrc=` leaves the module alone, and `mem.scan` takes
its region out of the frame allocator -- proved by the sum at the END of
the run being the same one.

**Users, permissions and a first process (round K13).** Every process
carries a real, an effective and a saved user and group id; they are
inherited through `fork` and `execve` and changed through
`setuid`/`setgid`/`setresuid` with the rules of POSIX -- call numbers as
on Linux. Files carry permission bits and an owner IN THE INODE; the
format got a version number in the superblock for this and old images
stay readable. The check stands in ONE place (`kernel/perm.fi`) and is
called from five gates: `open`, `mkdir`, `unlink`, `chdir`, `execve`.
Plus `chmod`, `chown`, `id`, `whoami`, `su`, `passwd` and `login` --
passwords as PBKDF2-HMAC-SHA256 with salt, measured against Python's
`hashlib`. And `/sbin/init` as **process 1**: a service table
(`/etc/inittab`), restart of crashed services, reaping of orphans, `svc`
for starting/stopping/querying, and a shutdown through real ACPI -- to be
recognised by QEMU's exit code (0 instead of 21). An escape hatch on the
command line (`initsh`) starts the shell as before.

**Userland.** `/bin/sh` with pipes, redirection (`>`, `<`), `;`, line
editor, `cd`, `exit` — and twenty-five tools: `cat`, `cp`, `date`, `df`,
`echo`, `false`, `grep`, `head`, `kill`, `ls`, `mkdir`, `mv`, `ping`,
`ps`, `rm`, `rmdir`, `sleep`, `sort`, `tail`, `touch`, `true`, `uname`,
`uniq`, `wc`, `wget`.

**What happens when the machine is stolen (round TRESOR).** A **device
identity** that survives a reinstall (`kernel/hwid.fi`): the SMBIOS tables
the firmware leaves in memory (entry point found by a 16-aligned,
checksummed scan of `0xF0000..0xFFFFF`; type 1 system and type 2
baseboard), the serial number of the NVMe drive out of **IDENTIFY
CONTROLLER** -- a second command, not the namespace identify the driver
already had -- and the MAC address. Readable as `/proc/hwid`, with
`/bin/hwid` showing the raw values and a SHA-256 fingerprint over the
fields that a reinstall does not change. Measured against a **second,
independent SMBIOS reader in Python** that decodes the same memory dump.

A **backup** that is content addressed like `opk` (`/bin/backup`): every
chunk is named by its SHA-256, so identical chunks are stored once and
"incremental" is not a separate mechanism. Measured: the second `backup save`
of an unchanged tree reads all 25,491 octets and writes **0**; save,
delete and restore give a tree that the HOST reads back out of the disk
image and compares octet for octet (6 entries, 6 identical); and one
flipped octet in the pack file is found by `backup verify`.

The backup carries **three rules and no fourth** (`docs/ORPHANS.md`):
user data is ALWAYS kept, packages a source can deliver and `cache/` are
NEVER kept, and a package **no source can deliver** -- built by hand,
never published -- is kept ONLY THEN, because its hash in the PLAN names
octets nobody else has.

**Secrets are not user data** (`docs/BACKUP-SECRETS.md`). A backup stick
is an object and objects get lost, so there are **three classes**:
ordinary data travels; the **password vault, saved logins and VPN private
keys travel only on request** and only sealed under a separate master
password that is never in the backup; and the **device key, machine
identity and session tokens never travel at all** -- they are re-created
on the target, and a copy of the device key in a backup would defeat the
crypto erase this same round built. Measured: with the vault carried
along, the marker `MARK-VAULT-SECRET-BANK-PW` occurs **0 times** in the
finished store, while ordinary data is still found **1** time in the same
search -- and the whole backup encrypts too, at a cost of **0.39 %** on
disk and **no loss of deduplication at all** (6 blocks seen, 2 stored,
with and without). What is *not* hidden is stated and measured: the
**paths** in a snapshot are still readable. Measured: one such package costs **+29,128
octets, +67.6 %** on a realistic backup set, and a second machine holding
*only* the backup store restores it byte for byte and **runs** it.

Backing up is **a menu entry in the file manager**, not a command to
learn: right-click a folder or a stick → *"Backup hierhin sichern"*. What
lands there is a **directory**, not a ZIP -- a block store plus one text
file per snapshot -- so the second backup of an unchanged tree writes
**0 octets**, one changed octet in a 16 KiB file costs **4,096 instead of
44,384** (11× less), and the same file in three folders is stored once.
Going *into* a backup shows the snapshots with the date they were taken,
and you can walk into one and fetch a single file back like any other
copy. `docs/BACKUP-UI.md` has the numbers and the honest limits --
including that the menu entry itself is built but not yet measured end to
end.

And the **key management** that disk encryption would hang off
(`/bin/key`): a random data key, wrapped by a passphrase-derived key
(PBKDF2-HMAC-SHA256, measured against Python), authenticated before it is
unwrapped, and destroyable in milliseconds -- which is what remote wipe
has to mean, because overwriting a terabyte is not something a stolen
machine stays online long enough to do.

**What this round explicitly cannot do is written down and measured too**
(`docs/THEFT.md`): Apple's Activation Lock needs our own silicon, our own
signed firmware and a vendor server, and Find My needs an installed base
of millions of foreign devices -- neither is a programming problem. SMBIOS
serial numbers are a claim made by firmware: the same kernel image, with
`-smbios` on the QEMU command line, reports whatever was put there, and a
default virtual machine gives an empty serial, a zero UUID and no
baseboard structure at all. And the backup's fixed 4096 octet chunking is
measured at its worst: eight octets appended to a file cost 1 new chunk
of 3, the same eight octets inserted at the FRONT cost 3 of 3.

---

## What it lacks

* **No window system.** There is a framebuffer, a text console and
  `/dev/fb` (round K7) — but only ONE surface. Console and program paint
  over each other when they take the same scan lines. There is no
  `ioctl` either: a program learns the size of the image through
  `lseek(SEEK_END)` and the width not at all.
* **The window server runs IN THE KERNEL.** Round K10 has windows, a
  mouse, stacking order, input focus and real fonts — but the server sits
  in ring 0, because this kernel cannot share memory between two
  processes (`mmap` knows anonymous pages and the framebuffer, nothing
  else). The protection between the APPLICATIONS is there; the one
  between server and application is not.
* **No `ioctl` for the surface.** A program learns the size of its window
  through `wm_info` and that of the screen through `lseek(SEEK_END)` on
  `/dev/fb` — change the resolution it cannot.
* **No hinting, no subpixel positioning, no rotation.** The rasteriser
  places glyphs on whole pixels and inserts composite glyphs with their
  offset, not with their matrix.
* **No network.** No driver for a network card. A TCP/IP stack in Firn
  exists (round K3, `docs/OSUM-K3.md`), but it lies in the Firn
  repository under `lib/net/` and has never been connected to this
  kernel — it was measured against the Linux kernel through a `veth`
  pair, not against a card.

* **No graphics.** No framebuffer, no VGA text mode as a console, no
  window system. The console is the serial port.
* **No name resolution.** No resolver, no `/etc/hosts`: an address is
  four numbers. `/bin/wget` rejects a URL with a name in it instead of
  answering something wrong.
* **Only one queue pair in the network**, no offloading of checksums to
  the card, no IPv6, no reassembly of IP fragments, no window scaling, no
  SACK.
* **No USB.** Neither host controller nor keyboard over USB. The keyboard
  is the PS/2 controller.
* **No SATA/AHCI**, no partition table reader, no journal in the file
  system, no dynamic linking, no shared libraries.
* **Permissions, but not complete ones.** Since round K13 there are
  users, permission bits and owners -- but the traverse permission is
  only checked on the LAST directory of a path, not on every element;
  there are no supplementary groups and no `/etc/group`; the sticky bit
  is stored and not honoured; and the 2048 rounds of PBKDF2 are too few
  by today's standards (the round count is stored in the entry and can be
  raised). `docs/ROUNDK13.md`, section 7, lists the gaps one by one.
* **Only x86-64, and without an architecture boundary.** Firn can do
  aarch64 as well, the kernel cannot — and there is no layer in this tree
  behind which the x86 details are hidden. OrientOS had
  `kcore/arch_iface.rs` for that (traits plus a test step that forbids
  x86 terms outside of `arch/`); that is NOT ported, because it would be
  a rebuild of every module and not a port. The template is in OrientOS
  under `vorlage/arch_iface.rs`.
* **Channels, ports, namespaces.** The native calls for them exist in
  `sys.fi`, and they answer `NotSupported` (−9): the call EXISTS in this
  ABI, this kernel just does not offer it. What is ported is the handle
  model underneath (`cap.fi`), not the objects that hang off it.
* **Testing happens in QEMU**, not on real hardware.

---

## Building and running

Required: `bash`, `git`, `rustc`/`cargo` (for the pinned compiler),
`binutils` (`as`, `ld`, `objcopy`, `nm`, `objdump`), `python3`,
`qemu-system-x86_64`.

```sh
git clone <this repo> osum
cd osum

# once: build the pinned Firn compiler
FIRN_REPO=/path/to/firn ./vendor/firn/hole-firnc.sh

# the whole acceptance suite (nineteen sections, 1638 checks, QEMU per case)
./test.sh
```

`./test.sh` calls `hole-firnc.sh` itself when the compiler is missing. If
the Firn repository sits as a sibling directory (`../firn`), the script
finds it without `FIRN_REPO`.

Individual sections also run on their own:

```sh
bash tools/kernel/run.sh      # the kernel (rounds 59/62)
bash tools/osum/run.sh        # ELF loader, /bin/sh off the disk (K1)
bash tools/pci/run.sh         # PCI, APIC, NVMe (K2)
bash tools/posix/run.sh       # POSIX layer and libc (K4)
bash tools/smp/run.sh         # four processors (K5)
bash tools/userland/run.sh    # shell and tools (K6)
bash tools/gfx/run.sh         # the screen (K7)
bash tools/unix/run.sh        # signals, terminal, clock, randomness (K9)
bash tools/net/run.sh         # virtio-net and the TCP/IP stack (K8)
bash tools/guard/run.sh       # SMEP/SMAP and the boot module (K10)
bash tools/wm/run.sh          # mouse, windows, TrueType (K10)
bash tools/hv/run.sh          # the hypervisor: AMD-V, NPT, guests (K12)
bash tools/k14/run.sh         # VFS, /proc, /dev, FAT32, MBR/GPT (K14)
bash tools/k16/run.sh         # the compiler on Osum itself (K16)
```

Start the kernel with a screen and look for yourself — `-vga std` is the
card that `kernel/fb.fi` drives:

```sh
qemu-system-x86_64 -kernel /tmp/k.mb -m 256 -append "osum gfx" \
   -serial stdio -vga std
```

And with **windows**, a mouse and real fonts (round K10). The fonts sit
on the disk, so it takes an image with `/lib/mono.ttf` and
`/lib/sans.ttf` on it:

```sh
python3 tools/osum/mkfs.py build /tmp/d.img 4096 /lib/ \
   /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf
qemu-system-x86_64 -kernel /tmp/k.mb -m 256 -append "gfx wm wmhold" \
   -serial stdio -vga std -drive file=/tmp/d.img,format=raw,if=ide,index=0
```

Build an image by hand and start it (what `tools/userland/run.sh` does in
more detail):

```sh
export FIRNLIB=$PWD/lib
FC=vendor/firn/bin/firnc
for f in boot isr switch smp; do as --64 -o /tmp/$f.o kernel/$f.s; done
$FC kernel/kmain.fi -o /tmp/k.o
$FC kernel/uprog.fi -o /tmp/u.o
ld -T kernel/kernel.ld --defsym=KERNEL_MAIN=_F0.kernel_main \
   -o /tmp/k.elf /tmp/boot.o /tmp/isr.o /tmp/switch.o /tmp/smp.o /tmp/k.o /tmp/u.o
objcopy -O elf32-i386 /tmp/k.elf /tmp/k.mb
qemu-system-x86_64 -kernel /tmp/k.mb -m 128 -append "osum" \
   -serial stdio -display none -no-reboot
```

---

## The compiler is a dependency, not content

Osum is written in Firn, but the Firn compiler does **not** belong in
this repository. It is **pinned**:

* `vendor/firn/COMMIT` contains exactly **one** Firn commit.
* `vendor/firn/hole-firnc.sh` fetches that state (`git archive`, without
  creating anything in the Firn repository) and builds
  `vendor/firn/bin/firnc` (firnc0, in Rust), `vendor/firn/bin/firnc1`
  (the compiler in Firn, compiled by firnc0) and `vendor/firn/lib/` (the
  Firn library of the same commit).
* Only the hash and the script are checked in, never the binary.

**Why.** Firn is under active development. If Osum were always built
against the newest state, then with every bug it would be unclear whether
it comes from the kernel or from the compiler. The hash is therefore
moved forward **only when `./test.sh` is green** — not before.

**What comes in from the Firn library.** Only `std`, and only in one
place: `kernel/kcore.fi` writes `import std.core` — the half of the
library that needs neither an allocator nor a system call (round 73,
`docs/ROUND73.md`). Everything else in the kernel is in this repository.
The way there is the search path that both compilers walk last,
`<directory of the compiler binary>/../lib` — which is why
`vendor/firn/bin/` and `vendor/firn/lib/` sit next to each other.
`$FIRNLIB` points at `lib/` of this repository and is thereby free for
its own libc (`import libc.io`).

Both compiler stages are measured: every test runner builds the kernel
with firnc0 **and** with firnc1 and compares the outputs.

---

## Relationship to Firn and to OrientOS

**Firn** is the language and its compiler (`../firn`). Osum was split out
of the Firn repository — the commit history in this repository is the
real one, it begins long before the split. The kernel lived there as
`demos/kernel/`, the libc as `lib/osum/`. What stayed in the Firn
repository: the compiler, the standard library, the browser building
blocks (`lib/html`, `lib/css`, `lib/js`, `lib/dom`) and the TCP/IP stack
from round K3.

**OrientOS** is the operating system *around* a kernel — its own
repository, its own acceptance suite. It has a kernel of the same name,
but that one consists of more than 17,000 lines of Rust and is only now
being migrated to Firn. **The kernel in this repository is the more
developed one.** The split Justin decided on:

* **Osum** = the kernel. This repository.
* **OrientOS** = the system around it.

That both were called "osum" until now is historical and is being
resolved there, not here.

---

## Documentation

The round reports in `docs/` were taken over from the Firn repository
unchanged and therefore still name the old paths (`demos/kernel/`,
`lib/osum/`). They are a record, not a manual, and are not rewritten
after the fact.

| file | round |
|---|---|
| `docs/ROUND52.md` | `profile kernel` — compiling freestanding |
| `docs/ROUND59.md` | the kernel: IDT, exceptions, timer, memory, ring 3 |
| `docs/ROUND62.md` | tasks, address spaces, system calls, file system |
| `docs/ROUND73.md` | `std.core` — the library without an allocator |
| `docs/OSUM-K1.md` | the ELF loader, `exec`, `/bin/sh` off the disk |
| `docs/OSUM-K2.md` | PCI, APIC, NVMe over DMA |
| `docs/OSUM-K3.md` | the TCP/IP stack (code in the Firn repository) |
| `docs/ROUNDK4.md` | the POSIX layer and the libc |
| `docs/ROUNDK5.md` | four processors and the lock |
| `docs/ROUNDK6.md` | the userland: shell and tools |
| `docs/ROUNDK7.md` | the screen: framebuffer, text console, /dev/fb |
| `docs/ROUNDK7B.md` | why the letters vanished from the screen after the merge — and the map of `kdata` |
| `docs/ROUNDK8.md` | the network: virtio-net, the stack from K3, sockets |
| `docs/ROUNDK9.md` | signals, terminals, clock and randomness |
| `docs/ROUNDK10.md` | SMEP/SMAP and the boot module — the last two items of the kernel switch |
| `docs/ROUNDK11.md` | **you can work on it**: the editor, twenty tools, the shell as a language |
| `docs/ROUNDK10W.md` | the user interface: mouse, window server, TrueType with antialiasing |
| `docs/ROUNDK12.md` | a host for foreign processors: AMD-V, nested page tables, guests, guest machines from ring 3 |
| `docs/ROUNDK15.md` | **widgets, the file manager and search**: the library in ring 3, `/bin/explorer`, programs as bundles under `/apps/*.prog/`, a name index across the whole file system modelled on "Everything" — ten calls in the kernel |
| `docs/ROUNDK13.md` | **users, permissions and `init`**: uid/gid, chmod/chown, /etc/passwd and /etc/shadow, login, the first process |
| `docs/ROUNDK14.md` | **VFS and foreign file systems**: the table of nine operations, /proc, /dev, FAT32 against `mkfs.vfat`/`mcopy`/`fsck.fat`, MBR and GPT |
| `docs/ROUNDK16.md` | **the compiler runs on the system itself**: `firnc` and an assembler in Firn on Osum, the result character-identical with the one from the host — plus the table "file kind → what opens it" in the kernel and `#!` in `execve` |

`ENTFERNEN-AUS-FIRN.md` describes what has to be deleted in the Firn
repository so that nothing lies there twice. **That has not been carried
out.**

## License

MIT, see `LICENSE`.
