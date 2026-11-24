# W5: own iwl driver vs lkpi-iwlwifi on the HP 8265

Switch: boot word `noiwl` keeps the native 8265 bring-up off (`iwl.wants_boot`); the compat package binds only when `/etc/drvstore.conf` says `tiers=native+compat` and `lkpi-iwlwifi` is installed (`drvctl install`).

| run | boot words | drvstore.conf | package |
|---|---|---|---|
| A native | default | default | not needed |
| B compat | `noiwl` | `tiers=native+compat` | `lkpi-iwlwifi` installed |

On the device after each boot: `/bin/busybox sh /tmp/ab.sh <A|B> <gateway-ip> <url of a >=100 MiB file>`; result in `/tmp/ab-<label>.txt` (link-up time from boot, `/proc/wlan` before and after, 20 pings, download time). Compare A and B: link-up seconds, ping loss/avg, download seconds for 100 MiB.

Blocked until W4 produces a loadable `lkpi-iwlwifi` package (see docs/LINUXKPI-80211.md, W4 ratchet).
