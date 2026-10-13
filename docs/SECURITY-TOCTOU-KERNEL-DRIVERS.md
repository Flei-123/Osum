# Schrodinger's TOCTOU in the kernel drivers (W-TOCTOU-B, 13.10.2026)

Source: https://github.com/xoreaxeaxeax/schrodingers-toctou. The source reads
untrusted memory once, checks the copy, uses the copy -- and the compiler
emits an extra load of the original, so check and use see different values.
Scope here: everything a DEVICE, a guest or a hypervisor can write:
descriptor rings, completion queues, DMA buffers, USB descriptors, Rx frames.
Sibling document for the rest of the kernel: SECURITY-TOCTOU-KERNEL.md
(W-TOCTOU-A); language side: SECURITY-TOCTOU.md (Firn department).

## 1. Why the drivers are mostly safe by construction

- Every access to device-written memory in `kernel/drv/**`, `kernel/usb`,
  `kernel/bus` goes through `__mmio_read{8,16,32,64}` (directly or via
  `rd32`, `cqe`, `dsc_*`, `used_*`, `kstate.get/get8/get32`, `b8/b16`). The
  Firn IR makes these `Op::MmioLoad`: volatile, never merged, moved,
  duplicated or removed (`firn/compiler/src/fir.rs`, round 52). One source
  read = exactly one machine load. The compiler-made duplication of the
  paper cannot happen on these paths.
- Firn has no rematerialisation pass (grep in `compiler/src`: none), but it
  does have CSE/LICM/inline/mem2reg. A plain `*p` load is NOT pinned.
  So the rule is: plain pointers must never reach memory a device writes.
- What remains is the SOURCE-level double fetch: check on one read, use on
  another. The audit looked for exactly that.

## 2. Findings (risk = hostile device / hypervisor / malicious USB stick)

| ID | Where (file:line) | What | Risk | Status |
|----|-------------------|------|------|--------|
| F-01 | `kernel/net/inet.fi` pump (rx loop, ~l.575); consumers `vendor/firn/lib/net/stack.fi:360,458`, `wire.fi:337-340` (`ip_header_ok`), `tcp.fi:1191`, `kernel/net/wg.fi:563-587`, `ipc/share.fi:827`, `ebpfhook.xdp`, `netmon.frame_seen` | Rx frame was parsed IN PLACE in the DMA buffer by 7 consumers with PLAIN loads (`wire.ld8` = `*ptr`). `ip_header_ok` checks ihl/total, `ip_in`/`tcp_in` read ihl/total again. | medium (hostile NIC/hypervisor; plain loads are not pinned) | FIXED: `rx_snapshot` copies the frame once into the scratch page, all consumers see the copy |
| F-02 | `lib/crypto/chacha.fi:450-454` (`aead_open`), called from `lib/wg/proto.fi:1609 try_keypair` | verify-then-decrypt: Poly1305 over `ct`, then `chacha20(ct)` re-reads `ct`. If `ct` is the live Rx buffer, a device can change ciphertext between tag check and decryption: unauthenticated plaintext. Same for `tag_equal` reading the tag from `ct`. | medium | FIXED by F-01 (input is the private copy). Keep the rule: AEAD input must never be DMA memory |
| F-03 | `kernel/drv/usb/ehci.fi:1420` (`poll`) | qTD token read twice (`ACTIVE` test, then `ERRMASK` test). Controller writes the token. | low | FIXED: one read into `tok` |
| F-04 | `kernel/drv/blk/virtio.fi:504` (`region`) | virtio PCI capability `offset` (config space, device chosen) is added to the BAR with no check against `cap.length` / BAR size; result goes to `apic.map_device`. Not a double fetch, a missing bound. | low-medium | FIXED (13.10., BAR size bound in `region`) |
| F-05 | `kernel/usb/usb.fi:1407,1501,2989` (`best_rang`, `parse`, `first_iface`) | descriptor walk checks `at + 2 <= total` but not `at + len <= total`; a device-chosen `bLength` makes `take_ep` read up to 255 octets beyond `total` (inside `state`, not out of the kernel). Three passes over the same DMA buffer (device is done by then, so not racy). | low | FIXED (13.10., `at + len > total` stops the walk in best_rang/parse/first_iface) |
| F-06 | `kernel/usb/usb.fi:1308-1325` (`configure`) | configuration descriptor fetched twice (9 octets, then `wTotalLength`); only the FIRST `total` is used, clamped to 512, and the second pass is bounded by it. Classic double fetch, handled correctly. | none | ok, keep |
| F-07 | `kernel/drv/blk/virtio.fi:879` (`rx_take_on`), `l.920` (`tx_room_on`) | `used.id` is only `% QSIZE`, not checked against "was posted"; a device can return one buffer twice or move `used.idx` arbitrarily (inflight wraps to a lie). `len` is read once and bounded (`12 < len <= BUFSZ`). | low | FIXED (13.10., used.idx distance clamp + posted bitmap S_RXPOST) |
| F-08 | `kernel/drv/gpu/vgpu.fi:839-844` | display size `w`,`h` from the device response, stored without upper bound. | low | FIXED (13.10., w/h capped at 16384) |
| F-09 | `kernel/drv/usb/xhci.fi:605-630` (`drain_inner`/`handle`) | `c3` read once, `st` read once more from the same TRB (different dword; ordered because both are volatile; no `barrier_read` between them -- fine on x86, needed on AArch64). Residual is checked `resid <= len` before use (`xhci.fi:1268,1303`). | low | ok on x86; add `arch.barrier_read()` when AArch64 xHCI is used |

## 3. Checked and clean (one read into a local, then only the local)

- `drv/blk/nvme.fi` `cqe(...,3)` -> `d3` (phase+status from one read), `drain`, admin path. Identify data read byte-wise once each.
- `drv/net/e1000.fi:1086` `rx_take_on` (`st`, `len`, `err` are locals; DD then barrier then len), `r8169.fi:1000` (`dw0` one read, len from `raw`), `virtio.fi:860` (`last`/`now`/`id`/`len` locals).
- `drv/blk/ahci.fi` (PxCI/PxTFD/PxIS are register reads, results in locals; identify words one read each).
- `drv/snd/hda.fi:870-880` RIRB (`resp`, `ex` one read each), position buffer `kstate.get32(dpib)` read once and `% RING_OCTETS` (`hda.fi:2008`).
- `drv/snd/ac97.fi:960-965`: CIV/PICB/CIV read, retried on change -- the correct way to handle a torn read.
- `drv/usb/xhci.fi` event ring: result code and residual copied into the endpoint record in `handle`; callers use the record.
- `drv/hid/hidin.fi:540-560`: report id read once, size checked against the parsed descriptor before the field extraction; `i2chid.fi:361` firmware buffer walk bounded by `len`.
- `bus/pci.fi:378` and `virtio.fi:466` capability chains: bounded by `guard < 48`.
- `kernel/net/wg.fi:553 rx_hook`: `hl`, `ulen`, `blen` locals, bounds checked against `n` (the snapshot length). `proto.try_keypair`: `ctr` read once and used for nonce and replay check.

## 4. What was changed

- `kernel/net/inet.fi`: `rx_snapshot(state, src, n)`; `pump` calls `frame = rx_snapshot(state, frame, len)` right after `rx_take`. Cost: one pass of 4-octet copies (<= 512 steps per frame). Invariant: every driver bounds `len <= BUFSZ = 2048`, the scratch page is 4096; transmit reuses the page only after the Rx loop.
- `kernel/drv/usb/ehci.fi`: `poll` reads the qTD token once.

## 5. Rules for new driver code

1. Device memory only through `__mmio_*` (or a wrapper); never `*p` or struct fields.
2. One read -> one local -> check AND use the local. No second call of the same accessor on the same address.
3. Lengths, indices, offsets from the device are bounded against OUR size at the point of use.
4. Anything that verifies and then consumes (MAC, signature, checksum, length) gets a private copy first.
5. A retry loop on a changing value (ac97 CIV/PICB) is fine when the second read is meant to compare.

## 6. Open

- F-04, F-05, F-07, F-08: fixed (13.10., W-TOCTOU-C, no dedicated device-side test: the values are chosen by the device; regression via the net/hid/hotplug gates).
- The `firn` language item (`read_once`/`snapshot` primitive and a lint for plain pointers into DMA memory) belongs to docs/SECURITY-TOCTOU.md; when it lands in main, `rx_snapshot` and F-05's bound should use it.
- Not covered line by line: `kernel/block/*` (partition tables, on-disk data -- not racy but untrusted), `kernel/drv/con/*` (UART/PS2 port I/O, no DMA), the ebpf verifier (user programs, not device memory).
