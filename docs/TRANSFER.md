# The transfer service

One service moves data between programs: the **clipboard** (with history), the **primary selection**
(select to copy, middle click to paste) and the **drag payload**. They are three *slots* of the system bus
(`docs/SYSTEMBUS.md`) with one item format and one set of functions.

| file | role |
|---|---|
| `kernel/bus/slots.fi` | the slots: set / offer / fill / get / clear / promote, mime names, owner clean-up |
| `kernel/bus/bus.fi` | the bus page, the lock, the segments (`seg_adopt`, `seg_release`, `seg_span`) |
| `kernel/sys/sys.fi` (`do_bus`) | the system call door, rights check, copy to and from Ring 3 |
| `kernel/user/xfer.fi` | the one API for programs (terminal and window programs alike) |
| `lib/urilist.fi` | text/uri-list: `file://` and `smb://` to paths and back (kernel and Ring 3) |
| `kernel/user/xclip.fi` | command line door and test tool (`/bin/xclip`) |
| `kernel/user/cliphist.fi` | the history popup (Win+V) |

## Item model

An item has an owner (pid, uid), a **type mask** (what is offered), a **held mask** (what is in memory right now),
a length and a blob. The blob is inline (up to 192 octets) or lives in a **segment** (up to 2 MiB).

* **Eager** (`xfer.set`): the blob is there; the held mask equals the type mask.
* **Lazy** (`xfer.offer` then `xfer.fill`): only the types are announced. The first reader of a type that is not held
  gets `AGAIN`, the kernel marks the item as wanted *for that type*, the owner's `xfer.pump()` (called by
  `wlib.step` for every window program) asks the registered provider, the provider calls `xfer.fill`. Nothing is
  produced before somebody pastes (`offers` and `fills` counters of `xclip stat`). One representation is held at a
  time; asking for another type asks the owner again.
* Segments given to the service are **adopted** (owner `ADOPT_PID`): they survive the exit of the program that
  copied, and are freed when the item leaves the ring, is replaced or cleared (`adopted` equals `freed` when
  everything is cleared). Readers copy with `BUS_SEGIO` in chunks; they map nothing, so no address space is used up.
* A reader checks the item's sequence number after copying a segment and starts again when it moved.
* If the owner dies, a lazy item that was never filled disappears; a filled one stays with the held type only.

## Slots

| slot | `xfer.SEL_*` | depth |
|---|---|---|
| clipboard | `SEL_CLIPBOARD` | ring of 20, newest is back 0 |
| primary selection | `SEL_PRIMARY` | one item |
| drag payload | `SEL_DRAG` | one item, emptied on drop or Esc |

The drag slot used to overlap the first notification slot (96 octets): every drag zeroed the head of
notification 0. The slots now sit in their own parts of the bus page (`DRAG` 0x7500, `PRIMARY` 0x7E00,
mime names 0x7F00); `xclip noti` plus `drag` in `tools/xfer/guest.sh` measures it.

## Types

`text/plain` (bit 0), `text/x-osum-path` (bit 1, one path as text), `text/html` (2), `image/png` (3),
`text/uri-list` (4). Bits 32..39 are **custom types** by name (`application/x-...`): `xfer.mime_of(name)` registers a
name on first use (8 names, 31 octets each), every program gets the same bit. Parameters after `;` are ignored.
The explorer marks a cut with `application/x-osum-cut` next to `text/uri-list`.

Readers negotiate with `xfer.negotiate(sel, back, accept_mask)` (lowest bit wins) or ask for a type directly.
`xfer.get_text` falls back from text to path to a file list (converted to one path per line);
`xfer.get_files` returns a uri-list for both file-list and single-path items.

## API (`kernel/user/xfer.fi`)

```
set(sel, mask, p, n)          eager, any size up to SIZE_MAX (2 MiB)        -> n or error
set_text(p, n)                clipboard text
set_file(sel, mask, path)     eager, streams a file into a segment
offer(sel, mask)              lazy; provide(sel, fn(sel, mime)) registers the provider
fill(sel, mime, p, n)         called by a provider
get(sel, back, mime, dst, max) -> total length (copies at most max); waits for a lazy owner (3 s)
get_text / get_files / get_to_file
types / have / count / owner / seq / length
clear(sel)                    drops the newest item (primary, drag: the item)
promote(back)                 moves a history entry to the front without copying its data
pump() / flush()              serve wanted types / materialise unfilled offers (call at exit)
drag_start / drag_get / drag_active / drag_types / drag_end
mime_of / mime_name / mime_custom
```

`ulib.clip_*`, `ulib.drag_*`, `wlibc.clip_*`, `wlibc.drag_*` and `wlib.clip_*` are thin wrappers over this file.

## Programs

* terminal (kernel window server): copy, paste and middle click paste (primary first, clipboard otherwise) go through
  `slots.put_kernel` / `slots.get_kernel`; a pasted file list becomes space separated paths
* fUi text areas (`fuied`): Ctrl+C/X/V, selection by mouse sets the primary selection, middle click pastes it at the click
* explorer: Ctrl+C/X publishes `text/uri-list` (cut adds the custom cut type); Ctrl+V reads the clipboard, so a list
  copied by another program works; drag and drop moves with `expakt.stage` and no longer touches the clipboard
* image viewer: Ctrl+C offers `image/png` lazily and encodes only when somebody pastes (and at exit, `xfer.flush`);
  Ctrl+V takes `image/png` or the first file of a list
* screenshot tools: the PNG of the screenshot goes to the clipboard as `image/png`
* Win+V (`cliphist`): text rows as before, other types as `[mime]` rows; picking a non-text row promotes it
* Wayland clients (`wl_data.fi`): text, asks for `text/plain` only, so an image offer is never triggered by polling

## Rights

Writing the clipboard or the primary selection (set and offer) needs `P_CLIP_WRITE`, reading needs `P_CLIP_READ`
(`kernel/sched/policy`, checked in `do_bus`); the drag slot is open as before.

## Gate

`tools/xfer/run.sh`: console part (`guest.sh` + `check.py`: round trips from 100 octets to 2 MiB with FNV sums, lazy
counters, types, custom types, primary, ring, uri-list, drag next to notifications, leak check) and three counter-probes
with a mutated copy of the tree each (no adoption, no lazy handover, no release).
