# Firn pin and patch upstream status

Checked 02.11.2026 against /root/firn (origin/main 534d6ad7).

## Pin
- vendor/firn/COMMIT = b6bf6765, present in /root/firn and reachable from origin/main.
- The old pin 7b4c22b1 and the bundle repo-backup/firn-vor-rewrite.bundle are no longer needed (bundle is gone; fallback in fetch-firnc.sh is inert).
- HERKUNFT.md describes the pre-rewrite history and is outdated regarding the hash.

## Verification
- `tools/firnpin/check.sh` (pin) and `tools/firnpin/check.sh origin/main` (pin candidate): build firnc0, apply all patches, build firnc1 from a temp copy with --force.
- 02.11.2026: pin b6bf6765 OK, origin/main 534d6ad7 OK (all 12 patches apply, firnc1 builds).
- Run under /root/jarvis/bin/heavy.

## Patches (none upstream yet, all apply on pin and on origin/main)
| Patch | Touches (lib/) | Upstream |
|---|---|---|
| 0001-rundruf-ohne-arp | net/stack.fi | not upstream |
| 0002-buf-grow-antwortet | firnc1/rt.fi, html/mem.fi, rt/rt.fi, std/deflate.fi, std/rt.fi | not upstream |
| 0005-rt-rt-heisst-std-rt | paint/png.fi, str/ucd.fi | not upstream |
| 0006-netzplus-ws-ts-sack-pmtu | net/stack.fi, net/tcp.fi, net/wire.fi | not upstream |
| 0007-time-wait-slot-reuse | net/tcp.fi | not upstream |
| 0008-tcp-keepalive | net/stack.fi, net/tcp.fi | not upstream |
| 0009-font-fallback | font/ttf.fi | not upstream |
| 0010-font-face-table | font/ttf.fi | not upstream |
| 0011-font-vertical-hint | font/ttf.fi, fui/painter.fi | not upstream |
| 0012-fui-corner-coverage-8x8 | fui/core.fi | not upstream |
| 0013-blog-no-std-io | plat/blog.fi | not upstream |
| 0014-font-kern-cache-caller-memory | font/ttf.fi | not upstream |

Numbers 0003 and 0004 do not exist in patches/ (retired earlier; no record kept).
