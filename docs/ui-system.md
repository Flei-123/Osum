# UI system — the single design spec (owner: UI system owner, 08.11.2026)

One look everywhere. Every visible element (card, toast, notification, dialog, popup, flyout,
list row, button, icon, tray chip, taskbar preview, toggle, slider) comes from ONE component file
and takes its colours from palette ROLES. No per-place drawing code, no colour literals.
A new variant extends the component; it never copies it.

Related detail docs (they stay valid, this file wins on conflict):
`docs/DESIGN-TOKENS.md` (numbers), `docs/FUI-CONTROLS.md` (scene controls),
`docs/ui/dialog-api.md` (system dialogs), `docs/ICONS.md` (icon font), `docs/TRAY.md` (tray model).

## 1. Tokens

Source of truth for numbers: `lib/fui/tokens.fi` (integers only, kernel + app profile).
Lengths are points at scale 1; the token functions multiply by the scale `s` (1 or 2). Never multiply twice.

| group | tokens | value at scale 1 (scale 2 = x2) |
|---|---|---|
| radius | `R_SMALL` / `R_MEDIUM` / `R_LARGE` / `R_FULL` | 4 / **8** / 12 / pill. Default for everything = **8** (button, field, row, card, popup, dialog, window corner) |
| spacing | `SP_1`..`SP_6` | 4 / 8 / 12 / 16 / 24 / 32 |
| type | `T_CAPTION` / `T_BODY` / `T_STRONG` / `T_TITLE` / `T_DISPLAY` | 12 / 15 / 15 / 18 / 24 px |
| icon | `I_INLINE` / `I_ROW` / `I_TRAY` / `I_BAR` / `I_TILE` / `I_HERO` | 16 / 16 / 20 / 24 / 32 / 48 px |
| elevation | `E_LOW` / `E_MID` / `E_HIGH` | card at rest / popup, flyout, toast / dialog |
| motion | `D_FAST` / `D_NORMAL` / `D_SLOW` | 100 / 160 / 300 ms |
| states | `ST_NORMAL` / `ST_HOVER` / `ST_PRESS` / `ST_FOCUS` / `ST_OFF` | one answer via `tokens.state_fill` |

### Palette roles (light + dark)

Colours are ROLES resolved at run time from the system theme (light/dark/contrast + user accent).
There are three role namespaces today; they map onto each other and must not grow:

| meaning | scene code (`fuiscene.R_*`, `role_col`) | wlibc code (`wlibc.theme(T_*)`) | tokens neutral |
|---|---|---|---|
| window / page base | `R_SURFACE` | `T_BG` | `N_BASE` |
| card, popup, flyout, toast, dialog body | `R_SURFACE` raised (`theme.Colors.surface_raised`) | `T_MENU` / `T_DLG` / `T_PANEL` | `N_RAISED` |
| field | `R_FIELD` | `T_ENTRY` | `N_FIELD` |
| stroke / outline | `R_BORDER` | `T_LINE` | `N_STROKE` |
| text | `R_TEXT` | `T_FG` | `N_TEXT` |
| secondary text | `R_MUTED` | `T_DIM` | `N_MUTED` |
| accent fill | `R_ACCENT` | `T_ACCENT` / `T_SEL` | `acc_*` derived |
| text on accent | `R_ONFILL` | `T_SELFG` | `acc_on` |
| status | `R_SUCCESS` / `R_WARN` / `R_ERR` | (status binds in `wlibc/wcpal.fi`) | - |

Dark values live in `kernel/user/wlibc/wcpal.fi` (only allowed literal file, skipped by the palette ratchet).
Contrast rules: text >= 4.5:1, UI strokes >= 3:1 (checked by `tools/tokens/run.sh`, `tools/palette/run.sh`).

### Scale

Scale 1 and 2 only. Every component takes points and converts once (`fuiscene.sp`, `tokens.space`,
`tokens.radius`). Gates check both scales (`res=1920x1080 uiscale=2`).

## 2. Components — one implementation file each

"Canonical" = the only file allowed to contain the drawing code. "Migrate" = duplicates that must
move onto the canonical file (tracked by `tools/uicheck`, ratchet only shrinks).
"Owner" = worker currently changing it; others only consume its API.

| component | canonical file (API) | duplicates to migrate | owner |
|---|---|---|---|
| surface plate (shared base of card / popup / flyout / toast / dialog: fill + 1-pt stroke + radius 8 + elevation) | `kernel/user/uikit/uisurface.fi` (`uisurface.paint(kind, x, y, w, h)`, kind registry) | `barpop.plate`, `traypop.plate/ringp`, `fsdraw.draw_card/draw_card_soft/draw_layer`, `taskbar/tbhover.hover_plate/pill`, `qsmedia`, `calpop`, `signin`, `store`, `taskmgr`, `settings/set*` round-rect plates | UI system owner |
| card / notification card | scene: `fuiscene.card` / `card_soft` (fsdraw) on top of `uisurface` kind `CARD` | `notifc.fi` card layout, `barpop.toast_draw` | w-notify-unify |
| toast | `barpop.toast_show` (kind `TOAST`) | `taskbar/tbpopup.toast_*` | w-notify-unify |
| system dialog / confirm (UAC-like, above all windows) | `kernel/ui/wm/wmtrust.fi` drawn by the window server; API `kernel/user/dialog.fi` + `consent.fi` | `busy.alert/confirm`, ad-hoc confirm windows in installer / ota / explorer | w-settings-win11-confirm |
| app-modal dialog (inside one window) | `fuiscene.dialog_open/dialog_entry` (fsctl) on `uisurface` kind `DIALOG` | `wlib` dialogs | w-settings-win11-confirm |
| popup / flyout (tooltip, menu, tray flyout, quick settings, calendar) | `kernel/user/uikit/uiflyout.fi` (placement + plate) using `uisurface` kind `FLYOUT` / `TIP`; menus `menu.fi` over `fuiscene.menu_open` | `traypop.fi` own painter plates, `calpop.fi`, `qs.fi`, `qsmedia.fi`, `barpop.tip_draw` | net flyout: w-net-flyout; tray: w-tray-icons; rest: UI system owner |
| list row | scene: `fuiscene.table` (fsdraw `draw_ct`) ; long lists `rowlist.fi` | `navview.fi`, `store.fi`, `taskmgr.fi`, `disks.fi` hand-drawn rows | UI system owner |
| button | `fuiscene.button` / `button_main` / `icon_button` (fsdraw `draw_btn_plate`) | `wlib` buttons, `fuib.rrect` buttons, `taskbar/tbhover.button` | UI system owner |
| toggle / slider / segmented / check | `fuiscene.toggle` / `slider` / `segmented` / `check` (fsdraw `draw_toggle`, fsctl) | settings pages drawing own switches | w-settings-win11-confirm |
| icon set (shell symbols) | icon font `lib/icons.fi` + `assets/icons/icons.list` (glyph takes text colour); app icons `assets/apps/*/symbol.svg` via `lib/appicon.fi` | `traypop.net_glyph/wlan_glyph/badge/slash` vector glyphs, `symvar.fi` | w-tray-icons |
| tray chip | `lib/fui/tray.fi` (model) + taskbar paint in `taskbar/tbpaint.fi` | `traypop` chips | w-tray-icons |
| taskbar preview | `taskbar/tbhover.preview_*` (only place) on `uisurface` kind `FLYOUT` | - | w-taskbar-preview-ram |
| window chrome (frame, title, buttons, shadow) | `kernel/ui/wm/wmchrome.fi`, `wmshadow.fi` | - | (stable) |

Status: `uikit/uisurface`, `uikit/uiflyout`, the `I_*` icon tokens and `tools/uicheck` land in the follow-up commits of the UI system owner; until then the canonical scene code is `fuiscene` (fsdraw/fsctl).

Layers: tokens (`lib/fui/tokens.fi`) -> roles (`wlibc.theme`, `fuiscene.R_*`) -> primitives
(`fuiscene.cv_*`, `painter.*`, `wlibc.rect`) -> **components (`kernel/user/uikit/*`, `fuiscene`)** -> apps.
Apps call components only. Primitives outside component files are counted by `tools/uicheck`.

## 3. Rules for every UI change

1. Search first (`search`, `grep -r kernel/user/uikit kernel/user/fuiscene lib/fui`). If a component exists, use it.
2. No colour literals (palette ratchet `tools/palette/ratchet.py`), no raw primitives outside component
   files (`tools/uicheck/ratchet.py`): both counters only shrink.
3. New variant = new entry in the component's kind registry, not a copy.
4. Gate per component: pixel equality of the same component in two contexts + a mutant (old look) that
   must go red (`tools/uicheck/run.sh`).
5. Before landing: rebase origin/main, respect the owners above, run the ratchets.
