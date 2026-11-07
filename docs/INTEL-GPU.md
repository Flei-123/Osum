# INTEL-GPU — Intel display bring-up on the HP (07.11.2026, W-INTEL-GPU phase 1)

Status: **identification + read-only evidence done on the real HP. No driver code yet** (phase 1b). All values below were read from the HP with the existing tools `/bin/lspci -v`, `/bin/pcicfg`, `/bin/regdump` (SYS_OSUM_DBG, read ops only, no `--write`). Offsets are from memory of the public i915/PRM register layout and were **checked against these real values** (decode plausible = offset confirmed).

## 1. Identification (HP-ORIENTOS, subsystem 103c:827d)

| Item | Value | Meaning |
|---|---|---|
| GPU | `00:02.0 8086:5916` rev `0x02`, class 0x030000 | Intel HD Graphics 620, Kaby Lake GT2 (U), **Gen9.5, display ver 9** |
| Host bridge | `00:00.0 8086:5904` | KBL-U host bridge (BDSM mirror at 0xb0 = 0xb4800001) |
| PCH | LPC `00:1f.0 8086:9d4e` | Sunrise Point-LP family (SPT-LP): PCH panel power + PCH backlight regs apply |
| Thunderbolt | `8086:15da` x4, xHCI `8086:15db` | Alpine Ridge: external DP/HDMI go through DDI B/C (not measured) |
| BAR0 | `0x1ff2000000`, 16 MiB, 64-bit | registers 0..8 MiB, GGTT 8..16 MiB |
| BAR2 | `0x1fc0000000`, 256 MiB, prefetch | aperture |
| BAR4 | I/O `0x3000`, 0x40 | legacy VGA index/data |
| cfg 0x50 (GMCH_CTRL) | `0x01c1` | GMS=1 → 32 MiB stolen, GGMS=3 → 8 MiB GTT |
| cfg 0x5c (BSM) | `0xb4800001` | stolen memory base `0xb4800000` (locked) |
| cfg 0xfc (ASLS) | `0xb1f68018` | OpRegion (VBT: panel timings, DDC pins, backlight type) — not read yet |
| caps | vendor 0x40, PCIe 0x70, MSI 0xac, PM 0xd0 | cmd = 0x0007 (MEM+IO+BM on, GOP running) |

`/proc/drivers` shows `unclaimed pci 00:02.0 8086:5916 class=0300`; the existing rows `vmsvga` / `virtio-gpu` use `drvclass.CLS_DISPLAY` (no `gpu` class exists; reuse CLS_DISPLAY).

## 2. Real register values (firmware/GOP state, read-only)

| Register | Offset | Value | Decode |
|---|---|---|---|
| PIPESRC_A | 0x6001c | 0x077f0437 | 1920x1080 |
| TRANS_HTOTAL/HBLANK_EDP | 0x6f000/04 | 0x0837077f | active 1920, total 2104 |
| TRANS_HSYNC_EDP | 0x6f008 | 0x079f078f | sync 1936..1952 (16), back porch 152 |
| TRANS_VTOTAL/VBLANK_EDP | 0x6f00c/10 | 0x045b0437 | active 1080, total 1116 |
| TRANS_VSYNC_EDP | 0x6f014 | 0x0448043a | sync 1083..1097 (14), back porch 19 |
| TRANSCONF_EDP | 0x7f008 | 0xc0000000 | enabled + state, progressive. PIPECONF_A/B (0x70008/0x71008) = 0: **eDP transcoder carries pipe A** |
| TRANS_DDI_FUNC_CTL_EDP | 0x6f400 | 0x82200002 | enable, DP SST, 6 bpc, input pipe A, 2 lanes, hsync/vsync negative. Transcoder A (0x60400) = 0x30000, off |
| PIPE_DATA_M1/N1_EDP | 0x6f030/34 | 0x7e4b3333 / 0x00800000 | TU 64, M/N = 0.5875 |
| PIPE_LINK_M1/N1_EDP | 0x6f040/44 | 0x00042d82 / 0x00080000 | 0.5222 = pclk/270 MHz |
| **Native mode** | derived | | **1920x1080, pixel clock 141.000 MHz (0.5875 x 240), 2104x1116 total = 60.05 Hz, 6 bpc, eDP 2 lanes HBR 2.7 Gb/s** |
| DDI_BUF_CTL_A | 0x64000 | 0x80000003 | enable, 2 lanes, init-display-detected |
| DP_TP_CTL_A / STATUS | 0x64040/44 | 0x80040300 / 0 | enable, SST, enhanced framing, link trained (normal) |
| DP_AUX_CH_CTL_A | 0x64010 | 0x0410023f | idle, last msg 1 byte, 600 us timeout |
| DPLL_CTRL1/2/STATUS | 0x6c058/5c/60 | 3 / 0x00a00001 / 0x11 | DPLL0 override, link-rate field 1 (2.7 Gb/s), DDI A on DPLL0 |
| LCPLL1_CTL | 0x46010 | 0xc0000000 | enabled + locked |
| CDCLK_CTL | 0x46000 | 0x0c000544 | **675 MHz** (sel 3, decimal 0x544) |
| DSSM / DFSM | 0x51004 / 0x51000 | 1 / 0x20400042 | ref clock field 0 (24 MHz), cdclk limit 675 |
| FUSE_STATUS | 0x42000 | 0x8e000000 | download done, PG0/1/2 distributed |
| PLANE_CTL_1_A | 0x70180 | 0x84000000 | enabled, XRGB8888, linear |
| PLANE_STRIDE/SIZE/SURF_1_A | 0x70188/90/9c | 0x78 / 0x0437077f / 0 | 120 x 64 = 7680 B/line, 1920x1080, **framebuffer at GGTT offset 0** |
| PP_STATUS/CONTROL | 0xc7200/04 | 0x80000008 / 0x7 | panel on, sequencer idle; power on + reset + backlight enable |
| PP_ON/OFF_DELAYS/DIVISOR | 0xc7208/0c/10 | 0 / 0x01f40000 / 0x0004af06 | off delay 0x1f4 (50 ms) |
| BLC_PWM_PCH_CTL1/CTL2 | 0xc8250/54 | 0x80000000 / 0x1d4c1d4c | PCH PWM enabled, period 7500, duty 7500 (100 %) |
| BLC_PWM_CPU_CTL2/CTL | 0x48250/54 | 0x80000000 / 0 | CPU PWM enable bit set, duty 0 |
| PWR_WELL_CTL1..4 | 0x45400.. | 0xf000000f 0x50000005 0x40000000 0x50000005 | wells on |
| DC_STATE_EN | 0x45504 | 0 | no DC states (no DMC firmware) |
| GMBUS2 | 0xc5108 | 0x800 | HW_RDY, idle |

Generation check: DDI A + eDP transcoder, DPLL0/CDCLK on LCPLL1, PCH PPS/backlight, universal plane regs 0x70180 — all Gen9 (SKL/KBL) layout. **Not** BXT/GLK (PPS at 0xc7200 + backlight at 0xc8250 are the SPT-PCH variant).

## 3. Consequences

- The internal panel is **eDP**: EDID/DPCD must come over **DP AUX channel A** (0x64010 ctl, 0x64014.. data, I2C-over-AUX address 0x50). GMBUS (0xc5100.., pins 5/4/6 for DDI B/C/D) serves only HDMI/DVI/VGA ports. Both need register **writes** (AUX/GMBUS only, not scanout) — kept out of the read-only phase.
- The firmware mode is already known without EDID: read it back from the eDP transcoder (table above). A same-mode modeset needs only that readback + DPLL0/CDCLK/PPS/backlight values, no EDID.
- DMC firmware is absent (DC_STATE_EN=0): do not enable DC states; modeset must keep CDCLK 675 MHz and DPLL0 as the firmware left them.

## 4. Build plan (phase 1b, not started)

1. `lib/gpu/intel/` (host-testable, `--profile=kernel` clean, register access through `fn(u64) -> u64` / `fn(u64, u64)` accessors like `lib/ntfsshrink/shrink.fi`): `ids.fi` (5916 → gen9.5 table), `regs.fi` (offsets above), `timing.fi` (decode HTOTAL..VSYNC, M/N → pclk), `dump.fi` (text report), `aux.fi` (AUX transaction + I2C-over-AUX EDID), `gmbus.fi`, `edid.fi` (block + checksum + preferred DTD), `hpd.fi` (SDEISR 0xc4000 / DE_PORT_ISR 0x44440 decode).
2. `kernel/drv/gpu/intel/{probe,mmio,proc}.fi`: map BAR0 with `apic.map_range` (as `pcidbg.mmio_window`), row `intel-gpu pci 8086:*/0300` in `kernel/bus/drvreg.fi` with `CLS_DISPLAY`, boot word `intelgpu` (M_* in kstate + bootwords_store.fi, default OFF), `/proc/intelgpu` text. Word `intelgpuedid` adds AUX/GMBUS transactions. Word `intelgpumode` (phase 2) adds modeset.
3. Host model `tools/intelgpu/run.sh` + `oracle.fi`: register-file model with GMBUS/AUX state machines, **the real HP values from section 2 as decode fixtures**, mutation counter-proofs like `tools/usbnet/run.sh`; summary line `INTELGPU: N passed, M failed`, rows in `tools/qa/gates.tsv` and `summary-required.txt`.
4. Gates before landing: drvstore, classes, k15, smp, bootwords, english.
5. Phase 2 modeset: only same native mode (section 2), sequence PPS off/on, pipe/plane/transcoder/DDI, backlight; watchdog: confirm key within N s else revert to GOP (reboot-to-GOP). Needs HP image with the word and Boss at the machine.

## 5. Phase 1b research notes (07.11.2026, still no driver code)

Sources: Linux 6.12.101 (`include/drm/intel/i915_pciids.h`, `display/intel_dp_aux.c`, `intel_dp_aux_regs.h`, `intel_gmbus_regs.h`) under /root/lkpi-src/tree612.

- **PCI ids Gen9 (exact, from i915_pciids.h).** SKL (gen 9, 25): 1902 1906 190A 190B 190E 1912 1913 1915 1916 1917 191A 191B 191D 191E 1921 1923 1926 1927 192A 192B 192D 1932 193A 193B 193D. KBL (gen 9.5, 22): 5902 5906 5908 590A 590B 590E 5912 5913 5915 5916 5917 591A 591B 591C 591D 591E 5921 5923 5926 5927 593B 87C0. Compact encoding: one u64 bit mask per high byte (0x19, 0x59, bit = low byte, max 0x3D) plus explicit 87C0.
- **AUX channel A send word** (matches the HP idle value 0x0410023f in its low 10 bits): `BUSY<<31 | DONE<<30 | INT<<29 | TIMEOUT_ERR<<28 | TIMEOUT_MAX(3)<<26 | RECV_ERR<<25 | size<<20 | ((18-1)<<5 = 0x220) | (32-1 = 0x1f)`. Data regs 0x64014 + 4*i (5 regs), bytes packed big endian (first byte in the MSB). Header 4 bytes: `req<<4 | addr[19:16]`, `addr[15:8]`, `addr[7:0]`, `len-1`. Requests: I2C write 0, I2C read 1, MOT 4, native write 8, native read 9; payload max 16.
- **AUX flow**: wait !BUSY (3 x 1 ms) -> up to 5 sends: load data, write ctl, wait !BUSY (10 ms), write `status|DONE|TIMEOUT|RECV_ERR` (write-1-to-clear); TIMEOUT -> retry; RECV_ERR -> 400 us pause + retry; DONE -> ok. Reply size = status[24:20], must be 1..20. Reply byte 0 >> 4: native ACK 0 / NACK 1 / DEFER 2; I2C ACK 0 / NACK 4 / DEFER 8.
- **EDID over AUX** (addr 0x50): I2C write offset byte with MOT, then 16-byte I2C reads with MOT, the last one without MOT. DPCD: native read at 0x000 (rev, max rate 0x0A = HBR, lanes & 0x1f) and 0x100/0x101 (current rate, lanes).
- **GMBUS** (external ports only): GMBUS0 0xc5100 pin|100 kHz; GMBUS1 0xc5104 `SW_RDY<<30 | CYCLE_WAIT<<25 | CYCLE_INDEX(2)<<25 | STOP(4)<<25 | count<<16 | index<<8 | addr<<1 | READ`; GMBUS2 0xc5108 HW_RDY bit 11, SATOER (NAK) bit 10, ACTIVE bit 9; GMBUS3 0xc510c data (LE, 4 bytes per read); GMBUS5 0xc5120; pins DPC 4, DPB 5, DPD 6. End: STOP, wait !ACTIVE, GMBUS0 = 0; on NAK reset via GMBUS1.
- **Pixel clock**: `pclk_kHz = round(link_M * link_symbol_kHz / link_N)` with link_symbol 270000 for HBR (DPLL_CTRL1 rate field 1); HP: 273794 * 270000 / 524288 = 141000. Refresh = pclk / (htotal * vtotal).
- **Kernel hook points**: `kernel/bus/drvreg.fi` rows (MAXR 40, 28 used): add `D_INTEL_GPU = 28`, `reg(name, 1, 0x8086, 0, 0x300, 0x1FF, 0)` + `set_class(CLS_DISPLAY)`. Boot words: `kstate.fi` mode bits 1292..1343 are free (MODE_WORDS 21), add `M_*` + export, `kernel/init/bootwords_store.fi` with `cmdword.find` (whole word: `intelgpu` and `intelgpuedid` are independent, tools/bootwords checks this, so bind when either is set). `/proc/intelgpu`: `kernel/fs/procfs/pfnode.fi`, four places per node (G_ id, render dispatch, name to id, listing) exactly like `vmxcaps`. BAR0: `apic.map_range(state, phys, size)`. Delay: per-driver `udelay(state, us)` (ahci.fi, hda.fi), no shared helper yet.
- **Oracle plan** (`tools/intelgpu`): register file with write-1-to-clear AUX status, sink model (DPCD + EDID fixture synthesized from the HP mode: 1920x1080, pclk 14100 x 10 kHz, h 16/16/152, v 3/14/19), assertions: decode equals section 2, snapshot performs 0 register writes, 400 us pause on receive error, EDID checksum rejects a flipped byte; mutation controls on pack order, `+1` field decode, M/N formula, id masks, checksum, timeout handling.

## 6. Phase 1c: measured on the real HP (07.11.2026, HP-ORIENTOS, build ee4223ec)

- MMIO works: the earlier all-zero `regdump 00:02.0 0 0 40` is only the reserved start of BAR0. `0x45400` PWR_WELL_CTL1 = `0xf000000f`, `0x45404` = `0x50000005`, so the AUX power well is on. BAR0 is 16 MB: 0..8 MB registers, 8..16 MB GGTT PTEs.
- No kernel with the `intelgpu` word is on the HP (old build, no `/proc/intelgpu`). Evidence was taken with `/bin/regdump --write` (one write per call, no `;` chains, scripts via `/bin/sh /tmp/x.sh` with literal command lines, `$VAR` words are not split).
- **DPCD over AUX** (`0x64014 <- 0x9000000f`, ctl `0xfe40023f`, reply ctl `0x6d10023f` = 17 bytes): `11 0a 82 41 00 00 01 c0 02 00 00 00 0f 0b 00 00` = DPCD 1.1, max rate 0x0a (HBR 2.7 G), 2 lanes + enhanced framing.
- **EDID over I2C-over-AUX** (offset write with MOT `0x40005000`, 16-byte reads `0x5000500f`, eight reads, final stop read): 128 bytes, header + checksum OK, manufacturer AUO, product 0x422d, base size 290x170 mm, DTD 293x165 mm, DTD = 1920x1080, 141000 kHz, 2104x1116, sync 16/16 and 3/14. Identical to the firmware register readback. Bytes are the fixture in `tools/intelgpu/oracle.fi` (`HP_EDID_HEX`).
- The AUX send word `0xfe40023f` pattern (low bits 0x23f) from section 5 works unchanged on silicon: first try, no retry, no defer.
- **Plane flip** (write `PLANE_SURF_1_A` 0x7019c): `0 -> 0x1000` latched in `PLANE_SURFLIVE_1_A` 0x701ac (`0x20 -> 0x1020`) within one frame; written back to `0`, live back to `0x20`. GGTT PTE 0 = `0xb4800001`, PTEs contiguous from phys `0xb4800000` (the 8.3 MB UEFI framebuffer). Scanout address control via GGTT works; a second buffer needs its own PTEs.
- Library: `lib/gpu/intel/flip.fi` (`flip`, `flip_checked` with rollback to a fallback surface, 4 KiB alignment, SURFLIVE poll with budget). Gate `intelgpu` models the latch and has counter-proofs.
- Next: kernel word that calls `flip_checked` for double buffering (needs GGTT PTE writer for a second buffer), then same-mode modeset with a confirm watchdog (Phase 2).

## 7. Phase 2: GGTT writer, double buffer, same-mode apply with watchdog (07.11.2026)

- `lib/gpu/intel/ggtt.fi`: PTE = phys | 1 (HP value `0xb4800001`), PTE of GGTT offset `o` at BAR0 `0x800000 + (o >> 12) * 8`, `map_linear` writes then reads every PTE back (`G_VERIFY` on a dropped write), refuses unaligned, over 4096 pages, past 4 GiB or past 39 bits without a write.
- `lib/gpu/intel/dbuf.fi`: `setup` refuses unless the claimed front (kernel framebuffer phys) really is what the plane scans out (PTE readback, `D_NOT_FRONT`, no write), then maps the back buffer; `present` = `flip_checked` to the hidden surface with the shown one as fallback, swaps roles only on success; `restore_front`.
- `lib/gpu/intel/confirm.fi`: confirm watchdog (idle/armed/confirmed/reverted), `tick` calls the revert callback exactly once after the deadline.
- `lib/gpu/intel/modeset.fi`: same-mode apply. Only the four eDP transcoder timing registers (HTOTAL, HSYNC, VTOTAL, VSYNC) are re-encoded from the mode and written, after the readback has proven that the encoding equals the running values (`M_MISMATCH` otherwise, zero writes); verify, restore on mismatch. No pipe/DDI/PPS off-on sequence yet.
- Kernel: boot words `intelgpuflip` (back buffer = `frame_run`, copy of the front + marker bar, one checked flip to it, hold 400 ms, flip back) and `intelgpumode` (apply_same + 5 s watchdog + stability check, revert + front restore on failure). Write policy in `kernel/drv/gpu/intel/mmio.fi`: only AUX, PLANE_SURF (flip word), the four timing registers (mode word) and the PTE range of the back buffer; everything else counts in `denied=`. `/proc/intelgpu` shows `flip_*`, `mode_*`, `ptes=`.
- Not wired: the desktop does not draw into the back buffer yet (`fb.flip_setup` is Bochs-VBE only); `igflip.present`/`back_addr` are the hooks.
- HP evidence (07.11., regdump): firmware already maps GGTT beyond the framebuffer (PTE idx 4096 at `0x808000` = `0xb5800001`, contiguous from `0xb4800000`); a PTE write at that offset (`0xb4801001`) read back correctly and was restored to `0xb5800001`. Boot words cannot be set over OTA on the HP, so the kernel path is not run at the HP yet.

## 8. Desktop back buffer (07.11.2026)

- Boot word `intelgpuback` (default off, needs `intelgpu` hardware path: GGTT + front verified by `dbuf.setup`). `igflip.stage` also runs for this word (no marker bar, no self-test unless `intelgpuflip` is set).
- `fb` got a generic hook (`fbdraw.ext_attach(state, hook)`, cell `S_EXT` 0xFF0): `draw_base`, `shown_base` (used by `front_paar`/`front_pixel`) and `flip` call `hook(state, EXT_DRAW|EXT_SHOWN|EXT_PRESENT)`. VBE flipping is unchanged; `kgstage` tries the hook only when `fb.flip_setup` failed.
- `kernel/drv/gpu/intel/igback.fi`: hook = back/front addresses from `gpu.intel.backbuf` state; present = `arch.cache_writeback` + `dbuf.present` (`flip_checked`, rollback to the shown surface).
- `lib/gpu/intel/backbuf.fi`: `commit` returns PRESENTED / RETRY (rolled back, shown unchanged, max 2 retries) / OFF_COPY (3rd miss: restore front, copy the drawn back buffer into the front, `fb.ext_detach`) / OFF / STUCK (restore failed: draw into the shown surface). The WM does a full-frame flush before each flip, so the stale hidden buffer is never reused partially.
- `/proc/intelgpu`: `back_mode=`, `back_presented=`, `back_last=`, `back_offs=`.
- Open: `wbinvd` per present is costly on real HW (needs a WC mapping of the back buffer or ranged clflush); direct writers to `fb.addr` (panic screen, `write_bytes`) bypass the back buffer; not run on the HP.
