# PLAN-8000-LOADER (HP-9) -- Intel family 8000 (8260/8265) firmware loader

Status 21.10.2026: plan only. Boot code (`iwlboot`) prints `iwl: boot unsupported (family 8000 loader: HP-9)` and writes nothing.
Facts below are from the Linux iwlwifi source (read as specification, raw.githubusercontent.com/torvalds/linux/master, 21.10.2026). OrientOS code is an own implementation; nothing is copied.

## 1. Device IDs and firmware names (verified)
- Source `pcie/drv.c` (`iwl_hw_card_ids`, `iwl_dev_info_table`): 8260 = PCI 8086:24F3 and 24F4; 4165 = 24F5, 24F6 (use the 8260 cfg); 8265 = 24FD (subdevices 3E01/3E02/1012/0012 are the 8275 name, 1431/1432 Killer 1435i/1434). 24FB is a 3168 (family 7000), NOT 8000.
- Source `cfg/8000.c`: firmware API range 22..36 for both; names `iwlwifi-8000C-<api>.ucode` (8260) and `iwlwifi-8265-<api>.ucode` (8265); newest 36. Driver tries 36 downwards to 22. NVM version 0x0a1d, `nvm_type = EXT`, `nvm_hw_section_num = 10`.
- To do in `lib/wlan/iwl_probe.fi`: add 0x24F5/0x24F6 (4165) as FAM_8000 / 8260 file set. (24fd/24f3/24f4 already there.)

## 2. Loading sequence of family 8000 (verified from `pcie/gen1_2/trans.c`)
No context-info block (that is 9000+/AX). Secure boot with sections:
1. `start_fw` dispatches `iwl_pcie_load_given_ucode_8000` for family >= 8000 (after clearing the RF-kill handshake bits in CSR_UCODE_DRV_GP1_CLR).
2. `WFPM_GP2 (prph 0xA030B4) <- 0x01010101`; `RELEASE_CPU_RESET (prph 0x300C) <- BIT(24)`.
3. CPU1 sections, then CPU2 sections, are copied by `load_section`: chunk = min(FH_MEM_TB_MAX_LENGTH 0x20000, section len); destination in the extended SRAM range toggles `LMPM_CHICK (prph 0xA01FF8)` bit 0 around the chunk; each chunk goes through the service DMA channel (FH_SRVC_CHNL = 9) and the driver waits up to 5 s for the end-of-TFD interrupt.
4. After each section a bit is set in the load-status register (`FH_UCODE_LOAD_STATUS`; CPU2 uses shift 16); after the last one of a CPU a final value is written and interrupts are enabled; the ROM then continues and the firmware sends ALIVE.
- FH register offsets verified (`iwl-fh.h`): FH_MEM_LOWER_BOUND 0x1000; FH_TFDIB_CTRL0/1(ch) = 0x1900 + 8*ch (+4); FH_SRVC_LOWER_BOUND = 0x1000 + 0x9C8, `FH_SRVC_CHNL_SRAM_ADDR_REG(ch) = lower + (ch-9)*4`; FH_TCSR_CHNL_TX_CONFIG_REG(ch) = FH_TCSR_LOWER_BOUND + 0x20*ch; DMA_CHNL_ENABLE 0x80000000, CREDIT_DISABLE 0, CIRQ_HOST_ENDTFD 0x00100000, CIRQ_RTC_NOINT 0; FH_TSSR_TX_STATUS_REG = 0x1000 + 0xEA0 + 0x10; FH_TX_CHICKEN_BITS_REG = 0x1000 + 0xE98.
- NOT verified yet (read before coding, do not guess): numeric address of FH_UCODE_LOAD_STATUS, FH_TCSR_LOWER_BOUND, exact bit formula per section, the order of the register writes inside `load_firmware_chunk`, section separator handling (CPU1/CPU2 split markers in the TLV image), `LMPM_SECURE_UCODE_LOAD_CPU1_HDR_ADDR` (0x1E78) use for 8000 (the old path only).

## 3. Steps
- HP-9a: host model `lib/wlan/iwl_fh8000.fi`: section list -> chunk plan (count, length, destination, extended-range flag), load-status bit accumulation, register-write script per chunk; oracle + Python reference + control runs (like tools/wlan/iwl.sh). Needs the unverified items of section 2 first.
- HP-9b: kernel `iwl.fi`: execute the script with a fake CSR file in QEMU (CSR simulation of `tools/wlan/iwlpwr.fi`) -- end-of-TFD interrupt, timeout 5 s, error lines.
- HP-9c: real HP laptop only: ALIVE wait, NVM section 10 read, then commands (LW-4 style).
- Firmware blobs are never checked in (pin SHA-256 only). File lookup by PCI ID is already in `iwl_fwsel.dev_path`.
