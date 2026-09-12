/* _start for Osum: Osum passes the arg block pointer in RDI (elf.fi),
 * NOT the Linux SysV stack layout. We synthesise argc/argv/envp/auxv.
 * Osum arg block:  +0 argc, +8 argv[] (NULL-term), +2048 envc, +2056 envp[] */
.section .text
.globl _start
_start:
    xor %rbp, %rbp
    mov %rdi, %r12              /* r12 = osum arg block */
    test %r12, %r12
    jz 1f
    mov (%r12), %rdi            /* argc */
    lea 8(%r12), %rsi           /* argv */
    lea 2056(%r12), %rdx        /* envp */
    jmp 2f
1:  xor %rdi, %rdi
    xor %rsi, %rsi
    xor %rdx, %rdx
2:  and $-16, %rsp
    call osum_main
    mov %rax, %rdi
    mov $231, %rax              /* exit_group */
    syscall
    hlt
