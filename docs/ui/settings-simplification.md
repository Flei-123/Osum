# Settings simplification (Boss rule: the best, simplest interface)

## Rule
- A setting nobody needs daily is removed or hidden under `advanced` routes.
- Defaults must work; no jargon (no IP, channel, driver phase, errno) on normal pages.

## Done: Wi-Fi page (settings://network/wifi)
- Removed field `wifi-ssid` (free text network name). Replaced by the list of found networks (`wifi-nets`), one click selects.
- Password field shown only for a secured, not yet saved network (`when wifi-need`).
- Status line is plain: no adapter / not connected / connected to NAME / no networks / switched off.
- Removed driver-phase, step and errno status text and 10 locale keys (settings.wifi.ssid/off/noscan/badssid/nodriver/saved/savedram/nowrite/drv/found).
- `Scan` renamed `Refresh`; the page refreshes on open.
- Code: kernel/user/settings/setwifi.fi (reuses welcome_net + netui list model, wlanconf.save).

## Done: rarely used pages behind `advanced` (routes flag, no code removed)
- USB network (`network/usb`): needs a phone or tether cable, not daily.
- Sync (`accounts/sync`): only with a cloud account, a sub-step of Cloud.
- Activity log (`privacy/activity-log`): diagnostics, not a setting.
- Wi-Fi status distinguishes `Connected to X` from `No internet access, connected to X` (gateway never answered, `nv.link_state`).

## Done: `advanced` really hides sidebar entries
- Before, the `advanced` route flag only exempted a page from the control-count lint; the sidebar still listed every page.
- Now the sidebar skips advanced routes unless the page is the open one or the search box has text (setpages.advanced_listed, setroute.flat_advanced). Related links, deep links and search still reach them.
- Newly advanced: Connections (network view: view modes, per-program usage, active connections with local/remote addresses) and Remote control access (bridge).
- Normal Network section now lists only Network and Wi-Fi (+ Bluetooth); no IP field outside `fixed` mode.

## Done: Network start page
- Normal view: one status line (`connected`, `not connected`, `connecting ...`, `no internet`) and the address mode (`automatic` / `fixed`).
- Throughput, link speed, address, mask, gateway, hardware and the manual address entries show only with mode `fixed` (existing `when manual` condition, no new code).
- Plain words: `not connected` instead of `no carrier`, `no internet` instead of `gateway silent`, `Address: automatic | fixed` instead of `Obtain address: over DHCP`.
- Connections page: long note lines shortened so they are no longer cut off at the column edge.

## Open
- A real `network/details` route (advanced) instead of the `fixed` condition needs a new tab id; R_ANZ shifts K_TAB0/K_PKGTAB0 ranges and the package tabs, so it needs its own change and gate run.
- Connections table: the `Kind` column is too narrow, header and the empty row are cut (`K...`, `(...`); needs proportional column widths in the table widget.
- Replace `nv.link_state` by the NETHEAL stage once the network health service is on main (one place: setwifi.status_fill).
