# r348: the boot crash after "ring3: back in ring 0" (06.10.2026, FIXED: the ring-3 interrupt stack was too small)

Machine: `tools/design/eh6.sh` as `tools/zreap/run.sh` builds it (gfx, xHCI + usb-kbd + usb-mouse,
1 core, `nosched noproc nofs`), KVM. Boot loop without gdb: 1 of 40 boots dies
(and 3 of 3 collected crashes look the same):

    ring3: back in ring 0
    *** EXCEPTION 6 #UD   rip=0x67   cs=0x8  rflags=0x10202  rsp=0x8fc680  ss=0x10
    rax=1 rbx=0x9500 rbp=0x314 r10=0x92a800 ... (pid 1, "ANDERE KERNE: keiner")

* It is **not** the r378 race (1 core, boot task, with the r378 fix it still happens).
* It does **not** happen without a screen (`tools/execsmp/crash.sh 60 1`: 0 of 60).
* Same place every time: the kernel stack of the boot task (0x8bf000..0x8ff000), the
  word at 0x8fc678 = stack top - 0x2988. A `ret` pops 0x67 from it (other build: 0xc7 one
  word lower). The stack above it holds old `fb.*`/`wm.*` frames (text drawing), the live
  callers are gone: the slot is not a return address any more.
* `gdb` on KVM (hardware breakpoints work, software ones do not): a conditional
  hardware watchpoint on 0x8fc678 ("value between 1 and 0xfff"), armed at `unmap_user`
  (the first thing after the excursion), saw **no CPU write** before the exception frame
  itself. So the word was not written by code running on the CPU after the excursion:
  either it was already wrong at that moment, or a device wrote it (DMA), or `rbp`/`rsp`
  were off by a word at the `leave`/`ret` (rbp=0x314 is not a frame pointer).
* Next: watch the same word from the START of `user.run` (not only after), and compare
  `rbp`/`rsp` at every `leave_user`; check the devices that DMA (xHCI rings live in kdata,
  not near the stack; IDE is PIO) and the `fb` text path that runs after the excursion.

Tools used: `/tmp/r348/loop.sh`-style boot loop (KVM, 40 boots) and `gdb -batch` with
`target remote` + `hbreak _F0.trap__report` (copy of the commands is in the roadmap note).


## ROOT CAUSE FOUND AND FIXED (06.10.2026, evening)

**A timer interrupt that hits the boot task while it is in ring 3 ran the diagnostic board on a 16 KiB stack
that needs 44 KiB.** The stack ran through `df_stack` and into the top of `kernel_stack`, over the frames of
the functions that had entered ring 3. Nothing else wrote, which is why the watchpoint on one word saw no CPU
write after `unmap_user`: the writer had finished before the excursion returned.

How it was measured (not guessed):

1. *Probe in `user.run`:* a snapshot of 3 KiB..16 KiB above `rsp` before `enter_user`, compared right after it
   returns and BEFORE `sti`. Clean boots: 0 words differ. Crashed boots: 480 words differ (3 840 octets),
   new content = frames with the kdata pointer 0x8c4000 and return addresses in `fb.blit` / `fb.line`.
2. *Same probe, `sti` moved behind the compare:* the damage is already there before interrupts are on again, so
   it happens during the excursion, with no task switch (a print in `sched.schedule_locked` stayed silent).
3. *gdb on KVM* (hardware breakpoints at `enter_user`, `leave_user`, `isr_common`): the first interrupt
   arrives in ring 3 (`cs=0x2b`, rip 0x600010) at `rsp=0x8bbfc8` = the top of `syscall_stack`, which is
   TSS.rsp0 (`sched.set_kernel_stack(vector 61)`). The next write to the damaged word comes from
   `trap.entry -> lower_chunk -> gfx.tafel_tick -> kgui.tafel_streichen -> wm.messzeile -> fb.fill ->
   fb.hline -> fb.dirty_x -> fb.dirty_rect` with `rsp=0x8b1270`: 0xad58 = 44 376 octets below the stack top.
4. Memory order (boot.s): `kernel_stack` 0x874000..0x8b4000, `df_stack` ..0x8b8000, `syscall_stack` ..0x8bc000.
   44 KiB from 0x8bc000 ends 12 KiB inside `kernel_stack`.

Why 1 in 10-40 boots and only with a screen: the board paints a line only on some ticks, and only a tick that falls
inside the (short) excursion goes through this path; without a screen (`tafel` off, no `fb`) the handler is shallow.

**Fix:** `syscall_stack` 16 KiB -> 128 KiB (three times the measured depth), `irq_stack` 16 KiB -> 64 KiB
(boot.s, `.bss`, no cost in the image). Measured: see the commit message.

**Not done (roadmap):** the real cause is "painting from an interrupt handler"; the board should paint from a
task, and `trap.entry` should check the stack depth in debug builds (a guard page below `syscall_stack`).
