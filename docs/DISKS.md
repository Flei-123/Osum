# DISKS.md -- the disk manager: one library, one service, one program

Decision of 07.10.2026 (Justin's proposal, checked against the code). The file manager gets only a
READ view of drives; everything that changes a partition table or a file system lives in a program of its
own, `disks`, on top of a headless library that the command line and Jarvis use the same way.

## 1. The three layers

| layer | what | where | who calls it |
|---|---|---|---|
| **`lib/disks`** (headless) | read disks and partitions (MBR, GPT, protective MBR), compute a PLAN for create / delete / grow / shrink / move / format / label, run a plan step by step, verify | `lib/disks/*.fi` (profile app, no GUI) | `/bin/disks`, the action bus, the installer later |
| **`/bin/diskctl`** (CLI + bus provider) | `diskctl list`, `diskctl plan <op> ...` (prints the plan, changes nothing), `diskctl apply <plan>` (asks, journals, runs), a manifest for the action bus (`docs/ACTION-BUS.md`) so Jarvis can read everything and change only through the trusted dialog | `kernel/user/diskctl.fi` | the shell, Jarvis, `/bin/disks` |
| **`/bin/disks`** (fUi window) | the Disk Management window: tree (disks -> partitions) at the left, detail list, an occupancy map (bar per disk), command bar with icons (`lib/fui/cmdbar.fi`), context menus, wizards with a plan preview and a double confirmation | `kernel/user/disks.fi` | the person |
| **explorer** | NOT a partition editor. "This computer" view with drives and occupancy bars, right click on a drive: Properties, Format (with a warning), Eject, "Open disk management" (starts `/bin/disks <device>`) | `kernel/user/explorer.fi` | the person |

WHY NOT IN THE FILE MANAGER. A file manager has the rights of the person and the life of a window the
person opens fifty times a day; a partition editor needs root, can destroy every file at once, and must
never run by accident with a drag. Different rights (the program asks the broker for them), a different
life cycle (one operation at a time, a log that survives a crash), a different test discipline (loop
images in the VM only). The explorer shows and opens; it never writes a table.

WHY A HEADLESS LIBRARY FIRST. Everything dangerous is a PLAN: a list of steps with the sectors each one
reads and writes, printed before anything happens. The same plan is shown in the wizard, printed by
`diskctl plan`, checked by the tests (the plan of "grow partition 2 by 1 GiB" must touch exactly these
sectors) and approved by a person through the trusted dialog (AB-004) -- one code path, three ways to look.

## 2. What exists today (evidence)

* **Read:** `kernel/block/part.fi` scans MBR and GPT (both header CRCs are checked) for the kernel's own
  mounts; Ring 3 has no syscall for the table. Ring 3 CAN read the raw devices: `/dev/hda`, `/dev/hdb`,
  `/dev/nvme0`, `/dev/sda`, `/dev/ram0` are block files (`kernel/fs/devfs.fi`), and the mount table is
  readable through `SYS_MNTSTAT` (`ulib.MS_*`: path, device, first block, blocks, flags) and removable media
  through `SYS_WECHSEL` (`ulib.WX_*`). So a read-only Disks view needs no kernel change.
* **Write:** only the installer writes a GPT (`kernel/user/instkern.fi` `gpt_schreiben`), plus a FAT32 ESP
  (`fat32_create`) and the offline file-system growth `instkern.wachsen` (new block count in the OFS
  superblock, bitmap bits freed; only when the bitmap is already large enough). Dual boot adds a third
  partition and never shrinks one (`docs/RUNDE-DUALBOOT.md`).
* **Limits that bound the work** (`docs/OFS-LIMITS.md`): ATA driver LBA28 = 128 GiB per disk
  (`kernel/block/blk.fi`), OFS format 2 = about 2 MiB per volume, format 3 (`--v3`) = 128 GiB measured,
  journal fixed at 522 blocks. OFS has no online grow and no shrink; the kernel does not know the second
  disk's size (`docs/RUNDE-DUALBOOT.md` 4.1).

## 3. The order of the stages (Grow before Shrink, read before write, loop images before anything)

| stage | what | test |
|---|---|---|
| D-0 | `lib/disks` read side: MBR / GPT / protective MBR parsing in Ring 3 from the raw devices, joined with the mount table; `diskctl list` | VM with a GPT image, an MBR image, an empty disk, a corrupt header (CRC) -- exact output compared |
| D-1 | the window `disks` (read-only): tree, list, occupancy map; the explorer's "This computer" view with bars | picture checks (midline, no overlap), the numbers equal `diskctl list` |
| D-2 | plans without effect: `diskctl plan create|delete|grow|shrink|move|format|label` print the steps and the sectors; the window shows the same plan | golden plans for loop images; a plan that would overlap or exceed the disk is refused |
| D-3 | safe writes in the VM on loop images only: label, create a partition in free space, delete, GPT backup header at the disk's end; each step journaled (`/var/lib/disks/journal`) and replayed after a crash | kill the VM in the middle of every step, replay, table valid (CRCs), nothing else moved |
| D-4 | grow: partition first, then file system (OFS offline-then-online, FAT32, ext4 not touched) | grow while a writer runs; the written data is intact |
| D-5 | shrink: file system first (OFS block relocation, needs a free tail), then partition; move = copy with a journal | the same crash matrix; a full file system refuses |
| D-6 | bus manifest + trusted dialog; Jarvis can read all, change nothing without the person | `tools/actionbus` style run |
| D-7 | the Dell: never written by a worker (only read, only when the person asks) | -- |

## 4. Rules that do not move

1. **No write without a plan shown before and a journal written first.** The journal says which step
   comes next; after a crash `diskctl recover` finishes or undoes it. Every step is idempotent.
2. **Order:** growing = partition table, then file system; shrinking = file system, then partition table.
   A tool that does it the other way round loses data on a crash between the two steps.
3. **The partition table is written LAST and with both copies** (primary + backup GPT at the end of the
   disk, CRCs right). A table with a wrong CRC is not read by this kernel (`part.fi`), which is the
   safe failure.
4. **Nothing mounted is touched** except for an online grow of a volume that supports it; a mounted
   volume cannot be shrunk, moved, formatted or deleted (the tool says so, it does not try).
5. **Two confirmations** for anything that destroys data (delete, format, shrink): the plan preview, then
   the typed name of the volume. The second one is not a button.
6. **Tests run on loop images in the VM, never on a real disk.** The Dell is not written to by a worker.
7. **English in the code**, German only in the catalogs (standing rule, 07.10.2026).

## 5. The read view in the file manager (this round)

"This computer" lists the volumes (`exporte.carrier_*`: mount path, blocks, used) with a thin occupancy bar
under each name; the numbers are the mount table's, the same ones `df` prints. A right click on a volume
opens the context menu (Properties, Format -- with the warning --, Eject, Open disk management). Format
and "open disk management" start `/bin/disks`; until D-2 exists they show the plan text only.

## 6. Roadmap

OrientOS roadmap items r444..r447 (P-012a..d) hold the stages; this file is their design (SDD) -- the
status of each stage is kept there, not here.
