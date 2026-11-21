# Explorer icons

Sources: `assets/icons/explorer/<name>.svg`, registry `assets/icons/explorer/index.txt` (`name<TAB>description`). Style = `docs/APP-ICONS.md` (viewBox 24, flat two-tone, round caps, no gradients).
Load by name: read `assets/icons/explorer/<name>.svg` and render with `lib/svg` (`svgdoc.render`, baker `tools/svg/bake.fi`) at 16/24/32/48.

## Names

- Folders (amber, front panel carries the glyph): `folder`, `desktop`, `documents`, `downloads`, `pictures`, `music`, `videos`
- Places: `drive`, `usb`, `quickaccess` (star), `gallery`, `home` (Start page), `pin`
- Toolbar: `filter`, `preview`, `share`, `rename`, `cut`, `copy`, `paste`, `delete`, `sort`, `view`

## Gate

`bash tools/explorericons/run.sh`: baker exit 0 (16/24/32/48), alpha error vs cairosvg, bbox center within 1 px of the middle, <= 62 % opaque, >= 6 colours, outline contrast on light and dark, only allowed elements, registry row per file, 3 counter-proofs.
Contact sheet: `python3 -I tools/svg/contact.py <out.png> assets/icons/explorer/*.svg`.
Add an icon: draw the SVG, add a registry row and the name to REQUIRED in the gate.
