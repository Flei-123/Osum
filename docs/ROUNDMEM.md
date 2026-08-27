# Round MEM -- the 512 MiB ceiling

**Date:** 27.08.2026 - Branch `ofs3`, on top of the OFS3 round - Acceptance:
`bash tools/mem/run.sh` -> **50 checks, 0 failures**, 24 s - Own commit,
separate from the file system work

---

## 1. The sentence this round is about

**Osum managed 512 MiB of RAM, and above one gibioctet it did not just
waste memory -- it died. It now manages what the memory map reports, and
64 GiB has been booted, mapped, written to and given back with not one
frame lost.**

---

## 2. The measurement before anything was changed

Same kernel image (`main`, 3389fbd), nothing but `-m` different. Every
number below is copied from a serial line, not computed.

| `-m` | `mmap:` says usable | `frames:` covered | free | QEMU exit |
|---|---|---|---|---|
| 512 | 523775 KiB | **131072** | 130298 | 21 (shutdown) |
| 2G | 2096639 KiB | **131072** | 130330 | **63 (exception)** |
| 8G | 8388095 KiB | **131072** | 130330 | **63** |
| 64G | 67108351 KiB | **131072** | 130330 | **63** |

Read the third column. The kernel **saw** every octet the loader
reported -- the first column is the memory map, and it is right at
64 GiB -- and it **managed** 512 MiB of it in every single run. That is
the first constant:

```
kstate.BITMAP_BYTES = 0x4000        // 16 KiB
mem.scan:  let frames = kstate.BITMAP_BYTES * 8   // 131072, always
```

Now read the fourth column. 63 is an exception, not a shutdown. From the
`-m 2G` run, word for word:

```
*** EXCEPTION 14 #PF  err=0x0  cr2=0x7ffe1adc
  rip=0x11625d  cs=0x8  rflags=0x206  rsp=0x275c50
```

`err=0x0` means "the page is not there", and `0x7ffe1adc` is just under
two gibioctets, where QEMU puts the ACPI tables. That is the second
constant, and it is in the assembler:

```
    /* --- PD: 512 entries of 2 MiB, identity mapped */
    movl $pd, %edi
    movl $512, %ecx
```

512 entries of 2 MiB is **one gibioctet**, and that was the whole
identity map. A bigger bitmap alone would have changed nothing: the
kernel would have handed out frames it could not touch.

---

## 3. The order in which it is undone

The hen and the egg of a frame allocator is that a bitmap for 64 GiB is
2 MiB of memory, and memory is what the bitmap is for. Three steps, and
each may only use what the one before it made usable. The same three
steps are written into the header of `kernel/mem.fi`.

**Step 1 -- the small map, exactly as before.** 16 KiB in the kernel
data area (`kstate.BITMAP_OFF`), 131072 frames, the first 512 MiB. It
needs no allocator because it is not allocated: it is a fixed part of a
data area the kernel already stands in. The memory map is walked,
everything usable below 512 MiB is released, the kernel, the map, the
multiboot structure and the boot modules are taken back. **After this
step there is a working frame allocator -- a small one.**

**Step 2 -- the identity map, grown with frames from step 1.** For every
gibioctet above the first that the memory map reports, one frame becomes
a page directory of 512 entries of 2 MiB, and the PDPT gets a pointer to
it. The frames come out of step 1, so they all lie below 512 MiB, so
they all lie inside the one gibioctet `boot.s` already mapped -- writing
into them cannot fault. That is the reason this is step 2 and not step 1.
The PDPT is found the way the processor finds it, `cr3 -> PML4 ->
PML4[0] -> PDPT`, not through a symbol out of the assembler file.
**After this step every octet the machine has can be read and written.**

**Step 3 -- the big map.** `ceil(top / 4096 / 8)` octets, rounded up to
whole frames, taken as **one contiguous run** (`frame_run_inner`). Every
bit starts as taken; then the 16 KiB of step 1 are copied over the front,
so the first 512 MiB keep their exact state -- **including the run that
was just handed out for the bitmap itself**. Only then is the memory map
walked a second time, and only frames at or above the old ceiling are
released (`release_from`); the low ones already carry the right answer.

Whoever swaps steps 1 and 3 gets a kernel that allocates its own bitmap
out of a bitmap that does not exist yet.

---

## 4. The measurement afterwards

Same kernel image, nothing but `-m` different, straight out of
`tools/mem/run.sh`:

```
-m         usable KiB       frames         free     bitmap  GiB map
128            130559       131072        31462      16384        1
256            261631       131072        64230      16384        1
512            523775       131072       129766      16384        1
1G            1048063       262112       260830      32764        1
2G            2096639       524256       522965      65532        2
8G            8388095      2359296      2095766     294912        9
16G          16776703      4456448      4192846     557056       17
64G          67108351     17039360     16775326    2129920       65
```

Every one of these runs ends with `kernel: done` and QEMU exit 21. Not
one exception in any of them.

Three things in that table are worth reading twice:

* **The `frames` column follows the first column now.** It used to be
  131072 in every line.
* **`-m 8G` maps nine gibioctets, not eight.** The memory map reaches
  `top=0x240000000` because a PC has a hole under 4 GiB for devices; the
  RAM sits below it and above it. The kernel maps up to the top and only
  releases what the map calls usable -- hence 2359296 frames covered but
  only 2095766 free, which is 8 GiB.
* **`-m 512` did not change.** Same 131072 frames, same 16384 octets of
  bitmap, same page directory out of `boot.s`. Steps 2 and 3 do nothing
  at all on a machine that has no more than the small map covers.

---

## 5. What it costs

One bit per 4 KiB frame is **32 KiB of bitmap per gibioctet of RAM**.
Checked against the reported frame count and not taken on faith:

| `-m` | frames | bitmap octets | `ceil(frames/8)` |
|---|---|---|---|
| 2G | 524256 | 65532 | 65532 |
| 8G | 2359296 | 294912 | 294912 |
| 64G | 17039360 | 2129920 | 2129920 |

At 64 GiB that is **2080 KiB of bitmap** plus **65 frames of page
directories** (260 KiB) = 2.29 MiB out of 65536 MiB, or **0.0034 %**.

---

## 6. The frames are really there

A number in a bitmap is not a frame. `memprobe` takes the highest free
frame the memory map covers, writes two words into it -- a marker and a
value derived from its own address -- and reads them back:

```
-m 512:  memprobe: at=0x1ffdf000   ok=1
-m 2G:   memprobe: at=0x7ffdf000   ok=1
-m 8G:   memprobe: at=0x23ffff000  ok=1
-m 64G:  memprobe: at=0x103ffff000 ok=1
```

`0x7ffdf000` is the address range in which the old kernel died.
`0x103ffff000` is 65 gibioctets up.

---

## 7. Nothing gets lost

`memstress` takes half of the free frames, capped at 200000, writes into
every single one of them, walks the chain back, checks every value and
gives every frame back. The list lives **in the frames themselves**: each
one carries the address of the previous frame in its first eight octets
and `addr XOR 0xA5A5A5A5A5A5A5A5` in the next eight. A frame handed out
twice breaks the chain or the check word, and both are noticed; a value
that is merely remembered would notice nothing.

```
-m 128:  want=15731  got=15731  before=31462     low=15731     after=31462     bad=0 seen=15731  ok=1
-m 512:  want=64883  got=64883  before=129766    low=64883     after=129766    bad=0 seen=64883  ok=1
-m 2G:   want=200000 got=200000 before=522965    low=322965    after=522965    bad=0 seen=200000 ok=1
-m 8G:   want=200000 got=200000 before=2095766   low=1895766   after=2095766   bad=0 seen=200000 ok=1
-m 16G:  want=200000 got=200000 before=4192846   low=3992846   after=4192846   bad=0 seen=200000 ok=1
-m 64G:  want=200000 got=200000 before=16775326  low=16575326  after=16775326  bad=0 seen=200000 ok=1
```

`before == after` in every line, `bad=0` in every line, and `low` is
lower than `before` by exactly `got` -- so the frames were really held
and not merely counted.

---

## 8. One thing had to be fixed on the way

`frame_alloc_inner` started its search at frame 0 **every single time**.
With 131072 frames that is a quarter of a mebioctet of bitmap in the
worst case and nobody ever noticed. With 16777216 frames it is two
mebioctets per call, and taking two hundred thousand frames in a row
becomes quadratic: measured, the stress test did not finish.

The fix is the one `kernel/fs.fi` already uses for the block bitmap:
remember the last frame handed out (`kstate.FRAME_HINT`) and start
there; a free that gives back something lower takes the hint down again.
It is a hint and not a promise -- the search still wraps around to 0 and
covers the whole map, so nothing can be lost, only found sooner.

The same reasoning made `release_from` and `count_free` work an octet at
a time where they can, instead of a bit at a time. At 64 GiB that is the
difference between a boot and a coffee break.

---

## 9. What is NOT proven

* **Measured in QEMU/TCG, on one machine, with no `/dev/kvm`.** Nothing
  here has run on real hardware. In particular, a real machine may have
  memory-mapped devices, reserved ranges and NUMA holes that this
  measurement does not contain.
* **The identity map is built as write-back cacheable 2 MiB pages for
  every gibioctet the map reports.** On QEMU that is harmless. On real
  hardware, mapping a range that turns out to be device memory with the
  wrong caching attribute is a real class of bug, and this round has not
  gone near MTRRs or PAT.
* **64 GiB is measured; 512 GiB is only arithmetic.** `MAX_GIB` is 512
  because one PDPT has 512 entries and one PML4 entry is used. Between
  64 and 512 GiB **nothing has been measured**. Above 512 GiB this
  kernel would need a second PML4 entry, and it does not have the code
  for it.
* **Two hundred thousand frames is not sixteen million.** The stress
  test walks upwards from the bottom and reached `0x31481000` (about
  790 MiB) at `-m 64G`. Every frame *between* there and the top has been
  counted and mapped, and exactly **one** of them -- the highest free
  one -- has been written to and read back (`memprobe`). A run that
  touches all 16 million has not been made; in TCG it would take hours.
* **The memory is never *used* at that size.** No process, no heap and
  no file system in this system asks for more than a few mebioctets. The
  round proves that the frames are managed and addressable, not that
  anything makes use of them.
* **`kalloc`/`kfree` are untouched.** The kernel heap is still 256 KiB
  out of 64 contiguous frames (`kmain.fi`), it is still first fit, and
  it still has no size classes. That ceiling is a different round.
* **Nothing measures what happens when the memory map is a lie.** A
  loader that reports RAM which is not there would get a kernel that
  maps it and hands it out. The old kernel had the same property below
  512 MiB; this round widens it rather than fixing it.
* **The 8 GiB case covers a hole.** 2359296 frames are covered but only
  2095766 are free, and the difference is the device hole under 4 GiB.
  That the hole stays taken is measured; that every single reserved
  range of a real firmware would be handled the same way is not.

---

## 10. How to measure it again

```
bash tools/mem/run.sh      # 50 checks, ~24 s

# by hand, one size:
bash tools/build-kernel.sh /tmp/k.mb
qemu-system-x86_64 -kernel /tmp/k.mb -m 64G \
    -append "memstress nokbd nosched noproc nofs noring3" \
    -serial stdio -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04
```

New lines on the serial console, in every boot:

```
mem: bitmap=2129920 octets  mapped=65 GiB  of 65 GiB
```

and with the word `memstress` on the command line:

```
memstress: want=... got=... high=0x... before=... low=... after=... bad=0 seen=... ok=1
memprobe: at=0x103ffff000 ok=1
```
