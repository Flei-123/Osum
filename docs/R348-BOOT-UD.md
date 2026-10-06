# r348: the boot crash after "ring3: back in ring 0" (measured 06.10.2026, NOT fixed)

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

## Update 06.10.2026 (later): two ideas read out of the code and refuted

Both came from the same question -- what writes a small number (0x67 = `g`, 0xc7) into a
return-address slot 14 KB below the top of the boot task's kernel stack -- and both are
**not** it:

1. *A syscall or an interrupt of the ring-3 excursion running on the boot task's stack.*
   Not so: the excursion's syscalls use `%gs:CPU_KSTACK`, which `sched.init` sets to
   `vector(61)` (`T_KTOP` of task 0 is that too), the dedicated syscall stack; interrupts from
   ring 3 use `TSS.rsp0` = the dedicated irq stack. From `nm` of a kernel image:
   `boot_stack` 0x8bc000..0x8c0000, `kernel_stack` 0x8c0000..0x900000 (the boot task's, 256 KB),
   `df_stack` 0x900000..0x904000, `syscall_stack` 0x904000..0x908000, `irq_stack`
   0x908000..0x90c000, `tss` 0x90f000, `kdata` 0x910000. No overlap, and `set_kernel_stack` on a
   switch back to task 0 writes the same dedicated top again.
2. *The xHCI rings or the scratchpad buffers overlapping the stack.* The rings live inside
   `kdata` (fixed offsets, `state + ..._OFF`), the scratchpad pages come from
   `mem.frame_alloc` (`xhci.scratchpad`); nothing there points below 0x910000.

What is left from the measurements above: it needs the screen (0 of 60 without), the word is
written by something that is not a CPU store after `unmap_user` (the hardware watchpoint saw
none), and rbp is wrong too (0x314). The next experiment that is not a guess: record the value
of that word at the START of `user.run` and again right after `leave_user` (a few lines
of `serial.hex`), in the 1-in-40 boot, to learn whether it is already wrong before the
excursion (then it is an earlier writer: look at what runs between the kernel's first text
drawing and `user.run`) or changes inside it.
