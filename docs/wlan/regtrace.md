# regtrace v1 -- shared register trace format (Osum and Linux)

One text format for everything the host does to an Intel WLAN device. Osum writes it (`/proc/wlan_trace`),
the Linux side (mmiotrace on the live stick, converter by W-wlantrace) writes the same lines, and
`tools/regtrace` (parse, normalize, diff) compares two traces.

## Line format

```
<seq> <t_us> <kind> <space> <offset> <value> [ctx...]
```

- Fields are separated by single spaces. `#` starts a comment line (header lines are `# regtrace v1 <source> ...`).
- `seq`: decimal, increasing per record. `t_us`: decimal microseconds, any epoch (0 if unknown). Both are dropped by normalize.
- `offset`, `value`: lowercase hex, no prefix, 8 digits (`wid` offsets 4 digits). 32-bit values.
- `ctx`: optional `key=value` tokens (hex values without prefix).

## Kinds and spaces

| kind | space | offset | value | ctx | produced by |
|------|-------|--------|-------|-----|-------------|
| `r32` | `csr` | byte offset inside BAR0 | value read | | Osum accessor, Linux mmiotrace |
| `w32` | `csr` | byte offset inside BAR0 | value written | | same |
| `prph_r` | `prph` | 20-bit periphery address | value | | folded by `tools/regtrace` from `HBUS_TARG_PRPH_RADDR/RDAT` |
| `prph_w` | `prph` | 20-bit periphery address | value | | folded from `HBUS_TARG_PRPH_WADDR/WDAT` |
| `sram_r` | `sram` | device SRAM address | value | | folded from `HBUS_TARG_MEM_RADDR/RDAT` |
| `sram_w` | `sram` | device SRAM address | value | | folded from `HBUS_TARG_MEM_WADDR/WDAT` |
| `hcmd` | `host` | wide id `ggcc` (group, cmd) | payload length | `v=<ver> d=<payload hex> [t=1]` | host command sent; payload = bytes after the 4-byte header |
| `rx` | `host` | wide id `ggcc` of the packet | payload length | `d=<first 64 payload bytes hex> [t=1]` | response or notification received |
| `dma_desc` | `dma` | descriptor index | low 32 bits of the buffer address | `ah=<hi32> l=<len 8hex> q=<queue 4hex>` | TFD/RBD written (Osum only) |
| `irq` | `csr` | `00000008` (CSR_INT) | interrupt cause | | interrupt taken (Osum only) |

- `t=1` means the payload was truncated; the real length is in `value`.
- Producers emit only the physical level (`r32`/`w32` on BAR0). `prph_*` and `sram_*` are folded by the parser from the
  `HBUS_TARG_*` register pairs (CSR 0x444 waddr, 0x448 raddr, 0x44c wdat, 0x450 rdat for prph; 0x410 waddr, 0x40c raddr, 0x418 wdat, 0x41c rdat for mem; mem data accesses auto-increment by 4), so Linux and Osum
  normalize identically. Address flags in the upper bits (`3<<24` dword flag) are masked.
- Records that exist on one side only (`dma_desc`, `irq`, ...) are removed by `normalize --keep` (default keeps
  `r32 w32 prph_* sram_* hcmd`).

## Normalized form (`tools/regtrace normalize`)

No seq, no time, no BAR base (`--bar <hex>` subtracts an absolute base from csr offsets). One entry per line:

```
w32 csr 00000024 00000008
prph_w prph 00a02c60 00000001
poll csr 00000024 until 00000008        (run of reads of one register; xN is shown in the report only)
hcmd host 0c00 00000010 v=0 d=...
```

A `poll` entry replaces two or more consecutive reads of the same register (or the same `HBUS_TARG_*` read pair); `until` is the
last value. The count is not compared (timing differs between machines).

## diff

`tools/regtrace diff a b` reports the first differing normalized entry: register/command, expected (a) vs actual (b),
and the context: the last `hcmd` seen before that point. Exit 1 on difference, 0 if equal.

## Osum side

- Switch: boot word `wltrace` or `trace=1` in `/etc/wlan.conf` (runtime: `wlanctl reload wltrace on`). Off = one flag test per access, no buffer.
- Read: `/proc/wlan_trace` (offset reads, any chunk size). Header: `# regtrace v1 osum first_seq=<n> records=<n> cap_slots=<n>`.
- The ring keeps the newest records; `first_seq` > 0 means older ones were overwritten.
- Code: `lib/wlan/regtrace.fi` (ring + formatter), accessors `iwl_probe.rd32/wr32`.
