# App window options and "JARVIS Mini" -- plan (W-WINOPTS-C)

Status: stage 1 **built and gated** (`bash tools/winopts/run.sh`); stages 2-5 and "later" are the plan.
Sources: code audit (W-WINOPTS-A, references below are `file:line` on main `ec13bbf2`) and web research (W-WINOPTS-B:
wlr-layer-shell, Windows ex-styles, WCAG, Acrylic/Mica, GlobalShortcuts portal, Android tapjacking).

## 1. What we want

"JARVIS Mini": a small chat box of the assistant that

- has **no frame** and no title bar, sits **above the normal windows**, in the **bottom right corner**;
- has a **height that follows its content** (the text grows, the box grows upward);
- is **transparent / adaptive**: the background shows what is behind it, the text stays readable;
- opens and closes with a **global hotkey**, without taking the focus of the program the person is working in;
- talks to the bridge (network) **and** answers bus actions in one loop.

Everything below is the smallest set of kernel/library pieces that carries this, and that other apps can use too.

## 2. Ist-Stand

| Topic | State on main | Where |
|---|---|---|
| Frameless | **yes**: `WS_DECO 0`; `wlib.window_plain` = create + 2 more calls | `sysgui.fi:1498`, `wm.fi:4624`, `wlib.fi:1616` |
| Create-time options | **none** before stage 1: `WM_CREATE` a3 had only bit 0 | `sysgui.fi:921-975` |
| Window above the others | **root only**: any layer except `L_NORMAL`/`L_DESK` returns `E_RIGHTS` for non-root | `sysgui.fi:1479-1486` |
| `L_TOP` | the **task bar's trust level**: `WM_LIST/WM_ACT/WM_DECO/WM_FORM` demand a window on `L_TOP`; lock screen promise hangs on `L_TOP`+ | `sys.fi:4366-4405`, `sysgui.fi:1466-1478` |
| Layers | `L_DESK 0, L_NORMAL 1, L_TOP 2, L_FULL 3, L_MENUE 4, L_POPUP 5, L_TIP 6, L_TOAST 7`, numbers kept twice (`wlibc.fi`, `wm.fi`) | `wlibc.fi:433-455` |
| Keyboard on a high layer | windows leaving the normal layer lose focus unless `WS_KEYS 1` | `wm.fi:4500-4545`, `sysgui.fi:1504` |
| Per-window opacity | in the kernel (`W_OPAC`, `set_opac`), **no syscall** before stage 1; only the blur demo called it | `wm.fi:1734,10386-10410` |
| Global window alpha | `FM_WIN_ALPHA`, percent, **all** normal windows, a user setting | `wm.fi:1369,6644` |
| Pixel format | `0x00RRGGBB`; client alpha byte is **ignored**; no premultiplied, no ARGB anywhere | `lib/fui/comp.fi:4-6`, `wm.fi:10386` |
| `wmd` (ring-3 compositor) | alpha byte 0 means "opaque"; windows with `W_OPAC < 255` are "not plain" and not judged | `wmd.fi:372`, `wm.fi:6628` |
| Glass | key-colour distance alpha; only the surface becomes see-through, text stays opaque; a veil lifts alpha where 4.5:1 would break | `wm.fi:12208-12340` |
| Blur | only `L_TOP, L_MENUE, L_POPUP, L_TIP`; cache has 4 slots | `wm.fi:10326-10345,10261` |
| Background brightness | **no query**; `hell_von()` exists per pixel but is not averaged or exported | `wm.fi` (`glass_mix`) |
| Height follows content | `WM_SIZE` can shrink and grow back **up to the buffer size of creation**; frameless may go to 1x1 | `sysgui.fi:1536`, `wm.fi:6172,6209`; model `barpop.fi:1-25` |
| Hotkeys | kernel ring `push_hot` (Alt mode) -> `wmplug` owner (`E_KEY`) or fixed tile actions; **the bus knows no keys**; lock screen drops every shortcut | `kbd.fi:1251`, `wmplug.fi:886`, `tile.fi:162-229`, `wm.fi:19136` |
| fUi loop + network + bus | `fuiscene.pump()` with timeout receive and `rpc.pump(ms)` already combine; no common wait helper | `fuiscene.fi:2666`, `lib/fv/client.fi:561`, `rpc.fi:364,485` |
| Manifest rights | AR-2: `net notify clipboard.* audio.play mic` enforced; **no bit** for window layer, shortcut, backdrop | `lib/apprights/policy.fi` (`P_ALL 2047`) |

Not verified in the audit: frame flash at creation (stage 1 removes the question), screenshot right of ring 3, the fUi alpha
convention, non-blocking TLS read for streaming, `R_ACT_KEY` without config entry, the path of the Super key.

## 3. The seven proposals, judged

| # | Proposal | Verdict | Effort |
|---|---|---|---|
| 1 | Window attributes at creation | Right goal. "topmost = `L_TOP`" is **wrong and dangerous** (task bar trust, lock screen). Needs a **new layer `L_FLOAT`** below `L_TOP`, plus `WS_OPAC` and a flag word | S (flags, opacity) + M (layer) |
| 2 | Adaptive background (brightness from the blur cache) | Idea good, source wrong: the cache holds no brightness and the Mini layer has no blur. Measure the **mean/percentile brightness of the rectangle behind the window** in the server, export as `WI_BACKLUM`, client flips text colour with hysteresis | M |
| 3 | Difference blend per pixel | Weak as a readability trick: mid grey (~50 %) makes white text vanish (`|bg-255| ~ bg`). Leave out as readability; at most decoration | S-M |
| 4 | ARGB premultiplied as standard | **Wrong as standard**: kernel ignores client alpha, `wmd` treats alpha 0 as opaque, all compositor gates assume `0x00RRGGBB`. Only as **opt-in per window** (`WS_ARGB`), premultiplied | L |
| 5 | Hotkey through the action bus | The bus has no keys. The key belongs to the kernel ring -> a small ring-3 helper (wmplug) owns the key and calls the bus action | M |
| 6 | fUi with network in one loop | True; the pattern exists (timeout receive, 250 ms poll, bus in the same loop). A common `wait(ms, fds)` helper is nice, not needed | S (one source) / M (helper) |
| 7 | `app.window_opts(...)` | Good API form (one call, one word). Wrong: the name (`app.` does not exist, the libraries are `wlib/fuiapp/fuiscene`), "topmost" as a bool, "adaptive background" as an option (it is client logic + an info field), `perm=` has no window bit | M (all stages) |

## 4. What the research adds (B), and what we take

- **Overlay by role, not by "topmost"** (layer-shell model): layer + corner + margin, size 0 = automatic, **no focus by default**,
  position and z-order stay with the compositor. We take: new layer, corner placement by the client with `WM_MOVE`/`WI_WORK*`
  (no new anchor protocol yet), keys only with `WS_KEYS`.
- **Hotkeys: action + wish-key, the system owns the key** (portal, `RegisterHotKey`): the app gets "action X fired" and never the
  key stream. We take this model exactly.
- **Three rights, separate**: window float, hotkey, backdrop (blur). Cheap ones (blur flag) need no dialog.
- **Readability**: luminance switch point `L ~ 0.179` (equal contrast black/white), worst-case sampling over a 8x4 grid, hysteresis
  band + minimum hold time (~250 ms), optional scrim/tint. Contrast ratio is not readability: a **tint behind the text** is the
  robust base, the switch is the refinement.
- **Premultiplied only as opt-in**, scale only premultiplied, blend modes on un-premultiplied values.
- **Blur is server-side** (client sets a flag and a region); hard fallback to a solid colour when transparency is off, power saving,
  high contrast, inactive.
- **Safety**: an always-on-top window is a phishing surface. Trusted windows (login, rights dialog, lock screen) must never be
  covered by an app overlay.

## 5. Decisions (taken here, not asked)

1. **Topmost for apps only through a new layer `L_FLOAT`, NEVER `L_TOP`.** `L_FLOAT` lies above `L_NORMAL`, below `L_TOP` (so below the
   task bar, start menu, popups and the lock screen). `wm.L_MAX`, hit test, z order, the lock seal and `wmd` sorting must know it.
2. **Right `window.float`** in the manifest (`perm=`), granted by the person **like the microphone** (default deny, Settings -> app
   rights). New bit in the rights table `lib/apprights/policy.fi` (`P_ALL` grows), new word in `tools/sdk/osdk.py`. Without the
   right: `E_RIGHTS`. The root rule for the other layers stays as it is.
3. **Hotkeys follow the portal model**: the app registers a **named action** (`jarvismini.toggle`) with a preferred trigger
   (`Ctrl+Alt+J`); a **helper owns the key** (a `wmplug` plugin reading `E_KEY`), the person sees and changes the binding in one
   place, conflicts are shown; the app gets only the action over the bus. Right `hotkey`. System keys are not bindable. The lock
   screen already drops every shortcut.
4. **Layer is not part of the creation word.** The options word carries frameless, keys and opacity (things that cannot hurt
   other windows). The layer needs a right and gets its own call.
5. **Options act before the window opens** (no frame flash, no opaque first picture) and an unknown bit refuses the call
   (`E_INVALID`, no window), so a later stage can add bits without older kernels misreading them.
6. **Opacity is checked, not clamped**: above 255 is `E_INVALID`.

## 6. Stages

| Stage | What | Effort | VM gate idea |
|---|---|---|---|
| **S1** (built) | `WS_OPAC` syscall (own window, 0..255) + `WI_OPAC` read-back + options word in `WM_CREATE` a3 (`WO_FRAMELESS`, `WO_KEYS`, `WO_OPAC`) + `wlib.window_opts` / `wlibc.win_opts` / `wlibc.win_set_opac` | S | `tools/winopts`: read-back, range, unknown bit, foreign handles, non-root `L_TOP` still `E_RIGHTS` |
| **S2** | `L_FLOAT` layer + `window.float` right (policy bit, osdk word, `E_RIGHTS` without it); `WS_KEYS` for input; trusted dialogs stay above | M | non-root without right = `E_RIGHTS`; with granted right the layer is set; lock screen and task bar cover the float window; typing reaches it; still `L_TOP` = `E_RIGHTS` for everybody but root |
| **S3** | Hotkey helper (`wmplug`) + `jarvismini.toggle` over the bus; config `Ctrl+Alt+J -> bus action`; right `hotkey`; conflicts shown in Settings | M | QEMU `sendkey ctrl-alt-j` -> action fires, app toggles 1/0; locked screen: stays off; without helper: nothing; second binding of the same key refused |
| **S4** | `WI_BACKLUM` (server measures the rectangle behind the window, worst-case percentile, Q16 integer, only when something below changed) + client text colour switch at L ~ 0.179 with hysteresis + optional scrim | M | background black / white / grey gradient: `WI_BACKLUM` within +-8; text colour flips at most once on a noisy constant grey; contrast >= 4.5:1 at the worst sample |
| **S5** | The Mini app: fUi chat box, bridge stream and bus in one loop (`pump` + timeout receive), height from content with `WM_SIZE` (created at the largest height), corner from `WI_WORK*` | S-M | fake bridge server 100 msg/s: time to picture <= 2 frames, idle system calls per 5 s small, typing without stalls; box stays in the corner after height changes |
| later | ARGB opt-in (`WS_ARGB`, premultiplied), blur flag + region with fallbacks, `alpha-modifier`-like fade | L | host proof over all 256^3 triples; screen dump against the formula; `wmd` gates unchanged |

## 7. What we leave out (honest list)

- **`difference` blend as a readability tool**: mid-grey trap, letters flip inside one glyph on a gradient. Not even as a later
  stage; at most pure decoration.
- **ARGB as the default pixel format**: costs every gate and the zero-deviation proof of `wmd`; the Mini does not need it (key
  colour + opacity + tint is enough).
- **Client-side always-on-top without a right** (the `SetWindowPos TOPMOST` way): never. Only `L_FLOAT` with `window.float`.
- **App hotkey hooks / global key taps** (`SetWindowsHookEx`, event taps): never. Keylogger surface. Only named actions.
- Real-time blur behind several stacked glass surfaces (seams, cost), ICC colour management, Dual Kawase before a GPU/SIMD path.

## 8. Stage 1 as built

Kernel (`kernel/sys/sys.fi`, `sysgui.fi`):

- `WM_STATE` sub-code `WS_OPAC = 7`, value 0..255 on the caller's **own** window (the handle decides; no handle, no change).
  A value above 255 is `E_INVALID` and changes nothing. `WM_INFO` sub-code `WI_OPAC = 21` reads it back (255 = opaque, the default).
- `WM_CREATE` argument a3 is the **options word**: bit 0 as before; `WO_FRAMELESS = 2`, `WO_KEYS = 4`, `WO_OPAC = 8` with the opacity
  in bits 8..15. Any other bit: `E_INVALID`, no window made. The options are applied before the open animation.
- The layer rule is unchanged: non-root on `L_TOP` is still `E_RIGHTS`.

Library (`kernel/user/wlibc.fi`, `wlib.fi`):

    // one call: frameless + keys + opacity 0..255 (opac > 255 = leave opaque)
    let i: u64 = wlib.window_opts(x, y, w, h, title, true, true, 200)
    // afterwards, own window only
    wlibc.win_set_opac(wlib.handle(i), 128)

Gate: `bash tools/winopts/run.sh` (run through `/root/jarvis/bin/heavy`). Not covered yet: the pixel effect of the opacity on the
screen (the compositor path was not changed), and the read-back of `WO_KEYS` (no query exists; stage 2 tests typing on a float window).
