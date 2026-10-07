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
