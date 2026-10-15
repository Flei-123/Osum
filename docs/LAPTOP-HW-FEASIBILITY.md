# Laptop hardware feasibility (L-011 .. L-018) — 14.10.2026

Honest assessment, no code. Effort: **S** = days, **M** = 1-3 weeks, **L** = months or open-ended.
Facts about the current tree were read from the sources on 14.10.2026; facts about foreign
hardware are from public driver tables / datasheets as known and are marked *(unverified here)*
where nobody in this repo has measured them.

## 0. Starting point (what exists, measured in the tree)

| Area | State in tree |
|---|---|
| USB host | xHCI + EHCI, hub, HID (boot + report descriptors), mass storage. `kernel/usb/usb.fi` binds by class (`DRV_KBD/MOUSE/MSC/HIDGEN/HUB`). **No isochronous transfers**, no CDC, no video class. |
| xHCI API | `xhci.control(...)` and a synchronous `xhci.bulk(state, slot, dci, dst, len)`; endpoints opened via `ep_open`/`configure_endpoint`. No asynchronous RX queue, no interrupt-endpoint callback beyond what HID does. |
| Net | `kernel/net/netdev.fi` is a **PCI-keyed** table (virtio, e1000/I219, r8169). Every accessor takes a *card number* derived from PCI IDs. A USB NIC has no PCI ID, so it needs a second "kind". |
| WLAN | `lib/wlan/` = 802.11 framing, beacon, channel/regulatory, WPA handshake, CCMP, state machine (184 checks green, no card). `lib/wlan/usbchip.fi` only **names** USB chips. |
| Audio | `kernel/drv/snd/hda.fi`: analog codecs; HDMI/DP and SPDIF pins are **skipped on purpose**. `GET_PINSENSE (0xF09)` is defined and used for jacks. |
| GPU | `kernel/drv/gpu/vgpu.fi` (virtio-gpu 2D, one scanout, reads `num_scanouts`), Bochs VBE / UEFI GOP framebuffer. No Intel/AMD KMS. |
| Login | PBKDF2 `$osum1$` passwords, lock screen, multi-user (`kernel/user/login.fi`, `lock.fi`, `ipc/perm.fi`). No PIN, no passkey, no TPM (comments only). |
| Bluetooth, camera | nothing (grep finds only mentions). |

## 1. Recommended order

1. **L-011 PIN part** (S/M) — pure software, QEMU-testable, unlocks the daily-driver login story. Do first.
2. **L-015 USB tethering** (M) — the only radio-free way to get online on a WLAN-only laptop, fully QEMU-testable (`usb-net`). Do second.
3. **L-016 Bluetooth step 1** (M) — HCI over USB + HID keyboards/mice; QEMU can pass through a host dongle, protocol half is host-testable.
4. **L-012 UVC camera** (M) — needs isochronous support in xHCI first; QEMU 7.2 has no `usb-video` (measured with `-device help`) — test with `usb-host` passthrough.
5. **L-013 fingerprint** (M for one documented class, L for the rest) — only after PIN exists (it is a convenience on top of PIN).
6. **L-014 IR face** (L) — after camera; hardware-dependent.
7. **L-018 GPU KMS** (L, open-ended) — Intel display-only first; do not start before the multi-monitor model is wired (see `docs/MONITORS.md`).
8. **L-017 WLAN** (L, probably never for Intel) — see section 8; prefer tethering + USB-Ethernet.

## 2. L-011 Hello-like biometrics security model

**Effort:** PIN = **S-M**; biometric templates + lockout = **M**; TPM sealing = **L** (separate item X7).

Model (what to build, in this order):
- **PIN first (r253).** A PIN is *not* a weak password: it is a **device-bound** credential. It only unlocks a key on THIS machine and is useless elsewhere. That is the whole security argument and it must hold in the implementation:
  - PIN is verified by the local login service (same path as password, `$osum1$`-style salted PBKDF2/Argon2 — Argon2 exists in `tools/argon`), never sent anywhere.
  - Store in the user's secret area (mode 0600, owned by the user, in the encrypted home if CRYPTO-ERASE is on) — not world-readable.
  - **Lockout:** counter persisted *before* the check (so pulling power does not reset it). 5 wrong tries → exponential back-off (1 min, 2, 4 …); 10 → PIN disabled, password required. Counter and time are in the same record; the record is written with the journal commit so a crash cannot roll the counter back.
  - PIN length 6+ digits recommended; no "1234" list; same lock-screen UI path (`lockseal` gate must stay green).
- **Biometric templates** (fingerprint, face) are **secondary** unlock factors: they only *release the PIN-equivalent key*, they never replace the password for first login after boot or for changing security settings.
  - Template stored **locally only**, **encrypted** with a key that is itself released by PIN/password (so a template file alone is useless). AES-GCM or ChaCha20-Poly1305 from `lib/crypto`.
  - Never leaves the machine, not synced, not in backups (`docs/BACKUP-SECRETS.md` class "never").
  - Matching threshold and false-accept rate are properties of the *sensor + matcher*; without a measured FAR we must say "convenience unlock", not "secure".
  - Presentation-attack resistance: fingerprint (capacitive) is OK-ish; **RGB camera face unlock is not safe** (photo attack) — only IR+depth face (L-014) may be offered, and only with a liveness check.
- **TPM (optional, later):** seals the unlock key to the boot state (PCR). Needs TIS/CRB driver + TPM2 command set + measured boot, which does not exist (Secure Boot is off, loader unsigned). Without measured boot a TPM only gives "key cannot be copied off the disk", still useful but not Hello-grade. Effort **L**.
- **Software fallback without TPM:** key wrapped by a key derived from the password/PIN + a device key in `/device` (already "never backed up"). Rate-limited offline attack is then bounded by KDF cost.

Risks: lockout counter rollback (fix: persist first), shoulder-surf PIN on lock screen (mask input), template theft (encryption), biometric false accepts (document), user lockout (always keep password path).

Required hardware: none for PIN. Fingerprint/IR: see 4/5. TPM: a real board with TPM 2.0 (most laptops have fTPM).

## 3. L-012 UVC camera over xHCI

**Effort: M-L.** Steps:
1. **xHCI isochronous endpoints** (the real blocker): transfer rings with TD descriptors per micro-frame, scheduling (Frame ID / `SIA`), interval handling. Today only control/bulk/interrupt exist. **M**.
2. UVC class parse: Video Control (processing unit, camera terminal) + Video Streaming interface, format/frame descriptors, alt-setting selection by bandwidth. **S**.
3. Probe/Commit control (`VS_PROBE_CONTROL`, `VS_COMMIT_CONTROL`), payload header parsing (FID/EOF/ERR bits), frame assembly. **S-M**.
4. MJPEG decode (a JPEG decoder exists in the Firn lib `vendor/firn/lib/jpeg`, port needed) and/or YUY2→RGB. **S**.
5. Userland API: a `camd` service + capture permission through the action bus (privacy: indicator + per-app grant). **M**.
6. Real-laptop quirks: many integrated cams are UVC 1.1/1.5 with vendor extension units; bandwidth reservation for >1 stream; USB 2 high-speed micro-frame timing.

Hardware: any UVC webcam for the protocol half; the laptop's own cam for the real test. QEMU 7.2: no UVC device (measured); use host USB passthrough (`usb-host`) of a real webcam.
Risks: isochronous timing under load (we saw load 300 on the build server — real-time scheduling matters), buffer ownership, DMA below 4 GiB.

## 4. L-013 fingerprint readers

**Effort: L overall; M for one documented class.** Reality check:
- **Documented / open-ish:** *(unverified here, from public driver tables)*
  - Reader families supported by `libfprint` with open drivers: Elan (some USB), AuthenTec/UPEK (old), Validity (partially), Synaptics (newer "Prometheus" with host-side matching and a signed firmware flow — **partly proprietary**).
  - **Match-on-chip** sensors (Elan/Goodix newer, Synaptics): the sensor does the matching; the host only enrols/identifies through a vendor protocol. Needs the vendor's command set.
- **Proprietary:** **Goodix** (most modern Lenovo/Dell/HP laptops, USB `27c6:xxxx`) — encrypted vendor protocol with per-device TLS-like channel and firmware upload; the open reverse-engineered `libfprint` drivers exist but are brittle. **Synaptics Prometheus** needs signed firmware provisioning.
- **Bus:** USB (most) or **SPI/I²C** (some newer ones, behind ACPI) — I²C-HID exists in the tree (`i2chid.fi`), SPI does not.
- **Architecture to copy:** libfprint-style split: *sensor driver* (get image or template) → *matcher* (minutiae, NBIS-like, ours to write, ~3-4k lines, M) → *template store* (see section 2).
- **Honest conclusion:** one concrete sensor model in the owner's laptop is the only sane target. Identify the exact USB ID first (`lsusb`-equivalent; our USB boot line prints `id=VVVV:PPPP`), then decide. Do **not** start before PIN (L-011) exists.

Hardware: the actual laptop sensor. QEMU cannot emulate any of them.

## 5. L-014 IR face recognition

**Effort: L.** Needs: UVC camera working (L-012) **plus** the IR stream (Windows Hello cameras expose a second video-streaming interface for the IR sensor, often with a vendor extension unit to switch the IR emitter on — `uvcvideo`-style quirks), a face-detect + embedding model (needs CPU/GPU inference; no ML runtime in the tree), liveness (IR + depth or blink), and the template store from section 2.
Risks: model quality and FAR cannot be validated without a data set and hardware; emitter control is vendor-specific; compute cost on a kernel without SIMD-optimised libs (SWR numbers show 1.3 ns/op scalar).
Recommendation: **last**; probably userland with a small embedding model, only after camera + PIN + template store exist.

## 6. L-015 USB tethering (CDC-ECM / CDC-NCM / RNDIS)

**Effort: M.** Checked in the tree: **no CDC code at all** (no ECM, NCM, RNDIS); `usb.fi` only claims HID and mass storage by interface class. Decision: **not implemented in this run** because it is not cheap:
- `netdev.fi` is PCI-keyed (card number → PCI kind). A USB NIC needs a new kind and every `*_on(state, card)` accessor must route to it (tx, rx_take, link state, MAC).
- `xhci.bulk` is synchronous and blocking; RX needs an asynchronous bulk-IN queue (re-arm a transfer, poll/irq completion, copy to the net stack), i.e. xHCI work, not just a driver.
- Hot-plug and `configure_endpoint` for 3 endpoints (bulk IN, bulk OUT, interrupt IN for link/speed notifications).

Steps and rough sizes:
1. Config selection + class match (CDC 02:06:00 ECM, 02:0D NCM, 02:02:FF RNDIS; Android uses RNDIS or NCM, iPhone uses ECM-like "ipheth" — a different protocol) **S**.
2. CDC functional descriptors → MAC address string descriptor, max segment size **S**.
3. **ECM:** frames are raw Ethernet on bulk endpoints; trivial once the async RX exists **S**.
4. **RNDIS:** init/query/set/keep-alive message exchange on the control pipe (`SEND_ENCAPSULATED_COMMAND`/`GET_ENCAPSULATED_RESPONSE`) + 44-byte data header per packet **M**. The message layer is pure encode/decode and can be tested on the host like `lib/wlan`.
5. **NCM:** NTB16 headers, aggregation **M** (needed by modern Android "USB tethering" on some devices).
6. xHCI async bulk IN queue + netdev "usb" kind **M**.
7. QEMU test: `-device usb-net,netdev=n0` (QEMU 7.2: strings show configurations "CDC", "Subset" and "RNDIS") — both client protocols testable with SLIRP DHCP. No NCM model: NCM stays untested until a real phone.

**Done (protocol half):** `lib/usbnet/rndis.fi` -- RNDIS INIT/QUERY/SET/KEEPALIVE/HALT encoders (golden layout), validating readers, PACKET_MSG wrap/unwrap, CDC-ECM MAC-string parser; gate `tools/usbnet/run.sh` (host only).

**Done (CDC-ECM driver, step 1-3 + 6):** `kernel/drv/net/usbnet.fi` (bulk IN/OUT data plane), `kernel/usb/usb.fi` (walks all configurations, class 02:06 -> `DRV_ECM`, union + ethernet functional descriptors, MAC from the string descriptor, SET_INTERFACE to the data alt setting), `kernel/net/netdev.fi` (`KIND_USBNET`, `late_usb` after USB enumeration), `kmain.fi` (second `netsvc.stage` when the USB function is the only NIC). Gate `tools/usbecm/run.sh` (= `tools/usbnet/qemu.sh`): QEMU `qemu-xhci` + `usb-net`, no PCI NIC.
Not done: RNDIS driver (the messages exist), NCM, interrupt-IN notifications (link is assumed up), halted-bulk-endpoint recovery, hot unplug, a second USB NIC.

Hardware: any Android phone with USB tethering (RNDIS/NCM), or a USB-Ethernet dongle (ASIX/Realtek RTL8152 are vendor-class, not CDC: a **separate** driver each, S-M).
Why this matters: laptop has WLAN only; this is the cheapest way online (r21 is not coming soon, see 8).

## 7. L-016 Bluetooth

**Effort: L overall; M for step 1.**
- **Transport:** nearly all laptop controllers are USB (btusb: Intel AX2xx BT, Realtek, MediaTek, Qualcomm). HCI over USB = class E0:01:01; control endpoint for commands, interrupt-IN for events, bulk-IN/OUT for ACL data. SCO/isochronous (headset audio) needs isochronous (blocker shared with L-012).
- **Firmware:** Intel and Realtek controllers need a **firmware blob loaded over HCI vendor commands** (Intel: `ibt-*.sfi/.ddc`; Realtek: `rtl_bt/*.bin`). Licence of the blobs must be checked before shipping; not shippable in the OS image by default.
- **Stack steps:** HCI (commands/events, S-M) → L2CAP (M) → SDP (S) → HID over BR/EDR or BLE HOGP (M; reuses `hidrep.fi`) → pairing/SMP + key storage (M, crypto exists) → A2DP (L2CAP + AVDTP + SBC codec encoder + audio sink, **M-L**) → HFP (needs SCO) → BLE GATT (M).
- **Testing:** QEMU can pass a real USB dongle through (`usb-host`) — no virtual controller. HCI parsing/encoding is host-testable.
- **Recommended scope:** step 1 = HCI + pairing + BLE/BR-EDR HID keyboard/mouse (covers "no USB mouse on the laptop"), step 2 = A2DP.
Risks: firmware licence, per-vendor quirks (Intel two-stage boot loader mode), timing.

## 8. L-017 WLAN, honestly

**Effort: L, and for Intel AX2xx realistically "not planned".**
- **Protocol side is done and host-tested** (`lib/wlan`). What is missing is the **card**: PCIe MAC + firmware.
- **Intel AX200/AX201/AX210/AX211 (iwlwifi):** the driver is ~100k lines in Linux, talks to a **mandatory proprietary firmware** (`iwlwifi-*-qu-*.ucode`, 1+ MB) through a command/notification interface with hundreds of message types, TX/RX rings, DMA, regulatory data in the firmware, calibration. Firmware is redistributable under Intel's licence but not open. A minimal station-only driver (scan, WPA2 connect, data) is **many months** of work *(estimate, unverified)* and cannot be tested in QEMU (QEMU has no 802.11 model; measured in `tools/wlan/run.sh`).
- **MediaTek MT7921 / Qualcomm QCA6390:** similar firmware dependence, also no QEMU model.
- **USB WLAN sticks** are the pragmatic exception: few chip families (RTL8812AU, MT7612U, MT7921U) with simpler firmware, USB bus already exists. Still a firmware download per family. `lib/wlan/usbchip.fi` names the chips; one family could be a realistic **L-sized** target *only* with the physical stick on the desk.
- **Recommendation:** treat WLAN as **hardware-gated**: (1) tethering (L-015) now, (2) USB-Ethernet dongle drivers, (3) one USB WLAN family if the owner keeps a specific stick, (4) Intel PCIe WLAN last/never.

Required hardware: the exact chip (PCI ID from the boot table prints `wifi, needs 802.11 + fw`).

## 9. L-018 GPU KMS (Intel / AMD)

**Effort: L, open-ended; display-only Intel = L; AMD = XL.**
- **Today:** UEFI GOP / Bochs framebuffer, no mode changes after boot, no real EDID, no vsync (r33, G-008), no multi-monitor.
- **Intel integrated:** register documentation is public per generation (Intel PRM volumes). Display-only order: GMBUS/DDC (EDID) → pipes/planes/transcoders/PLLs/DDI buffers → eDP panel power sequencing + backlight (PWM via PCH/GPU) → hot-plug detect → atomic modeset. Each generation (Gen9 Skylake … Gen12 Tiger/Alder Lake, Xe) differs (clocks, DDI, watermarks). **One generation = M-L**, the owner's laptop generation first. Firmware: DMC (display microcontroller) blob needed for power states on Gen9+ *(unverified details)*; GuC/HuC only for rendering.
- **Rendering** (OpenGL/Vulkan, r36): separate, years. Current path is the software rasteriser (`lib/gpu/swr`: 31.8 ms/frame 1240x720 1 core).
- **AMD (amdgpu):** register headers are published but the driver is hundreds of thousands of lines, firmware (PSP, SMU, DMCUB…) mandatory. **Not realistic.**
- **Pragmatic path:** UEFI GOP framebuffer with a *second* GOP/virtio per output (multi-monitor via firmware-initialised outputs, no mode switch) is much cheaper than KMS; and virtio-gpu (QEMU) covers testing.
- **Recommendation:** do not start native KMS before (a) the output model is wired through `fb.fi`/`wm.fi` and (b) a concrete laptop generation is fixed. GOP + software compositor stays the product until then.

## 10. Roadmap-note summary

| Item | Effort | Order |
|---|---|---|
| L-011 PIN (r253) | S-M (PIN) / M (biometric store) / L (TPM) | 1 |
| L-015 USB tethering | M | 2 |
| L-016 Bluetooth | M (HCI+HID) / L (A2DP) | 3 |
| L-012 UVC | M-L (isoch first) | 4 |
| L-013 Fingerprint | M per documented class; Goodix = L | 5 |
| L-014 IR face | L | 6 |
| L-018 GPU KMS | L Intel display-only, XL AMD | 7 |
| L-017 WLAN | L (USB family) / not planned (Intel PCIe) | 8 |

## 11. Hibernate (S4) and I2C-HID touchpad (15.10.2026)

- **S4**: see `docs/HIBERNATE-S4.md` (concept, risks, order). Image format `lib/power/hibimg.fi` is done and host-tested; page export, raw writer and boot restore are not.
- **I2C-HID**: `kernel/drv/hid/i2chid.fi` now runs end to end against a *simulated* DesignWare controller + precision touchpad (`tools/i2csim/run.sh`, 18/0): probe with a decoy slave, SET_POWER + RESET, report descriptor parse, input reports through `poll` into `hidin` (same events as the direct replay). The GUI loop polls every 8 ms (`i2chid.poll_tick`). **[unverified]** on silicon: LPSS controller found by PCI class + IC_COMP_TYPE, clock counts, power-on/reset timing (no delay after SET_POWER yet), `_DSM` descriptor register (tries 0x0001 then 0x0020), polling instead of the ACPI GpioInt interrupt.
