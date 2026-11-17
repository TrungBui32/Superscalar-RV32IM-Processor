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
    li a1, 99
    lr.w.aq a2, (a0)
    li t0, 10
    bne a2, t0, fail
    # The interrupt handler performs an LR itself. Its reservation must not
    # leak across mret into the interrupted instruction stream.
    sc.w.rl a3, a1, (a0)
    li t0, 1
    bne a3, t0, fail
    bne s1, t0, fail
    lw a2, 0(a0)
    li t0, 10
    bne a2, t0, fail
    lr.w a2, (a0)
    addi a2, a2, 1
    sc.w a3, a2, (a0)
    bnez a3, fail
    lw a2, 0(a0)
    li t0, 11
    bne a2, t0, fail
    li t0, 1
    la t1, tohost
    sw t0, 0(t1)
1:  j 1b
handler:
    csrr t5, mcause
    li t6, 0x80000007
    bne t5, t6, fail
    lr.w t5, (a0)
    li t6, 10
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
