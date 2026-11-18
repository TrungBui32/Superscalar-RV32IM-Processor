#include "test.h"
    la a0, data
    li a1, 23
    sw a1, 0(a0)
    li gp, 3
    lr.w x0, (a0)
    li a1, 24
    sc.w a2, a1, (a0)
    EQ a2, 0
    lw a2, 0(a0)
    EQ a2, 24
    sc.w a2, a1, (a0)
    EQ a2, 1
    li gp, 4
    # rd==rs2 must store the original operand and return old memory.
    li a1, 25
    amoswap.w a1, a1, (a0)
    EQ a1, 24
    lw a2, 0(a0)
    EQ a2, 25
    # rd==rs1 must still write to the original address.
    li a1, 1
    amoadd.w a0, a1, (a0)
    EQ a0, 25
    la a0, data
    lw a2, 0(a0)
    EQ a2, 26
    li gp, 5
    lr.w a2, (a0)
    li a1, 27
    sc.w a1, a1, (a0)
    EQ a1, 0
    lw a2, 0(a0)
    EQ a2, 27
    lr.w a2, (a0)
    li a1, 28
    sc.w a0, a1, (a0)
    EQ a0, 0
    la a0, data
    lw a2, 0(a0)
    EQ a2, 28
    li gp, 6
    # A taken branch between LR and SC must not destroy forward progress.
    lr.w a2, (a0)
    beq x0, x0, branch_target
    sw x0, 0(a0)
branch_target:
    li a1, 29
    sc.w a2, a1, (a0)
    EQ a2, 0
    # Two consecutive stores, including a byte store, invalidate reservation.
    lr.w a2, (a0)
    sb x0, 1(a0)
    sw x0, 4(a0)
    sc.w a2, a1, (a0)
    EQ a2, 1
    li gp, 7
    lr.w a2, (a0)
    addi a4, a0, 4
    lr.w a2, (a4)
    sc.w a2, a1, (a0)
    EQ a2, 1
    sc.w a2, a1, (a4)
    EQ a2, 1
    # Wrong-path atomics must never update memory or establish a reservation.
    li a1, 99
    beq x0, x0, skip_amo
    amoswap.w a2, a1, (a0)
skip_amo:
    lw a2, 0(a0)
    EQ a2, 29
    sc.w a2, a1, (a0)
    EQ a2, 1
    # A normal store through a backing-RAM alias must invalidate reservation.
    lr.w a2, (a0)
    li a4, 0x40000
    add a4, a0, a4
    sw a1, 0(a4)
    sc.w a2, a1, (a0)
    EQ a2, 1
    lw a2, 0(a0)
    EQ a2, 99
    li gp, 8
    # aq/rl encodings and x0 destination still update memory.
    amoadd.w.aq x0, a1, (a0)
    amoadd.w.rl x0, a1, (a0)
    amoadd.w.aqrl x0, a1, (a0)
    lw a2, 0(a0)
    EQ a2, 396
    csrr a2, misa
    EQ a2, 0x40141101
    END_TEST
.balign 4
data: .word 0,0
