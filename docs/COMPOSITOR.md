# COMPOSITOR -- can fUi take over the window buffers? (07.10.2026)

Question (Justin): can fUi also own the **window buffers** (compositing: buffers, layers / z-order,
damage, blending, shadow, glass / blur, animation, full-screen output) instead of `wm.fi`? Check first,
with evidence, what `wm.fi` does and in which ring; what fUi / `lib/paint` / the scene host can do today;
then decide an architecture with reasons, staged, with risks and measuring points.

Everything below is marked **[seen]** (read in the code / log on 07.10.2026, file given), **[measured]**
(a number from a run, run given) or **[not shown]** (a claim nobody has measured or tried). Where I
did not look, it says so.

## 0. Short answer

* **Yes, in the end -- but not as one step and not first.** The target is a **compositor process in ring 3
  (`wmd`)** that draws chrome and effects with fUi (scene tree for frames, bar, menus; fUi's blur / shadow /
  group-opacity for glass and depth). The **kernel keeps** what must not depend on a user program:
  the framebuffer / GPU and the flip, the input capture, the window *policy* table (owner, rectangle, layer,
  secure flags), the lock (`lockseal`), the trusted dialog and the right check of the accessibility tree.
* The step that makes it possible **exists since the Wayland round**: shared memory (`memfd` + `mmap(MAP_SHARED)`
  + `SCM_RIGHTS`) [seen: `kernel/fs/unixsock.fi`, `docs/RUNDE-WAYLAND.md` section 1]. The old reason to keep
  the server in the kernel ("a ring-3 server needs a memory object two processes can map, and this kernel does
  not have it", header of `kernel/ui/wm.fi`, round K10) is **out of date**.
* What blocks "fUi does it all" today is **not speed, it is missing pieces**: fUi has no window table, no
  z-order or focus across processes, no multi-rectangle damage, no scan-out / flip, no input capture
  (section 2). Those are the first things to build, and they are small compared with the 14 600 lines of
  `wm.fi`.
* **Not first:** a big-bang rewrite. `wm.fi` stays the working compositor and, later, the **fallback** when
  `wmd` is missing or dies. Each stage below has a gate that is a test which exists today.

## 1. What `wm.fi` is today [seen]

| fact | evidence |
|---|---|
| runs in **ring 0**, `profile kernel` (no heap, no `std.rt`, **no floating point**) | `kernel/ui/wm.fi` line 59; header "WO DER SERVER LAEUFT. Im Kernel." |
| 14 634 lines, 506 functions; coarse split by function name: chrome painting (frame, title, caption) 12 %, input (mouse, keys, grips, cursor) 12 %, window management (z-order, focus, move, resize, maximise, snap, tiling, work area) 10 %, blur / glass 10 %, compose / damage / present / row blits 8 %, terminal grid 7 %, selftest and reports 5 %, animation 3 %, lock / trusted dialog / `darf` 3 %, shadow 2 %, a11y 1 %, the rest 27 % (helpers, slots, comments) | script over `^fn ` blocks (07.10.2026, rough: comment lines are counted with the function above them) |
| **one buffer per window**, kernel frames (`mem.frame_run`), `W_BUF`; the client paints into its own memory and `WIG_BLIT` **copies** it into the kernel buffer on every frame (`WM_FILL` / `WM_TEXT` paint into it directly) | `wm.fi` `create`; `kernel/sys/sys.fi` `WIG_BLIT = 1800`; `kernel/user/wlibc.fi:24` |
| **stack order** is the server's list (`raise_win`, layers `L_DESK` ... `L_TIP`) | `wm.fi:3921`, `win_layer` |
| **damage is ONE rectangle** (`S_DX0..S_DY1`, the bounding box of everything dirty); a dirty rectangle that touches a blurring window grows to that window | `compose_one` (`wm.fi:6086`ff.) |
| blending: per row, `fb_row` (plain, `rep movsq`), `fb_row_a` (alpha + key colour + veil), `fb_row_mix`; frosted glass = box blur with a cache; shadow = precomputed mask; all integer | `wm.fi:8981`, `9249`, `7436`, `7533`, `shadow_*` |
| **present**: copy of the dirty rectangle to the card (`fb.flush_rect`) or full page with flip; virtio-gpu has its own transfer | `wm.fi:5725` `present`, `fb.frame_done` |
| **input**: PS/2 IRQ 12 and USB reports end in `wm.on_mouse` right after the report; keys go `kbd` -> `gfx.wm_on_key` -> `wm.on_key`; the server then pushes events into a **per-window ring** (`ev_push`) that the client reads with `WM_EVENT` | `kernel/gfx/gfx.fi:358`, `kernel/drv/hid/kbd.fi:892`, `wm.fi:10710` |
| policy inside the server: `darf(state, i)` (lock seal: while locked only the locker gets anything), trusted dialog `td_*` (a password prompt the kernel draws and answers itself), window-id stamping for the a11y store | `wm.fi` `darf`, `td_click`; `kernel/ui/ax.fi` header (security decision 1-3) |
| **terminal**: a text grid kept in the kernel (`term_*`, `cell_*`), painted by the server | `wm.fi:11900`ff. |
| cost, **kernel boot bench**: full recompose 1.9 - 3.0 ms, small damage 0.12 ms | [measured] `wmbench2: compose full=3001 us small=116 us`, `ohne full=1934 us` in `d2out/a3/serial.txt` (KVM, 1280x800, host loaded) |
| cost, **frames of a whole run**: mean 89 - 97 ms, max 455 - 464 ms, 43 - 46 of 67 frames above 16 ms | [measured] `bildzeit: n=67 mittel=89453 us max=454887 us ueber16=43` (and 68 / 96899 / 464184 / 46), two audit runs, 100 s of boot + start menu + settings, **host loaded**. Dominated by the first frames after start (wallpaper repaint, blur, windows opening). **It does not contradict the bench above, and it does not say what a steady frame costs** -- that is not measured (section 5, point 1) |
| the same runs print the **histogram** of the frames (`bildfach:`, buckets <1, <2, <4, <8, <16, <32, <64, more ms) | [measured] `bildfach: 21 1 1 0 1 3 4 32  betrieb max=309830 us ueber16=33` (the run of `d2out/deco1`, 63 frames): 21 frames under 1 ms (the pointer, the clock) **and 32 over 64 ms** (the first frames of every window and of the blurred menu, host loaded). Two clusters, nothing in between -- which is why a mean says nothing and why S0 asks for the steady state per phase |
| an earlier ring-0 painting bug shows the risk of painting in the kernel: the measuring table painted from the **timer interrupt** needed 44 KiB of a 16 KiB stack and overwrote the boot stack (r348, 3 crashes in 34 boots) | `docs/R348-BOOT-UD.md`; fixed in `3e35808b` |

So `wm.fi` is **architecturally a Wayland-style compositor** (client paints into its own buffer, server
composes, clients never see the screen) -- the Wayland round said exactly that (`kernel/user/wayd.fi`
header) -- sitting in ring 0.

## 2. What fUi can do today [seen]

| need | in fUi / `lib/paint` / scene host | status |
|---|---|---|
| anti-aliased shapes, text, images | `lib/fui/painter.fi`, `lib/paint/canvas.fi` (clip stack: `clip_push_rect`), `lib/fui/uiimage.fi` | **have** (float, `profile app`) |
| scene tree, flex layout, widgets, a11y nodes, focus, hover / press states, animation | `lib/fui/scene.fi`, `flex.fi`, `control.fi`, `anim.fi`; host `kernel/user/fuiscene.fi` | **have**, 34 programs use it |
| several windows in **one** program | `fuiscene.win_*`, `docs/FUI-MULTIWINDOW.md` (the bar has window, quick settings, tooltip, toast) | **have** -- but it is windows of one process, not a window table of the system |
| blur (3x box, running sum, premultiplied, clamp-to-edge), soft shadow, glass, colour matrix | `lib/fui/effect.fi` | **have** (float / heap; speed at 1280x800 per frame **[not shown]**) |
| group opacity (paint a group off-screen, lay it over once), baked backgrounds | `lib/fui/layer.fi` | **have** |
| GPU canvas | `lib/fui/gpu.fi`, `lib/plat/gles.fi` | exists; on OrientOS **[not shown]** |
| integer-only, kernel-safe subset | `lib/fui/core.fi` (`profile kernel`: fills, rounded corners with coverage, the three caption marks, button surface). `wm.fi` already paints the caption buttons with it | **have**, small |
| window list, z-order, focus, hit test across processes | -- | **missing** (the system's is `wm.fi`) |
| damage as a *region* list / per-window damage | host has one dirty flag per window (`fuiwirt.host_dirty`); `scene.fi:505`: "it damages nothing" | **missing** |
| scan-out, flip / vsync, hardware cursor | -- (kernel `fb`, `vgpu`, `cursor`) | **missing**, stays kernel |
| input capture and routing | -- (kernel) | **missing**, stays kernel |
| import of another process's pixel buffer | unix socket + `memfd` + `MAP_SHARED` exist in the kernel (Wayland round); fUi has no "surface from fd" | **missing in fUi**, kernel part exists |

Reading: fUi is a **drawing and UI toolkit** with effects; it is **not** a display server. It can draw
everything a compositor draws *with*, but not the bookkeeping a compositor *is*.

## 3. Decision

**Target: a ring-3 compositor `wmd` that composes with fUi primitives and draws the chrome as a fUi
scene tree; the kernel stays the display / input / policy core. Reached in stages; `wm.fi` stays as fallback
until the last gate is green, and the kernel part of the policy never moves out.**

Why (and what I rejected):

1. **Why not leave everything in `wm.fi` and only pull fUi's integer core in.** That is what is done
   *now* (stage 1): it gives Win11 chrome and fUi's caption marks, but it can never give a fUi scene tree for
   menus / frames / bar, a11y nodes from the same tree, floating-point effects (the kernel is `profile kernel`;
   FPU use in ring 0 needs a save per use: `fpu: mode=3 size=832` [seen in the boot log]), or fUi's
   `layer` / `effect`. Every new look feature would again be re-written in integer Firn inside a 14 600-line
   ring-0 file. The audit round showed the cost: ten surface defects, several of them in `wm.fi` (frost corners).
2. **Why not a pure "fUi draws everything inside every client" (client-side decoration only).** It solves the
   title bar, not the blur / shadow / z-order. It also needs the server to know the caption rectangle
   (a protocol) and still leaves two painters (client frames, server effects). It is a good *part* (stage 6 may
   use it for scene programs) but not the architecture.
3. **Why ring 3 is acceptable now.** Shared memory exists [seen]; input events already reach clients through
   a ring and a syscall, so an extra hop is a ring + a wake-up; the compositor is *one* process that crashes
   alone instead of taking the kernel (see the r348 evidence). **What it costs, honestly:** one more
   process switch per frame and per input event. **Not measured.** The gate "input to picture <= 16 ms" decides
   whether this holds (section 5, point 2).
4. **What must stay in the kernel, and why.**
   * *Framebuffer, flip, hardware cursor, virtio-gpu transfer*: the card belongs to one owner; the kernel
     must be able to take it back (fallback, panic screen, trusted dialog).
   * *Input capture*: keys and pointer reach the kernel first; the **kernel** decides whether a client may get
     them (`darf`: locked screen => only the locker). If routing moved out, a bug in `wmd` could leak keys to
     the wrong program. The compositor receives a **copy** of pointer / key events for chrome (move, hover,
     caption, Alt+Tab), nothing more.
   * *Window policy table*: owner, rectangle, layer, hidden, locked, trusted flags. Written by the kernel from
     the clients' calls (as `W_*` today), **read** by `wmd` from a shared page. `ax` (rights, stamping) and the
     lock (`lockseal` 43/0) read the same table, so `wmd` can neither forge ownership nor unlock.
   * *Trusted dialog* (ACTION-BUS-5): drawn by the kernel on top of everything, never by `wmd`.
5. **Crash safety.** Client buffers live in shared memory objects the kernel holds; `wmd` only maps them.
   If `wmd` dies or misses N frames, the kernel resumes compositing from the same table with `wm.fi` (kept
   as fallback) -- no window and no pixel is lost, the lock state is unchanged (it is the kernel's). A new
   `wmd` re-attaches to the table and the buffers. **Gate:** kill `wmd` during a window drag; the screen is
   back within one second; `lockseal` still 43/0.

## 4. Stages, gates, measuring points

| stage | what | gate (tests that exist today, plus the new ones) |
|---|---|---|
| **S0 -- measure** (this round, started) | document (this file); steady-state frame histogram after boot (reset the counters; pointer movement, window drag, menu open) -- **new**; split `wm.fi` time per phase (damage / desktop / each window / blur / present) and the input-to-present latency in the kernel -- **new** | numbers in this file; no behaviour change |
| **S1 -- chrome as fUi (integer core)** (this round, first part built) | Win11 title bar / buttons / frame through shape numbers (`title_bar`, `cap_w`, `frame`), caption states (hover, pressed, inactive) from `fui/core`; the layout table of the chrome in one place (`fui/deco.fi`, later); Alt+F4 | `wm` 108/0, `fourbugs` 26/0 (title centre, window protrudes, 8 edge cursors), `look` 41/0, `softui` 24/0, `themestore` 298/0, `k15` 258/0, `alltag` 44/0, `lockseal` 43/0, frame time <= 16 ms |
| **S2 -- compositing primitives as a library** | `lib/fui/comp.fi`, integer, `profile kernel` (usable in both rings): rectangle algebra and a **region** (list of damage rectangles), row copy / alpha / key-colour mix, shadow mask, box blur with running sum. `wm.fi` calls it row by row; **differential test**: for random input the library output equals the old `fb_row*` octet for octet | new `tools/comp` 0 differences; `look` / `softui` unchanged; micro-bench in ring 0 and ring 3 (the ring-3 number is the first real evidence for section 5, point 3) |
| **S3 -- shared window buffers** | `WM_CREATE` variant that takes a `memfd`-backed buffer: the client paints into the buffer the kernel composes from (no `WIG_BLIT` copy); a read-only table page (rect, z, layer, flags, owner) for ring 3; `wayd` keeps working | copies per frame 0 for scene programs; `tools/wayland` 45/0; `a11y` 58/0 |
| **S4 -- `wmd` as a shadow compositor (observer)** | `wmd` composes the same scene into an off-screen buffer from the shared table and buffers, **does not touch the screen**; a test compares its picture with the kernel's pixel for pixel (the oracle is `wm.fi`, which exists) | pixel difference 0 on the scenes of `look` / `themestore` / `design`; time per frame <= 8 ms measured in ring 3 |
| **S5 -- switch scan-out to `wmd`, `wm.fi` as fallback** | kernel `PRESENT(rect)` syscall for the compositor, watchdog and take-over by `wm.fi`; input copy ring for chrome | crash test (kill, hang, slow `wmd`: back to `wm.fi` < 1 s, no window lost); `lockseal` 43/0; trusted dialog tests; `a11y` 58/0; **input to picture <= 16 ms** (`tools/...` new, measured from the IRQ time stamp to `PRESENT`) |
| **S6 -- chrome and effects move to fUi in `wmd`** | frames, caption, Alt+Tab switcher, snap preview, window menu, bar's pop-ups as fUi scene windows of `wmd`; blur / shadow / glass from `fui/effect`; a11y nodes of the chrome in the `ax` store stamped with `wmd`'s task | `fourbugs`, `wm`, `look`, `softui`, `themestore`, `barscene` ...; frame time <= 16 ms |
| **S7 -- delete the kernel painters** | `wm.fi` shrinks to the policy table and the fallback; terminal grid out of the kernel (optional) | boot time, memory, no step backwards |

## 5. What is **not shown** (open, do not take as fact)

1. **Steady-state frame time.** The only whole-run figure (mean 90 - 97 ms) is dominated by start-up under
   host load; the only steady one is the boot bench (full recompose 1.9 - 3.0 ms). A histogram after boot,
   while the pointer moves and a window is dragged, does not exist yet: that is the first thing S0 builds.
2. **Latency of the extra hop.** Pointer IRQ -> kernel -> `wmd` -> `PRESENT` is *designed* to cost two wake-ups.
   Nobody has measured the scheduler's wake-up latency for a ring-3 process on this kernel under load.
3. **Speed of compositing loops written in Firn in ring 3** against `rep movsq` and the hand-tuned row
   functions in `fb.fi` (S2's micro-benchmark answers it).
4. **fUi `effect` blur at 1280x800 per frame** on this CPU (claimed O(1) per pixel, never run here); the
   kernel's own blur has a cache and a hit rate of 90 % (round BLUR) -- the same trick would be needed.
5. **GPU path** (`gpu.fi`) on OrientOS: never run; the plan does not depend on it.
6. **Multi-core:** `compose` takes one lock (`S_CLOCK`); whether a compositor on another core is faster or
   only moves the contention is not known.
7. The percentages in section 1 are by function name and count comments with the function above; they
   say where the lines are, not where the time is.
8. I did **not** read all of `kgui.fi`, `tile.fi` (tiling tree, 3 000 lines) or `wmplug.fi` (plug-ins in the
   server); they also have to be classified before S4 (what stays kernel, what moves).

## 6. First stage built in this round (S0 / S1)

* **S0 measuring tool (built).** `F12` now also prints `wm: bild n= mittel= max= ueber16= fach=<8 counts>` --
  the frame statistics **since the last F12** -- and starts them again. `tools/design/stationaer.txt` is the
  drehbuch (idle / pointer moves / start menu open and close / window drag, one F12 between the phases);
  `tools/design/stationaer.sh` runs it. Numbers: section 7.


* This document; the roadmap items for S0 - S7 (project OrientOS).
* **S1, part 1 -- Windows 11 chrome from shape numbers.** Three new window-server slots
  (`FM_TITLE_BAR`, `FM_CAP_W`, `FM_FRAME`), carried through `wlibc` (`title_bar`, `cap_w`, `frame` in a shape
  file) and `sys` (`WF_*`); `osum.shape` says 32 / 46 / 1, so the title bar is 32 points high, the caption
  buttons are 46 x 32 and the frame is one point; `classic` and `modern` do not say them and keep the old
  22 / 30 / 2 octet for octet. The caption buttons are painted with `fui/core` as before (hover, and the
  new pressed state).
* Left for the next steps of S1: the layout / hit table in `fui/deco.fi`, a11y nodes for the chrome (the
  kernel adds them when a privileged reader asks, no storage), the window menu on Alt+Space, the
  switcher / snap preview as scene windows (S6).
