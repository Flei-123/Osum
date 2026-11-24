# W5: own iwl driver vs lkpi-iwlwifi on the HP 8265

Switch: boot word `noiwl` keeps the native 8265 bring-up off (`iwl.wants_boot`); the compat package binds only when `/etc/drvstore.conf` says `tiers=native+compat` and `lkpi-iwlwifi` is installed (`drvctl install`).

| run | boot words | drvstore.conf | package |
|---|---|---|---|
| A native | default | default | not needed |
| B compat | `noiwl` | `tiers=native+compat` | `lkpi-iwlwifi` installed |

On the device after each boot: `/bin/busybox sh /tmp/ab.sh <A|B> <gateway-ip> <url of a >=100 MiB file>`; result in `/tmp/ab-<label>.txt` (link-up time from boot, `/proc/wlan` before and after, 20 pings, download time). Compare A and B: link-up seconds, ping loss/avg, download seconds for 100 MiB.

Blocked until W4 produces a loadable `lkpi-iwlwifi` package (see docs/LINUXKPI-80211.md, W4 ratchet).

## W5 status (24.11.)

The real iwlmvm reaches ALIVE in the fake (RX ring, MSI-less interrupt, v3 alive notification). The fake does not yet answer the real command queue: queue 0 doorbell without NIC access (shadow registers), a larger prph table, a believable 8000-family NVM (SW, REGULATORY, MAC_OVERRIDE, PHY_SKU) and INIT_COMPLETE/PHY_DB sequences of the stock driver are missing. If that fake work grows past two more sessions, test directly on the HP:

1. Build: `LKPI_IWL_PUMP=1 bash compat/linuxkpi/iwlmod.sh <dir>` (debug: `LKPI_IWL_DEBUG=1`), pack with `wifipack.sh` as in `iwl.sh`, install with `drvctl install`.
2. Boot words `iwlcompat` (no `fakewlan`), `/etc/drvstore.conf` = `tiers=native+compat`.
3. Expect in the serial log: `iwl_pcie_rx_handle_rb ... UCODE_ALIVE_NTFY`, then `NVM_ACCESS_CMD` answers from the real firmware, `iwl_mvm_...` init and `ieee80211_register_hw`.
4. Then run A/B as above (`ab.sh`): link-up time, 20 pings, 100 MiB download.
5. If the HP hangs after the firmware load: collect `/proc/drivers`, the serial tail and the `hang:` report; the DMA path is already verified in QEMU (bus address == kernel address, RX ring bases are 256-byte aligned).
