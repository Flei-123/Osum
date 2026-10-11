# CURSOR.md -- the pointer system (W-CURSOR, 11.10.2026)

## State found
- The pointer is a **software cursor of the kernel** (`kernel/gfx/cursor.fi` + `wm.fi paint_cursor`), painted as the top layer of the
  compose pass. QEMU/virtio and the Intel board have no usable hardware cursor plane in our drivers (`vgpu.cursor_*` exists only for virtio-gpu); the
  software path is the one that runs on the Dell.
- Shapes are **data**: nine vector outlines on a 24x24 design grid (`tools/wm/zeiger2.py` is the source), rasterised at the target size
  (24 px at scale 1, 48 at scale 2) with 4x4 supersampling into core / rim / shadow coverage, cached per shape (`kcache`). Not bitmaps, so scale 1 and 2 share one source.
- Existing before this round: arrow, text bar, hand, resize (4 directions), move cross, wait; automatic edge shapes (`margin_cursor`, the same
  `grip_mask` as the press). **Gaps:** `WIG_CURSOR` refused every shape > 1 (the hand never arrived), the wish was one global word (a text bar stayed
  over the desktop and over the next window), no "forbidden" shape, terminal grid and title bar had no rule, no way for a scene program to name a shape.

## Proposal (built)
1. **Shape 9 "forbidden"** (ring with slash; one simple outline with two 0.45-unit slits, closed visually by the rim). Tables are patched into `cursor.fi` by `tools/cursor/gen_tables.py` from `zeiger2.py`.
2. **Protocol:** `WIG_CURSOR(shape)` (0..9) stores the wish **per window** (`W_CURSOR`, the window under the pointer when the call arrives). The shown shape is computed
   by the server at every move (`margin_cursor`): edge/corner -> resize (8 directions) > client area -> terminal grid = text bar, else the window's wish > frame/title bar -> arrow >
   window drag -> move cross > outside any window -> arrow. Leaving a window drops its wish at once, no stale bar. No client cache any more (one syscall per move; the server only acts on a change).
3. **Clients:** wlib widgets: text field -> bar, list / table / tabs / menu bar / tiles -> hand, normal button, check, choice, slider -> arrow (Windows rule). fUi scene programs:
   framework rule in `fuiscene.scene_cursor` (entry / editor -> bar, hovering list row -> hand) and `fuiscene.cursor_for(key, shape)` per node key (hand for links, 9 for a refusing node).
4. **No flicker:** the shape change repaints only the pointer box (`shape_intern` -> `damage`); old and new box are one damage rectangle, the image is composed in one pass with the pointer on top (no under-copy to restore).
5. **Counter-proof:** kernel word `noshapes` = arrow everywhere (tools/cursor/run.sh must go red).

Not done (needs a producer): Busy at program start (shape 8 exists, nobody asks), forbidden over a rejected drop (shape 9 is reachable via `cursor_for`, no drag-drop reject path yet).
