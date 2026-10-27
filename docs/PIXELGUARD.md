# Pixelguard

Compares the composed back buffer with a full reference render of the same window state and reports differing pixels.

## Switches
- Kernel line: `pixelguard=all` (every frame) or `pixelguard` (sample), `pgfreeze` (stop after the first BAD), `pgbug=N` (counter-probe 1..5), `pgdump` (print the pixels around the BAD box).
- Settings: Pointer page, switch `debug.pixelguard` (`/etc/mouse.conf` key `pixelguard`), sets sample mode / off at run time.
- F12 prints `pixelguard: stat checks= bad= unstable= pending= skipped= card_bad= renders= us=`.
- `/proc/frames`: `frames.pixelguard.<mode|checks|bad|unstable|pending|skipped|px|card_checks|card_bad|x0|y0|x1|y1|win|us|renders>`.

## Output
`pixelguard: BAD level=A|B px= bbox=x0,y0,x1,y1 win= first= want= got=` (A = back buffer vs reference, B = card buffer vs back buffer). A BAD needs two consecutive hits on the same box.

## Gate
`/root/jarvis/bin/heavy bash tools/pixelguard/run.sh` (clean run, probes 1..5, Settings switch, procfs via OCR). Judge: `tools/pixelguard/judge.py`.

## Known
- Tooltip left corners: live shows square corners where the reference is rounded (`wlib: tip`, 46x24 at x=1,y=730); reproduced with `pgdump`.
- Dark switch (QS tile) animation produces BAD while fading; not part of clean.txt.
