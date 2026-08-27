# Round TILING — the window tree

Until this round the windows of Osum floated. Round K10 gave them a
stacking order, an input focus and damage tracking; **where** a window
was put was decided by whoever created it. That is the state every
window system starts in, and it is the state in which eight windows are
a pile of cards rather than a desk.

This round adds a **tree**: leaves are windows, inner nodes are splits,
and every arrangement that can be drawn is a tree.

The code is `kernel/tile.fi` (the tree, 2,932 lines), a seam in
`kernel/wm.fi` (which leaf belongs to which window, who paints the tab
bars, what the mouse does), the hot-key ring in `kernel/kbd.fi`, four
system calls in `kernel/sys.fi`, and `/bin/tiling` in ring 3
(`kernel/user/tiling.fi`). The acceptance run is `tools/tiling/run.sh`.

---

## 1. Why a tree, and not templates

Windows 11 has "Snap Layouts": a handful of fixed pictures — two halves,
three columns, four quarters — and whoever opens a fifth window falls out
of the scheme. A template is an enumeration, and an enumeration ends.

i3, sway and bspwm do it the other way round. They keep a tree. Splitting
is an operation on the tree, not a choice from a menu, so there is no
arrangement that is "not supported" — the two halves and the four
quarters are *special cases* of the tree and not a separate machinery.

That is the design taken here, literally: the Windows-style quick snap
(`snap-left`, `snap-topleft`, dragging to a screen edge) is one function
that **builds a particular tree** and then gets out of the way. After a
snap you can split into the snapped half, turn it into tabs, and rotate
it. In Windows the template ends exactly there.

## 2. What the two references do, and what was taken

### i3 / sway — an n-ary tree of containers

i3 keeps a tree in which an inner node ("container") has any number of
children and a **layout**: `splith`, `splitv`, `tabbed`, `stacked`. Each
child carries a percentage of its parent. A new window splits the
focused leaf; inside a tabbed container it becomes a new tab instead.

**Taken:** the n-ary shape, the per-child fraction, the three container
modes, and the rule that a new window in a tab container becomes a tab
rather than a split. Also i3's behaviour of dropping the dragged window
out of the tree while it hangs on the pointer.

**Not taken:** workspaces (there is one tree, see §7), marks, scratchpad,
the IPC socket, and i3's `focus parent` navigation. `layout toggle
split` exists here as `split-h` / `split-v` — as a *hint for the next
insert*, which is what i3's `split h` really is.

### bspwm — a binary tree with geometry operations

bspwm keeps a strictly binary tree and offers what i3 does not: **rotate**
a subtree by 90/180/270 degrees, **mirror** it along an axis, **balance**
it so that every ratio becomes equal, and the *automatic scheme* — when
you do not say how to split, the aspect ratio decides (a wide leaf is
split vertically, a tall one horizontally).

**Taken:** rotate, mirror, balance, and the automatic scheme. They are the
operations that make a tree feel like a tree rather than like a stack of
splits, and they cost almost nothing once the tree is there.

**Not taken:** bspwm's strict binariness (tabs need n children), its
preselection UI, its receptacles, and its external `bspc` protocol — the
equivalent here is `/bin/tiling` over four system calls.

## 3. What was built

### The data structure

A node is 128 octets in `kstate.TILE_OFF` (0x4C000..0x50000, four pages,
entered in `tools/kernel/memmap.py`):

```
parent, first child, last child, next/prev sibling   the n-ary links
kind        leaf or container
layout      split | tabbed | stacked
dir         horizontal | vertical          (only meaningful for split)
frac        this node's share of its parent, in FRAC_ONE steps
client      window slot + 1, 0 = a leaf without a window
x, y, w, h  the computed rectangle
active      which child is in front        (tabbed / stacked)
```

**The size limit is named, not hoped for.** A tree with N leaves has at
most 2N−1 nodes (every inner node has at least two children — otherwise
it collapses immediately). 96 nodes therefore carry 48 windows, and
`MAX_LEAVES = 48` is the constant that says so. Window 49 gets a
refusal, not a silent overflow; promise 22 of the self-test opens 52
windows and checks exactly that.

The remaining 3,584 octets of the region hold the key map (56 entries of
64 octets).

### Exact geometry

Ratios are **not pixels**. `FRAC_ONE` is 720720, and that number is not a
whim: 720720 = 2⁴·3²·5·7·11·13 is divisible by every integer from 1 to
16, so "all children equal" is an *exact* division for up to sixteen
children rather than a rounded one.

When fractions become pixels, the children of a split are laid out by
prefix sum and **the last child gets the remainder** (`end = total`
instead of a computed value). Therefore the sum of the children is
exactly the parent — in every case, with no gap and no overlap. That is
the invariant the whole round rests on.

### Container modes

* `split` — the children divide the area along `dir`.
* `tabbed` — one bar of 22 pixels at the top, one tab per child, only the
  active child is visible.
* `stacked` — one title row of 22 pixels per child, stacked at the top,
  only the active child is visible below them.

A node changes its mode without the windows noticing anything: they get a
rectangle, as before. The bars are painted by the server (like the title
bar) — they lie *outside* the window rectangle, so an application could
not paint them even if it wanted to.

### Operations

| operation | what it does |
|---|---|
| `focus-left/right/up/down` | **geometrically**: among all visible leaves, the nearest one in that direction; leaves that do not overlap crosswise come last |
| `move-left/right/up/down` | re-hangs the node next to that leaf; the old container collapses if it is left with one child |
| `split-h` / `split-v` | direction for the *next* insert (i3's `split h`) |
| `layout-split/tabbed/stacked` | the mode of the focused container |
| `rotate` | quarter turn clockwise over a subtree |
| `mirror` | reverses left/right |
| `balance` | all ratios equal |
| `grow` / `shrink` | shifts the ratio at the inner node |
| `float` | takes the window out of the tree and back in |
| `snap-left/right/top/bottom`, `snap-topleft/…` | the quick snap, derived from the tree |

**The rotation rule is derived, not invented.** Under a quarter turn
clockwise the left edge becomes the top edge. So a horizontal container
becomes vertical and *keeps* its order (left→top, right→bottom); a
vertical one becomes horizontal and *reverses* it (top→right,
bottom→left). Screenshot 3 shows exactly that.

**Floating and tiled live side by side.** A window with `W_NODE == 0`
floats as it did before this round; a dialog wants to float, a terminal
wants to tile. `float` moves a window from one world to the other, and
the floating geometry is kept in `W_SAVXY`/`W_SAVWH` — otherwise the
dialog comes back in the corner.

### No recursion

Every traversal in `tile.fi` is a loop over `dfs_next`/`dfs_skip`
(preorder without a stack, via the parent pointers). The reason is
measured and stands in `kernel/sys.fi`: the kernel stack is 16 KiB and
was 112 octets from full in round K13. A tree of 48 leaves can be 48
deep — a recursive relayout would be a stack overflow that looks like a
bug in the window server.

### Controls

* **Keyboard.** `kbd.irq` remembers Alt and puts the key into a **separate
  ring** instead of sending it through the line discipline — otherwise an
  `h` appears in the shell when you move the focus left. `wm.poll` picks
  it up. This is the same direction as the pointing device, and it is why
  `kbd.fi` does not have to know the window server.

  **The key map is a text file**, `/users/<name>/config/tiling.conf`, in
  i3's syntax:

  ```
  bind mod+h focus-left
  bind mod+shift+l move-right
  bind mod+w layout-tabbed
  ```

  The kernel reads it at boot; `/bin/tiling load` reads it again after
  you have edited it, from ring 3, where the user name is known. Without
  the file there is **no** key map at all — a built-in set of keys in the
  source would be exactly what the round forbade, and it would pass the
  test silently. Section 8 of `tools/tiling/run.sh` therefore boots a
  second disk image without the file and demands `binds=0`.

* **Mouse.** Dragging a tiled window takes it out of the tree (that is
  what i3 does too — otherwise the tree pulls it back to its old place on
  every pointer movement). While it hangs on the pointer, a **preview
  rectangle** shows where it will land: the quarter of the target window
  the pointer is in gives the side, the middle means "as a tab", and a
  screen edge means the quick snap. The grip in the bottom right corner
  of a tiled window shifts the **ratio** at the inner node, not the size
  of the window — anything else would be a gap.

* **Ring 3.** `/bin/tiling` shows the state, prints the key map, reloads
  it and executes any action by name. Four system calls (1820..1823),
  built like `osum_pwrget` of round K18: one number per call, no pointer
  into the kernel except for the config text, which goes through
  `copy_in` like every other buffer from ring 3.

---

## 4. The measurements

All numbers from a real run, QEMU 800x600, **TCG, without KVM** — on real
hardware everything below is faster. Reproduce with
`bash tools/tiling/run.sh`.

### Relayout

A thousand runs per number, so the microsecond count of the whole run is
the nanosecond count of one run — without a division that could flatter
anything.

| leaves | nodes | relayout | invariant check |
|---:|---:|---:|---:|
| 2 | 3 | 5,452 ns | — |
| 8 | 15 | 27,365 ns | — |
| 32 | 63 | 95,897 ns | 336,345 ns |

The cost grows with the number of windows, not with its square: 32
windows are sixteen times two windows and cost **17.5 times** as much.
Across repeated runs the numbers move by up to 20 % (5,419–6,321 ns for
two leaves, 92,834–114,150 for 32); that spread is the emulator, not the
tree. The check is the noisiest, because it walks every node twice — once
locally and once for the area.

Two of these numbers are large in absolute terms and that is honest:
every field access in this kernel goes through `__mmio_read64`, which
under TCG is a call, and a relayout of 63 nodes is roughly 12,000 of
them.

### Damage tracking — the point of the round

Round K10 showed that damage tracking is the difference between a usable
surface and an unusable one. Splitting a leaf must therefore repaint the
**affected subtree only**, not the screen.

Measured with the window server's own counter (`compose` adds the area it
really composited), four windows at 800x600:

| | pixels repainted |
|---|---:|
| split a leaf | **240,000** |
| close a window | 240,000 |
| the whole screen | 480,000 |
| the same split with `notiledirty` | **480,000** |

So the subtree tracking halves the repainted area in this arrangement,
and the counter-probe `notiledirty` turns it off so the number means
something. The 240,000 is not a constant: it is the rectangle of the
node that changed. Splitting a leaf in the bottom right quarter of a
2×2 grid paints 120,000; the measurement above splits a half.

### The invariant, and 10,000 random operations

After **every** operation the kernel recomputes the invariant, on two
independent paths:

1. **Locally, at every container:** do the children lie edge to edge
   without gap or overlap, does the first start at the parent's border
   and the last end at the other one, and do the fractions sum to
   `FRAC_ONE`? If that holds at every container, the whole tree tiles —
   induction over the depth, no list of rectangles needed.
2. **Over the area:** the sum of the areas of all *visible* leaves plus
   all tab bars must equal the area of the root. This number is produced
   on a different path than (1) and falls even when two local errors
   cancel out.

Plus the bookkeeping: reachable nodes = allocated nodes (no leak), leaf
count correct, parent pointers pointing back, focus on a live leaf.

```
tile: fuzz ops=10000  violations=0  peak=85  checks=10000
```

Ten thousand random operations — open, close, move, change mode, resize,
rotate, mirror, balance, snap — and **zero** violations. The generator is
pinned: same seed, same sequence, a failure is reproducible.

**The check itself has a counter-probe.** Promise 23 of the self-test
moves one rectangle by one pixel and demands that `check` finds it. A
check that cannot fail checks nothing — the lesson of round K7B, one
level up.

That this is not decoration is shown by what the fuzz test found, and
neither of the two would have been found by hand:

1. The area counter walked into the *siblings* of the active child in a
   tab container and counted them twice. 9,291 of 10,000 operations then
   reported a violation that was not one — and the real ones behind them
   would have drowned.
2. `wm.set_focus` did not carry the focus of the **tree** along. A new
   window therefore split not the window you had clicked, but the one
   created last. It looks like a broken tree and is a missing line.

### The self-test

```
tile: selftest 24/24  failed=0x0
```

Twenty-four promises, each with the number of the bit it clears — so a
failure says *which* promise fell, not just "22 of 24". Among them: the
first window fills the area; the second splits it into two exact halves;
closing collapses the container with no gap; a tab container gives all
children the same rectangle and shows exactly one; directional focus is
geometric; rotate turns horizontal into vertical; balance is exact; a
**resolution change** keeps the structure and re-measures it; snap-left
is exactly 400x600; the quarter is exactly 400x300; window 49 is refused.

### Resolution changes

`tile.set_area` re-measures the tree instead of rebuilding it, because
the ratios are stored as fractions and not as pixels. Promise 19 changes
800x600 → 1024x768 and checks that the node count is unchanged, the first
child is 512 wide, and the invariant holds. `wm.on_screen_resize` is the
entry point for the parallel DISPLAY round.

### The screenshots

Three, machine-checked pixel by pixel by `tools/gfx/checkshot.py`; each
window has its own colour.

They are in the tree: `docs/tiling/tiling-split.png`,
`docs/tiling/tiling-tabbed.png`, `docs/tiling/tiling-rotated.png`.

1. **split** — four tiles of exactly 400x300 at (0,0), (400,0),
   (400,300), (0,300). Checked: the colour at the place the tree computed
   it, and that the seam between the tiles is *not* the server's desktop
   colour — that is "no gap" in one pixel.
2. **tabbed** — the same four as tabs: all of them 800x578 at (0,22),
   three hidden, the fourth tab highlighted, the first not, and there is
   text in the tab bar rather than only colour.
3. **rotated** — the same four after a quarter turn: yellow moved from
   the bottom left to the top left, red from the top left to the top
   right.

---

## 5. What does not work, and why

* **One tree, no workspaces.** i3 has a tree per workspace. Here there is
  one root for one screen. Workspaces need a place to keep N trees and a
  switch; the node budget (96) would then have to be divided. It was left
  out deliberately rather than half-built.

* **Tab bars are painted under the windows.** This window server has no
  layers in this branch (the parallel DESKTOP round adds them). A
  *floating* window that overlaps a tab bar therefore covers it. Tiled
  windows never do, because the tree subtracts the bar height from the
  children's area. The fix is one line once layers exist: bars into the
  layer above the normal windows.

* **A tab bar is not clickable.** You can switch tabs with the keyboard
  (`focus-left`/`focus-right` walk into the neighbouring tab because they
  are geometric and the hidden tabs share the visible one's rectangle),
  but a click on the bar does nothing yet. The bar rectangles exist
  (`tile.tab_x/y/w/h`) — what is missing is the hit test in `wm.on_mouse`.

* **No gaps, no borders between tiles.** `gaps inner/outer` of i3 is not
  there. The invariant is written as "the sum of the children is exactly
  the parent"; gaps mean the sum is *smaller* by a known amount, which
  the check would have to know about. That is a deliberate ordering: the
  exact case first.

* **48 windows, not more.** The tree lives in four pages of `kdata`. More
  windows means either more pages or a node allocator on the heap. The
  window server itself stops at 8 windows in this branch anyway
  (`wm.MAX_WIN`), so the tree is not the narrow part today.

* **`move` at the edge does not push out one level.** i3 moves a window
  out of its container when there is nothing in that direction. Here
  `move-left` at the left edge does nothing and reports failure. The
  operation is in the tree (`detach` + `graft` on an ancestor); what is
  missing is the decision when it should happen.

* **The layout is not persisted.** After a restart there is a single
  window again. The tree is 12 KiB and would fit in a file; nothing reads
  or writes it yet.

* **`stacked` shows the title rows, but not more.** Every child gets one
  row of 22 pixels with the title of its first leaf. i3 shows the whole
  path of the subtree there; here it is the first window found.

* **The numbers are from an emulator.** Everything in §4 was measured
  under QEMU without KVM. The relative statements (linear growth, factor
  two for the damage tracking, zero violations) carry over; the absolute
  microseconds do not.
