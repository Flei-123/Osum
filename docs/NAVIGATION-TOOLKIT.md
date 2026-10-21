# Navigation toolkit (TK) — container in container

Status: design + core library (21.10.2026). Code: `lib/nav/*` (English only, no heap, static tables, kernel-profile safe like `lib/fui/navnum.fi`).
Users: Settings (SET-2..4), Explorer, Task Manager, Store, Control Center. Reuses `lib/settingsman` (manifest style, errors, rollback) and the fUi scene tree (`kernel/user/fuiscene.fi`); it does not replace either.

## 1. Model

```
sidebar entry (main category)  ->  category page  ->  sub page  ->  (row focus)
settings://personalization        settings://personalization/taskbar
```
* A **route** is one addressable place. Every route has a URI, a catalogue title key, a symbol, an order, a parent (derived from the URI), flags and a control count.
* An **app root** (`settings://`) is created by the `app` line. Routes below it form a tree: sidebar = children of the root, depth <= 4 (`MAX_DEPTH`).
* **Dynamic routes** (flag `dynamic`) own a whole subtree that is not registered: `explorer://folder` resolves every `explorer://folder/usr/share` to the same route plus the rest path (folder in folder). Crumbs and stack work on the full URI.

## 2. URI grammar (`lib/nav/route.fi`)

```
uri    = scheme "://" [ seg *( "/" seg ) ] [ "?" key "=" val *( "&" key "=" val ) ]
scheme = [a-z] *( [a-z0-9] / "-" )          ; 1..16, equals the app name
seg    = 1*( [A-Za-z0-9] / "-" / "." / "_" / "~" / "%" HEX HEX )   ; "." and ".." are invalid
```
* Static routes: segments `[a-z0-9._-]`. Dynamic remainder: any bytes, percent-encoded (`route.enc_seg` / `route.dec_seg`), so `explorer://folder/My%20Docs`.
* Canonical form (`route.canon`): lower-case scheme, no empty or trailing segment, query kept after the path. Length <= 255. Equality is byte equality of the canonical form.
* Query is only a hint for the page (`?row=brightness` = scroll to and highlight that row). It never selects the route, is not part of back/forward identity and is stripped by `route.path_len`.

## 3. Route manifest `ROUTES` (`lib/nav/loader.fi`)

Same line format and rules as `SETTINGS` / `ACTIONS`: words split at blanks, `#` starts a comment. Built-in apps embed it with `__include_str`; a package ships `/apps/<app>.prog/ROUTES`; admins may drop `/etc/routes.d/*.routes`.

```
routes 1
app settings settings.app.title symbol-gear
limit 8                                     # optional: max controls per page for this app (default 8)
route settings://personalization settings.page.personalization.title symbol-palette 10
kw settings.page.personalization.kw         # directly after route: extra search words (catalogue key)
controls 6                                  # directly after route: primary controls on the page
related settings://personalization/themes settings.related.themes
route settings://personalization/taskbar settings.page.taskbar.title symbol-bar 20 advanced
route explorer://folder explorer.folder.title symbol-folder 10 dynamic
```
* `route <uri> <title-key> <symbol> <order> [flag...]`; flags: `advanced` (collapsed / not in the sidebar), `hidden` (not in sidebar and crumbs only), `dynamic`, `home` (opened by an empty URI).
* `kw`, `controls`, `related` bind to the `route` line directly before them (any order, at most one `kw` and one `controls`, up to 4 `related`).
* Rules (as `settingsman`): a KNOWN line with wrong words, bad name, duplicate URI, scheme != `app`, parent route not registered earlier, depth > 4, table full -> the WHOLE file is rejected and the registry is exactly as before (`err_code()` / `err_line()`). Unknown lines are skipped and counted (`warn_count()`).
* Limits: 8 apps, 192 routes, 96 related links, 20 KiB text pool. A package may register only its own scheme (`E_MISMATCH` like `add_pkg`).
* Settings **Manifest v2** (`page ... parent ...`) is converted to routes at load time (SET-2): `page <id>` becomes `settings://<category>/<id>`; the route table is the one source for sidebar, breadcrumb and search.

## 4. Registry API (`lib/nav/reg.fi`)

`load(buf,len)`, `add(buf,len)`, `add_pkg(buf,len,dir)`, `reset()`, `count()`, `find(uri,len) -> id|NONE`, `resolve(uri,len) -> id|NONE` (longest registered prefix, dynamic routes accept a rest path; `rest_off()`), `parent(id)`, `child_count(id)`, `child_at(id,i)` (ordered by `order`, then registration), `depth(id)`, `uri(id)`, `title_key(id)`, `icon_name(id)`, `flags(id)`, `controls(id)`, `kw_key(id)`, `related_count(id)`, `related_to(id,i)`, `related_key(id,i)`, `lint(limit_override) -> violations` (checks section 7).

## 5. Stack (`lib/nav/stack.fi`)

Per window (instances 0..3): `push(h,uri,len)`, `back(h)`, `forward(h)`, `up(h)`, `replace(h,uri,len)`, `current(h)`, `can_back/can_forward/can_up`, `aux_set/aux_get(h)` (scroll offset to restore).
* `push` of the current route is a no-op (same path); a push after `back` drops the forward tail (browser semantics); capacity 32, the oldest entry falls out.
* `up` = parent in the registry; for a dynamic rest path = one segment less; root has no parent. `up` pushes like a normal navigation.
* Keys (Settings/Explorer/Store alike): Alt+Left / Backspace / mouse button 4 = back, Alt+Right / button 5 = forward, Alt+Up = up, Esc = back one level in a page-less view, Ctrl+F = search.

## 6. Crumbs (`lib/nav/crumbs.fi`) and search (`lib/nav/search.fi`)

* `crumbs.build(uri,len) -> n`: root ... route ... dynamic segments, each with `crumb_uri(i)`, `crumb_key(i)` (catalogue key, static) or `crumb_seg(i)` (decoded text, dynamic), `crumb_dynamic(i)`. `crumbs.fit(widths, n, avail, sep_w) -> first` keeps the last crumb and as many before it as fit; the hidden head collapses to one `...` crumb whose menu lists them.
* **Search:** the app resolves catalogue text itself (current language) and feeds it: `search.set(id, title, kw)` for every route (and `search.set_row(...)` for rows, `row` = query hint). `search.query(q,len,out,cap) -> n`: every query word must be a case-insensitive prefix of a word of title+kw; rank 0 = all words in the title, rank 1 = elsewhere, ties by tree order. Hidden routes are searched, `dynamic` routes are not. Result line = title + crumb path; opening a result = `stack.push(uri)` + row highlight.
* **Related links:** `related` lines render as a "Related" row group at the end of a page (icon + label + chevron); activating one is `stack.push(to)`. They are the Windows "Related settings" equivalent and cross app boundaries only through the broker (scheme `explorer://` from Settings is allowed, the receiving app decides).

## 7. Limits and lint (gate material)

* **Controls per page <= `limit` (default 8, configurable per app by the `limit` line or `reg.limit_set`)**; a landing page counts its sub-page link rows as controls; `advanced` routes are exempt; a route without a `controls` line is reported as "unmeasured".
* Further lint: depth <= 4, every non-root route has a parent, sidebar entries (depth 1, not advanced/hidden) <= 12, titles unique among siblings, `order` unique among siblings, related targets exist.
* Host runner `bash tools/nav/run.sh` (seconds, no VM) with counter-proofs: golden cases for URI / registry / stack / crumbs / search, "search finds every route" over the real Settings route table in `en` and `de`, and N parser/stack/search mutations that must turn it red.

## 8. View and scene-tree integration (`kernel/user/navview.fi`)

Built (21.10.2026): `navview.toolbar` (nav.back / nav.forward / nav.up buttons), `navview.crumbs_row` (crumb buttons over `lib/nav/crumbs`, last crumb is a label, at most 5 shown), `navview.action_of(key)` / `crumb_target_len(key)`. The builders live in `kernel/user` because they import `fuiscene` (layer rule: `lib` does not import `kernel/user`). Settings glue: `kernel/user/setroute.fi` (route table + `settings.d/settings.pagemap` page map, stack instance 0, search feed, sidebar order). NOT built yet: `related` rows, `results` list (search filters the sidebar and Enter opens the best hit), Alt+Left/Right keys. Original plan below.

* Three reusable builders over `fuiscene`: `view.sidebar(parent, h)` (children of the app root, symbol + title, active entry accent, one tab stop per entry), `view.crumbs(parent, h)` (buttons `nav.crumb.<i>`), `view.related(parent, id)` (rows `nav.rel.<i>`), `view.results(parent)` (search results).
* Stable scene names (used by gates and the a11y tree): `nav.side.<route-id>`, `nav.crumb.<i>`, `nav.back`, `nav.forward`, `nav.up`, `nav.search`, `nav.result.<i>`, `nav.rel.<i>`. The a11y role of the sidebar is `list`, entries `listitem`, crumbs `navigation`/`button`.
* Event glue: the app maps keys to `view.on_key(h,key)` and clicks to `view.on_click(h,name)`, both return a URI to open (or none). Opening = `stack.push` then the app builds the page for `reg.resolve(uri)`.
* Narrow windows: the sidebar becomes the first stack entry (`app://` root list) and `nav.back` returns to it — the same code path, no special layout.

## 9. i18n and a11y

* Keys: `<app>.page.<route-id>.title|kw`, `<app>.related.<id>`, `nav.back|forward|up|search|search.empty|related|more` in `locale/en` and `locale/de` (checked by the host runner: every key of every route in both catalogues, label <= 38 characters).
* Every sidebar entry, crumb and related row has an accessible name (= its title); the focused sidebar entry is announced with its crumb path; keyboard: Tab = one stop per area, Up/Down inside the sidebar, Enter opens.

## 10. Rollout

1. Core lib + host gate `nav` (this change). 2. `ROUTES` for Settings + SET-2 (sidebar / breadcrumb / row search in `settings.fi` through `view.*`). 3. Explorer (`explorer://folder/<path>`: crumbs and stack replace the private path history). 4. Task Manager / Store / Control Center reuse the same builders.
