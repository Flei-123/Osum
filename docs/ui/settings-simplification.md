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

## Candidates, not done yet (need Boss ok per page)
- Network view (netv), USB network, Bridge, Log, Sync: move behind `advanced`.
- Advanced display, Window effects, Gestures: already `advanced` routes, keep hidden.
- Connections page: IP/mask/gateway only in a manual-mode block.

## Open
- After-screenshots scale 1+2 and gate runs (settingsnarrow, a11y, desktop quick, k15, palette, settingsman) not run.
