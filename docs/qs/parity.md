# Quick settings parity check vs Windows 11

Audit of `kernel/user/qs.fi` (panel, Win+A) and what sits behind it. Measured 31.10.2026 on the real HP EliteBook x360 1030 G2 (device `HP-ORIENTOS`, `XoffiOS (Firn) version 6 build d55bcfe6`, read-only: `/proc/*`, `/bin/hwinv`, `/bin/ps`, `/etc/*`). Code read on main `d0e7a932`. No code changed.

Effort: S = hours, M = 1 day, L = several days, XL = a week or more / new driver stack. "Works on HP" = proven on the real HP, not QEMU.

## What the panel is today

Layout (`build()`): 5 tiles (3 + 2), brightness slider, volume slider with mute glyph, media plate, separator, footer (battery percent, task manager button, gear). Tiles placed by `tile_of`: wired network on/off, dark mode, power profile (save/balanced/performance cycle), window tiling, do-not-disturb. Two more tiles exist in code but are never placed (`tile_of` never returns 0 or 2): fake network, hide taskbar.

## Parity table

| # | Win11 element | Visible | Works on HP | Evidence | Missing | Effort |
|---|---------------|---------|-------------|----------|---------|--------|
| 1 | Media card: title, artist, cover, prev/play/next | Plate only, static text "no media" (`media_paint`) | No | No media session anywhere (grep mpris/session/nowplaying in kernel+lib: only a taskbar comment); `/bin` has no player; media keys not bound (`taskbar.fi` comment); `/proc/hotkeys` unknown=1 | Media session service on the bus (players publish title/artist/cover/state, receive transport commands), card with cover + 3 buttons + progress, media key routing | L |
| 2 | Wi-Fi tile + chevron (network list) + SSID | No (the "Network" tile is the wired IP on/off switch) | Radio + scan yes, connection no | `/proc/wlan`: 8265 `3a:00.0 8086:24fd`, fw 36 loaded, `alive=yes`, NVM ok, `scan nets=3` (Holo, HoloG, DIRECT-...); `auto=no-conf rc=-300 tries=332`, `/etc/wlan.conf` empty, no link/DHCP over WLAN; real traffic goes over `eth0` = usb-net (`/proc/net/dev`); `hwinv` still prints `wlan ... driver=none` (stale) | Wi-Fi tile with state + SSID, chevron flyout with scan list from `/proc/wlan`, join with password (Settings has the flow: `settings.fi` writes `/etc/wlan.conf`). Real join on HP still open (r21, r118, r2466: needs SSID/password from Boss) | M (tile + list), L (join proven on HP) |
| 3 | Bluetooth tile + chevron | No | No | `/proc/bluetooth`: `power off state none controller 00:00:00:00:00:00`; `hwinv usb_bt=0`; internal xHCI `00:14.0` is `state=idle` (only the dock xHCI `39:00.0` is up) so internal USB devices are never enumerated; `btusb.fi` + `lib/bt/hci.fi` are generic HCI over USB, no Intel bootloader/firmware load found; ACPI also lists `INT33E1 \_SB.PCI0.UA00.BTH0` (UART node) - which transport the 8265 combo uses here is unverified; Settings page `setbt.fi` exists | Evaluation: internal xHCI bring-up on HP (L), Intel BT bootloader + firmware (M), pairing UI + profiles HID/A2DP (XL), then tile + device list (M) | XL |
| 4 | Airplane mode | No | No | Only `kernel/net/wlan_rfkill.fi`, which WATCHES the hardware switch (`/proc/wlan`: `rfkill: hw=off radio=enabled changes=0`); no software rfkill, no service, no BT radio | Radio service (software rfkill state for WLAN, later BT, persisted in `/etc`), WLAN radio off/on in `iwl`, tile, restore at boot | M (WLAN only), L (with BT) |
| 5 | Battery saver | Partly: tile "Energy: save/balanced/performance" cycles 3 profiles, not a Win11 on/off saver | Battery yes, profile unproven | `/proc/battery present=1 valid=1 percent=97 state=0` (ACPI `PNP0C0A` + EC `found=1 run=1`). Profile: kernel writes `IA32_PERF_CTL/HWP` (`pwr.fi`), but `PG_READY` on the HP is not readable with any allowed command; `/bin/ps` shows NO `powerd` and no `hotkeyd`, so `/etc/power.conf` (`profile_bat=save`) is not applied automatically | Saver semantics (toggle, auto-on at 20 %, dim screen, lower profile), measure the PERF_CTL effect on HP | M |
| 6 | Night light | No (the "dark mode" tile is the theme switch, a different feature) | No | Zero code: grep nightlight/nachtlicht/colour temperature hits only `docs/RECHERCHE-TASKLEISTE-2026.md` | Colour-temperature pass in the compositor (per-channel scale on present; HP fb write ~10 GB/s, cost fine), strength, schedule, tile + Settings page. Independent of backlight, so it would really work on the HP | M |
| 7 | Mobile hotspot | No | No | Only Wi-Fi client code (`lib/wlan/iwl_mvm_*`: station context, scan, connect); no AP context, no beacon TX, no authenticator side of the 4-way handshake, no DHCP server (`dhcp.fi` is a client), no NAT | Evaluation: AP mode on 8265 mvm (firmware side exists, driver side missing), authenticator, DHCP server, NAT/forwarding, upstream choice (HP upstream today is usb-net), STA+AP on one channel, UI | XL |
| 8 | Brightness slider | Yes (live while dragging, 20..200 mapped to percent) | **No** | `/proc/backlight`: `source 0 hw.any 0 acpi.bcm 0 acpi.levels 0 pwm.ok 0 pwm.why 3 soft.writes 0 changes 0`. `pwm.why=3` = PWM BAR beyond the identity map; no `_BCM` levels from the HP DSDT; GPU `00:02.0 8086:5916` has no driver. Only fallback is `SRC_SOFT` (needs `gfx.ready`), never triggered (`soft.writes 0`), unmeasured. Fn brightness key arrives as `ext.last0=0x80` (unknown, not mapped) | Real backlight on the HP (BAR in identity map + PWM verify, or EC/OpRegion path), Fn keys, honest disabled state when `source=0` | L (hardware) + S (honest UI state) |
| 9 | Volume slider + mute glyph | Yes | Unproven (likely no) | `00:1f.3 8086:9d71` HDA controller present; `/proc/drivers hda found=1 state=seen`; `hwinv audio=8086:9d71` with no driver name; `docs/DRIVER-ARCHITECTURE.md` step 8: "controller ok, codec unknown"; no `/bin/play` and no readable `A_READY` on the HP, so no proof that sound ever came out of the HP; slider silently does nothing when `A_READY!=1` | HDA codec/pin config for the HP, proof with a tone; disabled state with reason when no device | L (codec) + S (honest UI state) |
| 10 | Output device chevron (next to volume) | No | No | `lib/audio/hub.fi` has device registry + default policy (speaker/HDMI/jack/USB priority) but no back end registers devices and no UI reads it; `traypop.fi` sound menu has no device list either | Chevron + flyout from the hub, default switch (`hub_set_default`), back ends register HDA jack/HDMI/USB audio, per-app mixer later | M (needs row 9 first) |
| 11 | Battery percent bottom left | Yes (`bat_line`, text only "97 %") | **Yes** | `/proc/battery percent=97 state=0 full=4229 rem=4104`, read via `SYS_PWRGET` fields 24/25/27 | Charging/plugged glyph (state field read but unused), battery level icon, click opens Settings > Power | S |
| 12 | Gear (all settings) | Yes | **Yes** | `/bin/settings` present on the HP; `spawn_and_close` | Nothing for parity (extra task-manager button next to it is harmless) | - |
| 13 | Edit (pencil): add/remove/reorder tiles | No | n/a | `tile_of` is a hard-coded 5-slot map, `N_TILE_ALL=6` constant | Tile registry (id, label, glyph, state, click, optional flyout), per-user list in `/etc`, edit mode UI | M |

## Other differences

- Win11 default tiles absent: Accessibility, Cast, Focus timing, Nearby sharing, Project. Do-not-disturb exists (flag in `qs`; the bar asks before showing a toast) and has no HP dependency.
- Fake network and hide-taskbar tiles are implemented but unreachable; put them into the registry (row 13) or remove them.
- The panel misleads by silence in two places: brightness and volume sliders look alive while the hardware path is dead on the HP (rows 8, 9). The header comment of `qs.fi` states the rule "only what really exists"; the sliders break it on the HP.
- `qs.fi` still has German identifiers and comments (`anhaengen`, `kopiere`, `zwei_zeilen`); conflicts with the English-code rule, not a parity point.

## Result

- Works for real on the HP: battery percent, gear.
- Visible but dead on the HP: brightness (no backlight source), volume (audio unproven).
- Visible, stub only: media card.
- Missing entirely: Wi-Fi tile, Bluetooth, airplane, night light, hotspot, output chevron, edit mode.

## Roadmap items (group Design/UI), by effort

- S: battery footer glyph + click; honest disabled sliders; powerd autostart on HP.
- M: tile registry + edit mode; night light; Wi-Fi tile with network list; airplane mode (WLAN); output device chevron; battery saver semantics.
- L: media session + card; real backlight on HP; HDA codec on HP.
- XL: Bluetooth (internal xHCI + Intel firmware + pairing); mobile hotspot.
- Wi-Fi join on HP stays with the existing r21 / r118 / r2466.
