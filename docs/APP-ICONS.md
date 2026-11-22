# App icons — one hand-built SVG per program

## One registry, resolved by program id

- Runtime: every consumer (start menu list and search, task bar, task manager, store tiles, elevate dialog) calls `appreg.symbol_for(id, slot)`.
  It reads `/usr/share/appreg/<id>/symbol` first and falls back to `/apps/<id>.osp/symbol` only for packages that ship their own picture.
  The fallback for a program with neither is the generic letter tile (`lib/appicon.fi`). No per-program glyph or colour table exists in code.
- Build: `tools/appreg/build.py` writes one registry entry per row of `tools/svg/apps.tsv` (plus `apps.tab` and `alias.tsv`), joined from the baked 72/44/64 pictures.
- Swap an icon: replace `assets/icons/app/<name>.svg`, run `bash tools/svg/apps.sh <app>`, rebuild the image. Nothing else changes.
- Gate: `bash tools/iconreg/run.sh` (host only) is red when a file outside `kernel/user/appreg.fi` names an icon path, when code holds a per-program icon table, when a copy of an icon differs from its central source, or when a program has no registry entry. Ratchet value `icons outside registry` must stay 0.

## Registry consumers beyond the start menu

- Tray: the flyout tile (`traypop.app_glyph`) and the bar tray (`tbapps.paint_registry`) look up the tray owner name as program id with `storeicon.registry_slot`. No registry entry keeps the old plate with the first letter (flyout) or the generic program glyph (bar).
- Explorer: program rows (executables, `.osp` bundles) in the list, table and icon views use `storeicon.registry_slot_for_file` (name without `.osp` = program id). The slot ring is reset per listing build; the first 12 distinct programs of a listing get their picture, later rows keep the generic program glyph.
- Store catalog: tiles of packages that are not installed resolve the package id in the registry (every id of the feed `apps.tsv` has an entry). Third-party packages unknown to the registry still get the letter tile; icons of third-party packages: see the signed feed format below.

## Homepage export (build / deploy)

- Interface: `python3 -I tools/appreg/export.py --out <dir> [--repo <osum checkout>] [--ref <git ref>]`.
  It writes `<dir>/<app id>.svg` for every id of `tools/svg/apps.tsv` plus every alias of `tools/appreg/alias.tsv`, and `<dir>/index.json` (`schema_version`, `commit`, `icons.<id> = {file, source, title, alias_of}`).
  With `--ref` (for example `origin/main`) it reads through `git show`, so the homepage build needs no checkout.
- The homepage (`/root/projects/osum-site`, templates use `{{icon:<app id>}}`) takes icons only from this export or from the same sources (`apps.tsv` row, `assets/icons/app|brand/<name>.svg`) at a pinned ref; it keeps no icon files and no hand-written `<symbol>`.
- Gate: `tools/iconreg/run.sh` check "homepage takes icons only from the registry" (site dir `ICONREG_SITE`, default `/root/projects/osum-site`, skipped when absent) is red for a file under `src/assets/icons/`, an inline `<svg`, or a `{{icon:id}}` without registry id; the run also checks the export (every id has its SVG, aliases resolve).

Source of truth: `assets/icons/app/<name>.svg`. `tools/svg/apps.tsv` maps a bundle to its source (`=<name>`, or `@<brand>` for a brand logo
in `assets/icons/brand/`). `bash tools/svg/apps.sh [app...]` copies the SVG to `<bundle>/symbol.svg` and bakes `symbol.osym` (72) +
`symbol44.osym` + `symbol64.osym` with our own renderer (`lib/svg`, baker `tools/svg/bake.fi`).

## Style

- Canvas `viewBox="0 0 24 24"`, `width/height 72`. Free-standing object, NO filled tile behind it (`tools/iconaudit`: <= 62 % opaque, corners not all opaque).
- Flat two-tone: body fill = hue 500, light detail = hue 200, outline = hue 800. No gradients, no alpha, no blur.
- Delivered set (22.11.2026, Boss choice): `calc editor terminal lock cliphist explorer charmap snip` use `viewBox 0 0 256 256`, a vertical
  `linearGradient` on the body and a soft ground shadow. The renderer has no `filter`, so `python3 -I tools/svg/softshadow.py <delivered.svg> <out.svg>`
  replaces the blurred ellipse by nine stacked black `ellipse` layers (non-negative least-squares fit to the Gaussian-blurred ellipse) and the `text`
  glyph by its DejaVu Serif outline. Measured against the delivered PNGs (Lanczos to 72/64/44 px, light and dark ground): mean RGB error 0.9-3.0 of 255.
- Outline stroke 1.5, detail strokes 1.7-2.4, round caps and joins, corner radius 2.5-3 on bodies, 1.2-1.8 on small parts.
- Paper-like surfaces use `#f1f5f9` with the hue-800 outline; the terminal screen uses `#1e293b` with a `#64748b` outline.
- Never let two shapes share an outer edge (two partially covered pixels composite twice and break the 22 px row check): draw fills first, the outline of the window/body LAST as one stroke-only shape.
- The hue-800 outline keeps the silhouette on light backgrounds, the hue-500 body keeps it on dark backgrounds (checked with `tools/svg/contact.py`).
- Allowed elements (renderer limits): `svg g path rect circle ellipse line polyline polygon linearGradient stop`, `fill-rule`, `transform`.
  Not available: `radialGradient`, `clipPath`, `mask`, `use`, `text`, `filter`. `tools/svg/bake` exits 5 on anything unsupported.

## Palette (hue: light / body / outline)

slate `#cbd5e1 #64748b #334155`, blue `#bfdbfe #3b82f6 #1e40af`, sky `#bae6fd #0ea5e9 #075985`, teal `#99f6e4 #14b8a6 #115e59`,
green `#bbf7d0 #22c55e #166534`, amber `#fde68a #f59e0b #92400e`, orange `#fed7aa #f97316 #9a3412`, red `#fecaca #ef4444 #991b1b`,
pink `#fbcfe8 #ec4899 #9d174d`, violet `#ddd6fe #8b5cf6 #5b21b6`, indigo `#c7d2fe #6366f1 #3730a3`.

## Brand exceptions

Certus and Firefox keep their real brand logos (`assets/icons/brand/*.svg`, rasterised with cairosvg because they use radial gradients).

## Icons of third-party packages (signed feed format)

- Installed package: the recipe ships `datei=symbol` (joined OSYM, 72/44/64 px); it lands in `/apps/<id>.osp/symbol` and is covered by the package signature. `appreg.symbol_for` reads it after the registry. System ids never come from here.
- Not installed (store tile): the catalog app carries `icons{72,44,64}` = `{datei, sha256, groesse}`, PNG, content addressed under `symbole/`. The signed client view `apps.tsv` (`A` line, icon field) names the 72 px file; the file name contains its SHA-256, so the signature on `apps.tsv.sig` pins the picture. The client checks the hash after download and discards on mismatch.
- Resolution order on the client: registry id, installed bundle `symbol`, feed picture (cached per package id and revision), letter tile. A missing or unverified feed picture never blocks a tile.
- No new feed field is needed: the existing `A` icon field is the format. Open: client fetch, PNG decode and cache (roadmap).

## Contact sheet

`python3 -I tools/svg/contact.py <out.png> assets/icons/app/*.svg` renders every icon at 16/24/32/48/72 px on light and dark.

## Add a program

1. Draw `assets/icons/app/<name>.svg` in the style above. 2. Add a row to `tools/svg/apps.tsv`. 3. `bash tools/svg/apps.sh <app>`. 4. `bash tools/iconaudit/run.sh`.
