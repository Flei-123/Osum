/* kernel/arch/aarch64/mmu.S -- page tables, and what they are NOT.
 *
 * The x86-64 side of this kernel builds four levels whose entries are the
 * physical address plus a handful of bits, and switches the whole thing on
 * by writing one register (CR3) with the paging bit already set in CR0
 * since `boot.s`. AArch64 says the same thing with different words, and
 * three of the differences bite:
 *
 * 1. THERE ARE TWO TABLE BASE REGISTERS, not one. TTBR0_EL1 translates
 *    addresses whose top bits are zero, TTBR1_EL1 those whose top bits are
 *    one. A process and the kernel can therefore live in one address space
 *    without either one being able to name the other's pages -- and,
 *    unlike on x86, WITHOUT the kernel's half being copied into every page
 *    table. This file sets up both: TTBR0 identity maps the machine, TTBR1
 *    maps the same RAM once more at the top of the address space, and
 *    `probe.S` reads one octet through both and compares. That comparison
 *    is the whole proof that TTBR1 is doing anything.
 *
 * 2. THE MEMORY ATTRIBUTE IS AN INDEX, not bits. A descriptor carries three
 *    bits that select one of eight bytes in MAIR_EL1. Which is why the
 *    UART, the GIC and the RAM can share one descriptor format and still be
 *    device memory and normal memory: attr 0 = Normal write-back,
 *    attr 1 = Device-nGnRnE, attr 2 = Device-nGnRE.
 *
 * 3. THE ACCESS FLAG IS NOT OPTIONAL. Bit 10 (AF) clear means "this page
 *    has never been touched", and the hardware takes an ACCESS FLAG FAULT
 *    the first time it is used. A descriptor that looks right in every
 *    other way and has AF clear produces a data abort with ESR 0b0010xx,
 *    and the address in FAR_EL1 looks perfectly mapped. Every descriptor
 *    below therefore sets AF, and it is called out here because the x86
 *    format has no such bit and nothing reminds you.
 *
 * The geometry: 4 KiB granule, 39-bit virtual addresses (T0SZ = T1SZ = 25),
 * which starts the walk at level 1. One level-1 entry covers 1 GiB.
 *
 *   TTBR0  L1[0] -> 1 GiB block, device      0x00000000..0x3FFFFFFF
 *                   (PL011 0x09000000, GIC 0x08000000, virtio 0x0A000000)
 *          L1[1] -> 1 GiB block, normal      0x40000000..0x7FFFFFFF  (RAM)
 *          L1[2] -> table -> L2[0] -> table -> L3[0] -> ONE 4 KiB page
 *                   at 0x80000000, pointing at `test_page` in RAM.
 *                   That page is the second proof: written through the
 *                   mapping, read back through the identity address.
 *   TTBR1  L1[1] -> the same 1 GiB block of RAM, reachable at
 *                   0xFFFFFF8040000000.
 */

#include "virt.inc"

    /* descriptor bits */
    .set D_VALID,     (1 << 0)
    .set D_TABLE,     (1 << 1)      /* with D_VALID: a table, not a block */
    .set D_PAGE,      (1 << 1)      /* with D_VALID at level 3: a page    */
    .set D_ATTR_NORM, (0 << 2)      /* MAIR index 0                       */
    .set D_ATTR_DEV,  (1 << 2)      /* MAIR index 1                       */
    .set D_AP_RW_EL1, (0 << 6)
    .set D_SH_INNER,  (3 << 8)
#ifdef NO_AF
    /* The counter-check of round ARM: the access flag left clear. Every
     * other bit of every descriptor stays exactly as it is, the tables are
     * built the same way, and the first access through them takes an
     * ACCESS FLAG FAULT. If a build with this switch still passes the page
     * proof, the page proof is not proving a translation. */
    .set D_AF,        0
#else
    .set D_AF,        (1 << 10)
#endif
    .set D_PXN,       (1 << 53)
    .set D_UXN,       (1 << 54)

    .set BLK_DEV,   (D_VALID | D_ATTR_DEV  | D_AP_RW_EL1 | D_AF | D_PXN | D_UXN)
    .set BLK_NORM,  (D_VALID | D_ATTR_NORM | D_AP_RW_EL1 | D_SH_INNER | D_AF | D_UXN)
    .set TBL_DESC,  (D_VALID | D_TABLE)
    .set PAGE_NORM, (D_VALID | D_PAGE | D_ATTR_NORM | D_AP_RW_EL1 | D_SH_INNER | D_AF | D_UXN)

    /* MAIR_EL1: attr0 Normal WB RW-allocate, attr1 Device-nGnRnE,
     *           attr2 Device-nGnRE. */
    /* byte 0 = attr0 = 0xFF, byte 1 = attr1 = 0x00, byte 2 = attr2 = 0x04 */
    .set MAIR_EL1_VAL, 0x00000000000400FF

    /* TCR_EL1:
     *   T0SZ  = 25   bits 0..5     39-bit VA under TTBR0
     *   IRGN0 = 1    bits 8..9     inner write-back write-allocate
     *   ORGN0 = 1    bits 10..11   outer write-back write-allocate
     *   SH0   = 3    bits 12..13   inner shareable
     *   TG0   = 0    bits 14..15   4 KiB granule
     *   T1SZ  = 25   bits 16..21   39-bit VA under TTBR1
     *   IRGN1 = 1    bits 24..25
     *   ORGN1 = 1    bits 26..27
     *   SH1   = 3    bits 28..29
     *   TG1   = 2    bits 30..31   4 KiB granule (the encoding DIFFERS
     *                              from TG0's -- 2 here, 0 there. A single
     *                              digit, and a wrong one gives a
     *                              translation fault on the first high
     *                              address with no other symptom.)
     *   IPS   = 2    bits 32..34   40-bit physical addresses
     */
    .set TCR_EL1_VAL, (25) | (1 << 8) | (1 << 10) | (3 << 12) | (0 << 14) \
                    | (25 << 16) | (1 << 24) | (1 << 26) | (3 << 28) | (2 << 30) \
                    | (2 << 32)

    .text

/* mmu_init -- build the tables and switch translation on.
 * Returns nothing. From here on every address goes through a descriptor. */
    .globl mmu_init
mmu_init:
    stp     x29, x30, [sp, #-16]!

    /* --- the tables start empty. `.pagetables` is NOLOAD; nothing in the
     * ELF zeroes it and `start.S` only clears `.bss`. */
    adrp    x0, __pt_start
    add     x0, x0, :lo12:__pt_start
    adrp    x1, __pt_end
    add     x1, x1, :lo12:__pt_end
1:  cmp     x0, x1
    b.hs    2f
    str     xzr, [x0], #8
    b       1b
2:

    /* --- TTBR0 L1[0]: the first gigabyte as device memory. */
    adrp    x0, pt_l1_lo
    add     x0, x0, :lo12:pt_l1_lo
    ldr     x2, =BLK_DEV
    str     x2, [x0, #0]                    /* PA 0x00000000 | attrs */

    /* --- TTBR0 L1[1]: the RAM gigabyte as normal memory. */
    ldr     x2, =(RAM_BASE | BLK_NORM)
    str     x2, [x0, #8]

    /* --- TTBR0 L1[2] -> L2, L2[0] -> L3, L3[0] -> test_page. */
    adrp    x3, pt_l2
    add     x3, x3, :lo12:pt_l2
    orr     x2, x3, #TBL_DESC
    str     x2, [x0, #16]

    adrp    x4, pt_l3
    add     x4, x4, :lo12:pt_l3
    orr     x2, x4, #TBL_DESC
    str     x2, [x3, #0]

    adrp    x5, test_page
    add     x5, x5, :lo12:test_page
    ldr     x6, =PAGE_NORM
    orr     x2, x5, x6
    str     x2, [x4, #0]

    /* --- TTBR1 L1[1]: the same RAM once more, at the top of the space. */
    adrp    x1, pt_l1_hi
    add     x1, x1, :lo12:pt_l1_hi
    ldr     x2, =(RAM_BASE | BLK_NORM)
    str     x2, [x1, #8]

    /* --- the tables have to be VISIBLE TO THE TABLE WALKER before they are
     * used. The walker is not the load/store unit; on a machine with a weak
     * memory model the stores above may still be in a buffer. `dsb ishst`
     * is the sentence "everything I stored is now visible in the inner
     * shareable domain", and without it the first walk can read zeroes out
     * of a table that the code just filled. There is no x86 counterpart:
     * writing CR3 there is itself the ordering point. */
    dsb     ishst

    ldr     x2, =MAIR_EL1_VAL
    msr     mair_el1, x2
    ldr     x2, =TCR_EL1_VAL
    msr     tcr_el1, x2
    msr     ttbr0_el1, x0
    msr     ttbr1_el1, x1
    isb

    tlbi    vmalle1
    dsb     ish
    isb

    mrs     x2, sctlr_el1
    orr     x2, x2, #(1 << 0)               /* M: translation on          */
    orr     x2, x2, #(1 << 2)               /* C: data cache on           */
    orr     x2, x2, #(1 << 12)              /* I: instruction cache on    */
    msr     sctlr_el1, x2
    isb

    ldp     x29, x30, [sp], #16
    ret

/* mmu_is_on -> x0 = 1 if SCTLR_EL1.M is set. Read out of the machine, not
 * remembered in a variable -- a variable would only prove that this file
 * ran, not that the processor agreed. */
    .globl mmu_is_on
mmu_is_on:
    mrs     x0, sctlr_el1
    and     x0, x0, #1
    ret

/* mmu_test_va -> x0 = the virtual address of the one page mapped by hand. */
    .globl mmu_test_va
mmu_test_va:
    mov     x0, #0
    movk    x0, #0x8000, lsl #16
    ret

/* mmu_high_va(x0 = a physical address in RAM) -> x0 = the address of the same
 * octet under TTBR1. The 39-bit high half starts at 0xFFFFFF8000000000; the
 * identity map under TTBR0 is 1:1, so the offset carries straight over. */
    .globl mmu_high_va
mmu_high_va:
    movz    x1, #0xFFFF, lsl #48
    movk    x1, #0xFF80, lsl #32
    orr     x0, x0, x1
    ret

/* ------------------------------------------------------------- the tables */

    .section .pagetables, "aw", %nobits
    .balign 4096
    .globl pt_l1_lo
pt_l1_lo:   .space 4096
    .globl pt_l1_hi
pt_l1_hi:   .space 4096
    .globl pt_l2
pt_l2:      .space 4096
    .globl pt_l3
pt_l3:      .space 4096
    .globl test_page
test_page:  .space 4096
