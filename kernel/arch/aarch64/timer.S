/* kernel/arch/aarch64/timer.S -- the generic timer, and what it saves.
 *
 * `kernel/idt.fi` programs an 8254: three port writes to set a divisor of a
 * fixed 1.193182 MHz, and the kernel then COUNTS ticks to know what time it
 * is. `kernel/time.fi` reads the cycle counter with `rdtsc` and has to
 * calibrate it against that same 8254, because nothing tells it how fast
 * the processor runs.
 *
 * AArch64 hands over both for free. CNTFRQ_EL0 states the frequency of the
 * counter in hertz -- on `-M virt` it reads 62500000 -- and CNTVCT_EL0 is a
 * monotone 64-bit count at exactly that rate. There is nothing to
 * calibrate, and the same two registers exist on every AArch64 machine from
 * a Raspberry Pi to a phone. So `time.fi` loses its whole calibration
 * routine on this side, and the port GAINS something over the original.
 *
 * The comparator is set as a COUNTDOWN (CNTV_TVAL_EL0 = how many ticks from
 * now) rather than as an absolute deadline, which is the one thing that
 * differs from the usual Linux arrangement; for a fixed period tick the
 * countdown form is one instruction and cannot drift more than the handler
 * latency, which is what a 100 Hz tick wants.
 *
 * WHY THE VIRTUAL TIMER: see virt.inc. CNTV_* is readable at EL1 whether or
 * not EL2 exists, INTID 27.
 */

#include "virt.inc"

    .text

/* timer_freq -> x0 = ticks per second, as the machine states it. */
    .globl timer_freq
timer_freq:
    mrs     x0, cntfrq_el0
    ret

/* timer_count -> x0 = the monotone counter. */
    .globl timer_count
timer_count:
    isb                                     /* the read may be speculated  */
    mrs     x0, cntvct_el0
    ret

/* timer_arm(x0 = ticks from now) -- sets the comparator and enables it. */
    .globl timer_arm
timer_arm:
    msr     cntv_tval_el0, x0
    mov     x1, #1                          /* ENABLE, IMASK clear         */
    msr     cntv_ctl_el0, x1
    isb
    ret

/* timer_off */
    .globl timer_off
timer_off:
    msr     cntv_ctl_el0, xzr
    isb
    ret

/* timer_period_hz(w0 = wanted frequency) -> x0 = the tick count for it. */
    .globl timer_period_hz
timer_period_hz:
    mrs     x1, cntfrq_el0
    udiv    x0, x1, x0
    ret
