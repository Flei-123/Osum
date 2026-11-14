.intel_syntax noprefix

.section .vdsodata,"a",@progbits
vdso_data:
.fill 8,8,0

.set SEQ, vdso_data
.set KHZ, vdso_data + 8
.set TSC0, vdso_data + 16
.set REAL_BASE, vdso_data + 24
.set REAL_OK, vdso_data + 32
.set MULT, vdso_data + 40

.macro split_ns
    mov rcx,rax
    shr rax,9
    movabs rdx,19342813113834067
    mul rdx
    shr rdx,11
    mov rax,rdx
    imul rdx,rdx,1000000000
    sub rcx,rdx
    mov rdx,rcx
.endm

.text

.type vdso_calc,@function
vdso_calc:
.Lretry:
    mov r8,[rip+SEQ]
    test r8d,1
    jnz .Lspin
    mov r9,[rip+MULT]
    test r9,r9
    jz .Lfail
    mov r10,[rip+TSC0]
    mov r11,[rip+REAL_BASE]
    mov rcx,[rip+REAL_OK]
    lfence
    rdtsc
    shl rdx,32
    or rax,rdx
    sub rax,r10
    mul r9
    mov rax,rdx
    cmp r8,[rip+SEQ]
    jne .Lretry
    test edi,edi
    jz .Ldone
    test rcx,rcx
    jz .Lfail
    add rax,r11
.Ldone:
    ret
.Lspin:
    pause
    jmp .Lretry
.Lfail:
    mov rax,-1
    ret

.globl __vdso_clock_gettime
.type __vdso_clock_gettime,@function
__vdso_clock_gettime:
    cmp rdi,7
    ja .Lcgt_syscall
    mov eax,0xF3
    bt eax,edi
    jnc .Lcgt_syscall
    push rdi
    xor eax,eax
    cmp rdi,0
    je .Lcgt_real
    cmp rdi,5
    jne .Lcgt_calc
.Lcgt_real:
    mov eax,1
.Lcgt_calc:
    mov edi,eax
    call vdso_calc
    pop rdi
    cmp rax,-1
    je .Lcgt_syscall
    split_ns
    mov [rsi],rax
    mov [rsi+8],rdx
    xor eax,eax
    ret
.Lcgt_syscall:
    mov eax,228
    syscall
    ret

.globl __vdso_gettimeofday
.type __vdso_gettimeofday,@function
__vdso_gettimeofday:
    push rdi
    mov edi,1
    call vdso_calc
    pop rdi
    cmp rax,-1
    je .Lgtod_syscall
    test rdi,rdi
    jz .Lgtod_zero
    split_ns
    mov [rdi],rax
    mov rax,rdx
    shr rax,3
    movabs rcx,2361183241434822607
    mul rcx
    shr rdx,4
    mov [rdi+8],rdx
.Lgtod_zero:
    xor eax,eax
    ret
.Lgtod_syscall:
    mov eax,96
    syscall
    ret

.globl __vdso_time
.type __vdso_time,@function
__vdso_time:
    push rdi
    mov edi,1
    call vdso_calc
    pop rdi
    cmp rax,-1
    je .Ltime_syscall
    split_ns
    test rdi,rdi
    jz .Ltime_ret
    mov [rdi],rax
.Ltime_ret:
    ret
.Ltime_syscall:
    mov eax,201
    syscall
    ret

.weak clock_gettime
.set clock_gettime, __vdso_clock_gettime
.weak gettimeofday
.set gettimeofday, __vdso_gettimeofday
.weak time
.set time, __vdso_time
