.option norvc
.option norelax
.section .text.init
.globl _start
_start:
    la t0, handler
    csrw mtvec, t0
    li t0, 128
    csrw mie, t0
    csrsi mstatus, 8
    li s0, 0
    li s1, 0
    li gp, 2
    la a0, data
    li a1, 3
    amoadd.w.aqrl a2, a1, (a0)
    li t0, 10
    bne a2, t0, fail
    addi s0, s0, 1
    # Also exercise an atomic in the handler and resumed dependent operations.
    lw a2, 0(a0)
    li t0, 15
    bne a2, t0, fail
    li t0, 1
    bne s0, t0, fail
    bne s1, t0, fail
    la t1, tohost
    sw t0, 0(t1)
1:  j 1b
handler:
    csrr t5, mcause
    li t6, 0x80000007
    bne t5, t6, fail
    li t6, 2
    amoadd.w t5, t6, (a0)
    li t6, 13
    bne t5, t6, fail
    addi s1, s1, 1
    mret
fail:
    li t0, 5
    la t1, tohost
    sw t0, 0(t1)
2:  j 2b
.section .tohost,"aw",@progbits
.balign 8
.globl tohost
tohost: .dword 0
.section .data
.balign 4
data: .word 10
