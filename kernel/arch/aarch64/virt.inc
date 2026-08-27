/* kernel/arch/aarch64/virt.inc -- the addresses of `qemu-system-aarch64 -M virt`.
 *
 * NOT taken from a manual and NOT guessed. Every number below was read out
 * of the device tree that QEMU itself writes:
 *
 *     qemu-system-aarch64 -machine virt,dumpdtb=virt.dtb -cpu cortex-a53
 *     ./tools/arm/dtb.py virt.dtb
 *
 * and the tool that reads it is checked in next to this file, so the claim
 * can be repeated instead of believed.
 *
 * Round ARM (2026-08-27), QEMU 8.x, `-M virt` without `virtualization=on`:
 *
 *   /memory@40000000     reg   0x40000000  0x08000000     RAM, 128 MiB
 *   /pl011@9000000       reg   0x09000000  0x1000         the serial console
 *                        interrupts  0 1 4                SPI 1 -> INTID 33
 *   /intc@8000000        reg   0x08000000  0x10000        GICv2 distributor
 *                              0x08010000  0x10000        GICv2 CPU interface
 *                        compatible  arm,cortex-a15-gic
 *   /virtio_mmio@a000000 reg   0x0a000000  0x200          32 slots, 0x200 apart
 *                        interrupts  0 16 1 .. 0 47 1     SPI 16.. -> INTID 48..
 *   /timer               interrupts  1 11 260             PPI 11 -> INTID 27
 *                                                         (the VIRTUAL timer)
 *
 * WHY THE VIRTUAL TIMER AND NOT THE PHYSICAL ONE. The physical timer of the
 * architecture is reachable from EL1 only if EL2 lets it through
 * (CNTHCTL_EL2.EL1PCTEN/EL1PCEN). On a machine without EL2 that is moot, on
 * one with EL2 it is a trap waiting to happen. CNTV_* is readable and
 * writable at EL1 in both cases, and with CNTVOFF_EL2 = 0 it counts the same
 * ticks. So the timer of this port is the virtual one, INTID 27.
 *
 * THE I/O PORTS ARE GONE. There is no `in`/`out` here and no port number.
 * Everything below is an ADDRESS, and every access to it has to be ordered
 * by hand -- see `dev_read32`/`dev_write32` in `arch.fi` and the section
 * "the weak memory model" in docs/ARCH.md.
 */

    /* --- memory ------------------------------------------------------- */
    .set RAM_BASE,      0x40000000
    .set RAM_SIZE,      0x08000000
    .set LOAD_ADDR,     0x40080000      /* where virt.ld puts the image  */

    /* --- PL011, the serial console ------------------------------------ */
    .set UART0,         0x09000000
    .set UART_DR,       0x000           /* data                          */
    .set UART_FR,       0x018           /* flags: bit 5 = transmit full  */
    .set UART_IBRD,     0x024
    .set UART_FBRD,     0x028
    .set UART_LCRH,     0x02C
    .set UART_CR,       0x030
    .set UART_IMSC,     0x038
    .set UART_ICR,      0x044
    .set UART_FR_TXFF,  (1 << 5)
    .set UART_INTID,    33              /* SPI 1                         */

    /* --- GICv2 -------------------------------------------------------- */
    .set GICD,          0x08000000
    .set GICD_CTLR,     0x000
    .set GICD_TYPER,    0x004
    .set GICD_ISENABLER,0x100
    .set GICD_ICENABLER,0x180
    .set GICD_IPRIORITY,0x400
    .set GICD_ITARGETSR,0x800
    .set GICD_ICFGR,    0xC00

    .set GICC,          0x08010000
    .set GICC_CTLR,     0x000
    .set GICC_PMR,      0x004
    .set GICC_IAR,      0x00C
    .set GICC_EOIR,     0x010

    /* --- the generic timer -------------------------------------------- */
    .set TIMER_INTID,   27              /* PPI 11, the virtual timer     */

    /* --- virtio over MMIO (not over PCI, as on the PC) ----------------- */
    .set VIRTIO_MMIO,   0x0a000000
    .set VIRTIO_STRIDE, 0x200
    .set VIRTIO_SLOTS,  32
    .set VIRTIO_INTID0, 48              /* SPI 16                        */

    /* --- PSCI: how this machine is switched off ----------------------- */
    .set PSCI_SYSTEM_OFF, 0x84000008
