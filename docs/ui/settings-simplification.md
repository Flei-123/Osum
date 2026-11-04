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

## Candidates, not done yet (need Boss ok per page)
- Network view (netv), Bridge: move behind `advanced`.
- Advanced display, Window effects, Gestures: already `advanced` routes, keep hidden.
- Connections page: IP/mask/gateway only in a manual-mode block.

## Open
- Replace `nv.link_state` by the NETHEAL stage once the network health service is on main (one place: setwifi.status_fill).
