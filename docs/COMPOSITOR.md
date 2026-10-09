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
| **S1 -- chrome as fUi (integer core)** (this round, first part built) | Win11 title bar / buttons / frame through shape numbers (`title_bar`, `cap_w`, `frame`), caption states (hover, pressed, inactive) from `fui/core`; the layout table of the chrome in one place (`fui/deco.fi`, later); Alt+F4 | `wm` 108/0, `fourbugs` 26/0 (title centre, window protrudes, 8 edge cursors), `look` 41/0, `softui` 24/0, `themestore` 298/0, `k15` 259/0, `alltag` 45/0, `lockseal` 43/0, frame time <= 16 ms |
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

### S0 steady-state measurement (07.10.2026, design3 tree, KVM, 1280x800, host load about 5)

[measured] `tools/design/stationaer.sh` (one boot, F12 between the phases; buckets <1, <2, <4, <8, <16, <32, <64, more ms):

| phase | frames | mean | max | over 16 ms | buckets |
|---|---|---|---|---|---|
| idle (6 s) | 2 | 7.9 ms | 15.7 ms | 0 | 1 0 0 0 1 0 0 0 |
| pointer moves | 46 | 1.2 ms | 17.1 ms | 1 | 43 0 0 0 2 1 0 0 |
| start menu open / close | 54 | 17.1 ms | 218 ms | 8 | 27 3 2 0 14 2 0 6 |
| window dragged | 181 | 15.1 ms | 36.0 ms | 109 | 24 0 1 0 47 107 2 0 |

Reading: the pointer alone is cheap (43 of 46 frames under 1 ms), so the base composition is not the problem; a dragged window
costs 8 - 32 ms per frame (154 of 181 frames in the two top buckets), a blurred menu has six frames above 64 ms. The kernel boot
bench (full recompose 1.9 - 3.8 ms) does not contain a moved window with shadow / blur. **The cost per phase inside `wm.fi`
(damage / desktop / each window / blur / shadow / present) is still not split -- that is the next S0 step**; until then no
change to the frame path is justified.

## 8. Decision of 07.10.2026: who owns what (fUi, OrientOS, kernel) -- checked against the code

The order of the day: *"`wmd` is an OrientOS program in ring 3 and does not live in Firn `lib/fui`, but uses fUi. fUi (generic,
cross-platform): title bar, buttons, frame, menu as a scene tree, rasteriser, maybe shadow / glass. OrientOS (system-specific):
window buffers, z-order, input routing, window rights, lock. The kernel only delivers the framebuffer, shared buffers and input."*

**Verdict: confirmed, with three refinements.** It is the target of section 3, only drawn sharper. What I checked:

| claim | check | result |
|---|---|---|
| `wmd` as an OrientOS program in ring 3 | [seen] `kernel/user/wayd.fi` is already a ring-3 server (`profile kernel`, integer only); `memfd` + `MAP_SHARED` exist; login (`glogin`), taskbar and launcher are already ring-3 programs the system depends on | **possible today**; the display server is the last big piece in ring 0 |
| not in Firn `lib/fui` | `lib/fui` is a toolkit shared with X11 / Wayland / web hosts (pinned in `vendor/firn`; new parts are mirrored in `lib/fui`, `lib/FROM-FIRN.md`). A window table, `memfd` import and `PRESENT` are OrientOS syscalls | **right**: the *program* is OrientOS; only *pure functions* belong in `lib/fui` |
| kernel profile has no floating point | [seen] `wm.fi` is `profile kernel` (no heap, no float); `fpu` use costs a save per use. `lib/fui/core.fi`, `navnum.fi`, `region.fi` are integer and run in both profiles (`wm.fi` already imports `fui.core`) | so **hot loops must be integer**: the same file runs in the kernel fallback and in `wmd` |
| fUi can draw chrome as a scene tree | [seen] 34 programs, the bar already has four scene windows (`FUI-MULTIWINDOW.md`); the explorer's command bar and `cmdbar.fi` are fUi parts used by three programs | **yes** for chrome and menus (small areas, float is fine in `profile app`) |
| shadow / glass / blur in fUi | `lib/fui/effect.fi` is float + heap; the kernel blur is integer with a cache (3.2 ms for the menu, `BEFUND-BLUR`) | **only as integer parts** for the per-frame path; the float `effect` stays for client-side use. Not shown: speed of `effect` at 1280x800 |
| window table / z-order / focus / hit test in `wmd` | the policy table must stay readable by `ax` and `lockseal` | **table stays kernel-owned**, `wmd` reads it from a shared page (stage S3) |

### Who owns what

| layer | owns | where it lives |
|---|---|---|
| **fUi (generic, no syscalls)** | scene tree of the chrome: title bar, caption buttons, frame, window menu, snap preview, Alt+Tab list, tooltips; layout and hit-test tables of the chrome (`deco`); the painter (anti-aliased shapes, text); **integer compositing primitives** (`region`, row copy / alpha / key mix, shadow mask, box blur with running sum); animation curves | `lib/fui/*` (Firn; mirrored in `osum/lib/fui` until Firn main has it) |
| **OrientOS `wmd` (ring 3, system-specific)** | per-window buffers (imports the shared buffers), z-order and focus *policy*, damage per window and per region, input distribution to clients (from the copy ring), window rights (`darf`), the glue between the table page and fUi, `PRESENT(rect)`, the watchdog heartbeat | `kernel/user/wmd.fi` (new), uses `lib/fui` |
| **kernel (ring 0)** | framebuffer / GPU / flip, input capture (first reader), shared buffer objects, the read-only policy table page, the lock (`lockseal`), the trusted dialog, the a11y store and its rights, **and `wm.fi` as the fallback compositor** | `kernel/ui/wm.fi`, `fb.fi`, `ax.fi` |

### Refinements to the hypothesis

1. **Two profiles, one source.** Everything that runs per frame (region, row mix, blur, shadow mask) is **integer, no heap**, in
   `lib/fui/comp*.fi`: the kernel fallback and `wmd` call the *same* file, and the differential test (S2) proves it equals the old
   `fb_row*`. fUi's float painter and scene tree are used only for the **chrome** (title bar, menus), which is a few percent of the pixels.
2. **The policy table is not fUi and not `wmd`.** It stays kernel-owned (written from the clients' calls, read by `wmd`, `ax`,
   `lockseal`). If `wmd` owned it, a bug in `wmd` could forge ownership or unlock the screen. The lock is checked by the kernel
   before any buffer is composed (`darf`), not by the compositor.
3. **Speed is not the argument for moving, features and safety are.** The measured drag cost (15 ms / frame, 144 of 182 frames above 16 ms)
   was **not** caused by ring 0 or by missing fUi: it was one loop that called `fb.pixel` for every pixel and divided twice per pixel
   (`paint_win_drag`, 93 % of the window time). Rewritten row by row (same picture, integer remainder instead of two divisions) it costs
   2.9 ms / frame and 11 of 182 frames are above 16 ms. The same fix would be needed in ring 3. What ring 3 buys is the **fUi scene tree for the
   chrome and the isolation of a crash**, not frames per second.

### Alternatives and why not

| alternative | for | against |
|---|---|---|
| A. everything stays in `wm.fi` (ring 0) | no new process, no extra hop | no fUi scene tree for menus / frames, no float effects, 14 600 lines of integer Firn in the kernel, every look change is a kernel change, a painting bug crashes the kernel (r348) |
| B. kernel compositor with fUi integer core (stage 1, done) | cheap, already works | stays a kernel painter; fine as a *step*, not as the target |
| C. **ring-3 `wmd` + fUi + kernel policy core (chosen)** | crash isolation, fUi chrome, a11y from the same tree, one effects library | one more process switch per frame and per input event (not measured), the table page and `PRESENT` must be built, two compositors during the migration |
| D. client-side decoration only | no server chrome | does not give blur / shadow / z-order; two painters |
| E. GPU compositing (`gpu.fi`) | fast on real GPUs | never run on OrientOS; no driver (G-012); the plan must not depend on it |

### Stages (r428 - r435), as built and as next

| stage | state 07.10.2026 |
|---|---|
| S0 measure | **done**: `wm: phase` line per F12 (background / windows / lifted windows / top layer / present / blur / glass / shadow, microseconds and pixels); numbers in section 7 |
| S1 chrome as fUi | part 1 done (shape numbers); next: layout / hit table `fui/deco.fi`, a11y nodes for the chrome |
| S2 compositing primitives | `lib/fui/region.fi` built (test 1932); next: damage as a region in `wm.fi` and the differential tests |
| S3 shared buffers + table page | **done** (08.10.2026, `tools/comp/shared.sh`) |
| S4 shadow compositor | **done** (08.10.2026, `tools/comp/shadow.sh`) |
| S5 scan-out switch + watchdog | **done, opt-in** (`wmd present`; 08.10.2026, `tools/comp/present.sh`, section "S5") |
| S6 chrome and effects in `wmd` | **started**: S6a the window shadow is composed and judged in `wmd` (`tools/comp/shadow.sh`, section "S6a"); next: frame + title bar (rounded `fill_round`), caption buttons, blur, glass, pointer |
| S7 delete the kernel painters | not started |

### S0 per-phase split and the first fixes (07.10.2026, measured with `phases` on, `tools/design/stationaer.sh`, KVM, host load 4 - 8)

`F12` with the kernel word `phases` also prints `wm: phase n= bg= win= drag= top= pend= px= blur= glass= shadow= rgn= saved= blurs= bhits=
blurus=` (microseconds summed over the n frames since the last F12; `rgn`/`saved` = frames composed rectangle by rectangle and the pixels
that did not have to be painted; the blur counters are running totals). The first split showed where the time was:

| phase | frames | mean before | over 16 ms before | where it went |
|---|---|---|---|---|
| window dragged | 181 | 15.1 ms | 109 | `paint_win_drag` = 93 % of the window time: one `fb.pixel` call (five state reads, three compares) and two divisions for **every pixel** of the lifted window |
| start menu open / close | 54 | 17.1 ms | 8 (6 above 128 ms) | `blur_flaeche` = 95 % of the window time: 37 blurs in 56 frames (27 ms each); the animation frames of the opening menu with one `pixel_a` call per pixel |
| the rest of the boot | 71 | 75 - 87 ms | 38 - 43 | the opening animation of every window (`paint_win_anim`, one `pixel_a` per pixel) |

What was changed (all pixel-identical, counters included):

* `paint_win_drag`: row by row (clip once, row address, source column stepped with an integer remainder instead of two divisions);
* `paint_win_anim`: one call per row (`fb.scaled_row_a`: same `mix8`, `blends` / `blend_reads` added in bulk, one dirty rectangle per row);
* the pointer and a window's own contents no longer spoil its cached blur (`damage_ex(..., skip)`; the blur is made from what lies **under**
  the window); a change made by a window only spoils the blur of windows above it (`W_Z`); `blur_h` takes the reciprocal only when `n` changes;
* damage as a region (`lib/fui/region.fi`, up to 16 disjoint rectangles) next to the bounding box, composed rectangle by rectangle when it
  covers less than three quarters of the box (word `norgn` = the old single box; `tools/region/run.sh`: the same picture pixel for pixel,
  134 region frames and 12.5 million pixels saved in the drehbuch).

After (same drehbuch):

| phase | frames | mean | max | over 16 ms | what is left |
|---|---|---|---|---|---|
| pointer moves | 48 | 0.9 ms | 15.2 ms | 0 | -- |
| start menu open / close | 58 | 9.9 ms | 101 ms | 7 | the **cold blur**: 640 x 416 takes 70 - 120 ms (4 passes + tint / noise per pixel, about 260 ns a pixel), 17 blurs instead of 37, cache hits 50 |
| window dragged | 179 | 4.7 ms | 21.6 ms | 10 | the pointer **jumps** hundreds of points in the drehbuch: one big dirty box; a real mouse moves a few points per frame |
| the rest of the boot | 92 | 10.2 ms | 51.7 ms | 33 | the first blur and the first frames of every window |

### The cold blur, solved (r464, `tools/blur/blurasm.py`)

The "cold blur" was not a cold cache. `blur_flaeche` computes the picture of a window from what lies under it whenever the cached
picture is spoiled (a menu that opens, a bar under a moving window), and that computation cost **260 - 390 ns a pixel**: a
640 x 416 menu 77 - 105 ms, the bar (1280 x 40) 13 - 15 ms, every time, not only the first time. Measured in the object code
(`objdump` of `wm.blur_h`): firnc keeps every variable on the stack and puts an overflow check on every `+`, about 15 times
slower than the same loop in C at -O2. First touch of the buffers, page faults and cache build-up were checked and are not the cause.

What was done: the three inner loops (horizontal pass, vertical pass over a row of running sums, tint + grain + clamp) are
assembly in `asm(...)` blocks. firnc allows only `rax rcx rdx rsi rdi r8..r11` there, so the loops keep their constants in a
small parameter block and read them from memory. The arithmetic is the same (same reciprocal table, same rounding, same hash
for the grain, the same corner rule), proved by `tools/blur/asmtest.c` (the old Firn loops written out in C against the assembly,
752 random cases, `python3 tools/blur/blurasm.py test`) and by the pictures (design, look, themestore, region runs: the same
pixels). `python3 tools/blur/blurasm.py check` demands that the text in `wm.fi` is the text of `blurasm.py`.

| what | before | after |
|---|---|---|
| one blur of the start menu (640 x 416) | 77 - 105 ms | 11.3 - 15.1 ms |
| the bar (1280 x 40), one blur | 13.3 - 15.9 ms | 2.1 - 2.2 ms |
| start menu open / close, 55 frames (`stationaer.sh`): mean / max | 8.55 ms / 118.6 ms | 3.31 ms / 22.0 ms |
| window dragged, 181 frames: mean / max / over 16 ms | 5.49 ms / 29.6 ms / 11 | 4.53 ms / 10.6 ms / 0 |

What is left: 43 ns a pixel is still about 130 cycles; the vertical pass (six read-modify-write per pixel and pass) and the
`div` of the grain dominate. A fused vertical pass (add and remove row in one loop) and a reciprocal for the grain's modulus
would take it below 8 ms. Not needed for the 16 ms budget.

### The next bottleneck after the shared buffers, measured and removed (r465, 08.10.2026)

The shared window buffers cut the kernel's copies 9.8 times, but the frame time did not move: the copy was never the big cost. `tools/design/stationaer.sh`
(`phases` on, KVM, host load 12 - 15) on `main` 51121409 split the frame time per phase (`wm: phase`, microseconds summed over the frames):

| phase | frames | mean | max | over 16 ms | where the time went |
|---|---|---|---|---|---|
| window dragged | 181 | 5.09 ms | 18.2 ms | 2 | `drag` 657 ms = **3.63 ms per frame, 71 %**; `win` 766 ms in all; `px` 66 million = 10 ns a pixel |
| start menu open / close | 52 | 3.36 ms | 21.5 ms | 6 | `blur` 77 ms (16 blurs, 4.8 ms each), `win` 98 ms, `top` 57 ms |

The dragged (lifted, scaled) window is copied by `paint_win_drag`, and its per-pixel loop is firnc stack code (loads, stores and overflow checks, plus the
`0 <= q < bw` test). The same loop is assembly now (`tools/blur/blurasm.py`, routine `d`; 2000 random cases against the Firn arithmetic in
`tools/blur/asmtest.c`). The column test is gone: the clip keeps every x inside the window, so `q = (x - ox) * bw / nw` is always in `[0, bw)`.

| after (same drehbuch) | frames | mean | max | over 16 ms | `drag` per frame |
|---|---|---|---|---|---|
| window dragged | 181 | **1.54 ms** | 5.6 ms | **0** | **0.34 ms** (was 3.63) |
| start menu open / close | 51 | 3.11 ms | 20.3 ms | 3 | -- |

What is left in the menu: 16 blurs of 4.4 ms and the `top` layer; both are inside the budget.

### Section 5, points 2 and 3 answered (`kernel/user/compbench.fi`, `tools/comp/run.sh`, 1 and 4 cores, KVM)

| what | measured | reading |
|---|---|---|
| a whole recompose in a user program (desktop + three windows, `rep movsq` rows) | 0.6 ms | ring 3 does not cost speed for plain copying |
| a 100 x 100 damage rectangle | 4 us | -- |
| a translucent 640 x 400 window (per-pixel integer blend in Firn) | 9 - 10 ms | **per-pixel loops are the cost**, in ring 0 and ring 3 alike (35 - 40 ns a pixel) |
| one horizontal box-blur pass over 320 x 520 | 9.5 - 12 ms | the same: about 60 ns a pixel |
| a round trip between two processes through `poll()` | 8 - 10 us | the hop of the plan is cheap **when the wake-up is event driven** |
| a round trip through a blocking `read` on a pipe | 9.9 ms | the kernel sleeps in whole ticks (`pipe_read`: `sleep_ticks(1)`, 100 Hz): **not usable** for a compositor |

Consequences for the plan: (1) `wmd` must wait with `poll` (or a wake-driven call), never with a blocking `read`; the input copy ring and
`PRESENT` have to be wake driven. (2) The speed problem of compositing is the per-pixel Firn loops, not the ring; the integer primitives
(`lib/fui/comp*.fi`) must be written and measured as loops of whole rows. (3) Not measured: the wake-up of a process that sleeps on **another,
idle core** (both ends probably ran on the same core in the bench), and the effect of a busy second core.

### Tabs in the title bar (r454): the way that fits this architecture (design, not built)

Justin's order A wants row 1 of the file manager = tabs **in the title bar** (like Windows 11). The server draws the title bar today
(`paint_title`, `paint_caption`; the window buffer is the client area only). Three ways, and why this one:

| way | what it needs | verdict |
|---|---|---|
| client-side decoration (the program draws frame, title, caption buttons) | a begin-move / begin-resize request, edge cursors and snap by the client, the lock and Alt+Tab must still work | too much: every program would repeat what `wm.fi` does, and the lock (`darf`) must trust the client's chrome; this is S6 for scene programs |
| **a caption strip owned by the client (chosen)** | window flag `WF_CAPTION_CLIENT`: the window buffer grows upward by the title height; the server still draws frame, shadow and the three caption buttons and **skips the title text and background**; the client paints the strip (tabs, plus button) and declares which x-range of the strip is a **drag region** (the empty part): a press there starts the server's own move / snap / maximise on double click | small: one flag, one declared range, two rules in `paint_win` and `on_mouse`; the policy (move, resize, snap, caption buttons, lock) stays in the kernel |
| tabs stay a row under the title bar (today) | nothing | what is built; costs one row of height |

Steps: (1) the flag and the larger buffer in `create` / `resize_win`; (2) `paint_title` leaves the strip alone, `cap_at` still hits the three
buttons; (3) the drag range through the existing `WM_` request path; (4) a11y: the strip is part of the client's tree; (5) the file manager
paints its tabs there (cmdbar row 1 disappears); tests: `fourbugs` (title centre, edges), `midline` (tabs on the centre line of the bar),
`lockseal` (a locked window gives no drag), `k15`. When `wmd` exists (S4 - S6) the strip is just a scene window of the same program.

## 9. S2 - S4 as built (08.10.2026)

### S2 -- the compositing primitives as a library (`lib/fui/comp.fi`)

`lib/fui/comp.fi` (integer, no heap, `profile kernel`, used by the kernel and by ring 3): `mix8`, `blend`, `copy_row`, `mix_row`, `blur_line`,
`box_recip`, `copy_words` (`rep movsq` on x86-64, a plain loop on aarch64). `wm.fi` calls it: `fb_row` is `comp.copy_row`, `fb_row_mix` is
`comp.mix_row`, `blend` / `mix8` / `blur_line` are one-line wrappers. The damage as a region (`lib/fui/region.fi`) was already in `wm.fi`
(r461, `tools/region`). Not moved (they need window-server state): `glass_mix` (counters), the shadow mask, `fb_row_a`.

**Differential test** `tools/comp/diff.sh` (`kernel/user/compdiff.fi`): frozen copies of the old loops (`ref_*`, copied from main 124f9874)
against the library, whole buffers compared (guard words around the target included), in ring 3: `mix8` on all 16 777 216 (alpha, src, dst)
triples, `blend` 2 000 000 random, `copy_row` 3000 and `mix_row` 3000 random rows (odd/even length, unaligned, alpha 0 / 1 / 254 / 255 often),
`blur_line` 4000 random lines (across and down, radius 0..35), `box_recip` for every width 3..33 and every sum 0..8415: **0 differences
everywhere.** Counter-proof: with `+127` changed to `+126` in `mix8` and the odd-pixel tail of `copy_row` removed the test shows 32 896 / 11 073
/ 1 512 / 4 389 differences.

### S3 -- shared window buffers and the window table page

* **memfd with frames in one run.** `memfd_create(MFD_FRAMES = 0x40000000)`: the object is ONE run of frames (`mem.frame_run`), made at
  `ftruncate` (or `mmap`), zeroed, no page table (base + count), up to 8192 pages (32 MiB). `unixsock` has 40 objects now (it had 16; the
  first 16 keep their page tables, 16..39 are contiguous only).
* **The mapping reference is given back now.** `map_shm` has always taken a reference for a mapping, but `munmap` and the end of a task never
  gave it back (every mapped object lived for ever). A table of 96 records (`UMAP`, task, object, address, pages) lets `munmap` of the start
  address and the end of the task release it. Needed: a window buffer is 1 - 4 MiB.
* **`WM_CREATE`, fifth argument = descriptor + 1** of such a memfd: the window takes the run as its buffer (`W_SHM`, one reference). Nothing fits
  -> the window gets its own buffer as before and `WM_INFO / WI_SHARED` says 0 (the client falls back to `WIG_BLIT`). `WM_SETBUF (h, fd)` attaches
  a new memfd (after a resize), `WM_DAMAGE (h, xy, wh)` names the rectangle the client painted: **no copy**. A user resize of a shared window
  hands it a buffer of its own (the row length of the old width is wrong) and the client attaches a new one on `E_RESIZE`.
* **Window table page** `WM_TABLE` -> read-only descriptor of one kernel page (never writable: `SMF_RO`, map `PROT_WRITE` is refused):
  magic, sequence number (odd while writing), rows with id, owner, rectangle, z, layer, kind, flags, client offset, shared object, row length,
  opacity and a PLAIN bit (the server paints this client area as a plain copy). `WM_BUFFD (id)`: read-only descriptor of a shared window's
  buffer, root only, never while the screen is locked.
* **Clients.** `wlibc` (`shm_buffer`, `win_setbuf`, `win_damage`), `wlib` (`want_shared`, `N_SHP`; `flush_rect` names the damage instead of
  painting strips and calling `WIG_BLIT`), `fuiapp` (the canvas IS the shared buffer; `resize` attaches a new one). Every scene program
  (`fuiapp` / `fuiscene`) gets it without a change. The kernel word `noshare` switches it off (counter-proof).
* **Gates:** `tools/comp/shared.sh` (shmtest in the desktop, screenshot shows the client's gradient, differential pictures shared vs `noshare`,
  copies per frame), `tools/wayland` 45/0.

### S5 -- `wmd present`: the compositor takes the scan-out, the kernel keeps a watchdog

`wmd present` (kernel/user/wmd.fi, `run_present`) attaches with `WM_COMP / CP_ATTACH` (root only). From then on `compose` still paints the whole
picture, but the finished rectangle is handed over (`cp_hand`) and the program is woken (`CP_WAIT`); the card gets it only when the program calls
`CP_PRESENT`. The kernel keeps the framebuffer, the lock, the trusted dialog and the **watchdog** (`wm.fi`, `cp_watch`): a rectangle that waits longer
than 50 ms is pushed to the card by the kernel (a miss); 3 misses in a row or the death of the task detach the compositor and the kernel presents
every frame again (the old code path, unchanged). `wmd` attaches again 500 ms after a detach. The **input copy ring** (read-only page, `CP_PAGE`)
carries pointer moves, button changes and keys only while Alt / Windows is held; ordinary key codes are never copied, nothing is copied while the
screen is locked or the trusted dialog is up. It is **opt-in** (`wigapp=/bin/wmd,present`); the desktop default is still the kernel path, because
S6 (chrome in `wmd`) has to exist before the switch is worth anything.

`tools/comp/present.sh` (one boot per scene, same drehbuch): normal (frames shown by `wmd`, kernel shows none, input to picture mean well below 16 ms),
die (task exits -> detach at once, kernel presents, drag still works), hang (watchdog pushes 3 frames, detaches), slow (120 ms per frame -> misses,
detach again and again), and the counter-proofs `nowatch` (a hung compositor freezes the picture: frames pile up, nothing shown) and `nocomp`
(the attach is refused: the kernel shows every frame).

### S6a -- the window shadow is composed in ring 3 and judged (r485, first slice)

The kernel puts the numbers its shadow mask is built from on the window table page: **word 8** = strength of the focused window | its reach << 8 |
strength of the other windows << 16 | their reach << 24 | corner radius << 32 (strengths already scaled by the window alpha, as `shadow_staerke`
does), **word 9** = shadow colour (rgb24) | 1 << 32 (valid) | 1 << 33 (the old ring painter is on, then `wmd` leaves the shadow alone). Row word 11
bit 33 says "this window gets a shadow" (a framed window that is on the screen). `wmd` builds the same two corner banks and the two edge strips with the
same integers (`sh_ramp`, `sh_build`: `isqrt`, 16ths of a point) and blends the shadow in the z order with `comp.blend`, the same `mix8` the kernel uses.
A plain framed window now takes only its own outer rectangle out of the judged area (before: 48 points around it); the ring of shadow around it is
judged. A pixel the client left translucent is not touched and not judged, as before.

**Two kernel bugs the judge found (08.10.2026).** (1) `shadow_mask` placed the top and bottom runs `side` rows away from the window instead of `reach`:
the shadow floated R points too far out above and below (visible in the screenshot of a `shadow=on` boot; `wmd` had copied the same rows, so "0
differ" was true and useless -- a judge that shares a bug with the oracle cannot see it). Both now start `reach` rows above / end `reach` rows below
the window. `shadow.sh` therefore also reads the PICTURE: the row just below and the column just right of the focused window must be darker than the
wallpaper beyond the reach (`wmd: shadow-geo x y ow oh reach` names the window). (2) `paint_win` returned early when the clip did not touch the
window itself, so a repaint of the background that lay only in the shadow ring (an icon, the wallpaper) wiped the shadow for good (1387 pixels of the
top strip). It now lays the shadow again when the clip touches the ring.

Gate: `tools/comp/shadow.sh` (0 judged pixels differ, `shadow=` windows and `shadowpx=` pixels per cycle on the cycle line) and the counter-proof
`noshadow=1` (`wigapp=/bin/wmd,noshadow=1`): the ring is still judged but not composed, so the judge must see the missing shadow.

### r486 -- the terminal window in a shared buffer (09.10.2026)

Who paints the terminal: NOT a user program. The kernel terminal (`K_TERM`, `wm.term_paint`) writes the cell grid into the window's own buffer; the buffer used
to be a private run of frames, so the table page said `shm = 0` and `wmd` could not look at it. Now `create_ex` asks `kern_shared` for a **shared object the kernel
makes itself** (`unixsock.shm_new_contig` + `shm_grow`; the window holds the one reference, no client has a descriptor), the window table names it (shm column,
`plain` as before) and `wmd` maps it read-only (`WM_BUFFD`) like any other client buffer. The kernel keeps painting; nothing in the paint path changed.

* Resize / maximise: `term_fit` keeps the object while the new size fits, else makes a bigger one; when no object or no contiguous run can be had the window goes back
  to a private run (`detach_buf`), which is exactly the `noshare` path.
* `noshare` (kernel word): `kern_shared` returns 0 -> the terminal has a private buffer as before (the counter-proof).
* `wmd` marks the pixels of a kind-1 window with mask value 2 and prints `term=<windows> termpx=<judged px> termdiff=<differing px>` on every cycle line.
  A terminal's pixels come from the kernel painter, which leaves the alpha octet clear; the terminal is opaque by its kind, so the judge and `sh_mix` (the shadow of a
  window above) treat mask 2 as opaque. (First try: forcing the alpha octet to 255 per pixel in the picture doubled the compose time -- 6.6 ms against 3.1 ms -- and was dropped.)
* New kernel word `termdump` (`fb.M_TERMDUMP`): every pulse the terminal's cells go to the serial line (`wm: termgeo ...`, `wm: termzeile n [...]`) without the
  diagnostic board -- the independent witness below. `tools/design/eh6.sh` got `window_alpha=`, `tafel=nein` (the board paints over the screen, which a judge that compares
  the screen cannot have) and runs at 1280x800 here (`wmd` reads at most 1280 x 800).

**Gate `tools/comp/termshare.sh` (9/0):** (1) the terminal has a shared object (`shared=40`), `wmd` judges 183 744 terminal pixels per cycle, 913 344 - 1 099 776 over a run,
**0 differ**; (2) an INDEPENDENT witness: the cells of the kernel's own state (`termgeo/termzeile`, a path that goes through neither `wmd` nor the judge) are looked up in the
screenshot of the screen device: 449 - 470 cells carry ink, 1067 of 1069 checked cells agree (ink where there is a character, none where there is none), and the marker typed into the
shell (`echo tsmarker4711`, three times: the keyboard path drops a character under host load) stands in the cells; (3) `noshare`: `shared=0`, `wmd` judges 0 terminal pixels, the text still
stands in the picture (the old path works); (4) the witness fails on a screenshot with the terminal wiped out (it would not pass on an empty picture).

**Measured (KVM):** `tools/comp/shadow.sh` 14/0, 0 of 41 277 476 judged pixels differ, largest judged area 766 609 px (was 667 538: the terminal is in it), compose median 3 727 us (main 3 095 us,
budget 8 000); `tools/comp/shared.sh` 25/0 (the terminal was never copied by `WIG_BLIT`, so the copies per frame are unchanged: 314 928 px, 999 px per frame; what changed is that the
terminal is now judged). The terminal region of the pictures of `shared.sh` (c3) carries the uitrace lines of the programs (`wlib: text win=...`), which scroll in by timing: a source of noise
that was there before (the gate flickers on main too).
Judged area per cycle: +7 % (a 560 x 380 client area that was never judged).

### S4 -- `wmd`, the shadow compositor (observer)

`kernel/user/wmd.fi` reads the table page and the buffers of the shared windows (`WM_BUFFD`), composes the CLIENT AREAS of the plain windows into
an off-screen picture with `comp.copy_row`, reads the screen back (`/dev/fb`) and counts differing pixels. It judges only what it can reproduce:
client areas of plain windows, 16 points inside the edge, 48 points around every other window given up, not near the pointer, screen and table
read twice and unchanged. Chrome, shadow, blur, glass and the pointer are not composed (S6). `tools/comp/shadow.sh`.

What the first runs taught (each was a real difference between what `wmd` believed and what the kernel paints; every one is fixed in `wmd` or in
the table, none by loosening the comparison):

* the card keeps no alpha, the buffer does: compare the colour channels only;
* a pixel the client left clear or translucent (alpha != 255) is painted by the server over the wallpaper: not judged (`notopaque=`);
* a HIDDEN window (start menu, search, toast ... waiting at 0,0) neither paints nor covers: skipped in `wmd` and `PLAIN = 0` in the table;
* a framed window is plain only when the window alpha is 100 (`tab_plain` copied the rule of the frameless branch; the framed branch of
  `paint_win` uses only `FM_WIN_ALPHA`); the gate therefore boots with `window_alpha=100`, the default theme paints glass;
* a client that paints its own title strip (`WF_CAPTION_CLIENT`) has the server's caption buttons on top: the top 56 points are not judged;
* the image of a program is 11 MiB (`proc.IMAGE_END`): the two screen reads live in shared memory (`wlibc.shm_buffer`), not in `.bss`.

**Measured (KVM, `tools/comp/shadow.sh`, 70 stable cycles after the file manager opened):** 21 938 700 pixels judged over all cycles (largest area
447 948 px, the file manager's client), **0 differ**; one frame composed in ring 3 takes **521 us** (median; budget 8000); with `noshare` no window is
shared and `wmd` judges 0 pixels (the counter-proof that "0 differences" is not an accident of looking at nothing).

### S3 -- measured: what a frame costs the kernel

`tools/comp/shared.sh`, the same drehbuch (idle, start menu, file manager), once with shared buffers and once with `noshare` (the old `WIG_BLIT` path),
KVM, host load 8 - 14 (final run, 08.10.2026):

| | frames | pixels the kernel copied out of clients | per frame | `WIG_BLIT` row calls | `win` phase per frame |
|---|---|---|---|---|---|
| `noshare` (before) | 301 | 16 246 784 | **53 976 px** | 30 880 | 3 576 us |
| shared (after) | 289 | 1 598 992 | **5 532 px** | 3 760 | 4 463 us |

**Copies per frame fell by a factor of 9.8.** The `win` phase of `compose` did NOT get faster (3.6 -> 4.5 ms, within the noise of a loaded host): the saving
is the copy that used to happen inside the client's flush call (`WIG_BLIT`), not the composing. What is still copied: menus (`NK_MENU` take the old path),
a window during a drag, the first frame of a window, programs that do not use `fuiapp`. The shared windows named 16 130 013 pixels of damage without a copy.
Pictures, shared vs `noshare`: idle 0 differing pixels, start menu 20 (the tooltip edge, an animation step), file manager 24 (the last digits of the file
dates: the wall clock differs between boots; two shared runs differ from each other at 491 more places) -- the gate allows 512 (0.05 %).

### What did not get done / the order for the next rounds

* S5/S6 (chrome, shadow, blur, glass and the pointer in `wmd`) -- `wmd` is an observer only; the kernel still composes everything.
* ~~Terminal and desktop windows are not shared yet~~: the desktop window is (r486), the terminal is (r486, see above). Menus (`NK_MENU`) and a window during a drag still take the `WIG_BLIT` / kernel path.
* ~~`look`: `'Größe' does not match a second rasterisation`~~ fixed (08.10.2026): the file manager's buffer grows upward by its caption strip (r454); `tools/look/umlaut.py` now subtracts the strip height the program reports (`explorer: strip h=`). `look` 41/0. `alltag` had silently lost its counter-proof (45 -> 44): the console lines were renamed (`opk: installed`, `opk: SIGNATURE WRONG`) and the German words it looked for never matched; the check is now mandatory (45/0). `k15` is 259/0: r454 added one line (the title bar of the file manager is its tab strip).

### The blur in SSE2 and the cursor table cache (r481, 09.10.2026)

Goal: the largest frame of the first start-menu open <= 16 ms and a blur call far below 4.4 ms, with the same pixels. `tools/design/stationaer.sh`
(KVM, phases on, host load 10 - 30) showed the menu blur at 11.3 - 12.1 ms (640 x 416) and 2.2 ms for the bar (1280 x 40); the scalar loops
were already assembly (r464) but still 25 - 35 cycles a pixel. Three SSE2 routines in `tools/blur/blurasm.py` replace the loops when `fb.simd_ok`
(the vector unit is on and `fbnosimd` is not given):

| routine | does | how |
|---|---|---|
| `x` | horizontal pass, four rows at once | the sums of four rows are two xmm registers (4 x 16-bit lanes per pixel); load/store with `movd` |
| `w` | vertical pass, a multiple of four columns | one pass per output row over the row of sums; the other columns use the scalar `v` with the same row distance |
| `s` | tint + clamp of four pixels, then the grain | the grain's 64-bit hash stays scalar (written to a small buffer), tint and clamp are `pmullw` / `pmulhuw` / `packuswb` |

The division by n is the old `(S * rec + 262144) >> 19`; with rec = rh * 65536 + rl it is `(pmulhuw(S, rl) + pmullw(S, rh) + 4) >> 3`, exact for
S <= 9945 (derivation in the file). The tint's `* 5243 >> 19` is `pmulhuw(x, 5243) >> 3`. Interrupts are off per row group (`pushfq / cli / popfq`
inside the routine, block flag), the constants are rebuilt at the start of every such window, and the caller's xmm0 - xmm15 are saved into the block
and put back (no stack: firnc forbids rsp in an asm block). `python3 tools/blur/blurasm.py test`: 20 006 707 cases (random pictures with random
alpha bytes, sizes 1 x 1 .. 640 x 5, radii 1 .. 16, every odd modulus 3 .. 201) incl. a check that xmm0 - xmm15 come back unchanged (mutation-tested).
Pictures: start menu and desktop views of a SIMD run and an `fbnosimd` run differ only where two runs of the SAME configuration differ too (clock, hover).

| measured | before | after |
|---|---|---|
| native, 640 x 416, r = 8: h / v / tint+grain per pass | 1.53 / 1.25 / 3.21 ms (one blur 8.78 ms) | x 0.39 / w 0.25 / s 1.07 ms (one blur 2.35 ms) |
| KVM, start menu 640 x 416, one blur | 11.3 - 12.1 ms | 3.0 - 3.4 ms warm, 4.4 - 5.3 ms cold |
| KVM, bar 1280 x 40, one blur | 2.1 - 2.3 ms | 0.62 ms |
| start menu open / close, mean per blur (all blurs of the phase) | 3.3 - 5.5 ms | 0.95 - 1.2 ms |

The slow frames that were left were not the blur: with `phases` the new line `wm: slow us= bg= win= top= pend= blur=` splits every frame over 16 ms and
`wm: toplong` splits a slow top layer. Result: 16 - 42 ms frames in the **top** layer, all in `paint_cursor` -> `cursor.karte_bauen`: the pointer's
coverage table (three rasterisations of up to 192 x 192 samples with a point-in-polygon test, in Firn) was rebuilt at EVERY change of the pointer's shape.
`cursor.fi` now keeps the finished table per shape (`kcache`, 62 KiB) and copies it (about 20 us); a shape seen for the first time still builds once.
Same bytes, so the same pointer. What is left in the first-open frame: the cold blur (first touch of the 5 MB scratch), the menu's own paint, and two menu
blurs in that frame (the slot is spoiled by a damage right after the first computation).
