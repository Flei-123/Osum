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
