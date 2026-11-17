#include "test.h"
    la a0, data
    li a1, 23
    sw a1, 0(a0)
    li gp, 3
    # Atomics must trap rather than reuse the ordinary byte-split engine.
    addi a0, a0, 1
    FAULT_LR 4
    FAULT_STORE sc.w, 6
    FAULT_STORE amoadd.w, 6
    addi a0, a0, 1
    FAULT_LR 4
    FAULT_STORE amoswap.w, 6
    li gp, 4
    # The testbench exposes atomics only in its real RAM PMA region.
    li a0, 0x90000000
    FAULT_LR 5
    FAULT_STORE sc.w, 7
    FAULT_STORE amoadd.w, 7
    li gp, 5
    # A locked read-only PMP word permits LR, denies SC/AMO including failed SC.
    la a0, data
    srli t0, a0, 2
    csrw pmpaddr0, t0
    li t0, 0x91
    csrw pmpcfg0, t0
    FAULT_STORE sc.w, 7
    FAULT_STORE amoadd.w, 7
    lr.w a2, (a0)
    EQ a2, 23
    FAULT_STORE sc.w, 7
    lw a2, 0(a0)
    EQ a2, 23
    li gp, 6
    # Reserved funct5, LR with nonzero rs2, and RV64-only width are illegal.
    li s10, 2
    li s11, 0xfeb526af
    addi s8, s8, 1
    .word 0xfeb526af
    li s11, 0x10b526af
    addi s8, s8, 1
    .word 0x10b526af
    li s11, 0x00b536af
    addi s8, s8, 1
    .word 0x00b536af
    END_TEST
.balign 4
data: .word 0
