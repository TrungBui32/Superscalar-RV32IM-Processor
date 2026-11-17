.option norvc
.option norelax
.section .text.init
.globl _start
_start:
    la t0, trap_handler
    csrw mtvec, t0
    li gp, 2
    li s8, 0
    li s9, 0
.macro EQ reg, value
    li t0, \value
    bne \reg, t0, fail
.endm
.macro EXPECT cause, address
    li s10, \cause
    mv s11, \address
    addi s8, s8, 1
    li a3, 0x5eed
.endm
.macro FAULT_LR cause
    EXPECT \cause, a0
    lr.w a3, (a0)
    EQ a3, 0x5eed
.endm
.macro FAULT_STORE insn, cause
    EXPECT \cause, a0
    \insn a3, a1, (a0)
    EQ a3, 0x5eed
.endm
.macro END_TEST
    bne s8, s9, fail
pass:
    li t0, 1
    la t1, tohost
    sw t0, 0(t1)
1:  j 1b
fail:
    slli t0, gp, 1
    ori t0, t0, 1
    la t1, tohost
    sw t0, 0(t1)
2:  j 2b
.balign 4
trap_handler:
    csrr t5, mcause
    bne t5, s10, fail
    csrr t5, mtval
    bne t5, s11, fail
    addi s9, s9, 1
    csrr t5, mepc
    addi t5, t5, 4
    csrw mepc, t5
    mret
.section .tohost,"aw",@progbits
.balign 8
.globl tohost
tohost: .dword 0
.section .data
.endm
