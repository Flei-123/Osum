# TRAY -- notification area, overflow, tray API, microphone indicator, audio hub (r? W-TRAY, 12.10.2026)

Status: **model + audio hub done and tested on the host; the bar UI (fUi scene, glass flyouts) is NOT built yet.**

## What exists now (main)

| Part | File | Test |
|---|---|---|
| Audio device/stream registry: defaults (priority + pin), hot-plug, volume/mute per device, per-app mixer, systemwide mic mute, levels, owners, events | `lib/audio/hub.fi` = **mirror** of Firn `lib/audio/hub.fi` (Firn main f9b93c0f9, `docs/AUDIO-HUB.md`) | Firn `tests/2790_audio_hub.fi` (63 checks, 4 build levels); here `tools/tray/hub_host.fi` |
| Tray model: items (icon, tooltip, badge, 6-entry context menu), places bar / overflow / hidden, drag-reorder, owner-gone cleanup, click / menu / pick events | `lib/fui/tray.fi` | `tools/tray/host.fi` (41 checks) |
| Texts of the sound + mic icons ("Mikrofon wird verwendet von A und B", "Lautsprecher: 35 %") | `lib/fui/trayaudio.fi` | same |

`bash tools/tray/run.sh` runs all three in seconds (gate `tray`, tier quick). `lib/audio/hub.fi` must stay byte-identical to Firn's
(the runner checks it when `/root/firn` is there); delete the mirror when `vendor/firn/COMMIT` has moved past f9b93c0f9 (same rule as `lib/fui/navkit.fi`).

## How the pieces connect (design, not yet wired)

```
HDA driver (kernel/hda.fi, syscalls 1850-1854) --report--> audio service (thin process) --hub_*--> audio.hub
        ^                                                       |  hub_event_pop / hub_gen
        |  samples: hub_apply(stream) in the mix path           v
   mixer (kernel/mix.fi / audio.mixer)                 tray model (fui.tray) <--register-- programs (action bus)
                                                              |  tray_at(place, i)
                                                              v
                                          task bar scene (icons, flyouts)  --EV_CLICK/EV_PICK--> action bus --> owner
```

* Back end: the Osum audio syscalls know ONE output (HDA or AC97, up to 4 mixer streams, one volume, no capture, no device list). The hub is
  ready for many devices; the driver side needs (a) jack sense -> `K_JACK` device add/remove, (b) capture stream (`SYS_AUDREAD` or similar), (c) a USB audio class driver. None of this exists (roadmap).
* Programs register tray items over the action bus (`tray_register` / `tray_menu_add` / `tray_owner_gone` when the process dies); the bar turns `tray_event_pop`
  events into bus messages to the owner. The bus message names are NOT defined yet (see `docs/ACTION-BUS.md`).
* Mic indicator rule: shown while any capture stream is open or the systemwide mute is on; the tooltip names the apps. Capture mute is enforced inside `hub_apply`
  (silence + level 0), not in the UI, so a program cannot bypass it by ignoring the icon.

## Honest gaps (what the order asked for and is NOT done)

* Win11 system area as fUi scene (network glyph states, speaker slider flyout, battery, clock + bell), overflow flyout, drag in the picture, glass, light/dark, scale 1/2,
  midline test, a11y names, keyboard -- **not built**; `kernel/user/taskbar.fi` is 8262 lines and sits at the format-2 size limit (`tools/progsize`): the flyouts must be separate
  scene windows (like `barpop.fi` / `taskview.fi`), not more code in the bar.
* Existing bar today (`docs/WIN11BAR.md`): fields F_NET/F_SND/F_BAT/F_CLK/F_NOTI/F_LANG, `tray_chevron=1`, `tray_group=1` capsule, quick settings in `kernel/user/qs.fi`
  (1706 lines), sound via `SYS_AUDGET/AUDSET` (volume + mute only). There is no Wi-Fi glyph (no Wi-Fi driver, r21), no vector glyph set per network state.
* No before/after screenshots (no VM run was started in this slot).
