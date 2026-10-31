# Intel 8265 (iwlwifi-8265-36.ucode): command sequence Linux iwlmvm vs Osum

Source: /root/linux-v510 (mvm/fw.c iwl_mvm_up, scan.c iwl_mvm_legacy_config_scan, sta.c iwl_mvm_add_aux_sta). Firmware TLVs read from /root/fw-cache/iwlwifi-8265-36.ucode (release/core33::c8e8e144).

## Firmware facts
| item | value | consequence |
|---|---|---|
| CAPA 2 UMAC_SCAN | set | UMAC scan: SCAN_CFG_CMD 0x0C + SCAN_REQ_UMAC 0x0D |
| CAPA 12 DQA_SUPPORT | set | DQA_ENABLE (group 5 cmd 0x00, cmd_queue 0); aux queue 1, data queues >= 4 |
| CAPA 1 LAR_SUPPORT | set | MCC_UPDATE_CMD 0xC8 before scan config (if NVM LAR enabled) |
| API 30 STA_TYPE | set | ADD_STA is 48 octets (iwl_mvm_add_sta_cmd v10), station_type at offset 35 |
| API 32 ADAPTIVE_DWELL / API 42 / API 56 / API 58 | set / no / no / no | SCAN_REQ_UMAC v7, legacy SCAN_CFG v1 (not reduced), tail v1 |
| N_SCAN_CHANNELS | 52 | SCAN_CFG length = 36 + 52 |
| PHY_SKU | 0x330018 | valid tx/rx ant 3/3 |
| CMD_VERSIONS TLV | ADD_STA v10, SCAN_CFG v2, SCAN_REQ v7 (group 0 = LONG group set) | ADD_STA < 12: aux station needed |

## RT sequence after REGULAR alive
| # | Linux iwl_mvm_up | id / group | Osum (before) | Osum (branch staff/orientos-mvvmracy) |
|---|---|---|---|---|
| 1 | FW_PAGING_BLOCK | 0x4F/0 | sent | sent |
| 2 | SHARED_MEM_CFG (get) | 0x25/0 | missing | missing |
| 3 | SF_CFG | 0xD1/0 | sent | sent |
| 4 | TX_ANT_CONFIG | 0x98/0 | sent | sent |
| 5 | PHY_DB x n, PHY_CONFIGURATION | 0x6C, 0x6A | sent | sent |
| 6 | BT_CONFIG | 0x9B/0 | sent | sent |
| 7 | DQA_ENABLE | 0x00/5 | missing | sent (before aux station) |
| 8 | SCD_QUEUE_CFG aux queue 1, fifo MCAST 5, tid 8, window 64 | 0x1D/0 | missing | sent (when DQA known) |
| 9 | ADD_STA aux: mac_id 4, tid_disable 0xFFFF, type AUX 4, queue msk 0x2, 48 octets | 0x18/0 | missing | sent |
| 10 | PHY_CONTEXT add x NUM_PHY_CTX | 0x08/0 | 1 sent | 1 sent |
| 11 | THERMAL backoff 0 | 0x7E/0 | missing | missing |
| 12 | POWER_TABLE | 0x77/0 | missing | missing |
| 13 | MCC_UPDATE "ZZ" | 0xC8/0 | missing | missing |
| 14 | SCAN_CFG v1, wide header group 1, 88 octets | 0x0C/1 | short header group 0 (silent fw = HP err -70) | wide header |
| - | MAC_CONTEXT, BINDING (at add_interface, not in up) | 0x28, 0x2B | sent before SCAN_CFG | same |

## SCAN_CFG payload v1
| field | Linux | Osum before | Osum branch |
|---|---|---|---|
| flags | ACTIVATE, ALLOW_CHUB, TX/RX chains, SET_AUX_STA_ID, ALL_TIMES, LEGACY_RATES, MAC, CHANNEL_FLAGS, CLEAR_FRAGMENTED, N_CHANNELS<<26 | no ALLOW_CHUB, no AUX_STA_ID, no CLEAR_FRAGMENTED | as Linux (0x2EF09 + n<<26) |
| legacy_rates | 0x0FFF0FFF | 0xFF0F (wrong bits) | 0x0FFF0FFF |
| dwell act/pas/frag/ext | 10/110/44/90 | 30/110/44/0 | 10/110/44/90 |
| bcast_sta_id | aux sta id | 1, no station | 1 = aux station |
| channel_flags | 0xF (EBS, accurate EBS, EBS add, passive2active) | 1 | 0xF |

## CSR rfkill
- CSR_GP_CNTRL bit 27 (0x08000000) HW_RF_KILL_SW: 1 = radio on. Linux iwl_trans_pcie_check_hw_rf_kill: hw_rfkill = !(GP_CNTRL & bit). lib/wlan/iwl_rfkill.fi hw_set(gp) = bit clear: same polarity. "rfkill hw=off" = radio NOT blocked; not the cause.
