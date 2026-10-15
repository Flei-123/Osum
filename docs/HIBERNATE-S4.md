# Hibernate (S4) -- concept and feasibility (15.10.2026, W-LAPTOP)

Facts are marked **[tree]** (read from the sources today), **[measured]** (gate run today) or
**[plan]** (design, nothing built). Real-hardware behaviour is **[unverified]**.

## 1. State

- **[tree]** `powerd` knows the action `hibernate` (lid / settings, `lib/power/policy.fi` ACT_HIBERNATE) and
  falls back to sleep: `powerd: hibernate unavailable, sleeping instead`.
- **[tree]** S3 exists incl. SMP parking and device resume hooks (`kernel/pwr/s3.fi`, `s3dev.fi`: NVMe, AHCI, xHCI,
  e1000, HDA re-initialise from scratch). `\_S5` (power off) exists (`kernel/pwr/power.fi`). No swap, no image writer.
- **[measured]** `tools/hibimg/run.sh`: image format (header, extents, CRC32) 18/0 on the host.

## 2. Design [plan]: hibernate = "S3 whose RAM lives on disk"

OS-managed hibernate: no firmware S4 (`_S4` / S4BIOS not needed). Write the image, then power off with `\_S5`.

1. **Freeze**: same path as S3 (park cores, quiesce devices, no new tasks). Reuse `s3.suspend` up to the point where it
   would write SLP_TYP.
2. **Snapshot**: write every used page frame (allocator bitmap -> extents, `lib/power/hibimg.fi`) plus the CPU/context
   block that the S3 wake block already saves, to a raw hibernate area on disk. The writer uses a polled driver path and
   a bounce buffer; pages the writer itself touches are written last / marked "restore last".
3. **Power off**: `\_S5`. Header sealed last (data CRC, header CRC); a half-written image has no valid header.
4. **Boot**: early in `kmain`, after the disk driver is up and BEFORE the heap is used: read header, `hdr_check` (magic,
   version, CRC, page size, **kernel build id**, extent sums). No image -> normal boot. Valid -> `hdr_invalidate` first
   (a crash while restoring must never loop), then copy pages back, then jump into the **S3 wake path**: CPU context
   restored, device resume hooks re-initialise NVMe/AHCI/xHCI/e1000/HDA (they already do that from scratch).
5. Clock: recompute from RTC + SNTP as after S3.

## 3. Hard parts / risks

| Point | Why it matters | Answer |
|---|---|---|
| Restore code overwritten by its own restore | classic S4 bug | restore from a stub in pages excluded from the image, copy those last |
| Secrets in RAM (CRYPTO-ERASE keys, session keys) | image on disk = keys on disk | **refuse hibernate unless the image is encrypted** (AES-GCM, `lib/crypto`); key from the user password at resume, never stored plain |
| Kernel changed (OTA) between hibernate and boot | memory layout differs | build id in header, mismatch -> discard image |
| Fragmented RAM | header holds 28 extents | writer refuses (`ext_add` false) -> chain extent blocks (v2) before real use |
| Disk space | RAM size (zero-run compression helps) | dedicated partition/file created by the installer; size = RAM; settings page shows "hibernate unavailable" if absent |
| GPU / framebuffer state | GOP is passive, fine; virtio-gpu needs re-attach | via the S3 resume hooks |
| Devices with internal state not covered by hooks | USB hubs, audio streams | same list as S3, `s3dev` gate pattern |

## 4. Effort and order

1. **Image format** -- done, host-tested (`lib/power/hibimg.fi`).
2. **Page allocator export** (used-frame bitmap -> extents) -- S.
3. **Raw hibernate area + polled writer/reader** (NVMe + AHCI) -- M. QEMU-testable with a second disk.
4. **Boot-time restore + jump into the S3 wake path** -- M-L. QEMU-testable (hibernate, `-no-reboot` quit, boot again on the
   same disk image, compare a RAM checksum and a running counter).
5. **Encrypted image + password prompt** -- M. Required before it is the default.
6. **Settings**: hibernate-after-standby (hybrid) timer, "hibernate unavailable" state. The schema already has `hibernate` as lid
   action; a new key means `keys=N` updates in `tools/actionbus/run.sh` + `image.sh`.

Real-hardware test is the Boss's job after step 4: hibernate a laptop with SMP and NVMe, resume, check keyboard, touchpad,
network and clock.
