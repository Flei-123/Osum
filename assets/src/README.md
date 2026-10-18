# assets/src -- sources the shipped assets are cut from

| file | licence | what is cut from it |
|---|---|---|
| `Inter-Regular.ttf`  | SIL Open Font License 1.1 (`../LICENSE-OFL-inter.txt`) | `../osum-sans.ttf`      by `tools/design/mkfont.py` |
| `Inter-SemiBold.ttf` | SIL Open Font License 1.1 | `../osum-sans-bold.ttf` by `tools/design/mkfont.py` |

Inter 4.0, https://rsms.me/inter, `extras/ttf` of the release archive. The cut keeps the
characters of the old DejaVu cut, drops hinting and layout tables, and turns the GPOS pair
kerning into a legacy `kern` table (format 0, the 10 900 strongest pairs, the length field is
16 bit). It is reproducible octet for octet (`tools/wm/run.sh` part 3, `tools/i18n/run.sh`).

`osum-sans.cps` lists the 339 code points of the original DejaVu cut. Inter lacks three of them
(U+00AD soft hyphen, U+0149, U+FFFD); `mkfont.py` maps them to the glyphs `hyphen`, `n` and
`question` so that the character set -- and `tools/i18n/run.sh` -- stay complete.

## Fallback fonts (G-009 / r1084)

| file | licence | what is cut from it |
|---|---|---|
| `DejaVuSans.ttf` (fonts-dejavu-core 2.37) | Bitstream Vera licence, DejaVu changes public domain (`../LICENSE-dejavu.txt`) | `../osum-symbols.ttf` by `tools/design/mkfallback.py` |
| `NotoEmoji-Variable.ttf` (Noto Emoji, monochrome, variable) | SIL Open Font License 1.1 (`../LICENSE-OFL-noto-emoji.txt`) | `../osum-emoji.ttf` by `tools/design/mkfallback.py` (frozen at wght 400) |

`osum-sans.ttf` has no arrows, no Latin Extended-A/B beyond its 339 characters and no Emoji. `fuiglyph` loads the two cuts
(`/lib/symbols.ttf`, `/lib/emoji.ttf`) on the first miss only and asks them in that order. The cuts carry only code points the
sans lacks. The name table is dropped (the Vera licence forbids modified copies named "Vera"/"Bitstream").
`python3 tools/design/mkfallback.py assets/src/DejaVuSans.ttf assets/src/NotoEmoji-Variable.ttf assets/osum-sans.ttf
assets/osum-symbols.ttf assets/osum-emoji.ttf` reproduces both.
