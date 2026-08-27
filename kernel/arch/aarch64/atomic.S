/* kernel/arch/aarch64/atomic.S -- the counterpart to kernel/atomic.fi,
 * and the one file of this port that is not a translation but a CORRECTION.
 *
 * `kernel/atomic.fi` says, in as many words:
 *
 *     "On x86-64 an ALIGNED 64-bit read or write is atomic in the hardware
 *      (SDM volume 3, 8.1.1) ... So `load` and `store` below are
 *      `__mmio_read64`/`__mmio_write64` and nothing else, and the pair is a
 *      correct atomic load/store on this architecture. On a machine with a
 *      weaker memory model it would not be, and then this file is the one
 *      place that has to change."
 *
 * This is that machine, and this is that change. The sentence was right
 * about the load and the store themselves -- an aligned 64-bit access is
 * single-copy atomic on AArch64 too. It is wrong about everything around
 * them, because x86-64 is TSO and AArch64 is not:
 *
 *   * On x86 a store is never moved ahead of an older store, so releasing a
 *     lock with a plain store publishes everything the holder wrote. The
 *     same code on AArch64 lets the unlocking store become visible BEFORE
 *     the data it was protecting. `atomic.fi` names exactly this as the
 *     reason its plain store is enough -- and names it as an x86 fact.
 *   * On x86 a load is never moved ahead of an older load, so taking a lock
 *     with a plain compare-and-swap already orders the reads that follow.
 *     On AArch64 they can be hoisted above it.
 *
 * So the lock here is not `lock cmpxchg` written in another notation. It is
 * LDAXR/STXR (load-acquire exclusive, store exclusive) to take, and STLR
 * (store-release) to give. The acquire and the release are the barriers,
 * built into the access rather than standing next to it -- which is the
 * shape AArch64 wants and is cheaper than a `dmb` on either side.
 *
 * `pause` becomes `wfe`/`sev`: a waiting processor really sleeps until
 * something writes, instead of spinning warm.
 */

    .text

/* atomic_cas(x0 = address, x1 = expected, x2 = wanted) -> x0 = the old value.
 * The caller compares the result with `expected` to learn whether it won,
 * which is the same contract `atomic.fi` has on x86. */
    .globl atomic_cas
atomic_cas:
1:  ldaxr   x3, [x0]
    cmp     x3, x1
    b.ne    2f
    stlxr   w4, x2, [x0]
    cbnz    w4, 1b                          /* the reservation was lost    */
2:  clrex
    mov     x0, x3
    ret

/* atomic_add(x0 = address, x1 = delta) -> x0 = the value BEFORE the add,
 * the same return as `lock xadd` gives on x86. */
    .globl atomic_add
atomic_add:
1:  ldaxr   x2, [x0]
    add     x3, x2, x1
    stlxr   w4, x3, [x0]
    cbnz    w4, 1b
    mov     x0, x2
    ret

/* atomic_load(x0 = address) -> x0. Load-acquire: nothing after it may be
 * hoisted above it. A plain LDR would be atomic and still wrong. */
    .globl atomic_load
atomic_load:
    ldar    x0, [x0]
    ret

/* atomic_store(x0 = address, x1 = value). Store-release: everything before
 * it is visible before it is. */
    .globl atomic_store
atomic_store:
    stlr    x1, [x0]
    ret

/* barrier -- a full one, in both directions, for the whole shareable
 * domain. `mfence` is the x86 name. */
    .globl barrier
barrier:
    dmb     sy
    ret

/* barrier_device -- what has to stand between filling a descriptor in
 * memory and ringing a device's doorbell. `dsb` and not `dmb`: the write
 * must have COMPLETED, not merely be ordered, before the device is told to
 * go looking for it. This is the barrier `nvme.fi` and `virtio.fi` do not
 * have and do not need on x86, and the bug it prevents is a device reading
 * a descriptor that is still in a store buffer. */
    .globl barrier_device
barrier_device:
    dsb     sy
    ret

/* ---------------------------------------------------------------- the lock */

/* lock_take(x0 = address of a 64-bit word, x1 = the owner's number) */
    .globl lock_take
lock_take:
    mov     x2, x1
1:  ldaxr   x3, [x0]
    cbnz    x3, 2f                          /* held: go and wait           */
    stxr    w4, x2, [x0]
    cbnz    w4, 1b
    ret
2:  clrex
    wfe                                     /* sleep until someone sends   */
    b       1b

/* lock_try(x0, x1) -> x0 = 1 if taken, 0 if it was already held */
    .globl lock_try
lock_try:
    ldaxr   x2, [x0]
    cbnz    x2, 2f
    stxr    w3, x1, [x0]
    cbnz    w3, 2f
    mov     x0, #1
    ret
2:  clrex
    mov     x0, #0
    ret

/* lock_give(x0 = address) -- store-release plus a wake-up for the waiters. */
    .globl lock_give
lock_give:
    stlr    xzr, [x0]
    dsb     ishst
    sev
    ret

/* cpu_relax -- what goes in a spin loop that is NOT holding a lock. */
    .globl cpu_relax
cpu_relax:
    yield
    ret
