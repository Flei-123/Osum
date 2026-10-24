# DRIVER-CLASSES — one interface per device class (W-CLASSES, 24.10.2026)

Boss decision 24.10.2026: universal class layer per device type; chip drivers below only translate into that interface. Step 1 = inventory + design. Base: main `8d432803`. Every signature below was read from the tree; nothing here was run unless section 7 says so.

## 1. Findings that shape the design

- **Seven de-facto class layers already exist**, each with a different mechanism: `kernel/net/netdev.fi` (if-chain on `KIND_*`), `kernel/block/blkdev.fi` (if-chain on `KIND_*`), `kernel/drv/snd/audio.fi` (`hw_*` if-chains hda/ac97), `kernel/drv/hid/hidin.fi` + `hidrep.fi` (one report path), `lib/wlan/device.fi` (function-pointer table), display (no layer, `gfx.fi bild_fertig` picks driver by `usable`/`is_ready`), serial (`kernel/drv/con`).
- **The idiom for a real table already exists:** `struct Ops { f: fn(u64,..)->u64 }` + `fn ops() -> Ops` per driver + `ops_of(kind)` (`kernel/fs/vfsops.fi`, `ofs.fi`, `vfs.fi`), and `Tafel` in `lib/wlan/device.fi`. Firn stage 0 can call a struct field, not convert a pointer to a number. The class layer should reuse exactly this idiom.
- **`kernel/bus/drvreg.fi` registers only match rows** (25 rows: bus, vendor, device, class, prog-if, ACPI HID). It has **no probe/remove and no class column**. `mark_ok`/`mark_fail` exist but `grep -rn mark_ok kernel` finds **no caller**, so `/proc/drivers` can only say `seen`/`absent` for built-ins; `bound`/`failed` come only from the Treiber-Store (`drvstore.fi`).
- Store modules get a device context page (`state+0xAA800`, `DRIVER-STORE.md` §5) and a signed `driver.inf`; the manifest has no class key, so a module cannot say what interface it implements.

## 2. Today's interface per class (real signatures)

All `state: u64` first (data region). `u` = unit number inside the driver, `c`/`i` = card/disk number in the dispatcher.

### 2.1 net-eth — `kernel/net/netdev.fi` (1563 lines)

Dispatcher chooses by `KIND_VIRTIO=1, E1000=2, R8169=3, I219=4, USBNET=5, WLAN=6`. `driver_for(ven,dev,rev)->kind` is the match table, `reason_for` names recognised-but-undriven chips, `probe` walks PCI class 02:00 and fills 8 card slots (`MAX_CARDS=8`, only cards 0/1 get an IRQ vector, `IRQ_CARDS=2`). 44 `r8169.` references and ~30 `if k == KIND_x` chains.

Core set every driver exports (identical names/signatures in `e1000.fi`, `r8169.fi`, `usbnet.fi`, `wlan_net.fi`, virtio-net in `kernel/drv/net/virtio.fi`):

```
present_on(state,u)->bool  ready_on  up_on  link_up_on  poll_on(state,u)->bool
mac_at_on(state,u,i)->u64                    rx_take_on(state,u,frame:*mut u64,slot:*mut u64)->u64
rx_recycle_on(state,u,id)                    tx_room_on(state,u)->u64
tx_frame_on(state,u,src,n)->bool             rx_frames_on tx_frames_on tx_drops_on rx_octets_on tx_octets_on (state,u)->u64
init_on(state,u,use_msix:bool,armed:bool,vec:u64)->bool     irq_on(state,u)     shut_down_on(state,u)
```

| Chip driver | Extras beyond the core | Where it differs |
|---|---|---|
| e1000 / I217 / I219 (`e1000.fi`, 2755 l.) | `hwstat_on`, `kill_on`, `resume_on` (S3), `irq_mode_on`, `warn_on`, `step_on`, `storm_on`, `phy_id_on`, `swflag_on`, `txprobe_on`, `link_speed_on`, `msix_on` | only driver with suspend/resume and raw register stats; `MAX_UNITS` 2; two `KIND`s (E1000, I219) for one file |
| r8169 (`r8169.fi`, 1484 l.) | `rx_errors_on`, `oversize_on`, `rx_overflow_on`, `selftest_on`, `print_regs_on`, `variant_of(dev)`; `irq_kind` hard-coded `1` (pin) in netdev | no suspend/resume; chip variants (8139C+, 8168, 8125) decided by `variant_of`, not by the dispatcher |
| virtio-net (`drv/net/virtio.fi`, moved from drv/blk) | `features_on`, `queue_size_on`, `notified_on`, `msix_on` | `MAX_CARDS=2` |
| USB ECM/RNDIS/NCM/CH397/AX88772 (`drv/net/usbnet.fi`, 715 l.) | `attach`, `attach_rndis`, `attach_ncm`, `attach_ch336`, `attach_ax88772`, `detach`, `unplug_slot`, `link_on`, `exists`, `keepalives` | **push model**: `usb.fi` enumerates and calls `attach*`, netdev only polls `exists` (`late_usb`); `MAX_UNITS=1`; always polled; hot-unplug exists; chip protocol is in `lib/usbnet/{ch397,ax88772,ncm,rndis}.fi` (`tx_wrap`, `rx_next`, `rx_frame_off`, `rx_frame_len`, `supported`) and chosen inside `usbnet.fi` by `rx_take_on` -> `rndis_next`/`ncm_next`/`ch_next`/`ax_next` |
| WLAN (`net/wlan_net.fi`) | `exists`, `set_mac`, `set_link`, `rx_offer`, `tx_take`, `tx_pending` | one-slot ring buffers pumped by a kernel task; no PCI place |

Gaps: no `probe/remove` per driver, no error codes (everything `bool`/`0`), no link-change event (callers poll `link_up_on`), unit limits and IRQ vector limits live in the dispatcher, `hwstat_on`/`kill`/`resume` are special-cased for e1000.

### 2.2 net-wlan — `lib/wlan/device.fi` + `kernel/drv/net/iwl*.fi`

```
struct Tafel { send: fn(u64,u64,usize)->i64, receive: fn(u64,u64,usize)->i64,
               channel_set: fn(u64,u64,u64)->i64, key_set: fn(u64,u64,u64,u64,usize)->i64 }
struct Device { tafel, ctx, adr:[u8;6], channel, band, kann_ccmp:bool, ready:bool, n_gesendet, n_empfangen, n_verworfen }
```

This is the only class interface that is already a real pointer table with `i64` errors and a capability flag (`kann_ccmp`). Implementations: `testdevice.fi` (fake), Intel (`iwl.fi` + `lib/wlan/iwl_*.fi`), Atheros (`lib/wlan/ar9271.fi`, `htc.fi`). Firmware loading, queues and power are deliberately outside the table. Bridge to the IP stack: `wlan_net.fi` (KIND_WLAN).

### 2.3 block — `kernel/block/blkdev.fi` (752 l.) over `kernel/block/blk.fi`

Dispatcher: `KIND_NVME=1, AHCI=2, USB=3, ATA=4`; `driver_for(cls,sub,pif)`, `probe`, `init_on/present_on/blocks_on/bsize_on/read_on/write_on/flush_on(state,i,..)`. Reads/writes go through the older block layer `blk.read_on(state,dev,lba,dst)->bool` / `write_on(state,dev,lba,src)->bool` with fixed device numbers (`DEV_ATA=1, NVME=2, ATA1=3, USB=4/6/7/8, AHCI=5`) and a 512-byte block (`BLOCK_SIZE`), cache + write-back in `blk.fi`.

| Driver | Signatures |
|---|---|
| NVMe `drv/blk/nvme.fi` | `init(state,use_msix,armed)->bool`, `present`, `ready`, `blocks`, `read_block(state,lba,dst)`, `read_block_ns(state,i,lba,dst)`, `write_block`, `read_many(state,lba,count,dst)`, `flush`, `kill`, `resume`, `block_shift` |
| AHCI `drv/blk/ahci.fi` | `init(state)->bool`, `present`, `ready`, `blocks`, `read_block`, `write_block`, `read_many`, `write_many`, `flush`, `kill`, `resume`, `block_shift`, `mode`, `ports_seen` |
| USB mass storage `usb/usb.fi` | `msc_ready`, `msc_blocks`, `msc_bsize`, `msc_read_at(state,i,lba,dst)`, `msc_write_at`, up to 4 devices (`msc_slot`, `msc_count`), hot-plug through `block/wechsel.fi` |
| ATA PIO/DMA `blk.fi` | `ata_read_on`, `ata_write_on`, `identify`, `present`, `flush`; two drives (slave flag) |

Differences: NVMe has namespaces, AHCI sees one port, USB has up to 4 removable devices, ATA is PIO; `write_many` only AHCI; `flush` only NVMe/AHCI (others return `true`); `block_shift` allows non-512 sizes but `blk.fi` assumes 512. virtio-blk has a `drvreg` row (`D_VIRTIO_BLK`) but no `KIND` in `blkdev.fi` (not checked further).

### 2.4 audio — `kernel/drv/snd/audio.fi` (2085 l.)

`audio.fi` states the boundary itself ("six things a driver provides"); in code 14 `hw_*` functions dispatch `hda` vs `ac97`:

```
hw_ready(state)->bool  hw_ring(state)->u64  hw_ring_frames  hw_entry_frames  hw_entries
hw_submit(state)->bool  hw_start(state)->bool  hw_stop(state)  hw_position(state)->u64 (frames, monotonic)
hw_volume(state,pct)  hw_running(state)->bool  hw_drain_mark(state) (HDA only)  hw_rate(state)  hw_set_rate(state,hz)->bool
```

Above it: `mix.fi` (streams: `open(state,pid,hz)`, `write(state,i,src,frames)`, per-stream volume/mute), `mic.fi` (capture policy). Differences: AC97 DMA stops at the last valid entry, HDA loops (`hw_drain_mark` added); capture exists only in `hda.fi` (`cap_*`: `cap_open`, `cap_read`, `cap_poll`, ...), jack/pin routing is HDA-internal (`cap_pin_*`); `ac97.fi` has no capture.

### 2.5 input — `kernel/drv/hid/*`

Three transports, one report path:

| Transport | Entry | Common path |
|---|---|---|
| USB HID (`usb/usb.fi`, `drv/usb/ohci.fi`) | interrupt-IN | `hidrep.parse(state,dev,buf,len)->u64` (E_OK) once per device, then `hidin.report(state,dev,buf,len)->bool` per report |
| I2C-HID (`hid/i2chid.fi`) | `poll`, `probe_all`, `probe_aml` | same two calls; device numbers `I2C_DEV_FIRST=3`, `USB_DEV_MAX=3` |
| PS/2 (`hid/kbd.fi`, `ps2m.fi`) | `kbd.irq`, `ps2m.irq` | **own path**: `kbd.on_code(state, scancode)`; mouse state `ps2m.x/y/buttons/wheel` |

Sinks are not an interface: keys end as set-1 scancodes in `kbd.on_code`, pointer data in the `ps2m` state (`MOUSE_OFF`), hot keys via `kbd.push_hot`. Gaps: PS/2 bypasses `hidin`; no per-device descriptor (name, caps) visible to user space; hot-plug only for USB.

### 2.6 display — `gfx/gfx.fi`, `drv/gpu/*`

No class layer. `ui/kgui.fi` init order: `vgpu.init` > `vmsvga.init` > firmware framebuffer; `gfx.bild_fertig` branches `vgpu.usable` / `vmsvga.is_ready`. Surface actually used:

```
vgpu:   init(state)->bool usable present(state)->bool resize(state,w,h)->bool scanout_w/h head_* ext_* say shut_down
vmsvga: init is_ready present resize(state,w,h) resized set_mode(state,w,h) width height pitch fb_phys vram_bytes cursor_* shut_down panic_present
fb:     firmware (GOP) framebuffer, no mode-set; vmode.fi set_mode(state,w,h,bpp) calls vmsvga.resize
```

Differences: virtio-gpu has transfer+flush with multi-head/EDID, VMSVGA has UPDATE rectangles and a hardware cursor, GOP has neither mode-set nor present. No Intel/AMD driver (r36).

### 2.7 serial / camera

Serial: `drv/con/{sercon,odbuart,tty,ansi}.fi` (UART console, ODB agent port, tty layer) — put/get byte plus IRQ; no registry row. Camera: no driver (`tools/xhciiso` isochronous test, `tools/uvc`, `lib/uvc` host code only). Both are listed as classes so the manifest key is reserved; no interface is proposed beyond `probe/remove`.

## 3. Proposed common interface

### 3.1 Shape

One struct of function pointers per class (idiom of `vfsops.Ops` / `Tafel`), returned by `fn ops() -> <Class>Ops` in a small adapter file per chip, selected by `ops_of(kind)` or by the registry row. Every class struct starts with the same header fields:

| Field | Meaning |
|---|---|
| `probe: fn(state, ctx) -> i64` | `ctx` = device context page (same layout as `DRIVER-STORE.md` §5). 0 = bound, `< 0` = error code |
| `remove: fn(state, unit) -> i64` | callable at any time; afterwards every op returns `E_GONE` |
| `suspend / resume: fn(state, unit) -> i64` | optional (bit in `caps`); today `kill_on`/`resume_on` (e1000), `nvme.kill/resume`, `ahci.kill/resume`, `hda.kill/resume` |
| `caps: u64` | capability bits, class-specific, plus common `CAP_HOTPLUG`, `CAP_SUSPEND`, `CAP_IRQ`, `CAP_DMA` |
| `tag: u64` | 8-byte name packed little-endian (as `vfsops.Ops.tag`) |

### 3.2 Errors

Common negative `i64` codes (same on all classes): `E_NODEV -19`, `E_BUSY -16`, `E_IO -5`, `E_TIMEOUT -110`, `E_NOTSUP -95`, `E_INVAL -22`, `E_GONE -108`, `E_NOMEM -12`. `bool` returns stay as thin legacy wrappers during migration. One boot/serial line per failed `probe`: `drv: <name> probe failed <code>` (extends the existing `nic: init failed: e1000 step N` style).

### 3.3 Events and hot-plug

Class drivers post to the system bus (`kernel/bus/bus.fi`): `DEV_ADDED`, `DEV_REMOVED`, plus class events `LINK_CHANGED` (net), `MEDIA_CHANGED` (block), `ROUTE_CHANGED` (audio jack), `MODE_CHANGED` (display). Polling stays as fallback. Rule from `usbnet.unplug_slot`: the unit stays registered but not ready, ops return `E_GONE`, upper layers get `DEV_REMOVED`. PCI hot-plug stays out of scope (`DRIVER-ARCHITECTURE.md` 3.6).

### 3.4 Rights

A class implies a minimum right set, checked against the manifest `rights=`: net-eth/net-wlan `pci-cfg,mmio,irq,dma` (+`fw` for wlan), block `pci-cfg,mmio,irq,dma`, audio `pci-cfg,mmio,irq,dma`, input `irq` (+`usb` or `acpi`), display `pci-cfg,mmio`, serial `mmio` or port I/O, camera `usb,dma`. Upper layers (netd, vfs, mixer, window server) call only the class struct, never the chip module; user space reaches devices through the existing nodes/syscalls with their existing capability checks.

### 3.5 Per class: required ops and capability bits

| Class | Required (maps to today) | Optional / capability bit |
|---|---|---|
| **net-eth** | `present ready up init shut_down irq poll rx_take rx_recycle tx_room tx_frame mac_at link_up` + `stat(state,u,id)` (ids `RX_FRAMES TX_FRAMES TX_DROPS RX_OCTETS TX_OCTETS RX_ERRORS`) | `link_speed` (CAP_SPEED), `info(state,u,id)` for `BDF IDX IRQS FEATURES QUEUE MSIX NOTIFIED IRQ_KIND` (replaces 8 getters), `hwstat` (CAP_HWSTAT), `suspend/resume` (CAP_SUSPEND, e1000 only today), `CAP_MSIX`, `CAP_POLL_ONLY` (usbnet, wlan) |
| **net-wlan** | `send receive channel_set key_set` (today's `Tafel`) | `scan`, `CAP_CCMP` (= `kann_ccmp`), `CAP_FW_LOAD`, `CAP_POWERSAVE`; fed to the IP stack through a net-eth adapter (`wlan_net.fi`) |
| **block** | `present blocks block_size read(lba,count,dst) write(lba,count,src)` as multi-block calls | `flush` (CAP_FLUSH), `trim` (CAP_TRIM), `removable` (CAP_REMOVABLE, with `MEDIA_CHANGED`), `read_ns` (CAP_NS), `suspend/resume` |
| **audio** | `ready ring submit start stop position rate set_rate set_volume running` (today's `hw_*`) | `drain_mark` (CAP_LOOP_DMA), `capture_*` (CAP_CAPTURE), `jack_state` (CAP_JACK), `formats` bitmask |
| **input** | `report(state,dev,buf,len)` entry for transports + descriptor `parse`; sink `emit_key(code,flags)`, `emit_ptr(dx,dy,btn,wheel)` | `led_set`, `CAP_ABS` (touch), `CAP_PRECISION_TP`; PS/2 moves behind the same `emit_*` |
| **display** | `present(rect)`, `mode_get`, `fb_info` (phys, pitch, w, h) | `mode_set` (CAP_MODESET), `cursor_*` (CAP_HWCURSOR), `heads/edid` (CAP_MULTIHEAD), `panic_present` (CAP_PANIC) |
| **serial** | `put byte`, `get byte`, `irq` | `baud_set` |
| **camera** | `open close frame_get` | `controls` |

Gate rule for every class (extends D8): a fake device, a counter-proof where the dispatcher is bypassed, and a hardware checklist line.

## 4. Attaching to drvreg and the Treiber-Store

1. **drvreg gets a class column.** New file `kernel/bus/drvclass.fi` holds the ids (`CLS_NET_ETH=1, NET_WLAN=2, BLOCK=3, AUDIO=4, INPUT=5, DISPLAY=6, SERIAL=7, CAMERA=8`) and names; `drvreg.reg` rows get a class; `/proc/drivers` appends ` class=<name>` at the end of each row line (appending keeps the existing `grep -F` prefixes in `tools/drvreg/run.sh` valid).
2. **Built-in drivers bind through the class layer.** A class dispatcher calls `probe`; the result goes to `drvreg.mark_ok(row)` / `mark_fail(row, text)` (finally with callers), so `/proc/drivers` shows `bound`/`failed` for built-ins too.
3. **`driver.inf` gets `class=<name>`** (required for store packages). `drvinf.fi` validates it against the table above (unknown class = reject code 2 "key"), and the loader checks that the module registers an ops struct of that class (`drvclass.register(class, ops)` through a new `ksym` entry; ABI number bumps once). A package whose module registers another class is rejected.
4. **Selection order stays** (built-in claims first, then specificity/rank/version). Added rule: for a given device the class of the winning package must equal the class of the matching `pciclass` row, so a `pciclass 0200` match can only yield a net-eth driver.
5. **Remove path:** `drvctl remove/ban` calls `remove` of the live unit before the files disappear (today it only takes effect at next boot).

## 5. Reference hardware list (self-built OrientOS laptop)

Goal: every internal part is covered by one class driver with an open standard, so no chip-specific driver is needed.

| Function | Choose | Class driver | Why |
|---|---|---|---|
| Storage | NVMe M.2 SSD | block / NVMe 1.x | one standard register set; `nvme.fi` exists, QEMU-gated (`tools/metal` 72/0). Avoid SATA RAID/Intel RST modes (no driver) |
| USB | xHCI controller (no EHCI/OHCI-only) | xHCI + USB classes | REAL on silicon (`BLECH-BEREIT.md`); gives HID, MSC, ECM/NCM, UVC, audio on one controller |
| Audio | Intel HDA controller with standard codec | audio / HDA | `hda.fi` exists; codec quirks are the only chip-specific part, keep to standard Realtek/Conexant verb sets or use USB audio class |
| Display | UEFI GOP framebuffer as baseline | display (fb) | works on every UEFI board with no driver; real GPU driver is a later class implementation. Pick an eDP panel with standard EDID and PWM or ACPI `_BCM` backlight |
| Input | I2C-HID keyboard/touchpad/touchscreen (ACPI `PNP0C50`) or USB HID | input | `i2chid.fi` + `hidrep.fi` parse descriptors, no per-device driver; PS/2 only as fallback |
| Wired net | USB CDC-ECM/NCM adapter (or port on the board with an Intel e1000e-compatible NIC) | net-eth | ECM/NCM are class standards (`lib/usbnet/ncm.fi`); proprietary chips (CH397, AX88772) need their own small protocol file |
| WLAN | USB WLAN module with open firmware (e.g. Atheros AR9271 class, `lib/wlan/ar9271.fi`) as default; M.2 Intel only if firmware blobs are accepted | net-wlan | open firmware removes the blob/licence step (`DRIVER-ARCHITECTURE.md` 3.5); Intel 8265 needs FH loader + redistributed firmware, ALIVE never seen on silicon |
| Camera | UVC USB camera | camera / UVC | class standard, host code in `lib/uvc` |
| Bluetooth | USB HCI (btusb class) | later | class standard, firmware is the catch |
| Power/EC | ACPI battery/lid/AC (`PNP0C0A/0D`, `ACPI0003`), standard i8042 or ACPI EC | ACPI | AML interpreter exists |
| Firmware | UEFI with Secure Boot disable option, VT-d/IOMMU present | — | needed for ring-3 drivers later (D6/D7) |

## 6. Migration order

1. `drvclass.fi` + class column + `mark_ok/mark_fail` callers (small, visible in `/proc/drivers`).
2. net-eth adapter files (no change to chip files), then convert the dispatcher branch by branch (r8169 first, e1000, virtio, usbnet last because of parallel work).
3. block (`blkdev.fi` becomes a table; NVMe/AHCI/USB-MSC/ATA adapters; multi-block read/write signature).
4. audio `hw_*` -> struct; input `emit_*` sink with PS/2 behind it; display struct from the `vgpu`/`vmsvga` surface.
5. `class=` key in `driver.inf` + `ksym` registration entry + ABI bump.

## 7. Implementation status

Step 1 (inventory + design) is delivered by this document. The net-eth proof (`kernel/drv/net/netclass.fi`, r8169 adapter, `tools/classes/run.sh`) is **not built**: the worker ran out of context. Plan for it: `netclass.fi` defines `EthOps` and `ops_for(kind)`, a new `r8169_class.fi` returns the table over the unchanged `r8169.fi`, the 30 `r8169.` branches in `netdev.fi` call through the table, the gate boots QEMU `rtl8139` and checks traffic plus a call counter with counter-proofs (no NIC, e1000 NIC), then runs `tools/net`, `tools/rtl`, `tools/drvreg`, `tools/drvstore`, `tools/dbgtools` through `/root/jarvis/bin/heavy`. Nothing in this document was executed.
