# USB mass storage, exFAT, automount, safe eject (R-012)

## State

| Part | Where | Status |
|---|---|---|
| xHCI / EHCI / OHCI host controllers | `kernel/drv/usb/` | present |
| Enumeration, hubs, up to 4 mass storage devices | `kernel/usb/usb.fi` | present (HOTPLUG-2) |
| Bulk-Only Transport class driver | `kernel/usb/usb.fi` (`bot`, `msc_*`) | CBW/CSW with tag check, STALL clearing, reset recovery on phase error |
| SCSI command set | `kernel/usb/scsi.fi` | INQUIRY, TEST UNIT READY, REQUEST SENSE, READ CAPACITY(10/16), READ/WRITE(10/16), SYNCHRONIZE CACHE, START STOP UNIT (builders only) |
| Capacity above 2 TiB | `usb.fi` `msc_start` | READ CAPACITY(16) when READ CAPACITY(10) says 0xFFFFFFFF; READ/WRITE(16) beyond LBA 2^32 |
| File systems on sticks | `kernel/fs/` | FAT32, exFAT (read + write), NTFS/ext4 read only through `mount` |
| File system detection | `kernel/block/fsdetect.fi` | boot sector content, not the partition type byte |
| Automount and eject | `kernel/block/wechsel.fi` | exFAT + FAT32 mounted under `/medien/usbN`, eject = unmount, SYNCHRONIZE CACHE, relock |
| Write lock | `kernel/block/wlock.fi` | a mounted removable stick is unlocked while mounted and locked again on eject/unplug |

## exFAT

`kernel/fs/exfat.fi`: boot sector checks, FAT chains and NoFatChain files, allocation bitmap, entry sets with set checksum,
directory growth, create/delete/rename/truncate, 64-bit sizes (files above 4 GiB, contiguous and FAT-chained).
`kernel/fs/exfat_name.fi`: UTF-8 to UTF-16 names for new files (BMP only), case-insensitive compare and name hash with a built-in
up-case function for ASCII, Latin-1, Latin Extended-A, Greek and Cyrillic.

Not done: sectors other than 512 bytes (4Kn sticks are refused with `usb: msc unusable`), TexFAT (two FATs), a fragmented
allocation bitmap, characters outside the BMP in new names, the on-disk up-case table (a built-in subset is used; names in
scripts outside the subset keep a hash the host may not accept), volume dirty flag, UAS (BOT only), multi-sector transfers
(one 512-byte command per sector).

## Gate

`/root/jarvis/bin/heavy bash tools/usbexfat/run.sh`

1. exFAT stick hot-plugged: host-written tree read with equal SHA-256, Osum writes (mkdir, create, 1 MB copy, in-fs copy,
   rename, delete, umlaut/Greek/Cyrillic names, case-insensitive lookup), eject, `fsck.exfat -n` clean, host re-reads the tree.
2. exFAT + FAT32 stick at once, no cross-talk.
3. exFAT without partition table; pull without eject; plug again.
4. 12 GiB sparse stick with two 4.6 GB files: markers beyond 4 GiB read, append grows both, `fsck.exfat` clean.
5. Fuzz: corrupted images (boot sector, entry sets, FAT, bitmap); no crash, no hang (`FUZZ_COUNT=n`).
