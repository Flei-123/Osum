# HOTPLUG — inventory and unified device-event design (W-HOTPLUG, 28.10.2026)

Roadmap H-001..H-004 (r2196-r2199). Base: main `2979af73`. Every row below was read from the tree. The older per-case report (removable media, 2026-09) is `docs/HOTPLUG-MEDIA.md`.

Tick rate: 100 Hz (`time.TICK_HZ`), so `% 25` = 250 ms.

## 1. Inventory

| # | Class | File : function | Trigger | On add | On remove |
|---|---|---|---|---|---|
| 1 | USB root port | `kernel/arch/x86_64/trap.fi` (timer, BSP only, `% 25` ticks) -> `usb.port_watch` | **Poll**, 250 ms: PORTSC change bit read per root port | marks port in `S_PEND` bitmap (no work in IRQ) | same, `S_PEND` |
| 2 | xHCI Port Status Change event | `drv/usb/xhci.fi : handle` (`T_PORT_EVENT`) | **IRQ** (event ring) | only counts `S_PORTEV`; **nobody acts on it** | same |
| 3 | USB enumerate/teardown worker | `usb/usb.fi : hotplug_work` (task context) | called from desktop loops: `ui/kgui.fi` (3 sites), `kmain.fi` (console loop); runs only if `S_PEND` or `S_HUBDUE` set | `mark` + `attach` (reset, descriptors, class bind) | `gone` -> `unplug_dev` |
| 4 | USB hub children | `usb/usb.fi : hub_rescan` / `hub_rescan_ports` / `hub_child_gone` | **Poll**: `usbdiag.rescan_due` sets `S_HUBDUE` every 2 s for the first 60 s after `t0`, then every 10 s; hub port status read over control pipe | `hub_probe_port` | `hub_child_gone` -> `unplug_dev` (+ `unplug_below` for nested hubs) |
| 5 | Root ports missed by PSC | `usb.port_watch` with `usbdiag.rescan_due` | **Poll** (same 2 s / 10 s): connected but not marked -> `S_PEND` | attach | n/a |
| 6 | USB mass storage add | `usb.fi : attach` -> `S_MSCGEN` +1 ; `block/wechsel.fi : kommt` via `kmain/kgui : wechsel_schritt` | counter comparison in desktop loop (poll of a counter) | assign slot in `S_MSCTAB`, probe partitions, mount `/medien/usbN`, `bus.noti_post` text `usb+ <path>` | `unplug_dev` -> `S_MSCWEG` +1 -> `wechsel.geht`: unmount, `usb-` notification |
| 7 | Eject button | `block/wechsel.fi : auswerfen`, `user/eject.fi`, `SYS_WECHSEL` (`WX_EJECT`) | user action | n/a | sync + unmount, `usb^` notification |
| 8 | USB NIC add | `usb/usb.fi : attach*` -> `drv/net/usbnet.fi : attach/attach_rndis/attach_ncm/attach_ch336/attach_ax88772/...` ; `net/netdev.fi : late_usb` | `late_usb` polled from the same desktop loops (only if no card exists yet) | `netdev.probe` + `netsvc.stage`, DHCP | n/a |
| 9 | USB NIC remove | `usb.fi : unplug_dev` -> `usbnet.unplug_slot`; `usb.fi : net_reclaim` (called at every `attach_at`) | from item 3/4 | n/a | card marked not-ready, counters stay; `net_reclaim` frees the owner slot if its device is gone (fix r2185) |
| 10 | DHCP link cycle | `user/dhcp.fi : link_watch` / `link_cycled` | **Poll** of `link_up_on` while waiting | restart DHCP when link came back | `link_lost` |
| 11 | RNDIS link state | `usbnet.fi : link_set` (`usbnet: rndis link up/down`) | RNDIS status interrupt IN | link up/down log | same |
| 12 | Display (virtio-gpu) | `drv/gpu/vgpu.fi : ereignis_pruefen` called from `gfx/gfx.fi : gpu_event` (idle task) | **Poll** of `G_EVENTS_READ` (device-driven `EVENT_DISPLAY`); not from timer because `GET_DISPLAY_INFO` waits | `vgpu.relayout` (extend) or follow host size via `vmode` ; `wm.heads_sync` | head scanout switched off, same path |
| 13 | Display (VMSVGA/VBox) | `drv/gpu/vmsvga.fi : host_pending` (`VMM_EVENT_DISPLAY`), `gfx.fi : gpu_event` | **Poll**, rate limited | `vmode.follow_host` | n/a |
| 14 | Display test bed | `vgpu.hot_toggle`, `wm.hd_demo` (`hdhot`) | boot word | forced head flip | forced head flip |
| 15 | Real HDMI/DP, EDID on HW | — | **none**: no i915/amdgpu driver (G-012) | — | — |
| 16 | HDA headphone jack | `drv/snd/hda.fi` : `GCTL_UNSOL` constant only; `V_GET_PINSENSE` used by the HDMI report only | **none**: unsolicited responses never enabled, jack state never sensed | — | — |
| 17 | AHCI/SATA/NVMe | `drv/blk/ahci.fi` (PCS repair at init only) | **none** at run time (no PxIS.PCS / CPDS handling) | — | — |
| 18 | PCI / PCIe | `bus/pci.fi` scan at boot; `diag/hw.fi` comment lists PCIe hotplug as a planned ACPI purpose event | **none** | — | — |
| 19 | ACPI events | `acpi/acpiev.fi` (lid, AC adapter `Notify`, battery) | SCI IRQ | `lid_state`, `ac_online`, battery -> taskbar | same |
| 20 | Driver Store binding | `bus/drvstore.fi : bind_all` (from `init`), `bind_pci`, `best_pci`, `best_usb`, `best_simple`, `best_acpi` | **boot only**; `best_usb` exists but has no caller | — | `release_binds` / `unload_pkg` only on `drvctl` command |
| 21 | Class layer | `bus/drvclass.fi` (`CLS_NET_ETH ... CLS_CAMERA`, hit counters), `drv/net/netclass.fi`, `block/blockclass.fi` | static tables | — | — |
| 22 | Ring 3 notification | `bus/bus.fi : noti_post` (text), consumed by `user/taskbar.fi` toast via `wlibc.noti_peek` | bus counter polled by taskbar | text toast `usb+ ...` | `usb- ...` |
| 23 | Ring 3 media table | `SYS_WECHSEL` 1704 (`WX_COUNT/DEV/MNT/BLOCKS/PATHCH/EVENTS/KOMMT/GEHT/AUS`), Explorer `carrier_read`, `/proc` mnt stat | Explorer re-reads on F5 / timer | drive appears | drive disappears |
| 24 | Diagnostics | `drv/usb/usbdiag.fi : event/log`, `fs/procusb.fi` (`/proc/usb`), gates `tools/hotplug`, `tools/usbhot` | — | PSC ring (`ev_port/ev_psc`) | same |
| 25 | Wi-Fi | `net/wlan_net.fi`, `drv/net/iwl*.fi` | PCI device bound once | — | — |

Findings that drive the design:

- **No kernel-wide event concept.** Each source has its own counter (`S_MSCGEN`, `S_MSCWEG`, `S_HOTPLUGS`, `S_PENDN`, `vgpu.S_EREIG`, `usbnet` link) and each consumer re-polls the counter it knows.
- **The only Ring 3 path is a free-text notification** (`usb+ /medien/usb0`). It carries no class, no id, no add/remove/change type; the taskbar cannot tell a NIC from a stick.
- **USB NIC add has no event at all**: it is noticed through `netdev.late_usb` polling (item 8), which is why a dongle plugged after boot only worked after the r2185 fixes.
- **The xHCI PSC interrupt is already delivered and ignored** (item 2); the 250 ms timer poll does the work.
- **Driver Store binds at boot only** (item 20). `best_usb` has no caller, so no USB class module can be bound at add time.
- **HDA jack, SATA, PCIe: no run-time detection exists.**

## 2. Design

### 2.1 Event structure (`kernel/bus/uevent.fi`)

Fixed 64-byte record, all fields `u64`:

| Offset | Field | Meaning |
|---|---|---|
| 0 | `seq` | global sequence, starts at 1, never wraps in practice |
| 8 | `tick` | `kstate.TICKS` at post time |
| 16 | `action` | `ACT_ADD=1`, `ACT_REMOVE=2`, `ACT_CHANGE=3` |
| 24 | `class` | `drvclass.CLS_*` (`NET_ETH`, `NET_WLAN`, `BLOCK`, `AUDIO`, `INPUT`, `DISPLAY`, `SERIAL`, `CAMERA`) plus `CLS_TYPEC=9`, `CLS_JACK=10` (appended; `CLS_COUNT` grows) |
| 32 | `bus` | `BUS_USB=1`, `BUS_PCI=2`, `BUS_HDA=3`, `BUS_DISPLAY=4`, `BUS_ACPI=5`, `BUS_UCSI=6` |
| 40 | `ids` | `vid<<16 | pid` for USB, `ven<<16 | dev` for PCI, else 0 |
| 48 | `path` | bus-specific location: USB `root_port<<16 | route`, PCI bdf, HDA `cad<<8 | nid`, display head number |
| 56 | `arg` | class-specific: block `DEV_USB0+n`, net card index, display `w<<16 | h`, jack `1 = plugged` |

Text form (serial log, `/proc/uevent`): `uevent: <seq> <add|remove|change> class=<name> bus=<name> ids=<vvvv:pppp> path=<hex> arg=<hex>`.

### 2.2 Queue in the kernel

- One global ring `static mut` in `uevent.fi`: 64 records (4 KiB), index `seq % 64`. Producers never block; overwrite counted in `dropped`.
- `post(action, class, bus, ids, path, arg) -> seq` is IRQ-safe: fills the slot, then publishes `seq` last (single writer per call under the same short `take`/release spinlock idiom as `bus.noti_post`). Allowed from IRQ and from task context; **no allocation, no waiting**.
- Event sources do the same split as today: the IRQ/timer only marks, the task-context worker (`hotplug_work`) does the slow work and then posts the event. The event is posted AFTER the state change (device usable on add; already torn down on remove), so a subscriber that reacts sees the final state.
- Consumers keep their own cursor (`next_seq`); `read(cursor, out) -> n` copies records with `seq >= cursor`, reports a gap if `cursor` is older than `seq - 64`.

### 2.3 Subscription API

| Consumer | Mechanism |
|---|---|
| Kernel drivers / managers | `uevent.subscribe(class_mask, handler)` — table of 8 handlers called synchronously from the posting worker (task context only; IRQ posts are queued and drained by `uevent.dispatch(state)` from the desktop loop and `kmain` console loop, next to `hotplug_work`). Handlers: Driver Store binder, `wechsel`, `netdev`, audio route, `wm.heads_sync`. |
| Ring 3 (Explorer, taskbar, tray, settings) | (1) `/proc/uevent`: text ring snapshot, cursor in the open file so `read` returns only new lines; (2) Action Bus / RPC topic `device.event` carrying the same text line; (3) the existing text notification stays for the toast (`usb+ ...`), generated FROM the event by `wechsel` as today until Ring 3 renders from the topic. No new syscall in the MVP. |
| Tests / gates | serial line `uevent: ...` printed by `post` when word `uevlog` is set; `/proc/uevent` read from the guest. |

### 2.4 Class -> Driver Store tables

The bind step moves from boot-only to event-driven:

| Class | Event source | Match function (exists) | Bind | Release on remove |
|---|---|---|---|---|
| `NET_ETH` (USB NIC) | USB attach in `hotplug_work` | `drvstore.best_usb(vid, pid)` (no caller today) then built-in `usbnet.attach_*` chain as fallback | `usbnet.attach*` / store module | `usbnet.unplug_slot` + `net_reclaim`, then `netdev` re-probe |
| `BLOCK` (USB MSC) | USB attach | built-in `usbmsc_class` ; store lookup for exotic bridges | `wechsel.kommt` mounts | `wechsel.geht` unmounts |
| `NET_WLAN` (USB Wi-Fi dongle) | USB attach | `best_usb` | store module | `drvstore.release_binds` |
| `DISPLAY` | vgpu EVENT_DISPLAY / VMSVGA hint (later: HPD + EDID) | static | `vgpu.relayout` | head off, `wm.heads_sync` |
| `AUDIO` (jack) | HDA unsolicited response (new) | pin config / `V_GET_PINSENSE` | `audio.set_route(headphone\|speaker)` | route back to speaker |
| `INPUT` | USB attach (HID) | `usb.fi` class bind | `usb.S_KBD/S_MOUSE` | cleared in `unplug_dev` |
| PCI (`best_pci`) | PCIe hotplug (future) | `best_pci` | `bind_pci` | `release_binds` |

Rule: the binder is ONE subscriber (`drvstore.on_uevent`) that handles `ADD` by running the class' match function and `REMOVE` by `release_binds`. Chip drivers do not call each other.

### 2.5 Sources: interrupt first, poll with budget

| Source | Target trigger | Fallback / budget |
|---|---|---|
| xHCI root ports | `T_PORT_EVENT` in `xhci.handle` sets `S_PEND` bit directly (extend the existing handler with the port id from TRB bits 31:24) | keep the 250 ms PSC read as safety net (1 MMIO read per port) |
| USB hubs | hub status-change interrupt endpoint (bitmap IN, one transfer per hub) sets `S_HUBDUE` for that hub | keep 2 s / 10 s rescan as net |
| HDA jack | enable `GCTL_UNSOL`, set unsolicited response on the jack pin (`SET_UNSOLICITED_RESPONSE 0xF08`), RIRB handler decodes tag -> `post(CHANGE, JACK)`; sense via `V_GET_PINSENSE` | QEMU `intel-hda` has no jack: gate injects through a test word |
| Display | EVENT_DISPLAY / host hint via `gpu_event` (idle task) | real HW: HPD IRQ + EDID read when a GPU driver exists (G-012) |
| UCSI (USB-C alt mode) | ACPI `Notify` on the UCSI device in `acpiev.fi` -> `post(CHANGE, TYPEC)` | not present on HP EliteBook x360 1030 G2 in the current tree; no work until probed on HW |
| SATA/NVMe | AHCI `PxIS.PCS`/`CPDS` | skipped: not needed for the Boss targets |

### 2.6 Migration of the existing single cases

| Step | Change | Risk |
|---|---|---|
| M1 | Add `uevent.fi` (ring, post, text, `/proc/uevent`). No behaviour change. | none |
| M2 | `usb.fi : attach_at` end -> `post(ADD, BLOCK/NET_ETH/INPUT)`; `unplug_dev` -> `post(REMOVE, ...)` with `vid/pid/port`. | low (log + ring only) |
| M3 | `wechsel` and `netdev.late_usb` become subscribers of `uevent` instead of polling `S_MSCGEN/S_MSCWEG` / `usbnet.exists`; counters stay for gates. | medium |
| M4 | `drvstore.on_uevent` binds `best_usb`; unload on REMOVE. | medium (needs a USB module in the store; none exists yet) |
| M5 | `vgpu`/`vmsvga` post `CHANGE DISPLAY` from `gpu_event`; `wm.heads_sync` subscribes. | low |
| M6 | xHCI PSC IRQ marks `S_PEND` directly; timer poll stays. | medium (IRQ context rules) |
| M7 | HDA unsolicited jack + audio route switch. | medium (needs HW proof) |
| M8 | Ring 3: Action Bus topic `device.event`, taskbar/Explorer/netview subscribe; remove the text parsing of `usb+`. | medium |

### 2.7 Gates

- `tools/hotplug/events.sh` (new): QEMU monitor series, per class: USB stick `device_add/device_del` x3, USB NIC (`usb-net`) x3 on root port and behind a hub; checks serial `uevent:` lines (add/remove pairs, strictly increasing `seq`, correct class/ids), `/proc/uevent` content from the guest, counter `dropped=0`. Counter-proof: old kernel (`nouevent`) prints none.
- Existing gates stay green: `tools/usbhot/replug.sh`, `tools/usbhot/run.sh`, `tools/hotplug/run.sh`.
- HDMI/jack/real dongle/real stick: only provable on the HP. One bundled `project_needs` after the build exists.

## 3. Status of this document

- Phase 1 (inventory) and phase 2 (design): done in this file.
- Phase 3 (MVP M1+M2): see the worker report `reports/20261028-W-HOTPLUG.md` for what was built and measured.
