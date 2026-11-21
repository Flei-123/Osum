# App icons — one hand-built SVG per program

Source of truth: `assets/icons/app/<name>.svg`. `tools/svg/apps.tsv` maps a bundle to its source (`=<name>`, or `@<brand>` for a brand logo
in `assets/icons/brand/`). `bash tools/svg/apps.sh [app...]` copies the SVG to `<bundle>/symbol.svg` and bakes `symbol.osym` (72) +
`symbol44.osym` + `symbol64.osym` with our own renderer (`lib/svg`, baker `tools/svg/bake.fi`).

## Style

- Canvas `viewBox="0 0 24 24"`, `width/height 72`. Free-standing object, NO filled tile behind it (`tools/iconaudit`: <= 62 % opaque, corners not all opaque).
- Flat two-tone: body fill = hue 500, light detail = hue 200, outline = hue 800. No gradients, no alpha, no blur.
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

## Contact sheet

`python3 -I tools/svg/contact.py <out.png> assets/icons/app/*.svg` renders every icon at 16/24/32/48/72 px on light and dark.

## Add a program

1. Draw `assets/icons/app/<name>.svg` in the style above. 2. Add a row to `tools/svg/apps.tsv`. 3. `bash tools/svg/apps.sh <app>`. 4. `bash tools/iconaudit/run.sh`.
