# LINUXKPI-80211: unmodified Linux Wi-Fi drivers on the own 802.11 stack (15.11.2026)

Roadmap r3731. Sibling of `LINUXKPI-PLAN.md` (same rules: Linux sources only via `compat/linuxkpi/fetch.sh` at build time, never in the repo, never patched, shipped only as a signed driver-store package, nothing in the standard image). Model: FreeBSD LinuxKPI-802.11 on net80211. **Linux mac80211/cfg80211 are not ported**; the shim implements the mac80211 *driver API* (`struct ieee80211_hw`, `ieee80211_ops`, rx/tx-status, scan, sta, keys) on top of `lib/wlan/*` + `kernel/net/wlan_*.fi`.

Status (24.11.2026, roadmap r91): W1-W3 green, W4 in progress (build probe + ratchet), W5 prepared, not run.
- W1 planner: `tools/lkpi80211/run.sh` 19/0 (also covers W2).
- W2 shim (hw/vif/sta/key objects, op dispatch from macplan, upcalls, skb pool) + host fake driver: same gate, 9 shim mutants red.
- W3 QEMU: `tools/lkpi80211/qemu.sh` 45/0 on main c7befade6 (fake radio module through the shim over `iwl_fakeap`: scan, auth, assoc, WPA2 M2/M4, DHCP, ICMP; counter-proofs wrong PSK, no-BSSID/no-STA mutants, tier=native, no package).
- W4: `tools/lkpi80211/w4.sh` (fetch iwlwifi tree + 3 Linux protocol headers by hash, wrong tree hash rejected, `compat/linuxkpi/treeprobe.sh` compiles the 67 Kbuild units of iwlwifi+iwlmvm against the shim, ratchet `compat/linuxkpi/units/iwlwifi.ratchet`, counter-proof: removing one shim header trips it). Baseline 24.11.: units 0/67, missing headers 65 -> 45 after the first base header batch.
- W5: `tools/lkpi80211/hpab/` (A/B script + switch table); switch = boot word `noiwl` + `tiers=native+compat` + installed `lkpi-iwlwifi`.

## 1. Measured surface (Linux 6.12.101, Debian `6.12.101+deb12-rt` .ko, tool `compat/linuxkpi/measure80211.py`)
Method: `nm -u` over all modules of one driver stack minus what the stack defines; split by provider: defined in `mac80211.ko`, defined in `cfg80211.ko`, rest = kernel base (grouped by the `EXPORT_SYMBOL` file in the pinned tarball). Compiler artifacts removed. Sources: `#include <...>` and `struct ieee80211_ops` initializers in the driver tree.

| stack (modules) | .ko KB | needed | mac80211 | cfg80211 | kernel base | ops implemented | src lines |
|---|---|---|---|---|---|---|---|
| iwlwifi (iwlwifi+iwlmvm, pcie inside) | 2833 | 363 | 78 | 27 | 258 | 80 | 102321 |
| rtw88 (core, pci, 8822c, 8822ce) | 1376 | 158 | 39 | 4 | 115 | 40 | 125109 |
| mt76 (mt76, connac, mt792x, mt7921 common+e) | 1142 | 251 | 49 | 6 | 196 | 52 | 36456 |
| rtw89 (core, pci, 8852c, 8852ce) | 3444 | 186 | 43 | 14 | 129 | 44 | 277495 |
| ath10k (ath, core, pci) | 1723 | 225 | 45 | 15 | 165 | 50 | 89284 |
| ath11k (ath, ath11k, pci) | 1677 | 257 | 41 | 16 | 200 | 45 | 84309 |

- Union over 6 stacks: **116** mac80211 names, **43** cfg80211 names; intersection only 13 / 1. iwlwifi∩rtw88∩mt76 = 19 mac80211 names; iwlwifi alone 39; rtw88+mt76 add 24 (txq scheduling `ieee80211_next_txq`/`txq_schedule_start`, `ieee80211_emulate_*chanctx`, frame templates `nullfunc/probereq/pspoll_get`, `ieee80211_queue_work`).
- ieee80211_ops: iwlwifi 80 callbacks, union iwlwifi+rtw88+mt76 = 97, common to all three = 28 (start/stop, add/remove_interface, config, bss_info_changed, sta_state, set_key, hw_scan, ampdu_action, tx, wake_tx_queue, conf_tx, flush, ...).
- Compare: Linux mac80211+cfg80211 themselves need **328** base symbols and export 2302 + 2062 names (that is the code we do not take).
- Headers: every stack needs only `net/mac80211.h`, `net/cfg80211.h`, `linux/ieee80211.h` (+ radiotap) from the Wi-Fi side; base headers iwlwifi 72, rtw88 21, mt76 49, rtw89 15, ath10k 77, ath11k 60.
- iwlwifi kernel base (258) by group: net core skb/netdev/napi 33, kernel misc 33, lib containers 28, memory 28, pci 23, timers 17, other drivers (thermal, led, hwmon) 16, workqueue 13, device model 10, locks 9, sched/wait 8, acpi/firmware/x86 4 each, irq 3; 19 macro/alias names. Overlap with the DRM shim base (memory, locks, pci, workqueue, firmware) is the reuse lever; new for Wi-Fi: **skb + NAPI** (alloc/put/pull/push/queue, `netif_napi_add_weight`, `napi_complete_done`, TSO helpers).
- iwlmvm mac80211 calls (upcalls the shim must implement, 78): rx `ieee80211_rx_napi/_irqsafe`; tx `ieee80211_tx_dequeue`, `ieee80211_tx_status_ext/_skb`, `ieee80211_free_txskb`, `stop/wake_queues`; scan `scan_completed`, `sched_scan_results/stopped`; link `beacon_loss`, `connection_loss`, `cqm_rssi_notify`, `chswitch_done`, `csa_finish`; sta `find_sta(_by_ifaddr)`, `iterate_*`, `sta_ps_transition`, `sta_set_buffered`; keys `iter_keys(_rcu)`, `get/set_key_rx_seq`, `gtk_rekey_add/notify`, `remove_key`, TKIP p1k/p2k; BA `start/stop_tx_ba_session`, `*_ba_cb_irqsafe`, `rx_ba_timer_expired`; rate control `ieee80211_rate_control_register` (iwlmvm brings its own RS); hw `alloc_hw_nm`, `register_hw`, `restart_hw`, `free_hw`. cfg80211 (27): channel/freq helpers, `cfg80211_chandef_create`, elem find, regulatory set, `wiphy_work_*`, `wiphy_delayed_work_*`, rfkill, pmsr (FTM; stub).

FreeBSD reference (freebsd-src main, read only): `linux_80211.c` 10309 lines (32 `lkpi_ic_*` net80211 callbacks, 57 `linuxkpi_*` upcalls, state table `lkpi_sta_*_to_*`), `linux_80211_macops.c` 1041 (44 `lkpi_80211_mo_*` op wrappers), `linux_80211.h` 545, headers `net/mac80211.h` 2684 + `net/cfg80211.h` 2384 + `linux/ieee80211.h` 1412 (41+39 inline helpers). 94 TODO/XXX in `linux_80211.c`. Their cut: net80211 keeps MLME/scan list/crypto policy; the shim translates the net80211 state machine into `sta_state` single steps + chanctx + `mgd_prepare_tx`, and rx/tx into skb. Same cut here, with `lib/wlan` in the net80211 role.

## 2. Cut
- **Own stack keeps (Firn):** scan result list + choice (`connect.fi`, `beacon.fi`), auth/assoc frame building (`mgmt.fi`), state machine (`state.fi`, `join.fi`, `autojoin.fi`), WPA2 4-way + group rekey (`wpa.fi`, `groupkey.fi`), software CCMP (`ccmp.fi`) when the driver has no hw crypto, regulatory (`channel.fi`), caps parse (`caps.fi`), link stats (`link.fi`), netdev side (`kernel/net/wlan_net.fi`, `wlan_class.fi` = netclass ops).
- **Shim (Firn logic, C only for headers + glue behind `osum_if.h`):** `ieee80211_hw`/`vif`/`sta`/`key_conf`/`chanctx_conf` objects, op dispatch in the order of `lib/wlan/macplan.fi`, skb (own pool over frames), NAPI (poll from the net loop), txq per sta/tid, upcall table (rx, tx status, scan done, beacon loss, ...), rate-control registry (driver RS or own minimal), cfg80211 helpers (pure functions, reimplemented).
- **Seam:** `lib/wlan/device.fi` Board (send/receive/channel/key) is too thin for mac80211 drivers (firmware needs MAC context + station + chanctx). Extension: an optional lifecycle hook on Board fed by `macplan` events; native drivers (iwl_ops, ar9271) ignore it.

## 3. Mapping mac80211 call -> own stack
| mac80211 driver API | direction | own stack / shim |
|---|---|---|
| `ieee80211_alloc_hw_nm`, `register_hw` | drv->shim | create wlan device + netclass entry (`wlan_class.ops`), read `hw->wiphy` bands into `channel.fi` rule |
| `ops->start`, `add_interface` | shim->drv | `macplan` EV_UP (radio on, `wlan_rfkill` off) |
| `ops->hw_scan` / `ieee80211_scan_completed` | both | `connect.suchlauf_beginnen`; rx beacons/probe resp -> `beacon_aufnehmen`; EV_SCAN / EV_SCAN_DONE |
| `add_chanctx`, `assign_vif_chanctx`, `bss_info_changed(BSSID)` | shim->drv | `net_choose` result channel -> EV_JOIN_OPEN/RSN |
| `sta_state` NOTEXIST..AUTHORIZED | shim->drv | single steps only (`macplan.sta_up/sta_down`), from state.fi events Z_AUTH, Z_ASSOZ, Z_VERBUNDEN |
| `mgd_prepare_tx` / `mgd_complete_tx` | shim->drv | around auth + assoc frames from `mgmt.auth_build/assoc_build` |
| `ops->tx` + `wake_tx_queue` / `ieee80211_tx_dequeue` | shim->drv | data from `wlan_net.tx_frame_on`, 802.3->802.11 via `ethconv`/`llc`; mgmt raw via tx |
| `ieee80211_rx_napi` / `_irqsafe` | drv->shim | `device.receive` path -> `connect.data_receive`, EAPOL -> `wpa`, mgmt -> `beacon`/`state` |
| `ieee80211_tx_status_ext` | drv->shim | ack for mgmt frames (auth/assoc retry in `join.fi`), counters `wlan_count` |
| `ops->set_key` SET/DISABLE | shim->drv | `device.key_set` KEY_PTK/KEY_GTK; hw crypto -> `device.ccmp_capable_set(true)`, else `ccmp.protect` in software |
| `conf_tx`, `vif_cfg_changed(ASSOC)`, `bss_info_changed(QOS)` | shim->drv | WMM params from assoc response (default EDCA if none) |
| `ampdu_action` RX_START/TX_START | shim->drv | today `addba.build_decline`; later own BA session table |
| `beacon_loss`, `connection_loss`, `cqm_rssi_notify` | drv->shim | `autojoin.auto_link_lost`, reconnect |
| `ieee80211_rate_control_register` | drv->shim | rate-control registry; iwlmvm/rtw firmware RS used as is |
| `restart_hw` | drv->shim | replay `macplan` from EV_UP to the current phase |
| `wiphy_work_*`, `ieee80211_queue_work` | drv->shim | shim workqueue (shared with DRM shim) |
| `cfg80211_*`/freq helpers | drv->shim | pure reimplementation in the shim (no cfg80211 state) |

## 4. Gaps in the own stack
- **WPA3/SAE** (iwlmvm offloads nothing; SAE commit/confirm is host side): `beacon.fi` knows AKM_SAE, no SAE code. Needs SAE (hunting-and-pecking + H2E), PMF/BIP (`CH_BIP` parsed only), 802.11w.
- **11n/ac aggregation:** RX BA only declined (`addba.fi`); no reorder buffer, no TX A-MPDU sessions. iwlmvm does reorder in firmware on 9000+ (RSS), 8265 needs host reorder.
- **Rate control:** none own; fine for iwlmvm (own RS) and rtw88/mt76 (firmware RS); ath10k/11k firmware too. Minstrel-like only needed for pure softmac (ar9271 class).
- **Power save / U-APSD, TDLS, CSA, MLO links, AP mode, sched scan, WoWLAN, FTM:** not in stack; ops stay unimplemented (driver sees no flag in `hw->wiphy`).
- **skb/NAPI/txq:** no Linux-like skb in Osum; shim needs an skb pool with headroom/tailroom + frags.
- **Regulatory:** only ETSI rule (`channel.etsi_rule`); `regulatory_set_wiphy_regd` must feed it.

## 5. Stages
| stage | content | gate |
|---|---|---|
| W1 (done) | op ordering as Firn state planner `lib/wlan/macplan.fi` (events from own stack -> ordered `ieee80211_ops` calls, sta single steps, chanctx, keys, leave/down from every phase); measurement tool | `tools/lkpi80211/run.sh` 6/0 (kernel-profile compile, 23 host checks incl. 200000-event fuzz, 4 mutants red) |
| W2 (done) | C glue + objects: `ieee80211_hw/vif/sta`, op dispatch from macplan, upcall table, skb pool; Board lifecycle hook | `tools/lkpi80211/run.sh` 19/0 (host fake driver, 9 shim mutants) |
| W3 (done) | QEMU: own fake radio module (C, not Linux code) over `iwl_fakeap` -> scan, WPA2 connect, ping | `tools/lkpi80211/qemu.sh` 45/0 |
| W4 (in progress) | iwlwifi (iwlmvm + pcie) fetched 6.12.101 as a hashed tree, unmodified, built over shim, store package `lkpi-iwlwifi`; firmware via fw.request | `tools/lkpi80211/w4.sh` ratchet (units compiling, missing headers), then closure 0 undefined; QEMU probe on fake CSR (`tools/iwlfh`) |
| W5 | HP 8265: A/B own driver vs lkpi-iwlwifi (scan count, connect time, ping, throughput) | Boss hardware (needs) |
| W6 | rtw88, mt76 (mt7921e), then rtw89, ath10k/11k (ath11k needs MHI + QMI: extra base) | per driver |

## 6. Rules
- Same as `LINUXKPI-PLAN.md` sections 0 and 2; Wi-Fi rows go to `compat/linuxkpi/sources.tsv` only in W4.
- Licenses (main file SPDX): iwlwifi `GPL-2.0 OR BSD-3-Clause` (dual), mt76 ISC, rtw88/rtw89 `GPL-2.0 OR BSD-3-Clause`, ath10k ISC, ath11k BSD-3-Clause-Clear (SPDX of the main file each, checked 6.12.101): all usable without GPL. Not yet scanned per file. Firmware blobs: linux-firmware redistributable, data only.

## 7. W4 build path (24.11.2026)
- Sources: `sources.tsv` row `iwlwifi` pins the whole directory `drivers/net/wireless/intel/iwlwifi/` (204 files) by a tree hash (`find | sort | sha256sum` of every file, then sha256 of that list); `fetch.sh` handles rows ending in `/`. Units = `compat/linuxkpi/units/iwlwifi.txt` (Kbuild for IWLWIFI+IWLMVM without DVM, debugfs, LEDs, PM_SLEEP, MEI, EFI, ACPI, tracing): 34 iwlwifi + 33 iwlmvm.
- Cut for headers: wire protocol definitions come from Linux unchanged (`hdr-ieee80211` = include/linux/ieee80211.h, `hdr-nl80211` = uapi nl80211.h, `hdr-radiotap`; fetched by hash, `lkpi_driver_headers`); the driver API (`net/mac80211.h`, `net/cfg80211.h`) and all base headers are own shim headers (FreeBSD way), because the shim implements them and owns the struct layout. Kconfig: `shim/include/osum/kconfig_iwlwifi.h` via `lkpi_driver_flags iwlwifi`.
- `treeprobe.py`: per unit ok / first missing header / error count; full missing-header set by stub discovery (empty stubs until no new name); closure (nm -u of compiled units minus defined minus shim objects) once units compile.
- Open, in order: (1) remaining 45 base headers (netdevice/skb+NAPI, spinlock/mutex/wait/completion, workqueue/timer/jiffies/ktime, device/dma-mapping/dmapool/interrupt/firmware, mm/vmalloc, sched, seq_file/debugfs stubs, tracepoint stubs, ipv6/tcp/tso for TSO offload); (2) own `net/mac80211.h` + `net/cfg80211.h` grown to iwlmvm usage (FreeBSD: 2684 + 2384 lines) and the W2 shim C moved onto that layout; (3) closure to 0: ~258 base symbols + 78 mac80211 + 27 cfg80211 upcalls; (4) loader limit `closure.py MAX_IMAGE` 512 KiB vs ~2.8 MB driver; (5) `pack.sh` for `lkpi-iwlwifi` with iwlwifi-8265 firmware via fw.request; (6) QEMU probe on fake CSR.
- Guard needed before W5: native iwl must claim the PCI function in `drvreg` when it boots, so a compat package can never bind the same 8265 (today only `noiwl` separates them).
- Estimate to W5 on the HP: ~15-20 worker sessions of 60 min (headers 2-3, mac80211/cfg80211 API 4-6, closure + loader 4-6, package + QEMU probe 3-4, HP A/B 1-2).
